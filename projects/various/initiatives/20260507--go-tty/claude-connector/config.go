package main

import (
	"encoding/json"
	"fmt"
	"os"
)

const configFile = "config.json"

type Config struct {
	Channels []ChannelConfig `json:"channels"`
}

type ChannelConfig struct {
	ID        string `json:"id"`
	AgentType string `json:"agent_type"` // "claude" or "gemini"
}

func loadConfig() (Config, error) {
	data, err := os.ReadFile(configFile)
	if err != nil {
		return Config{}, fmt.Errorf("failed to read %s: %w", configFile, err)
	}
	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return Config{}, fmt.Errorf("failed to parse %s: %w", configFile, err)
	}
	return cfg, nil
}

