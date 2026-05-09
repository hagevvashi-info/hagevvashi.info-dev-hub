# go-tty-from-queue

Slack Events API + Google Apps Script → Google Sheets というキュー方式に対応した、Claude Agent の TTY 実行エンジン。

## アーキテクチャ

```
GAS (doPost) → Sheets (Queue) → go-tty-from-queue
                ↑                      ↓
                └── MarkProcessed ←────┘
```

- **入力**: `fixtures/queue.json`（ローカル）/ Google Sheets（本番）
- **処理**: Queue エントリをスレッド単位でグループ化 → TTY で Agent に投げる
- **出力**: stdout（ローカル）/ Slack スレッド返信（本番）
- **状態管理**: `sessions.json`（Claude セッション ID 紐付け）

## 設計

### スレッド概念

- **スレッドトップ**: `message_ts == thread_ts` の場合
  - 新規セッション を作成
  - `sessions.json` に登録

- **スレッド返信**: `message_ts != thread_ts` の場合
  - 既存セッションを再開（`--resume` フラグ）
  - 既存セッション喪失時は新規作成

### メッセージ結合

同一スレッド内に複数メッセージがある場合、`\n\n---\n\n` 区切りで結合して 1 回の Agent 実行にする。

```
メッセージ1: "現在のファイル一覧を教えて"
メッセージ2: "それぞれのサイズも教えて"
              ↓ 結合
投げるテキスト: "現在のファイル一覧を教えて\n\n---\n\nそれぞれのサイズも教えて"
```

### 並列実行

- **スレッド間**: 並列（goroutine で独立実行）
- **スレッド内**: 逐次（sync.Mutex でシリアライズ）

セッション状態の一貫性のため、同一スレッドは逐次実行に寄せます。

## ファイル構成

```
.
├── main.go              # エントリポイント（Queue読み込み・スレッド並列化・状態管理）
├── platform.go          # Platform I/F（LocalPlatform + SheetsPlatform）
├── bridge.go            # Message → Agent 実行（セッション管理・返信投稿・MarkProcessed）
├── agent.go             # Agent I/F（ClaudeAgent + GeminiAgent）
├── session.go           # SessionManager + AgentSession
├── session_store.go     # SessionStore（sessions.json への永続化）
├── queue_entry.go       # QueueEntry 型（GAS → Sheets のスキーマ）
├── go.mod
├── go.sum
├── .gitignore
└── fixtures/
    └── queue.json       # ローカルテスト用 Queue（ただし実行後は completed で上書き）
```

## ローカル実行

```bash
cd /home/hagevvashi/hagevvashi.info-dev-hub/projects/various/initiatives/20260510--go-tty-from-queue

# ローカルモード（デフォルト）
go run .

# または
APP_ENV=local go run .
```

期待動作:
1. `fixtures/queue.json` から pending を読み込む
2. スレッド単位でグループ化
3. 各スレッドを TTY で Claude に投げる
4. 返答を stdout に出力
5. `queue.json` の status を "completed" に更新
6. `sessions.json` にセッションID紐付けを保存

実行結果例:
```
🔍 [Local] Queue から pending メッセージを取得します...
📨 取得したメッセージ数: 3
👷 [Bridge] 開始: 1715161200.000100 (Agent: claude)
👷 [Bridge] 開始: 1715161400.000100 (Agent: claude)
📢 [Local Post] channel: C_LOCAL_CLAUDE ID: ... への返信:
(Claude の返答)
✅ All jobs finished.
```

## 本番実行（未実装）

```bash
export APP_ENV=production
export SPREADSHEET_ID=your-sheet-id
go run .
```

- `SheetsPlatform` で Google Sheets API から Queue を読み込む
- Slack API で スレッド返信を投稿
- Sheets の status フィールドを更新

## Queue スキーマ

GAS が Google Sheets から読んで JSON 化するデータ構造：

```json
{
  "channel": "C_LOCAL_CLAUDE",
  "thread_ts": "1715161200.000100",
  "message_ts": "1715161200.000100",
  "text": "質問や指示",
  "time": "2026-05-08T10:00:00Z",
  "status": "pending",
  "agent_type": "claude"
}
```

- `channel`: Slack チャンネルID
- `thread_ts`: スレッドトップのタイムスタンプ
- `message_ts`: このメッセージのタイムスタンプ
- `text`: 質問・指示テキスト
- `time`: ISO 8601 形式のタイムスタンプ
- `status`: `"pending"` / `"processing"` / `"completed"` / `"failed"`
- `agent_type`: `"claude"` / `"gemini"`

## Status フロー（Queue 管理）

```
pending
  ↓ 本アプリが処理開始
processing (オプション、現在は未実装)
  ↓ Agent 実行完了
completed
  ↓ 定期削除タスク（24時間後またはrows > 1000）
  削除
```

### completed 行の削除

ローカルでは Firebase やスプレッドシート関数で自動削除が望ましい。
本番では GAS トリガー（毎日0:00）で削除:

```javascript
function deleteCompletedRows() {
  const sheet = SpreadsheetApp
    .openById(SPREADSHEET_ID)
    .getSheetByName('Queue');
  
  const values = sheet.getDataRange().getValues();
  const now = new Date();
  const rowsToDelete = [];
  
  for (let i = values.length - 1; i > 0; i--) {
    const status = values[i][/* status column */];
    const time = values[i][/* time column */];
    
    if (status === 'completed' && (now - time) > 24 * 60 * 60 * 1000) {
      rowsToDelete.push(i + 1);
    }
  }
  
  rowsToDelete.forEach(row => sheet.deleteRow(row));
}
```

## 依存関係

```
github.com/creack/pty v1.1.18  # PTY エミュレーション（Claude CLI 実行用）
```

## 開発ノート

### スレッド同期

- `AgentSession.mu` で同一スレッド内の逐次実行を保証
- `SessionManager.mu` でセッション領域全体を保護

### セッション永続化

- `SessionStore.Save()` は `.tmp` ファイルに書いてからアトミックリネーム
- 部分的な書き込みフェイルを防止

### エラーハンドリング

- Agent 実行エラーは `PostResponse` で通知（ユーザーに伝わる）
- Queue 読み込みエラーは終了
- JSON パースエラーは詳細を stderr に出力

## 今後の改善

1. SheetsPlatform の実装
2. 定期削除メカニズムの実装
3. GeminiAgent の実装
4. エラーリトライロジック
5. Rate limit 対応
