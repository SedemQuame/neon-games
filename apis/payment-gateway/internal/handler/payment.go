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
	"sync"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/websocket/v2"
	"github.com/redis/go-redis/v9"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"

	"gamehub/payment-gateway/internal/config"
	"gamehub/payment-gateway/internal/flutterwave"
	"gamehub/payment-gateway/internal/tatum"
	"gamehub/payment-gateway/internal/wallet"
)

// Active polling trackers
var activeCryptoChecks sync.Map

type Handler struct {
	db            *mongo.Database
	rdb           *redis.Client
	flutterClient *flutterwave.Client
	tatumClient   *tatum.Client
	walletClient  *wallet.HTTPClient
	cfg           *config.Config
}

func New(db *mongo.Database, rdb *redis.Client, fc *flutterwave.Client, tc *tatum.Client, wc *wallet.HTTPClient, cfg *config.Config) *Handler {
	return &Handler{db: db, rdb: rdb, flutterClient: fc, tatumClient: tc, walletClient: wc, cfg: cfg}
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
	ID           string    `bson:"_id"`
	UserID       string    `bson:"userId"`
	Type         string    `bson:"type"`
	Status       string    `bson:"status"`
	Amount       float64   `bson:"amount"`
	Currency     string    `bson:"currency"`
	Channel      string    `bson:"channel,omitempty"`
	Phone        string    `bson:"phone,omitempty"`
	Reference    string    `bson:"reference,omitempty"`
	ProviderTxID string    `bson:"providerTxId,omitempty"`
	CreatedAt    time.Time `bson:"createdAt"`
	UpdatedAt    time.Time `bson:"updatedAt"`
	SettledAt    time.Time `bson:"settledAt,omitempty"`
}

