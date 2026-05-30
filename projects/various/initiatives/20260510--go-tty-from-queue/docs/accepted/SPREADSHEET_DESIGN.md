---
status: accepted
date: 2026-05-17
author: アーキテクチャレビュー
reviewed: 2026-05-30
reviewer_notes: Production-ready（デプロイ前チェック＆フェーズ実装で実現可）
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

### Entry 型の定義

```go
// internal/queue/entry.go
package queue

type Entry struct {
  Channel   string `json:"channel"`
  ThreadTS  string `json:"thread_ts"`
  MessageTS string `json:"message_ts"`
  Text      string `json:"text"`
  UserID    string `json:"user_id"`
  Time      string `json:"time"`
  Status    string `json:"status"`
  AgentType string `json:"agent_type"`
  Revision  int    `json:"revision,omitempty"`
  RowIndex  int    `json:"-"` // 内部用（行番号）
}
```

### Sheets 構造体の定義

```go
// internal/queue/sheets.go
package queue

import (
  "google.golang.org/api/sheets/v4"
  "time"
)

type Sheets struct {
  service       *sheets.Service
  spreadsheetID string
  timeout       time.Duration
  rateLimit     int
}
```

### Read(): pending 行を取得

```go
func (s *Sheets) Read(ctx context.Context) ([]Entry, error) {
  resp, err := s.service.Spreadsheets.Values.Get(s.spreadsheetID, "A2:I1000").
    Context(ctx).
    Do()
  if err != nil {
    return nil, fmt.Errorf("failed to get spreadsheet values: %w", err)
  }

  var entries []Entry
  for i, row := range resp.Values {
    if len(row) < 7 {
      continue
    }
    
    status, ok := row[6].(string)
    if !ok || status != "pending" {
      continue
    }

    entry := Entry{
      Channel:   getString(row, 0),
      ThreadTS:  getString(row, 1),
      MessageTS: getString(row, 2),
      Text:      getString(row, 3),
      UserID:    getString(row, 4),
      Time:      getString(row, 5),
      Status:    status,
      AgentType: getString(row, 7),
      Revision:  getInt(row, 8),
      RowIndex:  i + 2, // 0-indexed + header row
    }
    entries = append(entries, entry)
  }

  return entries, nil
}

func (s *Sheets) Write(ctx context.Context, entries []Entry) error {
  if len(entries) == 0 {
    return nil
  }

  const batchSize = 50
  for i := 0; i < len(entries); i += batchSize {
    end := i + batchSize
    if end > len(entries) {
      end = len(entries)
    }
    
    batch := entries[i:end]
    if err := s.batchUpdateRows(ctx, batch); err != nil {
      return fmt.Errorf("failed to batch update rows: %w", err)
    }
  }

  return nil
}
```

**ヘルパー関数：**

```go
func getString(row []interface{}, idx int) string {
  if idx >= len(row) {
    return ""
  }
  s, ok := row[idx].(string)
  if !ok {
    return ""
  }
  return s
}

func getInt(row []interface{}, idx int) int {
  if idx >= len(row) {
    return 0
  }
  s, ok := row[idx].(string)
  if !ok {
    return 0
  }
  v, err := strconv.Atoi(s)
  if err != nil {
    return 0
  }
  return v
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

## エラーハンドリング

### エラー分類と対応

**エラータイプ別戦略：**

| エラー | HTTP ステータス | 対応 | 例 |
|--------|----------------|------|-----|
| レート制限 | 429 Too Many Requests | Exponential Backoff 再試行 | `quotaExceeded` |
| 認証失敗 | 401 Unauthorized | ログ出力後ファイル | サービスアカウント期限切れ |
| 権限不足 | 403 Forbidden | ログ出力後ファイル | スプレッドシート未共有 |
| メッセージ未検出 | (メッセージ無し) | スキップして継続 | `findRowByMessageTS` 返り値: error |
| ネットワークタイムアウト | timeout | Exponential Backoff 再試行 | `context.DeadlineExceeded` |

**実装例：**

```go
func isRateLimitError(err error) bool {
  if err == nil {
    return false
  }
  return strings.Contains(err.Error(), "quotaExceeded") ||
         strings.Contains(err.Error(), "429")
}

func isAuthError(err error) bool {
  if err == nil {
    return false
  }
  return strings.Contains(err.Error(), "401") ||
         strings.Contains(err.Error(), "Unauthorized")
}

func isPermissionError(err error) bool {
  if err == nil {
    return false
  }
  return strings.Contains(err.Error(), "403") ||
         strings.Contains(err.Error(), "Forbidden")
}

func retryWithBackoff(ctx context.Context, maxRetries int, fn func() error) error {
  backoff := time.Second
  maxBackoff := 30 * time.Second

  for attempt := 0; attempt < maxRetries; attempt++ {
    err := fn()
    if err == nil {
      return nil
    }

    if !isRateLimitError(err) {
      // レート制限以外は即座に失敗
      return err
    }

    if attempt < maxRetries-1 {
      log.Printf("Rate limit hit. Waiting %v before retry %d/%d",
        backoff, attempt+1, maxRetries)
      
      select {
      case <-time.After(backoff):
        backoff *= 2
        if backoff > maxBackoff {
          backoff = maxBackoff
        }
      case <-ctx.Done():
        return ctx.Err()
      }
    }
  }

  return fmt.Errorf("max retries exceeded after %d attempts", maxRetries)
}

