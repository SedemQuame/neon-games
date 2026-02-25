package pool

import (
	"context"
	"fmt"
	"log"
	"math"
	"strconv"
	"strings"
	"sync/atomic"
	"time"

	"github.com/ksysoev/deriv-api"
	"github.com/ksysoev/deriv-api/schema"

	"gamehub/trader-pool/internal/config"
)

type derivAccount struct {
	id     string
	token  string
	cfg    *config.Config
	active int64
}

func newDerivAccount(id, token string, cfg *config.Config) *derivAccount {
	return &derivAccount{
		id:    id,
		token: token,
		cfg:   cfg,
	}
}

func (a *derivAccount) inFlight() int64 {
	return atomic.LoadInt64(&a.active)
}

func (a *derivAccount) execute(ctx context.Context, order tradeOrder) (*tradeSettlement, error) {
	atomic.AddInt64(&a.active, 1)
	defer atomic.AddInt64(&a.active, -1)

	appID, err := strconv.Atoi(a.cfg.DerivAppID)
	if err != nil {
		return nil, fmt.Errorf("invalid DERIV_APP_ID: %w", err)
	}
	api, err := deriv.NewDerivAPI(a.cfg.DerivWSURL, appID, a.cfg.DerivLanguage, a.cfg.DerivOrigin)
	if err != nil {
		return nil, fmt.Errorf("deriv connect: %w", err)
	}
	defer api.Disconnect()

	if _, err := api.Authorize(ctx, schema.Authorize{Authorize: a.token}); err != nil {
		return nil, fmt.Errorf("deriv authorize: %w", err)
	}
	log.Printf("[trace=%s][%s] authorized with Deriv", order.TraceID, a.id)

	req, err := buildDerivProposal(order, a.cfg)
	if err != nil {
		return nil, err
	}
	duration := 0
	if req.Duration != nil {
		duration = *req.Duration
	}
	log.Printf("[trace=%s][%s] placing contract type=%s symbol=%s stake=%.2f duration=%d unit=%s",
		order.TraceID, a.id, req.ContractType, req.Symbol, order.StakeUsd, duration, req.DurationUnit)

	resp, err := api.Proposal(ctx, req)
	if err != nil {
		return nil, fmt.Errorf("deriv proposal: %w", err)
	}
	if resp.Proposal == nil {
		return nil, fmt.Errorf("deriv proposal missing payload")
	}
	log.Printf(
		"[trace=%s][%s] proposal id=%s spot=%v ask=%v payout=%v barrier=%v/%v",
		order.TraceID,
		a.id,
		resp.Proposal.Id,
		resp.Proposal.Spot,
		resp.Proposal.AskPrice,
		resp.Proposal.Payout,
		req.Barrier,
		req.Barrier2,
	)

	buyReq := schema.Buy{
		Buy:   resp.Proposal.Id,
		Price: order.StakeUsd,
	}
	_, sub, err := api.SubscribeBuy(ctx, buyReq)
	if err != nil {
		return nil, fmt.Errorf("deriv buy: %w", err)
	}
	defer sub.Forget()
	log.Printf("[trace=%s][%s] buy subscribed id=%s price=%.2f", order.TraceID, a.id, resp.Proposal.Id, order.StakeUsd)

	timeout := time.NewTimer(2 * time.Minute)
	defer timeout.Stop()

	contractID := ""
	for {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-timeout.C:
			return nil, fmt.Errorf("deriv settlement timeout")
		case msg, ok := <-sub.Stream:
			if !ok {
				return nil, fmt.Errorf("deriv stream closed")
			}
			oc := msg.ProposalOpenContract
			if oc == nil {
				continue
			}
			if oc.ContractId != nil {
				contractID = strconv.Itoa(*oc.ContractId)
			}
			if oc.IsSold == nil || *oc.IsSold != 1 {
				log.Printf(
					"[trace=%s][%s] contract update id=%s entry_price=%v profit=%v isSold=%v",
					order.TraceID,
					a.id,
					contractID,
					oc.EntrySpot,
					oc.Profit,
					oc.IsSold,
				)
				continue
			}
			profit := 0.0
			if oc.Profit != nil {
				profit = *oc.Profit
			}
			sellPrice := 0.0
			if oc.SellPrice != nil {
				sellPrice = *oc.SellPrice
			}

			outcome := "LOSS"
			payout := 0.0
			if profit > 0 || sellPrice > order.StakeUsd {
				outcome = "WIN"
				if sellPrice > 0 {
					payout = sellPrice
				} else {
					payout = order.StakeUsd + profit
				}
			} else if profit >= -0.00001 {
				outcome = "REFUND"
				payout = order.StakeUsd
			}
			log.Printf("[trace=%s][%s] contract=%s outcome=%s profit=%.2f payout=%.2f", order.TraceID, a.id, contractID, outcome, profit, payout)
			return &tradeSettlement{
				Outcome:    outcome,
				PayoutUsd:  payout,
				ContractID: contractID,
			}, nil
		}
	}
}

