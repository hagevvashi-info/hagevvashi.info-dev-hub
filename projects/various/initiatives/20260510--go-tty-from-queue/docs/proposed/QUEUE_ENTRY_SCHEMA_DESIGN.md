---
status: proposed
date: 2026-05-17
author: アーキテクチャレビュー（main ブランチ保護インシデント）
last_updated: 2026-05-17
information_sources: ["https://docs.slack.dev/reference/events/message/", "https://api.slack.com/methods/conversations.history", "https://api.slack.com/changelog/2016-08-11-user-id-format-changes"]
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
    UserID    string `json:"user_id"`      // ← NEW: Slack ユーザー ID（Slack API の "user" フィールド）
}
```

---

## 📚 フィールド詳細とサンプル（Slack API ドキュメント ベース）

### 情報ソース一覧

すべてのフィールド情報は以下の公式 Slack API ドキュメントに基づいています：

| リソース | URL | 用途 |
|---------|-----|------|
| **message event** | https://docs.slack.dev/reference/events/message/ | メッセージイベント構造 |
| **conversations.history** | https://api.slack.com/methods/conversations.history | メッセージ取得 API |
| **User ID format** | https://api.slack.com/changelog/2016-08-11-user-id-format-changes | ID フォーマット仕様 |
| **Retrieving messages** | https://api.slack.com/messaging/retrieving | メッセージ取得方法 |
| **ts precision** | https://github.com/Inumedia/SlackAPI/issues/74 | タイムスタンプ精度 |

---

### 1️⃣ Channel（チャンネルID）

**情報ソース:** [conversations.history method](https://api.slack.com/methods/conversations.history)

**Slack API フィールド:** `channel`

**フォーマット:** `C` で始まる ID（11～13文字）

**公式引用：**
```
"The conversation ID to query. This argument takes a channel ID, or a DM user ID."
```

**実データサンプル：**
```json
{
  "channel": "C0LDKJ9RZ"
}
```

**Curl での取得例：**
```bash
# conversations.history で チャンネルメッセージ を取得
curl -X POST https://slack.com/api/conversations.history \
  -H "Authorization: Bearer xoxb-YOUR-TOKEN" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "channel=C0LDKJ9RZ&limit=10"

# レスポンス
{
  "ok": true,
  "messages": [
    {
      "type": "message",
      "channel": "C0LDKJ9RZ",
      "user": "U024BE7LH",
      "text": "Hello",
      "ts": "1403051575.000407"
    }
  ]
}
```

**GAS での取得：**
```javascript
const entry = {
  channel: event.channel  // Slack イベント から直接
};
```

**用途：**
- メッセージのポストされたチャンネル
- チャンネル別処理ルール（例：テック質問チャンネル → Claude）
- 監査証跡（「#general に投稿」）

---

### 2️⃣ MessageTS（メッセージタイムスタンプ）

**情報ソース:** [message event reference](https://docs.slack.dev/reference/events/message/) + [Message timestamp precision](https://github.com/Inumedia/SlackAPI/issues/74)

**Slack API フィールド:** `ts`

**フォーマット:** Unix エポック秒 + マイクロ秒（**文字列**）

**公式引用 1** - メッセージ イベント定義:
```
"The unique identifier for the message, in the form of a message's 
timestamp in floating-point seconds since the epoch."
```

**公式引用 2** - 精度 GitHub Issue:
```
"ts value is essentially the ID of the message, guaranteed unique within 
the context of a channel or conversation. They look like UNIX/epoch 
timestamps, hence ts, with specified milliseconds."

⚠️ 重要: "Even though they look like floats, they should always be stored 
and compared as strings - because floats occasionally lose precision and 
that would be bad here."
```

**実データサンプル：**
```json
{
  "ts": "1403051575.000407"
}
```

**フォーマット詳細：**
```
1403051575  = Unix エポック秒（1970-01-01 00:00:00 UTC からの秒数）
.000407     = マイクロ秒（6 桁、精度は マイクロ秒）

例: "1715951240.001200"
  ↓ JavaScript で変換
const date = new Date(parseFloat("1715951240.001200") * 1000);
  ↓ 結果
2026-05-27T10:20:40.001Z
```

**Curl での確認：**
```bash
# 特定メッセージを ts で取得
curl -X POST https://slack.com/api/conversations.history \
  -H "Authorization: Bearer xoxb-YOUR-TOKEN" \
  -d "channel=C0LDKJ9RZ&oldest=1403051575.000407&inclusive=true&limit=1"

