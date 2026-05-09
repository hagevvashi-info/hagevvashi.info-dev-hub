# Slack Events API + Google Apps Script による実装案

## 背景

前の案A（監視スレッド一覧）には致命的なスケーリング問題がある：

```
時間経過に伴う計算量増加

Day 1:  sessions.json に 10 スレッド
        → conversations.replies を 10 回呼び出し

Day 30: sessions.json に 500 スレッド
        → conversations.replies を 500 回呼び出し

Day 365: sessions.json に 10,000 スレッド
        → conversations.replies を 10,000 回呼び出し
        → Slack API レート制限（50 req/min）に引っかかる
```

**結論**: 古いセッションをいくら管理しても、スレッド数に比例して計算量が増え続ける。実用性が数日～数週間で失われる。

---

## 解決策：Slack Events API + Google Apps Script + Google Sheets

### 基本概念

```
【従来のポーリング方式】
SAM が定期的に Slack API を呼び出す
  ↓
「新着ありますか？」と毎回確認
  ↓
スレッド数に比例して呼び出し増加

【Events API 方式】
Slack が能動的に通知を送信
  ↓
新着イベント発生時のみ GAS が受け取る
  ↓
計算量は常に一定（新着のみ）
```

---

## アーキテクチャ

```
┌─────────────────────────────────────────────────────────────┐
│                     Slack Workspace                         │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ Channel with Threads                                    │ │
│ │ ┌─────────────────────────────────────────────────────┐ │ │
│ │ │ Parent Message (ts=1000)                            │ │ │
│ │ │ ├─ Reply (ts=2000) ← イベント発火！                 │ │ │
│ │ │ └─ Reply (ts=2001) ← イベント発火！                 │ │ │
│ │ └─────────────────────────────────────────────────────┘ │ │
│ └─────────────────────────────────────────────────────────┘ │
└────────────┬──────────────────────────────────────────────┘
             │ Events API (WebHook POST)
             ↓
┌─────────────────────────────────────────────────────────────┐
│             Google Apps Script                              │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ doPost(e) {                                             │ │
│ │   - Slack 署名検証                                      │ │
│ │   - イベント解析                                        │ │
│ │   - Google Sheets にキュー追加                          │ │
│ │ }                                                       │ │
│ └─────────────────────────────────────────────────────────┘ │
└────────────┬──────────────────────────────────────────────┘
             │
             ↓
┌─────────────────────────────────────────────────────────────┐
│         Google Sheets (Queue 管理)                          │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ Channel|ThreadTS|MessageTS|Text|Time|Status            │ │
│ │ C_XXX  |1715161200|1715161250|...|...|pending          │ │
│ │ C_YYY  |1715161300|1715161350|...|...|processing       │ │
│ │ C_ZZZ  |1715161400|1715161450|...|...|completed        │ │
│ └─────────────────────────────────────────────────────────┘ │
└────────────┬──────────────────────────────────────────────┘
             │ 定期監視（1分間隔）
             ↓
┌─────────────────────────────────────────────────────────────┐
│    SAM (Server Agent Manager / Go)                          │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ 1. Sheets から pending を読む                            │ │
│ │ 2. Claude Agent を実行                                  │ │
│ │ 3. Status を completed に更新                            │ │
│ │ 4. 定期削除: completed を自動削除                        │ │
│ └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

---

## 実装例

### 1. Google Apps Script（WebHook エンドポイント）

```javascript
// config
const SLACK_SIGNING_SECRET = PropertiesService.getScriptProperties()
  .getProperty('SLACK_SIGNING_SECRET');
const SPREADSHEET_ID = 'YOUR_SHEET_ID';