type withdrawalRecord struct {
	ID                string    `bson:"_id"`
	UserID            string    `bson:"userId"`
	Phone             string    `bson:"phone"`
	Channel           string    `bson:"channel"`
	Amount            float64   `bson:"amount"`
	Currency          string    `bson:"currency"`
	ProviderRef       string    `bson:"providerRef,omitempty"`
	LegacyPaystackRef string    `bson:"paystackRef,omitempty"`
	TransferCode      string    `bson:"transferCode,omitempty"`
	Status            string    `bson:"status"`
	CreatedAt         time.Time `bson:"createdAt"`
	UpdatedAt         time.Time `bson:"updatedAt"`
	SettledAt         time.Time `bson:"settledAt,omitempty"`
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

type flutterwaveWebhook struct {
	Event string                 `json:"event"`
	Data  flutterwaveWebhookData `json:"data"`
}

type flutterwaveWebhookData struct {
	ID        int64   `json:"id"`
	Status    string  `json:"status"`
	TxRef     string  `json:"tx_ref"`
	Reference string  `json:"reference"`
	FlwRef    string  `json:"flw_ref"`
	Amount    float64 `json:"amount"`
	Currency  string  `json:"currency"`
}

// =============================================================================
// MOBILE MONEY — DEPOSIT
// =============================================================================

// InitiateMoMoDeposit triggers a Flutterwave MoMo charge for the user's phone.
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
	body.Phone = normalizePhone(strings.TrimSpace(body.Phone))
	body.Channel = normalizeChannel(body.Channel)
	if body.Phone == "" || body.Amount <= 0 || body.Channel == "" {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "phone, channel and amount are required"})
	}
	if !h.isChannelSupported(body.Channel) {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "unsupported channel"})
	}

	amount := roundMoney(body.Amount)
	if amount <= 0 {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "amount must be at least 0.01"})
	}

	clientRef := fmt.Sprintf("DEP-%s-%d", shortID(userID), time.Now().UnixNano())
	event := bson.M{
		"_id":       clientRef,
		"reference": clientRef,
		"userId":    userID,
		"type":      "MOMO_DEPOSIT",
		"channel":   body.Channel,
		"phone":     body.Phone,
		"amount":    amount,
		"currency":  h.cfg.MoMoDefaultCurrency,
		"status":    "PENDING",
		"createdAt": time.Now(),
		"updatedAt": time.Now(),
	}
	if _, err := h.db.Collection("payment_events").InsertOne(context.Background(), event); err != nil {
		log.Printf("[payments][deposit][%s] ERROR InsertOne payment_events: %v", clientRef, err)
		return c.Status(http.StatusInternalServerError).JSON(fiber.Map{"error": "failed to record payment intent"})
	}
	log.Printf("[payments][deposit][%s] user=%s channel=%s amount=%.2f", clientRef, userID, body.Channel, amount)

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	network := networkFromChannel(body.Channel)
	resp, err := h.flutterClient.ChargeMobileMoney(ctx, flutterwave.MobileMoneyChargeRequest{
		Reference:   clientRef,
		Amount:      amount,
		Currency:    h.cfg.MoMoDefaultCurrency,
		Email:       fmt.Sprintf("%s@gusers.gamehub", userID),
		FullName:    fmt.Sprintf("Glory Grid %s", shortID(userID)),
		PhoneNumber: body.Phone,
		Network:     network,
		Narration:   "Glory Grid Deposit",
		CallbackURL: h.cfg.FlutterwaveChargeCallback,
	}, clientRef)
	if err != nil {
		log.Printf("[payments][deposit][%s] flutterwave charge error: %v", clientRef, err)
		h.db.Collection("payment_events").UpdateOne(context.Background(),
			bson.M{"_id": clientRef},
			bson.M{"$set": bson.M{"status": "INITIATION_FAILED", "error": err.Error(), "updatedAt": time.Now()}},
		)
		return c.Status(http.StatusBadGateway).JSON(fiber.Map{"error": "could not initiate Flutterwave payment"})
	}

	respBody := fiber.Map{
		"reference":         clientRef,
		"status":            "PENDING",
		"message":           "Approve the mobile money prompt that just appeared on your phone to finish the deposit.",
		"providerReference": resp.FlwRef,
	}
	if resp.Authorization != nil {
		if resp.Authorization.Mode != "" {
			respBody["providerAuthMode"] = resp.Authorization.Mode
		}
		if resp.Authorization.Redirect != "" {
			respBody["providerRedirectUrl"] = resp.Authorization.Redirect
			respBody["message"] = "We opened Flutterwave to finish verification. Complete that step, then approve the prompt on your phone."
		}
	}
	return c.Status(http.StatusAccepted).JSON(respBody)
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
	if err != nil {
		return httpError(c, err)
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
	body.Phone = normalizePhone(strings.TrimSpace(body.Phone))
	body.Channel = normalizeChannel(body.Channel)
	if body.Phone == "" || body.Amount <= 0 || body.Channel == "" {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "phone, amount and channel are required"})
	}
	if !h.isChannelSupported(body.Channel) {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "unsupported channel"})
	}
	amount := roundMoney(body.Amount)

	withdrawalID := primitive.NewObjectID().Hex()
	if err := h.walletClient.ReserveWithdrawal(context.Background(), wallet.ReservationRequest{
		UserID:       userID,
		WithdrawalID: withdrawalID,
		AmountUsd:    amount,
	}); err != nil {
		return c.Status(http.StatusUnprocessableEntity).JSON(fiber.Map{
			"error": fmt.Sprintf("insufficient balance or reservation failed: %v", err),
		})
	}

	clientRef := fmt.Sprintf("WIT-%s-%d", shortID(userID), time.Now().UnixNano())
	doc := bson.M{
		"_id":         withdrawalID,
		"userId":      userID,
		"phone":       body.Phone,
		"channel":     body.Channel,
		"amount":      amount,
		"currency":    h.cfg.MoMoDefaultCurrency,
		"providerRef": clientRef,
		"paystackRef": clientRef,
		"status":      "PROCESSING",
		"createdAt":   time.Now(),
		"updatedAt":   time.Now(),
	}
	h.db.Collection("withdrawals").InsertOne(context.Background(), doc)
	log.Printf("[payments][withdraw][%s] user=%s channel=%s amount=%.2f", clientRef, userID, body.Channel, amount)

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	network := networkFromChannel(body.Channel)
	transfer, err := h.flutterClient.InitiateTransfer(ctx, flutterwave.TransferRequest{
		Reference:     clientRef,
		Amount:        amount,
		Currency:      h.cfg.MoMoDefaultCurrency,
		DebitCurrency: h.cfg.MoMoDefaultCurrency,
		AccountBank:   network,
		AccountNumber: body.Phone,
		Narration:     "Glory Grid Wallet Withdrawal",
		CallbackURL:   h.cfg.FlutterwaveTransferCallback,
		Beneficiary:   fmt.Sprintf("GH %s", shortID(userID)),
	}, clientRef)
	if err != nil {
		h.walletClient.ReleaseWithdrawal(context.Background(), userID, withdrawalID, false)
		h.db.Collection("withdrawals").UpdateOne(context.Background(),
			bson.M{"_id": withdrawalID},
			bson.M{"$set": bson.M{"status": "FAILED", "error": err.Error(), "updatedAt": time.Now()}},
		)
		return c.Status(http.StatusBadGateway).JSON(fiber.Map{"error": "could not initiate withdrawal"})
	}

	h.db.Collection("withdrawals").UpdateOne(context.Background(),
		bson.M{"_id": withdrawalID},
		bson.M{"$set": bson.M{"transferCode": transfer.FlwRef}},
	)

	return c.Status(http.StatusAccepted).JSON(fiber.Map{
		"withdrawalId": withdrawalID,
		"reference":    clientRef,
		"status":       "PROCESSING",
		"message":      "Withdrawal is being processed. Funds will arrive within minutes once Flutterwave confirms.",
	})
}

