package platform

import "go-tty-from-queue/internal/message"

type Platform interface {
	FetchNewMessages() ([]message.Message, error)
	PostResponse(original message.Message, response string) error
	MarkProcessed(messageID string) error
}
