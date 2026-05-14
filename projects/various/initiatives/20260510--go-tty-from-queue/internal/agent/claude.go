package agent

import (
	"encoding/json"
	"strings"
	"time"
)

type Claude struct{}

type claudeJSONResult struct {
	Result    string `json:"result"`
	SessionID string `json:"session_id"`
}

func (a *Claude) CLIName() string {
	return "claude"
}

func (a *Claude) BuildArgs(input, resumeSessionID string) []string {
	args := []string{}
	if strings.TrimSpace(resumeSessionID) != "" {
		args = append(args, "--resume", resumeSessionID)
	}
	args = append(args, "-p", "--output-format", "json", input)
	return args
}

func (a *Claude) ParseResult(raw []byte) (string, string, error) {
	return parseJSONResult(raw, func(jsonBytes []byte) (string, string, error) {
		var jr claudeJSONResult
		if err := json.Unmarshal(jsonBytes, &jr); err != nil {
			return "", "", err
		}
		return jr.Result, jr.SessionID, nil
	})
}

func (a *Claude) Timeout() time.Duration {
	return 30 * time.Second
}

func (a *Claude) Run(input, resumeSessionID string) (string, string, error) {
	return runCLIAgent(a, input, resumeSessionID)
}
