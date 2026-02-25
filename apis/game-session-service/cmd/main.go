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

	"gamehub/game-session-service/internal/auth"
	"gamehub/game-session-service/internal/config"
	"gamehub/game-session-service/internal/handler"
	"gamehub/game-session-service/internal/middleware"
	"gamehub/game-session-service/internal/session"
	"gamehub/game-session-service/internal/wallet"
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

	db.Collection("game_sessions").Indexes().CreateMany(context.Background(), []mongo.IndexModel{
		{Keys: bson.D{{Key: "userId", Value: 1}, {Key: "startedAt", Value: -1}}},
		{Keys: bson.D{{Key: "outcome", Value: 1}}},
	})

	// --- Redis (session locks + PubSub for Deriv outcome delivery) ---
	rdb := redis.NewClient(&redis.Options{
		Addr:     cfg.RedisAddr,
		Password: cfg.RedisPassword,
	})

	// --- Wallet client (direct HTTP for balance reservation) ---
	walletClient := wallet.NewHTTPClient(cfg.WalletServiceURL, cfg.InternalKey)

	// --- Session Manager ---
	// Manages bet lifecycle: validate → reserve balance → call trader-pool → await result
	// Results arrive via Redis PubSub published by trader-pool
	mgr := session.NewManager(db, rdb, walletClient, cfg)

	// Subscribe to game outcome channel from trader-pool
	// trader-pool publishes: PUBLISH game:outcome:{sessionId} {outcome:"WIN",payoutUsd:95}
	go mgr.SubscribeToOutcomes(context.Background())
	go mgr.StartStaleSweeper(context.Background())

	// --- Fiber App ---
	app := fiber.New(fiber.Config{
		AppName:      "Glory Grid Game Session Service",
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
	})
	app.Use(logger.New())
	app.Use(recover.New())

	h := handler.New(db, mgr, cfg)

	app.Get("/health", func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{"status": "ok", "service": "game-session-service"})
	})

	// REST
	v1 := app.Group("/api/v1/games", middleware.RequireAuth(tokenValidator))
	v1.Get("/history", h.GetHistory)
	v1.Get("/session/:id", h.GetSession)

	// WebSocket — full game session lifecycle
	app.Use("/ws", middleware.UpgradeWS(tokenValidator))
	app.Get("/ws", websocket.New(h.HandleWebSocket))

	// --- Graceful Shutdown ---
	go func() {
		log.Printf("Game session service on :%s", cfg.Port)
		if err := app.Listen(":" + cfg.Port); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server error: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGTERM, syscall.SIGINT)
	<-quit
	log.Println("Shutting down game-session-service...")
	_ = app.Shutdown()
}