// Read 呼び出し時の使用例
func (s *Sheets) ReadWithRetry(ctx context.Context) ([]Entry, error) {
  var entries []Entry
  err := retryWithBackoff(ctx, 4, func() error {
    var err error
    entries, err = s.Read(ctx)
    return err
  })
  return entries, err
}
```

## トラブルシューティング

### よくある問題と対応

1. **Google Sheets API エラー (429 Too Many Requests)**
   - 現象：レート制限エラーが頻発
   - 対策：Exponential Backoff を設定済みのため自動再試行されます
   - チューニング：`batchSize` を 50 → 100 に増やす、API キーの割り当てを確認

2. **認証エラー (401 Unauthorized)**
   - 現象：`SHEETS_CREDENTIALS_PATH` の JSON ファイルが読み込めない
   - 対策：JSON ファイルの パス を確認、ファイルのパーミッション（`chmod 600`）を確認
   - 確認方法：`cat ~/.config/go-tty/sheets-creds.json | jq '.client_email'`

3. **権限不足エラー (403 Forbidden)**
   - 現象：スプレッドシートへのアクセスが拒否される
   - 対策：Google Cloud Console でサービスアカウント email をスプレッドシートと共有し、「編集者」権限を付与

4. **データ同期の遅延**
   - 現象：GAS が行を append した直後に go-tty-from-queue が読み込むと見つからない
   - 対策：revision-based optimistic locking で競合状態を検出。重複検出時は `log.Printf` で記録
   - API レスポンス時間の計測：`time.Since()` で計測結果をログ出力

---

## 並行実行とロック戦略

### 5.1 競合状態シナリオ分析

**問題：** GAS が行を append、go-tty-from-queue が status を更新する際に、同じ行に対して同時アクセスが発生

**具体的なシナリオ：**

```
時刻1: go-tty-from-queue が message_ts="A" を読み込み
       → status="pending" で表示

時刻2: 同時に GAS が message_ts="A" を再度作成しようとする
       （重複チェックなし）

時刻3: go-tty-from-queue が status を "processing" に更新

時刻4: 同時に GAS が status="pending" で新しい行を append

結果：message_ts="A" が2行存在（重複）→ エージェントが2回実行
```

**リスク：**
- 無限ループ誘発
- 監査証跡の不正確性
- API コスト の増加（重複処理）

### 5.2 ロック戦略の比較

| 戦略 | 概要 | メリット | デメリット | 推奨度 |
|------|------|---------|---------|--------|
| **A. 楽観的ロック（Revision ID）** | 各行に revision フィールドを追加、更新時に version 確認 | シンプル、スケーラブル | GAS 側の実装が複雑 | 🟢 推奨 |
| **B. メッセージID重複チェック** | append前に message_ts が存在するか確認 | GAS側で実装可能 | Google Sheets API 呼び出し増加 | 🟡 代案 |
| **C. ペシミスティックロック** | 行単位で明示的にロック | 強い一貫性 | Google Sheets API が lock をサポートしない | ✗ 不可 |
| **D. Firebase へ移行** | Google Sheets から Cloud Firestore に切り替え | 強い一貫性、トランザクション対応 | プロジェクト規模の大幅変更 | 🟡 検討 |

### 5.3 採用パターン：楽観的ロック（Revision ID）

**実装方法：**

スプレッドシートに **列 I：revision** を追加

```
A | B | C | D | E | F | G | H | I
channel | thread_ts | message_ts | text | user_id | time | status | agent_type | revision
```

**GAS 側の実装：**

```javascript
function appendQueueEntry(event) {
  const sheet = SpreadsheetApp.getActiveSheet();
  
  // フィルタ 1: Agent Y 除外
  if (event.user === "U0K4HRSJ2") return;
  
  // フィルタ 2: 重複チェック（楽観的ロック）
  const data = sheet.getDataRange().getValues();
  for (let i = 1; i < data.length; i++) {
    if (data[i][2] === event.ts) {  // message_ts 列（C）
      console.log("Duplicate message_ts detected. Skipping.");
      return;  // 既に存在 → append しない
    }
  }
  
  // 新規行を append（revision = 1 で開始）
  const row = [
    event.channel,
    event.thread_ts || event.ts,
    event.ts,
    event.text,
    event.user,
    new Date().toISOString(),
    "pending",
    selectAgent(event),
    1  // revision = 1（新規）
  ];
  
  sheet.appendRow(row);
}
```

**Go 側の実装（update時）：**

```go
// internal/queue/sheets.go

func (s *Sheets) Write(entries []Entry) error {
  ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
  defer cancel()

  for _, entry := range entries {
    // message_ts で該当行を検索
    rowIndex, currentRevision, err := s.findRowByMessageTS(ctx, entry.MessageTS)
    if err != nil {
      return err
    }

    // 楽観的ロック：現在の revision が期待値と一致するか確認
    if currentRevision != entry.Revision {
      // 別のプロセスが更新している → スキップ
      log.Printf("Revision mismatch for %s. Expected %d, got %d. Skipping.",
        entry.MessageTS, entry.Revision, currentRevision)
      continue
    }

    // revision をインクリメントして更新
    entry.Revision++
    err = s.updateRow(ctx, rowIndex, entry)
    if err != nil {
      return err
    }
  }

  return nil
}

