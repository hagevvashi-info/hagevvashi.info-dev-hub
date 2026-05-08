package main

import (
	"encoding/json"
	"fmt"
	"os"
	"sort"
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
		return State{LastCheckTime: time.Now().Add(-1 * time.Hour)} // 初回は1時間前から
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
	bridge := &Bridge{Platform: platform, Sessions: NewSessionManager()}
	var wg sync.WaitGroup

	// スレッド単位でまとめて、スレッド内は順序を守って逐次実行する。
	// （メッセージ単位で並列化すると、返信が親より先に処理されてセッションが崩れる）
	byThread := map[string][]Message{}
	for _, msg := range messages {
		key, err := threadKeyFromMessage(msg)
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
		go func(threadMsgs []Message) {
			defer wg.Done()
			for _, m := range threadMsgs {
				bridge.Execute(m) // (C) に仕事を渡す
			}
		}(msgs)
	}

	wg.Wait() // すべてのジョブが終わるまで待機 (バッチとしての責任)

	// 4. 状態の更新
	state.LastCheckTime = now
	saveState(state)

	fmt.Println("✅ All jobs finished.")
}
