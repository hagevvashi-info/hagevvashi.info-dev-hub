# Slack スレッド取得と「新着」判定メモ

このメモは、`projects/various/initiatives/20260507--go-tty/claude-connector/` の実装・fixture設計の議論から、
Slack Web API の制約と、実装方針の候補を整理したもの。

## 背景: やりたいこと

- 前回チェック時刻 `lastCheck` 以降の「新着メッセージ」を取りたい
- Slack にはスレッドがあるので、以下を漏らさず扱いたい
  - チャンネル直下の新着（親メッセージ）
  - 既存スレッドに付いた新着返信（親が古くても返信は新しい）
- 取得したメッセージをスレッド単位にグルーピングし、Agent セッション（Claude の `session_id`）と紐付けたい

## 重要な観察: `conversations.history` だけでは「返信」を拾えない

- `conversations.history` はチャンネルの履歴取得で、スレッド内のメッセージ取得は基本 `conversations.replies` を使う設計。
- `oldest`（= `lastCheck`）で絞ると、**親（スレッドトップ）が `oldest` より古い場合**、そのスレッドに新しい返信があっても検知できない問題が起き得る。
  - 直感的には「新着があるなら拾えるはず」だが、API都合で「親が範囲外＝そもそもスレッドを見つけられない」ことがある。

要するに「前回以降のメッセージをフラットに全件取ってからスレッドにグルーピング」したくても、
Slack API の都合で `history` 単独では成立しにくい。

## 現在のローカル実装（claude-connector 側）の設計メモ

`LocalPlatform.FetchNewMessages(lastCheck)` は fixture を以下の順で読む。

1. `config.json` からチャンネルIDと agent_type を読む
2. `fixtures/conversations_history_<CHANNEL_ID>.json` を読み、`[]Message` に変換
3. history で `reply_count > 0` のスレッドトップを見つけたら
   `fixtures/conversations_replies_<CHANNEL_ID>_<THREAD_TS>.json` を追加で読み、返信を `[]Message` に変換して追加
4. 最後に `Timestamp.After(lastCheck)` で新着だけにフィルタ
5. `Timestamp` 昇順でソートして返す

この方式はローカルfixtureでは成立するが、「本番 Slack API で oldest を絞る」と “親が古いが返信が新しい” を取りこぼす懸念が残る。

## 議論のポイント: どう取得するのが筋がいいか

ユーザーの直感（理想）:
- 「スレッドトップかどうかは問わず、created_at(ts)で前回以降の全メッセージを取る」→「それからスレッドにグルーピング」

実際の制約:
- `conversations.history` はスレッド返信を網羅しない（または oldest の範囲外の親スレッドは検知できない）。
- `conversations.replies` はスレッド単位の取得で、`oldest` を渡せるが、呼ぶには thread_ts（親の ts）が必要。

## 提案（設計候補）

### 案A: 監視スレッド一覧を持つ（推奨）

1. `conversations.history(channel, oldest=lastCheck)` で「チャンネル直下の新着（親）」を取得
2. 取得した親のうち `reply_count > 0` のものは `conversations.replies(channel, ts=thread_ts, oldest=lastCheck)` を呼び、返信の新着だけ取る
3. **別途**、すでに「監視対象」として登録済みの thread_ts については、親が古くても定期的に `conversations.replies(..., oldest=lastCheck)` を回して新着返信を拾う

監視対象スレッド（thread_ts）の管理方法（例）:
- 「Agent セッションを作ったスレッド」は監視対象に登録
- `sessions.json` / DB に `thread_ts -> last_seen_ts` を保存

長所:
- “親が古いが返信が新しい” を取りこぼさない
- 取得する thread_ts が管理下に入るので、コストが制御しやすい

短所:
- スレッド監視リスト（永続化）を設計・運用する必要がある

### 案B: history を広めに取る + latest_reply で検知

1. `conversations.history(channel, oldest=lastCheck - margin)` のようにマージンを持って広めに取る
2. 親メッセージの `latest_reply`（または `reply_count` の変化）で「このスレッドは最近動いた」と推測して `conversations.replies` を呼ぶ

長所:
- 監視スレッド一覧を持たなくても拾える範囲が増える

短所:
- margin を大きくすると history の取得量が増える
- それでも “親が超古いが最近返信” を完全に救える保証はない

### 案C: Events API（イベント駆動）

- Slack のイベント購読で返信イベントを受け、thread_ts を確実に把握して処理する

長所:
- ポーリングの取りこぼし問題が減る

短所:
- 運用・実装が一段重い（署名検証、受信エンドポイント、再送対策など）

## セッション紐付けのルール（合意したい前提）

- スレッド（channel_id + thread_ts）と Agent セッション（Claude `session_id`）は紐付く
  - スレッドトップ: 問答無用で新規セッション
  - スレッド返信: 既存セッションへ投げる
  - 既存セッション喪失時: 新規セッションを作り、スレッドに再紐付け

## ローカルfixture運用の補足（state の初期値問題）

- `state.json` が無い初回の `last_check_time` が「1時間前」だと、fixture の `ts` が古い場合にゼロ件になりうる
- 対策として「初回は30日前」など十分古い値にするか、ローカルだけ `lastCheck` を無視する/自動で `ts` をずらす等の選択肢がある

