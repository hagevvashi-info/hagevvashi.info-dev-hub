package main

// Slack conversations.history のレスポンス (必要最小限)
// 参考: https://api.slack.com/methods/conversations.history
type SlackConversationsHistoryResponse struct {
	OK       bool          `json:"ok"`
	Messages []SlackMessage `json:"messages"`
	Error    string        `json:"error,omitempty"`
}

// Slack conversations.replies のレスポンス (必要最小限)
// 参考: https://api.slack.com/methods/conversations.replies
type SlackConversationsRepliesResponse struct {
	OK       bool          `json:"ok"`
	Messages []SlackMessage `json:"messages"`
	Error    string        `json:"error,omitempty"`
}

type SlackMessage struct {
	Type    string `json:"type,omitempty"`
	Subtype string `json:"subtype,omitempty"`

	// text + ts が最低限必要
	Text string `json:"text"`
	TS   string `json:"ts"`

	// bot 投稿っぽいものを弾く用途
	BotID string `json:"bot_id,omitempty"`
	User  string `json:"user,omitempty"`

	// Thread関連 (APIによって出たり出なかったりする)
	ThreadTS        string `json:"thread_ts,omitempty"`
	ReplyCount      int    `json:"reply_count,omitempty"`
	ReplyUsersCount int    `json:"reply_users_count,omitempty"`
	LatestReply     string `json:"latest_reply,omitempty"`
}
