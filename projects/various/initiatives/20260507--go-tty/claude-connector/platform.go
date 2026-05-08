package main

import (
	"fmt"
	"time"
)

// Message はプラットフォームを問わず扱う共通メッセージ形式
type Message struct {
	ID        string
	AgentType string // "claude" or "gemini"
	Content   string
	Timestamp time.Time
}

// Platform は Slack や Local とのやり取りを抽象化する
type Platform interface {
	FetchNewMessages(lastCheck time.Time) ([]Message, error)
	PostResponse(original Message, response string) error
}

// --- Local 実装 (テスト用) ---
type LocalPlatform struct{}

func (p *LocalPlatform) FetchNewMessages(lastCheck time.Time) ([]Message, error) {
	fmt.Println("🔍 [Local] 擬似メッセージを生成します...")
	// テスト用に1つメッセージを返す
	return []Message{
		{ID: "local-123", AgentType: "claude", Content: "現在のディレクトリのファイル一覧を教えて", Timestamp: time.Now()},
	}, nil
}

func (p *LocalPlatform) PostResponse(original Message, response string) error {
	fmt.Printf("\n📢 [Local Post] ID: %s への返信:\n%s\n", original.ID, response)
	return nil
}

// --- Slack 実装 (本番用) ---
type SlackPlatform struct {
	Token string
}

func (p *SlackPlatform) FetchNewMessages(lastCheck time.Time) ([]Message, error) {
	// TODO: Slack API (conversations.history) を叩いて、
	// lastCheck 以降の、かつ Bot 以外からのメッセージを抽出するロジック
	fmt.Println("📡 [Slack] 新着メッセージを確認中...")
	return nil, nil
}

func (p *SlackPlatform) PostResponse(original Message, response string) error {
	// TODO: Slack API (chat.postMessage) でスレッド等に返信する
	fmt.Println("🚀 [Slack] メッセージを送信しました")
	return nil
}
