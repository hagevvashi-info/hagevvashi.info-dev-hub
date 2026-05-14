package queue

import "fmt"

type Sheets struct {
	SpreadsheetID string
}

func NewSheets(spreadsheetID string) *Sheets {
	return &Sheets{SpreadsheetID: spreadsheetID}
}

func (s *Sheets) Read() ([]Entry, error) {
	return nil, fmt.Errorf("Sheets.Read is not implemented yet")
}

func (s *Sheets) Write(entries []Entry) error {
	return fmt.Errorf("Sheets.Write is not implemented yet")
}
