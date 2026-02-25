package handler

import (
	"context"
	"encoding/json"
	"strconv"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/websocket/v2"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"

	"gamehub/game-session-service/internal/config"
	"gamehub/game-session-service/internal/session"
)

type Handler struct {
	db  *mongo.Database
	mgr *session.Manager
	cfg *config.Config
}

func New(db *mongo.Database, mgr *session.Manager, cfg *config.Config) *Handler {
	return &Handler{db: db, mgr: mgr, cfg: cfg}
}

func (h *Handler) GetHistory(c *fiber.Ctx) error {
	userID := c.Locals("userId").(string)
	limit := parseInt(c.Query("limit"), 20)
	page := parseInt(c.Query("page"), 1)
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	if page <= 0 {
		page = 1
	}
	skip := int64((page - 1) * limit)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	cursor, err := h.db.Collection("game_sessions").Find(ctx,
		bson.M{"userId": userID},
		options.Find().SetSort(bson.D{{Key: "createdAt", Value: -1}}).
			SetLimit(int64(limit)).
			SetSkip(skip),
	)
	if err != nil {
		return fiberErr(c, err)
	}
	defer cursor.Close(ctx)

	var sessions []bson.M
	if err := cursor.All(ctx, &sessions); err != nil {
		return fiberErr(c, err)
	}
	return c.JSON(fiber.Map{
		"items": sessions,
		"page":  page,
		"limit": limit,
	})
}

func (h *Handler) GetSession(c *fiber.Ctx) error {
	userID := c.Locals("userId").(string)
	sessionID := c.Params("id")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	var doc bson.M
	err := h.db.Collection("game_sessions").FindOne(ctx, bson.M{"sessionId": sessionID, "userId": userID}).Decode(&doc)
	if err == mongo.ErrNoDocuments {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": "session not found"})
	}
	if err != nil {
		return fiberErr(c, err)
	}
	return c.JSON(doc)
}

func (h *Handler) HandleWebSocket(conn *websocket.Conn) {
	userID, _ := conn.Locals("userId").(string)
	if userID == "" {
		conn.WriteJSON(fiber.Map{"type": "ERROR", "message": "unauthorized"})
		conn.Close()
		return
	}

	events, unsubscribe := h.mgr.Subscribe(userID)
	defer unsubscribe()

	conn.WriteJSON(fiber.Map{
		"type":        "CONNECTED",
		"userId":      userID,
		"connectedAt": time.Now().UTC(),
	})

	errCh := make(chan error, 1)
	go func() {
		for msg := range events {
			if err := conn.WriteMessage(websocket.TextMessage, msg); err != nil {
				errCh <- err
				return
			}
		}
	}()

	for {
		select {
		case err := <-errCh:
			if err != nil {
				conn.Close()
				return
			}
		default:
		}

		_, data, err := conn.ReadMessage()
		if err != nil {
			conn.Close()
			return
		}
		var envelope struct {
			Type string `json:"type"`
		}
		if err := json.Unmarshal(data, &envelope); err != nil {
			conn.WriteJSON(fiber.Map{"type": "ERROR", "message": "invalid payload"})
			continue
		}

		switch envelope.Type {
		case "PLACE_BET":
			var req session.PlaceBetRequest
			if err := json.Unmarshal(data, &req); err != nil {
				conn.WriteJSON(fiber.Map{"type": "ERROR", "message": "bad bet payload"})
				continue
			}
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			resp, err := h.mgr.PlaceBet(ctx, userID, req)
			cancel()
			if err != nil {
				conn.WriteJSON(fiber.Map{
					"type":    "BET_REJECTED",
					"reason":  err.Error(),
					"traceId": req.TraceID,
				})
				continue
			}
			conn.WriteJSON(fiber.Map{
				"type":       "BET_ACCEPTED",
				"sessionId":  resp.SessionID,
				"stakeUsd":   resp.StakeUsd,
				"newBalance": resp.NewBalance,
				"traceId":    resp.TraceID,
			})
		case "PING":
			conn.WriteJSON(fiber.Map{"type": "PONG"})
		default:
			conn.WriteJSON(fiber.Map{"type": "ERROR", "message": "unknown message type"})
		}
	}
}

func parseInt(val string, fallback int) int {
	if val == "" {
		return fallback
	}
	n, err := strconv.Atoi(val)
	if err != nil {
		return fallback
	}
	return n
}

func fiberErr(c *fiber.Ctx, err error) error {
	return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
}
