package handler

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"math"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/websocket/v2"
	"github.com/redis/go-redis/v9"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"

	"gamehub/payment-gateway/internal/config"
	"gamehub/payment-gateway/internal/paystack"
	"gamehub/payment-gateway/internal/tatum"
	"gamehub/payment-gateway/internal/wallet"
)

type Handler struct {
	db             *mongo.Database
	rdb            *redis.Client
	paystackClient *paystack.Client
	tatumClient    *tatum.Client
	walletClient   *wallet.HTTPClient
	cfg            *config.Config
}

func New(db *mongo.Database, rdb *redis.Client, pc *paystack.Client, tc *tatum.Client, wc *wallet.HTTPClient, cfg *config.Config) *Handler {
	return &Handler{db: db, rdb: rdb, paystackClient: pc, tatumClient: tc, walletClient: wc, cfg: cfg}
}

var confirmationThreshold = map[string]int{
	"BTC":  3,
	"ETH":  12,
	"USDT": 1,
}

var defaultNetworks = map[string]string{
	"BTC":  "BTC",
	"ETH":  "ERC20",
	"USDT": "TRC20",
}

type paymentEvent struct {
	ID        string    `bson:"_id"`
	UserID    string    `bson:"userId"`
	Type      string    `bson:"type"`
	Status    string    `bson:"status"`
	Amount    float64   `bson:"amount"`
	Currency  string    `bson:"currency"`
	Channel   string    `bson:"channel,omitempty"`
	Reference string    `bson:"reference,omitempty"`
	CreatedAt time.Time `bson:"createdAt"`
}

type withdrawalRecord struct {
	ID           string    `bson:"_id"`
	UserID       string    `bson:"userId"`
	Phone        string    `bson:"phone"`
	Channel      string    `bson:"channel"`
	Amount       float64   `bson:"amount"`
	Currency     string    `bson:"currency"`
	PaystackRef  string    `bson:"paystackRef"`
	TransferCode string    `bson:"transferCode,omitempty"`
	Status       string    `bson:"status"`
	CreatedAt    time.Time `bson:"createdAt"`
	UpdatedAt    time.Time `bson:"updatedAt"`
}

type cryptoDepositPayload struct {
	TxID          string  `json:"txId"`
	Address       string  `json:"address"`
	Coin          string  `json:"coin"`
	Network       string  `json:"network"`
	AmountCrypto  float64 `json:"amount"`
	AmountUsd     float64 `json:"amountUsd"`
	Confirmations int     `json:"confirmations"`
}

type paystackWebhook struct {
	Event string          `json:"event"`
	Data  json.RawMessage `json:"data"`
}

type paystackChargeData struct {
	Reference string `json:"reference"`
	Status    string `json:"status"`
	Amount    int64  `json:"amount"`
	Currency  string `json:"currency"`
}

type paystackTransferData struct {
	TransferCode string `json:"transfer_code"`
	Reference    string `json:"reference"`
	Status       string `json:"status"`
	Amount       int64  `json:"amount"`
	Currency     string `json:"currency"`
}

// =============================================================================
// MOBILE MONEY — DEPOSIT
// =============================================================================

