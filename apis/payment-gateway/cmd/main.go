package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/logger"
	"github.com/gofiber/fiber/v2/middleware/recover"
	"github.com/gofiber/websocket/v2"
	"github.com/redis/go-redis/v9"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"

	"gamehub/payment-gateway/internal/auth"
	"gamehub/payment-gateway/internal/config"
	"gamehub/payment-gateway/internal/handler"
	"gamehub/payment-gateway/internal/middleware"
	"gamehub/payment-gateway/internal/paystack"
	"gamehub/payment-gateway/internal/tatum"
	"gamehub/payment-gateway/internal/wallet"
)

func main() {
	cfg := config.Load()

	tokenValidator, err := auth.NewValidator(cfg.JWTPublicKeyPath, cfg.JWTIssuer)
	if err != nil {
		log.Fatalf("JWT validator init failed: %v", err)
	}

	// --- MongoDB ---
	mongoClient, err := mongo.Connect(context.Background(), options.Client().ApplyURI(cfg.MongoURI))
	if err != nil {
		log.Fatalf("MongoDB connect error: %v", err)
	}
	defer mongoClient.Disconnect(context.Background())
	db := mongoClient.Database("gamehub")

	// Idempotency indexes — prevents double-processing of any payment event
	db.Collection("payment_events").Indexes().CreateMany(context.Background(), []mongo.IndexModel{
		// reference = Paystack clientReference or txHash — must be globally unique
		{Keys: bson.D{{Key: "reference", Value: 1}}, Options: options.Index().SetUnique(true)},
		{Keys: bson.D{{Key: "userId", Value: 1}, {Key: "status", Value: 1}, {Key: "createdAt", Value: -1}}},
	})
	db.Collection("withdrawals").Indexes().CreateMany(context.Background(), []mongo.IndexModel{
		{Keys: bson.D{{Key: "userId", Value: 1}, {Key: "status", Value: 1}}},
		{Keys: bson.D{{Key: "hubtelRef", Value: 1}}, Options: options.Index().SetSparse(true)},
	})

	// Crypto deposit tracking indexes
	db.Collection("crypto_deposits").Indexes().CreateMany(context.Background(), []mongo.IndexModel{
		{Keys: bson.D{{Key: "userId", Value: 1}, {Key: "createdAt", Value: -1}}},
		{Keys: bson.D{{Key: "status", Value: 1}}},
	})
	db.Collection("crypto_wallets").Indexes().CreateMany(context.Background(), []mongo.IndexModel{
		{Keys: bson.D{{Key: "address", Value: 1}}, Options: options.Index().SetUnique(true)},
		{Keys: bson.D{{Key: "userId", Value: 1}, {Key: "coin", Value: 1}}, Options: options.Index().SetSparse(true)},
	})

	// --- Redis (idempotency fast-path + webhook dedup) ---
	rdb := redis.NewClient(&redis.Options{
		Addr:     cfg.RedisAddr,
		Password: cfg.RedisPassword,
	})

	// --- External Clients ---
	// Paystack: Mobile Money deposits + withdrawals
	paystackClient := paystack.NewClient(cfg.PaystackSecretKey, cfg.PaystackBaseURL, cfg.PaystackSubaccount)

	// Tatum: Blockchain monitoring for crypto deposits
	tatumClient := tatum.NewClient(cfg.TatumAPIKey)

	// Wallet service client: called directly over HTTP after payment confirms
	walletClient := wallet.NewHTTPClient(cfg.WalletServiceURL, cfg.InternalServiceKey)

	// --- Handler ---
	h := handler.New(db, rdb, paystackClient, tatumClient, walletClient, cfg)

	// --- Background: Poll Paystack for pending payment statuses ---
	// Webhooks can occasionally be delayed — this ensures we don't miss confirmations
	go h.RunPaystackStatusPoller(context.Background())

	// --- Fiber App ---
	app := fiber.New(fiber.Config{
		AppName:      "Glory Grid Payment Gateway",
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 30 * time.Second,
	})
	app.Use(logger.New())
	app.Use(recover.New())

	app.Get("/health", func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{"status": "ok", "service": "payment-gateway"})
	})

	// ==========================================================================
	// PUBLIC ROUTES (require user JWT)
	// ==========================================================================
	v1 := app.Group("/api/v1/payments", middleware.RequireAuth(tokenValidator))

	// --- Mobile Money (Paystack) ---
	// Initiate a deposit: triggers Paystack charge → MoMo prompt on phone
	v1.Post("/momo/deposit", h.InitiateMoMoDeposit)
	// Check status of a specific payment by client reference
	v1.Get("/momo/status/:reference", h.GetMoMoStatus)
	// Initiate a withdrawal to mobile money
	v1.Post("/momo/withdraw", h.InitiateMoMoWithdrawal)

	// --- Crypto ---
	// Generate a deposit address for a given coin (BTC, ETH, USDT)
	v1.Post("/crypto/address", h.GenerateCryptoAddress)
	// Check status of a crypto deposit by tx hash
	v1.Get("/crypto/status/:txHash", h.GetCryptoDepositStatus)

	// --- General History ---
	v1.Get("/history", h.GetPaymentHistory)
	v1.Get("/withdrawals", h.GetWithdrawals)

	// ==========================================================================
	// WEBHOOK ROUTES (provider → our server; no user JWT, HMAC-verified)
	// IP-whitelist enforced by NGINX upstream — these are NOT in the public gateway
	// ==========================================================================
	webhooks := app.Group("/webhooks/payment")

	// Paystack fires this when user completes MoMo payment
	webhooks.Post("/paystack",
		middleware.VerifyPaystackHMAC(cfg),
		h.PaystackDepositCallback,
	)

	// Paystack fires this when a transfer (withdrawal) is processed
	webhooks.Post("/paystack/withdrawal",
		middleware.VerifyPaystackHMAC(cfg),
		h.PaystackWithdrawalCallback,
	)

	// Tatum fires this when a crypto tx reaches required confirmations
	webhooks.Post("/crypto",
		middleware.VerifyTatumHMAC(cfg),
		h.CryptoDepositCallback,
	)

	// ==========================================================================
	// INTERNAL ROUTES (called by other services inside the Docker network)
	// ==========================================================================
	internal := app.Group("/internal", middleware.RequireInternalKey(cfg))

	// Wallet service calls this after a game win to check pending withdrawals
	internal.Get("/withdrawals/pending/:userId", h.GetPendingWithdrawals)

	// ==========================================================================
	// WEBSOCKET — real-time payment status updates to connected Flutter clients
	// ==========================================================================
	app.Use("/ws/payments", middleware.UpgradeWS(tokenValidator))
	app.Get("/ws/payments", websocket.New(h.PaymentStatusWebSocket))
	// Client subscribes to their userId channel; receives push when payment settles

	// --- Graceful Shutdown ---
	go func() {
		log.Printf("Payment gateway running on :%s", cfg.Port)
		if err := app.Listen(":" + cfg.Port); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server error: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGTERM, syscall.SIGINT)
	<-quit
	log.Println("Shutting down payment-gateway...")
	_ = app.Shutdown()
}
