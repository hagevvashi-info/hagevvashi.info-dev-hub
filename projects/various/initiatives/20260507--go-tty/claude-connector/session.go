package main

import (
	"fmt"
	"strings"
	"sync"
	"time"
)

type SessionManager struct {
	mu       sync.Mutex
	sessions map[string]*AgentSession
}

type AgentSession struct {
	mu sync.Mutex

	ThreadKey  string
	AgentType  string
	CreatedAt  time.Time
	LastUsedAt time.Time

	// Claude Code CLI の session_id (claude -p --output-format json の返り値)
	ClaudeSessionID string
}

func NewSessionManager() *SessionManager {
	return &SessionManager{
		sessions: map[string]*AgentSession{},
	}
}

func threadKeyFromMessage(m Message) (string, error) {
	if strings.TrimSpace(m.ChannelID) == "" {
		return "", fmt.Errorf("ChannelID is empty")
	}
	threadTS := strings.TrimSpace(m.ThreadTS)
	if threadTS == "" {
		// 非スレッドメッセージは「そのメッセージを親にしたスレッド」として扱う
		threadTS = strings.TrimSpace(m.ID)
	}
	if threadTS == "" {
		return "", fmt.Errorf("message id is empty")
	}
	return m.ChannelID + ":" + threadTS, nil
}

func isThreadRoot(m Message) bool {
	// Slack: スレッドトップは thread_ts == ts になりがち。history の通常メッセージは thread_ts が空。
	if m.ThreadTS == "" {
		return true
	}
	return m.ThreadTS == m.ID
}

func (sm *SessionManager) GetOrCreate(m Message) (*AgentSession, bool, error) {
	key, err := threadKeyFromMessage(m)
	if err != nil {
		return nil, false, err
	}

	sm.mu.Lock()
	defer sm.mu.Unlock()

	now := time.Now()

	// スレッドトップなら問答無用で新規セッション（既存があれば置き換え）
	if isThreadRoot(m) {
		s := &AgentSession{
			ThreadKey:  key,
			AgentType:  strings.ToLower(m.AgentType),
			CreatedAt:  now,
			LastUsedAt: now,
		}
		sm.sessions[key] = s
		return s, true, nil
	}

	// スレッド返信なら既存セッションを優先。無ければ新規作成して紐付け。
	if s, ok := sm.sessions[key]; ok {
		s.LastUsedAt = now
		return s, false, nil
	}
	s := &AgentSession{
		ThreadKey:  key,
		AgentType:  strings.ToLower(m.AgentType),
		CreatedAt:  now,
		LastUsedAt: now,
	}
	sm.sessions[key] = s
	return s, true, nil
}

func (s *AgentSession) Touch() {
	s.LastUsedAt = time.Now()
}