// =============================================================================
// FLUTTERWAVE WEBHOOKS
// =============================================================================

// FlutterwaveDepositCallback handles Flutterwave charge notifications.
// POST /webhooks/payment/flutterwave
func (h *Handler) FlutterwaveDepositCallback(c *fiber.Ctx) error {
	var evt flutterwaveWebhook
	if err := json.Unmarshal(c.Body(), &evt); err != nil {
		return c.Status(http.StatusBadRequest).SendString("bad payload")
	}
	ref := firstNonEmpty(evt.Data.TxRef, evt.Data.Reference)
	if ref == "" {
		return c.SendStatus(http.StatusOK)
	}

	key := fmt.Sprintf("idempotency:flutterwave:deposit:%s", ref)
	set, _ := h.rdb.SetNX(context.Background(), key, "1", 24*time.Hour).Result()
	if !set {
		return c.SendStatus(http.StatusOK)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	status := strings.ToLower(evt.Data.Status)
	if status == "successful" || strings.EqualFold(evt.Event, "charge.completed") {
		log.Printf("[payments][deposit][%s] webhook success", ref)
		if err := h.markMoMoDepositConfirmed(ctx, ref, evt.Data.FlwRef); err != nil {
			log.Printf("flutterwave webhook confirm failed: %v", err)
		}
	} else if status == "failed" || strings.EqualFold(evt.Event, "charge.failed") {
		log.Printf("[payments][deposit][%s] webhook failure", ref)
		if err := h.markMoMoDepositFailed(ctx, ref); err != nil {
			log.Printf("flutterwave webhook fail mark error: %v", err)
		}
	}

	return c.SendStatus(http.StatusOK)
}

// FlutterwaveWithdrawalCallback handles Flutterwave transfer notifications.
// POST /webhooks/payment/flutterwave/withdrawal
func (h *Handler) FlutterwaveWithdrawalCallback(c *fiber.Ctx) error {
	var evt flutterwaveWebhook
	if err := json.Unmarshal(c.Body(), &evt); err != nil {
		return c.Status(http.StatusBadRequest).SendString("bad payload")
	}
	ref := firstNonEmpty(evt.Data.Reference, evt.Data.TxRef)
	if ref == "" {
		return c.SendStatus(http.StatusOK)
	}

	key := fmt.Sprintf("idempotency:flutterwave:withdrawal:%s", ref)
	set, _ := h.rdb.SetNX(context.Background(), key, "1", 24*time.Hour).Result()
	if !set {
		return c.SendStatus(http.StatusOK)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	status := strings.ToLower(evt.Data.Status)
	success := status == "successful" || strings.EqualFold(evt.Event, "transfer.completed")

	if success {
		log.Printf("[payments][withdraw][%s] webhook success", ref)
		if err := h.settleWithdrawal(ctx, ref, true); err != nil {
			log.Printf("withdrawal settle error: %v", err)
		}
	} else if status == "failed" || strings.EqualFold(evt.Event, "transfer.failed") {
		log.Printf("[payments][withdraw][%s] webhook failure", ref)
		if err := h.settleWithdrawal(ctx, ref, false); err != nil {
			log.Printf("withdrawal revert error: %v", err)
		}
	}

	return c.SendStatus(http.StatusOK)
}

// =============================================================================
// BACKGROUND: Poll Flutterwave for PENDING payments (catches missed webhooks)
// =============================================================================

// RunMoMoStatusPoller checks pending deposits/withdrawals every 30 seconds.
func (h *Handler) RunMoMoStatusPoller(ctx context.Context) {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			h.pollPendingDeposits(ctx)
			h.pollPendingWithdrawals(ctx)
		}
	}
}

