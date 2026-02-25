package config

import (
	"log"
	"os"
	"strconv"
)

type Config struct {
	Port             string
	MongoURI         string
	RedisAddr        string
	RedisPassword    string
	WalletServiceURL string
	InternalKey      string
	OrderQueue       string
	OutcomePrefix    string
	AppEnv           string
	JWTPublicKeyPath string
	JWTIssuer        string
	StaleSweepSec    int
	StaleRefundSec   int
}

func Load() *Config {
	return &Config{
		Port:             getEnv("PORT", "8002"),
		MongoURI:         mustGetEnv("MONGO_URI"),
		RedisAddr:        getEnv("REDIS_ADDR", "localhost:6379"),
		RedisPassword:    getEnv("REDIS_PASSWORD", ""),
		WalletServiceURL: getEnv("WALLET_SERVICE_URL", "http://wallet-service:8004"),
		InternalKey:      getEnv("INTERNAL_SERVICE_KEY", "dev-internal-key"),
		OrderQueue:       getEnv("TRADE_ORDER_QUEUE", "trade:orders"),
		OutcomePrefix:    getEnv("GAME_OUTCOME_PREFIX", "game:outcome"),
		AppEnv:           getEnv("APP_ENV", "development"),
		JWTPublicKeyPath: getEnv("JWT_PUBLIC_KEY_PATH", "/run/secrets/jwt_public.pem"),
		JWTIssuer:        getEnv("JWT_ISSUER", "gamehub-auth"),
		StaleSweepSec:    getEnvInt("GAME_STALE_SWEEP_INTERVAL_SECONDS", 20),
		StaleRefundSec:   getEnvInt("GAME_STALE_REFUND_SECONDS", 90),
	}
}

func mustGetEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		log.Fatalf("required env %s missing", key)
	}
	return v
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func getEnvInt(key string, fallback int) int {
	if v := os.Getenv(key); v != "" {
		if i, err := strconv.Atoi(v); err == nil {
			return i
		}
	}
	return fallback
}