func (s *Sheets) findRowByMessageTS(ctx context.Context, messageTS string) (int, int, error) {
  // API 呼び出し削減：単一リクエストで A:I を取得してからクライアント側で検索
  resp, err := s.service.Spreadsheets.Values.Get(s.spreadsheetID, "A2:I1000").
    Context(ctx).
    Do()
  if err != nil {
    if isRateLimitError(err) {
      return 0, 0, fmt.Errorf("rate limit exceeded: %w", err)
    }
    if isAuthError(err) {
      return 0, 0, fmt.Errorf("authentication failed: %w", err)
    }
    return 0, 0, fmt.Errorf("failed to get spreadsheet: %w", err)
  }

  // クライアント側で message_ts（列 C = index 2）を検索
  for i, row := range resp.Values {
    if len(row) > 2 && getString(row, 2) == messageTS {
      rowIndex := i + 2
      revision := 1
      if len(row) > 8 {
        revision = getInt(row, 8)
      }
      return rowIndex, revision, nil
    }
  }

  return 0, 0, fmt.Errorf("message_ts not found: %s", messageTS)
}

func (s *Sheets) updateRow(ctx context.Context, rowIndex int, entry Entry) error {
  return s.batchUpdateRows(ctx, []Entry{entry})
}

func (s *Sheets) batchUpdateRows(ctx context.Context, entries []Entry) error {
  requests := make([]*sheets.Request, 0, len(entries)*2)

  for _, entry := range entries {
    // Status を更新（列 G = index 6）
    requests = append(requests, &sheets.Request{
      UpdateCells: &sheets.UpdateCellsRequest{
        Range: &sheets.GridRange{
          SheetId:       0,
          StartRowIndex: int64(entry.RowIndex - 1),
          EndRowIndex:   int64(entry.RowIndex),
          StartColumnIndex: 6,
          EndColumnIndex:   7,
        },
        Rows: []*sheets.RowData{
          {
            Values: []*sheets.CellData{
              {
                UserEnteredValue: &sheets.ExtendedValue{
                  StringValue: &entry.Status,
                },
              },
            },
          },
        },
        Fields: "userEnteredValue",
      },
    })

    // Revision を更新（列 I = index 8）
    revStr := fmt.Sprintf("%d", entry.Revision)
    requests = append(requests, &sheets.Request{
      UpdateCells: &sheets.UpdateCellsRequest{
        Range: &sheets.GridRange{
          SheetId:       0,
          StartRowIndex: int64(entry.RowIndex - 1),
          EndRowIndex:   int64(entry.RowIndex),
          StartColumnIndex: 8,
          EndColumnIndex:   9,
        },
        Rows: []*sheets.RowData{
          {
            Values: []*sheets.CellData{
              {
                UserEnteredValue: &sheets.ExtendedValue{
                  StringValue: &revStr,
                },
              },
            },
          },
        },
        Fields: "userEnteredValue",
      },
    })
  }

  req := &sheets.BatchUpdateSpreadsheetRequest{
    Requests: requests,
  }

  _, err := s.service.Spreadsheets.BatchUpdate(s.spreadsheetID, req).
    Context(ctx).
    Do()
  if err != nil {
    if isRateLimitError(err) {
      return fmt.Errorf("rate limit exceeded: %w", err)
    }
    return fmt.Errorf("batch update failed: %w", err)
  }

  return nil
}
```

**ライフサイクル例：**

```
【初期】
message_ts="A", status="pending", revision=1

【go-tty-from-queue が処理開始】
1. message_ts="A" の行を読み込み → revision=1 を確認
2. status を "processing" に変更 → revision を 2 に更新
3. write 実行成功

【同時に GAS が重複 append を試みる】
1. sheet.getDataRange() で全行を検索
2. message_ts="A" が既に存在 → append をスキップ

【go-tty-from-queue が処理完了】
1. message_ts="A" の行を再度読み込み → revision=2 を確認
2. status を "completed" に変更 → revision を 3 に更新
```

---

## セットアップと認証

### 6.1 サービスアカウント作成（Google Cloud Console）

**前提：** Google Cloud プロジェクトが既に存在すること

**手順：**

1. **Google Cloud Console にログイン**
   ```
   https://console.cloud.google.com
   ```

2. **Google Sheets API を有効化**
   - 「API とサービス」→「ライブラリ」
   - "Google Sheets API" を検索
   - 「有効にする」をクリック

3. **サービスアカウントを作成**
   - 「API とサービス」→「認証情報」
   - 「認証情報を作成」→「サービスアカウント」
   - 以下を入力：
     - サービスアカウント名：`go-tty-queue-reader`
     - サービスアカウントID：（自動生成）
     - 説明：`Go service for reading Slack queue from Google Sheets`
   - 「作成して続行」

4. **ロールを付与**
   - **Basic Roles** から「編集者」を選択
   - 「続行」

5. **キーを作成**
   - 「キーを作成」→「新しいキーを作成」
   - キータイプ：「JSON」
   - 「作成」
   - JSON ファイルが自動ダウンロード（保管）

### 6.2 スプレッドシート共有設定

**手順：**

1. **キューストレージ用スプレッドシートを作成**
   ```
   https://sheets.google.com
   ```

2. **ヘッダ行を設定（A1:I1）**
   ```
   channel | thread_ts | message_ts | text | user_id | time | status | agent_type | revision
   ```

3. **サービスアカウントに共有**
   - スプレッドシートを開く
   - 「共有」→「ユーザーやグループを追加」
   - サービスアカウント email を入力：
     ```
     go-tty-queue-reader@PROJECT_ID.iam.gserviceaccount.com
     ```
   - 権限：「編集者」を選択
   - 「共有」

4. **Spreadsheet ID を確認**
   - URL から抽出：
     ```
     https://docs.google.com/spreadsheets/d/{SPREADSHEET_ID}/edit
     ```

### 6.3 環境変数設定

**ローカル開発用 .env ファイル（git ignore）：**

```bash
# Google Sheets キューストレージ設定
SHEETS_SPREADSHEET_ID="1a2b3c4d5e6f7g8h9i0j1k2l3m4n5o6p"
SHEETS_CREDENTIALS_PATH="~/.config/go-tty/sheets-creds.json"

