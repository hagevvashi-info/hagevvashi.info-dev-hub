package main

import (
	"fmt"
	"os"
	"sort"
	"strings"
	"sync"
)

func main() {
	var source QueueSource
	switch os.Getenv("APP_ENV") {
	case "production":
		spreadsheetID := os.Getenv("SPREADSHEET_ID")
		source = NewSheetQueueSource(spreadsheetID)
	default:
		source = NewLocalQueueSource("")
	}

	platform := NewQueuePlatform(source)

	messages, err := platform.FetchNewMessages()
	if err != nil {
		fmt.Printf("Error fetching messages: %v\n", err)
		return
	}

	if len(messages) == 0 {
		fmt.Println("✅ No pending messages.")
		return
	}

	fmt.Printf("📨 取得したメッセージ数: %d\n", len(messages))

	bridge := &Bridge{Platform: platform, Sessions: NewSessionManager(NewSessionStore(""))}
	var wg sync.WaitGroup

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

			if len(threadMsgs) == 1 {
				bridge.Execute(threadMsgs[0])
				return
			}

			channelID, threadTS := splitThreadKey(threadKey)
			last := threadMsgs[len(threadMsgs)-1]
			combined := Message{
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

	wg.Wait()

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
	sep := "\n\n---\n\n"
	out := make([]string, 0, len(msgs))
	for _, m := range msgs {
		out = append(out, m.Content)
	}
	return strings.Join(out, sep)
}