func buildDerivProposal(order tradeOrder, cfg *config.Config) (schema.Proposal, error) {
	pred := order.Prediction
	if pred == nil {
		pred = map[string]interface{}{}
	}

	contractType := strings.ToUpper(readString(pred, "derivContractType"))
	if contractType == "" {
		contractType = defaultContractType(order)
	}
	if contractType == "" {
		return schema.Proposal{}, fmt.Errorf("missing derivContractType in prediction")
	}

	amount := order.StakeUsd
	if amount <= 0 {
		return schema.Proposal{}, fmt.Errorf("invalid stake amount %.2f", amount)
	}

	basis := schema.ProposalBasisStake
	if strings.EqualFold(readString(pred, "basis"), "payout") {
		basis = schema.ProposalBasisPayout
	}

	symbol := readString(pred, "symbol")
	if symbol == "" {
		symbol = cfg.DerivSymbol
	}

	req := schema.Proposal{
		Proposal:     1,
		Amount:       &amount,
		Basis:        &basis,
		ContractType: schema.ProposalContractType(contractType),
		Currency:     strings.ToUpper(readString(pred, "currency")),
		Symbol:       symbol,
		Passthrough: schema.ProposalPassthrough{
			"sessionId": order.SessionID,
			"userId":    order.UserID,
		},
	}
	if req.Currency == "" {
		req.Currency = "USD"
	}

	assignDurationFromPrediction(pred, &req)
	normalizeDuration(&req)

	if barrier := readString(pred, "barrier"); barrier != "" {
		req.Barrier = &barrier
	}
	if v, ok := readFloat(pred, "barrierHigh"); ok {
		formatted := formatBarrier(v)
		req.Barrier = &formatted
	}
	if v, ok := readFloat(pred, "barrierLow"); ok {
		formatted := formatBarrier(v)
		req.Barrier2 = &formatted
	}

	if v, ok := readFloat(pred, "multiplier"); ok {
		req.Multiplier = floatPtr(v)
	}
	if v, ok := readFloat(pred, "takeProfit"); ok {
		if req.LimitOrder == nil {
			req.LimitOrder = &schema.ProposalLimitOrder{}
		}
		req.LimitOrder.TakeProfit = floatPtr(v)
	}
	if v, ok := readFloat(pred, "stopLoss"); ok {
		if req.LimitOrder == nil {
			req.LimitOrder = &schema.ProposalLimitOrder{}
		}
		req.LimitOrder.StopLoss = floatPtr(v)
	}

	return req, nil
}

func defaultContractType(order tradeOrder) string {
	dir := strings.ToUpper(readString(order.Prediction, "direction"))
	switch order.GameType {
	case "NEON_PERIMETER":
		if dir == "OUT" {
			return "EXPIRYMISS"
		}
		return "EXPIRYRANGE"
	case "DIGIT_DASH":
		return "DIGITDIFF"
	case "DUAL_DIMENSION_FLIP":
		if dir == "PUT" {
			return "PUT"
		}
		return "CALL"
	case "ZERO_HOUR_SNIPER":
		if dir == "LOW" {
			return "TICKLOW"
		}
		return "TICKHIGH"
	case "VELOCITY_VECTOR":
		if dir == "DOWN" {
			return "MULTDOWN"
		}
		return "MULTUP"
	default:
		if dir == "PUT" {
			return "PUT"
		}
		return "CALL"
	}
}

func floatPtr(v float64) *float64 {
	return &v
}

func intPtr(v int) *int {
	return &v
}

func formatBarrier(val float64) string {
	return fmt.Sprintf("%+.5f", val)
}

func readString(m map[string]interface{}, key string) string {
	if m == nil {
		return ""
	}
	if val, ok := m[key]; ok {
		switch t := val.(type) {
		case string:
			return t
		case fmt.Stringer:
			return t.String()
		case float64:
			return fmt.Sprintf("%v", t)
		case int:
			return strconv.Itoa(t)
		case bool:
			return strconv.FormatBool(t)
		}
	}
	return ""
}

func readFloat(m map[string]interface{}, key string) (float64, bool) {
	if m == nil {
		return 0, false
	}
	val, ok := m[key]
	if !ok {
		return 0, false
	}
	switch v := val.(type) {
	case float64:
		return v, true
	case float32:
		return float64(v), true
	case int:
		return float64(v), true
	case int64:
		return float64(v), true
	case string:
		f, err := strconv.ParseFloat(v, 64)
		return f, err == nil
	default:
		return 0, false
	}
}