# API タイムアウト
SHEETS_API_TIMEOUT_SECONDS="30"

# レート制限（最大 500 req/min）
SHEETS_REQUEST_RATE_LIMIT="450"
```

**サービスアカウント JSON の配置：**

```bash
# ステップ 6.1 でダウンロードしたファイルをコピー
mkdir -p ~/.config/go-tty
cp ~/Downloads/go-tty-queue-reader-XXXXX.json ~/.config/go-tty/sheets-creds.json

# パーミッション設定（セキュリティ）
chmod 600 ~/.config/go-tty/sheets-creds.json
```

### 6.4 Go アプリケーション設定

**internal/queue/sheets.go（初期化）：**

```go
package queue

import (
  "context"
  "fmt"
  "os"
  "strconv"
  "time"
  "google.golang.org/api/sheets/v4"
  "google.golang.org/api/option"
)

type SheetsConfig struct {
  SpreadsheetID     string
  CredentialsPath   string
  TimeoutSeconds    int
  RequestRateLimit  int
}

func NewSheetsFromEnv() (*Sheets, error) {
  cfg := SheetsConfig{
    SpreadsheetID:    os.Getenv("SHEETS_SPREADSHEET_ID"),
    CredentialsPath:  os.Getenv("SHEETS_CREDENTIALS_PATH"),
    TimeoutSeconds:   getEnvInt("SHEETS_API_TIMEOUT_SECONDS", 30),
    RequestRateLimit: getEnvInt("SHEETS_REQUEST_RATE_LIMIT", 450),
  }

  // バリデーション
  if cfg.SpreadsheetID == "" {
    return nil, fmt.Errorf("SHEETS_SPREADSHEET_ID environment variable not set")
  }
  if cfg.CredentialsPath == "" {
    return nil, fmt.Errorf("SHEETS_CREDENTIALS_PATH environment variable not set")
  }

  // ファイルの存在確認
  if _, err := os.Stat(cfg.CredentialsPath); err != nil {
    return nil, fmt.Errorf("credentials file not found at %s: %w", cfg.CredentialsPath, err)
  }

  // サービスアカウント JSON で認証
  ctx := context.Background()
  srv, err := sheets.NewService(ctx, option.WithCredentialsFile(cfg.CredentialsPath))
  if err != nil {
    return nil, fmt.Errorf("failed to create Sheets service: %w", err)
  }

  return &Sheets{
    service:       srv,
    spreadsheetID: cfg.SpreadsheetID,
    timeout:       time.Duration(cfg.TimeoutSeconds) * time.Second,
    rateLimit:     cfg.RequestRateLimit,
  }, nil
}

func getEnvInt(key string, defaultValue int) int {
  val := os.Getenv(key)
  if val == "" {
    return defaultValue
  }
  num, err := strconv.Atoi(val)
  if err != nil {
    return defaultValue
  }
  return num
}
```

---

## パフォーマンスとスケーリング

### 7.1 Google Sheets API レート制限対応

**API レート：** 500 リクエスト/分（制限）

**最適化戦略：**

1. **バッチ操作（batchGet/batchUpdate）**
   ```go
   // ❌ 非効率：個別に更新（N 行 = N リクエスト）
   for _, entry := range entries {
     updateRow(entry)  // 1 リクエスト/行
   }

   // ✅ 効率的：バッチ更新（N 行 = 1 リクエスト）
   batchUpdateRows(entries)  // 1 リクエスト/batch
   ```

2. **ページネーション（大量行の処理）**
   ```go
   // pending 行が 1000 行以上の場合
   const pageSize = 100
   for offset := 0; offset < totalRows; offset += pageSize {
     entries := readPendingRows(offset, pageSize)
     processBatch(entries)
   }
   ```

3. **キャッシング戦略**
   - メモリに最後の Read 結果をキャッシュ（30秒 TTL）
   - 重複 Read リクエストをスキップ

### 7.2 Retry 戦略（レート制限エラー時）

**Exponential Backoff：**

```go
func retryWithBackoff(maxRetries int, fn func() error) error {
  backoff := time.Second
  maxBackoff := 30 * time.Second

  for attempt := 0; attempt < maxRetries; attempt++ {
    err := fn()
    if err == nil {
      return nil
    }

    if isRateLimitError(err) {
      log.Printf("Rate limit hit. Waiting %v before retry %d/%d",
        backoff, attempt+1, maxRetries)
      time.Sleep(backoff)
      
      // 指数バックオフ：1s → 2s → 4s → 8s → ... → 30s
      backoff *= 2
      if backoff > maxBackoff {
        backoff = maxBackoff
      }
      continue
    }

    // レート制限以外のエラーは即座に失敗
    return err
  }

  return fmt.Errorf("max retries exceeded")
}
```

### 7.3 大規模キューへの対応

**pending 行数が 1000 行を超える場合：**

| 処理 | 単位 | API コスト | 推奨設定 |
|------|------|----------|--------|
| Read | 100行/batch | 1 req/batch | pageSize=100 |
| Write | 50行/batch | 1 req/batch | batchUpdateSize=50 |
| 月間コスト | 1000 pending | 600 req/day | 18k req/month |

### 7.4 バッチサイズ計算の詳細

**API レート制限の分析：**

```
Google Sheets API: 500 requests/minute（制限）
= 500 req/min ÷ 60 sec = 8.33 req/sec

