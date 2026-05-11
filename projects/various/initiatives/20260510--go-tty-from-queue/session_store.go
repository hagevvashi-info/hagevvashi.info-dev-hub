package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"time"

	"github.com/redis/go-redis/v9"
)

const (
	sessionKeyPrefix = "session:"
	sessionTTL       = 24 * time.Hour
)

type SessionStore struct {
	client *redis.Client
}

type SessionRecord struct {
	AgentType       string    `json:"agent_type"`
	CreatedAt       time.Time `json:"created_at"`
	LastUsedAt      time.Time `json:"last_used_at"`
	ClaudeSessionID string    `json:"claude_session_id"`
}

func NewSessionStore() *SessionStore {
	addr := os.Getenv("REDIS_ADDR")
	if addr == "" {
		fmt.Fprintf(os.Stderr, "Error: REDIS_ADDR environment variable is required\n")
		os.Exit(1)
	}
	client := redis.NewClient(&redis.Options{
		Addr: addr,
	})
	return &SessionStore{client: client}
}

func (s *SessionStore) Load() (map[string]SessionRecord, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	// session: で始まる全キーを取得
	keys, err := s.client.Keys(ctx, sessionKeyPrefix+"*").Result()
	if err != nil {
		return nil, fmt.Errorf("failed to fetch session keys: %w", err)
	}

	records := make(map[string]SessionRecord)
	for _, key := range keys {
		// キーから threadKey を復元（"session:C_LOCAL_CLAUDE:xxx" → "C_LOCAL_CLAUDE:xxx"）
		threadKey := key[len(sessionKeyPrefix):]

		data, err := s.client.Get(ctx, key).Result()
		if err != nil {
			return nil, fmt.Errorf("failed to load session %s: %w", threadKey, err)
		}

		var record SessionRecord
		if err := json.Unmarshal([]byte(data), &record); err != nil {
			return nil, fmt.Errorf("failed to parse session %s: %w", threadKey, err)
		}

		records[threadKey] = record
	}

	return records, nil
}

func (s *SessionStore) Save(records map[string]SessionRecord) error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if records == nil {
		records = map[string]SessionRecord{}
	}

	// 全レコードを保存（TTL付き）
	for threadKey, record := range records {
		key := sessionKeyPrefix + threadKey
		data, err := json.Marshal(record)
		if err != nil {
			return fmt.Errorf("failed to marshal session %s: %w", threadKey, err)
		}

		if err := s.client.Set(ctx, key, data, sessionTTL).Err(); err != nil {
			return fmt.Errorf("failed to save session %s: %w", threadKey, err)
		}
	}

	return nil
}
