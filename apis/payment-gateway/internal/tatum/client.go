package tatum

import "context"

type Client struct {
	ApiKey string
}

func NewClient(apiKey string) *Client {
	return &Client{ApiKey: apiKey}
}

func (c *Client) GenerateAddress(ctx context.Context, coin string) (string, error) {
	return "mock-address-" + coin, nil
}
