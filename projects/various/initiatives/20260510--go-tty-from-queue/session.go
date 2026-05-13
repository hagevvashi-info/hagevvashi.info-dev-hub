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

	SessionID string
}

func NewSessionManager(store *SessionStore) *SessionManager {
	sm := &SessionManager{
		// map[スレッドキー]*AgentSession
		// 例: {
		//   "C_LOCAL_CLAUDE:1715161200.000100": &AgentSession{
		//     ThreadKey: "C_LOCAL_CLAUDE:1715161200.000100",
		//     AgentType: "claude",
		//     SessionID: "e7f6d54b-7eb3-4156-b20e-f0322ca165ef",
		//     CreatedAt: 2026-05-10T21:07:41Z,
		//     LastUsedAt: 2026-05-10T21:17:15Z
		//   }
		// }
		sessions: map[string]*AgentSession{},
		store:    store,
	}
	_ = sm.loadFromStore()
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

func (sm *SessionManager) UpdateSessionID(threadKey string, sessionID string) {
	if strings.TrimSpace(threadKey) == "" || strings.TrimSpace(sessionID) == "" {
		return
	}
	sm.mu.Lock()
	defer sm.mu.Unlock()
	s, ok := sm.sessions[threadKey]
	if !ok {
		return
	}
	s.SessionID = sessionID
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
			ThreadKey:  k,
			AgentType:  r.AgentType,
			CreatedAt:  r.CreatedAt,
			LastUsedAt: r.LastUsedAt,
			SessionID:  r.SessionID,
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
			AgentType:  s.AgentType,
			CreatedAt:  s.CreatedAt,
			LastUsedAt: s.LastUsedAt,
			SessionID:  s.SessionID,
		}
	}
	_ = sm.store.Save(records)
}
