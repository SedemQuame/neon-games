package middleware

import (
	"github.com/gofiber/fiber/v2"

	"gamehub/wallet-service/internal/auth"
	"gamehub/wallet-service/internal/config"
)

// RequireAuth validates incoming JWT access tokens and exposes the claims on the Fiber context.
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
		if c.Get("X-Internal-Key") != cfg.InternalServiceKey {
			return c.Status(fiber.StatusForbidden).JSON(fiber.Map{"error": "forbidden"})
		}
		return c.Next()
	}
}