// InitiateMoMoDeposit triggers a Paystack MoMo charge for the user's phone.
// POST /api/v1/payments/momo/deposit
func (h *Handler) InitiateMoMoDeposit(c *fiber.Ctx) error {
	userID := c.Locals("userId").(string)

	var body struct {
		Phone   string  `json:"phone" validate:"required"`
		Amount  float64 `json:"amount" validate:"required,gt=0"`
		Channel string  `json:"channel" validate:"required"` // mtn-gh | vodafone-gh | airteltigo-gh
	}
	if err := c.BodyParser(&body); err != nil {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "invalid request body"})
	}
	body.Phone = strings.TrimSpace(body.Phone)
	body.Channel = strings.ToLower(strings.TrimSpace(body.Channel))
	if body.Phone == "" || body.Amount <= 0 || body.Channel == "" {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "phone, channel and amount are required"})
	}
	if !h.isChannelSupported(body.Channel) {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "unsupported channel"})
	}

	// Generate a unique reference per transaction
	clientRef := fmt.Sprintf("DEP-%s-%d", shortID(userID), time.Now().UnixNano())

	// Record the intent before calling Paystack (idempotency anchor)
	event := bson.M{
		"_id":       clientRef, // clientReference as _id for O(1) dedup
		"userId":    userID,
		"type":      "MOMO_DEPOSIT",
		"channel":   body.Channel,
		"phone":     body.Phone,
		"amount":    body.Amount,
		"currency":  "GHS",
		"status":    "PENDING",
		"createdAt": time.Now(),
		"updatedAt": time.Now(),
	}
	_, err := h.db.Collection("payment_events").InsertOne(context.Background(), event)
	if err != nil {
		return c.Status(http.StatusInternalServerError).JSON(fiber.Map{"error": "failed to record payment intent"})
	}
	log.Printf("[payments][deposit][%s] user=%s channel=%s amount=%.2f", clientRef, userID, body.Channel, body.Amount)

	amountMinor := toMinorUnits(body.Amount)
	provider := providerFromChannel(body.Channel)

	resp, err := h.paystackClient.ChargeMobileMoney(context.Background(), paystack.ChargeRequest{
		Reference:   clientRef,
		Email:       fmt.Sprintf("%s@gusers.gamehub", userID),
		AmountMinor: amountMinor,
		Currency:    h.cfg.PaystackDefaultCurrency,
		Phone:       body.Phone,
		Provider:    provider,
	})
	if err != nil {
		// Mark as failed in DB but don't lose the record
		h.db.Collection("payment_events").UpdateOne(context.Background(),
			bson.M{"_id": clientRef},
			bson.M{"$set": bson.M{"status": "INITIATION_FAILED", "error": err.Error()}},
		)
		return c.Status(http.StatusBadGateway).JSON(fiber.Map{"error": "could not initiate Paystack payment"})
	}

	return c.Status(http.StatusAccepted).JSON(fiber.Map{
		"reference":   clientRef,
		"message":     "Paystack mobile money prompt sent to your phone. Approve it to finish the deposit.",
		"displayText": resp.DisplayText,
		"status":      "PENDING",
	})
}

// GetMoMoStatus checks the current status of a MoMo payment.
// GET /api/v1/payments/momo/status/:reference
func (h *Handler) GetMoMoStatus(c *fiber.Ctx) error {
	ref := c.Params("reference")
	userID := c.Locals("userId").(string)

	var event bson.M
	err := h.db.Collection("payment_events").FindOne(context.Background(),
		bson.M{"_id": ref, "userId": userID},
	).Decode(&event)
	if err == mongo.ErrNoDocuments {
		return c.Status(http.StatusNotFound).JSON(fiber.Map{"error": "payment not found"})
	}

	return c.JSON(event)
}

// =============================================================================
// MOBILE MONEY — WITHDRAWAL
// =============================================================================

