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

	"gamehub/trader-pool/internal/config"
	"gamehub/trader-pool/internal/pool"
	"gamehub/trader-pool/internal/wallet"
)

func main() {
	cfg := config.Load()

	// --- Redis (account registry + session locks) ---
	rdb := redis.NewClient(&redis.Options{
		Addr:     cfg.RedisAddr,
		Password: cfg.RedisPassword,
	})
	if _, err := rdb.Ping(context.Background()).Result(); err != nil {
		log.Fatalf("Redis ping failed: %v", err)
	}

	walletClient := wallet.New(cfg.WalletServiceURL, cfg.InternalKey)
	mgr := pool.NewManager(rdb, walletClient, cfg)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go mgr.Start(ctx)

	// --- Fiber App (admin/health only — not in public gateway) ---
	app := fiber.New(fiber.Config{
		AppName:      "GameHub Trader Pool",
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
	})
	app.Use(logger.New())
	app.Use(recover.New())

	app.Get("/health", func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{"status": "ok", "service": "trader-pool"})
	})

	// --- Graceful Shutdown ---
	go func() {
		log.Printf("Trader pool on :%s", cfg.Port)
		if err := app.Listen(":" + cfg.Port); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server error: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGTERM, syscall.SIGINT)
	<-quit
	log.Println("Shutting down trader-pool")
	cancel()

	app.Shutdown()
}