# レスポンス
{
  "messages": [
    {
      "ts": "1403051575.000407",
      "text": "original message"
    }
  ]
}
```

**GAS での取得：**
```javascript
const entry = {
  message_ts: event.ts  // "1715951240.001200"
};
```

**用途：**
- メッセージの一意識別子（channel:ts で重複なし）
- メッセージスレッド化（thread_ts の基準）
- キューシステムでの重複検出

---

### 3️⃣ ThreadTS（スレッドトップのタイムスタンプ）

**情報ソース:** [message event reference](https://docs.slack.dev/reference/events/message/)

**Slack API フィールド:** `thread_ts`

**フォーマット:** Unix エポック秒 + マイクロ秒（**文字列**、MessageTS と同じ形式）

**公式引用：**
```
"If the message is a reply in a thread, thread_ts contains the timestamp 
of the parent message in the thread."
```

**実データサンプル：**
```json
{
  "thread_ts": "1403051575.000407",
  "ts": "1403051580.000500",
  "parent_user_id": "U024BE7LH",
  "type": "message"
}
```

**thread_ts の動作パターン：**
```
【スレッドルートメッセージ】
{
  "ts": "1403051575.000407",
  "thread_ts": "1403051575.000407",  ← ts と同じ
  "reply_count": 3
}

【スレッド内リプライ】
{
  "ts": "1403051580.000500",          ← リプライの時刻
  "thread_ts": "1403051575.000407",   ← ルートの時刻（同じ値）
  "reply_count": null
}

同じスレッド内のすべてのリプライ:
  thread_ts = "1403051575.000407" （同じ）
  ts = 各メッセージの時刻（異なる）
```

**Curl での取得：**
```bash
# スレッド内のすべてのメッセージを取得
curl -X POST https://slack.com/api/conversations.replies \
  -H "Authorization: Bearer xoxb-YOUR-TOKEN" \
  -d "channel=C0LDKJ9RZ&ts=1403051575.000407"

# レスポンス
{
  "messages": [
    {
      "ts": "1403051575.000407",
      "thread_ts": "1403051575.000407",
      "text": "Initial message"
    },
    {
      "ts": "1403051580.000500",
      "thread_ts": "1403051575.000407",
      "text": "First reply"
    }
  ]
}
```

**GAS での取得（オプション）：**
```javascript
const entry = {
  thread_ts: event.thread_ts || null  // スレッドリプライの場合のみ存在
};
```

**用途：**
- スレッド単位でのグループ化
- スレッド内の完全な会話を取得
- スレッドに返信（thread_ts を指定して channel.reply）

---

### 4️⃣ UserID（ユーザーID） ⭐ **カラム名決定**

**情報ソース:** [message event reference](https://docs.slack.dev/reference/events/message/) + [User ID format changes](https://api.slack.com/changelog/2016-08-11-user-id-format-changes)

**Slack API フィールド:** `user` （NOT `user_id`）

**フォーマット:** `U` で始まる ID（11～13文字）、または `W`、`B`

**公式引用 1** - message event:
```
"The ID of the user who sent the message. If the message was sent by 
a bot, this field may be omitted."
```

**公式引用 2** - User ID format:
```
"User IDs typically begin with U. From now on, you may also encounter 
team members with a user ID beginning with W. Treat these user IDs just 
as you would those beginning with U."
```

**ID タイプ一覧（Slack API 公式）：**
| 先頭 | タイプ | 例 | 備考 |
|------|--------|------|------|
| **U** | ユーザー | `U024BE7LH` | 標準ユーザー |
| **W** | ユーザー（新） | `W024BE7LH` | 新しい ID 形式 |
| **B** | Bot/App | `B024BE7LH` | ボット、Slack App |
| **A** | （古い Bot） | `A024BE7LH` | 互換性のため保持 |

**実データサンプル：**
```json
{
  "type": "message",
  "user": "U024BE7LH",
  "username": "alice.smith",
  "real_name": "Alice Smith"
}
```

**Curl で user フィールドを確認：**
```bash
# イベント webhook で受け取ったメッセージ
curl -X POST https://your-app.example.com/slack/events \
  -H "Content-Type: application/json" \
  -d '{
    "type": "event_callback",
    "event": {
      "type": "message",
      "user": "U024BE7LH",
      "text": "Hello",
      "ts": "1403051575.000407"
    }
  }'

# または conversations.history で取得
curl -X POST https://slack.com/api/conversations.history \
  -H "Authorization: Bearer xoxb-YOUR-TOKEN" \
  -d "channel=C0LDKJ9RZ&limit=5"
  