// Slack 署名検証
function verifySlackSignature(e) {
  const signature = e.parameter.X_SLACK_REQUEST_SIGNATURE || 
                    e.postData.headers['X-Slack-Request-Signature'];
  const timestamp = e.parameter.X_SLACK_REQUEST_TIMESTAMP || 
                    e.postData.headers['X-Slack-Request-Timestamp'];
  
  const currentTime = Math.floor(Date.now() / 1000);
  if (Math.abs(currentTime - timestamp) > 300) {
    return false; // リプレイ攻撃対策
  }

  const baseString = `v0:${timestamp}:${e.postData.contents}`;
  const hmac = Utilities.computeHmacSignature(
    Utilities.MacAlgorithm.HMAC_SHA_256,
    baseString,
    SLACK_SIGNING_SECRET
  );
  const computedSignature = 'v0=' + 
    Utilities.bytesToHex(hmac).toLowerCase();
  
  return computedSignature === signature;
}

// メイン処理
function doPost(e) {
  const json = JSON.parse(e.postData.contents);
  
  // 署名検証
  if (!verifySlackSignature(e)) {
    return HtmlService.createHtmlOutput('Unauthorized')
      .setHttpResponseCode(401);
  }
  
  // URL verification challenge
  if (json.type === 'url_verification') {
    return ContentService.createTextOutput(json.challenge)
      .setHttpResponseCode(200);
  }
  
  // イベント処理
  if (json.type === 'event_callback') {
    const event = json.event;
    
    // メッセージ + スレッド返信を検出
    if (event.type === 'message' && event.thread_ts) {
      addToQueue(
        event.channel,
        event.thread_ts,
        event.ts,
        event.text,
        'pending'
      );
    }
  }
  
  return HtmlService.createHtmlOutput('OK')
    .setHttpResponseCode(200);
}

// キューにイベントを追加
function addToQueue(channel, threadTS, messageTS, text, status) {
  const sheet = SpreadsheetApp
    .openById(SPREADSHEET_ID)
    .getSheetByName('Queue');
  
  sheet.appendRow([
    channel,
    threadTS,
    messageTS,
    text,
    new Date(),
    status
  ]);
}

// GAS をデプロイ
// 新しいデプロイ → Web アプリケーション → 実行対象: 自分 → アクセス: 誰でも
```

### 2. GAS を Web App としてデプロイ

```
Google Apps Script エディタ
  → 「デプロイ」ボタン
  → 「新しいデプロイ」
  → タイプ: Web アプリケーション
  → 実行対象: 自分
  → アクセス権限: 誰でも
  ↓
公開 URL が生成される
例: https://script.google.com/macros/d/1a2b3c.../usercontent
```

### 3. Slack App でイベント購読を設定

```
Slack App 管理画面
  → Event Subscriptions
  → Enable Events: ON
  → Request URL: 上記の GAS URL をペースト
  ↓ Slack が自動検証（url_verification challenge）
  → Subscribe to bot events: "message"
  → Save
```

### 4. SAM（Go）が Sheets を監視

```go
type SheetsPlatform struct {
  SpreadsheetID string
  ServiceAccount *sheets.Service
}

func (p *SheetsPlatform) FetchNewMessages() ([]Message, error) {
  // Google Sheets API で pending を取得
  values, err := p.ServiceAccount.Spreadsheets.Values.Get(
    p.SpreadsheetID,
    "Queue!A:F",
  ).Do()
  
  var messages []Message
  for _, row := range values.Values {
    if len(row) >= 6 && row[5] == "pending" {
      messages = append(messages, Message{
        ChannelID: row[0].(string),
        ThreadTS:  row[1].(string),
        ID:        row[2].(string),
        Content:   row[3].(string),
      })
    }
  }
  return messages, nil
}