func (h *Handler) pollPendingDeposits(ctx context.Context) {
	cutoff := time.Now().Add(-2 * time.Minute)
	cursor, err := h.db.Collection("payment_events").Find(ctx, bson.M{
		"status":    "PENDING",
		"type":      "MOMO_DEPOSIT",
		"createdAt": bson.M{"$lt": cutoff},
	})
	if err != nil {
		log.Printf("deposit poller: query error: %v", err)
		return
	}
	defer cursor.Close(ctx)

	for cursor.Next(ctx) {
		var event bson.M
		if err := cursor.Decode(&event); err != nil {
			continue
		}
		ref, _ := event["_id"].(string)
		if ref == "" {
			continue
		}
		tx, err := h.flutterClient.VerifyTransactionByReference(ctx, ref, ref)
		if err != nil {
			log.Printf("[payments][deposit-poller][%s] verify error: %v", ref, err)
			continue
		}
		log.Printf("[payments][deposit-poller][%s] status=%s", ref, tx.Status)
		if strings.EqualFold(tx.Status, "successful") {
			if err := h.markMoMoDepositConfirmed(ctx, ref, tx.FlwRef); err != nil {
				log.Printf("deposit poller confirm error: %v", err)
			}
		} else if strings.EqualFold(tx.Status, "failed") {
			if err := h.markMoMoDepositFailed(ctx, ref); err != nil {
				log.Printf("deposit poller fail error: %v", err)
			}
		}
	}
}

