package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"time"
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

type TestPattern struct {
	ID          string
	Name        string
	Agent       string
	Description string
	Generator   func() []QueueEntry
}

var patterns = []TestPattern{
	{
		ID:          "1",
		Name:        "claude-single",
		Agent:       "claude",
		Description: "Single message, single thread",
		Generator: func() []QueueEntry {
			return []QueueEntry{
				{
					Channel:   "C_LOCAL_CLAUDE",
					ThreadTS:  "1715161200.000100",
					MessageTS: "1715161200.000100",
					Text:      "現在のディレクトリのファイル一覧を教えて",
					Time:      time.Now().UTC().Format(time.RFC3339),
					Status:    "pending",
					AgentType: "claude",
				},
			}
		},
	},
	{
		ID:          "2",
		Name:        "claude-multi-thread",
		Agent:       "claude",
		Description: "Multiple threads, 1 message each",
		Generator: func() []QueueEntry {
			return []QueueEntry{
				{
					Channel:   "C_LOCAL_CLAUDE",
					ThreadTS:  "1715161200.000100",
					MessageTS: "1715161200.000100",
					Text:      "ファイル一覧を教えて",
					Time:      time.Now().UTC().Format(time.RFC3339),
					Status:    "pending",
					AgentType: "claude",
				},
				{
					Channel:   "C_LOCAL_CLAUDE",
					ThreadTS:  "1715161300.000100",
					MessageTS: "1715161300.000100",
					Text:      "ディスク容量を教えて",
					Time:      time.Now().UTC().Format(time.RFC3339),
					Status:    "pending",
					AgentType: "claude",
				},
				{
					Channel:   "C_LOCAL_CLAUDE",
					ThreadTS:  "1715161400.000100",
					MessageTS: "1715161400.000100",
					Text:      "プロセス一覧を表示して",
					Time:      time.Now().UTC().Format(time.RFC3339),
					Status:    "pending",
					AgentType: "claude",
				},
			}
		},
	},
	{
		ID:          "3",
		Name:        "claude-multi-msg",
		Agent:       "claude",
		Description: "Single thread, multiple messages (combined execution)",
		Generator: func() []QueueEntry {
			return []QueueEntry{
				{
					Channel:   "C_LOCAL_CLAUDE",
					ThreadTS:  "1715161200.000100",
					MessageTS: "1715161200.000100",
					Text:      "現在のディレクトリのファイル一覧を教えて",
					Time:      time.Now().UTC().Format(time.RFC3339),
					Status:    "pending",
					AgentType: "claude",
				},
				{
					Channel:   "C_LOCAL_CLAUDE",
					ThreadTS:  "1715161200.000100",
					MessageTS: "1715161300.000100",
					Text:      "それぞれのファイルサイズも教えて",
					Time:      time.Now().UTC().Format(time.RFC3339),
					Status:    "pending",
					AgentType: "claude",
				},
				{
					Channel:   "C_LOCAL_CLAUDE",
					ThreadTS:  "1715161200.000100",
					MessageTS: "1715161400.000100",
					Text:      "総容量はいくら？",
					Time:      time.Now().UTC().Format(time.RFC3339),
					Status:    "pending",
					AgentType: "claude",
				},
			}
		},
	},
	{
		ID:          "4",
		Name:        "gemini-single",
		Agent:       "gemini",
		Description: "Gemini single message",
		Generator: func() []QueueEntry {
			return []QueueEntry{
				{
					Channel:   "C_LOCAL_GEMINI",
					ThreadTS:  "1715161500.000100",
					MessageTS: "1715161500.000100",
					Text:      "このディレクトリ内のテキストファイルを一覧表示して",
					Time:      time.Now().UTC().Format(time.RFC3339),
					Status:    "pending",
					AgentType: "gemini",
				},
			}
		},
	},
	{
		ID:          "5",
		Name:        "gemini-multi-msg",
		Agent:       "gemini",
		Description: "Gemini single thread, multiple messages",
		Generator: func() []QueueEntry {
			return []QueueEntry{
				{
					Channel:   "C_LOCAL_GEMINI",
					ThreadTS:  "1715161500.000100",
					MessageTS: "1715161500.000100",
					Text:      "このディレクトリ内のテキストファイルを一覧表示して",
					Time:      time.Now().UTC().Format(time.RFC3339),
					Status:    "pending",
					AgentType: "gemini",
				},
				{
					Channel:   "C_LOCAL_GEMINI",
					ThreadTS:  "1715161500.000100",
					MessageTS: "1715161600.000100",
					Text:      "それぞれのファイルの行数も数えて",
					Time:      time.Now().UTC().Format(time.RFC3339),
					Status:    "pending",
					AgentType: "gemini",
				},
			}
		},
	},
	{
		ID:          "6",
		Name:        "mixed-agents",
		Agent:       "mixed",
		Description: "Claude + Gemini agents",
		Generator: func() []QueueEntry {
			return []QueueEntry{
				{
					Channel:   "C_LOCAL_CLAUDE",
					ThreadTS:  "1715161200.000100",
					MessageTS: "1715161200.000100",
					Text:      "ファイル一覧を教えて（Claude）",
					Time:      time.Now().UTC().Format(time.RFC3339),
					Status:    "pending",
					AgentType: "claude",
				},
				{
					Channel:   "C_LOCAL_GEMINI",
					ThreadTS:  "1715161500.000100",
					MessageTS: "1715161500.000100",
					Text:      "テキストファイルを列挙して（Gemini）",
					Time:      time.Now().UTC().Format(time.RFC3339),
					Status:    "pending",
					AgentType: "gemini",
				},
			}
		},
	},
}

func listPatterns() {
	fmt.Println("Available test patterns:")
	fmt.Println()
	for _, p := range patterns {
		fmt.Printf("  ID: %s | Name: %-20s | Agent: %-6s | %s\n", p.ID, p.Name, p.Agent, p.Description)
	}
	fmt.Println()
}

func findPattern(identifier string) *TestPattern {
	for i := range patterns {
		if patterns[i].ID == identifier || patterns[i].Name == identifier {
			return &patterns[i]
		}
	}
	return nil
}

func main() {
	output := flag.String("output", "", "Output file path (required)")
	pattern := flag.String("pattern", "2", "Test pattern (ID or name, default: 2 for multi-thread)")
	list := flag.Bool("list", false, "List all available patterns")
	flag.Parse()

	if *list {
		listPatterns()
		os.Exit(0)
	}

	if *output == "" {
		fmt.Fprintf(os.Stderr, "Error: -output flag is required\n")
		flag.PrintDefaults()
		os.Exit(1)
	}

	p := findPattern(*pattern)
	if p == nil {
		fmt.Fprintf(os.Stderr, "Error: unknown pattern '%s'\n\n", *pattern)
		listPatterns()
		os.Exit(1)
	}

	entries := p.Generator()
	data, err := json.MarshalIndent(entries, "", "  ")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error marshaling JSON: %v\n", err)
		os.Exit(1)
	}

	if err := os.WriteFile(*output, data, 0644); err != nil {
		fmt.Fprintf(os.Stderr, "Error writing file: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("✅ Queue data generated: %s (pattern: %s - %s)\n", *output, p.ID, p.Name)
}
