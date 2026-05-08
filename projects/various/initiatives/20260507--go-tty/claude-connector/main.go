package main

import (
	"bufio"
	"fmt"
	"log"
	"os"
	"regexp"
	"strings"
	"time"
)

func main() {
	env := os.Getenv("APP_ENV")
	var notifier Notifier = &LocalNotifier{}
	var inputSource InputSource = &LocalInput{}

	if env == "production" {
		notifier = &SlackNotifier{Token: os.Getenv("SLACK_TOKEN")}
		inputSource = &SlackInput{}
	}

	fmt.Println("🚀 System Online. Usage: 'claude <cmd>' or 'gemini <cmd>'")

	var agent Agent
	var actualCommand string

	// 1. エージェントの選択（入力があるまでループ）
	for {
		firstInput, err := inputSource.GetCommand()
		if err != nil {
			log.Fatal(err)
		}
		if firstInput == "" {
			continue
		}

		switch {
		case strings.HasPrefix(firstInput, "gemini "):
			agent = &GeminiAgent{}
			actualCommand = strings.TrimPrefix(firstInput, "gemini ")
		case strings.HasPrefix(firstInput, "claude "):
			agent = &ClaudeAgent{}
			actualCommand = strings.TrimPrefix(firstInput, "claude ")
		default:
			fmt.Printf("❌ Invalid agent prefix. Use 'claude ' or 'gemini '\n")
			continue
		}
		break
	}

	// 2. エージェントの起動（ここでコマンドを渡す）
	f, cmd, err := agent.Start(actualCommand)
	if err != nil {
		log.Fatalf("Fatal: Failed to start agent: %v", err)
	}
	defer f.Close()

	outputChan := make(chan string)
	re := regexp.MustCompile(`Session ID: (sess_[a-z0-9]+)`)

	// --- パイプライン ---

	// A. 追加入力ループ（一撃で終わるモードでも、一応 Stdin を維持）
	go func() {
		for {
			text, err := inputSource.GetCommand()
			if err != nil {
				return
			}
			fmt.Fprintln(f, text)
		}
	}()

	// B. 読み取りループ
	go func() {
		scanner := bufio.NewScanner(f)
		for scanner.Scan() {
			line := scanner.Text()
			outputChan <- line

			// JSONの中から Session ID を探す
			if match := re.FindStringSubmatch(line); match != nil {
				notifier.SaveSession(match[1])
			}
		}
	}()

	// C. 通知ループ
	go func() {
		var buffer string
		ticker := time.NewTicker(2 * time.Second) // 少し早めに 2秒に
		for {
			select {
			case line := <-outputChan:
				buffer += line + "\n"
			case <-ticker.C:
				if buffer != "" {
					notifier.Notify(buffer)
					buffer = ""
				}
			}
		}
	}()

	// 子プロセスの終了待機
	if err := cmd.Wait(); err != nil {
		log.Printf("Process finished: %v", err)
	}
	// 最後のバッファを出し切るための猶予
	time.Sleep(2 * time.Second)
	fmt.Println("--- Shutdown ---")
}