func (h *Handler) pollPendingWithdrawals(ctx context.Context) {
	cutoff := time.Now().Add(-2 * time.Minute)
	cursor, err := h.db.Collection("withdrawals").Find(ctx, bson.M{
		"status":    "PROCESSING",
		"createdAt": bson.M{"$lt": cutoff},
	})
	if err != nil {
		log.Printf("withdrawal poller: query error: %v", err)
		return
	}
	defer cursor.Close(ctx)

	for cursor.Next(ctx) {
		var record withdrawalRecord
		if err := cursor.Decode(&record); err != nil {
			continue
		}
		ref := record.ProviderRef
		if ref == "" {
			ref = record.LegacyPaystackRef
		}
		if ref == "" {
			continue
		}
		transfer, err := h.flutterClient.GetTransferByReference(ctx, ref, ref)
		if err != nil {
			log.Printf("[payments][withdraw-poller][%s] verify error: %v", ref, err)
			continue
		}
		log.Printf("[payments][withdraw-poller][%s] status=%s", ref, transfer.Status)
		if strings.EqualFold(transfer.Status, "successful") {
			if err := h.settleWithdrawal(ctx, ref, true); err != nil {
				log.Printf("withdrawal poller settle error: %v", err)
			}
		} else if strings.EqualFold(transfer.Status, "failed") {
			if err := h.settleWithdrawal(ctx, ref, false); err != nil {
				log.Printf("withdrawal poller revert error: %v", err)
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

// History + utility handlers (unchanged)

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

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// --- Get-or-Create: check if the user already has an address for this coin ---
	var existing bson.M
	err := h.db.Collection("crypto_wallets").FindOne(ctx, bson.M{
		"userId": userID,
		"coin":   body.Coin,
	}).Decode(&existing)
	if err == nil {
		// Already has one — return it
		return c.JSON(fiber.Map{
			"address":   existing["address"],
			"coin":      existing["coin"],
			"network":   existing["network"],
			"createdAt": existing["createdAt"],
		})
	}
	if err != nil && !errors.Is(err, mongo.ErrNoDocuments) {
		return httpError(c, err)
	}

	// --- Derive next HD wallet index via atomic counter ---
	counterKey := fmt.Sprintf("crypto_%s", strings.ToLower(body.Coin))
	counterResult := h.db.Collection("crypto_counters").FindOneAndUpdate(
		ctx,
		bson.M{"_id": counterKey},
		bson.M{"$inc": bson.M{"seq": int64(1)}},
		options.FindOneAndUpdate().SetUpsert(true).SetReturnDocument(options.After),
	)
	var counterDoc struct {
		Seq int64 `bson:"seq"`
	}
	if err := counterResult.Decode(&counterDoc); err != nil {
		return httpError(c, fmt.Errorf("failed to get derivation index: %w", err))
	}
	derivationIndex := counterDoc.Seq

	// --- Generate address via Tatum ---
	address, err := h.tatumClient.GenerateAddress(ctx, body.Coin, derivationIndex)
	if err != nil {
		return c.Status(http.StatusBadGateway).JSON(fiber.Map{"error": "address generation failed: " + err.Error()})
	}

	doc := bson.M{
		"userId":          userID,
		"coin":            body.Coin,
		"network":         network,
		"address":         address,
		"derivationIndex": derivationIndex,
		"status":          "ACTIVE",
		"createdAt":       time.Now(),
	}
	if _, err := h.db.Collection("crypto_wallets").InsertOne(ctx, doc); err != nil {
		return httpError(c, err)
	}

	// --- Register Tatum webhook subscription for this address (best-effort) ---
	if h.cfg.CryptoWebhookURL != "" {
		go func() {
			subCtx, subCancel := context.WithTimeout(context.Background(), 10*time.Second)
			defer subCancel()
			subID, err := h.tatumClient.CreateAddressSubscription(subCtx, body.Coin, address, h.cfg.CryptoWebhookURL)
			if err != nil {
				log.Printf("[crypto][address] webhook subscription failed for %s/%s: %v", body.Coin, address, err)
				return
			}
			h.db.Collection("crypto_wallets").UpdateOne(context.Background(),
				bson.M{"address": address},
				bson.M{"$set": bson.M{"subscriptionId": subID}},
			)
			log.Printf("[crypto][address] webhook subscription created for %s/%s → %s", body.Coin, address, subID)
		}()
	}

	return c.JSON(fiber.Map{
		"address":   address,
		"coin":      body.Coin,
		"network":   network,
		"createdAt": doc["createdAt"],
	})
}

func (h *Handler) GenerateAllCryptoWallets(c *fiber.Ctx) error {
	var body struct {
		UserID string `json:"userId"`
	}
	if err := c.BodyParser(&body); err != nil || body.UserID == "" {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "invalid payload or missing userId"})
	}

	coins := []string{"BTC", "ETH", "USDT"}
	results := make(map[string]interface{})

	// Fire them off synchronously; they are fast enough and happen in background anyway from auth's perspective.
	for _, coin := range coins {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		network := defaultNetworks[coin]
		if network == "" {
			network = "L1"
		}

		// Check if exists
		var existing bson.M
		err := h.db.Collection("crypto_wallets").FindOne(ctx, bson.M{
			"userId": body.UserID,
			"coin":   coin,
		}).Decode(&existing)
		if err == nil {
			results[coin] = existing["address"]
			continue
		}

		// Derive next HD index
		counterKey := fmt.Sprintf("crypto_%s", strings.ToLower(coin))
		counterResult := h.db.Collection("crypto_counters").FindOneAndUpdate(
			ctx,
			bson.M{"_id": counterKey},
			bson.M{"$inc": bson.M{"seq": int64(1)}},
			options.FindOneAndUpdate().SetUpsert(true).SetReturnDocument(options.After),
		)
		var counterDoc struct {
			Seq int64 `bson:"seq"`
		}
		if err := counterResult.Decode(&counterDoc); err != nil {
			results[coin] = fmt.Sprintf("error getting derivation index: %v", err)
			continue
		}
		derivationIndex := counterDoc.Seq

		// Generate via Tatum
		address, err := h.tatumClient.GenerateAddress(ctx, coin, derivationIndex)
		if err != nil {
			results[coin] = fmt.Sprintf("tatum error: %v", err)
			continue
		}

		doc := bson.M{
			"userId":          body.UserID,
			"coin":            coin,
			"network":         network,
			"address":         address,
			"derivationIndex": derivationIndex,
			"status":          "ACTIVE",
			"createdAt":       time.Now(),
		}
		if _, err := h.db.Collection("crypto_wallets").InsertOne(ctx, doc); err != nil {
			results[coin] = fmt.Sprintf("db insert error: %v", err)
			continue
		}

		// Best-effort webhook
		if h.cfg.CryptoWebhookURL != "" {
			go func(c string, a string) {
				subCtx, subCancel := context.WithTimeout(context.Background(), 10*time.Second)
				defer subCancel()
				subID, err := h.tatumClient.CreateAddressSubscription(subCtx, c, a, h.cfg.CryptoWebhookURL)
				if err != nil {
					log.Printf("[crypto][generate-all] webhook sub failed for %s/%s: %v", c, a, err)
					return
				}
				h.db.Collection("crypto_wallets").UpdateOne(context.Background(),
					bson.M{"address": a},
					bson.M{"$set": bson.M{"subscriptionId": subID}},
				)
			}(coin, address)
		}

		results[coin] = address
	}

	return c.JSON(fiber.Map{
		"userId":  body.UserID,
		"wallets": results,
	})
}

// ManualCryptoCheck allows the frontend to manually ask the backend to scan Tatum for a specific wallet address
func (h *Handler) ManualCryptoCheck(c *fiber.Ctx) error {
	var body struct {
		Coin    string `json:"coin"`
		Address string `json:"address"`
	}
	if err := c.BodyParser(&body); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "invalid JSON"})
	}
	if body.Coin == "" || body.Address == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "coin and address are required"})
	}

	userID := c.Locals("userId").(string)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// 1. Verify this wallet belongs to the user
	var walletDoc bson.M
	err := h.db.Collection("crypto_wallets").FindOne(ctx, bson.M{
		"userId":  userID,
		"coin":    body.Coin,
		"address": body.Address,
	}).Decode(&walletDoc)
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": "wallet not found"})
	}

	trackingKey := body.Coin + "_" + body.Address

	// 2. Check if already tracking
	if _, tracking := activeCryptoChecks.Load(trackingKey); tracking {
		return c.JSON(fiber.Map{
			"status": "TRACKING_STARTED",
			"found":  0,
		})
	}

	// Lock the tracking
	activeCryptoChecks.Store(trackingKey, true)

	// 3. Perform immediate check 0m
	status, count, err := h.checkAndProcessTxs(userID, body.Coin, body.Address)
	if err != nil {
		activeCryptoChecks.Delete(trackingKey)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to contact blockchain explorer"})
	}

	if status == "CONFIRMED" || status == "PENDING" {
		activeCryptoChecks.Delete(trackingKey)
		return c.JSON(fiber.Map{
			"status": status,
			"found":  count,
		})
	}

	// 4. Start background polling 1m, 3m
	go func(coin, address, uid, key string) {
		defer activeCryptoChecks.Delete(key) // Ensure cleanup when goroutine finishes

		// Wait 1 minute
		time.Sleep(1 * time.Minute)
		bgStatus, _, bgErr := h.checkAndProcessTxs(uid, coin, address)
		if bgErr == nil && (bgStatus == "CONFIRMED" || bgStatus == "PENDING") {
			return // Success, terminate early
		}

		// Wait 3 more minutes (total 4m from start)
		time.Sleep(3 * time.Minute)
		_, _, _ = h.checkAndProcessTxs(uid, coin, address)
		// Routine exits and defers deletion
	}(body.Coin, body.Address, userID, trackingKey)

	// Return to user immediately indicating we are watching it
	return c.JSON(fiber.Map{
		"status": "TRACKING_STARTED",
		"found":  count,
	})
}

