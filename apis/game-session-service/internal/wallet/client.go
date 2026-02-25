package wallet

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

type Client struct {
	baseURL     string
	internalKey string
	httpClient  *http.Client
}

func NewHTTPClient(baseURL string, internalKey string) *Client {
	return &Client{
		baseURL:     baseURL,
		internalKey: internalKey,
		httpClient:  &http.Client{Timeout: 5 * time.Second},
	}
}

type Balance struct {
	UserID       string  `json:"userId"`
	AvailableUsd float64 `json:"availableUsd"`
	ReservedUsd  float64 `json:"reservedUsd"`
}

type ReserveBetRequest struct {
	UserID    string  `json:"userId"`
	SessionID string  `json:"sessionId"`
	GameType  string  `json:"gameType"`
	AmountUsd float64 `json:"amountUsd"`
	TraceID   string  `json:"traceId,omitempty"`
}

type SettleGameRequest struct {
	UserID    string  `json:"userId"`
	SessionID string  `json:"sessionId"`
	Outcome   string  `json:"outcome"`
	StakeUsd  float64 `json:"stakeUsd"`
	PayoutUsd float64 `json:"payoutUsd"`
	TraceID   string  `json:"traceId,omitempty"`
}

func (c *Client) ReserveBet(ctx context.Context, req ReserveBetRequest) (*Balance, error) {
	var bal Balance
	err := c.post(ctx, "/internal/ledger/reserve-bet", req, &bal)
	return &bal, err
}

func (c *Client) SettleGame(ctx context.Context, req SettleGameRequest) (*Balance, error) {
	var bal Balance
	err := c.post(ctx, "/internal/ledger/settle-game", req, &bal)
	return &bal, err
}

func (c *Client) post(ctx context.Context, path string, payload interface{}, out interface{}) error {
	body, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+path, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	if c.internalKey != "" {
		req.Header.Set("X-Internal-Key", c.internalKey)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		if out == nil {
			io.Copy(io.Discard, resp.Body)
			return nil
		}
		return json.NewDecoder(resp.Body).Decode(out)
	}
	respBody, _ := io.ReadAll(resp.Body)
	return fmt.Errorf("wallet service %s: %s", resp.Status, string(respBody))
}
