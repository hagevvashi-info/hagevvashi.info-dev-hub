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

type ClaudeAgent struct{}

type claudeJSONResult struct {
	Result    string `json:"result"`
	SessionID string `json:"session_id"`
}

func (a *ClaudeAgent) Run(input string, resumeSessionID string) (string, string, error) {
	args := []string{}
	if strings.TrimSpace(resumeSessionID) != "" {
		args = append(args, "--resume", resumeSessionID)
	}
	args = append(args, "-p", "--output-format", "json", input)

	cmd := exec.Command("claude", args...)
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

type GeminiAgent struct{}

func (a *GeminiAgent) Run(input string, resumeSessionID string) (string, string, error) {
	_ = resumeSessionID
	return "Gemini response for: " + input, "", nil
}
