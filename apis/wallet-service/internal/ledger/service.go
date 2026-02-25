package ledger

import (
	"context"
	"errors"
	"fmt"
	"log"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

var (
	// ErrInsufficientFunds indicates there are not enough available funds for the requested action.
	ErrInsufficientFunds = errors.New("insufficient balance")
	// ErrReservationNotFound indicates the referenced withdrawal/bet reservation does not exist.
	ErrReservationNotFound = errors.New("reservation not found")
)

type Service struct {
	client      *mongo.Client
	balances    *mongo.Collection
	entries     *mongo.Collection
	withdrawals *mongo.Collection
	bets        *mongo.Collection
	rdb         *redis.Client
}

func NewService(db *mongo.Database, rdb *redis.Client) *Service {
	return &Service{
		client:      db.Client(),
		balances:    db.Collection("wallet_balances"),
		entries:     db.Collection("ledger_entries"),
		withdrawals: db.Collection("withdrawals"),
		bets:        db.Collection("bet_reservations"),
		rdb:         rdb,
	}
}

type Balance struct {
	UserID        string    `json:"userId"`
	AvailableUsd  float64   `json:"availableUsd"`
	ReservedUsd   float64   `json:"reservedUsd"`
	LastUpdatedAt time.Time `json:"updatedAt"`
}

type LedgerEntry struct {
	ID               primitive.ObjectID `bson:"_id,omitempty" json:"id"`
	UserID           string             `bson:"userId" json:"userId"`
	Type             string             `bson:"type" json:"type"`
	AmountUsd        float64            `bson:"amountUsd" json:"amountUsd"`
	Reference        string             `bson:"reference,omitempty" json:"reference,omitempty"`
	Metadata         bson.M             `bson:"metadata,omitempty" json:"metadata,omitempty"`
	BalanceAvailable float64            `bson:"balanceAvailableUsd" json:"balanceAvailableUsd"`
	BalanceReserved  float64            `bson:"balanceReservedUsd" json:"balanceReservedUsd"`
	CreatedAt        time.Time          `bson:"createdAt" json:"createdAt"`
}

type WithdrawalRecord struct {
	ID        string    `bson:"_id" json:"withdrawalId"`
	UserID    string    `bson:"userId" json:"userId"`
	AmountUsd float64   `bson:"amountUsd" json:"amountUsd"`
	Status    string    `bson:"status" json:"status"`
	CreatedAt time.Time `bson:"createdAt" json:"createdAt"`
	UpdatedAt time.Time `bson:"updatedAt" json:"updatedAt"`
}

type CreditRequest struct {
	UserID    string
	AmountUsd float64
	Source    string
	Reference string
	Metadata  bson.M
}

type WithdrawalReserveRequest struct {
	UserID       string
	WithdrawalID string
	AmountUsd    float64
	Metadata     bson.M
}

type WithdrawalReleaseRequest struct {
	UserID       string
	WithdrawalID string
	Success      bool
}

type BetReserveRequest struct {
	UserID    string
	SessionID string
	AmountUsd float64
	Metadata  bson.M
	TraceID   string
}

type GameSettlementRequest struct {
	UserID    string
	SessionID string
	Outcome   string
	StakeUsd  float64
	PayoutUsd float64
	TraceID   string
}

func (s *Service) GetBalance(ctx context.Context, userID string) (*Balance, error) {
	var doc balanceDoc
	err := s.balances.FindOne(ctx, bson.M{"userId": userID}).Decode(&doc)
	if err == mongo.ErrNoDocuments {
		return &Balance{UserID: userID}, nil
	}
	if err != nil {
		return nil, err
	}
	return doc.toBalance(), nil
}

func (s *Service) ListLedger(ctx context.Context, userID string, limit, offset int64) ([]LedgerEntry, error) {
	opts := options.Find().SetSort(bson.D{{Key: "createdAt", Value: -1}}).SetLimit(limit).SetSkip(offset)
	cursor, err := s.entries.Find(ctx, bson.M{"userId": userID}, opts)
	if err != nil {
		return nil, err
	}
	defer cursor.Close(ctx)
	var entries []LedgerEntry
	for cursor.Next(ctx) {
		var entry LedgerEntry
		if err := cursor.Decode(&entry); err != nil {
			return nil, err
		}
		entries = append(entries, entry)
	}
	return entries, cursor.Err()
}

func (s *Service) ListWithdrawals(ctx context.Context, userID string, limit int64) ([]WithdrawalRecord, error) {
	opts := options.Find().SetSort(bson.D{{Key: "createdAt", Value: -1}}).SetLimit(limit)
	cursor, err := s.withdrawals.Find(ctx, bson.M{"userId": userID}, opts)
	if err != nil {
		return nil, err
	}
	defer cursor.Close(ctx)
	var out []WithdrawalRecord
	for cursor.Next(ctx) {
		var rec WithdrawalRecord
		if err := cursor.Decode(&rec); err != nil {
			return nil, err
		}
		out = append(out, rec)
	}
	return out, cursor.Err()
}

func (s *Service) CreditDeposit(ctx context.Context, req CreditRequest) (*Balance, error) {
	var result *Balance
	err := s.executeTx(ctx, func(tx mongo.SessionContext) error {
		if req.Reference != "" {
			count, err := s.entries.CountDocuments(tx, bson.M{"reference": req.Reference})
			if err != nil {
				return err
			}
			if count > 0 {
				bal, err := s.GetBalance(tx, req.UserID)
				result = bal
				return err
			}
		}
		bal, err := s.incrementAvailable(tx, req.UserID, req.AmountUsd)
		if err != nil {
			return err
		}
		entry := LedgerEntry{
			UserID:           req.UserID,
			Type:             "DEPOSIT_CONFIRMED",
			AmountUsd:        req.AmountUsd,
			Reference:        req.Reference,
			Metadata:         req.Metadata,
			BalanceAvailable: bal.AvailableUsd,
			BalanceReserved:  bal.ReservedUsd,
			CreatedAt:        time.Now(),
		}
		if _, err := s.entries.InsertOne(tx, entry); err != nil {
			return err
		}
		result = bal
		return nil
	})
	return result, err
}

func (s *Service) ReserveWithdrawal(ctx context.Context, req WithdrawalReserveRequest) (*Balance, error) {
	var result *Balance
	err := s.executeTx(ctx, func(tx mongo.SessionContext) error {
		var existing WithdrawalRecord
		err := s.withdrawals.FindOne(tx, bson.M{"_id": req.WithdrawalID}).Decode(&existing)
		if err == nil {
			bal, err := s.GetBalance(tx, req.UserID)
			result = bal
			return err
		}
		if err != mongo.ErrNoDocuments {
			return err
		}

		bal, err := s.moveAvailableToReserved(tx, req.UserID, req.AmountUsd)
		if err != nil {
			return err
		}

		doc := WithdrawalRecord{
			ID:        req.WithdrawalID,
			UserID:    req.UserID,
			AmountUsd: req.AmountUsd,
			Status:    "HELD",
			CreatedAt: time.Now(),
			UpdatedAt: time.Now(),
		}
		if _, err := s.withdrawals.InsertOne(tx, doc); err != nil {
			return err
		}

		entry := LedgerEntry{
			UserID:           req.UserID,
			Type:             "WITHDRAWAL_RESERVED",
			AmountUsd:        -req.AmountUsd,
			Reference:        req.WithdrawalID,
			Metadata:         req.Metadata,
			BalanceAvailable: bal.AvailableUsd,
			BalanceReserved:  bal.ReservedUsd,
			CreatedAt:        time.Now(),
		}
		if _, err := s.entries.InsertOne(tx, entry); err != nil {
			return err
		}
		result = bal
		return nil
	})
	if errors.Is(err, ErrInsufficientFunds) {
		return nil, err
	}
	return result, err
}

func (s *Service) ReleaseWithdrawal(ctx context.Context, req WithdrawalReleaseRequest) (*Balance, error) {
	var result *Balance
	err := s.executeTx(ctx, func(tx mongo.SessionContext) error {
		var doc WithdrawalRecord
		if err := s.withdrawals.FindOne(tx, bson.M{"_id": req.WithdrawalID}).Decode(&doc); err != nil {
			if err == mongo.ErrNoDocuments {
				return ErrReservationNotFound
			}
			return err
		}
		if doc.Status == "COMPLETED" || doc.Status == "FAILED" {
			bal, err := s.GetBalance(tx, req.UserID)
			result = bal
			return err
		}

		var bal *Balance
		var err error
		if req.Success {
			bal, err = s.burnReserved(tx, req.UserID, doc.AmountUsd)
			doc.Status = "COMPLETED"
		} else {
			bal, err = s.moveReservedToAvailable(tx, req.UserID, doc.AmountUsd)
			doc.Status = "FAILED"
		}
		if err != nil {
			return err
		}

		doc.UpdatedAt = time.Now()
		if _, err := s.withdrawals.UpdateByID(tx, doc.ID, bson.M{"$set": bson.M{"status": doc.Status, "updatedAt": doc.UpdatedAt}}); err != nil {
			return err
		}

		entryType := "WITHDRAWAL_RELEASED"
		amount := doc.AmountUsd
		if req.Success {
			entryType = "WITHDRAWAL_CONFIRMED"
			amount = -doc.AmountUsd
		}

		entry := LedgerEntry{
			UserID:           req.UserID,
			Type:             entryType,
			AmountUsd:        amount,
			Reference:        req.WithdrawalID,
			BalanceAvailable: bal.AvailableUsd,
			BalanceReserved:  bal.ReservedUsd,
			CreatedAt:        time.Now(),
		}
		if _, err := s.entries.InsertOne(tx, entry); err != nil {
			return err
		}

		result = bal
		return nil
	})
	return result, err
}

func (s *Service) ReserveBet(ctx context.Context, req BetReserveRequest) (*Balance, error) {
	var result *Balance
	err := s.executeTx(ctx, func(tx mongo.SessionContext) error {
		var existing bson.M
		if err := s.bets.FindOne(tx, bson.M{"_id": req.SessionID}).Decode(&existing); err == nil {
			bal, err := s.GetBalance(tx, req.UserID)
			result = bal
			return err
		} else if err != mongo.ErrNoDocuments {
			return err
		}

		bal, err := s.moveAvailableToReserved(tx, req.UserID, req.AmountUsd)
		if err != nil {
			return err
		}

		betDoc := bson.M{
			"_id":       req.SessionID,
			"userId":    req.UserID,
			"amountUsd": req.AmountUsd,
			"status":    "HELD",
			"createdAt": time.Now(),
			"updatedAt": time.Now(),
		}
		if req.TraceID != "" {
			betDoc["traceId"] = req.TraceID
		}
		if _, err := s.bets.InsertOne(tx, betDoc); err != nil {
			return err
		}

		metadata := metadataWithTrace(req.Metadata, req.TraceID)
		entry := LedgerEntry{
			UserID:           req.UserID,
			Type:             "BET_RESERVED",
			AmountUsd:        -req.AmountUsd,
			Reference:        fmt.Sprintf("%s:reserve", req.SessionID),
			Metadata:         metadata,
			BalanceAvailable: bal.AvailableUsd,
			BalanceReserved:  bal.ReservedUsd,
			CreatedAt:        time.Now(),
		}
		if _, err := s.entries.InsertOne(tx, entry); err != nil {
			return err
		}

		result = bal
		return nil
	})
	if errors.Is(err, ErrInsufficientFunds) {
		return nil, err
	}
	return result, err
}

func (s *Service) SettleGame(ctx context.Context, req GameSettlementRequest) (*Balance, error) {
	var result *Balance
	err := s.executeTx(ctx, func(tx mongo.SessionContext) error {
		var betDoc bson.M
		if err := s.bets.FindOne(tx, bson.M{"_id": req.SessionID}).Decode(&betDoc); err != nil {
			if err == mongo.ErrNoDocuments {
				return ErrReservationNotFound
			}
			return err
		}
		if betDoc["status"] == "SETTLED" {
			bal, err := s.GetBalance(tx, req.UserID)
			result = bal
			return err
		}

		stake := req.StakeUsd
		if val, ok := betDoc["amountUsd"].(float64); ok && val > 0 {
			stake = val
		}
		if stake <= 0 {
			return ErrReservationNotFound
		}

		outcome := strings.ToUpper(req.Outcome)
		var bal *Balance
		var err error

		switch outcome {
		case "REFUND":
			bal, err = s.moveReservedToAvailable(tx, req.UserID, stake)
		default:
			bal, err = s.burnReserved(tx, req.UserID, stake)
			if err != nil {
				return err
			}
			if outcome == "WIN" && req.PayoutUsd > 0 {
				bal, err = s.incrementAvailable(tx, req.UserID, req.PayoutUsd)
				if err != nil {
					return err
				}
				s.enqueueLeaderboardUpdate(req.UserID, req.PayoutUsd-stake)
			}
		}
		if err != nil {
			return err
		}

		update := bson.M{
			"status":    "SETTLED",
			"result":    outcome,
			"updatedAt": time.Now(),
		}
		if _, err := s.bets.UpdateByID(tx, req.SessionID, bson.M{"$set": update}); err != nil {
			return err
		}

		metadata := metadataWithTrace(bson.M{
			"outcome":   outcome,
			"stakeUsd":  stake,
			"payoutUsd": req.PayoutUsd,
		}, req.TraceID)
		entry := LedgerEntry{
			UserID:           req.UserID,
			Type:             "GAME_RESULT",
			AmountUsd:        req.PayoutUsd - stake,
			Reference:        fmt.Sprintf("%s:settle", req.SessionID),
			Metadata:         metadata,
			BalanceAvailable: bal.AvailableUsd,
			BalanceReserved:  bal.ReservedUsd,
			CreatedAt:        time.Now(),
		}
		if _, err := s.entries.InsertOne(tx, entry); err != nil {
			return err
		}

		result = bal
		return nil
	})
	return result, err
}

func (s *Service) executeTx(ctx context.Context, fn func(mongo.SessionContext) error) error {
	session, err := s.client.StartSession()
	if err != nil {
		return err
	}
	defer session.EndSession(ctx)
	return mongo.WithSession(ctx, session, func(sc mongo.SessionContext) error {
		if err := sc.StartTransaction(); err != nil {
			return err
		}
		if err := fn(sc); err != nil {
			_ = sc.AbortTransaction(sc)
			return err
		}
		return sc.CommitTransaction(sc)
	})
}

func (s *Service) incrementAvailable(ctx context.Context, userID string, amount float64) (*Balance, error) {
	now := time.Now()
	filter := bson.M{"userId": userID}
	update := bson.M{
		"$inc": bson.M{"availableUsd": amount},
		"$setOnInsert": bson.M{
			"userId":      userID,
			"reservedUsd": 0,
			"createdAt":   now,
		},
		"$set": bson.M{"updatedAt": now},
	}
	opts := options.FindOneAndUpdate().SetUpsert(true).SetReturnDocument(options.After)
	var doc balanceDoc
	if err := s.balances.FindOneAndUpdate(ctx, filter, update, opts).Decode(&doc); err != nil {
		return nil, err
	}
	return doc.toBalance(), nil
}

func (s *Service) moveAvailableToReserved(ctx context.Context, userID string, amount float64) (*Balance, error) {
	now := time.Now()
	filter := bson.M{
		"userId":       userID,
		"availableUsd": bson.M{"$gte": amount},
	}
	update := bson.M{
		"$inc": bson.M{"availableUsd": -amount, "reservedUsd": amount},
		"$set": bson.M{"updatedAt": now},
	}
	opts := options.FindOneAndUpdate().SetReturnDocument(options.After)
	var doc balanceDoc
	err := s.balances.FindOneAndUpdate(ctx, filter, update, opts).Decode(&doc)
	if err == mongo.ErrNoDocuments {
		return nil, ErrInsufficientFunds
	}
	return doc.toBalance(), err
}

func (s *Service) moveReservedToAvailable(ctx context.Context, userID string, amount float64) (*Balance, error) {
	now := time.Now()
	filter := bson.M{
		"userId":      userID,
		"reservedUsd": bson.M{"$gte": amount},
	}
	update := bson.M{
		"$inc": bson.M{"availableUsd": amount, "reservedUsd": -amount},
		"$set": bson.M{"updatedAt": now},
	}
	opts := options.FindOneAndUpdate().SetReturnDocument(options.After)
	var doc balanceDoc
	err := s.balances.FindOneAndUpdate(ctx, filter, update, opts).Decode(&doc)
	if err == mongo.ErrNoDocuments {
		return nil, ErrReservationNotFound
	}
	return doc.toBalance(), err
}

func (s *Service) burnReserved(ctx context.Context, userID string, amount float64) (*Balance, error) {
	now := time.Now()
	filter := bson.M{
		"userId":      userID,
		"reservedUsd": bson.M{"$gte": amount},
	}
	update := bson.M{
		"$inc": bson.M{"reservedUsd": -amount},
		"$set": bson.M{"updatedAt": now},
	}
	opts := options.FindOneAndUpdate().SetReturnDocument(options.After)
	var doc balanceDoc
	err := s.balances.FindOneAndUpdate(ctx, filter, update, opts).Decode(&doc)
	if err == mongo.ErrNoDocuments {
		return nil, ErrReservationNotFound
	}
	return doc.toBalance(), err
}

func (s *Service) enqueueLeaderboardUpdate(userID string, delta float64) {
	if s.rdb == nil || delta <= 0 {
		return
	}
	if err := s.rdb.ZIncrBy(context.Background(), "leaderboard:global", delta, userID).Err(); err != nil {
		log.Printf("leaderboard update failed: %v", err)
	}
}

func metadataWithTrace(base bson.M, traceID string) bson.M {
	if base == nil {
		base = bson.M{}
	}
	if traceID != "" {
		base["traceId"] = traceID
	}
	return base
}

type balanceDoc struct {
	UserID    string    `bson:"userId"`
	Available float64   `bson:"availableUsd"`
	Reserved  float64   `bson:"reservedUsd"`
	CreatedAt time.Time `bson:"createdAt"`
	UpdatedAt time.Time `bson:"updatedAt"`
}

func (b balanceDoc) toBalance() *Balance {
	return &Balance{
		UserID:        b.UserID,
		AvailableUsd:  b.Available,
		ReservedUsd:   b.Reserved,
		LastUpdatedAt: b.UpdatedAt,
	}
}
