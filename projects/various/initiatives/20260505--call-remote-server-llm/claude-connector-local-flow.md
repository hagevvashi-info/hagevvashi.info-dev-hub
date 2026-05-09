# claude-connector (Local Mode) 実行フローまとめ

対象コード: `projects/various/initiatives/20260507--go-tty/claude-connector/`

このメモは「`state.json` が無い状態で `go run .` したとき」に、
どの JSON が参照され、どの文字列が Agent に投げられ、返事がどこに出るかをソースコードベースで追ったもの。

## 1. モード判定

エントリポイントは `main.go`。

- `APP_ENV` が `"production"` のとき: `SlackPlatform` を使う
- それ以外: `LocalPlatform` を使う

該当: `main.go` の `main()`

## 2. `state.json` が無い場合の `lastCheck`

`loadState()` は `state.json` を読み、無ければデフォルトを返す。

- `state.json` が無い場合: `LastCheckTime = time.Now().Add(-30 * 24 * time.Hour)`

該当: `main.go` の `loadState()`

次に `platform.FetchNewMessages(state.LastCheckTime)` が呼ばれ、`lastCheck` が「新着判定」に使われる。

## 3. Local で参照される JSON ファイル

`LocalPlatform.FetchNewMessages(lastCheck)` は `config.json` を読み、チャンネル一覧を得る。

- 設定: `config.json`
  - 例: `channels[].id` が `C_LOCAL_CLAUDE`、`channels[].agent_type` が `claude`

該当: `config.go` の `loadConfig()`

### 3.1 history fixture

各チャンネルIDについて、まず次のファイルを読む。

- `fixtures/conversations_history_<CHANNEL_ID>.json`
  - 例: `fixtures/conversations_history_C_LOCAL_CLAUDE.json`

該当: `platform.go` の `LocalPlatform.FetchNewMessages()`

読み込んだ JSON は `SlackConversationsHistoryResponse` に `json.Unmarshal` され、
`ConvertSlackConversationsHistoryToMessages(channelID, agentType, history)` に渡されて `[]Message` に変換される。

該当:
- 型: `slack_types.go`
- 変換: `slack_convert.go`

変換時のポイント（正規化）:
- `Message.ThreadTS` は必ず埋める（`thread_ts` が空なら `ts` を入れる）
- `Message.ID` は Slack の `ts`
- `Message.ChannelID` は config のチャンネルID
- `Message.AgentType` は config の `agent_type`（`claude` / `gemini`）

### 3.2 replies fixture（スレッドがある場合）

history で「スレッドトップ」かつ `reply_count > 0` のメッセージがあれば、追加で replies fixture を読む。

- 条件: `m.IsThreadRoot() && m.ReplyCount > 0`
  - `IsThreadRoot()` は `ThreadTS == ID`（= `thread_ts` が自分の `ts` と同じ）
- replies fixture: `fixtures/conversations_replies_<CHANNEL_ID>_<THREAD_TS>.json`
  - 例: `fixtures/conversations_replies_C_LOCAL_CLAUDE_1778292720.000100.json`

該当: `platform.go` の `LocalPlatform.FetchNewMessages()`

読み込んだ JSON は `SlackConversationsRepliesResponse` に `json.Unmarshal` され、
`ConvertSlackConversationsRepliesToMessages(channelID, agentType, threadTS, replies)` に渡されて `[]Message` に変換される。

注意:
- replies のレスポンスは root（スレッドトップ）も含むので、Local は root を除外して追加している。

## 4. 新着判定（`lastCheck`）と並び順

Local は history + replies を集めた後、次を実施する。

1. `m.Timestamp.After(lastCheck)` のものだけに絞る（= 新着判定）
2. `Timestamp` 昇順でソートして返す

該当: `platform.go` の `LocalPlatform.FetchNewMessages()`

## 5. スレッド単位のまとめ（複数メッセージを 1 回に結合）

`main.go` は `messages` をスレッド単位でまとめる。

- スレッドキー: `Message.ThreadKey()` = `ChannelID + ":" + ThreadTS`

そして同一スレッドで複数件あった場合は、結合して 1 つの `Message` にしてから `bridge.Execute()` に渡す。

- 結合のセパレータ: `\n\n---\n\n`
- 結合後の `Message` は「スレッドトップ扱い」に寄せるため、`ID = ThreadTS` にしている
  - これにより `IsThreadRoot()` が true になり、セッションが新規作成される

該当: `main.go` の「スレッド単位でまとめて…」以降、`joinThreadContents()`

## 6. どの文字列が Agent に投げられるか

`Bridge.Execute(msg)` で最終的に Agent を呼ぶ。

- 呼び出し: `agent.Run(msg.Content, resumeSessionID)`
- つまり **Agent に投げる文字列は `Message.Content`**
  - スレッド内で複数件溜まっていた場合は、前段で `Content` が `---` 区切りで結合された文字列になる

該当: `bridge.go` の `Bridge.Execute()`

## 7. セッションの紐付け（スレッド ↔ Claude session_id）

`SessionManager` はスレッドキー（`ChannelID:ThreadTS`）でセッションを管理し、`sessions.json` に永続化する。

- 新規セッションになる条件:
  - `Message.IsThreadRoot() == true` のときは問答無用で新規（既存があっても置換）
- 既存セッションを使う条件:
  - スレッド返信（`IsThreadRoot()==false`）の場合は既存を優先
- Claude 側セッション再開:
  - `ClaudeSessionID` があると `claude --resume <session_id> ...` で投げる

該当:
- `session.go` / `session_store.go`
- `bridge.go`（`resume := session.ClaudeSessionID`、`UpdateClaudeSessionID(...)`）
- `agent.go`（`--resume` を args に入れる）

## 8. 返事（エージェントの出力）はどこに出るか

Local モードでは `LocalPlatform.PostResponse()` が `fmt.Printf()` で標準出力へ出す。

- 出力先: **stdout**
- フォーマット: `📢 [Local Post] ... への返信:\n<response>`

該当: `platform.go` の `LocalPlatform.PostResponse()`

補足:
- `Bridge.Execute()` 自体も `👷 [Bridge] ...` や `🔁 [Bridge] ...` を stdout に出す。
- Slack 本番では `SlackPlatform.PostResponse()` が `chat.postMessage` を呼ぶ（`slack_api.go`）。

## 9. 実行後に更新されるファイル

`go run .` が最後まで動くと、次が更新される。

- `state.json`
  - `last_check_time` が `now`（実行開始時刻）に更新される
  - 該当: `main.go` の `saveState()`
- `sessions.json`
  - スレッドキー → Claude `session_id` の紐付けが保存される
  - 該当: `session_store.go`

