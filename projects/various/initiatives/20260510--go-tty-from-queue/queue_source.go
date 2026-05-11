package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// QueueSource は Queue の入出力を抽象化する
type QueueSource interface {
	// Read メモリ全体に乗る想定（定期削除で数は制限されるため）
	Read() ([]QueueEntry, error)
	Write(entries []QueueEntry) error
}

// LocalQueueSource は fixtures/queue.json を読み書きする
type LocalQueueSource struct {
	FilePath string
}

func NewLocalQueueSource(filePath string) *LocalQueueSource {
	return &LocalQueueSource{FilePath: filePath}
}

func (s *LocalQueueSource) Read() ([]QueueEntry, error) {
	data, err := os.ReadFile(s.FilePath)
	if err != nil {
		return nil, fmt.Errorf("failed to read queue file: %w", err)
	}

	var entries []QueueEntry
	if err := json.Unmarshal(data, &entries); err != nil {
		return nil, fmt.Errorf("failed to parse queue file: %w", err)
	}

	return entries, nil
}

func (s *LocalQueueSource) Write(entries []QueueEntry) error {
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

// SheetQueueSource は Google Sheets から読み書きする（未実装）
type SheetQueueSource struct {
	SpreadsheetID string
}

func NewSheetQueueSource(spreadsheetID string) *SheetQueueSource {
	return &SheetQueueSource{SpreadsheetID: spreadsheetID}
}

func (s *SheetQueueSource) Read() ([]QueueEntry, error) {
	return nil, fmt.Errorf("SheetQueueSource.Read is not implemented yet")
}

func (s *SheetQueueSource) Write(entries []QueueEntry) error {
	return fmt.Errorf("SheetQueueSource.Write is not implemented yet")
}
