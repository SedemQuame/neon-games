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
	"github.com/redis/go-redis/v9"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"

	"gamehub/wallet-service/internal/auth"
	"gamehub/wallet-service/internal/config"
	"gamehub/wallet-service/internal/handler"
	"gamehub/wallet-service/internal/ledger"
	"gamehub/wallet-service/internal/middleware"
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

	// Critical indexes
	db.Collection("ledger_entries").Indexes().CreateMany(context.Background(), []mongo.IndexModel{
		{Keys: bson.D{{Key: "userId", Value: 1}, {Key: "createdAt", Value: -1}}},
		{Keys: bson.D{{Key: "reference", Value: 1}}, Options: options.Index().SetUnique(true).SetSparse(true)},
	})
	db.Collection("crypto_wallets").Indexes().CreateMany(context.Background(), []mongo.IndexModel{
		{Keys: bson.D{{Key: "address", Value: 1}}, Options: options.Index().SetUnique(true)},
		{Keys: bson.D{{Key: "userId", Value: 1}, {Key: "coin", Value: 1}}},
	})
	db.Collection("wallet_balances").Indexes().CreateOne(context.Background(), mongo.IndexModel{
		Keys:    bson.D{{Key: "userId", Value: 1}},
		Options: options.Index().SetUnique(true),
	})
	db.Collection("withdrawals").Indexes().CreateMany(context.Background(), []mongo.IndexModel{
		{Keys: bson.D{{Key: "userId", Value: 1}, {Key: "createdAt", Value: -1}}},
		{Keys: bson.D{{Key: "status", Value: 1}}},
	})
	db.Collection("bet_reservations").Indexes().CreateOne(context.Background(), mongo.IndexModel{
		Keys: bson.D{{Key: "userId", Value: 1}},
	})

	// --- Redis (balance cache + leaderboard ZSETs) ---
	rdb := redis.NewClient(&redis.Options{
		Addr:     cfg.RedisAddr,
		Password: cfg.RedisPassword,
	})

	// --- Ledger Service (pure business logic, no Kafka) ---
	svc := ledger.NewService(db, rdb)

	// --- Fiber App ---
	app := fiber.New(fiber.Config{
		AppName:      "Glory Grid Wallet Service",
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
	})
	app.Use(logger.New())
	app.Use(recover.New())

	h := handler.New(rdb, svc, cfg)

	app.Get("/health", func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{"status": "ok", "service": "wallet-service"})
	})

	// ==========================================================================
	// PUBLIC ROUTES — require user JWT
	// ==========================================================================
	v1 := app.Group("/api/v1/wallet", middleware.RequireAuth(tokenValidator))
	v1.Get("/balance", h.GetBalance)
	v1.Get("/ledger", h.GetLedger) // Paginated transaction history
	v1.Get("/withdrawals", h.GetWithdrawals)

	// Leaderboard lives here (uses Redis ZSETs populated by game outcomes)
	app.Get("/api/v1/leaderboard/global", middleware.RequireAuth(tokenValidator), h.GlobalLeaderboard)
	app.Get("/api/v1/leaderboard/friends", middleware.RequireAuth(tokenValidator), h.FriendsLeaderboard)

	// ==========================================================================
	// INTERNAL ROUTES — called by payment-gateway and game-session-service
	// These are protected by an internal service key, NOT a user JWT
	// ==========================================================================
	internal := app.Group("/internal", middleware.RequireInternalKey(cfg))

	// Called by payment-gateway when deposit confirmed
	internal.Post("/ledger/credit", h.InternalCreditDeposit)

	// Called by payment-gateway: locks funds before initiating Flutterwave withdrawal
	internal.Post("/ledger/reserve-withdrawal", h.InternalReserveWithdrawal)

	// Called by payment-gateway: finalises or refunds a withdrawal reservation
	internal.Post("/ledger/release-withdrawal", h.InternalReleaseWithdrawal)

	// Called by game-session-service: locks stake amount before placing Deriv contract
	internal.Post("/ledger/reserve-bet", h.InternalReserveBet)

	// Called by trader-pool after Deriv settles a contract
	internal.Post("/ledger/settle-game", h.InternalSettleGame)

	// --- Graceful Shutdown ---
	go func() {
		log.Printf("Wallet service on :%s", cfg.Port)
		if err := app.Listen(":" + cfg.Port); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Wallet server error: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGTERM, syscall.SIGINT)
	<-quit
	log.Println("Shutting down wallet-service...")
	_ = app.Shutdown()
}
