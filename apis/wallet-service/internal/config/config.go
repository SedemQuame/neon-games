package config

import (
	"log"
	"net"
	"net/url"
	"os"
	"strings"
)

type Config struct {
	Port               string
	MongoURI           string
	RedisAddr          string
	RedisPassword      string
	InternalServiceKey string
	AllowedOrigins     string
	AppEnv             string
	JWTPublicKeyPath   string
	JWTIssuer          string
}

func Load() *Config {
	cfg := &Config{
		Port:               getEnv("PORT", "8004"),
		MongoURI:           mustGetEnv("MONGO_URI"),
		RedisAddr:          resolveRedisAddr(),
		RedisPassword:      resolveRedisPassword(),
		InternalServiceKey: getEnv("INTERNAL_SERVICE_KEY", "dev-internal-key"),
		AllowedOrigins:     getEnv("CORS_ALLOWED_ORIGINS", "*"),
		AppEnv:             getEnv("APP_ENV", "development"),
		JWTPublicKeyPath:   getEnv("JWT_PUBLIC_KEY_PATH", ""),
		JWTIssuer:          getEnv("JWT_ISSUER", "gamehub-auth"),
	}
	return cfg
}

func mustGetEnv(key string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	log.Fatalf("required env %s is not set", key)
	return ""
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func resolveRedisAddr() string {
	if addr, _, ok := redisFromURL(os.Getenv("REDIS_URL")); ok {
		return addr
	}
	if host := os.Getenv("REDISHOST"); host != "" {
		return net.JoinHostPort(host, getEnv("REDISPORT", "6379"))
	}
	if addr := os.Getenv("REDIS_ADDR"); addr != "" {
		return addr
	}
	return "localhost:6379"
}

func resolveRedisPassword() string {
	if _, password, ok := redisFromURL(os.Getenv("REDIS_URL")); ok && password != "" {
		return password
	}
	if password := os.Getenv("REDISPASSWORD"); password != "" {
		return password
	}
	if password := os.Getenv("REDIS_PASSWORD"); password != "" {
		return password
	}
	return ""
}

func redisFromURL(raw string) (addr, password string, ok bool) {
	if raw == "" {
		return "", "", false
	}
	raw = strings.TrimSpace(raw)
	if !strings.Contains(raw, "://") {
		if _, _, err := net.SplitHostPort(raw); err == nil {
			return raw, "", true
		}
		return net.JoinHostPort(raw, "6379"), "", true
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