pending キュー処理：
- Read: 1 req/100 rows
- Write: 1 req/50 rows（status + revision の2列を1つの batchUpdate で更新）
- 総処理: 2 req/cycle

1000 pending 行の処理：
- Read: ceil(1000/100) = 10 req
- Write: ceil(1000/50) = 20 req
- 総計: 30 req/cycle

レート制限内での動作確認：
30 req/cycle < 500 req/min ✅
= 0.006 × 100% = 0.6% 利用率
```

**バッチサイズ決定アルゴリズム：**

```go
const (
  APIRateLimit     = 500  // requests per minute
  SafetyMargin     = 0.9  // Use only 90% to avoid hitting limit
  ReqPerCycle      = 2    // 1 read + 1 write per batch cycle
  EstimatedSeconds = 300  // Expected cycle time (5 minutes)
)

func calculateOptimalBatchSize(maxPending int) int {
  // Available requests per cycle
  available := int(float64(APIRateLimit) * SafetyMargin * (float64(EstimatedSeconds) / 60.0))
  
  // How many batches can we process?
  availableBatches := available / ReqPerCycle
  
  // Optimal batch size
  batchSize := maxPending / availableBatches
  
  // Cap at 100 for memory efficiency
  if batchSize > 100 {
    batchSize = 100
  }
  
  return batchSize
}

// Example: maxPending=1000
// available = 500 × 0.9 × (300/60) = 225 req
// availableBatches = 225 / 2 = 112 batches
// batchSize = 1000 / 112 ≈ 8 rows... but cap at 100 for efficiency
// => Use batchSize=50 as safe default
```

---

## テスト戦略

### 9.1 ユニットテスト

**テスト対象：** `internal/queue/sheets_test.go`

```go
package queue

import (
  "context"
  "testing"
)

func TestFindRowByMessageTS(t *testing.T) {
  // モック Sheets API を準備
  mockSvc := &mockSheetsService{
    values: [][]interface{}{
      {"C024BE7LH", "1715161200.000100", "1715161200.000100", "test", "U024BE7LH", "2026-05-17T10:00:00Z", "pending", "claude", "1"},
    },
  }

  s := &Sheets{service: mockSvc, spreadsheetID: "test-id"}
  
  row, rev, err := s.findRowByMessageTS(context.Background(), "1715161200.000100")
  if err != nil {
    t.Fatalf("Expected no error, got %v", err)
  }
  if row != 2 {
    t.Errorf("Expected row=2, got %d", row)
  }
  if rev != 1 {
    t.Errorf("Expected revision=1, got %d", rev)
  }
}

func TestUpdateRow(t *testing.T) {
  mockSvc := &mockSheetsService{}
  s := &Sheets{service: mockSvc, spreadsheetID: "test-id"}

  entry := Entry{
    MessageTS: "1715161200.000100",
    Status:    "processing",
    Revision:  2,
    RowIndex:  2,
  }

  err := s.updateRow(context.Background(), 2, entry)
  if err != nil {
    t.Fatalf("Expected no error, got %v", err)
  }
}

func TestRetryWithBackoff(t *testing.T) {
  attempts := 0
  err := retryWithBackoff(context.Background(), 3, func() error {
    attempts++
    if attempts < 2 {
      return fmt.Errorf("quotaExceeded")
    }
    return nil
  })
  
  if err != nil {
    t.Fatalf("Expected no error after retries, got %v", err)
  }
  if attempts != 2 {
    t.Errorf("Expected 2 attempts, got %d", attempts)
  }
}

func TestRetryExceedsMaxAttempts(t *testing.T) {
  err := retryWithBackoff(context.Background(), 2, func() error {
    return fmt.Errorf("quotaExceeded")
  })
  
  if err == nil {
    t.Fatal("Expected error when max retries exceeded")
  }
  if !strings.Contains(err.Error(), "max retries exceeded") {
    t.Errorf("Expected 'max retries exceeded' error, got: %v", err)
  }
}
```

### 9.2 統合テスト（GAS + Go 連携）

**GAS テスト関数：**

```javascript
// apps-script.json 設定
{
  "timeZone": "Asia/Tokyo",
  "exceptionLogging": "STACKDRIVER",
  "runtimeVersion": "V8",
  "dependencies": {
    "sheets": {
      "version": "v4"
    }
  }
}

// Google Apps Script コード
function testAppendQueueEntry() {
  const testCases = [
    {
      channel: "C0LDKJ9RZ",
      ts: "1715951240.001200",
      thread_ts: "1715951234.000500",
      text: "Test message 1",
      user: "U024BE7LH"
    },
    {
      channel: "C0LDKJ9RZ",
      ts: "1715951240.001200",  // 重複
      thread_ts: "1715951234.000500",
      text: "Duplicate message",
      user: "U024BE7LH"
    }
  ];

  const sheet = SpreadsheetApp.getActiveSheet();
  const beforeCount = sheet.getLastRow();

  // テスト 1: 正常な行を append
  appendQueueEntry(testCases[0]);
  const afterFirstAppend = sheet.getLastRow();
  
  if (afterFirstAppend !== beforeCount + 1) {
    throw new Error("Expected 1 row appended, got " + (afterFirstAppend - beforeCount));
  }

  // テスト 2: 重複を検出してスキップ
  appendQueueEntry(testCases[1]);
  const afterDuplicate = sheet.getLastRow();
  
  if (afterDuplicate !== afterFirstAppend) {
    throw new Error("Expected duplicate to be skipped");
  }

  // テスト 3: revision が 1 で初期化されているか
  const lastRow = sheet.getRange(afterFirstAppend, 9).getValue();
  if (lastRow !== 1) {
    throw new Error("Expected revision=1, got " + lastRow);
  }

  console.log("✅ All GAS tests passed");
}

