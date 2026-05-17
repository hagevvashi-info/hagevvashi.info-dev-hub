package platform

import (
	"fmt"
	"strings"
	"time"

	"go-tty-from-queue/internal/message"
	"go-tty-from-queue/internal/queue"
)

const AGENT_USER_ID = "U0K4HRSJ2"

type QueuePlatform struct {
	source queue.Source
}

func NewQueue(source queue.Source) *QueuePlatform {
	return &QueuePlatform{source: source}
}

func (p *QueuePlatform) FetchNewMessages() ([]message.Message, error) {
	fmt.Println("🔍 [Queue] pending メッセージを取得します...")

	entries, err := p.source.Read()
	if err != nil {
		return nil, err
	}

	var messages []message.Message
	for _, entry := range entries {
		if entry.Status != "pending" {
			continue
		}

		if entry.UserID == AGENT_USER_ID {
			continue
		}

		if strings.HasPrefix(entry.UserID, "B_") {
			continue
		}

		timestamp, err := time.Parse(time.RFC3339, entry.Time)
		if err != nil {
			timestamp = time.Now()
		}

		msg := message.Message{
			ID:        entry.MessageTS,
			AgentType: entry.AgentType,
			Content:   entry.Text,
			Timestamp: timestamp,
			ChannelID: entry.Channel,
			ThreadTS:  entry.ThreadTS,
			ReplyCount: 0,
		}

		messages = append(messages, msg)
	}

	return messages, nil
}

func (p *QueuePlatform) PostResponse(original message.Message, response string) error {
	fmt.Printf("📢 [Queue Post] channel: %s ID: %s (thread_ts: %s) への返信:\n%s\n\n",
		original.ChannelID, original.ID, original.ThreadTS, response)
	return nil
}

func (p *QueuePlatform) MarkProcessed(messageID string) error {
	entries, err := p.source.Read()
	if err != nil {
		return err
	}

	for i := range entries {
		if entries[i].MessageTS == messageID {
			entries[i].Status = "completed"
			break
		}
	}

	return p.source.Write(entries)
}
