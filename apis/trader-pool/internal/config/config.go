package config

import (
	"log"
	"os"
	"sort"
	"strconv"
	"strings"
)

type Config struct {
	Port             string
	RedisAddr        string
	RedisPassword    string
	WalletServiceURL string
	InternalKey      string
	OrderQueue       string
	OutcomePrefix    string
	MinSettleMs      int
	MaxSettleMs      int
	DerivAppID       string
	DerivWSURL       string
	DerivLanguage    string
	DerivOrigin      string
	DerivSymbol      string
	DerivTokens      []string

	// Bounce system
	// BounceRate is the fraction of bets NOT forwarded to Deriv (0.0–1.0).
	// e.g. 0.2 means 20% of stakes are kept by the house as a forced LOSS.
	BounceRate float64
	// ProfitTargetUsd is the cumulative house profit threshold. Once reached
	// the effective bounce rate halves so bets keep flowing to Deriv.
	// Set to 0 to disable the target (rate stays constant).
	ProfitTargetUsd float64

	// Payout multiplier used in simulation mode (default 1.9 = 90% return on stake).
	PayoutMultiplier float64
	// WinRakeRate is the fraction of NET winnings taken by the house on every WIN.
	// Applied to both real Deriv and simulated outcomes.
	// e.g. 0.05 = keep 5% of profit, user gets 95%.
	WinRakeRate float64
}

func Load() *Config {
	return &Config{
		Port:             getEnv("PORT", "8005"),
		RedisAddr:        getEnv("REDIS_ADDR", "localhost:6379"),
		RedisPassword:    getEnv("REDIS_PASSWORD", ""),
		WalletServiceURL: getEnv("WALLET_SERVICE_URL", "http://wallet-service:8004"),
		InternalKey:      getEnv("INTERNAL_SERVICE_KEY", "dev-internal-key"),
		OrderQueue:       getEnv("TRADE_ORDER_QUEUE", "trade:orders"),
		OutcomePrefix:    getEnv("GAME_OUTCOME_PREFIX", "game:outcome"),
		MinSettleMs:      getEnvInt("MIN_SETTLE_MS", 1500),
		MaxSettleMs:      getEnvInt("MAX_SETTLE_MS", 4500),
		DerivAppID:       getEnv("DERIV_APP_ID", ""),
		DerivWSURL:       getEnv("DERIV_WS_URL", "wss://ws.binaryws.com/websockets/v3"),
		DerivLanguage:    getEnv("DERIV_LANGUAGE", "en"),
		DerivOrigin:      getEnv("DERIV_ORIGIN", "https://gamehub.local"),
		DerivSymbol:      getEnv("DERIV_SYMBOL", "R_50"),
		DerivTokens:      loadDerivTokens(),
		BounceRate:       getEnvFloat("BOUNCE_RATE", 0.0),
		ProfitTargetUsd:  getEnvFloat("PROFIT_TARGET_USD", 0.0),
		PayoutMultiplier: getEnvFloat("PAYOUT_MULTIPLIER", 1.9),
		WinRakeRate:      getEnvFloat("WIN_RAKE_RATE", 0.0),
	}
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func getEnvInt(key string, fallback int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return fallback
}

func getEnvFloat(key string, fallback float64) float64 {
	if v := os.Getenv(key); v != "" {
		if f, err := strconv.ParseFloat(v, 64); err == nil {
			return f
		}
	}
	return fallback
}

func mustGetEnv(key string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	log.Fatalf("required env %s missing", key)
	return ""
}

func loadDerivTokens() []string {
	var pairs []struct {
		index int
		value string
	}
	for _, env := range os.Environ() {
		parts := strings.SplitN(env, "=", 2)
		if len(parts) != 2 {
			continue
		}
		key := parts[0]
		val := parts[1]
		if !strings.HasPrefix(key, "DERIV_ACCOUNT_") || !strings.HasSuffix(key, "_TOKEN") {
			continue
		}
		idxPart := strings.TrimPrefix(key, "DERIV_ACCOUNT_")
		idxPart = strings.TrimSuffix(idxPart, "_TOKEN")
		if idx, err := strconv.Atoi(idxPart); err == nil && val != "" {
			pairs = append(pairs, struct {
				index int
				value string
			}{index: idx, value: val})
		}
	}
	sort.Slice(pairs, func(i, j int) bool {
		return pairs[i].index < pairs[j].index
	})
	tokens := make([]string, 0, len(pairs))
	for _, pair := range pairs {
		tokens = append(tokens, pair.value)
	}
	return tokens
}
