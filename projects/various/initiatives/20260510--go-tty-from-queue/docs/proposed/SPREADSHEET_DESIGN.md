---
status: proposed
date: 2026-05-17
author: アーキテクチャレビュー
---

# Google Sheets キューストレージ設計

## 概要

QUEUE_ENTRY_SCHEMA_DESIGN.md で accepted となった 8 フィールドを Google Sheets に格納する際の設計仕様。

## スプレッドシート構造

### 列定義

| 列 | ヘッダ | 型 | Slack API | 例 |
|------|--------|------|-----------|-----|
| A | channel | String | `channel` | `C024BE7LH` |
| B | thread_ts | String | `thread_ts` | `1715161200.000100` |
| C | message_ts | String | `ts` | `1715161200.000100` |
| D | text | String | `text` | `ファイル一覧を教えて` |
| E | user_id | String | `user` | `U024BE7LH` |
| F | time | String | 生成 | `2026-05-17T10:20:40.001Z` |
| G | status | String | キュー固有 | `pending` |
| H | agent_type | String | キュー固有 | `claude` |

### 行1: ヘッダ

```
channel | thread_ts | message_ts | text | user_id | time | status | agent_type
```

### 行2以降: データ

```
C024BE7LH | 1715161200.000100 | 1715161200.000100 | ファイル一覧を教えて | U024BE7LH | 2026-05-17T10:20:40.001Z | pending | claude
```

## データ型と制約

| フィールド | 型 | 制約 | 備考 |
|-----------|------|------|------|
| channel | String | C + 11-13文字 | Slack チャネルID |
| thread_ts | String | epoch.microseconds | スレッドトップのタイムスタンプ |
| message_ts | String | epoch.microseconds | メッセージのタイムスタンプ |
| text | String | UTF-8、任意長 | ユーザー質問・リクエスト |
| user_id | String | U/W/B + 11-13文字 | Slack ユーザーID |
| time | String | ISO 8601 | GAS が生成（現在時刻） |
| status | String | pending / processing / completed / failed | ライフサイクル |
| agent_type | String | claude / gemini | エージェント選択 |

## ライフサイクル

```
【初期状態】
GAS が Slack イベント受信 → キューに行を append
  ↓ status = "pending"

【処理中】
go-tty-from-queue が行を検出 → status を "processing" に変更
  ↓ エージェント実行

【完了】
エージェント実行完了 → status を "completed" に変更
  ↓ Slack に回答投稿

【失敗】
エラー発生 → status を "failed" に変更
  ↓ ログに記録
```

## サンプルスプレッドシート

### ヘッダ行

| A | B | C | D | E | F | G | H |
|---|---|---|---|---|---|---|---|
| channel | thread_ts | message_ts | text | user_id | time | status | agent_type |

### データ行（例1：pending）

| C024BE7LH | 1715161200.000100 | 1715161200.000100 | ファイル一覧を教えて | U024BE7LH | 2026-05-17T10:20:40.001Z | pending | claude |

### データ行（例2：completed）

| C0LDKJ9RZ | 1715161500.000100 | 1715161500.000100 | テキストファイルを列挙 | W024BE7LH | 2026-05-17T10:21:00.002Z | completed | gemini |

### データ行（例3：failed）

| C024BE7LH | 1715161200.000100 | 1715161600.000100 | プロセス一覧を表示 | U024BE7LH | 2026-05-17T10:22:15.500Z | failed | claude |

## GAS 側の実装（append）

```javascript
function appendQueueEntry(event) {
  const agentUserID = "U0K4HRSJ2";  // Agent Y
  
  // フィルタ 1（GAS 側）
  if (event.user === agentUserID) {
    return;
  }
  
  const sheet = SpreadsheetApp.getActiveSheet();
  const row = [
    event.channel,                      // A
    event.thread_ts || event.ts,        // B
    event.ts,                           // C
    event.text,                         // D
    event.user,                         // E
    new Date().toISOString(),           // F
    "pending",                          // G
    selectAgent(event)                  // H
  ];
  
  sheet.appendRow(row);
}
```

## go-tty-from-queue 側の実装（Read/Write）

### Read(): pending 行を取得

```go
func (s *Sheets) Read() ([]Entry, error) {
  // Google Sheets API で A:H 列を取得
  // ヘッダ行（行1）をスキップ
  // status == "pending" の行のみ返す
  
  return entries, nil
}
```

### Write(): status を更新

```go
func (s *Sheets) Write(entries []Entry) error {
  // Google Sheets API で各行の status 列（G）を更新
  // message_ts をキーに該当行を検索
  
  return nil
}
```

## Google Sheets API との連携

### 認証

- **ローカル開発**: `SHEETS_CREDENTIALS` 環境変数でサービスアカウント JSON
- **本番（GAS）**: GAS 標準の `SpreadsheetApp` API

### 必要な権限

- `spreadsheets.read`
- `spreadsheets.batchUpdate` (status 更新用)

### Quota

- Google Sheets API: 1 分間に 500 リクエスト

## スプレッドシート作成時のチェックリスト

- [ ] Spreadsheet ID を `.env` に設定
- [ ] サービスアカウント JSON を用意
- [ ] A1:H1 にヘッダ行を作成
- [ ] 共有設定（サービスアカウント email にアクセス権）
- [ ] GAS スクリプトで Slack webhook 設定

## 関連ドキュメント

- [QUEUE_ENTRY_SCHEMA_DESIGN.md](./accepted/QUEUE_ENTRY_SCHEMA_DESIGN.md) - スキーマ定義
- [internal/queue/sheets.go](../../internal/queue/sheets.go) - 実装予定

## 実装ロードマップ

- **フェーズ1**: internal/queue/sheets.go の Read/Write 実装
  - Read(): pending 行を取得する機能
  - Write(): status 列を更新する機能
- **フェーズ2**: Google Sheets API 認証・接続テスト
  - サービスアカウント認証
  - API キーの設定確認
- **フェーズ3**: GAS 側の appendQueueEntry 実装
  - Slack イベント受信時の自動追記
  - user_id フィールドの追加
- **フェーズ4**: end-to-end テスト実施
  - ローカル環境での動作確認
  - GAS との統合テスト

## トラブルシューティング

### よくある問題

1. **Google Sheets API エラー**
   - 認証情報が正しいか確認
   - API が有効になっているか確認
   - レート制限を確認

2. **データ同期の遅延**
   - GAS の実行ログを確認
   - API レスポンス時間を計測

---

**ステータス：提案中**  
**優先度：高（ローカル実装後のプロダクション化）**  
**作成日：2026-05-17**