// InitiateMoMoWithdrawal requests a payout to a user's mobile wallet.
// POST /api/v1/payments/momo/withdraw
func (h *Handler) InitiateMoMoWithdrawal(c *fiber.Ctx) error {
	userID := c.Locals("userId").(string)

	var body struct {
		Phone   string  `json:"phone" validate:"required"`
		Amount  float64 `json:"amount" validate:"required,gt=0"`
		Channel string  `json:"channel" validate:"required"`
	}
	if err := c.BodyParser(&body); err != nil {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "invalid request body"})
	}
	body.Phone = strings.TrimSpace(body.Phone)
	body.Channel = strings.ToLower(strings.TrimSpace(body.Channel))
	if body.Phone == "" || body.Amount <= 0 || body.Channel == "" {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "phone, amount and channel are required"})
	}
	if !h.isChannelSupported(body.Channel) {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "unsupported channel"})
	}

	// Step 1: Reserve funds in Wallet Service BEFORE initiating Paystack payout.
	// This prevents overdraft if the Paystack call is slow or retried.
	withdrawalID := primitive.NewObjectID().Hex()
	err := h.walletClient.ReserveWithdrawal(context.Background(), wallet.ReservationRequest{
		UserID:       userID,
		WithdrawalID: withdrawalID,
		AmountUsd:    body.Amount,
	})
	if err != nil {
		return c.Status(http.StatusUnprocessableEntity).JSON(fiber.Map{
			"error": fmt.Sprintf("insufficient balance or reservation failed: %v", err),
		})
	}

	clientRef := fmt.Sprintf("WIT-%s-%d", shortID(userID), time.Now().UnixNano())

	// Step 2: Record withdrawal intent
	h.db.Collection("withdrawals").InsertOne(context.Background(), bson.M{
		"_id":         withdrawalID,
		"userId":      userID,
		"phone":       body.Phone,
		"channel":     body.Channel,
		"amount":      body.Amount,
		"currency":    "GHS",
		"paystackRef": clientRef,
		"status":      "PROCESSING",
		"createdAt":   time.Now(),
	})
	log.Printf("[payments][withdraw][%s] user=%s channel=%s amount=%.2f", clientRef, userID, body.Channel, body.Amount)

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	provider := providerFromChannel(body.Channel)
	recipient, err := h.paystackClient.CreateTransferRecipient(ctx, paystack.TransferRecipientRequest{
		Name:     fmt.Sprintf("GH-%s", shortID(userID)),
		Phone:    body.Phone,
		Provider: provider,
		Currency: h.cfg.PaystackDefaultCurrency,
	})
	if err != nil {
		h.walletClient.ReleaseWithdrawal(context.Background(), userID, withdrawalID, false)
		h.db.Collection("withdrawals").UpdateOne(context.Background(),
			bson.M{"_id": withdrawalID},
			bson.M{"$set": bson.M{"status": "FAILED", "error": err.Error()}},
		)
		return c.Status(http.StatusBadGateway).JSON(fiber.Map{"error": "could not register transfer recipient"})
	}

	transfer, err := h.paystackClient.InitiateTransfer(ctx, paystack.TransferRequest{
		Reference:     clientRef,
		AmountMinor:   toMinorUnits(body.Amount),
		Currency:      h.cfg.PaystackDefaultCurrency,
		RecipientCode: recipient.RecipientCode,
		Reason:        "Glory Grid Wallet Withdrawal",
	})
	if err != nil {
		h.walletClient.ReleaseWithdrawal(context.Background(), userID, withdrawalID, false)
		h.db.Collection("withdrawals").UpdateOne(context.Background(),
			bson.M{"_id": withdrawalID},
			bson.M{"$set": bson.M{"status": "FAILED", "error": err.Error()}},
		)
		return c.Status(http.StatusBadGateway).JSON(fiber.Map{"error": "could not initiate withdrawal"})
	}
	h.db.Collection("withdrawals").UpdateOne(context.Background(),
		bson.M{"_id": withdrawalID},
		bson.M{"$set": bson.M{"transferCode": transfer.TransferCode}},
	)

	return c.Status(http.StatusAccepted).JSON(fiber.Map{
		"withdrawalId": withdrawalID,
		"reference":    clientRef,
		"status":       "PROCESSING",
		"message":      "Withdrawal is being processed. Funds will arrive within 1–5 minutes.",
	})
}

// =============================================================================
// PAYSTACK WEBHOOKS
// =============================================================================

