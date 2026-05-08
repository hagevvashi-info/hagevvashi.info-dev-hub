package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

type slackAPI struct {
	token  string
	client *http.Client
}

func newSlackAPI(token string) *slackAPI {
	return &slackAPI{
		token: token,
		client: &http.Client{
			Timeout: 20 * time.Second,
		},
	}
}

type slackChatPostMessageRequest struct {
	Channel  string `json:"channel"`
	Text     string `json:"text"`
	ThreadTS string `json:"thread_ts,omitempty"`
}

type slackChatPostMessageResponse struct {
	OK    bool   `json:"ok"`
	Error string `json:"error,omitempty"`
	TS    string `json:"ts,omitempty"`
}

func (api *slackAPI) postMessage(req slackChatPostMessageRequest) (slackChatPostMessageResponse, error) {
	body, err := json.Marshal(req)
	if err != nil {
		return slackChatPostMessageResponse{}, err
	}

	httpReq, err := http.NewRequest(http.MethodPost, "https://slack.com/api/chat.postMessage", bytes.NewReader(body))
	if err != nil {
		return slackChatPostMessageResponse{}, err
	}
	httpReq.Header.Set("Authorization", "Bearer "+api.token)
	httpReq.Header.Set("Content-Type", "application/json; charset=utf-8")

	resp, err := api.client.Do(httpReq)
	if err != nil {
		return slackChatPostMessageResponse{}, err
	}
	defer resp.Body.Close()

	var out slackChatPostMessageResponse
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return slackChatPostMessageResponse{}, err
	}
	if !out.OK {
		if out.Error != "" {
			return out, fmt.Errorf("slack chat.postMessage error: %s", out.Error)
		}
		return out, fmt.Errorf("slack chat.postMessage error")
	}
	return out, nil
}