func (h *Handler) checkAndProcessTxs(userID, coin, address string) (string, int, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	txs, err := h.tatumClient.GetTransactionsByAddress(ctx, coin, address)
	if err != nil {
		log.Printf("[crypto-check] error checking tatum for %s/%s: %v", coin, address, err)
		return "NO_TX", 0, err
	}

	if len(txs) == 0 {
		return "NO_TX", 0, nil
	}

	highestStatus := "NO_TX"
	for _, tx := range txs {
		if tx.Hash == "" {
			continue
		}

		// Process transaction uniquely
		h.processCryptoTx(context.Background(), userID, coin, address, tx)

		required := confirmationThreshold[coin]
		if required == 0 {
			required = 3
		}
		if tx.Confirmations >= required {
			highestStatus = "CONFIRMED"
		} else if highestStatus != "CONFIRMED" {
			highestStatus = "PENDING"
		}
	}

	return highestStatus, len(txs), nil
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
	if len(h.cfg.MoMoAllowedChannels) == 0 {
		return true
	}
	for _, ch := range h.cfg.MoMoAllowedChannels {
		if ch == channel {
			return true
		}
	}
	return false
}

func (h *Handler) markMoMoDepositConfirmed(ctx context.Context, ref, providerTxID string) error {
	res := h.db.Collection("payment_events").FindOneAndUpdate(
		ctx,
		bson.M{"_id": ref, "status": bson.M{"$in": []string{"PENDING", "PROCESSING"}}},
		bson.M{"$set": bson.M{
			"status":       "CONFIRMED",
			"providerTxId": providerTxID,
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

func (h *Handler) settleWithdrawal(ctx context.Context, providerRef string, success bool) error {
	filter := bson.M{
		"$or": []bson.M{
			{"providerRef": providerRef},
			{"paystackRef": providerRef},
		},
	}
	var rec withdrawalRecord
	err := h.db.Collection("withdrawals").FindOne(ctx, filter).Decode(&rec)
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

// =============================================================================
// INTERNAL: Crypto Master Wallet Configuration
// =============================================================================

// SaveCryptoWalletConfig stores or updates master wallet config per coin.
// Protected by RequireInternalKey middleware.
// POST /internal/crypto/wallets/config
func (h *Handler) SaveCryptoWalletConfig(c *fiber.Ctx) error {
	var body struct {
		Coin     string `json:"coin"`
		Xpub     string `json:"xpub"`
		Mnemonic string `json:"mnemonic"`
		Network  string `json:"network"`
		Active   *bool  `json:"active"`
	}
	if err := c.BodyParser(&body); err != nil {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "invalid payload"})
	}

	body.Coin = strings.ToUpper(strings.TrimSpace(body.Coin))
	if body.Coin == "" || body.Xpub == "" {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "coin and xpub are required"})
	}

	if body.Network == "" {
		body.Network = defaultNetworks[body.Coin]
		if body.Network == "" {
			body.Network = "L1"
		}
	}

	active := true
	if body.Active != nil {
		active = *body.Active
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	update := bson.M{
		"$set": bson.M{
			"coin":      body.Coin,
			"xpub":      body.Xpub,
			"network":   strings.ToUpper(body.Network),
			"active":    active,
			"updatedAt": time.Now(),
		},
		"$setOnInsert": bson.M{
			"createdAt": time.Now(),
		},
	}

	// Store mnemonic only if provided
	if body.Mnemonic != "" {
		update["$set"].(bson.M)["mnemonic"] = body.Mnemonic
	}

	result, err := h.db.Collection("crypto_master_wallets").UpdateByID(
		ctx,
		body.Coin, // _id = coin name
		update,
		options.Update().SetUpsert(true),
	)
	if err != nil {
		return httpError(c, fmt.Errorf("failed to save wallet config: %w", err))
	}

	action := "updated"
	if result.UpsertedCount > 0 {
		action = "created"
	}

	log.Printf("[crypto][config] %s master wallet config for %s (xpub=%s...)", action, body.Coin, body.Xpub[:12])
	return c.JSON(fiber.Map{
		"status": action,
		"coin":   body.Coin,
	})
}

// GetCryptoWalletConfig retrieves all stored master wallet configs.
// Mnemonics are masked for safety — only first/last 4 chars shown.
// GET /internal/crypto/wallets/config
func (h *Handler) GetCryptoWalletConfig(c *fiber.Ctx) error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	cursor, err := h.db.Collection("crypto_master_wallets").Find(ctx, bson.M{})
	if err != nil {
		return httpError(c, err)
	}
	defer cursor.Close(ctx)

	var configs []bson.M
	if err := cursor.All(ctx, &configs); err != nil {
		return httpError(c, err)
	}

	// Mask mnemonics for safety
	for _, cfg := range configs {
		if mnemonic, ok := cfg["mnemonic"].(string); ok && mnemonic != "" {
			words := strings.Fields(mnemonic)
			if len(words) > 4 {
				cfg["mnemonic"] = fmt.Sprintf("%s %s ... %s %s [%d words]",
					words[0], words[1], words[len(words)-2], words[len(words)-1], len(words))
			}
		}
	}

	return c.JSON(fiber.Map{
		"wallets": configs,
		"count":   len(configs),
	})
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

func networkFromChannel(channel string) string {
	switch channel {
	case "mtn-gh", "mtn":
		return "MTN"
	case "vodafone-gh", "vodafone", "telecel-gh", "telecel":
		return "VODAFONE"
	case "airteltigo-gh", "airteltigo", "airtel", "tigo":
		return "TIGO"
	default:
		return strings.ToUpper(strings.TrimSuffix(channel, "-gh"))
	}
}

func normalizeChannel(channel string) string {
	channel = strings.TrimSpace(strings.ToLower(channel))
	if channel == "" {
		return ""
	}
	if strings.HasSuffix(channel, "-gh") {
		return channel
	}
	if channel == "vodafone" {
		return "vodafone-gh"
	}
	if channel == "mtn" {
		return "mtn-gh"
	}
	if channel == "airteltigo" || channel == "airtel" || channel == "tigo" {
		return "airteltigo-gh"
	}
	return channel
}

func roundMoney(amount float64) float64 {
	if amount <= 0 {
		return 0
	}
	return math.Round(amount*100) / 100
}

func normalizePhone(phone string) string {
	if phone == "" {
		return ""
	}
	phone = strings.ReplaceAll(phone, " ", "")
	phone = strings.ReplaceAll(phone, "-", "")
	phone = strings.TrimSpace(phone)
	return phone
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if strings.TrimSpace(v) != "" {
			return strings.TrimSpace(v)
		}
	}
	return ""
}

// =============================================================================
// BACKGROUND: Crypto Deposit Watcher (polls blockchain explorer)
// =============================================================================

// RunCryptoDepositWatcher polls all active crypto wallet addresses for
// incoming transactions. This is the safety net alongside Tatum webhooks.
func (h *Handler) RunCryptoDepositWatcher(ctx context.Context) {
	interval := time.Duration(h.cfg.CryptoWatcherInterval) * time.Second
	if interval < 10*time.Second {
		interval = 60 * time.Second
	}
	log.Printf("[crypto-watcher] starting with interval=%v", interval)

	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			h.pollCryptoDeposits(ctx)
		}
	}
}