// デプロイ後にこのテスト関数を Google Apps Script エディタで実行
// メニュー → 実行 → testAppendQueueEntry
```

**Go 側の統合テストスクリプト：**

```bash
#!/bin/bash
# integration_test.sh

set -e

SPREADSHEET_ID="${SHEETS_SPREADSHEET_ID}"
SHEETS_CREDENTIALS_PATH="${SHEETS_CREDENTIALS_PATH:-~/.config/go-tty/sheets-creds.json}"

if [ -z "$SPREADSHEET_ID" ] || [ ! -f "$SHEETS_CREDENTIALS_PATH" ]; then
  echo "ERROR: SHEETS_SPREADSHEET_ID or SHEETS_CREDENTIALS_PATH not set"
  exit 1
fi

echo "[TEST] Starting integration test..."

# Step 1: GAS テスト実行確認（手動で実行済み）
echo "[TEST] GAS appendQueueEntry test - run 'testAppendQueueEntry()' in Apps Script editor"

# Step 2: Go ユニットテスト
echo "[TEST] Running Go unit tests..."
go test -v ./internal/queue -run "TestFindRowByMessageTS|TestRetryWithBackoff"

# Step 3: Go Read テスト
echo "[TEST] Testing Read() function..."
export SHEETS_SPREADSHEET_ID=$SPREADSHEET_ID
export SHEETS_CREDENTIALS_PATH=$SHEETS_CREDENTIALS_PATH
go run ./cmd/worker -test-read

# Step 4: Go Write テスト
echo "[TEST] Testing Write() function..."
go run ./cmd/worker -test-write

echo "[TEST] ✅ All integration tests passed"
```

### 9.3 E2E テスト

**テスト対象：** 実 Slack イベント → キュー → エージェント実行

```bash
#!/bin/bash
# e2e_test.sh

# 前提: 実環境の Google Sheets, Redis, Slack 接続

# ステップ 1: Slack テストメッセージ送信
MESSAGE_ID=$(curl -X POST https://slack.com/api/chat.postMessage \
  -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
  -d channel=C024BE7LH \
  -d text="E2E test message" | jq -r '.ts')

sleep 2

# ステップ 2: GAS が行を append したことを確認
SHEET_ROWS=$(gsheets read $SPREADSHEET_ID "G:G" | grep -c "pending")
if [ $SHEET_ROWS -lt 1 ]; then
  echo "ERROR: GAS did not append row"
  exit 1
fi

# ステップ 3: go-tty-from-queue を実行
./bin/go-tty-from-queue &
WORKER_PID=$!
sleep 5

# ステップ 4: status が "completed" に更新されたことを確認
FINAL_STATUS=$(gsheets read $SPREADSHEET_ID "G:G" | tail -1)
if [ "$FINAL_STATUS" != "completed" ]; then
  echo "ERROR: Status is $FINAL_STATUS, expected 'completed'"
  kill $WORKER_PID
  exit 1
fi

echo "✅ E2E test passed"
kill $WORKER_PID
```

---

## GAS 側の LockService 実装

### 10.1 原子的な append 処理

**問題：** GAS が行を append する際、複数の Slack イベントが同時に appendQueueEntry を呼び出すと、重複行が作成される可能性がある。

**解決：** `LockService` を使用して同時実行を制御

```javascript
function appendQueueEntry(event) {
  const agentUserID = "U0K4HRSJ2";  // Agent Y
  
  // フィルタ 1: Agent Y 除外
  if (event.user === agentUserID) return;
  
  // LockService で同時実行を制御
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(5000)) {
    // 5秒以内にロック取得失敗 → 他のプロセスが処理中
    console.log("Failed to acquire lock. Another process is appending.");
    return;
  }
  
  try {
    const sheet = SpreadsheetApp.getActiveSheet();
    
    // フィルタ 2: 重複チェック（ロック取得後、改めて確認）
    const data = sheet.getDataRange().getValues();
    for (let i = 1; i < data.length; i++) {
      if (data[i][2] === event.ts) {  // message_ts 列（C）
        console.log("Duplicate message_ts detected. Skipping.");
        return;
      }
    }
    
    // 新規行を append（revision = 1 で開始）
    const row = [
      event.channel,
      event.thread_ts || event.ts,
      event.ts,
      event.text,
      event.user,
      new Date().toISOString(),
      "pending",
      selectAgent(event),
      1  // revision = 1（新規）
    ];
    
    sheet.appendRow(row);
    console.log(`Appended row for message_ts=${event.ts}`);
    
  } finally {
    // ロック解放（必ず実行）
    lock.releaseLock();
  }
}

