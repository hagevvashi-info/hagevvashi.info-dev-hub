package session

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
)

const (
	sessionKeyPrefix = "session:"
	sessionTTL       = 24 * time.Hour
)

type RedisStore struct {
	client *redis.Client
}

func NewRedisStore(addr string) (*RedisStore, error) {
	if addr == "" {
		return nil, fmt.Errorf("Redis address is required")
	}
	client := redis.NewClient(&redis.Options{
		Addr: addr,
	})
	return &RedisStore{client: client}, nil
}

func (s *RedisStore) Load() (map[string]Record, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	keys, err := s.client.Keys(ctx, sessionKeyPrefix+"*").Result()
	if err != nil {
		return nil, fmt.Errorf("failed to fetch session keys: %w", err)
	}

	records := make(map[string]Record)
	for _, key := range keys {
		threadKey := key[len(sessionKeyPrefix):]

		data, err := s.client.Get(ctx, key).Result()
		if err != nil {
			return nil, fmt.Errorf("failed to load session %s: %w", threadKey, err)
		}

		var record Record
		if err := json.Unmarshal([]byte(data), &record); err != nil {
			return nil, fmt.Errorf("failed to parse session %s: %w", threadKey, err)
		}

		records[threadKey] = record
	}

	return records, nil
}

func (s *RedisStore) Save(records map[string]Record) error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if records == nil {
		records = map[string]Record{}
	}

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
