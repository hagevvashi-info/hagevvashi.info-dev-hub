package agent

import (
	"bytes"
	"context"
	"io"
	"os"
	"os/exec"
	"time"

	"github.com/creack/pty"
)

type Agent interface {
	Run(input string, resumeSessionID string) (result string, sessionID string, err error)
}

type CLIAgent interface {
	CLIName() string
	BuildArgs(input, resumeSessionID string) []string
	ParseResult(raw []byte) (output, sessionID string, err error)
	Timeout() time.Duration
}

func runCLIAgent(agent CLIAgent, input, resumeSessionID string) (string, string, error) {
	args := agent.BuildArgs(input, resumeSessionID)
	ctx, cancel := context.WithTimeout(context.Background(), agent.Timeout())
	defer cancel()

	cmd := exec.CommandContext(ctx, agent.CLIName(), args...)
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

func parseJSONResult(raw []byte, unmarshal func([]byte) (output, sessionID string, err error)) (string, string, error) {
	jsonBytes := raw
	if i := bytes.IndexByte(raw, '{'); i >= 0 {
		if j := bytes.LastIndexByte(raw, '}'); j > i {
			jsonBytes = raw[i : j+1]
		}
	}

	output, sessionID, err := unmarshal(jsonBytes)
	if err == nil && output != "" {
		return output, sessionID, nil
	}

	return string(raw), "", nil
}
