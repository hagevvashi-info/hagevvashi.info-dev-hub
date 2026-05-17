---
status: resolved
date: 2026-05-17
source: "cmd/worker/main.go、internal/platform/queue_platform.go、internal/bridge/bridge.go のコード審査"
---

# キューメッセージフロー仕様書

## 概要

このドキュメントは、Slack からのメッセージが go-tty-from-queue システムを通ってエージェント回答を生成し、Slack に戻されるまでのフローを仕様化します。

## 質問 1：システムはチャネル X のポストをエージェントに渡すか？

**答え：はい**

**ソースコード検証：**

```go
// cmd/worker/main.go
messages, err := plat.FetchNewMessages()  // ← キューから pending メッセージを取得
```

```go
// internal/platform/queue_platform.go - FetchNewMessages()
for _, entry := range entries {
    if entry.Status != "pending" {
        continue
    }
    // チャネル、ユーザー、コンテンツにフィルタリングなし
    msg := message.Message{
        ID:        entry.MessageTS,
        AgentType: entry.AgentType,
        Content:   entry.Text,
        // ... 
    }
    messages = append(messages, msg)
}
```

**動作：**
- `Status == "pending"` のすべてのエントリが取得される
- 追加フィルタリングは適用されない
- メッセージはスレッド単位でグループ化され、エージェント実行に渡される

**フロー：**
```
Slack チャネル X
    ↓
GAS（Google Apps Script）
    ↓
Google Sheets キュー
    ↓
go-tty-from-queue FetchNewMessages()
    ↓
エージェントにバッチ化（スレッド単位）
    ↓
エージェント実行（Claude/Gemini）
```

---

## 質問 2：システムはエージェント回答をチャネル X にユーザー Y で投稿するか？

**答え：はい**

**ソースコード検証：**

```go
// cmd/worker/main.go
result, sessionID, _ := brg.Execute(msg, sess, created)
brg.Platform.PostResponse(msg, result)  // ← レスポンスをポスト
```

```go
// internal/platform/queue_platform.go - PostResponse()
func (p *QueuePlatform) PostResponse(original message.Message, response string) error {
    fmt.Printf("📢 [Queue Post] channel: %s ID: %s (thread_ts: %s) への返信:\n%s\n\n",
        original.ChannelID, original.ID, original.ThreadTS, response)
    return nil
}
```

**動作（ローカル vs 本番）：**

| 環境 | 実装 |
|---|---|
| **ローカル** | stdout に出力 |
| **本番** | Slack API でチャネル X のスレッド返信をユーザー Y で投稿 |

**フロー：**
```
エージェント実行（ローカル：CLI TTY、リモート：API）
    ↓
result 文字列（Claude/Gemini 回答）
    ↓
PostResponse(original_message, result)
    ↓
ローカル：stdout
本番：Slack API（ユーザー Y 認証情報で channels.reply）
    ↓
Slack チャネル X（ユーザー Y のスレッド返信）
```

---

## 質問 3：システムは Y のポストをエージェントに戻して処理するか？フィルタリングすべきか？

**答え：現状は フィルタリングなし。本来は フィルタリングすべき。**

### 現在の実装の動作

**Y のポスト処理：**

1. **ローカル実行は、キューに含まれた場合 Y のポストが処理されることを示す：**
   ```go
   // cmd/worker/main.go
   messages, err := plat.FetchNewMessages()  // ← すべての pending を取得、Y フィルタリングなし
   // ...
   result, sessionID, _ := brg.Execute(msg, sess, created)  // ← Y のポストを実行
   ```

2. **go-tty-from-queue に Y フィルタリングが存在しない：**
   ```go
   // internal/platform/queue_platform.go
   // フィルタ対象：Status == "pending" のみ
   // user_id チェックなし、Y フィルタリングなし
   ```

3. **唯一の防御：GAS がキュー作成時に Y のポストを除外**
   - GAS フィルタが動作 → OK
   - GAS フィルタが失敗 → **無限ループリスク**

### Y のポストがフィルタリングされるべき理由

**リスク：無限ループ**
```
ユーザーがチャネル X に「ヘルプ」と投稿
    ↓
GAS がキューエントリを作成
    ↓
go-tty-from-queue が実行（Claude/Gemini）
    ↓
チャネル X にユーザー Y で回答をポスト
    ↓
GAS が Y の回答を検出
    ↓
GAS が Y をフィルタしなかった場合：キューエントリを作成
    ↓
go-tty-from-queue が Y の回答を実行（再度）
    ↓
Y で別の回答をポスト
    ↓
無限ループ 🔄
```

### 現在の依存関係

```
アーキテクチャの正確性は以下に依存：
    GAS フィルタ（Y 除外）
        ↑
        └─── 失敗 → 無限ループ
```

**問題：** 単一障害点、多層防御がない。

---

## 仕様書（理想的）

### 責務マトリックス

| タスク | GAS | go-tty-from-queue | キュー |
|---|---|---|---|
| Slack のすべてのポストを含める | ✓ | - | - |
| Entry に user_id を追加 | ✓ | - | ✓ |
| Y のポストをフィルタ（最初） | ✓ | - | - |
| Y のポストをフィルタ（防御） | - | ✓ | - |
| 監査証跡を保存 | - | - | ✓ |
| 非 Y のポストを実行 | - | ✓ | - |
| X に回答をポスト | - | ✓ | - |

### 理想的なメッセージフロー（user_id 付き）

```
Slack チャネル X
    ↓
GAS：user_id を抽出、user_id 付き Entry を作成
    ↓
キュー：user_id で保存（監査証跡）
    ↓
go-tty-from-queue：pending を取得
    ├─ フィルタ：user_id == "U_AGENT_Y" → スキップ
    └─ フィルタ：その他 → 実行
    ↓
エージェント実行
    ↓
X に PostResponse で返信
    ↓
GAS：新しいポストが到着（Y より）
    ├─ GAS フィルタ：user_id == "U_AGENT_Y" → キュー対象外
    └─ go-tty-from-queue フィルタ：user_id == "U_AGENT_Y" → キューにあったらスキップ
    ↓
✅ 無限ループなし
```

---

## サマリー

| 質問 | 現在の実装 | 理想的な動作 |
|---|---|---|
| **Q1：X のポストをエージェントに渡す？** | ✓ YES（すべての pending） | ✓ YES（非 Y の pending） |
| **Q2：Y の回答を X にポスト？** | ✓ YES | ✓ YES |
| **Q3：Y のポストをフィルタ？** | ✗ NO（GAS のみ） | ✓ YES（多層） |

---

## 関連ドキュメント

- **提案される修正：** docs/proposed/QUEUE_ENTRY_SCHEMA_DESIGN.md
- **設計決定：** docs/outdated/CURRENT_ENTRY_SCHEMA.md

---

**分析日：** 2026-05-17  
**ステータス：** 完了  
**信頼度：** 高（ソース：直接コード検査）
