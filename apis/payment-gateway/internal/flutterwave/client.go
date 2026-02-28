package flutterwave

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const maxRetries = 2

// Client wraps the subset of Flutterwave's API surface needed for
// mobile money deposits and withdrawals.
type Client struct {
	secretKey    string
	baseURL      string
	transferBase string
	httpClient   *http.Client
}

func NewClient(secretKey, baseURL, transferBase string) *Client {
	if baseURL == "" {
		baseURL = "https://api.flutterwave.com"
	}
	if transferBase == "" {
		transferBase = baseURL
	}
	return &Client{
		secretKey:    secretKey,
		baseURL:      strings.TrimRight(baseURL, "/"),
		transferBase: strings.TrimRight(transferBase, "/"),
		httpClient:   &http.Client{Timeout: 20 * time.Second},
	}
}

type MobileMoneyChargeRequest struct {
	Reference   string
	Amount      float64
	Currency    string
	Email       string
	FullName    string
	PhoneNumber string
	Network     string
	Narration   string
	CallbackURL string
}

type MobileMoneyChargeResponse struct {
	ID            int64           `json:"id"`
	Status        string          `json:"status"`
	TxRef         string          `json:"tx_ref"`
	FlwRef        string          `json:"flw_ref"`
	Amount        float64         `json:"amount"`
	Currency      string          `json:"currency"`
	Reference     string          `json:"reference"`
	Authorization *Authorization  `json:"authorization,omitempty"`
	Meta          json.RawMessage `json:"-"`
}

type Transaction struct {
	ID        int64   `json:"id"`
	Status    string  `json:"status"`
	TxRef     string  `json:"tx_ref"`
	FlwRef    string  `json:"flw_ref"`
	Amount    float64 `json:"amount"`
	Currency  string  `json:"currency"`
	Reference string  `json:"reference"`
}

type TransferRequest struct {
	Reference     string
	Amount        float64
	Currency      string
	DebitCurrency string
	AccountBank   string
	AccountNumber string
	Narration     string
	CallbackURL   string
	Beneficiary   string
}

type TransferResponse struct {
	ID        int64   `json:"id"`
	Status    string  `json:"status"`
	Reference string  `json:"reference"`
	Currency  string  `json:"currency"`
	Amount    float64 `json:"amount"`
	FlwRef    string  `json:"flw_ref"`
}

type Authorization struct {
	Mode                 string `json:"mode"`
	Redirect             string `json:"redirect"`
	ValidateInstructions string `json:"validate_instructions"`
}

type chargeMeta struct {
	Authorization Authorization `json:"authorization"`
}

func (c *Client) ChargeMobileMoney(ctx context.Context, req MobileMoneyChargeRequest, traceId string) (*MobileMoneyChargeResponse, error) {
	if c.secretKey == "" {
		log.Printf("[flutterwave][trace=%s] simulate charge ref=%s amount=%.2f", traceId, req.Reference, req.Amount)
		return &MobileMoneyChargeResponse{
			ID:        time.Now().Unix(),
			Status:    "pending",
			TxRef:     req.Reference,
			FlwRef:    fmt.Sprintf("SIM-%s", req.Reference),
			Amount:    req.Amount,
			Currency:  req.Currency,
			Reference: req.Reference,
		}, nil
	}

	payload := map[string]interface{}{
		"tx_ref":       req.Reference,
		"amount":       req.Amount,
		"currency":     req.Currency,
		"email":        req.Email,
		"fullname":     req.FullName,
		"phone_number": req.PhoneNumber,
		"network":      strings.ToUpper(req.Network),
	}
	if req.Narration != "" {
		payload["narration"] = req.Narration
	}
	if req.CallbackURL != "" {
		payload["callback_url"] = req.CallbackURL
	}

	var envelope apiResponse
	if err := c.doWithRetry(ctx, http.MethodPost, c.baseURL+"/v3/charges?type=mobile_money_ghana", payload, &envelope, traceId); err != nil {
		return nil, err
	}
	var data MobileMoneyChargeResponse
	if len(envelope.Data) > 0 {
		if err := json.Unmarshal(envelope.Data, &data); err != nil {
			return nil, err
		}
	}
	if len(envelope.Meta) > 0 {
		var meta chargeMeta
		if err := json.Unmarshal(envelope.Meta, &meta); err == nil {
			data.Authorization = &meta.Authorization
		}
	}
	return &data, nil
}

func (c *Client) VerifyTransactionByReference(ctx context.Context, reference string, traceId string) (*Transaction, error) {
	if c.secretKey == "" {
		log.Printf("[flutterwave][trace=%s] simulate verify ref=%s", traceId, reference)
		return &Transaction{
			ID:        time.Now().Unix(),
			Status:    "successful",
			TxRef:     reference,
			Reference: reference,
			Currency:  "GHS",
		}, nil
	}
	endpoint := fmt.Sprintf("%s/v3/transactions/verify_by_reference?tx_ref=%s", c.baseURL, url.QueryEscape(reference))
	var envelope apiResponse
	if err := c.doWithRetry(ctx, http.MethodGet, endpoint, nil, &envelope, traceId); err != nil {
		return nil, err
	}
	if len(envelope.Data) == 0 {
		return nil, fmt.Errorf("flutterwave verify: empty response for %s", reference)
	}
	var data Transaction
	if err := json.Unmarshal(envelope.Data, &data); err != nil {
		return nil, err
	}
	return &data, nil
}

