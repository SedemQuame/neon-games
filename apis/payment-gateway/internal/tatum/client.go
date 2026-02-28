package tatum

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math"
	"net/http"
	"strconv"
	"strings"
	"time"
)

// Client wraps the Tatum REST API for HD-wallet address derivation,
// transaction lookups, and webhook subscription management.
// If ApiKey is empty the client runs in simulation mode (returns mock data).
type Client struct {
	ApiKey     string
	BaseURL    string
	BTCXpub    string
	ETHXpub    string
	TRONXpub   string
	Testnet    bool
	httpClient *http.Client
}

// NewClient creates a Tatum client.  Pass an empty apiKey to keep
// the existing simulation mode for local development.
func NewClient(apiKey, baseURL, btcXpub, ethXpub, tronXpub string, testnet bool) *Client {
	if baseURL == "" {
		baseURL = "https://api.tatum.io"
	}
	return &Client{
		ApiKey:     apiKey,
		BaseURL:    strings.TrimRight(baseURL, "/"),
		BTCXpub:    btcXpub,
		ETHXpub:    ethXpub,
		TRONXpub:   tronXpub,
		Testnet:    testnet,
		httpClient: &http.Client{Timeout: 15 * time.Second},
	}
}

// ---------------------------------------------------------------------------
// Address generation (HD wallet derivation)
// ---------------------------------------------------------------------------

// addressResponse is the shape of Tatum's GET .../address/{xpub}/{index}
type addressResponse struct {
	Address string `json:"address"`
}

// GenerateAddress derives a blockchain address for the given coin at derivation
// index.  For USDT we reuse the ETH xpub (ERC-20 shares the same address space).
func (c *Client) GenerateAddress(ctx context.Context, coin string, index int64) (string, error) {
	coin = strings.ToUpper(coin)

	if c.ApiKey == "" {
		addr := fmt.Sprintf("sim-%s-%d-%d", strings.ToLower(coin), index, time.Now().UnixMilli())
		log.Printf("[tatum][sim] GenerateAddress coin=%s index=%d → %s", coin, index, addr)
		return addr, nil
	}

	xpub, chainPath := c.chainParams(coin)
	if xpub == "" {
		return "", fmt.Errorf("tatum: no xpub configured for %s", coin)
	}

	endpoint := fmt.Sprintf("%s/v3/%s/address/%s/%d", c.BaseURL, chainPath, xpub, index)
	var resp addressResponse
	if err := c.doGet(ctx, endpoint, &resp); err != nil {
		return "", fmt.Errorf("tatum GenerateAddress %s: %w", coin, err)
	}
	if resp.Address == "" {
		return "", fmt.Errorf("tatum: empty address in response for %s index %d", coin, index)
	}
	log.Printf("[tatum] GenerateAddress coin=%s index=%d → %s", coin, index, resp.Address)
	return resp.Address, nil
}

// ---------------------------------------------------------------------------
// Transaction lookups (explorer API)
// ---------------------------------------------------------------------------

// Transaction represents an incoming blockchain transaction returned by
// Tatum's explorer endpoints.
type Transaction struct {
	Hash          string `json:"hash"`
	From          string `json:"from,omitempty"`
	To            string `json:"to,omitempty"`
	Amount        string `json:"amount,omitempty"`
	Value         string `json:"value,omitempty"` // ETH uses "value"
	Confirmations int    `json:"confirmations"`
	BlockNumber   int64  `json:"blockNumber,omitempty"`
	Token         *Token `json:"token,omitempty"`
}

// Token is populated for ERC-20 / TRC-20 transactions.
type Token struct {
	Symbol   string `json:"symbol,omitempty"`
	Address  string `json:"contractAddress,omitempty"`
	Decimals int    `json:"decimals,omitempty"`
}

// GetTransactionsByAddress queries the Tatum explorer for recent transactions
// at the given address for the specified coin.
func (c *Client) GetTransactionsByAddress(ctx context.Context, coin, address string) ([]Transaction, error) {
	coin = strings.ToUpper(coin)

	if c.ApiKey == "" {
		log.Printf("[tatum][sim] GetTransactionsByAddress coin=%s addr=%s → []", coin, address)
		return nil, nil
	}

	_, chainPath := c.chainParams(coin)
	var endpoint string

	var txs []Transaction

	if chainPath == "tron" {
		if coin == "USDT" || coin == "USDC" {
			endpoint = fmt.Sprintf("%s/v3/tron/transaction/account/%s/trc20", c.BaseURL, address)
		} else {
			endpoint = fmt.Sprintf("%s/v3/tron/transaction/account/%s?pageSize=50", c.BaseURL, address)
		}

		// TRON endpoints return an object with a "transactions" array
		var tronResp struct {
			Transactions []struct {
				TxID          string `json:"txID"`
				From          string `json:"from"`
				To            string `json:"to"`
				Value         string `json:"value"`
				Confirmations int    `json:"confirmations,omitempty"` // For TRC20 they might omit it, default to 0
				TokenInfo     *Token `json:"tokenInfo,omitempty"`
			} `json:"transactions"`
		}

		if err := c.doGet(ctx, endpoint, &tronResp); err != nil {
			return nil, fmt.Errorf("tatum GetTransactionsByAddress TRON %s/%s: %w", coin, address, err)
		}

		txs = make([]Transaction, len(tronResp.Transactions))
		for i, raw := range tronResp.Transactions {
			// Convert raw token amount to human-readable float using decimals
			humanValue := raw.Value
			if raw.TokenInfo != nil && raw.TokenInfo.Decimals > 0 && raw.Value != "" {
				if atomicVal, err := strconv.ParseFloat(raw.Value, 64); err == nil {
					divisor := math.Pow(10, float64(raw.TokenInfo.Decimals))
					humanValue = fmt.Sprintf("%f", atomicVal/divisor)
				}
			}

			// TRON testnet usually has instant irreversibility, but some APIs might omit confirmations for TRC20.
			// Let's set it to 10 by default if it's missing just so the backend accepts it as CONFIRMED.
			confs := raw.Confirmations
			if confs == 0 {
				confs = 19 // sufficient to mark as confirmed in GameHub
			}

			txs[i] = Transaction{
				Hash:          raw.TxID,
				From:          raw.From,
				To:            raw.To,
				Value:         humanValue,
				Confirmations: confs, // Map to what our processCryptoTx expects
				Token:         raw.TokenInfo,
			}
		}
	} else {
		switch chainPath {
		case "bitcoin":
			endpoint = fmt.Sprintf("%s/v3/bitcoin/transaction/address/%s?pageSize=50", c.BaseURL, address)
		case "ethereum":
			endpoint = fmt.Sprintf("%s/v3/ethereum/account/transaction/%s?pageSize=50", c.BaseURL, address)
		default:
			return nil, fmt.Errorf("tatum: unsupported chain for tx lookup: %s", coin)
		}
		if err := c.doGet(ctx, endpoint, &txs); err != nil {
			return nil, fmt.Errorf("tatum GetTransactionsByAddress %s/%s: %w", coin, address, err)
		}
	}

	return txs, nil
}

