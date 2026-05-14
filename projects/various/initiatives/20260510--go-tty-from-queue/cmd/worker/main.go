package main

import (
	"fmt"
	"log"
	"os"
	"sort"
	"strings"
	"sync"

	"go-tty-from-queue/internal/bridge"
	"go-tty-from-queue/internal/message"
	"go-tty-from-queue/internal/platform"
	"go-tty-from-queue/internal/queue"
	"go-tty-from-queue/internal/session"
)

func main() {
	var source queue.Source
	switch os.Getenv("APP_ENV") {
	case "production":
		spreadsheetID := os.Getenv("SPREADSHEET_ID")
		if spreadsheetID == "" {
			fmt.Fprintf(os.Stderr, "Error: SPREADSHEET_ID environment variable is required in production mode\n")
			os.Exit(1)
		}
		source = queue.NewSheets(spreadsheetID)
	default:
		queueFile := os.Getenv("QUEUE_FILE")
		if queueFile == "" {
			fmt.Fprintf(os.Stderr, "Error: QUEUE_FILE environment variable is required\n")
			os.Exit(1)
		}
		source = queue.NewLocal(queueFile)
	}

	redisAddr := os.Getenv("REDIS_ADDR")
	if redisAddr == "" {
		redisAddr = "localhost:6379"
	}
	store, err := session.NewRedisStore(redisAddr)
	if err != nil {
		log.Fatal(err)
	}

	plat := platform.NewQueue(source)
	messages, err := plat.FetchNewMessages()
	if err != nil {
		fmt.Printf("Error fetching messages: %v\n", err)
		return
	}

	if len(messages) == 0 {
		fmt.Println("✅ No pending messages.")
		return
	}

	fmt.Printf("📨 取得したメッセージ数: %d\n", len(messages))

	brg := &bridge.Bridge{
		Platform: plat,
		Sessions: session.NewManager(store),
	}
	var wg sync.WaitGroup

	byThread := map[string][]message.Message{}
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
		go func(threadKey string, threadMsgs []message.Message) {
			defer wg.Done()

			msg := threadMsgs[0]
			if len(threadMsgs) > 1 {
				last := threadMsgs[len(threadMsgs)-1]
				msg = message.Message{
					ID:        last.ThreadTS,
					AgentType: last.AgentType,
					Content:   joinThreadContents(threadMsgs),
					Timestamp: last.Timestamp,
					ChannelID: last.ChannelID,
					ThreadTS:  last.ThreadTS,
				}
			}

			brg.Sessions.Lock()
			sess, created, err := brg.Sessions.GetOrCreateUnsafe(msg)
			brg.Sessions.Unlock()

			if err != nil {
				brg.Platform.PostResponse(msg, "❌ セッション初期化に失敗しました: "+err.Error())
				return
			}

			brg.Execute(msg, sess, created)

			for _, origMsg := range threadMsgs {
				brg.Platform.MarkProcessed(origMsg.ID)
			}
		}(key, msgs)
	}

	wg.Wait()

	fmt.Println("✅ All jobs finished.")
}

func joinThreadContents(msgs []message.Message) string {
	sep := "\n\n---\n\n"
	out := make([]string, 0, len(msgs))
	for _, m := range msgs {
		out = append(out, m.Content)
	}
	return strings.Join(out, sep)
}