func (c *Client) InitiateTransfer(ctx context.Context, req TransferRequest, traceId string) (*TransferResponse, error) {
	if c.secretKey == "" {
		log.Printf("[flutterwave][trace=%s] simulate transfer ref=%s amount=%.2f", traceId, req.Reference, req.Amount)
		return &TransferResponse{
			ID:        time.Now().Unix(),
			Status:    "pending",
			Reference: req.Reference,
			Amount:    req.Amount,
			Currency:  req.Currency,
			FlwRef:    fmt.Sprintf("SIM-%s", req.Reference),
		}, nil
	}

	payload := map[string]interface{}{
		"account_bank":   strings.ToUpper(req.AccountBank),
		"account_number": req.AccountNumber,
		"amount":         req.Amount,
		"currency":       req.Currency,
		"reference":      req.Reference,
		"narration":      req.Narration,
	}
	if req.DebitCurrency != "" {
		payload["debit_currency"] = req.DebitCurrency
	}
	if req.CallbackURL != "" {
		payload["callback_url"] = req.CallbackURL
	}
	if req.Beneficiary != "" {
		payload["beneficiary_name"] = req.Beneficiary
	}

	var envelope apiResponse
	if err := c.doWithRetry(ctx, http.MethodPost, c.transferBase+"/v3/transfers", payload, &envelope, traceId); err != nil {
		return nil, err
	}
	var data TransferResponse
	if len(envelope.Data) > 0 {
		if err := json.Unmarshal(envelope.Data, &data); err != nil {
			return nil, err
		}
	}
	return &data, nil
}

func (c *Client) GetTransferByReference(ctx context.Context, reference string, traceId string) (*TransferResponse, error) {
	if c.secretKey == "" {
		log.Printf("[flutterwave][trace=%s] simulate get-transfer ref=%s", traceId, reference)
		return &TransferResponse{
			ID:        time.Now().Unix(),
			Status:    "successful",
			Reference: reference,
		}, nil
	}
	endpoint := fmt.Sprintf("%s/v3/transfers?reference=%s", c.transferBase, url.QueryEscape(reference))
	var envelope apiResponse
	if err := c.doWithRetry(ctx, http.MethodGet, endpoint, nil, &envelope, traceId); err != nil {
		return nil, err
	}
	if len(envelope.Data) == 0 {
		return nil, fmt.Errorf("transfer not found for %s", reference)
	}
	var transfers []TransferResponse
	if err := json.Unmarshal(envelope.Data, &transfers); err != nil {
		return nil, err
	}
	if len(transfers) == 0 {
		return nil, fmt.Errorf("transfer not found for %s", reference)
	}
	return &transfers[0], nil
}

type apiResponse struct {
	Status  string          `json:"status"`
	Message string          `json:"message"`
	Data    json.RawMessage `json:"data"`
	Meta    json.RawMessage `json:"meta"`
}

// retryableError indicates a transient HTTP error that should be retried.
type retryableError struct {
	status int
	body   string
}

func (e *retryableError) Error() string {
	return fmt.Sprintf("flutterwave http %d: %s", e.status, e.body)
}

func (c *Client) doWithRetry(ctx context.Context, method, endpoint string, payload interface{}, envelope *apiResponse, traceId string) error {
	var lastErr error
	for attempt := 0; attempt <= maxRetries; attempt++ {
		if attempt > 0 {
			backoff := time.Duration(attempt) * 500 * time.Millisecond
			log.Printf("[flutterwave][trace=%s] retry %d/%d after %v for %s %s", traceId, attempt, maxRetries, backoff, method, endpoint)
			select {
			case <-time.After(backoff):
			case <-ctx.Done():
				return ctx.Err()
			}
		}
		lastErr = c.do(ctx, method, endpoint, payload, envelope, traceId)
		if lastErr == nil {
			return nil
		}
		// Only retry on 5xx server errors
		if re, ok := lastErr.(*retryableError); ok && re.status >= 500 {
			continue
		}
		return lastErr
	}
	return lastErr
}

func (c *Client) do(ctx context.Context, method, endpoint string, payload interface{}, envelope *apiResponse, traceId string) error {
	var body io.Reader
	var rawPayload []byte
	if payload != nil {
		var err error
		rawPayload, err = json.Marshal(payload)
		if err != nil {
			return err
		}
		body = bytes.NewReader(rawPayload)
	}

	req, err := http.NewRequestWithContext(ctx, method, endpoint, body)
	if err != nil {
		return err
	}
	if payload != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	req.Header.Set("Authorization", "Bearer "+c.secretKey)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		log.Printf("[flutterwave][trace=%s] %s %s network_error=%v", traceId, method, endpoint, err)
		return err
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}
	log.Printf("[flutterwave][trace=%s] %s %s status=%d body=%s", traceId, method, endpoint, resp.StatusCode, string(respBody))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		if resp.StatusCode >= 500 {
			return &retryableError{status: resp.StatusCode, body: string(respBody)}
		}
		return fmt.Errorf("flutterwave http %s: %s", resp.Status, string(respBody))
	}
	if err := json.Unmarshal(respBody, envelope); err != nil {
		return err
	}
	if strings.ToLower(envelope.Status) != "success" {
		return fmt.Errorf("flutterwave error: %s", envelope.Message)
	}
	return nil
}
