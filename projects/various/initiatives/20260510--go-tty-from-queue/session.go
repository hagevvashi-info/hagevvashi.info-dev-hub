package main

import (
	"fmt"
	"os"
	"strings"
	"sync"
	"time"
)

type SessionManager struct {
	Mu       sync.Mutex
	sessions map[string]*AgentSession
	store    *SessionStore
}

type AgentSession struct {
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

func (sm *SessionManager) getOrCreateUnsafe(m Message) (*AgentSession, bool, error) {
	key, err := m.ThreadKey()
	if err != nil {
		return nil, false, err
	}

	now := time.Now()
	isThreadRoot := m.IsThreadRoot()

	// セッション取得パターン：
	// | IsThreadRoot | セッション存在 | 動作       | 戻り値     |
	// |--------------|----------------|-----------|----------|
	// | true         | あり/なし      | 新規作成   | (s, true)  |
	// | false        | あり           | 既存再利用 | (s, false) |
	// | false        | なし           | 新規作成   | (s, true)  |
	if s, ok := sm.sessions[key]; ok && !isThreadRoot {
		s.LastUsedAt = now
		return s, false, nil
	}

	s := &AgentSession{
		ThreadKey:  key,
		AgentType:  strings.ToLower(m.AgentType),
		CreatedAt:  now,
		LastUsedAt: now,
		// SessionID は Agent 実行時に返される ID で後から更新される
	}
	sm.sessions[key] = s
	if err := sm.persistLocked(); err != nil {
		fmt.Fprintf(os.Stderr, "Warning: failed to persist session %s: %v\n", key, err)
	}
	return s, true, nil
}

func (s *AgentSession) Touch() {
	s.LastUsedAt = time.Now()
}

func (sm *SessionManager) updateSessionIDUnsafe(threadKey string, sessionID string) {
	if strings.TrimSpace(threadKey) == "" || strings.TrimSpace(sessionID) == "" {
		return
	}
	s, ok := sm.sessions[threadKey]
	if !ok {
		return
	}
	s.SessionID = sessionID
	s.LastUsedAt = time.Now()
	if err := sm.persistLocked(); err != nil {
		fmt.Fprintf(os.Stderr, "Warning: failed to persist session %s: %v\n", threadKey, err)
	}
}

func (sm *SessionManager) loadFromStore() error {
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

func (sm *SessionManager) persistLocked() error {
	if sm.store == nil {
		return nil
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
	return sm.store.Save(records)
}
