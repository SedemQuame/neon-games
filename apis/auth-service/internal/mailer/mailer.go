package mailer

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"
)

// Client wraps a lightweight transactional email sender.
// It currently targets the Resend HTTP API but falls back to logging when
// credentials are missing (useful for local development).
type Client struct {
	apiKey     string
	from       string
	resetURL   string
	httpClient *http.Client
}

func New(apiKey, from, resetURL string) *Client {
	return &Client{
		apiKey:   strings.TrimSpace(apiKey),
		from:     strings.TrimSpace(from),
		resetURL: strings.TrimSpace(resetURL),
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

func (c *Client) SendPasswordReset(ctx context.Context, email, token string) error {
	if email == "" || token == "" {
		return fmt.Errorf("email and token required")
	}

	resetLink := c.composeResetLink(token)
	if c.apiKey == "" || c.from == "" || c.resetURL == "" {
		log.Printf("⚠️  Password reset link for %s: %s", email, resetLink)
		return nil
	}

	payload := map[string]interface{}{
		"from":    c.from,
		"to":      email,
		"subject": "Reset your Glory Grid password",
		"html": fmt.Sprintf(
			`<p>We received a request to reset your Glory Grid password.</p>
<p><a href="%s" style="display:inline-block;padding:10px 18px;background:#0ea5e9;color:#fff;border-radius:6px;text-decoration:none;">Reset Password</a></p>
<p>This link expires in 30 minutes. If you did not request this, you can ignore this email.</p>`,
			resetLink,
		),
		"text": fmt.Sprintf(
			"Use the link below to reset your Glory Grid password (expires in 30 minutes):\n%s\nIf you did not request this change you can ignore this email.",
			resetLink,
		),
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://api.resend.com/emails", bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+c.apiKey)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		return fmt.Errorf("resend returned status %d", resp.StatusCode)
	}
	return nil
}

func (c *Client) composeResetLink(token string) string {
	base := c.resetURL
	if base == "" {
		base = "https://glorygrid.local/reset-password"
	}
	separator := "?"
	if strings.Contains(base, "?") {
		separator = "&"
	}
	return fmt.Sprintf("%s%stoken=%s", base, separator, token)
}