// PaystackDepositCallback handles Paystack's POST when a deposit payment is settled.
// POST /webhooks/payment/paystack
func (h *Handler) PaystackDepositCallback(c *fiber.Ctx) error {
	var evt paystackWebhook
	if err := json.Unmarshal(c.Body(), &evt); err != nil {
		return c.Status(http.StatusBadRequest).SendString("bad payload")
	}
	var data paystackChargeData
	if err := json.Unmarshal(evt.Data, &data); err != nil {
		return c.Status(http.StatusBadRequest).SendString("invalid data")
	}
	ref := data.Reference
	if ref == "" {
		return c.SendStatus(http.StatusOK)
	}

	key := fmt.Sprintf("idempotency:paystack:%s", ref)
	set, _ := h.rdb.SetNX(context.Background(), key, "1", 24*time.Hour).Result()
	if !set {
		// Already processed — acknowledge and exit
		return c.SendStatus(http.StatusOK)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	status := strings.ToLower(evt.Event)
	if status == "charge.success" || strings.EqualFold(data.Status, "success") {
		log.Printf("[payments][deposit][%s] webhook success", ref)
		if err := h.markMoMoDepositConfirmed(ctx, ref, ref); err != nil {
			log.Printf("paystack webhook confirm failed: %v", err)
		}
	} else if status == "charge.failed" || strings.EqualFold(data.Status, "failed") {
		log.Printf("[payments][deposit][%s] webhook failure", ref)
		if err := h.markMoMoDepositFailed(ctx, ref); err != nil {
			log.Printf("paystack webhook fail mark error: %v", err)
		}
	}

	return c.SendStatus(http.StatusOK)
}

// PaystackWithdrawalCallback handles Paystack's POST when a transfer is settled.
// POST /webhooks/payment/paystack/withdrawal
func (h *Handler) PaystackWithdrawalCallback(c *fiber.Ctx) error {
	var evt paystackWebhook
	if err := json.Unmarshal(c.Body(), &evt); err != nil {
		return c.Status(http.StatusBadRequest).SendString("bad payload")
	}
	var data paystackTransferData
	if err := json.Unmarshal(evt.Data, &data); err != nil {
		return c.Status(http.StatusBadRequest).SendString("invalid data")
	}
	ref := data.Reference
	if ref == "" {
		ref = data.TransferCode
	}
	if ref == "" {
		return c.SendStatus(http.StatusOK)
	}

	key := fmt.Sprintf("idempotency:paystack:withdrawal:%s", ref)
	set, _ := h.rdb.SetNX(context.Background(), key, "1", 24*time.Hour).Result()
	if !set {
		return c.SendStatus(http.StatusOK)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	status := strings.ToLower(evt.Event)
	success := status == "transfer.success" || strings.EqualFold(data.Status, "success")

	if success {
		log.Printf("[payments][withdraw][%s] webhook success", ref)
		if err := h.settleWithdrawal(ctx, ref, true); err != nil {
			log.Printf("withdrawal settle error: %v", err)
		}
	} else if status == "transfer.failed" || strings.EqualFold(data.Status, "failed") {
		log.Printf("[payments][withdraw][%s] webhook failure", ref)
		if err := h.settleWithdrawal(ctx, ref, false); err != nil {
			log.Printf("withdrawal revert error: %v", err)
		}
	}

	return c.SendStatus(http.StatusOK)
}

// =============================================================================
// BACKGROUND: Poll Paystack for PENDING payments (catches missed webhooks)
// =============================================================================

// RunPaystackStatusPoller checks PENDING payments every 30s.
// This ensures we never miss a settlement even if Paystack's webhook is late.
func (h *Handler) RunPaystackStatusPoller(ctx context.Context) {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			h.pollPendingPayments(ctx)
		}
	}
}

func (h *Handler) pollPendingPayments(ctx context.Context) {
	// Find payments stuck as PENDING for more than 2 minutes
	cutoff := time.Now().Add(-2 * time.Minute)
	cursor, err := h.db.Collection("payment_events").Find(ctx, bson.M{
		"status":    "PENDING",
		"createdAt": bson.M{"$lt": cutoff},
	})
	if err != nil {
		log.Printf("poller: query error: %v", err)
		return
	}
	defer cursor.Close(ctx)

	for cursor.Next(ctx) {
		var event bson.M
		if cursor.Decode(&event) != nil {
			continue
		}
		ref, _ := event["_id"].(string)
		status, err := h.paystackClient.GetTransactionStatus(ctx, ref)
		if err != nil {
			continue
		}
		if strings.EqualFold(status.Status, "success") {
			if err := h.markMoMoDepositConfirmed(ctx, ref, status.Reference); err != nil {
				log.Printf("poller confirm error: %v", err)
				continue
			}
			log.Printf("poller: recovered confirmed payment %s", ref)
		} else if strings.EqualFold(status.Status, "failed") {
			if err := h.markMoMoDepositFailed(ctx, ref); err != nil {
				log.Printf("poller fail mark error: %v", err)
			}
		}
	}
}

// =============================================================================
// CRYPTO DEPOSIT WEBHOOK (Tatum)
// =============================================================================

