package main

import (
	"bufio"
	"fmt"
	"os"
)

type InputSource interface {
	GetCommand() (string, error)
}

type LocalInput struct{}

func (i *LocalInput) GetCommand() (string, error) {
	fmt.Print("\n[Waiting for Input] > ")
	scanner := bufio.NewScanner(os.Stdin)
	if scanner.Scan() {
		return scanner.Text(), nil
	}
	return "", scanner.Err()
}

type SlackInput struct{}

func (i *SlackInput) GetCommand() (string, error) {
	// 将来的に Slack Socket Mode 等からコマンドを取得
	select {}
}
