package session

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"

	"gamehub/game-session-service/internal/config"
	"gamehub/game-session-service/internal/wallet"
)

var (
	ErrInvalidStake = errors.New("stake must be greater than zero")
)

type Manager struct {
	db     *mongo.Database
	rdb    *redis.Client
	wallet *wallet.Client
	cfg    *config.Config

	mu          sync.RWMutex
	subscribers map[string]map[chan []byte]struct{}
}

type PlaceBetRequest struct {
	GameType   string                 `json:"gameType"`
	StakeUsd   float64                `json:"stakeUsd"`
	Prediction map[string]interface{} `json:"prediction"`
	TraceID    string                 `json:"traceId,omitempty"`
}

type BetAcknowledgement struct {
	SessionID  string  `json:"sessionId"`
	StakeUsd   float64 `json:"stakeUsd"`
	NewBalance float64 `json:"newBalance"`
	TraceID    string  `json:"traceId"`
}

type SessionOutcome struct {
	SessionID  string  `json:"sessionId"`
	UserID     string  `json:"userId"`
	GameType   string  `json:"gameType"`
	Outcome    string  `json:"outcome"`
	PayoutUsd  float64 `json:"payoutUsd"`
	StakeUsd   float64 `json:"stakeUsd"`
	NewBalance float64 `json:"newBalance"`
	TraceID    string  `json:"traceId"`
	ContractID string  `json:"derivContractId,omitempty"`
}

func NewManager(db *mongo.Database, rdb *redis.Client, walletClient *wallet.Client, cfg *config.Config) *Manager {
	return &Manager{
		db:          db,
		rdb:         rdb,
		wallet:      walletClient,
		cfg:         cfg,
		subscribers: make(map[string]map[chan []byte]struct{}),
	}
}

func (m *Manager) PlaceBet(ctx context.Context, userID string, req PlaceBetRequest) (*BetAcknowledgement, error) {
	if req.StakeUsd <= 0 {
		return nil, ErrInvalidStake
	}
	traceID := req.TraceID
	if traceID == "" {
		traceID = uuid.NewString()
	}
	sessionID := primitive.NewObjectID().Hex()
	if req.GameType == "" {
		req.GameType = "NEON_PERIMETER"
	}

	bal, err := m.wallet.ReserveBet(ctx, wallet.ReserveBetRequest{
		UserID:    userID,
		SessionID: sessionID,
		GameType:  req.GameType,
		AmountUsd: req.StakeUsd,
		TraceID:   traceID,
	})
	if err != nil {
		log.Printf("[trace=%s] reserve bet failed user=%s err=%v", traceID, userID, err)
		return nil, err
	}

	now := time.Now()
	doc := bson.M{
		"sessionId":  sessionID,
		"userId":     userID,
		"gameType":   req.GameType,
		"stakeUsd":   req.StakeUsd,
		"prediction": req.Prediction,
		"traceId":    traceID,
		"status":     "PENDING",
		"createdAt":  now,
		"updatedAt":  now,
	}
	if _, err := m.db.Collection("game_sessions").InsertOne(ctx, doc); err != nil {
		log.Printf("[trace=%s] failed to insert session %s: %v", traceID, sessionID, err)
		return nil, err
	}

	order := map[string]interface{}{
		"sessionId":  sessionID,
		"userId":     userID,
		"gameType":   req.GameType,
		"stakeUsd":   req.StakeUsd,
		"prediction": req.Prediction,
		"traceId":    traceID,
		"createdAt":  now.UnixMilli(),
	}
	payload, _ := json.Marshal(order)
	if err := m.rdb.RPush(ctx, m.cfg.OrderQueue, payload).Err(); err != nil {
		log.Printf("[trace=%s] failed to enqueue session %s: %v", traceID, sessionID, err)
		return nil, err
	}
	m.rdb.Expire(ctx, m.cfg.OrderQueue, 12*time.Hour)

	log.Printf("[trace=%s] queued bet session=%s user=%s game=%s stake=%.2f payload=%s",
		traceID, sessionID, userID, req.GameType, req.StakeUsd, string(payload))
	return &BetAcknowledgement{
		SessionID:  sessionID,
		StakeUsd:   req.StakeUsd,
		NewBalance: bal.AvailableUsd,
		TraceID:    traceID,
	}, nil
}

func (m *Manager) Subscribe(userID string) (chan []byte, func()) {
	ch := make(chan []byte, 8)
	m.mu.Lock()
	defer m.mu.Unlock()
	if _, ok := m.subscribers[userID]; !ok {
		m.subscribers[userID] = make(map[chan []byte]struct{})
	}
	m.subscribers[userID][ch] = struct{}{}

	unsubscribe := func() {
		m.mu.Lock()
		defer m.mu.Unlock()
		if subs, ok := m.subscribers[userID]; ok {
			delete(subs, ch)
			if len(subs) == 0 {
				delete(m.subscribers, userID)
			}
		}
		close(ch)
	}
	return ch, unsubscribe
}