// CryptoDepositCallback handles Tatum's webhook when a crypto tx is confirmed.
// POST /webhooks/payment/crypto
func (h *Handler) CryptoDepositCallback(c *fiber.Ctx) error {
	var payload cryptoDepositPayload
	if err := c.BodyParser(&payload); err != nil {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "invalid payload"})
	}
	payload.Coin = strings.ToUpper(strings.TrimSpace(payload.Coin))
	if payload.Coin == "" {
		payload.Coin = "USDT"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	var walletDoc bson.M
	err := h.db.Collection("crypto_wallets").FindOne(ctx, bson.M{"address": payload.Address}).Decode(&walletDoc)
	if errors.Is(err, mongo.ErrNoDocuments) {
		return c.SendStatus(http.StatusOK)
	}
	if err != nil {
		return httpError(c, err)
	}

	userID := stringID(walletDoc["userId"])
	if userID == "" {
		return c.SendStatus(http.StatusOK)
	}

	required := confirmationThreshold[payload.Coin]
	if required == 0 {
		required = 3
	}
	status := "PENDING"
	if payload.Confirmations >= required {
		status = "CONFIRMED"
	}

	var existing bson.M
	err = h.db.Collection("crypto_deposits").FindOne(ctx, bson.M{"_id": payload.TxID}).Decode(&existing)
	if err != nil && !errors.Is(err, mongo.ErrNoDocuments) {
		return httpError(c, err)
	}
	alreadyConfirmed := existing["status"] == "CONFIRMED"

	update := bson.M{
		"$set": bson.M{
			"userId":        userID,
			"coin":          payload.Coin,
			"network":       payload.Network,
			"amountCrypto":  payload.AmountCrypto,
			"amountUsd":     payload.AmountUsd,
			"confirmations": payload.Confirmations,
			"status":        status,
			"updatedAt":     time.Now(),
		},
		"$setOnInsert": bson.M{
			"createdAt": time.Now(),
		},
	}
	if _, err := h.db.Collection("crypto_deposits").UpdateByID(ctx, payload.TxID, update, options.Update().SetUpsert(true)); err != nil {
		return httpError(c, err)
	}

	if status == "CONFIRMED" && !alreadyConfirmed {
		amountUsd := payload.AmountUsd
		if amountUsd <= 0 {
			amountUsd = payload.AmountCrypto
		}
		if err := h.walletClient.CreditDeposit(ctx, wallet.CreditRequest{
			UserID:    userID,
			AmountUsd: amountUsd,
			Source:    fmt.Sprintf("CRYPTO_%s", payload.Coin),
			Reference: payload.TxID,
		}); err != nil {
			return httpError(c, err)
		}
		h.publishPaymentEvent(userID, fiber.Map{
			"type":      "CRYPTO_DEPOSIT_CONFIRMED",
			"amountUsd": amountUsd,
			"coin":      payload.Coin,
			"txHash":    payload.TxID,
		})
	}

	return c.SendStatus(http.StatusOK)
}

// =============================================================================
// WEBSOCKET — Real-time payment status push to Flutter client
// =============================================================================

// PaymentStatusWebSocket allows Flutter to subscribe to payment updates.
// The client connects once and receives pushes when deposits/withdrawals settle.
// GET /ws/payments (upgraded to WS)
func (h *Handler) PaymentStatusWebSocket(c *websocket.Conn) {
	userID := c.Locals("userId").(string)
	channel := fmt.Sprintf("payment:user:%s", userID)

	pubsub := h.rdb.Subscribe(context.Background(), channel)
	defer pubsub.Close()

	ch := pubsub.Channel()
	for msg := range ch {
		if err := c.WriteMessage(websocket.TextMessage, []byte(msg.Payload)); err != nil {
			break
		}
	}
}

// Additional route handlers (history, withdrawals list, etc.)
func (h *Handler) GetPaymentHistory(c *fiber.Ctx) error {
	userID := c.Locals("userId").(string)
	limit := parseLimit(c.Query("limit"), 20, 100)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	cursor, err := h.db.Collection("payment_events").Find(ctx,
		bson.M{"userId": userID},
		options.Find().SetSort(bson.D{{Key: "createdAt", Value: -1}}).SetLimit(limit),
	)
	if err != nil {
		return httpError(c, err)
	}
	defer cursor.Close(ctx)

	var events []paymentEvent
	if err := cursor.All(ctx, &events); err != nil {
		return httpError(c, err)
	}

	return c.JSON(fiber.Map{"items": events})
}

