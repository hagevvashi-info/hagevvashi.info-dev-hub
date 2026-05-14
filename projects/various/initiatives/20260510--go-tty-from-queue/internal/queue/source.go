package queue

type Source interface {
	Read() ([]Entry, error)
	Write(entries []Entry) error
}
