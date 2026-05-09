package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"
)

type Message struct {
	ID        string
	AgentType string
	Content   string
	Timestamp time.Time

	ChannelID string
	ThreadTS  string
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
	FetchNewMessages(lastCheck time.Time) ([]Message, error)
	PostResponse(original Message, response string) error
	MarkProcessed(messageID string) error
}

type LocalPlatform struct{}

func (p *LocalPlatform) FetchNewMessages(lastCheck time.Time) ([]Message, error) {
	fmt.Println("🔍 [Local] Queue から pending メッセージを取得します...")

	data, err := os.ReadFile("fixtures/queue.json")
	if err != nil {
		return nil, fmt.Errorf("failed to read queue.json: %w", err)
	}

	var entries []QueueEntry
	if err := json.Unmarshal(data, &entries); err != nil {
		return nil, fmt.Errorf("failed to parse queue.json: %w", err)
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

func (p *LocalPlatform) PostResponse(original Message, response string) error {
	fmt.Printf("📢 [Local Post] channel: %s ID: %s (thread_ts: %s) への返信:\n%s\n\n",
		original.ChannelID, original.ID, original.ThreadTS, response)
	return nil
}

func (p *LocalPlatform) MarkProcessed(messageID string) error {
	data, err := os.ReadFile("fixtures/queue.json")
	if err != nil {
		return fmt.Errorf("failed to read queue.json: %w", err)
	}

	var entries []QueueEntry
	if err := json.Unmarshal(data, &entries); err != nil {
		return fmt.Errorf("failed to parse queue.json: %w", err)
	}

	for i := range entries {
		if entries[i].MessageTS == messageID {
			entries[i].Status = "completed"
			break
		}
	}

	updated, err := json.MarshalIndent(entries, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal queue.json: %w", err)
	}

	if err := os.WriteFile("fixtures/queue.json", updated, 0644); err != nil {
		return fmt.Errorf("failed to write queue.json: %w", err)
	}

	return nil
}

type SheetsPlatform struct {
	SpreadsheetID string
}

func (p *SheetsPlatform) FetchNewMessages(lastCheck time.Time) ([]Message, error) {
	return nil, fmt.Errorf("SheetsPlatform is not implemented yet")
}

func (p *SheetsPlatform) PostResponse(original Message, response string) error {
	return fmt.Errorf("SheetsPlatform is not implemented yet")
}

func (p *SheetsPlatform) MarkProcessed(messageID string) error {
	return fmt.Errorf("SheetsPlatform is not implemented yet")
}
