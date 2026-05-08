package main

import (
	"os"
	"os/exec"

	"github.com/creack/pty"
)

type Agent interface {
	// 起動時に最初の命令を渡せるように変更
	Start(input string) (*os.File, *exec.Cmd, error)
}

type ClaudeAgent struct{}

func (a *ClaudeAgent) Start(input string) (*os.File, *exec.Cmd, error) {
	// -p: プレーンモード, --output-format json: JSON出力
	// 最後に input を引数として渡すことで、一撃で実行させる
	cmd := exec.Command("claude", "-p", "--output-format", "json", input)

	cmd.Stderr = os.Stderr
	f, err := pty.Start(cmd)
	return f, cmd, err
}

type GeminiAgent struct{}

func (a *GeminiAgent) Start(input string) (*os.File, *exec.Cmd, error) {
	// Gemini CLI の仕様に合わせて調整が必要（ここでは仮）
	cmd := exec.Command("gemini", "chat", input)
	cmd.Stderr = os.Stderr
	f, err := pty.Start(cmd)
	return f, cmd, err
}