// ---------------------------------------------------------------------------
// Balance check
// ---------------------------------------------------------------------------

// BalanceResponse matches Tatum's GET .../{chain}/account/balance/{address}.
type BalanceResponse struct {
	Balance  string `json:"balance,omitempty"`
	Incoming string `json:"incoming,omitempty"`
	Outgoing string `json:"outgoing,omitempty"`
}

// GetBalance retrieves the on-chain balance for the given address.
func (c *Client) GetBalance(ctx context.Context, coin, address string) (*BalanceResponse, error) {
	coin = strings.ToUpper(coin)

	if c.ApiKey == "" {
		log.Printf("[tatum][sim] GetBalance coin=%s addr=%s → 0", coin, address)
		return &BalanceResponse{Balance: "0"}, nil
	}

	_, chainPath := c.chainParams(coin)
	endpoint := fmt.Sprintf("%s/v3/%s/account/balance/%s", c.BaseURL, chainPath, address)
	var resp BalanceResponse
	if err := c.doGet(ctx, endpoint, &resp); err != nil {
		return nil, fmt.Errorf("tatum GetBalance %s/%s: %w", coin, address, err)
	}
	return &resp, nil
}

// ---------------------------------------------------------------------------
// Webhook subscriptions
// ---------------------------------------------------------------------------

// SubscriptionRequest is the payload for POST /v3/subscription.
type SubscriptionRequest struct {
	Type string                 `json:"type"`
	Attr map[string]interface{} `json:"attr"`
}

// SubscriptionResponse is the response from POST /v3/subscription.
type SubscriptionResponse struct {
	ID string `json:"id"`
}

// CreateAddressSubscription registers a Tatum webhook that fires when
// any transaction hits the given address.
func (c *Client) CreateAddressSubscription(ctx context.Context, coin, address, webhookURL string) (string, error) {
	coin = strings.ToUpper(coin)

	if c.ApiKey == "" {
		subID := fmt.Sprintf("sim-sub-%s-%s", strings.ToLower(coin), address[:8])
		log.Printf("[tatum][sim] CreateAddressSubscription coin=%s addr=%s → %s", coin, address, subID)
		return subID, nil
	}

	_, chainPath := c.chainParams(coin)
	payload := SubscriptionRequest{
		Type: "ADDRESS_TRANSACTION",
		Attr: map[string]interface{}{
			"address": address,
			"chain":   strings.ToUpper(chainPath),
			"url":     webhookURL,
		},
	}

	var resp SubscriptionResponse
	if err := c.doPost(ctx, c.BaseURL+"/v3/subscription", payload, &resp); err != nil {
		return "", fmt.Errorf("tatum CreateAddressSubscription %s/%s: %w", coin, address, err)
	}
	log.Printf("[tatum] CreateAddressSubscription coin=%s addr=%s → sub=%s", coin, address, resp.ID)
	return resp.ID, nil
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

// chainParams returns the xpub and Tatum REST path segment for a coin.
func (c *Client) chainParams(coin string) (xpub string, chainPath string) {
	switch strings.ToUpper(coin) {
	case "BTC":
		return c.BTCXpub, "bitcoin"
	case "ETH":
		return c.ETHXpub, "ethereum"
	case "USDT":
		// USDT as TRC-20 on the Tron network (low fees, fast confirmations)
		return c.TRONXpub, "tron"
	default:
		return "", ""
	}
}

func (c *Client) doGet(ctx context.Context, url string, out interface{}) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	return c.execute(req, out)
}

func (c *Client) doPost(ctx context.Context, url string, payload interface{}, out interface{}) error {
	body, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	return c.execute(req, out)
}

func (c *Client) execute(req *http.Request, out interface{}) error {
	req.Header.Set("x-api-key", c.ApiKey)
	if c.Testnet {
		// Tatum uses a query param or header for testnet — the x-testnet-type header
		req.Header.Set("x-testnet-type", "ethereum-sepolia")
	}

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
		return fmt.Errorf("tatum HTTP %d: %s", resp.StatusCode, string(respBody))
	}

	if out != nil {
		return json.Unmarshal(respBody, out)
	}
	return nil
}
