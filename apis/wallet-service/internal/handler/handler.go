package handler

import (
	"context"
	"errors"
	"log"
	"strconv"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/redis/go-redis/v9"

	"gamehub/wallet-service/internal/config"
	"gamehub/wallet-service/internal/ledger"
)

type Handler struct {
	svc *ledger.Service
	rdb *redis.Client
	cfg *config.Config
}

func New(rdb *redis.Client, svc *ledger.Service, cfg *config.Config) *Handler {
	return &Handler{
		svc: svc,
		rdb: rdb,
		cfg: cfg,
	}
}

func (h *Handler) GetBalance(c *fiber.Ctx) error {
	userID := c.Locals("userId").(string)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	bal, err := h.svc.GetBalance(ctx, userID)
	if err != nil {
		return fiberErr(c, err)
	}
	log.Printf("[wallet] balance request user=%s available=%.2f reserved=%.2f", userID, bal.AvailableUsd, bal.ReservedUsd)
	return c.JSON(fiber.Map{
		"userId":       bal.UserID,
		"availableUsd": bal.AvailableUsd,
		"reservedUsd":  bal.ReservedUsd,
		"updatedAt":    bal.LastUpdatedAt,
	})
}

func (h *Handler) GetLedger(c *fiber.Ctx) error {
	userID := c.Locals("userId").(string)
	limit := parseInt(c.Query("limit"), 25)
	page := parseInt(c.Query("page"), 1)
	if limit <= 0 || limit > 100 {
		limit = 25
	}
	if page <= 0 {
		page = 1
	}
	offset := int64((page - 1) * limit)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	entries, err := h.svc.ListLedger(ctx, userID, int64(limit), offset)
	if err != nil {
		return fiberErr(c, err)
	}
	return c.JSON(fiber.Map{
		"entries": entries,
		"page":    page,
		"limit":   limit,
	})
}

func (h *Handler) GetWithdrawals(c *fiber.Ctx) error {
	userID := c.Locals("userId").(string)
	limit := parseInt(c.Query("limit"), 20)
	if limit <= 0 || limit > 50 {
		limit = 20
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	records, err := h.svc.ListWithdrawals(ctx, userID, int64(limit))
	if err != nil {
		return fiberErr(c, err)
	}
	return c.JSON(fiber.Map{"items": records})
}

func (h *Handler) GlobalLeaderboard(c *fiber.Ctx) error {
	if h.rdb == nil {
		return c.JSON(fiber.Map{"entries": []interface{}{}})
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	zs, err := h.rdb.ZRevRangeWithScores(ctx, "leaderboard:global", 0, 99).Result()
	if err != nil && err != redis.Nil {
		return fiberErr(c, err)
	}
	entries := make([]fiber.Map, 0, len(zs))
	for idx, z := range zs {
		userID, _ := z.Member.(string)
		entries = append(entries, fiber.Map{
			"rank":   idx + 1,
			"userId": userID,
			"score":  z.Score,
		})
	}
	return c.JSON(fiber.Map{"entries": entries})
}

func (h *Handler) FriendsLeaderboard(c *fiber.Ctx) error {
	if h.rdb == nil {
		return c.JSON(fiber.Map{"entries": []interface{}{}})
	}
	friendQuery := c.Query("ids")
	if friendQuery == "" {
		return c.JSON(fiber.Map{"entries": []interface{}{}})
	}
	ids := strings.Split(friendQuery, ",")
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	res := make([]fiber.Map, 0, len(ids))
	for _, id := range ids {
		id = strings.TrimSpace(id)
		if id == "" {
			continue
		}
		score, err := h.rdb.ZScore(ctx, "leaderboard:global", id).Result()
		if err == redis.Nil {
			continue
		}
		if err != nil {
			return fiberErr(c, err)
		}
		res = append(res, fiber.Map{"userId": id, "score": score})
	}
	return c.JSON(fiber.Map{"entries": res})
}

func (h *Handler) InternalCreditDeposit(c *fiber.Ctx) error {
	var body struct {
		UserID    string  `json:"userId"`
		AmountUsd float64 `json:"amountUsd"`
		Reference string  `json:"reference"`
		Source    string  `json:"source"`
	}
	if err := c.BodyParser(&body); err != nil || body.UserID == "" || body.AmountUsd <= 0 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "invalid payload"})
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	bal, err := h.svc.CreditDeposit(ctx, ledger.CreditRequest{
		UserID:    body.UserID,
		AmountUsd: body.AmountUsd,
		Reference: body.Reference,
		Source:    body.Source,
	})
	if err != nil {
		return fiberErr(c, err)
	}
	return c.JSON(balanceResponse(bal))
}

