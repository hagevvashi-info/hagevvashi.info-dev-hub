package message

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
