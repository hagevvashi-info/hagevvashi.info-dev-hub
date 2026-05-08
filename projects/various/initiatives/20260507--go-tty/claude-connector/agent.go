package main

import (
	"os"
	"os/exec"

	"github.com/creack/pty"
)

type Agent interface {
	Run(input string) (string, error)
}

type ClaudeAgent struct{}

func (a *ClaudeAgent) Run(input string) (string, error) {
	cmd := exec.Command("claude", "-p", "--output-format", "json", input)
	cmd.Stderr = os.Stderr
	f, err := pty.Start(cmd)
	if err != nil {
		return "", err
	}
	defer f.Close()

	// 結果をすべて読み取る (簡易版)
	buf := make([]byte, 1024*10)
	n, _ := f.Read(buf)
	return string(buf[:n]), nil
}

type GeminiAgent struct{}

func (a *GeminiAgent) Run(input string) (string, error) {
	// 現状は Claude と同様の構造にする想定
	return "Gemini response for: " + input, nil
}
