package config

import (
	"log"
	"os"
	"strings"
)

type Config struct {
	Port          string
	MongoURI      string
	RedisAddr     string
	RedisPassword string

	PaystackSecretKey          string
	PaystackPublicKey          string
	PaystackSubaccount         string
	PaystackBaseURL            string
	PaystackWebhookSecret      string
	PaystackMoMoCallbackURL    string
	PaystackWithdrawalCallback string
	PaystackAllowedChannels    []string
	PaystackDefaultCurrency    string

	TatumAPIKey        string
	TatumWebhookSecret string

	WalletServiceURL   string
	InternalServiceKey string

	JWTPublicKeyPath string
	JWTIssuer        string
	AppEnv           string
}

func Load() *Config {
	return &Config{
		Port:                       getEnv("PORT", "8003"),
		MongoURI:                   mustGetEnv("MONGO_URI"),
		RedisAddr:                  getEnv("REDIS_ADDR", "localhost:6379"),
		RedisPassword:              getEnv("REDIS_PASSWORD", ""),
		PaystackSecretKey:          getEnv("PAYSTACK_SECRET_KEY", ""),
		PaystackPublicKey:          getEnv("PAYSTACK_PUBLIC_KEY", ""),
		PaystackSubaccount:         getEnv("PAYSTACK_SUBACCOUNT", ""),
		PaystackBaseURL:            getEnv("PAYSTACK_BASE_URL", "https://api.paystack.co"),
		PaystackWebhookSecret:      getEnv("PAYSTACK_WEBHOOK_SECRET", ""),
		PaystackMoMoCallbackURL:    getEnv("PAYSTACK_MOMO_CALLBACK_URL", "https://api.gamehub.io/webhooks/payment/paystack"),
		PaystackWithdrawalCallback: getEnv("PAYSTACK_WITHDRAWAL_CALLBACK_URL", "https://api.gamehub.io/webhooks/payment/paystack/withdrawal"),
		PaystackAllowedChannels:    splitAndTrim(getEnv("PAYSTACK_ALLOWED_CHANNELS", "mtn-gh,vodafone-gh,airteltigo-gh")),
		PaystackDefaultCurrency:    getEnv("PAYSTACK_DEFAULT_CURRENCY", "GHS"),
		TatumAPIKey:                getEnv("TATUM_API_KEY", ""),
		TatumWebhookSecret:         getEnv("TATUM_WEBHOOK_SECRET", ""),
		WalletServiceURL:           getEnv("WALLET_SERVICE_URL", "http://wallet-service:8004"),
		InternalServiceKey:         getEnv("INTERNAL_SERVICE_KEY", "dev-service-key"),
		JWTPublicKeyPath:           getEnv("JWT_PUBLIC_KEY_PATH", "/run/secrets/jwt_public.pem"),
		JWTIssuer:                  getEnv("JWT_ISSUER", "gamehub-auth"),
		AppEnv:                     getEnv("APP_ENV", "development"),
	}
}

func mustGetEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		log.Fatalf("FATAL: %s required", key)
	}
	return v
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func splitAndTrim(raw string) []string {
	if raw == "" {
		return nil
	}
	parts := strings.Split(raw, ",")
	out := make([]string, 0, len(parts))
	for _, part := range parts {
		if trimmed := strings.TrimSpace(part); trimmed != "" {
			out = append(out, trimmed)
		}
	}
	return out
}
