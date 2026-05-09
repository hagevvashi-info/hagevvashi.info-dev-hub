package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

const sessionsFile = "sessions.json"

type SessionStore struct {
	Path string
}

type SessionRecord struct {
	AgentType       string    `json:"agent_type"`
	CreatedAt       time.Time `json:"created_at"`
	LastUsedAt      time.Time `json:"last_used_at"`
	ClaudeSessionID string    `json:"claude_session_id"`
}

func NewSessionStore(path string) *SessionStore {
	if path == "" {
		path = sessionsFile
	}
	return &SessionStore{Path: path}
}

func (s *SessionStore) Load() (map[string]SessionRecord, error) {
	data, err := os.ReadFile(s.Path)
	if err != nil {
		if os.IsNotExist(err) {
			return map[string]SessionRecord{}, nil
		}
		return nil, fmt.Errorf("failed to read %s: %w", s.Path, err)
	}
	var out map[string]SessionRecord
	if err := json.Unmarshal(data, &out); err != nil {
		return nil, fmt.Errorf("failed to parse %s: %w", s.Path, err)
	}
	if out == nil {
		out = map[string]SessionRecord{}
	}
	return out, nil
}

func (s *SessionStore) Save(records map[string]SessionRecord) error {
	if records == nil {
		records = map[string]SessionRecord{}
	}
	data, err := json.MarshalIndent(records, "", "  ")
	if err != nil {
		return err
	}
	tmp := s.Path + ".tmp"
	if err := os.WriteFile(tmp, data, 0644); err != nil {
		return fmt.Errorf("failed to write %s: %w", tmp, err)
	}
	if err := os.MkdirAll(filepath.Dir(s.Path), 0755); err != nil && filepath.Dir(s.Path) != "." {
		return err
	}
	if err := os.Rename(tmp, s.Path); err != nil {
		return fmt.Errorf("failed to replace %s: %w", s.Path, err)
	}
	return nil
}
