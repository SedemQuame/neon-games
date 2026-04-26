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
	if snapshot, ok := h.mgr.GetUserRoomSnapshot(userID); ok {
		_ = conn.WriteJSON(fiber.Map{
			"type":    "ROOM_STATE",
			"payload": snapshot,
		})
	}

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
		case "CREATE_ROOM":
			var req session.CreateRoomRequest
			if err := json.Unmarshal(data, &req); err != nil {
				conn.WriteJSON(fiber.Map{"type": "ROOM_ERROR", "message": "bad create-room payload"})
				continue
			}
			snapshot, err := h.mgr.CreateRoom(userID, req)
			if err != nil {
				conn.WriteJSON(fiber.Map{"type": "ROOM_ERROR", "message": err.Error()})
				continue
			}
			conn.WriteJSON(fiber.Map{"type": "ROOM_CREATED", "payload": snapshot})
			conn.WriteJSON(fiber.Map{"type": "ROOM_STATE", "payload": snapshot})
		case "LIST_PUBLIC_ROOMS":
			var req session.ListPublicRoomsRequest
			_ = json.Unmarshal(data, &req)
			items := h.mgr.ListPublicRooms(req)
			conn.WriteJSON(fiber.Map{
				"type":    "ROOM_LIST",
				"payload": fiber.Map{"rooms": items},
			})
		case "JOIN_ROOM":
			var req session.JoinRoomRequest
			if err := json.Unmarshal(data, &req); err != nil {
				conn.WriteJSON(fiber.Map{"type": "ROOM_ERROR", "message": "bad join payload"})
				continue
			}
			snapshot, err := h.mgr.JoinRoom(userID, req)
			if err != nil {
				conn.WriteJSON(fiber.Map{"type": "ROOM_ERROR", "message": err.Error()})
				continue
			}
			conn.WriteJSON(fiber.Map{"type": "ROOM_STATE", "payload": snapshot})
		case "LEAVE_ROOM":
			snapshot, err := h.mgr.LeaveRoom(userID)
			if err != nil {
				conn.WriteJSON(fiber.Map{"type": "ROOM_ERROR", "message": err.Error()})
				continue
			}
			if snapshot == nil {
				conn.WriteJSON(fiber.Map{"type": "ROOM_LEFT"})
			} else {
				conn.WriteJSON(fiber.Map{"type": "ROOM_STATE", "payload": snapshot})
			}
		case "SET_ROOM_READY":
			var req session.SetRoomReadyRequest
			if err := json.Unmarshal(data, &req); err != nil {
				conn.WriteJSON(fiber.Map{"type": "ROOM_ERROR", "message": "bad ready payload"})
				continue
			}
			snapshot, err := h.mgr.SetRoomReady(userID, req)
			if err != nil {
				conn.WriteJSON(fiber.Map{"type": "ROOM_ERROR", "message": err.Error()})
				continue
			}
			conn.WriteJSON(fiber.Map{"type": "ROOM_STATE", "payload": snapshot})
		case "START_ROOM_ROUND":
			ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			payload, err := h.mgr.StartRoomRound(ctx, userID)
			cancel()
			if err != nil {
				conn.WriteJSON(fiber.Map{"type": "ROOM_ERROR", "message": err.Error()})
				continue
			}
			conn.WriteJSON(fiber.Map{"type": "ROOM_ROUND_STARTED", "payload": payload})
		case "SUBMIT_ROOM_ACTION":
			var req session.SubmitRoomActionRequest
			if err := json.Unmarshal(data, &req); err != nil {
				conn.WriteJSON(fiber.Map{"type": "ROOM_ERROR", "message": "bad action payload"})
				continue
			}
			ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			payload, err := h.mgr.SubmitRoomAction(ctx, userID, req)
			cancel()
			if err != nil {
				conn.WriteJSON(fiber.Map{"type": "ROOM_ERROR", "message": err.Error()})
				continue
			}
			conn.WriteJSON(fiber.Map{"type": "ROOM_ROUND_STARTED", "payload": payload})
		case "INVITE_TO_ROOM":
			var req session.InviteToRoomRequest
			if err := json.Unmarshal(data, &req); err != nil {
				conn.WriteJSON(fiber.Map{"type": "ROOM_ERROR", "message": "bad invite payload"})
				continue
			}
			if err := h.mgr.InviteToRoom(userID, req); err != nil {
				conn.WriteJSON(fiber.Map{"type": "ROOM_ERROR", "message": err.Error()})
				continue
			}
			conn.WriteJSON(fiber.Map{"type": "ROOM_INVITE_SENT"})
		case "KICK_ROOM_PLAYER":
			var req session.KickRoomPlayerRequest
			if err := json.Unmarshal(data, &req); err != nil {
				conn.WriteJSON(fiber.Map{"type": "ROOM_ERROR", "message": "bad kick payload"})
				continue
			}
			snapshot, err := h.mgr.KickRoomPlayer(userID, req)
			if err != nil {
				conn.WriteJSON(fiber.Map{"type": "ROOM_ERROR", "message": err.Error()})
				continue
			}
			conn.WriteJSON(fiber.Map{"type": "ROOM_PLAYER_KICKED"})
			conn.WriteJSON(fiber.Map{"type": "ROOM_STATE", "payload": snapshot})
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
