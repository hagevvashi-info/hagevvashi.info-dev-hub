package main

import (
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strings"
	"sync"
	"time"
)

type State struct {
	LastCheckTime time.Time `json:"last_check_time"`
}

const stateFile = "state.json"

func loadState() State {
	data, err := os.ReadFile(stateFile)
	if err != nil {
		// 初回は過去30日分を拾う（ローカルfixtureのtsが古くても動作確認できるように）
		return State{LastCheckTime: time.Now().Add(-30 * 24 * time.Hour)}
	}
	var s State
	json.Unmarshal(data, &s)
	return s
}

func saveState(s State) {
	data, _ := json.Marshal(s)
	os.WriteFile(stateFile, data, 0644)
}

func main() {
	env := os.Getenv("APP_ENV")
	var platform Platform = &LocalPlatform{}

	if env == "production" {
		platform = &SlackPlatform{Token: os.Getenv("SLACK_TOKEN")}
	}

	// 1. 状態の読み込み (前回いつチェックしたか)
	state := loadState()
	now := time.Now()

	// 2. 新着メッセージの取得 (B-i, ii)
	messages, err := platform.FetchNewMessages(state.LastCheckTime)
	if err != nil {
		fmt.Printf("Error fetching messages: %v\n", err)
		return
	}

	// 3. 並列実行 (B-iii, iv)
	bridge := &Bridge{Platform: platform, Sessions: NewSessionManager(NewSessionStore(""))}
	var wg sync.WaitGroup

	// スレッド単位でまとめて、スレッド内は順序を守って逐次実行する。
	// （メッセージ単位で並列化すると、返信が親より先に処理されてセッションが崩れる）
	byThread := map[string][]Message{}
	for _, msg := range messages {
		key, err := msg.ThreadKey()
		if err != nil {
			fmt.Printf("Error building thread key: %v\n", err)
			continue
		}
		byThread[key] = append(byThread[key], msg)
	}

	threadKeys := make([]string, 0, len(byThread))
	for k := range byThread {
		threadKeys = append(threadKeys, k)
	}
	sort.Strings(threadKeys)

	for _, key := range threadKeys {
		msgs := byThread[key]
		sort.Slice(msgs, func(i, j int) bool { return msgs[i].Timestamp.Before(msgs[j].Timestamp) })

		wg.Add(1)
		go func(threadKey string, threadMsgs []Message) {
			defer wg.Done()
			// 同一スレッド内に複数メッセージが溜まっていた場合は、結合して 1 回で投げる。
			// （前回チェック〜今回チェックの間に「返信が連続で来た」ケースを想定）
			if len(threadMsgs) == 1 {
				bridge.Execute(threadMsgs[0]) // (C) に仕事を渡す
				return
			}

			channelID, threadTS := splitThreadKey(threadKey)
			last := threadMsgs[len(threadMsgs)-1]
			combined := Message{
				// スレッド内バッチを 1 回で投げるときは、セッション開始点としてスレッドトップ扱いに寄せる
				// （thread_ts と同じ ID にして IsThreadRoot() を満たす）
				ID:        threadTS,
				AgentType: last.AgentType,
				Content:   joinThreadContents(threadMsgs),
				Timestamp: last.Timestamp,
				ChannelID: channelID,
				ThreadTS:  threadTS,
			}
			bridge.Execute(combined)
		}(key, msgs)
	}

	wg.Wait() // すべてのジョブが終わるまで待機 (バッチとしての責任)

	// 4. 状態の更新
	state.LastCheckTime = now
	saveState(state)

	fmt.Println("✅ All jobs finished.")
}

func splitThreadKey(key string) (channelID string, threadTS string) {
	parts := strings.SplitN(key, ":", 2)
	if len(parts) != 2 {
		return "", ""
	}
	return parts[0], parts[1]
}

func joinThreadContents(msgs []Message) string {
	// まずは安全側に倒して、区切りは Markdown 的にも見やすい水平線にする。
	// Slack の引用っぽくしたい場合は ">" 形式にする等もあり。
	sep := "\n\n---\n\n"
	out := make([]string, 0, len(msgs))
	for _, m := range msgs {
		out = append(out, m.Content)
	}
	return strings.Join(out, sep)
}
