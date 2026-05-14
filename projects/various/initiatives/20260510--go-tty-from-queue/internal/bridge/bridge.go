package bridge

import (
	"fmt"
	"strings"

	"go-tty-from-queue/internal/agent"
	"go-tty-from-queue/internal/message"
	"go-tty-from-queue/internal/platform"
	"go-tty-from-queue/internal/session"
)

type Bridge struct {
	Platform platform.Platform
	Sessions session.Manager
}

func (b *Bridge) Execute(msg message.Message, sess *session.AgentSession, created bool) error {
	fmt.Printf("👷 [Bridge] 開始: %s (Agent: %s)\n", msg.ID, msg.AgentType)

	if created && !msg.IsThreadRoot() {
		fmt.Printf("⚠️ [Bridge] セッション喪失のため新規作成: thread=%s\n", msg.ThreadTS)
	}

	var agt agent.Agent
	switch strings.ToLower(msg.AgentType) {
	case "gemini":
		agt = &agent.Gemini{}
	case "claude":
		agt = &agent.Claude{}
	default:
		b.Platform.PostResponse(msg, fmt.Sprintf("❌ 未対応の AgentType です: %q", msg.AgentType))
		return nil
	}

	resume := sess.SessionID
	if created {
		resume = ""
	}
	if resume != "" && !msg.IsThreadRoot() {
		fmt.Printf("🔁 [Bridge] 既存セッションへ投げます: session_id=%s thread=%s\n", resume, msg.ThreadTS)
	}
	result, sessionID, err := agt.Run(msg.Content, resume)
	if err != nil {
		b.Platform.PostResponse(msg, "❌ エラーが発生しました: "+err.Error())
		return nil
	}
	if sessionID != "" {
		sess.SessionID = sessionID
		if threadKey, err := msg.ThreadKey(); err == nil {
			b.Sessions.UpdateSessionID(threadKey, sessionID)
		}
	}

	b.Platform.PostResponse(msg, result)
	b.Platform.MarkProcessed(msg.ID)
	return nil
}
