package agent

import (
	"encoding/json"
	"strings"
	"time"
)

type Gemini struct{}

type geminiJSONResult struct {
	Output    string `json:"output"`
	SessionID string `json:"session_id"`
}

func (a *Gemini) CLIName() string {
	return "gemini"
}

func (a *Gemini) BuildArgs(input, resumeSessionID string) []string {
	args := []string{"-p", input, "--output-format", "json"}
	if strings.TrimSpace(resumeSessionID) != "" {
		args = append(args, "--resume", resumeSessionID)
	}
	return args
}

func (a *Gemini) ParseResult(raw []byte) (string, string, error) {
	return parseJSONResult(raw, func(jsonBytes []byte) (string, string, error) {
		var jr geminiJSONResult
		if err := json.Unmarshal(jsonBytes, &jr); err != nil {
			return "", "", err
		}
		return jr.Output, jr.SessionID, nil
	})
}

func (a *Gemini) Timeout() time.Duration {
	return 120 * time.Second
}

func (a *Gemini) Run(input, resumeSessionID string) (string, string, error) {
	return runCLIAgent(a, input, resumeSessionID)
}
