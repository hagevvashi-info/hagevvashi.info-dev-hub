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
├── platform.go          # Platform I/F（QueuePlatform）
├── bridge.go            # Message → Agent 実行（セッション管理・返信投稿・MarkProcessed）
├── agent.go             # Agent I/F（ClaudeAgent + GeminiAgent）
├── queue_entry.go       # QueueEntry 型（GAS → Sheets のスキーマ）
├── queue_source.go      # QueueSource I/F（LocalQueueSource + SheetQueueSource）
├── session.go           # SessionManager + AgentSession
├── session_store.go     # SessionStore（sessions.json への永続化）
├── go.mod
├── go.sum
├── .gitignore
├── README.md
├── cmd/
│   └── worker/
│       └── main.go      # Worker バイナリ（エントリポイント）
│   └── generate-test-queue/
│       └── main.go      # テストデータ生成スクリプト
├── internal/
│   └── (内部パッケージ）
└── fixtures/
    └── queue.json       # git管理外（.gitignoreに追加）
```

## Build

バイナリをビルドします。出力先は `./bin/go-tty-from-queue`。

```bash
make build
```

またはシンプルに:
```bash
go build -o ./bin/go-tty-from-queue ./cmd/worker/
```

**クリーンアップ:**
```bash
make clean
```

## ローカルテスト実行

### ステップ 1: テストデータを生成

`-output` フラグで出力先を指定してテストデータを生成します（必須）。

```bash
go run ./cmd/generate-test-queue -output /tmp/queue.json
```

#### テストパターン指定（オプション）

`-pattern` フラグでテストパターンを選択できます（デフォルト: `2` = claude-multi-thread）。
パターンは **ID** または **名前** で指定可能です。

**利用可能なパターン一覧表示:**

```bash
go run ./cmd/generate-test-queue -list
```

出力例:
```
Available test patterns:

  ID: 1 | Name: claude-single        | Agent: claude | Single message, single thread
  ID: 2 | Name: claude-multi-thread  | Agent: claude | Multiple threads, 1 message each
  ID: 3 | Name: claude-multi-msg     | Agent: claude | Single thread, multiple messages (combined execution)
  ID: 4 | Name: gemini-single        | Agent: gemini | Gemini single message
  ID: 5 | Name: gemini-multi-msg     | Agent: gemini | Gemini single thread, multiple messages
  ID: 6 | Name: mixed-agents         | Agent: mixed  | Claude + Gemini agents
```

**パターン指定例:**

ID で指定:
```bash
go run ./cmd/generate-test-queue -output /tmp/queue.json -pattern 1
go run ./cmd/generate-test-queue -output /tmp/queue.json -pattern 3
```

名前で指定:
```bash
go run ./cmd/generate-test-queue -output /tmp/queue.json -pattern claude-single
go run ./cmd/generate-test-queue -output /tmp/queue.json -pattern mixed-agents
```

**パターンの説明:**

| ID | パターン名 | 説明 | 用途 |
|----|-----------|------|------|
| 1 | claude-single | Claude: 単一メッセージ、単一スレッド | 最小限のテスト |
| 2 | claude-multi-thread | Claude: 複数スレッド（各 1 メッセージ） | 並列実行テスト |
| 3 | claude-multi-msg | Claude: 1 スレッド内の複数メッセージ | メッセージ結合テスト |
| 4 | gemini-single | Gemini: 単一メッセージ | Gemini 動作確認 |
| 5 | gemini-multi-msg | Gemini: 1 スレッド内の複数メッセージ | Gemini 結合テスト |
| 6 | mixed-agents | Claude + Gemini 混在 | マルチエージェントテスト |

出力例:
```
✅ Queue data generated: /tmp/queue.json (pattern: 2 - claude-multi-thread)
```

**注**: `-output` フラグなしで実行するとエラーになります（出力先を明示的に指定するため）

### ステップ 2: メインプログラムを実行

```bash
QUEUE_FILE=/tmp/queue.json REDIS_ADDR=localhost:6379 go run ./cmd/worker/
```

**注**: 
- `QUEUE_FILE` 環境変数の指定は必須です（指定しないとエラーで終了）
- `REDIS_ADDR` 環境変数の指定も必須です（セッション保存に Redis を使用）
- デフォルト値: `REDIS_ADDR=localhost:6379`

#### パターン別実行例

**単一メッセージテスト:**
```bash
go run ./cmd/generate-test-queue -output /tmp/queue.json -pattern claude-single
QUEUE_FILE=/tmp/queue.json REDIS_ADDR=localhost:6379 go run ./cmd/worker/
```

**複数スレッド並列実行テスト:**
```bash
go run ./cmd/generate-test-queue -output /tmp/queue.json -pattern 2
QUEUE_FILE=/tmp/queue.json REDIS_ADDR=localhost:6379 go run ./cmd/worker/
```

**メッセージ結合テスト:**
```bash
go run ./cmd/generate-test-queue -output /tmp/queue.json -pattern claude-multi-msg
QUEUE_FILE=/tmp/queue.json REDIS_ADDR=localhost:6379 go run ./cmd/worker/
```

**マルチエージェントテスト:**
```bash
go run ./cmd/generate-test-queue -output /tmp/queue.json -pattern mixed-agents
QUEUE_FILE=/tmp/queue.json REDIS_ADDR=localhost:6379 go run ./cmd/worker/
```

期待動作:
1. `/tmp/queue.json` から pending メッセージを読み込む
2. スレッド単位でグループ化
3. 各スレッドを TTY で Agent に投げる（並列実行、Agent は queue.json の agent_type に従う）
4. 返答を stdout に出力
5. `queue.json` の status を "completed" に自動更新
6. Redis にセッション ID 紐付けを保存

実行結果例:
```
🔍 [Queue] pending メッセージを取得します...
📨 取得したメッセージ数: 3
👷 [Bridge] 開始: 1715161400.000100 (Agent: claude)
👷 [Bridge] 開始: 1715161200.000100 (Agent: claude)
🔁 [Bridge] 既存セッションへ投げます: session_id=... thread=1715161200.000100
📢 [Queue Post] channel: C_LOCAL_CLAUDE ID: ... への返信:
(Claude の返答 1)
📢 [Queue Post] channel: C_LOCAL_CLAUDE ID: ... への返信:
(Claude の返答 2)
✅ All jobs finished.
```

### ステップ 3: セッション確認

実行後、セッション紐付けが Redis に保存されます:

```bash
redis-cli KEYS "session:*"
```

出力例:
```
session:C_LOCAL_CLAUDE:1715161200.000100
session:C_LOCAL_CLAUDE:1715161400.000100
```

セッション詳細の確認:
```bash
redis-cli GET "session:C_LOCAL_CLAUDE:1715161200.000100" | jq .
```

出力例:
```json
{
  "agent_type": "claude",
  "created_at": "2026-05-10T00:12:16Z",
  "last_used_at": "2026-05-10T00:12:26Z",
  "session_id": "e7f6d54b-7eb3-4156-b20e-f0322ca165ef"
}
```

### ステップ 4: キューの状態確認

実行後、キューは updated に変わります:

```bash
cat /tmp/queue.json | jq '.[] | {message_ts, status}'
```

出力例:
```json
{
  "message_ts": "1715161200.000100",
  "status": "completed"
}
```

## 本番実行（未実装）

```bash
export APP_ENV=production
export SPREADSHEET_ID=your-sheet-id
export QUEUE_FILE=/path/to/queue.json
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
