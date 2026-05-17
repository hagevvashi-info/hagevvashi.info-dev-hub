---
status: outdated
date: 2026-05-17
reason: "Y ポストフィルタリングと監査証跡に必要な user_id フィールドがない"
---

# 現在のキューエントリスキーマ（廃棄済み）

## 定義

```go
type Entry struct {
    Channel   string `json:"channel"`      // Slack チャンネル ID
    ThreadTS  string `json:"thread_ts"`    // スレッドトップのタイムスタンプ
    MessageTS string `json:"message_ts"`   // メッセージのタイムスタンプ
    Text      string `json:"text"`         // ポストのテキスト
    Time      string `json:"time"`         // ISO 8601 形式
    Status    string `json:"status"`       // "pending", "processing", "completed", "failed"
    AgentType string `json:"agent_type"`   // "claude" または "gemini"
}
```

## 現在のスキーマの問題

### 1. ユーザー情報がない

**問題：** user_id フィールドがないため：
- go-tty-from-queue が Y のポストを特定できない
- 監査証跡が不完全（誰が何を投稿したかが見えない）
- go-tty-from-queue 側での防御的フィルタリングが実装できない

**現在の回避策：**
- GAS がキュー作成時に Y のポストを除外
- GAS フィルタが失敗すると無限ループリスク

### 2. 責務の曖昧性

| コンポーネント | 責務 |
|---|---|
| GAS | Y のポストをキューから除外 |
| go-tty-from-queue | すべての pending メッセージを処理 |

**問題：** 多層防御がない。GAS が失敗 = 無限ループ。

### 3. 将来の拡張性が限定的

以下のようなルールを簡単には実装できない：
- ボットのポストをフィルタ
- 管理者の手動ポストをフィルタ
- 重複ポストをフィルタ
- 「誰が何を言ったか」を監査

## 歴史的背景

- データ転送を削減するための最小限スキーマとして作成
- GAS が正しくフィルタすると信頼
- 多層防御は計画されていなかった

## 後継ドキュメント

改善設計については `proposed/QUEUE_ENTRY_SCHEMA_DESIGN.md` を参照してください。

---

**作成日：** 2026-05-16  
**廃棄日：** 2026-05-17  
**理由：** スキーマ拡張が必要な設計ギャップを特定