func readInt(m map[string]interface{}, key string) (int, bool) {
	if m == nil {
		return 0, false
	}
	val, ok := m[key]
	if !ok {
		return 0, false
	}
	switch v := val.(type) {
	case float64:
		return int(math.Round(v)), true
	case float32:
		return int(math.Round(float64(v))), true
	case int:
		return v, true
	case int64:
		return int(v), true
	case string:
		i, err := strconv.Atoi(v)
		return i, err == nil
	default:
		return 0, false
	}
}

func durationUnitFromPrediction(raw string) schema.ProposalDurationUnit {
	switch strings.ToLower(raw) {
	case "m":
		return schema.ProposalDurationUnitM
	case "h":
		return schema.ProposalDurationUnitH
	case "d":
		return schema.ProposalDurationUnitD
	case "t":
		return schema.ProposalDurationUnitT
	default:
		return schema.ProposalDurationUnitS
	}
}

func assignDurationFromPrediction(prediction map[string]interface{}, req *schema.Proposal) {
	if ticks, ok := readInt(prediction, "durationTicks"); ok && ticks > 0 {
		req.Duration = intPtr(ticks)
		req.DurationUnit = schema.ProposalDurationUnitT
		return
	}
	if minutes, ok := readInt(prediction, "durationMinutes"); ok && minutes > 0 {
		req.Duration = intPtr(minutes)
		req.DurationUnit = schema.ProposalDurationUnitM
		return
	}
	if dur, ok := readInt(prediction, "duration"); ok && dur > 0 {
		req.Duration = intPtr(dur)
		req.DurationUnit = durationUnitFromPrediction(readString(prediction, "durationUnit"))
		return
	}
	if seconds, ok := readInt(prediction, "durationSeconds"); ok && seconds > 0 {
		req.Duration = intPtr(seconds)
		req.DurationUnit = schema.ProposalDurationUnitS
	}
}

func normalizeDuration(req *schema.Proposal) {
	ct := strings.ToUpper(string(req.ContractType))
	switch ct {
	case "MULTUP", "MULTDOWN":
		req.Duration = nil
		req.DurationUnit = ""
	case "TICKHIGH", "TICKLOW":
		req.Duration = intPtr(5)
		req.DurationUnit = schema.ProposalDurationUnitT
	case "CALL", "PUT", "CALLE", "PUTE":
		ticks := 5
		if req.Duration != nil && req.DurationUnit == schema.ProposalDurationUnitT {
			ticks = clampInt(*req.Duration, 1, 10)
		}
		req.Duration = intPtr(ticks)
		req.DurationUnit = schema.ProposalDurationUnitT
	case "ONETOUCH", "NOTOUCH":
		ticks := 5
		if req.Duration != nil && req.DurationUnit == schema.ProposalDurationUnitT {
			ticks = clampInt(*req.Duration, 5, 10)
		}
		req.Duration = intPtr(ticks)
		req.DurationUnit = schema.ProposalDurationUnitT
	case "EXPIRYRANGE", "EXPIRYMISS", "RANGE", "UPORDOWN":
		minutes := 2
		if req.Duration != nil {
			if m := durationToMinutes(*req.Duration, req.DurationUnit); m > 0 {
				minutes = m
			}
		}
		minutes = clampInt(minutes, 3, 60)
		req.Duration = intPtr(minutes)
		req.DurationUnit = schema.ProposalDurationUnitM
	case "DIGITMATCH", "DIGITDIFF", "DIGITODD", "DIGITEVEN", "DIGITOVER", "DIGITUNDER":
		ticks := 1
		if req.Duration != nil && req.DurationUnit == schema.ProposalDurationUnitT {
			ticks = clampInt(*req.Duration, 1, 10)
		}
		req.Duration = intPtr(ticks)
		req.DurationUnit = schema.ProposalDurationUnitT
	default:
		if req.Duration == nil {
			defaultDur := 60
			req.Duration = &defaultDur
			req.DurationUnit = schema.ProposalDurationUnitS
		}
	}
}

func durationToMinutes(value int, unit schema.ProposalDurationUnit) int {
	switch unit {
	case schema.ProposalDurationUnitM:
		return value
	case schema.ProposalDurationUnitS:
		return int(math.Ceil(float64(value) / 60.0))
	case schema.ProposalDurationUnitH:
		return value * 60
	case schema.ProposalDurationUnitD:
		return value * 24 * 60
	default:
		return 0
	}
}

func clampInt(val, min, max int) int {
	if val < min {
		return min
	}
	if val > max {
		return max
	}
	return val
}