func (h *Handler) InternalReserveWithdrawal(c *fiber.Ctx) error {
	var body struct {
		UserID       string  `json:"userId"`
		WithdrawalID string  `json:"withdrawalId"`
		AmountUsd    float64 `json:"amountUsd"`
		AmountGhs    float64 `json:"amountGhs"`
	}
	if err := c.BodyParser(&body); err != nil || body.UserID == "" || body.WithdrawalID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "invalid payload"})
	}
	amount := body.AmountUsd
	if amount == 0 {
		amount = body.AmountGhs
	}
	if amount <= 0 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "amount must be positive"})
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	bal, err := h.svc.ReserveWithdrawal(ctx, ledger.WithdrawalReserveRequest{
		UserID:       body.UserID,
		WithdrawalID: body.WithdrawalID,
		AmountUsd:    amount,
	})
	if err != nil {
		if errors.Is(err, ledger.ErrInsufficientFunds) {
			return c.Status(fiber.StatusUnprocessableEntity).JSON(fiber.Map{"error": err.Error()})
		}
		return fiberErr(c, err)
	}
	return c.JSON(balanceResponse(bal))
}

func (h *Handler) InternalReleaseWithdrawal(c *fiber.Ctx) error {
	var body struct {
		UserID       string `json:"userId"`
		WithdrawalID string `json:"withdrawalId"`
		Success      bool   `json:"success"`
	}
	if err := c.BodyParser(&body); err != nil || body.UserID == "" || body.WithdrawalID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "invalid payload"})
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	bal, err := h.svc.ReleaseWithdrawal(ctx, ledger.WithdrawalReleaseRequest{
		UserID:       body.UserID,
		WithdrawalID: body.WithdrawalID,
		Success:      body.Success,
	})
	if err != nil {
		if errors.Is(err, ledger.ErrReservationNotFound) {
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": err.Error()})
		}
		return fiberErr(c, err)
	}
	return c.JSON(balanceResponse(bal))
}

func (h *Handler) InternalReserveBet(c *fiber.Ctx) error {
	var body struct {
		UserID    string  `json:"userId"`
		SessionID string  `json:"sessionId"`
		AmountUsd float64 `json:"amountUsd"`
		TraceID   string  `json:"traceId"`
	}
	if err := c.BodyParser(&body); err != nil || body.UserID == "" || body.SessionID == "" || body.AmountUsd <= 0 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "invalid payload"})
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	log.Printf("[trace=%s] reserve-bet user=%s session=%s amount=%.2f", body.TraceID, body.UserID, body.SessionID, body.AmountUsd)
	bal, err := h.svc.ReserveBet(ctx, ledger.BetReserveRequest{
		UserID:    body.UserID,
		SessionID: body.SessionID,
		AmountUsd: body.AmountUsd,
		TraceID:   body.TraceID,
	})
	if err != nil {
		if errors.Is(err, ledger.ErrInsufficientFunds) {
			return c.Status(fiber.StatusUnprocessableEntity).JSON(fiber.Map{"error": err.Error()})
		}
		return fiberErr(c, err)
	}
	return c.JSON(balanceResponse(bal))
}

func (h *Handler) InternalSettleGame(c *fiber.Ctx) error {
	var body struct {
		UserID    string  `json:"userId"`
		SessionID string  `json:"sessionId"`
		Outcome   string  `json:"outcome"`
		StakeUsd  float64 `json:"stakeUsd"`
		PayoutUsd float64 `json:"payoutUsd"`
		TraceID   string  `json:"traceId"`
	}
	if err := c.BodyParser(&body); err != nil || body.UserID == "" || body.SessionID == "" || body.Outcome == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "invalid payload"})
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	log.Printf("[trace=%s] settle-game user=%s session=%s outcome=%s stake=%.2f payout=%.2f", body.TraceID, body.UserID, body.SessionID, body.Outcome, body.StakeUsd, body.PayoutUsd)
	bal, err := h.svc.SettleGame(ctx, ledger.GameSettlementRequest{
		UserID:    body.UserID,
		SessionID: body.SessionID,
		Outcome:   strings.ToUpper(body.Outcome),
		StakeUsd:  body.StakeUsd,
		PayoutUsd: body.PayoutUsd,
		TraceID:   body.TraceID,
	})
	if err != nil {
		if errors.Is(err, ledger.ErrReservationNotFound) {
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": err.Error()})
		}
		return fiberErr(c, err)
	}
	return c.JSON(balanceResponse(bal))
}

func balanceResponse(b *ledger.Balance) fiber.Map {
	return fiber.Map{
		"userId":       b.UserID,
		"availableUsd": b.AvailableUsd,
		"reservedUsd":  b.ReservedUsd,
		"updatedAt":    b.LastUpdatedAt,
	}
}

func parseInt(val string, fallback int) int {
	if val == "" {
		return fallback
	}
	if n, err := strconv.Atoi(val); err == nil {
		return n
	}
	return fallback
}

func fiberErr(c *fiber.Ctx, err error) error {
	return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
}