func (m *Manager) broadcast(userID string, payload interface{}) {
	data, err := json.Marshal(payload)
	if err != nil {
		return
	}
	m.mu.RLock()
	defer m.mu.RUnlock()
	for ch := range m.subscribers[userID] {
		select {
		case ch <- data:
		default:
		}
	}
}

func (m *Manager) SubscribeToOutcomes(ctx context.Context) {
	pubsub := m.rdb.PSubscribe(ctx, m.cfg.OutcomePrefix+":*")
	defer pubsub.Close()

	for {
		msg, err := pubsub.ReceiveMessage(ctx)
		if err != nil {
			if ctx.Err() != nil {
				return
			}
			continue
		}
		var outcome SessionOutcome
		if err := json.Unmarshal([]byte(msg.Payload), &outcome); err != nil {
			continue
		}
		log.Printf("[trace=%s] outcome session=%s user=%s game=%s result=%s payout=%.2f", outcome.TraceID, outcome.SessionID, outcome.UserID, outcome.GameType, outcome.Outcome, outcome.PayoutUsd)
		m.persistOutcome(ctx, outcome)
		m.broadcast(outcome.UserID, wsMessage("GAME_RESULT", outcome))
	}
}

func (m *Manager) persistOutcome(ctx context.Context, outcome SessionOutcome) {
	_, _ = m.db.Collection("game_sessions").UpdateOne(
		ctx,
		bson.M{"sessionId": outcome.SessionID},
		bson.M{
			"$set": bson.M{
				"status":          outcome.Outcome,
				"outcome":         outcome.Outcome,
				"payoutUsd":       outcome.PayoutUsd,
				"completedAt":     time.Now(),
				"traceId":         outcome.TraceID,
				"derivContractId": outcome.ContractID,
			},
		},
	)
}

func wsMessage(messageType string, payload interface{}) map[string]interface{} {
	return map[string]interface{}{
		"type":    messageType,
		"payload": payload,
	}
}

func (m *Manager) StartStaleSweeper(ctx context.Context) {
	interval := time.Duration(m.cfg.StaleSweepSec) * time.Second
	if interval <= 0 {
		interval = 30 * time.Second
	}
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			sweepCtx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
			m.refundStaleSessions(sweepCtx)
			cancel()
		}
	}
}

func (m *Manager) refundStaleSessions(ctx context.Context) {
	if m.cfg.StaleRefundSec <= 0 {
		return
	}
	cutoff := time.Now().Add(-time.Duration(m.cfg.StaleRefundSec) * time.Second)
	cursor, err := m.db.Collection("game_sessions").Find(
		ctx,
		bson.M{
			"status":    "PENDING",
			"createdAt": bson.M{"$lt": cutoff},
		},
		options.Find().SetLimit(50),
	)
	if err != nil {
		return
	}
	defer cursor.Close(ctx)

	for cursor.Next(ctx) {
		var doc bson.M
		if err := cursor.Decode(&doc); err != nil {
			continue
		}
		userID, _ := doc["userId"].(string)
		sessionID, _ := doc["sessionId"].(string)
		traceID, _ := doc["traceId"].(string)
		stake, _ := doc["stakeUsd"].(float64)
		gameType, _ := doc["gameType"].(string)
		if userID == "" || sessionID == "" || stake <= 0 {
			continue
		}

		log.Printf("[trace=%s] stale session=%s detected, issuing refund", traceID, sessionID)
		wCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		bal, err := m.wallet.SettleGame(wCtx, wallet.SettleGameRequest{
			UserID:    userID,
			SessionID: sessionID,
			Outcome:   "REFUND",
			StakeUsd:  stake,
			PayoutUsd: stake,
			TraceID:   traceID,
		})
		cancel()
		if err != nil {
			log.Printf("[trace=%s] refund settle failed: %v", traceID, err)
			continue
		}

		outcome := SessionOutcome{
			SessionID:  sessionID,
			UserID:     userID,
			GameType:   gameType,
			Outcome:    "REFUND",
			PayoutUsd:  stake,
			StakeUsd:   stake,
			NewBalance: bal.AvailableUsd,
			TraceID:    traceID,
			ContractID: "REFUND",
		}
		m.persistOutcome(context.Background(), outcome)
		m.broadcast(userID, wsMessage("GAME_RESULT", outcome))
	}
}
