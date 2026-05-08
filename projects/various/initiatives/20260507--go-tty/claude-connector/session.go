package main

import (
	"strings"
	"sync"
	"time"
)

type SessionManager struct {
	mu       sync.Mutex
	sessions map[string]*AgentSession
	store    *SessionStore
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

func NewSessionManager(store *SessionStore) *SessionManager {
	sm := &SessionManager{
		sessions: map[string]*AgentSession{},
		store:    store,
	}
	if store != nil {
		_ = sm.loadFromStore()
	}
	return sm
}

func (sm *SessionManager) GetOrCreate(m Message) (*AgentSession, bool, error) {
	key, err := m.ThreadKey()
	if err != nil {
		return nil, false, err
	}

	sm.mu.Lock()
	defer sm.mu.Unlock()

	now := time.Now()

	// スレッドトップなら問答無用で新規セッション（既存があれば置き換え）
	if m.IsThreadRoot() {
		s := &AgentSession{
			ThreadKey:  key,
			AgentType:  strings.ToLower(m.AgentType),
			CreatedAt:  now,
			LastUsedAt: now,
		}
		sm.sessions[key] = s
		sm.persistLocked()
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
	sm.persistLocked()
	return s, true, nil
}

func (s *AgentSession) Touch() {
	s.LastUsedAt = time.Now()
}

func (sm *SessionManager) UpdateClaudeSessionID(threadKey string, sessionID string) {
	if strings.TrimSpace(threadKey) == "" || strings.TrimSpace(sessionID) == "" {
		return
	}
	sm.mu.Lock()
	defer sm.mu.Unlock()
	s, ok := sm.sessions[threadKey]
	if !ok {
		return
	}
	s.ClaudeSessionID = sessionID
	s.LastUsedAt = time.Now()
	sm.persistLocked()
}

func (sm *SessionManager) loadFromStore() error {
	sm.mu.Lock()
	defer sm.mu.Unlock()
	if sm.store == nil {
		return nil
	}
	records, err := sm.store.Load()
	if err != nil {
		return err
	}
	for k, r := range records {
		sm.sessions[k] = &AgentSession{
			ThreadKey:        k,
			AgentType:        r.AgentType,
			CreatedAt:        r.CreatedAt,
			LastUsedAt:       r.LastUsedAt,
			ClaudeSessionID:  r.ClaudeSessionID,
		}
	}
	return nil
}

func (sm *SessionManager) persistLocked() {
	if sm.store == nil {
		return
	}
	records := map[string]SessionRecord{}
	for k, s := range sm.sessions {
		records[k] = SessionRecord{
			AgentType:       s.AgentType,
			CreatedAt:       s.CreatedAt,
			LastUsedAt:      s.LastUsedAt,
			ClaudeSessionID: s.ClaudeSessionID,
		}
	}
	_ = sm.store.Save(records)
}