func (p *SheetsPlatform) UpdateStatus(rowIndex int, status string) {
  // Google Sheets API で Status を更新
  p.ServiceAccount.Spreadsheets.Values.Update(
    p.SpreadsheetID,
    fmt.Sprintf("Queue!F%d", rowIndex+2),
    &sheets.ValueRange{
      Values: [][]interface{}{{status}},
    },
  ).Do()
}
```

---

## Queue シートの構成

```
┌─────────────────────────────────────────────────────────────┐
│ A: Channel | B: ThreadTS | C: MessageTS | D: Text | E: Time │
│            |             |              |        |          │
├─────────────────────────────────────────────────────────────┤
│ C_CLAUDE   | 1715161200  | 1715161250   | "fix..." | 2026-05-08 |
│ C_CLAUDE   | 1715161300  | 1715161350   | "done"   | 2026-05-08 |
│ C_AGENTS   | 1715161400  | 1715161450   | "test"   | 2026-05-08 |
└─────────────────────────────────────────────────────────────┘

    F: Status
    
    pending      → SAM がまだ処理していない
    processing   → SAM が Claude Agent を実行中
    completed    → SAM が処理完了
    failed       → エラー発生
```

---

## 運用ポリシー

### Status フロー

```
新着イベント発生
  ↓ GAS で記録
pending (新着)
  ↓ SAM が検知（1分間隔）
processing (実行中)
  ↓ Claude Agent が返信を処理
completed (完了)
  ↓ 定期削除タスク（1日1回）
  ✅ シートから削除
```

### completed 行の削除ポリシー

```
定期削除のタイミング:
• 毎日 0:00 UTC に実行
• 完了から 24 時間経過した行を削除
• または completed 行数が 1000 を超えたら削除

実装方法:
- GAS: Time-driven トリガー（毎日実行）
- または SAM: 起動時に自動削除ロジック
```

例：

```javascript
// GAS トリガー関数
function deleteCompletedRows() {
  const sheet = SpreadsheetApp
    .openById(SPREADSHEET_ID)
    .getSheetByName('Queue');
  
  const values = sheet.getDataRange().getValues();
  const rowsToDelete = [];
  const now = new Date();
  
  for (let i = values.length - 1; i > 0; i--) {
    const status = values[i][5];
    const time = values[i][4];
    
    // completed かつ 24 時間以上前
    if (status === 'completed' && 
        (now - time) > 24 * 60 * 60 * 1000) {
      rowsToDelete.push(i + 1);
    }
  }
  
  // 下から削除（行番号がずれないように）
  rowsToDelete.forEach(row => sheet.deleteRow(row));
}

// トリガー設定: 毎日 0:00 UTC に実行
```

---

## メリット・デメリット

### ✅ メリット

| 項目 | ポーリング案（案A） | Events API + GAS 案 |
|-----|-------------------|-------------------|
| **計算量** | O(n)、増加し続ける | O(1)、常に一定 |
| **レイテンシ** | 10-30 秒 | 数秒以内 |
| **API 呼び出し** | 増加し続ける | 固定（新着のみ） |
| **スレッド数制限** | 数千スレッドで限界 | 無制限 |
| **メモリ効率** | 悪い（全スレッド列挙） | 良い（キューのみ） |

### ❌ デメリット

| 項目 | 対策 |
|-----|------|
| **GAS のコールドスタート** | 初回実行は 1-2 秒遅い。許容可 |
| **Slack App 管理の手間** | 署名検証など実装が少し増える |
| **Google Sheets の行数上限** | 定期削除で対応（100万行まで） |
| **OAuth スコープ管理** | GAS 認可が必要 |

---

## 結論

**Events API + GAS + Sheets は、スケーリング問題を完全に解決する最適アーキテクチャ。**

- ✅ ポーリングの計算量問題なし
- ✅ リアルタイム性（数秒以内）
- ✅ 監視スレッド一覧の管理が不要
- ✅ キュー管理が明示的で運用しやすい
- ✅ GAS + Sheets という Google エコシステムの活用

次のステップ：
1. GAS の実装と Web App デプロイ
2. Slack App で Events Subscription 設定
3. SAM に Google Sheets API クライアントを統合
4. テスト（ローカルで新しい実装フローを検証）
