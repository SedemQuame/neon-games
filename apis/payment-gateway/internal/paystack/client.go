package paystack

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// Client wraps Paystack's REST API surface that we use (charge + transfer).
type Client struct {
	secretKey  string
	baseURL    string
	subaccount string
	httpClient *http.Client
}

func NewClient(secretKey, baseURL, subaccount string) *Client {
	if baseURL == "" {
		baseURL = "https://api.paystack.co"
	}
	return &Client{
		secretKey:  secretKey,
		baseURL:    strings.TrimRight(baseURL, "/"),
		subaccount: subaccount,
		httpClient: &http.Client{Timeout: 15 * time.Second},
	}
}

type ChargeRequest struct {
	Reference   string
	Email       string
	AmountMinor int64  // amount in the smallest currency unit (pesewas)
	Currency    string // e.g., GHS
	Phone       string
	Provider    string // mtn | vodafone | airtel
}

type ChargeResponse struct {
	Reference        string `json:"reference"`
	Status           string `json:"status"`
	DisplayText      string `json:"display_text"`
	AuthorizationURL string `json:"authorization_url"`
}

type TransactionStatus struct {
	Reference string `json:"reference"`
	Status    string `json:"status"`
	Amount    int64  `json:"amount"`
	Currency  string `json:"currency"`
}

type TransferRecipientRequest struct {
	Name     string
	Phone    string
	Provider string
	Currency string
}

type TransferRecipient struct {
	RecipientCode string `json:"recipient_code"`
}

type TransferRequest struct {
	Reference     string
	AmountMinor   int64
	Currency      string
	RecipientCode string
	Reason        string
}

type Transfer struct {
	TransferCode string `json:"transfer_code"`
	Reference    string `json:"reference"`
	Status       string `json:"status"`
}

func (c *Client) ChargeMobileMoney(ctx context.Context, req ChargeRequest) (*ChargeResponse, error) {
	if c.secretKey == "" {
		// Simulation mode
		return &ChargeResponse{
			Reference:   req.Reference,
			Status:      "pending",
			DisplayText: "Simulated Paystack charge",
		}, nil
	}

	payload := map[string]interface{}{
		"email":     req.Email,
		"amount":    req.AmountMinor,
		"currency":  req.Currency,
		"reference": req.Reference,
		"mobile_money": map[string]string{
			"phone":    req.Phone,
			"provider": req.Provider,
		},
	}
	if c.subaccount != "" {
		payload["subaccount"] = c.subaccount
	}

	var data ChargeResponse
	if err := c.do(ctx, http.MethodPost, "/charge", payload, &data); err != nil {
		return nil, err
	}
	return &data, nil
}

func (c *Client) GetTransactionStatus(ctx context.Context, reference string) (*TransactionStatus, error) {
	if c.secretKey == "" {
		return &TransactionStatus{
			Reference: reference,
			Status:    "success",
			Amount:    0,
			Currency:  "GHS",
		}, nil
	}
	var data TransactionStatus
	path := fmt.Sprintf("/transaction/verify/%s", reference)
	if err := c.do(ctx, http.MethodGet, path, nil, &data); err != nil {
		return nil, err
	}
	return &data, nil
}

func (c *Client) CreateTransferRecipient(ctx context.Context, req TransferRecipientRequest) (*TransferRecipient, error) {
	if c.secretKey == "" {
		return &TransferRecipient{RecipientCode: fmt.Sprintf("SIM-%s", req.Phone)}, nil
	}
	payload := map[string]interface{}{
		"type":     "mobile_money",
		"name":     req.Name,
		"currency": req.Currency,
		"details": map[string]string{
			"phone":    req.Phone,
			"provider": req.Provider,
		},
	}
	var data TransferRecipient
	if err := c.do(ctx, http.MethodPost, "/transferrecipient", payload, &data); err != nil {
		return nil, err
	}
	return &data, nil
}

func (c *Client) InitiateTransfer(ctx context.Context, req TransferRequest) (*Transfer, error) {
	if c.secretKey == "" {
		return &Transfer{
			TransferCode: fmt.Sprintf("SIM-%s", req.Reference),
			Reference:    req.Reference,
			Status:       "success",
		}, nil
	}
	payload := map[string]interface{}{
		"source":    "balance",
		"amount":    req.AmountMinor,
		"currency":  req.Currency,
		"reason":    req.Reason,
		"reference": req.Reference,
		"recipient": req.RecipientCode,
	}
	var data Transfer
	if err := c.do(ctx, http.MethodPost, "/transfer", payload, &data); err != nil {
		return nil, err
	}
	return &data, nil
}

func (c *Client) GetTransferStatus(ctx context.Context, transferCode string) (*Transfer, error) {
	if c.secretKey == "" {
		return &Transfer{
			TransferCode: transferCode,
			Status:       "success",
		}, nil
	}
	var data Transfer
	path := fmt.Sprintf("/transfer/%s", transferCode)
	if err := c.do(ctx, http.MethodGet, path, nil, &data); err != nil {
		return nil, err
	}
	return &data, nil
}

type apiEnvelope struct {
	Status  bool            `json:"status"`
	Message string          `json:"message"`
	Data    json.RawMessage `json:"data"`
}

func (c *Client) do(ctx context.Context, method, path string, payload interface{}, out interface{}) error {
	var body io.Reader
	if payload != nil {
		buf, err := json.Marshal(payload)
		if err != nil {
			return err
		}
		body = bytes.NewReader(buf)
	}

	req, err := http.NewRequestWithContext(ctx, method, c.baseURL+path, body)
	if err != nil {
		return err
	}
	if payload != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	req.Header.Set("Authorization", "Bearer "+c.secretKey)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("paystack http %s: %s", resp.Status, string(respBody))
	}

	var envelope apiEnvelope
	if err := json.Unmarshal(respBody, &envelope); err != nil {
		return err
	}
	if !envelope.Status {
		return fmt.Errorf("paystack error: %s", envelope.Message)
	}
	if out == nil || len(envelope.Data) == 0 {
		return nil
	}
	return json.Unmarshal(envelope.Data, out)
}
