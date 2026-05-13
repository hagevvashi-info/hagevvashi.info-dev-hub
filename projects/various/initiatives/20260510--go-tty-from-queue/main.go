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
		if spreadsheetID == "" {
			fmt.Fprintf(os.Stderr, "Error: SPREADSHEET_ID environment variable is required in production mode\n")
			os.Exit(1)
		}
		source = NewSheetQueueSource(spreadsheetID)
	default:
		queueFile := os.Getenv("QUEUE_FILE")
		if queueFile == "" {
			fmt.Fprintf(os.Stderr, "Error: QUEUE_FILE environment variable is required\n")
			os.Exit(1)
		}
		source = NewLocalQueueSource(queueFile)
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

	bridge := &Bridge{Platform: platform, Sessions: NewSessionManager(NewSessionStore())}
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

			last := threadMsgs[len(threadMsgs)-1]
			combined := Message{
				ID:        last.ThreadTS,
				AgentType: last.AgentType,
				Content:   joinThreadContents(threadMsgs),
				Timestamp: last.Timestamp,
				ChannelID: last.ChannelID,
				ThreadTS:  last.ThreadTS,
			}
			bridge.Execute(combined)

			for _, msg := range threadMsgs {
				bridge.Platform.MarkProcessed(msg.ID)
			}
		}(key, msgs)
	}

	wg.Wait()

	fmt.Println("✅ All jobs finished.")
}

func joinThreadContents(msgs []Message) string {
	sep := "\n\n---\n\n"
	out := make([]string, 0, len(msgs))
	for _, m := range msgs {
		out = append(out, m.Content)
	}
	return strings.Join(out, sep)
}
