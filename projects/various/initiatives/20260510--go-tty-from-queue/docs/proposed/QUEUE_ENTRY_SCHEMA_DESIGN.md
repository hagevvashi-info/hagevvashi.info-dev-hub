---
status: proposed
date: 2026-05-17
author: アーキテクチャレビュー（main ブランチ保護インシデント）
---

# ユーザー ID を含むキューエントリスキーマの改善提案

## 提案

Entry 構造体に `user_id` フィールドを追加して以下を実現：
1. go-tty-from-queue 側での Y フィルタリング（多層防御）
2. 完全な監査証跡（誰が何を投稿したか）
3. 将来の拡張性（ボットフィルタリング、重複検出など）

## 提案するスキーマ

```go
type Entry struct {
    Channel   string `json:"channel"`      // Slack チャンネルID
    ThreadTS  string `json:"thread_ts"`    // スレッドトップのタイムスタンプ
    MessageTS string `json:"message_ts"`   // メッセージのタイムスタンプ
    Text      string `json:"text"`         // ポストのテキスト
    Time      string `json:"time"`         // ISO 8601 形式
    Status    string `json:"status"`       // "pending", "processing", "completed", "failed"
    AgentType string `json:"agent_type"`   // "claude" または "gemini"
    UserID    string `json:"user_id"`      // ← NEW: Slack ユーザー ID（例："U123456"）
}
```

## 根拠

### 1. 多層防御

**変更前（単一障害点）:**
```
GAS が Y を除外 → キュー作成 → go-tty-from-queue がすべて処理
↑ GAS が失敗 → 無限ループ
```

**変更後（複数防御層）:**
```
GAS が Y を除外 → キュー作成 → go-tty-from-queue が Y をフィルタ → 安全
      ↑ 最初の防御              ↑ 最終防御（失敗しない）
```

### 2. データ完全性

`user_id` があれば、キューは監査証跡になります：
- 「ユーザー U12345 が 2026-05-17T10:00:00Z に #channel-X で『ヘルプ』と投稿」
- デバッグを有効化：「このメッセージはどこからきた？」
- コンプライアンス：「誰が何をいつした？」

### 3. アーキテクチャの明確性

| 責務 | コンポーネント |
|---|---|
| 完全なメッセージデータを queue に提供 | GAS |
| Y でフィルタリング | GAS（最初の防御）+ go-tty-from-queue（最終防御） |
| 有効なメッセージを処理 | go-tty-from-queue |
| 監査証跡を保存 | キュー（user_id 経由） |

各コンポーネントに明確な単一責務があります。

### 4. 将来の拡張性

`user_id` があれば、フィルタリングルールを簡単に追加可能：

```go
func (p *QueuePlatform) FetchNewMessages() ([]message.Message, error) {
    entries, err := p.source.Read()
    
    var messages []message.Message
    for _, entry := range entries {
        if entry.Status != "pending" {
            continue
        }
        
        // Y のポストをフィルタ
        if entry.UserID == "U_AGENT_Y" {
            continue
        }
        
        // ボットをフィルタ（拡張可能）
        if strings.HasPrefix(entry.UserID, "B_") {
            continue
        }
        
        // ... 有効なメッセージを処理
    }
    return messages, nil
}
```

## 実装への影響

### GAS の変更

```javascript
// 変更前
const entry = {
    channel: event.channel,
    thread_ts: event.thread_ts,
    message_ts: event.ts,
    text: event.text,
    time: new Date().toISOString(),
    status: "pending",
    agent_type: "claude"
};

// 変更後
const entry = {
    channel: event.channel,
    thread_ts: event.thread_ts,
    message_ts: event.ts,
    text: event.text,
    time: new Date().toISOString(),
    status: "pending",
    agent_type: "claude",
    user_id: event.user  // ← これを追加
};
```

### go-tty-from-queue の変更

```go
// internal/queue/entry.go
type Entry struct {
    // ... 既存フィールド
    UserID string `json:"user_id"`  // ← これを追加
}

// internal/platform/queue_platform.go
func (p *QueuePlatform) FetchNewMessages() ([]message.Message, error) {
    // ... 既存コード
    
    for _, entry := range entries {
        if entry.Status != "pending" {
            continue
        }
        
        // ← 防御的フィルタを追加
        if entry.UserID == "U_AGENT_Y" {
            continue
        }
        
        // ... Message に変換
    }
    
    return messages, nil
}
```

## リスク評価

### 最小限のリスク
- Entry 構造体へのオプショナルフィールド追加（JSON との後方互換性あり）
- GAS は既に `event.user` にアクセス可能
- 既存インターフェースへの破壊的変更なし
- 純粋な追加（フィールド削除なし）

### マイグレーションパス
1. go-tty-from-queue をデプロイ（Y フィルタリングコード、user_id が空でも動作）
2. GAS を更新して新しいキューエントリに user_id を含める
3. user_id のない古いキューエントリ：go-tty-from-queue は非 Y として扱う
4. GAS ロールアウト後、すべてのエントリに user_id がある

## 必要な決定

| 項目 | 決定 |
|---|---|
| Entry に user_id を追加？ | YES / NO |
| go-tty-from-queue に Y フィルタリングを追加？ | YES / NO |
| GAS 更新のタイムライン？ | TBD |

---

## 関連する問題

- **現在のバグ：** GAS のみのフィルタリングで go-tty-from-queue が防御不可
- **関連決定：** docs/resolved/QUEUE_MESSAGE_FLOW_SPECIFICATION.md - システム全体の Y ポスト処理

---

**作成日：** 2026-05-17  
**ステータス：** 承認待機中  
**優先度：** 高（システムの正確性に影響）
