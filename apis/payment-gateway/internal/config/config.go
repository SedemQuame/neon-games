package config

import (
	"log"
	"net"
	"net/url"
	"os"
	"strconv"
	"strings"
)

type Config struct {
	Port          string
	MongoURI      string
	RedisAddr     string
	RedisPassword string

	MoMoAllowedChannels []string
	MoMoDefaultCurrency string

	FlutterwaveMode             string
	FlutterwaveSecretKey        string
	FlutterwavePublicKey        string
	FlutterwaveEncryptionKey    string
	FlutterwaveBaseURL          string
	FlutterwaveTransferBaseURL  string
	FlutterwaveWebhookSecret    string
	FlutterwaveChargeCallback   string
	FlutterwaveTransferCallback string

	TatumAPIKey           string
	TatumWebhookSecret    string
	TatumBaseURL          string
	TatumBTCXpub          string
	TatumETHXpub          string
	TatumTRONXpub         string
	TatumTestnet          bool
	CryptoWatcherInterval int
	CryptoWebhookURL      string

	WalletServiceURL   string
	InternalServiceKey string

	JWTPublicKeyPath string
	JWTIssuer        string
	AppEnv           string

	// Deposit fee: fraction of each deposit kept by the house before crediting.
	// e.g. 0.05 = 5% fee. Applies to both crypto and MoMo deposits.
	// Set to 0.0 to disable.
	DepositFeeRate float64

	// Withdrawal fee: fraction of each withdrawal kept by the house.
	// e.g. 0.05 = 5% fee. Applies to MoMo withdrawals.
	// Set to 0.0 to disable.
	WithdrawalFeeRate float64
}

func Load() *Config {
	appEnv := getEnv("APP_ENV", "development")
	mode := strings.ToLower(getEnv("FLUTTERWAVE_MODE", ""))
	if mode == "" {
		if strings.EqualFold(appEnv, "production") {
			mode = "live"
		} else {
			mode = "test"
		}
	}

	flutterwaveSecret := selectFlutterwaveValue(
		getEnv("FLUTTERWAVE_SECRET_KEY", ""),
		mode,
		getEnv("FLUTTERWAVE_TEST_SECRET_KEY", ""),
		getEnv("FLUTTERWAVE_LIVE_SECRET_KEY", ""),
	)
	flutterwavePublic := selectFlutterwaveValue(
		getEnv("FLUTTERWAVE_PUBLIC_KEY", ""),
		mode,
		getEnv("FLUTTERWAVE_TEST_PUBLIC_KEY", ""),
		getEnv("FLUTTERWAVE_LIVE_PUBLIC_KEY", ""),
	)
	flutterwaveEncryption := selectFlutterwaveValue(
		getEnv("FLUTTERWAVE_ENCRYPTION_KEY", ""),
		mode,
		getEnv("FLUTTERWAVE_TEST_ENCRYPTION_KEY", ""),
		getEnv("FLUTTERWAVE_LIVE_ENCRYPTION_KEY", ""),
	)

	allowedChannels := splitAndTrim(getEnv("MOMO_ALLOWED_CHANNELS", ""))
	if len(allowedChannels) == 0 {
		allowedChannels = splitAndTrim(getEnv("PAYSTACK_ALLOWED_CHANNELS", "mtn-gh,vodafone-gh,airteltigo-gh"))
	}
	defaultCurrency := getEnv("MOMO_DEFAULT_CURRENCY", "")
	if defaultCurrency == "" {
		defaultCurrency = getEnv("PAYSTACK_DEFAULT_CURRENCY", "GHS")
	}

	baseURL := getEnv("FLUTTERWAVE_BASE_URL", "https://api.flutterwave.com")
	transferBaseURL := getEnv("FLUTTERWAVE_TRANSFERS_BASE_URL", baseURL)

	return &Config{
		Port:                        getEnv("PORT", "8003"),
		MongoURI:                    mustGetEnv("MONGO_URI"),
		RedisAddr:                   resolveRedisAddr(),
		RedisPassword:               resolveRedisPassword(),
		MoMoAllowedChannels:         allowedChannels,
		MoMoDefaultCurrency:         defaultCurrency,
		FlutterwaveMode:             mode,
		FlutterwaveSecretKey:        flutterwaveSecret,
		FlutterwavePublicKey:        flutterwavePublic,
		FlutterwaveEncryptionKey:    flutterwaveEncryption,
		FlutterwaveBaseURL:          baseURL,
		FlutterwaveTransferBaseURL:  transferBaseURL,
		FlutterwaveWebhookSecret:    getEnv("FLUTTERWAVE_WEBHOOK_SECRET", ""),
		FlutterwaveChargeCallback:   getEnv("FLUTTERWAVE_MOMO_CALLBACK_URL", "https://api.gamehub.io/webhooks/payment/flutterwave/charge"),
		FlutterwaveTransferCallback: getEnv("FLUTTERWAVE_TRANSFER_CALLBACK_URL", "https://api.gamehub.io/webhooks/payment/flutterwave/transfer"),
		TatumAPIKey:                 getEnv("TATUM_API_KEY", ""),
		TatumWebhookSecret:          getEnv("TATUM_WEBHOOK_SECRET", ""),
		TatumBaseURL:                getEnv("TATUM_BASE_URL", "https://api.tatum.io"),
		TatumBTCXpub:                getEnv("TATUM_BTC_XPUB", ""),
		TatumETHXpub:                getEnv("TATUM_ETH_XPUB", ""),
		TatumTRONXpub:               getEnv("TATUM_TRON_XPUB", ""),
		TatumTestnet:                strings.EqualFold(getEnv("TATUM_TESTNET", "false"), "true"),
		CryptoWatcherInterval:       getIntEnv("CRYPTO_WATCHER_INTERVAL_SECONDS", 60),
		CryptoWebhookURL:            getEnv("CRYPTO_WEBHOOK_URL", "https://api.gamehub.io/webhooks/payment/crypto"),
		WalletServiceURL:            getEnv("WALLET_SERVICE_URL", "http://127.0.0.1:8004"),
		InternalServiceKey:          getEnv("INTERNAL_SERVICE_KEY", "dev-internal-key"),
		JWTPublicKeyPath:            getEnv("JWT_PUBLIC_KEY_PATH", ""),
		JWTIssuer:                   getEnv("JWT_ISSUER", "gamehub-auth"),
		AppEnv:                      appEnv,
		DepositFeeRate:              getFloatEnv("DEPOSIT_FEE_RATE", 0.0),
		WithdrawalFeeRate:           getFloatEnv("WITHDRAWAL_FEE_RATE", 0.0),
	}
}

func selectFlutterwaveValue(override, mode, testVal, liveVal string) string {
	if override != "" {
		return override
	}
	if mode == "live" {
		return liveVal
	}
	return testVal
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

func getIntEnv(key string, fallback int) int {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return fallback
	}
	return n
}

func getFloatEnv(key string, fallback float64) float64 {
	if v := os.Getenv(key); v != "" {
		if f, err := strconv.ParseFloat(v, 64); err == nil {
			return f
		}
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
