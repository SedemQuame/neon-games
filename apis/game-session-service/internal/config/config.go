package config

import (
	"log"
	"net"
	"net/url"
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
		RedisAddr:        resolveRedisAddr(),
		RedisPassword:    resolveRedisPassword(),
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

func resolveRedisAddr() string {
	if addr := os.Getenv("REDIS_ADDR"); addr != "" {
		return addr
	}
	if host := os.Getenv("REDISHOST"); host != "" {
		return net.JoinHostPort(host, getEnv("REDISPORT", "6379"))
	}
	if addr, _, ok := redisFromURL(os.Getenv("REDIS_URL")); ok {
		return addr
	}
	return "localhost:6379"
}

func resolveRedisPassword() string {
	if password := os.Getenv("REDIS_PASSWORD"); password != "" {
		return password
	}
	if password := os.Getenv("REDISPASSWORD"); password != "" {
		return password
	}
	if _, password, ok := redisFromURL(os.Getenv("REDIS_URL")); ok {
		return password
	}
	return ""
}

func redisFromURL(raw string) (addr, password string, ok bool) {
	if raw == "" {
		return "", "", false
	}
	parsed, err := url.Parse(raw)
	if err != nil || parsed.Host == "" {
		return "", "", false
	}
	addr = parsed.Host
	if parsed.Port() == "" {
		addr = net.JoinHostPort(parsed.Hostname(), "6379")
	}
	if parsed.User != nil {
		password, _ = parsed.User.Password()
	}
	return addr, password, true
}
