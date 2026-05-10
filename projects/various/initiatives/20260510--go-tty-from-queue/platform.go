package main

import (
	"fmt"
	"strings"
	"time"
)

type Message struct {
	ID        string
	AgentType string
	Content   string
	Timestamp time.Time

	ChannelID  string
	ThreadTS   string
	ReplyCount int
}

func (m Message) ThreadKey() (string, error) {
	if strings.TrimSpace(m.ChannelID) == "" {
		return "", fmt.Errorf("ChannelID is empty")
	}
	if strings.TrimSpace(m.ThreadTS) == "" {
		return "", fmt.Errorf("ThreadTS is empty")
	}
	return m.ChannelID + ":" + m.ThreadTS, nil
}

func (m Message) IsThreadRoot() bool {
	return m.ThreadTS == m.ID
}

type Platform interface {
	FetchNewMessages() ([]Message, error)
	PostResponse(original Message, response string) error
	MarkProcessed(messageID string) error
}

// QueuePlatform は QueueSource から Queue を読み書きする
type QueuePlatform struct {
	source QueueSource
}

func NewQueuePlatform(source QueueSource) *QueuePlatform {
	return &QueuePlatform{source: source}
}

func (p *QueuePlatform) FetchNewMessages() ([]Message, error) {
	fmt.Println("🔍 [Queue] pending メッセージを取得します...")

	entries, err := p.source.Read()
	if err != nil {
		return nil, err
	}

	var messages []Message
	for _, entry := range entries {
		if entry.Status != "pending" {
			continue
		}

		timestamp, err := time.Parse(time.RFC3339, entry.Time)
		if err != nil {
			timestamp = time.Now()
		}

		msg := Message{
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

func (p *QueuePlatform) PostResponse(original Message, response string) error {
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