function selectAgent(event) {
  // ボタンID で推測するなど、簡単なロジック
  // TODO: より複雑なエージェント選択ロジックはここに記述
  return event.text.includes("claude") ? "claude" : "gemini";
}
```

---

## アーキテクチャ比較：Google Sheets vs 代替案

| 特性 | Google Sheets | Cloud Firestore | DynamoDB |
|------|---------------|-----------------|----------|
| **セットアップ難度** | 簡単（GAS 統合） | 中程度（Firebase CLI） | 中程度（AWS CLI） |
| **レート制限** | 500 req/min | 無制限* | 40,000 WCU/s* |
| **強い一貫性** | ❌ 最終的一貫性 | ✅ 強い一貫性 | ✅ 強い一貫性 |
| **トランザクション** | ❌ 不可 | ✅ ACID | ✅ ACID |
| **料金** | 無料～ $10/month | $1～$100/month | $1～$500/month |
| **スケーラビリティ** | △ 1000行まで実用的 | ✅ 数百万行対応 | ✅ 数百万行対応 |
| **GAS との統合** | ✅ ネイティブ | △ REST API | △ REST API |
| **保守性** | ✅ シンプル | ❌ 複雑 | ❌ 複雑 |

**推奨：**
- **初期段階（pending < 1000）：** Google Sheets
- **スケール後（pending > 10000）：** Cloud Firestore への移行検討

---

## セキュリティ設計

### 11.1 認証情報の管理

**ローカル開発環境：**

```bash
# サービスアカウント JSON を ~/.config/go-tty に配置
mkdir -p ~/.config/go-tty
cp ~/Downloads/go-tty-queue-reader-XXXXX.json ~/.config/go-tty/sheets-creds.json
chmod 600 ~/.config/go-tty/sheets-creds.json
```

**.env ファイル（.gitignore に追加）：**

```bash
SHEETS_SPREADSHEET_ID="1a2b3c4d5e6f7g8h9i0j1k2l3m4n5o6p"
SHEETS_CREDENTIALS_PATH="~/.config/go-tty/sheets-creds.json"
SHEETS_API_TIMEOUT_SECONDS="30"
```

**本番環境（Kubernetes）：**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: sheets-credentials
  namespace: go-tty
type: Opaque
data:
  sheets-creds.json: <base64-encoded-json>
  spreadsheet-id: <base64-encoded-id>
---
apiVersion: v1
kind: Pod
metadata:
  name: go-tty-worker
spec:
  containers:
  - name: worker
    image: go-tty:latest
    env:
    - name: SHEETS_SPREADSHEET_ID
      valueFrom:
        secretKeyRef:
          name: sheets-credentials
          key: spreadsheet-id
    - name: SHEETS_CREDENTIALS_PATH
      value: /etc/secrets/sheets-creds.json
    volumeMounts:
    - name: sheets-creds
      mountPath: /etc/secrets
      readOnly: true
  volumes:
  - name: sheets-creds
    secret:
      secretName: sheets-credentials
      items:
      - key: sheets-creds.json
        path: sheets-creds.json
        mode: 0400
```

**HashiCorp Vault（本番推奨）：**

```hcl
# Vault へ秘密情報を保存
vault kv put secret/go-tty/sheets \
  spreadsheet_id="1a2b3c..." \
  credentials=@./sheets-creds.json

# Go アプリケーションから読み込み
vaultClient := api.NewClient(...)
secret, err := vaultClient.Logical().Read("secret/data/go-tty/sheets")
spreadsheetID := secret.Data["data"].(map[string]interface{})["spreadsheet_id"]
```

### 11.2 IAM 権限の最小化

**Google Cloud IAM ロール設定：**

```bash
# サービスアカウント メールアドレス
SA_EMAIL="go-tty-queue-reader@PROJECT_ID.iam.gserviceaccount.com"

# スプレッドシート ID
SHEET_ID="1a2b3c4d5e6f7g8h9i0j1k2l3m4n5o6p"

# 権限付与（スプレッドシートレベル）
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member=serviceAccount:$SA_EMAIL \
  --role=roles/editor

# または、カスタムロール（より制限的）
gcloud iam custom-roles create sheetsQueueReader \
  --project=PROJECT_ID \
  --title="Google Sheets Queue Reader" \
  --permissions=spreadsheets.values.get,spreadsheets.values.batchUpdate

gcloud projects add-iam-policy-binding PROJECT_ID \
  --member=serviceAccount:$SA_EMAIL \
  --role=projects/PROJECT_ID/roles/sheetsQueueReader
```

### 11.3 認証情報のローテーション

**30 日ごとのキーローテーション：**

```bash
#!/bin/bash
# rotate-sheets-key.sh

set -e

SA_NAME="go-tty-queue-reader"
PROJECT_ID="my-project"
KEY_PATH="${HOME}/.config/go-tty/sheets-creds.json"

# 既存キーの削除
OLD_KEY=$(gcloud iam service-accounts keys list \
  --iam-account="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --filter="validAfterTime<-P30D" \
  --format='value(name)' | head -1)

if [ -n "$OLD_KEY" ]; then
  gcloud iam service-accounts keys delete "$OLD_KEY" \
    --iam-account="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --quiet
  echo "Deleted old key: $OLD_KEY"
fi

# 新キーの作成
gcloud iam service-accounts keys create "$KEY_PATH" \
  --iam-account="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "Created new key at $KEY_PATH"

# Kubernetes Secret を更新（本番環境）
kubectl create secret generic sheets-credentials \
  --from-file=sheets-creds.json="$KEY_PATH" \
  --from-literal=spreadsheet-id="SPREADSHEET_ID" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Updated Kubernetes Secret"
```

**Cron スケジュール：**

```bash
# 30 日ごと（月初）
0 0 1 * * /usr/local/bin/rotate-sheets-key.sh >> /var/log/sheets-rotation.log 2>&1
```

### 11.4 監査ログ

**Go アプリケーション側の監査ログ：**

```go
func logAudit(action string, entry Entry, result string) {
  timestamp := time.Now().Format(time.RFC3339)
  log.Printf("[AUDIT] %s | action=%s | message_ts=%s | user=%s | result=%s",
    timestamp, action, entry.MessageTS, entry.UserID, result)
}

// 使用例
logAudit("READ", entry, "success")
logAudit("UPDATE_STATUS", entry, "processing")
logAudit("RATE_LIMIT", entry, "retry")
```

