package queue

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

type Local struct {
	FilePath string
}

func NewLocal(filePath string) *Local {
	return &Local{FilePath: filePath}
}

func (s *Local) Read() ([]Entry, error) {
	data, err := os.ReadFile(s.FilePath)
	if err != nil {
		return nil, fmt.Errorf("failed to read queue file: %w", err)
	}

	var entries []Entry
	if err := json.Unmarshal(data, &entries); err != nil {
		return nil, fmt.Errorf("failed to parse queue file: %w", err)
	}

	return entries, nil
}

func (s *Local) Write(entries []Entry) error {
	data, err := json.MarshalIndent(entries, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal entries: %w", err)
	}

	tmpPath := s.FilePath + ".tmp"
	if err := os.WriteFile(tmpPath, data, 0644); err != nil {
		return fmt.Errorf("failed to write temp file: %w", err)
	}

	if err := os.MkdirAll(filepath.Dir(s.FilePath), 0755); err != nil && filepath.Dir(s.FilePath) != "." {
		return err
	}

	if err := os.Rename(tmpPath, s.FilePath); err != nil {
		return fmt.Errorf("failed to replace queue file: %w", err)
	}

	return nil
}
