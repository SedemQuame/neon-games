package middleware

import (
	"strings"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/websocket/v2"

	"gamehub/game-session-service/internal/auth"
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

func UpgradeWS(validator *auth.Validator) fiber.Handler {
	return func(c *fiber.Ctx) error {
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
		if websocket.IsWebSocketUpgrade(c) {
			c.Locals("userId", claims.UserID)
			c.Locals("role", claims.Role)
			return c.Next()
		}
		return fiber.ErrUpgradeRequired
	}
}
