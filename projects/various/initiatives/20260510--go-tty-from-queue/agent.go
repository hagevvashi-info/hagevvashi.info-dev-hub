package main

import (
	"bytes"
	"encoding/json"
	"io"
	"os"
	"os/exec"
	"strings"

	"github.com/creack/pty"
)

type Agent interface {
	Run(input string, resumeSessionID string) (result string, sessionID string, err error)
}

// CLIAgent は CLI ベースのエージェント向けの共通インターフェース
type CLIAgent interface {
	CLIName() string
	BuildArgs(input, resumeSessionID string) []string
	ParseResult(raw []byte) (output, sessionID string, err error)
}

// runCLIAgent は CLI エージェント実行の共通ロジック
func runCLIAgent(agent CLIAgent, input, resumeSessionID string) (string, string, error) {
	args := agent.BuildArgs(input, resumeSessionID)
	cmd := exec.Command(agent.CLIName(), args...)
	cmd.Stderr = os.Stderr
	f, err := pty.Start(cmd)
	if err != nil {
		return "", "", err
	}
	defer f.Close()

	raw, readErr := io.ReadAll(f)
	if readErr != nil && len(raw) == 0 {
		return "", "", readErr
	}
	raw = bytes.TrimSpace(raw)

	return agent.ParseResult(raw)
}

type ClaudeAgent struct{}

type claudeJSONResult struct {
	Result    string `json:"result"`
	SessionID string `json:"session_id"`
}

func (a *ClaudeAgent) CLIName() string {
	return "claude"
}

func (a *ClaudeAgent) BuildArgs(input, resumeSessionID string) []string {
	args := []string{}
	if strings.TrimSpace(resumeSessionID) != "" {
		args = append(args, "--resume", resumeSessionID)
	}
	args = append(args, "-p", "--output-format", "json", input)
	return args
}

func (a *ClaudeAgent) ParseResult(raw []byte) (string, string, error) {
	var jr claudeJSONResult
	jsonBytes := raw
	if i := bytes.IndexByte(raw, '{'); i >= 0 {
		if j := bytes.LastIndexByte(raw, '}'); j > i {
			jsonBytes = raw[i : j+1]
		}
	}

	if err := json.Unmarshal(jsonBytes, &jr); err == nil && jr.Result != "" {
		return jr.Result, jr.SessionID, nil
	}

	return string(raw), "", nil
}

func (a *ClaudeAgent) Run(input, resumeSessionID string) (string, string, error) {
	return runCLIAgent(a, input, resumeSessionID)
}

type GeminiAgent struct{}

type geminiJSONResult struct {
	Output    string `json:"output"`
	SessionID string `json:"session_id"`
}

func (a *GeminiAgent) CLIName() string {
	return "gemini"
}

func (a *GeminiAgent) BuildArgs(input, resumeSessionID string) []string {
	args := []string{"--output-format", "json"}
	if strings.TrimSpace(resumeSessionID) != "" {
		args = append(args, "--session", resumeSessionID)
	}
	args = append(args, input)
	return args
}

func (a *GeminiAgent) ParseResult(raw []byte) (string, string, error) {
	var jr geminiJSONResult
	jsonBytes := raw
	if i := bytes.IndexByte(raw, '{'); i >= 0 {
		if j := bytes.LastIndexByte(raw, '}'); j > i {
			jsonBytes = raw[i : j+1]
		}
	}

	if err := json.Unmarshal(jsonBytes, &jr); err == nil && jr.Output != "" {
		return jr.Output, jr.SessionID, nil
	}

	return string(raw), "", nil
}

func (a *GeminiAgent) Run(input, resumeSessionID string) (string, string, error) {
	return runCLIAgent(a, input, resumeSessionID)
}
