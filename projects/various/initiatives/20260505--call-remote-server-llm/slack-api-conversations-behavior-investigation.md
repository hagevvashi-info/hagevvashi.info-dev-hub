# Slack API conversations.* の動作仕様調査レポート

## 背景

`slack-thread-polling-notes.md` で「親が古いが返信が新しい場合、`conversations.history` では見つけられない」という指摘があったが、その理由が不明確だったため、Slack REST API の公式ドキュメントを調査した。

---

## 重要な発見

### 1. `conversations.history` の仕様

**定義**: チャンネルの直下に投稿されたメッセージのリストを取得するメソッド

```
Slack チャンネルの実装構造:

┌─ 親メッセージ（ts=1000）
│  ├─ 返信（ts=2000）
│  ├─ 返信（ts=2001）
│  └─ 返信（ts=2002）
├─ 親メッセージ（ts=1001）
│  └─ 返信（ts=2003）
└─ 親メッセージ（ts=1002）
```

**critical point**: `conversations.history` は「親メッセージのみ」を返す。スレッド内の返信（2000, 2001 等）は**一切返されない**。

参照元: [Slack Developer Docs - conversations.history](https://docs.slack.dev/reference/methods/conversations.history)

### 2. なぜ「超古い親を見つけられない」のか

#### 時間フィルタの挙動

`conversations.history` のパラメータ：
- `oldest`: "このUnix timestamp 以降のメッセージを返す"
- `latest`: "このUnix timestamp 以前のメッセージを返す"

**重要**: これらのフィルタは **親メッセージの投稿時刻** に基づいて動作する。返信時刻は考慮されない。

#### 具体例

```
状況：
• 親メッセージ投稿: 2026-01-01 (ts=1000)
• 返信追加: 2026-05-08 (ts=2000)

クエリ：conversations.history(channel=C_XXX, oldest=1715161200)
        ↑ 2026-05-08 00:00:00 UTC 以降のメッセージを取得

結果：
  ❌ 返されない
  理由: 親は 2026-01-01 投稿 → フィルタ条件に合わない
       （返信が 5月 にあっても、「親」が 1月 なので除外）
```

#### Slack API のテーブル

| 項目 | 動作 |
|-----|------|
| 親メッセージの投稿時刻 | ✅ フィルタ対象 |
| 返信の投稿時刻 | ❌ フィルタに関係ない |
| スレッドの「更新時刻」概念 | ❌ API に存在しない |

### 3. `conversations.replies` の仕様

**定義**: 特定スレッド内の全メッセージ（親+返信）を取得するメソッド

パラメータ：
- `channel`: チャンネルID（必須）
- `ts`: スレッド親のタイムスタンプ（必須）
- `oldest`: Unix timestamp（オプション、時間フィルタ可能）
- `latest`: Unix timestamp（オプション）

**戻り値**: 親メッセージ + スレッド内の全返信

参照元: [Slack Developer Docs - conversations.replies](https://docs.slack.dev/reference/methods/conversations.replies)

---

## なぜ「監視スレッド一覧」（案A）が必要なのか

### シンプル案の限界

```pseudocode
【毎回のポーリング】
conversations.history(oldest=lastCheck)
  ↓ 結果
  新着親メッセージ: ✅ 拾える
  古い親の新着返信: ❌ 見落とされる
```

**理由**: 古い親はフィルタで除外されるため、その親のスレッドに新着返信があっても検知できない。

### 案A（推奨）の構造

```pseudocode
【毎回のポーリング】

Step 1. 新着親を探す
  conversations.history(oldest=lastCheck)
  → 新しく投稿された親メッセージを取得 ✅

Step 2. 既存スレッドの新着返信を探す
  for each thread_ts in monitored_threads:  // ← sessions.json から取得
    conversations.replies(ts=thread_ts, oldest=lastCheck)
    → 各スレッドの新着返信を取得 ✅
```

**利点**:
- 「古い親、新しい返信」ケースを完全に拾える
- スレッド ts は管理下にあるので、API コスト予測可能
- `sessions.json` の既存設計と相性が良い

---

## Slack API の設計哲学

ユーザーの直感：「スレッドに新着返信があれば、updated_at で新着に上がってくるのでは？」

→ **Slack API はそう設計されていない。** 理由は：

1. `conversations.history` は「チャンネルの直下」という「レイヤー」を表す設計
2. スレッドはその「レイヤーの下の別世界」として分離されている
3. 返信の追加は親の「メタデータ」（`reply_count`）は増やすが、履歴取得には反映されない

つまり、スレッド返信を確実に拾うには **能動的なアクション** が必要。これが案A の本質。

---

## 実装への影響

### `claude-connector` （Go） への適用

現在の `LocalPlatform.FetchNewMessages()` は fixture を読むため、この制限を受けない。

しかし本番環境の `SlackPlatform.FetchNewMessages()` 実装では、以下の 2 フェーズが必須：

```go
// Phase 1: 新着親メッセージを取得
newParents := conversationsHistory(channel, oldest=lastCheck)

// Phase 2: 既存スレッドの新着返信を取得
monitoredThreads := loadSessionThreads()  // sessions.json から読む
for _, threadTS := range monitoredThreads {
  newReplies := conversationsReplies(channel, threadTS, oldest=lastCheck)
  // 返信を処理
}
```

### `sessions.json` への拡張

現在:
```json
{
  "channel:thread_ts": {
    "claude_session_id": "sess_xxx"
  }
}
```

推奨される拡張:
```json
{
  "channel:thread_ts": {
    "claude_session_id": "sess_xxx",
    "last_reply_checked_ts": 1715161200
  }
}
```

---

## 結論

| 項目 | 判定 |
|-----|------|
| `conversations.history` でスレッド返信を取得可能？ | ❌ 不可 |
| `conversations.replies` で既知スレッドの返信を時間フィルタで取得可能？ | ✅ 可能 |
| 「古い親、新しい返信」を自動的に検知できる API は存在？ | ❌ 存在しない |
| 案A（監視スレッド一覧）が必須？ | ✅ 必須 |

`slack-thread-polling-notes.md` で提案された案A は、**Slack API の設計の現実に対する最適なアプローチ** である。