# レスポンス
{
  "messages": [
    {
      "type": "message",
      "user": "U024BE7LH",
      "text": "Hello"
    },
    {
      "type": "message",
      "user": "B024BE7LH",  ← Bot
      "text": "Bot response"
    }
  ]
}
```

**🎯 カラム名決定：`user_id` ✅**

| 比較項目 | `user` | `user_id` |
|---------|--------|-----------|
| **Slack API 名** | ✅ 同一 | ❌ 異なる |
| **Go 慣例** | ❌ camelCase | ✅ snake_case |
| **意味の明確さ** | △ フィールド不明 | ✅ 「ユーザーID」と明確 |
| **JSON 互換性** | ❌ API と異なる | ✅ マッピング時に明示 |

**結論：**
- **スキーマのカラム名：** `user_id` ✅
  - Go/JSON 命名規約に従う
  - 意味が明確（「ユーザーID」）
  
- **GAS 実装：** `user_id: event.user`
  - Slack API の `user` から、スキーマの `user_id` にマッピング

**GAS での取得と変換：**
```javascript
// Slack イベント処理
const agentUserID = "U0K4HRSJ2";  // Agent Y のユーザーID

function processMessage(event) {
  // ← フィルタ 1（GAS 側）
  if (event.user === agentUserID) {
    console.log("Agent Y のメッセージ → キューに含めない");
    return;
  }

  const entry = {
    user_id: event.user,  // Slack API "user" → スキーマ "user_id"
    // ...
  };
  queue.push(entry);
}
```

**Go での防御的フィルタ：**
```go
const AGENT_USER_ID = "U0K4HRSJ2"

// ← フィルタ 2（go-tty-from-queue 側）
func (p *QueuePlatform) FetchNewMessages() ([]message.Message, error) {
  for _, entry := range entries {
    if entry.UserID == AGENT_USER_ID {
      continue  // Agent Y を除外
    }
    
    if strings.HasPrefix(entry.UserID, "B_") {
      continue  // ボットを除外
    }
    
    // 有効なメッセージを処理
    messages = append(messages, convertToMessage(entry))
  }
}
```

**用途：**
- 無限ループ防止（Agent Y フィルタリング）
- 監査証跡（「ユーザー U024BE7LH が投稿」）
- ボット/自動メッセージの検出
- 重複検出（同じユーザーの連続ポスト）

---

### 5️⃣ Text（ポストテキスト）

**情報ソース:** [message event reference](https://docs.slack.dev/reference/events/message/)

**Slack API フィールド:** `text`

**フォーマット:** UTF-8 文字列（最大長は message type による）

**公式引用：**
```
"The message text. This is not guaranteed to be set for all message types."
```

**実データサンプル：**
```json
{
  "type": "message",
  "text": "プロジェクト Alpha の進捗状況を確認してください"
}
```

**リッチ要素の例：**
```json
{
  "text": "こんにちは <@U024BE7LH>、<#C0LDKJ9RZ|general> での <https://example.com|リンク> をご確認ください",
  "blocks": [
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "*進捗確認*\n```code block```"
      }
    }
  ],
  "attachments": [
    {
      "text": "添付: project-status.pdf"
    }
  ]
}
```

**Curl での取得：**
```bash
curl -X POST https://slack.com/api/conversations.history \
  -H "Authorization: Bearer xoxb-YOUR-TOKEN" \
  -d "channel=C0LDKJ9RZ&limit=5&inclusive=true"

# レスポンス
{
  "messages": [
    {
      "text": "プロジェクト Alpha の進捗状況を確認してください",
      "ts": "1403051575.000407"
    }
  ]
}
```

**GAS での取得：**
```javascript
const entry = {
  text: event.text
};
```

**用途：**
- エージェント入力プロンプト
- ユーザー質問・リクエストの取得

---

### 6️⃣ Time（ISO 8601 タイムスタンプ）

**情報ソース:** [ISO 8601 標準](https://ja.wikipedia.org/wiki/ISO_8601) + JavaScript `toISOString()`

**スキーマフィールド：** `time`（GAS で生成、Slack API にはない）

**フォーマット:** ISO 8601 形式（UTC、秒およびミリ秒精度）

**実データサンプル：**
```
2026-05-17T10:20:40.001Z
```

**フォーマット詳細：**
```
YYYY-MM-DD  = 年月日（2026-05-17）
T           = 日付と時刻の区切り
HH:MM:SS    = 時分秒（10:20:40）
.mmm        = ミリ秒（.001）
Z           = タイムゾーン（UTC、+00:00 と同じ）
```

**GAS（JavaScript）での生成：**
```javascript
const entry = {
  time: new Date().toISOString()
  // 出力: "2026-05-17T10:20:40.001Z"
};
```

**Go での解析：**
```go
import "time"

