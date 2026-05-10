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

func main() {
	output := flag.String("output", "", "Output file path (required)")
	flag.Parse()

	if *output == "" {
		fmt.Fprintf(os.Stderr, "Error: -output flag is required\n")
		flag.PrintDefaults()
		os.Exit(1)
	}

	entries := []QueueEntry{
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

	data, err := json.MarshalIndent(entries, "", "  ")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error marshaling JSON: %v\n", err)
		os.Exit(1)
	}

	if err := os.WriteFile(*output, data, 0644); err != nil {
		fmt.Fprintf(os.Stderr, "Error writing file: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("✅ Queue data generated: %s\n", *output)
}
