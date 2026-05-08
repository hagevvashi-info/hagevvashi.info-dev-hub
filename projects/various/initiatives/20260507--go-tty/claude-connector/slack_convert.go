package main

import (
	"fmt"
	"strconv"
	"strings"
	"time"
)

func ConvertSlackConversationsHistoryToMessages(channelID string, agentType string, resp SlackConversationsHistoryResponse) ([]Message, error) {
	if !resp.OK {
		if resp.Error != "" {
			return nil, fmt.Errorf("slack response not ok: %s", resp.Error)
		}
		return nil, fmt.Errorf("slack response not ok")
	}
	if strings.TrimSpace(agentType) == "" {
		return nil, fmt.Errorf("agent type not configured for channel %q", channelID)
	}

	out := make([]Message, 0, len(resp.Messages))
	for _, sm := range resp.Messages {
		// Bot の自動投稿などは除外 (本番取得ロジック側でやる予定だが、ローカルでも邪魔になりがち)
		if sm.BotID != "" || sm.Subtype == "bot_message" {
			continue
		}

		t, err := parseSlackTS(sm.TS)
		if err != nil {
			return nil, fmt.Errorf("invalid slack ts %q: %w", sm.TS, err)
		}

		// 正規化: thread_ts が空なら ts を入れて「このメッセージを root とするスレッド」として扱う
		threadTS := sm.ThreadTS
		if strings.TrimSpace(threadTS) == "" {
			threadTS = sm.TS
		}

		out = append(out, Message{
			ID:        sm.TS, // Slack では ts が一意 ID 的に使われる
			AgentType: strings.ToLower(agentType),
			Content:   sm.Text,
			Timestamp: t,
			ChannelID: channelID,
			ThreadTS:  threadTS,
			ReplyCount: sm.ReplyCount,
		})
	}
	return out, nil
}

func ConvertSlackConversationsRepliesToMessages(channelID string, agentType string, threadTS string, resp SlackConversationsRepliesResponse) ([]Message, error) {
	if !resp.OK {
		if resp.Error != "" {
			return nil, fmt.Errorf("slack response not ok: %s", resp.Error)
		}
		return nil, fmt.Errorf("slack response not ok")
	}
	if strings.TrimSpace(agentType) == "" {
		return nil, fmt.Errorf("agent type not configured for channel %q", channelID)
	}
	if strings.TrimSpace(threadTS) == "" {
		return nil, fmt.Errorf("thread_ts is required")
	}

	out := make([]Message, 0, len(resp.Messages))
	for _, sm := range resp.Messages {
		if sm.BotID != "" || sm.Subtype == "bot_message" {
			continue
		}
		t, err := parseSlackTS(sm.TS)
		if err != nil {
			return nil, fmt.Errorf("invalid slack ts %q: %w", sm.TS, err)
		}

		// 正規化: replies の root は thread_ts が無いこともあるので補完する
		thread := sm.ThreadTS
		if strings.TrimSpace(thread) == "" {
			thread = threadTS
		}

		out = append(out, Message{
			ID:        sm.TS,
			AgentType: strings.ToLower(agentType),
			Content:   sm.Text,
			Timestamp: t,
			ChannelID: channelID,
			ThreadTS:  thread,
		})
	}
	return out, nil
}

// parseSlackTS parses Slack's "ts" (e.g. "1715265073.000100") into time.Time (UTC).
func parseSlackTS(ts string) (time.Time, error) {
	parts := strings.SplitN(ts, ".", 2)
	secStr := parts[0]
	sec, err := strconv.ParseInt(secStr, 10, 64)
	if err != nil {
		return time.Time{}, err
	}

	var nsec int64
	if len(parts) == 2 {
		frac := parts[1]
		if len(frac) > 9 {
			frac = frac[:9]
		}
		for len(frac) < 9 {
			frac += "0"
		}
		nsec, err = strconv.ParseInt(frac, 10, 64)
		if err != nil {
			return time.Time{}, err
		}
	}

	return time.Unix(sec, nsec).UTC(), nil
}