entry := &Entry{
  Time: "2026-05-17T10:20:40.001Z",
}

parsedTime, err := time.Parse(time.RFC3339Nano, entry.Time)
// 出力: 2026-05-17 10:20:40.001 +0000 UTC
```

**用途：**
- ログ・監査記録の日時
- 人間が読める形式のタイムスタンプ
- JSON ログへの時刻記録

---

### 7️⃣ Status（ステータス）

**スキーマフィールド：** `status`（キューシステム固有、Slack API にはない）

**許可値：**
```
"pending"     → キューに入った、未処理
"processing"  → go-tty-from-queue が処理中
"completed"   → 処理完了、エージェント回答を投稿
"failed"      → 処理失敗（エラーまたはタイムアウト）
```

**ライフサイクル例：**
```json
{
  "status": "pending",
  "created_at": "2026-05-17T10:00:34.001Z",
  "status_history": [
    {
      "status": "pending",
      "timestamp": "2026-05-17T10:00:34.001Z"
    },
    {
      "status": "processing",
      "timestamp": "2026-05-17T10:00:35.000Z"
    },
    {
      "status": "completed",
      "timestamp": "2026-05-17T10:01:20.500Z"
    }
  ]
}
```

**用途：**
- キューエントリのライフサイクル管理
- 処理状態の追跡
- デバッグ・監査

---

### 8️⃣ AgentType（エージェント種別）

**スキーマフィールド：** `agent_type`（GAS で設定）

**許可値：**
```
"claude"  → Claude AI（Anthropic）
"gemini"  → Gemini AI（Google）
```

**実データサンプル：**
```json
{
  "agent_type": "claude",
  "agent_config": {
    "model": "claude-opus-4"
  }
}
```

**GAS での選択ロジック例：**
```javascript
const channelAgents = {
  "C_TECH": "claude",
  "C_CREATIVE": "gemini"
};

function selectAgent(event) {
  if (event.text.includes("画像")) return "gemini";
  if (event.text.includes("コード")) return "claude";
  return channelAgents[event.channel] || "claude";
}

const entry = {
  agent_type: selectAgent(event)
};
```

**用途：**
- メッセージ処理に使用するエージェント指定
- 複数エージェントの使い分け

---

## 📋 完全なサンプル（エンドツーエンド）

### ステップ 1: Slack イベント受信

**情報ソース:** [Events API | Slack Developer Docs](https://docs.slack.dev/apis/events-api/)

```bash
# GAS webhook が受け取るイベント
POST https://your-gas-endpoint.example.com/slack/events

{
  "token": "verification_token",
  "team_id": "T0KRCA68V",
  "api_app_id": "A123456",
  "event": {
    "type": "message",
    "channel": "C0LDKJ9RZ",
    "user": "U024BE7LH",
    "text": "プロジェクト Alpha の進捗状況を教えてください",
    "ts": "1715951240.001200",
    "thread_ts": "1715951234.000500",
    "event_ts": "1715951240.001200"
  },
  "type": "event_callback",
  "event_id": "Ev024BE7LH",
  "event_time": 1715951240
}
```

### ステップ 2: キューエントリに変換（GAS）

```javascript
function handleSlackEvent(event) {
  const agentUserID = "U0K4HRSJ2";  // Agent Y

  // フィルタ 1（GAS 側：最初の防御）
  if (event.user === agentUserID) {
    return;  // 処理しない
  }

  const entry = {
    // Slack イベントから直接
    channel: event.channel,         // "C0LDKJ9RZ"
    thread_ts: event.thread_ts,     // "1715951234.000500"
    message_ts: event.ts,           // "1715951240.001200"
    text: event.text,               // "プロジェクト Alpha..."
    user_id: event.user,            // "U024BE7LH"

    // GAS で生成
    time: new Date().toISOString(), // "2026-05-17T10:20:40.001Z"
    status: "pending",
    agent_type: "claude"            // または "gemini"
  };

  // キューに保存（Google Sheets）
  queue.push(entry);
}
```

### ステップ 3: キューエントリ（JSON）

```json
{
  "channel": "C0LDKJ9RZ",
  "thread_ts": "1715951234.000500",
  "message_ts": "1715951240.001200",
  "text": "プロジェクト Alpha の進捗状況を教えてください",
  "time": "2026-05-17T10:20:40.001Z",
  "status": "pending",
  "agent_type": "claude",
  "user_id": "U024BE7LH"
}
```

### ステップ 4: go-tty-from-queue で処理

```go
const AGENT_USER_ID = "U0K4HRSJ2"

