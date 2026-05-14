package session

import (
	"fmt"
	"os"
	"strings"
	"sync"
	"time"

	"go-tty-from-queue/internal/message"
)

type Manager interface {
	Lock()
	Unlock()
	GetOrCreateUnsafe(msg message.Message) (*AgentSession, bool, error)
	UpdateSessionIDUnsafe(threadKey, sessionID string)
}

type AgentSession struct {
	ThreadKey  string
	AgentType  string
	CreatedAt  time.Time
	LastUsedAt time.Time
	SessionID  string
}

type ManagerImpl struct {
	Mu       sync.Mutex
	sessions map[string]*AgentSession
	store    Store
}

func NewManager(store Store) *ManagerImpl {
	sm := &ManagerImpl{
		sessions: map[string]*AgentSession{},
		store:    store,
	}
	_ = sm.loadFromStore()
	return sm
}

func (sm *ManagerImpl) Lock() {
	sm.Mu.Lock()
}

func (sm *ManagerImpl) Unlock() {
	sm.Mu.Unlock()
}

func (sm *ManagerImpl) GetOrCreateUnsafe(msg message.Message) (*AgentSession, bool, error) {
	key, err := msg.ThreadKey()
	if err != nil {
		return nil, false, err
	}

	now := time.Now()
	isThreadRoot := msg.IsThreadRoot()

	if s, ok := sm.sessions[key]; ok && !isThreadRoot {
		s.LastUsedAt = now
		return s, false, nil
	}

	s := &AgentSession{
		ThreadKey:  key,
		AgentType:  strings.ToLower(msg.AgentType),
		CreatedAt:  now,
		LastUsedAt: now,
	}
	sm.sessions[key] = s
	if err := sm.persistLocked(); err != nil {
		fmt.Fprintf(os.Stderr, "Warning: failed to persist session %s: %v\n", key, err)
	}
	return s, true, nil
}

func (sm *ManagerImpl) UpdateSessionIDUnsafe(threadKey string, sessionID string) {
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

func (sm *ManagerImpl) loadFromStore() error {
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

func (sm *ManagerImpl) persistLocked() error {
	if sm.store == nil {
		return nil
	}
	records := map[string]Record{}
	for k, s := range sm.sessions {
		records[k] = Record{
			AgentType:  s.AgentType,
			CreatedAt:  s.CreatedAt,
			LastUsedAt: s.LastUsedAt,
			SessionID:  s.SessionID,
		}
	}
	return sm.store.Save(records)
}
