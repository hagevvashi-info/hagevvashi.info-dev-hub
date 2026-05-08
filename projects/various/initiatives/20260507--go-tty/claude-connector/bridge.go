package main

import (
	"fmt"
	"strings"
)

// Bridge は特定のメッセージに対して Agent を実行し、結果を報告する
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
		// 返信なのにセッションが無かった（喪失）ケース
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

	// 同一スレッドは逐次実行に寄せる（セッション状態と履歴の整合性のため）
	session.mu.Lock()
	defer session.mu.Unlock()

	// エージェント実行
	resume := session.ClaudeSessionID
	if created {
		// 新規セッション開始
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

	// プラットフォームへ返信
	b.Platform.PostResponse(msg, result)
}
