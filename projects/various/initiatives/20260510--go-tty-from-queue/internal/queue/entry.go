package queue

type Entry struct {
	Channel   string `json:"channel"`
	ThreadTS  string `json:"thread_ts"`
	MessageTS string `json:"message_ts"`
	Text      string `json:"text"`
	Time      string `json:"time"`          // ISO 8601 format
	Status    string `json:"status"`        // "pending", "processing", "completed", "failed"
	AgentType string `json:"agent_type"` // "claude" or "gemini"
}
