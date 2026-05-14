package session

import "time"

type Store interface {
	Load() (map[string]Record, error)
	Save(records map[string]Record) error
}

type Record struct {
	AgentType  string    `json:"agent_type"`
	CreatedAt  time.Time `json:"created_at"`
	LastUsedAt time.Time `json:"last_used_at"`
	SessionID  string    `json:"session_id"`
}