func (h *Handler) GetWithdrawals(c *fiber.Ctx) error {
	userID := c.Locals("userId").(string)
	limit := parseLimit(c.Query("limit"), 20, 100)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	cursor, err := h.db.Collection("withdrawals").Find(ctx,
		bson.M{"userId": userID},
		options.Find().SetSort(bson.D{{Key: "createdAt", Value: -1}}).SetLimit(limit),
	)
	if err != nil {
		return httpError(c, err)
	}
	defer cursor.Close(ctx)

	var records []withdrawalRecord
	if err := cursor.All(ctx, &records); err != nil {
		return httpError(c, err)
	}
	return c.JSON(fiber.Map{"items": records})
}

func (h *Handler) GetCryptoDepositStatus(c *fiber.Ctx) error {
	txHash := c.Params("txHash")
	if txHash == "" {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "txHash required"})
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	var deposit bson.M
	err := h.db.Collection("crypto_deposits").FindOne(ctx, bson.M{"_id": txHash}).Decode(&deposit)
	if errors.Is(err, mongo.ErrNoDocuments) {
		return c.Status(http.StatusNotFound).JSON(fiber.Map{"error": "deposit not found"})
	}
	if err != nil {
		return httpError(c, err)
	}
	return c.JSON(deposit)
}

func (h *Handler) GenerateCryptoAddress(c *fiber.Ctx) error {
	userID := c.Locals("userId").(string)
	var body struct {
		Coin    string `json:"coin"`
		Network string `json:"network"`
	}
	if err := c.BodyParser(&body); err != nil {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "invalid payload"})
	}
	body.Coin = strings.ToUpper(strings.TrimSpace(body.Coin))
	if body.Coin == "" {
		body.Coin = "USDT"
	}
	network := strings.ToUpper(strings.TrimSpace(body.Network))
	if network == "" {
		network = defaultNetworks[body.Coin]
		if network == "" {
			network = "L1"
		}
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	address, err := h.tatumClient.GenerateAddress(ctx, body.Coin)
	if err != nil {
		return c.Status(http.StatusBadGateway).JSON(fiber.Map{"error": "address generation failed"})
	}

	doc := bson.M{
		"userId":     userID,
		"coin":       body.Coin,
		"network":    network,
		"address":    address,
		"createdAt":  time.Now(),
		"derivation": fmt.Sprintf("user/%s/%d", userID, time.Now().Unix()),
	}
	if _, err := h.db.Collection("crypto_wallets").InsertOne(ctx, doc); err != nil {
		return httpError(c, err)
	}

	return c.JSON(fiber.Map{
		"address":   address,
		"coin":      body.Coin,
		"network":   network,
		"createdAt": doc["createdAt"],
	})
}

func (h *Handler) GetPendingWithdrawals(c *fiber.Ctx) error {
	userID := c.Params("userId")
	if userID == "" {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "userId required"})
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	cursor, err := h.db.Collection("withdrawals").Find(ctx, bson.M{
		"userId": userID,
		"status": bson.M{"$in": []string{"PROCESSING", "HELD"}},
	})
	if err != nil {
		return httpError(c, err)
	}
	defer cursor.Close(ctx)

	var records []withdrawalRecord
	if err := cursor.All(ctx, &records); err != nil {
		return httpError(c, err)
	}
	return c.JSON(fiber.Map{"items": records})
}

func httpError(c *fiber.Ctx, err error) error {
	return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
}

func parseLimit(raw string, fallback, max int64) int64 {
	if raw == "" {
		return fallback
	}
	val, err := strconv.ParseInt(raw, 10, 64)
	if err != nil || val <= 0 {
		return fallback
	}
	if val > max {
		return max
	}
	return val
}

func shortID(id string) string {
	if len(id) <= 8 {
		return id
	}
	return id[:8]
}

func (h *Handler) isChannelSupported(channel string) bool {
	if len(h.cfg.PaystackAllowedChannels) == 0 {
		return true
	}
	for _, ch := range h.cfg.PaystackAllowedChannels {
		if ch == channel {
			return true
		}
	}
	return false
}

