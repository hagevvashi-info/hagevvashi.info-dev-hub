package main

import (
	"fmt"
	"strings"
)

type Bridge struct {
	Platform Platform
	Sessions *SessionManager
}

func (b *Bridge) ExecuteUnsafe(msg Message, session *AgentSession, created bool) error {
	fmt.Printf("👷 [Bridge] 開始: %s (Agent: %s)\n", msg.ID, msg.AgentType)

	if created && !msg.IsThreadRoot() {
		fmt.Printf("⚠️ [Bridge] セッション喪失のため新規作成: thread=%s\n", msg.ThreadTS)
	}

	var agent Agent
	switch strings.ToLower(msg.AgentType) {
	case "gemini":
		agent = &GeminiAgent{}
	case "claude":
		agent = &ClaudeAgent{}
	default:
		b.Platform.PostResponse(msg, fmt.Sprintf("❌ 未対応の AgentType です: %q", msg.AgentType))
		return nil
	}

	resume := session.SessionID
	if created {
		resume = ""
	}
	if resume != "" && !msg.IsThreadRoot() {
		fmt.Printf("🔁 [Bridge] 既存セッションへ投げます: session_id=%s thread=%s\n", resume, msg.ThreadTS)
	}
	result, sessionID, err := agent.Run(msg.Content, resume)
	if err != nil {
		b.Platform.PostResponse(msg, "❌ エラーが発生しました: "+err.Error())
		return nil
	}
	if sessionID != "" {
		session.SessionID = sessionID
		if threadKey, err := msg.ThreadKey(); err == nil {
			b.Sessions.updateSessionIDUnsafe(threadKey, sessionID)
		}
	}
	session.Touch()

	b.Platform.PostResponse(msg, result)
	b.Platform.MarkProcessed(msg.ID)
	return nil
}

func (b *Bridge) ExecuteSafe(msg Message) {
	b.Sessions.Mu.Lock()
	session, created, err := b.Sessions.getOrCreateUnsafe(msg)
	b.Sessions.Mu.Unlock()

	if err != nil {
		b.Platform.PostResponse(msg, "❌ セッション初期化に失敗しました: "+err.Error())
		return
	}

	b.ExecuteUnsafe(msg, session, created)
}
