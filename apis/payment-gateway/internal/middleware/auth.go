package middleware

import (
	"crypto/hmac"
	"crypto/sha256"
	"crypto/sha512"
	"crypto/subtle"
	"encoding/hex"
	"strings"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/websocket/v2"

	"gamehub/payment-gateway/internal/auth"
	"gamehub/payment-gateway/internal/config"
)

func RequireAuth(validator *auth.Validator) fiber.Handler {
	return func(c *fiber.Ctx) error {
		claims, err := validator.FromHeader(c.Get("Authorization"))
		if err != nil {
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "unauthorized"})
		}
		c.Locals("userId", claims.UserID)
		c.Locals("role", claims.Role)
		return c.Next()
	}
}

func RequireInternalKey(cfg *config.Config) fiber.Handler {
	return func(c *fiber.Ctx) error {
		key := c.Get("X-Internal-Key")
		if key != cfg.InternalServiceKey {
			return c.Status(fiber.StatusForbidden).JSON(fiber.Map{"error": "forbidden"})
		}
		return c.Next()
	}
}

func VerifyTatumHMAC(cfg *config.Config) fiber.Handler {
	return func(c *fiber.Ctx) error {
		if cfg.TatumWebhookSecret == "" {
			return c.Next()
		}
		signature := c.Get("X-Tatum-Signature")
		if !verifyHMACSHA256(signature, c.Body(), cfg.TatumWebhookSecret) {
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "invalid tatum signature"})
		}
		return c.Next()
	}
}

func VerifyPaystackHMAC(cfg *config.Config) fiber.Handler {
	return func(c *fiber.Ctx) error {
		if cfg.PaystackWebhookSecret == "" {
			return c.Next()
		}
		signature := c.Get("X-Paystack-Signature")
		if !verifyHMACSHA512(signature, c.Body(), cfg.PaystackWebhookSecret) {
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "invalid paystack signature"})
		}
		return c.Next()
	}
}

func UpgradeWS(validator *auth.Validator) fiber.Handler {
	return func(c *fiber.Ctx) error {
		if !websocket.IsWebSocketUpgrade(c) {
			return fiber.ErrUpgradeRequired
		}
		var (
			claims *auth.Claims
			err    error
		)
		token := strings.TrimSpace(c.Query("token"))
		if token != "" {
			claims, err = validator.FromString(token)
		} else {
			claims, err = validator.FromHeader(c.Get("Authorization"))
		}
		if err != nil {
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"error": "missing or invalid token"})
		}
		c.Locals("userId", claims.UserID)
		c.Locals("role", claims.Role)
		return c.Next()
	}
}

func verifyHMACSHA256(provided string, payload []byte, secret string) bool {
	if provided == "" || secret == "" {
		return false
	}
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(payload)
	expected := hex.EncodeToString(mac.Sum(nil))
	return subtle.ConstantTimeCompare([]byte(strings.ToLower(provided)), []byte(expected)) == 1
}

func verifyHMACSHA512(provided string, payload []byte, secret string) bool {
	if provided == "" || secret == "" {
		return false
	}
	mac := hmac.New(sha512.New, []byte(secret))
	mac.Write(payload)
	expected := hex.EncodeToString(mac.Sum(nil))
	return subtle.ConstantTimeCompare([]byte(strings.ToLower(provided)), []byte(expected)) == 1
}
