package main

// QueueEntry は GAS → Google Sheets → Queue.json として流れるデータ構造
type QueueEntry struct {
	Channel   string `json:"channel"`
	ThreadTS  string `json:"thread_ts"`
	MessageTS string `json:"message_ts"`
	Text      string `json:"text"`
	Time      string `json:"time"`      // ISO 8601 形式
	Status    string `json:"status"`    // "pending", "processing", "completed", "failed"
	AgentType string `json:"agent_type"` // "claude" or "gemini"
}
