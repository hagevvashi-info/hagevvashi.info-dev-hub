.PHONY: build clean help

BINARY_NAME=go-tty-from-queue
BIN_DIR=./bin
BINARY=$(BIN_DIR)/$(BINARY_NAME)

help:
	@echo "Available targets:"
	@echo "  build       - Build the binary to ./bin/go-tty-from-queue"
	@echo "  clean       - Remove bin directory"
	@echo "  run         - Build and run the binary"
	@echo "  help        - Show this help message"

build:
	@mkdir -p $(BIN_DIR)
	go build -o $(BINARY) ./cmd/worker/
	@echo "✅ Binary built: $(BINARY)"

clean:
	rm -rf $(BIN_DIR)
	@echo "✅ Cleaned: $(BIN_DIR)"

run: build
	QUEUE_FILE=/tmp/queue.json REDIS_ADDR=localhost:6379 $(BINARY)
