package main

import (
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strings"
	"time"
)

// Message はプラットフォームを問わず扱う共通メッセージ形式
type Message struct {
	ID        string
	AgentType string // "claude" or "gemini"
	Content   string
	Timestamp time.Time

	// Slack 等のスレッド/チャンネル概念を取り込むためのメタ情報
	ChannelID string
	ThreadTS  string
	// スレッドトップの場合の返信数 (Slack: reply_count)
	ReplyCount int
}

func (m Message) ThreadKey() (string, error) {
	if strings.TrimSpace(m.ChannelID) == "" {
		return "", fmt.Errorf("ChannelID is empty")
	}
	if strings.TrimSpace(m.ThreadTS) == "" {
		return "", fmt.Errorf("ThreadTS is empty")
	}
	return m.ChannelID + ":" + m.ThreadTS, nil
}

func (m Message) IsThreadRoot() bool {
	// 正規化後は ThreadTS が必ず入る想定
	return m.ThreadTS == m.ID
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
	cfg, err := loadConfig()
	if err == nil {
		var all []Message
		for _, ch := range cfg.Channels {
			fixture := fmt.Sprintf("fixtures/conversations_history_%s.json", ch.ID)
			data, err := os.ReadFile(fixture)
			if err != nil {
				return nil, fmt.Errorf("failed to read fixture %s: %w", fixture, err)
			}
			var history SlackConversationsHistoryResponse
			if err := json.Unmarshal(data, &history); err != nil {
				return nil, fmt.Errorf("failed to parse %s: %w", fixture, err)
			}
			msgs, err := ConvertSlackConversationsHistoryToMessages(ch.ID, ch.AgentType, history)
			if err != nil {
				return nil, fmt.Errorf("failed to convert slack history for channel %s: %w", ch.ID, err)
			}

			// スレッドトップのメッセージがある場合、replies のフィクスチャも読み込んでぶら下げる
			for _, m := range msgs {
				all = append(all, m)

				// スレッドトップで reply_count > 0 のものはスレッドがあるので replies を拾いに行く
				if m.IsThreadRoot() && m.ReplyCount > 0 {
					repliesFixture := fmt.Sprintf("fixtures/conversations_replies_%s_%s.json", ch.ID, m.ThreadTS)
					repliesData, err := os.ReadFile(repliesFixture)
					if err != nil {
						return nil, fmt.Errorf("failed to read fixture %s: %w", repliesFixture, err)
					}
					var replies SlackConversationsRepliesResponse
					if err := json.Unmarshal(repliesData, &replies); err != nil {
						return nil, fmt.Errorf("failed to parse %s: %w", repliesFixture, err)
					}
					threadMsgs, err := ConvertSlackConversationsRepliesToMessages(ch.ID, ch.AgentType, m.ThreadTS, replies)
					if err != nil {
						return nil, fmt.Errorf("failed to convert slack replies for channel %s thread %s: %w", ch.ID, m.ThreadTS, err)
					}

					// replies は root を含むので、root 以外を追加
					for _, tm := range threadMsgs {
						if tm.ID == m.ID {
							continue
						}
						all = append(all, tm)
					}
				}
			}
		}

		// lastCheck 以降だけに絞る
		out := all[:0]
		for _, m := range all {
			if m.Timestamp.After(lastCheck) {
				out = append(out, m)
			}
		}
		all = out

		// 時系列順に安定化
		sort.Slice(all, func(i, j int) bool { return all[i].Timestamp.Before(all[j].Timestamp) })
		return all, nil
	}

	// フィクスチャが無い場合は従来の固定メッセージ
	return []Message{
		{ID: "local-123", AgentType: "claude", Content: "現在のディレクトリのファイル一覧を教えて", Timestamp: time.Now()},
	}, nil
}

func (p *LocalPlatform) PostResponse(original Message, response string) error {
	threadInfo := ""
	if original.ThreadTS != "" {
		threadInfo = fmt.Sprintf(" (thread_ts: %s)", original.ThreadTS)
	}
	fmt.Printf("\n📢 [Local Post] channel: %s ID: %s%s への返信:\n%s\n", original.ChannelID, original.ID, threadInfo, response)
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
	if strings.TrimSpace(p.Token) == "" {
		return fmt.Errorf("SLACK_TOKEN is empty")
	}
	if strings.TrimSpace(original.ChannelID) == "" {
		return fmt.Errorf("original.ChannelID is empty")
	}

	// スレッド返信として扱う。元がスレッド内なら original.ThreadTS、そうでなければ original.ID を thread_ts にする。
	threadTS := original.ThreadTS
	if strings.TrimSpace(threadTS) == "" {
		threadTS = original.ID
	}

	api := newSlackAPI(p.Token)
	_, err := api.postMessage(slackChatPostMessageRequest{
		Channel:  original.ChannelID,
		Text:     response,
		ThreadTS: threadTS,
	})
	if err != nil {
		return err
	}
	fmt.Println("🚀 [Slack] メッセージを送信しました")
	return nil
}
