package pool

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"math/rand"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"

	"gamehub/trader-pool/internal/config"
	"gamehub/trader-pool/internal/wallet"
)

type Manager struct {
	rdb             *redis.Client
	wallet          *wallet.Client
	cfg             *config.Config
	accounts        []*derivAccount
	simulate        bool
	rng             *rand.Rand
	bounceTracker   *BounceTracker
	activeMu        sync.Mutex
	activeTrades    map[string]*activeTrade
	pendingCashouts map[string]cashoutRequest
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

type cashoutRequest struct {
	SessionID  string  `json:"sessionId"`
	UserID     string  `json:"userId"`
	GameType   string  `json:"gameType"`
	TraceID    string  `json:"traceId"`
	Multiplier float64 `json:"multiplier"`
	CreatedAt  int64   `json:"createdAt"`
}

type activeTrade struct {
	order     tradeOrder
	cashoutCh chan cashoutRequest
}

func NewManager(rdb *redis.Client, walletClient *wallet.Client, cfg *config.Config) *Manager {
	rng := rand.New(rand.NewSource(time.Now().UnixNano()))
	mgr := &Manager{
		rdb:             rdb,
		wallet:          walletClient,
		cfg:             cfg,
		rng:             rng,
		bounceTracker:   newBounceTracker(cfg, rng),
		activeTrades:    make(map[string]*activeTrade),
		pendingCashouts: make(map[string]cashoutRequest),
	}

	if cfg.BounceRate > 0 {
		log.Printf("🎲 Bounce system active: rate=%.0f%% profit_target=$%.2f",
			cfg.BounceRate*100, cfg.ProfitTargetUsd)
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
	go m.startCashoutConsumer(ctx)
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

	// --- Bounce check: intercept before hitting Deriv ---
	if m.bounceTracker.ShouldBounce() {
		log.Printf("[trace=%s] 🎲 bounced (stake=%.2f)", order.TraceID, order.StakeUsd)
		m.bouncedSettle(order)
		return
	}

	if m.simulate {
		active := m.registerActive(order)
		defer m.unregisterActive(order.SessionID)
		m.simulateOrder(order, active)
		return
	}

	account := m.selectAccount()
	if account == nil {
		log.Printf("[trace=%s] no Deriv account available, issuing refund", order.TraceID)
		m.refundOrder(order, errors.New("no deriv accounts"))
		return
	}

	active := m.registerActive(order)
	defer m.unregisterActive(order.SessionID)

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	settlement, err := account.execute(ctx, order, active)
	if err != nil {
		log.Printf("[trace=%s][%s] deriv execution failed: %v", order.TraceID, account.id, err)
		m.refundOrder(order, err)
		return
	}
	if err := m.finalize(order, settlement); err != nil {
		log.Printf("[trace=%s] finalize failed: %v", order.TraceID, err)
	}
}

func (m *Manager) simulateOrder(order tradeOrder, active *activeTrade) {
	delay := m.randomDelay()
	timer := time.NewTimer(delay)
	defer timer.Stop()

	select {
	case req := <-active.cashoutCh:
		multiplier := req.Multiplier
		if multiplier < 1.01 {
			multiplier = 1.01
		}
		if multiplier > m.cfg.PayoutMultiplier {
			multiplier = m.cfg.PayoutMultiplier
		}
		settlement := &tradeSettlement{
			Outcome:    "WIN",
			PayoutUsd:  order.StakeUsd * multiplier,
			ContractID: "SIMULATED_CASHOUT",
		}
		if err := m.finalize(order, settlement); err != nil {
			log.Printf("[trace=%s] simulated cashout finalize failed: %v", order.TraceID, err)
		}
		return
	case <-timer.C:
	}

	outcome := "LOSS"
	payout := 0.0
	if m.rng.Intn(100) < 45 {
		outcome = "WIN"
		payout = order.StakeUsd * m.cfg.PayoutMultiplier
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

func (m *Manager) startCashoutConsumer(ctx context.Context) {
	queue := m.cashoutQueue()
	log.Printf("Trader pool consuming cashout queue %s", queue)
	for {
		select {
		case <-ctx.Done():
			return
		default:
		}
		result, err := m.rdb.BRPop(ctx, 0*time.Second, queue).Result()
		if err != nil {
			if ctx.Err() != nil {
				return
			}
			continue
		}
		if len(result) < 2 {
			continue
		}
		var req cashoutRequest
		if err := json.Unmarshal([]byte(result[1]), &req); err != nil {
			log.Printf("invalid cashout payload: %v", err)
			continue
		}
		m.requestCashout(req)
	}
}

func (m *Manager) cashoutQueue() string {
	return m.cfg.OrderQueue + ":cashout"
}

func (m *Manager) registerActive(order tradeOrder) *activeTrade {
	active := &activeTrade{
		order:     order,
		cashoutCh: make(chan cashoutRequest, 1),
	}
	m.activeMu.Lock()
	m.activeTrades[order.SessionID] = active
	pending, hasPending := m.pendingCashouts[order.SessionID]
	if hasPending {
		delete(m.pendingCashouts, order.SessionID)
	}
	m.activeMu.Unlock()
	if hasPending {
		select {
		case active.cashoutCh <- pending:
			log.Printf("[trace=%s] applied pending cashout session=%s multiplier=%.2f",
				pending.TraceID, pending.SessionID, pending.Multiplier)
		default:
		}
	}
	return active
}

func (m *Manager) unregisterActive(sessionID string) {
	m.activeMu.Lock()
	delete(m.activeTrades, sessionID)
	m.activeMu.Unlock()
}

func (m *Manager) requestCashout(req cashoutRequest) {
	m.activeMu.Lock()
	active := m.activeTrades[req.SessionID]
	if active == nil {
		m.pendingCashouts[req.SessionID] = req
	}
	m.activeMu.Unlock()
	if active == nil {
		log.Printf("[trace=%s] cashout queued until session is active: %s", req.TraceID, req.SessionID)
		go m.expirePendingCashout(req)
		return
	}
	select {
	case active.cashoutCh <- req:
		log.Printf("[trace=%s] cashout requested session=%s multiplier=%.2f",
			req.TraceID, req.SessionID, req.Multiplier)
	default:
		log.Printf("[trace=%s] duplicate cashout ignored session=%s", req.TraceID, req.SessionID)
	}
}

func (m *Manager) expirePendingCashout(req cashoutRequest) {
	time.Sleep(2 * time.Minute)
	m.activeMu.Lock()
	defer m.activeMu.Unlock()
	pending, ok := m.pendingCashouts[req.SessionID]
	if ok && pending.TraceID == req.TraceID && pending.CreatedAt == req.CreatedAt {
		delete(m.pendingCashouts, req.SessionID)
	}
}

// bouncedSettle intercepts the order without contacting Deriv.
// It sleeps a realistic delay, then settles as a forced LOSS (payout=0).
// The stake is recorded in bounceTracker as house profit.
// From the user's perspective this is identical to a real losing trade.
func (m *Manager) bouncedSettle(order tradeOrder) {
	time.Sleep(m.randomDelay())

	m.bounceTracker.RecordBounce(order.StakeUsd)

	settlement := &tradeSettlement{
		Outcome:    "LOSS",
		PayoutUsd:  0.0,
		ContractID: "BOUNCED", // internal label; not shown to user
	}
	if err := m.finalize(order, settlement); err != nil {
		log.Printf("[trace=%s] bounced finalize failed: %v", order.TraceID, err)
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

	// Apply win rake: deduct a % of net profit before crediting the user.
	// This runs on every WIN regardless of whether the bet was settled by
	// Deriv, simulated, or any future provider.
	rakeAmount := 0.0
	if strings.EqualFold(settlement.Outcome, "WIN") && m.cfg.WinRakeRate > 0 {
		profit := settlement.PayoutUsd - order.StakeUsd
		if profit > 0 {
			rakeAmount = profit * m.cfg.WinRakeRate
			settlement.PayoutUsd -= rakeAmount
			log.Printf("[rake][trace=%s] gross=%.4f rake=%.4f(%.0f%%) net=%.4f",
				order.TraceID, settlement.PayoutUsd+rakeAmount, rakeAmount,
				m.cfg.WinRakeRate*100, settlement.PayoutUsd)
		}
	}

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

	winAmount := 0.0
	if strings.EqualFold(settlement.Outcome, "WIN") {
		winAmount = settlement.PayoutUsd - order.StakeUsd
		if winAmount < 0 {
			winAmount = 0
		}
	}

	payload := map[string]interface{}{
		"sessionId":       order.SessionID,
		"userId":          order.UserID,
		"gameType":        order.GameType,
		"stakeUsd":        order.StakeUsd,
		"payoutUsd":       settlement.PayoutUsd,
		"winAmountUsd":    winAmount,
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
