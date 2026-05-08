package main

import "fmt"

type Notifier interface {
	Notify(content string) error
	SaveSession(sessionID string) error
}

type LocalNotifier struct{}

func (n *LocalNotifier) Notify(content string) error {
	fmt.Printf("\n--- 通知先: Local ---\n%s\n------------------\n", content)
	return nil
}

func (n *LocalNotifier) SaveSession(id string) error {
	fmt.Printf("LOG: Session ID '%s' を保存しました\n", id)
	return nil
}

type SlackNotifier struct {
	Token string
}

func (n *SlackNotifier) Notify(content string) error {
	fmt.Printf("LOG: Slack (%s) へ送信しました\n", n.Token[:5])
	return nil
}

func (n *SlackNotifier) SaveSession(id string) error {
	fmt.Printf("LOG: Slackセッション '%s' を永続化しました\n", id)
	return nil
}