**GAS 側の監査ログ：**

```javascript
function logAudit(action, eventTs, result) {
  const timestamp = new Date().toISOString();
  const logEntry = `[AUDIT] ${timestamp} | action=${action} | ts=${eventTs} | result=${result}`;
  console.log(logEntry);
  
  // オプション：Google Sheet の別シートに記録
  const logSheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName("audit");
  if (logSheet) {
    logSheet.appendRow([timestamp, action, eventTs, result]);
  }
}
```

---

## デプロイ前チェックリスト

本番環境へのデプロイ前に、以下のチェック項目を完了してください。

### ローカル開発環境

- [ ] Google Sheets API を有効化（Google Cloud Console）
- [ ] サービスアカウント作成、JSON キーをダウンロード
- [ ] `~/.config/go-tty/sheets-creds.json` に JSON キーを配置（chmod 600）
- [ ] `.env` ファイルを作成（SHEETS_SPREADSHEET_ID 設定）
- [ ] スプレッドシートを作成、サービスアカウント email に共有設定

### コード検証

- [ ] `go test ./internal/queue` で全テスト合格（TestFindRowByMessageTS, TestRetryWithBackoff 含む）
- [ ] `go build ./cmd/worker` でビルド成功
- [ ] `go build ./cmd/generate-test-queue` でテストキュー生成ツール作成完了

### GAS テスト実行

- [ ] Google Apps Script エディタで `testAppendQueueEntry()` 関数を実行
- [ ] テスト結果：3 行目以降に テストデータ が append されている
- [ ] テスト結果：重複データはスキップされている（行数が増えない）
- [ ] テスト結果：revision = 1 で初期化されている

### Go 側の機能テスト

**Read() のテスト：**
```bash
export SHEETS_SPREADSHEET_ID="..."
export SHEETS_CREDENTIALS_PATH="~/.config/go-tty/sheets-creds.json"
go test -v ./internal/queue -run TestRead
```

**Write() のテスト：**
```bash
# ローカルスプレッドシートに pending エントリを数行作成
go test -v ./internal/queue -run TestWrite
# status が "processing" に更新されることを確認
```

**リトライロジックのテスト：**
```bash
go test -v ./internal/queue -run TestRetryWithBackoff
go test -v ./internal/queue -run TestRetryExceedsMaxAttempts
```

### 本番環境初期化（Kubernetes デプロイ前）

- [ ] Kubernetes Secret 作成：
  ```bash
  kubectl create secret generic sheets-credentials \
    --from-file=sheets-creds.json="~/.config/go-tty/sheets-creds.json" \
    --from-literal=spreadsheet-id="SPREADSHEET_ID" \
    -n go-tty
  ```

- [ ] キーローテーション Cron ジョブをスケジュール：
  ```bash
  # rotate-sheets-key.sh を /usr/local/bin に配置
  # crontab に追加：0 0 1 * * /usr/local/bin/rotate-sheets-key.sh
  ```

- [ ] 監査ログの保存先を確認：
  ```bash
  kubectl logs -l app=go-tty-worker -n go-tty | grep AUDIT
  ```

### API レート制限テスト

- [ ] 50 行をバッチで複数回更新（無制限ループ）
- [ ] エラーが発生しないことを確認（Exponential Backoff で対応）
- [ ] レート制限エラー時に自動リトライされることを確認：
  ```bash
  # ログに "Rate limit hit. Waiting Xvs before retry" が出力される
  ```

### エラーシナリオテスト

- [ ] **認証エラー（401）：** JSON ファイルを削除 → エラーメッセージが表示される
  ```
  Expected: "credentials file not found"
  ```

- [ ] **権限エラー（403）：** スプレッドシート共有を取り消す → エラーメッセージが表示される
  ```
  Expected: "Forbidden" in error message
  ```

- [ ] **ネットワークタイムアウト：** ネットワークを遮断 → Exponential Backoff で リトライされる

---

## 実装ロードマップ

### フェーズ 1（ローカル開発）：2026-06-15 完了予定

- [ ] Entry 型・Sheets 型の実装
- [ ] Read() / Write() / findRowByMessageTS() / updateRow() の実装
- [ ] エラーハンドリング（isRateLimitError, isAuthError, retryWithBackoff）の実装
- [ ] ユニットテスト実装（TestFindRowByMessageTS, TestRetryWithBackoff）
- [ ] GAS appendQueueEntry() + LockService の実装
- [ ] ローカル環境で動作確認

### フェーズ 2（統合テスト）：2026-06-22 完了予定

- [ ] GAS テスト関数（testAppendQueueEntry）の実行
- [ ] Go + GAS 連携テスト（integration_test.sh）
- [ ] E2E テスト（Slack メッセージ → キュー → エージェント実行）
- [ ] エラーシナリオテスト（認証エラー、権限エラー、タイムアウト）

### フェーズ 3（本番デプロイ）：2026-06-29 完了予定

- [ ] Kubernetes Secret 作成
- [ ] キーローテーション スクリプト設定
- [ ] 監査ログ確認
- [ ] 本番スプレッドシート作成
- [ ] 本番エージェント設定
- [ ] トラフィック段階的増加（カナリアデプロイ）

---

**ステータス：改善完了（🟢 Product-Ready、デプロイ前チェック実施推奨）**  
**最終更新：2026-05-30**  
**優先度：高（ローカル実装後のプロダクション化）**
