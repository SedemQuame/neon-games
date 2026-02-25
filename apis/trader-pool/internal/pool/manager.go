package pool

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"math/rand"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"

	"gamehub/trader-pool/internal/config"
	"gamehub/trader-pool/internal/wallet"
)

type Manager struct {
	rdb      *redis.Client
	wallet   *wallet.Client
	cfg      *config.Config
	accounts []*derivAccount
	simulate bool
	rng      *rand.Rand
}

type tradeOrder struct {
	SessionID  string                 `json:"sessionId"`
	UserID     string                 `json:"userId"`
	GameType   string                 `json:"gameType"`
	StakeUsd   float64                `json:"stakeUsd"`
	Prediction map[string]interface{} `json:"prediction"`
	TraceID    string                 `json:"traceId"`
}

type tradeSettlement struct {
	Outcome    string
	PayoutUsd  float64
	ContractID string
}

func NewManager(rdb *redis.Client, walletClient *wallet.Client, cfg *config.Config) *Manager {
	mgr := &Manager{
		rdb:    rdb,
		wallet: walletClient,
		cfg:    cfg,
		rng:    rand.New(rand.NewSource(time.Now().UnixNano())),
	}

	if len(cfg.DerivTokens) == 0 || cfg.DerivAppID == "" {
		log.Println("⚠️  Deriv credentials missing — trader-pool running in simulation mode")
		mgr.simulate = true
		return mgr
	}

	for idx, token := range cfg.DerivTokens {
		accountID := fmt.Sprintf("acct-%d", idx+1)
		mgr.accounts = append(mgr.accounts, newDerivAccount(accountID, token, cfg))
	}
	if len(mgr.accounts) == 0 {
		log.Println("⚠️  No Deriv accounts initialised; falling back to simulation mode")
		mgr.simulate = true
	}

	return mgr
}

func (m *Manager) Start(ctx context.Context) {
	log.Printf("Trader pool consuming queue %s", m.cfg.OrderQueue)
	for {
		select {
		case <-ctx.Done():
			return
		default:
		}
		result, err := m.rdb.BRPop(ctx, 0*time.Second, m.cfg.OrderQueue).Result()
		if err != nil {
			if ctx.Err() != nil {
				return
			}
			continue
		}
		if len(result) < 2 {
			continue
		}
		raw := result[1]
		log.Printf("Dequeued trade order: %s", raw)
		var order tradeOrder
		if err := json.Unmarshal([]byte(raw), &order); err != nil {
			log.Printf("invalid order payload: %v", err)
			continue
		}
		go m.processOrder(order)
	}
}

func (m *Manager) processOrder(order tradeOrder) {
	if order.TraceID == "" {
		order.TraceID = uuid.NewString()
	}
	if order.Prediction == nil {
		order.Prediction = map[string]interface{}{}
	}

	if m.simulate {
		m.simulateOrder(order)
		return
	}

	account := m.selectAccount()
	if account == nil {
		log.Printf("[trace=%s] no Deriv account available, issuing refund", order.TraceID)
		m.refundOrder(order, errors.New("no deriv accounts"))
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	settlement, err := account.execute(ctx, order)
	if err != nil {
		log.Printf("[trace=%s][%s] deriv execution failed: %v", order.TraceID, account.id, err)
		m.refundOrder(order, err)
		return
	}
	if err := m.finalize(order, settlement); err != nil {
		log.Printf("[trace=%s] finalize failed: %v", order.TraceID, err)
	}
}

func (m *Manager) simulateOrder(order tradeOrder) {
	delay := m.randomDelay()
	time.Sleep(delay)

	outcome := "LOSS"
	payout := 0.0
	if m.rng.Intn(100) < 45 {
		outcome = "WIN"
		payout = order.StakeUsd * 1.9
	}
	settlement := &tradeSettlement{
		Outcome:    outcome,
		PayoutUsd:  payout,
		ContractID: "SIMULATED",
	}
	if err := m.finalize(order, settlement); err != nil {
		log.Printf("[trace=%s] simulated finalize failed: %v", order.TraceID, err)
	}
}

func (m *Manager) refundOrder(order tradeOrder, cause error) {
	log.Printf("[trace=%s] refunding session=%s: %v", order.TraceID, order.SessionID, cause)
	settlement := &tradeSettlement{
		Outcome:    "REFUND",
		PayoutUsd:  order.StakeUsd,
		ContractID: "REFUND",
	}
	if err := m.finalize(order, settlement); err != nil {
		log.Printf("[trace=%s] refund finalize failed: %v", order.TraceID, err)
	}
}

func (m *Manager) finalize(order tradeOrder, settlement *tradeSettlement) error {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	bal, err := m.wallet.Settle(ctx, wallet.SettleRequest{
		UserID:    order.UserID,
		SessionID: order.SessionID,
		Outcome:   settlement.Outcome,
		StakeUsd:  order.StakeUsd,
		PayoutUsd: settlement.PayoutUsd,
		TraceID:   order.TraceID,
	})
	if err != nil {
		return fmt.Errorf("wallet settle: %w", err)
	}

	newBalance := 0.0
	if bal != nil {
		newBalance = bal.AvailableUsd
	}

	payload := map[string]interface{}{
		"sessionId":       order.SessionID,
		"userId":          order.UserID,
		"gameType":        order.GameType,
		"stakeUsd":        order.StakeUsd,
		"payoutUsd":       settlement.PayoutUsd,
		"outcome":         settlement.Outcome,
		"newBalance":      newBalance,
		"traceId":         order.TraceID,
		"derivContractId": settlement.ContractID,
	}
	message, _ := json.Marshal(payload)
	channel := fmt.Sprintf("%s:%s", m.cfg.OutcomePrefix, order.SessionID)
	if err := m.rdb.Publish(context.Background(), channel, message).Err(); err != nil {
		return fmt.Errorf("publish outcome: %w", err)
	}
	return nil
}

func (m *Manager) selectAccount() *derivAccount {
	if len(m.accounts) == 0 {
		return nil
	}
	var best *derivAccount
	for _, acc := range m.accounts {
		if best == nil || acc.inFlight() < best.inFlight() {
			best = acc
		}
	}
	return best
}

func (m *Manager) randomDelay() time.Duration {
	min := m.cfg.MinSettleMs
	max := m.cfg.MaxSettleMs
	if max <= min {
		max = min + 1000
	}
	return time.Duration(min+m.rng.Intn(max-min)) * time.Millisecond
}