func (h *Handler) pollCryptoDeposits(ctx context.Context) {
	cursor, err := h.db.Collection("crypto_wallets").Find(ctx, bson.M{
		"status": "ACTIVE",
	})
	if err != nil {
		log.Printf("[crypto-watcher] query error: %v", err)
		return
	}
	defer cursor.Close(ctx)

	for cursor.Next(ctx) {
		var walletDoc bson.M
		if err := cursor.Decode(&walletDoc); err != nil {
			continue
		}

		address, _ := walletDoc["address"].(string)
		coin, _ := walletDoc["coin"].(string)
		userID := stringID(walletDoc["userId"])
		if address == "" || coin == "" || userID == "" {
			continue
		}

		txs, err := h.tatumClient.GetTransactionsByAddress(ctx, coin, address)
		if err != nil {
			log.Printf("[crypto-watcher] %s/%s tx lookup error: %v", coin, address[:8], err)
			continue
		}

		for _, tx := range txs {
			if tx.Hash == "" {
				continue
			}
			h.processCryptoTx(ctx, userID, coin, address, tx)
		}
	}
}

func (h *Handler) processCryptoTx(ctx context.Context, userID, coin, address string, tx tatum.Transaction) {
	// Parse amount from the transaction
	amountStr := tx.Amount
	if amountStr == "" {
		amountStr = tx.Value
	}
	amountCrypto, _ := strconv.ParseFloat(amountStr, 64)
	if amountCrypto <= 0 {
		return
	}

	// Determine confirmation status
	required := confirmationThreshold[coin]
	if required == 0 {
		required = 3
	}
	status := "PENDING"
	if tx.Confirmations >= required {
		status = "CONFIRMED"
	}

	update := bson.M{
		"$set": bson.M{
			"userId":        userID,
			"coin":          coin,
			"address":       address,
			"amountCrypto":  amountCrypto,
			"confirmations": tx.Confirmations,
			"status":        status,
			"updatedAt":     time.Now(),
		},
		"$setOnInsert": bson.M{
			"createdAt": time.Now(),
		},
	}

	if status == "CONFIRMED" {
		// ATOMIC: FindOneAndUpdate with status guard.
		// Only matches documents that are NOT yet CONFIRMED.
		// If another goroutine already confirmed this tx, FindOneAndUpdate
		// returns ErrNoDocuments and we skip the credit.
		res := h.db.Collection("crypto_deposits").FindOneAndUpdate(ctx,
			bson.M{
				"_id":    tx.Hash,
				"status": bson.M{"$ne": "CONFIRMED"},
			},
			update,
			options.FindOneAndUpdate().SetUpsert(true).SetReturnDocument(options.After),
		)
		var doc bson.M
		if err := res.Decode(&doc); err != nil {
			if errors.Is(err, mongo.ErrNoDocuments) {
				// Already confirmed by another poll cycle or webhook — skip
				return
			}
			log.Printf("[crypto-watcher] atomic upsert deposit %s error: %v", tx.Hash, err)
			return
		}

		// Credit the user's wallet — this branch only executes once per tx
		amountUsd := amountCrypto // In production, convert via price feed
		if err := h.walletClient.CreditDeposit(ctx, wallet.CreditRequest{
			UserID:    userID,
			AmountUsd: amountUsd,
			Source:    fmt.Sprintf("CRYPTO_%s", coin),
			Reference: tx.Hash,
		}); err != nil {
			// Roll back the status so the next poll retries
			h.db.Collection("crypto_deposits").UpdateByID(ctx, tx.Hash,
				bson.M{"$set": bson.M{"status": "PENDING", "updatedAt": time.Now()}},
			)
			log.Printf("[crypto-watcher] credit deposit %s error (rolled back): %v", tx.Hash, err)
			return
		}
		h.publishPaymentEvent(userID, fiber.Map{
			"type":         "CRYPTO_DEPOSIT_CONFIRMED",
			"amountCrypto": amountCrypto,
			"coin":         coin,
			"txHash":       tx.Hash,
		})
		log.Printf("[crypto-watcher] ✓ credited user=%s coin=%s amount=%.8f tx=%s", userID, coin, amountCrypto, tx.Hash)
	} else {
		// Still pending — just upsert the tracking record
		if _, err := h.db.Collection("crypto_deposits").UpdateByID(
			ctx, tx.Hash, update,
			options.Update().SetUpsert(true),
		); err != nil {
			log.Printf("[crypto-watcher] upsert pending deposit %s error: %v", tx.Hash, err)
		}
	}
}
