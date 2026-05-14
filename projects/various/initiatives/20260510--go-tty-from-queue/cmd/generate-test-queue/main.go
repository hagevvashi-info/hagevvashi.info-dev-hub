package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
)

type QueueEntry struct {
	Channel   string `json:"channel"`
	ThreadTS  string `json:"thread_ts"`
	MessageTS string `json:"message_ts"`
	Text      string `json:"text"`
	Time      string `json:"time"`
	Status    string `json:"status"`
	AgentType string `json:"agent_type"`
}

func generateClaudePattern() []QueueEntry {
	return []QueueEntry{
		{
			Channel:   "C_LOCAL_CLAUDE",
			ThreadTS:  "1715161200.000100",
			MessageTS: "1715161200.000100",
			Text:      "現在のディレクトリのファイル一覧を教えて",
			Time:      "2026-05-08T10:00:00Z",
			Status:    "pending",
			AgentType: "claude",
		},
		{
			Channel:   "C_LOCAL_CLAUDE",
			ThreadTS:  "1715161200.000100",
			MessageTS: "1715161300.000100",
			Text:      "それぞれのファイルサイズも教えて",
			Time:      "2026-05-08T10:01:00Z",
			Status:    "pending",
			AgentType: "claude",
		},
		{
			Channel:   "C_LOCAL_CLAUDE",
			ThreadTS:  "1715161400.000100",
			MessageTS: "1715161400.000100",
			Text:      "go.mod の中身を教えて",
			Time:      "2026-05-08T10:02:00Z",
			Status:    "pending",
			AgentType: "claude",
		},
	}
}

func generateGeminiPattern() []QueueEntry {
	return []QueueEntry{
		{
			Channel:   "C_LOCAL_GEMINI",
			ThreadTS:  "1715161500.000100",
			MessageTS: "1715161500.000100",
			Text:      "このディレクトリ内のテキストファイルを一覧表示して",
			Time:      "2026-05-08T10:05:00Z",
			Status:    "pending",
			AgentType: "gemini",
		},
		{
			Channel:   "C_LOCAL_GEMINI",
			ThreadTS:  "1715161500.000100",
			MessageTS: "1715161600.000100",
			Text:      "それぞれのファイルの行数も数えて",
			Time:      "2026-05-08T10:06:00Z",
			Status:    "pending",
			AgentType: "gemini",
		},
		{
			Channel:   "C_LOCAL_GEMINI",
			ThreadTS:  "1715161700.000100",
			MessageTS: "1715161700.000100",
			Text:      "README.md の最初の 5 行を表示して",
			Time:      "2026-05-08T10:08:00Z",
			Status:    "pending",
			AgentType: "gemini",
		},
	}
}

func generateMixedPattern() []QueueEntry {
	claude := generateClaudePattern()
	gemini := generateGeminiPattern()
	return append(claude, gemini...)
}

func main() {
	output := flag.String("output", "", "Output file path (required)")
	pattern := flag.String("pattern", "claude", "Test pattern: claude, gemini, or mixed")
	flag.Parse()

	if *output == "" {
		fmt.Fprintf(os.Stderr, "Error: -output flag is required\n")
		flag.PrintDefaults()
		os.Exit(1)
	}

	var entries []QueueEntry
	switch *pattern {
	case "claude":
		entries = generateClaudePattern()
	case "gemini":
		entries = generateGeminiPattern()
	case "mixed":
		entries = generateMixedPattern()
	default:
		fmt.Fprintf(os.Stderr, "Error: unknown pattern '%s'. Use: claude, gemini, or mixed\n", *pattern)
		os.Exit(1)
	}

	data, err := json.MarshalIndent(entries, "", "  ")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error marshaling JSON: %v\n", err)
		os.Exit(1)
	}

	if err := os.WriteFile(*output, data, 0644); err != nil {
		fmt.Fprintf(os.Stderr, "Error writing file: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("✅ Queue data generated: %s (pattern: %s)\n", *output, *pattern)
}
