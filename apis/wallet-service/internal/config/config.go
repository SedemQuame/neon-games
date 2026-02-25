package config

import (
	"log"
	"os"
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
		RedisAddr:          getEnv("REDIS_ADDR", "localhost:6379"),
		RedisPassword:      getEnv("REDIS_PASSWORD", ""),
		InternalServiceKey: getEnv("INTERNAL_SERVICE_KEY", "dev-internal-key"),
		AllowedOrigins:     getEnv("CORS_ALLOWED_ORIGINS", "*"),
		AppEnv:             getEnv("APP_ENV", "development"),
		JWTPublicKeyPath:   getEnv("JWT_PUBLIC_KEY_PATH", "/run/secrets/jwt_public.pem"),
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
