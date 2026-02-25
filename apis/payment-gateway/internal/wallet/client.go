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

type HTTPClient struct {
	BaseURL     string
	InternalKey string
	httpClient  *http.Client
}

func NewHTTPClient(baseURL, internalKey string) *HTTPClient {
	return &HTTPClient{
		BaseURL:     baseURL,
		InternalKey: internalKey,
		httpClient: &http.Client{
			Timeout: 5 * time.Second,
		},
	}
}

type Balance struct {
	UserID       string  `json:"userId"`
	AvailableUsd float64 `json:"availableUsd"`
	ReservedUsd  float64 `json:"reservedUsd"`
}

type CreditRequest struct {
	UserID    string  `json:"userId"`
	AmountUsd float64 `json:"amountUsd"`
	Source    string  `json:"source"`
	Reference string  `json:"reference"`
}

type ReservationRequest struct {
	UserID       string  `json:"userId"`
	WithdrawalID string  `json:"withdrawalId"`
	AmountUsd    float64 `json:"amountUsd"`
}

type BetReserveRequest struct {
	UserID    string  `json:"userId"`
	SessionID string  `json:"sessionId"`
	AmountUsd float64 `json:"amountUsd"`
	GameType  string  `json:"gameType"`
	TraceID   string  `json:"traceId,omitempty"`
}

type GameSettlementRequest struct {
	UserID    string  `json:"userId"`
	SessionID string  `json:"sessionId"`
	Outcome   string  `json:"outcome"`
	StakeUsd  float64 `json:"stakeUsd"`
	PayoutUsd float64 `json:"payoutUsd"`
	TraceID   string  `json:"traceId,omitempty"`
}

func (c *HTTPClient) CreditDeposit(ctx context.Context, req CreditRequest) error {
	return c.post(ctx, "/internal/ledger/credit", req, nil)
}

func (c *HTTPClient) ReserveWithdrawal(ctx context.Context, req ReservationRequest) error {
	return c.post(ctx, "/internal/ledger/reserve-withdrawal", req, nil)
}

func (c *HTTPClient) ReleaseWithdrawal(ctx context.Context, userID, withdrawalID string, success bool) error {
	payload := map[string]interface{}{
		"userId":       userID,
		"withdrawalId": withdrawalID,
		"success":      success,
	}
	return c.post(ctx, "/internal/ledger/release-withdrawal", payload, nil)
}

func (c *HTTPClient) ReserveBet(ctx context.Context, req BetReserveRequest) (*Balance, error) {
	var bal Balance
	err := c.post(ctx, "/internal/ledger/reserve-bet", req, &bal)
	return &bal, err
}

func (c *HTTPClient) SettleGame(ctx context.Context, req GameSettlementRequest) (*Balance, error) {
	var bal Balance
	err := c.post(ctx, "/internal/ledger/settle-game", req, &bal)
	return &bal, err
}

func (c *HTTPClient) post(ctx context.Context, path string, payload interface{}, out interface{}) error {
	body, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.BaseURL+path, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	if c.InternalKey != "" {
		req.Header.Set("X-Internal-Key", c.InternalKey)
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