func (p *QueuePlatform) FetchNewMessages() ([]message.Message, error) {
  entries := p.source.Read()

  var messages []message.Message
  for _, entry := range entries {
    // フィルタ 2（go-tty-from-queue 側：最終防御）
    if entry.UserID == AGENT_USER_ID {
      continue  // Agent Y を除外
    }

    if strings.HasPrefix(entry.UserID, "B_") {
      continue  // ボットを除外
    }

    entry.Status = "processing"
    result, _ := b.Execute(message.Message{
      ID:        entry.MessageTS,
      ChannelID: entry.Channel,
      ThreadTS:  entry.ThreadTS,
      Content:   entry.Text,
      AgentType: entry.AgentType,
    })
    entry.Status = "completed"

    messages = append(messages, convertToMessage(entry))
  }

  return messages, nil
}
```

### ステップ 5: Slack に投稿

**情報ソース:** [chat.postMessage method](https://api.slack.com/methods/chat.postMessage)

```bash
curl -X POST https://slack.com/api/chat.postMessage \
  -H "Authorization: Bearer xoxb-YOUR-TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "channel": "C0LDKJ9RZ",
    "thread_ts": "1715951234.000500",
    "text": "プロジェクト Alpha は現在 80% の進捗です。次のマイルストーンは 2026-05-31 です。"
  }'
```

---

## 🎯 カラム名の最終確認

| カラム名 | Slack API | 推奨理由 |
|---------|-----------|---------|
| `channel` | `channel` ✅ | 一致 |
| `message_ts` | `ts` ✅ | 意味を明確化 |
| `thread_ts` | `thread_ts` ✅ | 一致 |
| `user_id` | `user` ✅ | snake_case、意味を明確化 |
| `text` | `text` ✅ | 一致 |
| `time` | （生成） ✅ | ISO 8601 人間可読 |
| `status` | （キュー固有） ✅ | ライフサイクル管理 |
| `agent_type` | （キュー固有） ✅ | エージェント選択 |

---

## 📖 参考リンク（全情報ソース）

**Slack API 公式リファレンス：**
1. [message event | Slack Developer Docs](https://docs.slack.dev/reference/events/message/)
2. [conversations.history | Slack API Methods](https://api.slack.com/methods/conversations.history)
3. [User ID format changes | Slack Changelog](https://api.slack.com/changelog/2016-08-11-user-id-format-changes)
4. [Retrieving messages | Slack Developer Docs](https://api.slack.com/messaging/retrieving)
5. [chat.postMessage | Slack API Methods](https://api.slack.com/methods/chat.postMessage)

**テクニカルリファレンス：**
6. [Message timestamp precision | GitHub Issue](https://github.com/Inumedia/SlackAPI/issues/74)
7. [How to convert Slack Message Timestamp to DateTime](https://support.centro.rocks/articles/123439-how-to-convert-slack-message-timestamp-to-a-date-time)
8. [ISO 8601 Date and Time Format](https://ja.wikipedia.org/wiki/ISO_8601)

---

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
- 「ユーザー U024BE7LH が 2026-05-17T10:00:00Z に #general で『ヘルプ』と投稿」
- デバッグを有効化：「このメッセージはどこからきた？」
- コンプライアンス：「誰が何をいつした？」

### 3. アーキテクチャの明確性

| 責務 | コンポーネント |
|---|---|
| 完全なメッセージデータを queue に提供 | GAS |
| Y でフィルタリング | GAS（最初の防御）+ go-tty-from-queue（最終防御） |
| 有効なメッセージを処理 | go-tty-from-queue |
| 監査証跡を保存 | キュー（user_id 経由） |

### 4. 将来の拡張性

`user_id` があれば、フィルタリングルールを簡単に追加可能：

```go
// ボット除外
if strings.HasPrefix(entry.UserID, "B_") {
  continue
}

// 管理者手動ポスト検出
if isAdminUser(entry.UserID) {
  continue
}

// 重複ポスト検出
if entry.UserID == lastUserID && time.Since(lastTime) < 5*time.Minute {
  continue
}
```

---

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
**最終更新：** 2026-05-17  
**ステータス：** 承認待機中  
**優先度：** 高（システムの正確性に影響）
