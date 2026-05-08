package main

import (
	"fmt"
	"strings"
)

// Bridge は特定のメッセージに対して Agent を実行し、結果を報告する
type Bridge struct {
	Platform Platform
}

func (b *Bridge) Execute(msg Message) {
	fmt.Printf("👷 [Bridge] 開始: %s (Agent: %s)\n", msg.ID, msg.AgentType)

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

	// エージェント実行
	result, err := agent.Run(msg.Content)
	if err != nil {
		b.Platform.PostResponse(msg, "❌ エラーが発生しました: "+err.Error())
		return
	}

	// プラットフォームへ返信
	b.Platform.PostResponse(msg, result)
}
