package main

import (
	"fmt"
	"strings"
)

type Bridge struct {
	Platform Platform
	Sessions *SessionManager
}

func (b *Bridge) Execute(msg Message) {
	fmt.Printf("👷 [Bridge] 開始: %s (Agent: %s)\n", msg.ID, msg.AgentType)

	if b.Sessions == nil {
		b.Sessions = NewSessionManager(NewSessionStore(""))
	}
	session, created, err := b.Sessions.GetOrCreate(msg)
	if err != nil {
		b.Platform.PostResponse(msg, "❌ セッション初期化に失敗しました: "+err.Error())
		return
	}
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
		return
	}

	session.mu.Lock()
	defer session.mu.Unlock()

	resume := session.ClaudeSessionID
	if created {
		resume = ""
	}
	if resume != "" && !msg.IsThreadRoot() {
		fmt.Printf("🔁 [Bridge] 既存セッションへ投げます: session_id=%s thread=%s\n", resume, msg.ThreadTS)
	}
	result, sessionID, err := agent.Run(msg.Content, resume)
	if err != nil {
		b.Platform.PostResponse(msg, "❌ エラーが発生しました: "+err.Error())
		return
	}
	if sessionID != "" {
		session.ClaudeSessionID = sessionID
		if threadKey, err := msg.ThreadKey(); err == nil {
			b.Sessions.UpdateClaudeSessionID(threadKey, sessionID)
		}
	}
	session.Touch()

	b.Platform.PostResponse(msg, result)
	b.Platform.MarkProcessed(msg.ID)
}