func (h *Handler) markMoMoDepositConfirmed(ctx context.Context, ref, txID string) error {
	res := h.db.Collection("payment_events").FindOneAndUpdate(
		ctx,
		bson.M{"_id": ref, "status": bson.M{"$in": []string{"PENDING", "PROCESSING"}}},
		bson.M{"$set": bson.M{
			"status":       "CONFIRMED",
			"paystackTxId": txID,
			"settledAt":    time.Now(),
			"updatedAt":    time.Now(),
		}},
		options.FindOneAndUpdate().SetReturnDocument(options.After),
	)
	var event paymentEvent
	if err := res.Decode(&event); err != nil {
		if errors.Is(err, mongo.ErrNoDocuments) {
			return nil
		}
		return err
	}
	if event.UserID == "" || event.Amount <= 0 {
		return nil
	}
	if err := h.walletClient.CreditDeposit(ctx, wallet.CreditRequest{
		UserID:    event.UserID,
		AmountUsd: event.Amount,
		Source:    "MOMO_DEPOSIT",
		Reference: ref,
	}); err != nil {
		return err
	}
	h.publishPaymentEvent(event.UserID, fiber.Map{
		"type":      "DEPOSIT_CONFIRMED",
		"amount":    event.Amount,
		"reference": ref,
	})
	return nil
}

func (h *Handler) markMoMoDepositFailed(ctx context.Context, ref string) error {
	_, err := h.db.Collection("payment_events").UpdateOne(ctx,
		bson.M{"_id": ref, "status": bson.M{"$ne": "FAILED"}},
		bson.M{"$set": bson.M{"status": "FAILED", "settledAt": time.Now(), "updatedAt": time.Now()}},
	)
	if errors.Is(err, mongo.ErrNoDocuments) {
		return nil
	}
	return err
}

func (h *Handler) settleWithdrawal(ctx context.Context, paystackRef string, success bool) error {
	var rec withdrawalRecord
	err := h.db.Collection("withdrawals").FindOne(ctx, bson.M{"paystackRef": paystackRef}).Decode(&rec)
	if errors.Is(err, mongo.ErrNoDocuments) {
		return nil
	}
	if err != nil {
		return err
	}
	if rec.UserID == "" || rec.ID == "" {
		return nil
	}
	if err := h.walletClient.ReleaseWithdrawal(ctx, rec.UserID, rec.ID, success); err != nil {
		return err
	}
	status := "FAILED"
	event := "WITHDRAWAL_FAILED"
	if success {
		status = "COMPLETED"
		event = "WITHDRAWAL_COMPLETED"
	}
	_, err = h.db.Collection("withdrawals").UpdateOne(ctx,
		bson.M{"_id": rec.ID},
		bson.M{"$set": bson.M{"status": status, "updatedAt": time.Now(), "settledAt": time.Now()}},
	)
	if err != nil {
		return err
	}
	h.publishPaymentEvent(rec.UserID, fiber.Map{
		"type":   event,
		"amount": rec.Amount,
	})
	return nil
}

func (h *Handler) publishPaymentEvent(userID string, payload interface{}) {
	if userID == "" {
		return
	}
	data, err := json.Marshal(payload)
	if err != nil {
		return
	}
	h.rdb.Publish(context.Background(), fmt.Sprintf("payment:user:%s", userID), string(data))
}

func stringID(v interface{}) string {
	switch val := v.(type) {
	case string:
		return val
	case primitive.ObjectID:
		return val.Hex()
	default:
		return ""
	}
}

func toMinorUnits(amount float64) int64 {
	if amount <= 0 {
		return 0
	}
	return int64(math.Round(amount * 100))
}

func providerFromChannel(channel string) string {
	switch strings.ToLower(channel) {
	case "mtn-gh", "mtn":
		return "mtn"
	case "vodafone-gh", "vodafone", "telecel-gh", "telecel":
		return "vodafone"
	case "airteltigo-gh", "airteltigo", "airtel", "tigo":
		return "airtel"
	default:
		return strings.TrimSuffix(strings.ToLower(channel), "-gh")
	}
}
