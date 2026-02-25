package config

import (
	"log"
	"os"
	"strconv"
	"time"
)

// Config holds all environment-driven configuration for the auth service.
type Config struct {
	Port           string
	MongoURI       string
	RedisAddr      string
	RedisPassword  string
	JWTPrivateKey  string // path to PEM file
	JWTPublicKey   string // path to PEM file
	AccessTTLMin   string
	RefreshTTLDays string
	AccessTTL      time.Duration
	RefreshTTL     time.Duration
	AllowedOrigins string
	JWTIssuer      string

	// Hubtel SMS (OTP delivery)
	HubtelSMSClientID     string
	HubtelSMSClientSecret string
	HubtelSMSFrom         string
	OTPTTLMinutes         string

	// Google & Apple OAuth
	GoogleClientID string
	AppleClientID  string

	// Internal service key (for calls to wallet-service, etc.)
	InternalServiceKey string

	// Email + password reset
	ResendAPIKey            string
	EmailFrom               string
	PasswordResetURL        string
	PasswordResetTTLMinutes string
	PasswordResetTTL        time.Duration

	AppEnv   string
	LogLevel string
}

// Load reads configuration from environment variables.
// Any required variable that is missing causes an immediate fatal error.
func Load() *Config {
	cfg := &Config{
		Port:           getEnv("PORT", "8001"),
		MongoURI:       mustGetEnv("MONGO_URI"),
		RedisAddr:      getEnv("REDIS_ADDR", "localhost:6379"),
		RedisPassword:  getEnv("REDIS_PASSWORD", ""),
		JWTPrivateKey:  getEnv("JWT_PRIVATE_KEY_PATH", "secrets/jwt_private.pem"),
		JWTPublicKey:   getEnv("JWT_PUBLIC_KEY_PATH", "secrets/jwt_public.pem"),
		AccessTTLMin:   getEnv("JWT_ACCESS_TTL_MINUTES", "15"),
		RefreshTTLDays: getEnv("JWT_REFRESH_TTL_DAYS", "7"),
		AllowedOrigins: getEnv("CORS_ALLOWED_ORIGINS", "*"),
		JWTIssuer:      getEnv("JWT_ISSUER", "gamehub-auth"),

		HubtelSMSClientID:     getEnv("HUBTEL_SMS_CLIENT_ID", ""),
		HubtelSMSClientSecret: getEnv("HUBTEL_SMS_CLIENT_SECRET", ""),
		HubtelSMSFrom:         getEnv("HUBTEL_SMS_FROM", "GameHub"),
		OTPTTLMinutes:         getEnv("OTP_TTL_MINUTES", "5"),

		GoogleClientID: getEnv("GOOGLE_CLIENT_ID", ""),
		AppleClientID:  getEnv("APPLE_CLIENT_ID", ""),

		InternalServiceKey: getEnv("INTERNAL_SERVICE_KEY", "dev-internal-key"),

		ResendAPIKey:            getEnv("RESEND_API_KEY", ""),
		EmailFrom:               getEnv("EMAIL_FROM", "GameHub Support <support@gamehub.local>"),
		PasswordResetURL:        getEnv("PASSWORD_RESET_URL", "https://gamehub.local/reset-password"),
		PasswordResetTTLMinutes: getEnv("PASSWORD_RESET_TTL_MINUTES", "30"),

		AppEnv:   getEnv("APP_ENV", "development"),
		LogLevel: getEnv("LOG_LEVEL", "info"),
	}
	cfg.AccessTTL = parseMinutes(cfg.AccessTTLMin, 15)
	cfg.RefreshTTL = parseDays(cfg.RefreshTTLDays, 7)
	cfg.PasswordResetTTL = parseMinutes(cfg.PasswordResetTTLMinutes, 30)
	return cfg
}

func mustGetEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		log.Fatalf("FATAL: required environment variable %q is not set", key)
	}
	return v
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func parseMinutes(raw string, fallback int) time.Duration {
	if raw == "" {
		return time.Duration(fallback) * time.Minute
	}
	minutes, err := strconv.Atoi(raw)
	if err != nil || minutes <= 0 {
		log.Printf("⚠️ invalid minutes value %q, defaulting to %d", raw, fallback)
		return time.Duration(fallback) * time.Minute
	}
	return time.Duration(minutes) * time.Minute
}

func parseDays(raw string, fallback int) time.Duration {
	if raw == "" {
		return time.Duration(fallback) * 24 * time.Hour
	}
	days, err := strconv.Atoi(raw)
	if err != nil || days <= 0 {
		log.Printf("⚠️ invalid days value %q, defaulting to %d", raw, fallback)
		return time.Duration(fallback) * 24 * time.Hour
	}
	return time.Duration(days) * 24 * time.Hour
}
