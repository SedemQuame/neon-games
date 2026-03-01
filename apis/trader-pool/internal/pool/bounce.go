package pool

import (
	"log"
	"math/rand"
	"sync"

	"gamehub/trader-pool/internal/config"
)

// BounceTracker decides whether to intercept an incoming order before it
// reaches Deriv, keeping the stake as house profit ("bounce"). It also tracks
// cumulative profit and reduces the bounce rate once a configurable target is met.
type BounceTracker struct {
	mu             sync.Mutex
	accumulatedUsd float64
	cfg            *config.Config
	rng            *rand.Rand
}

// newBounceTracker creates a BounceTracker seeded from the shared rng source.
func newBounceTracker(cfg *config.Config, rng *rand.Rand) *BounceTracker {
	return &BounceTracker{cfg: cfg, rng: rng}
}

// ShouldBounce returns true if this bet should be intercepted as a forced LOSS.
//
// Effective bounce rate:
//   - If profit target is unset (0) → always use BounceRate.
//   - If accumulated profit >= target → use BounceRate * 0.5 (ease off).
func (b *BounceTracker) ShouldBounce() bool {
	if b.cfg.BounceRate <= 0 {
		return false
	}

	b.mu.Lock()
	accumulated := b.accumulatedUsd
	b.mu.Unlock()

	effectiveRate := b.cfg.BounceRate
	if b.cfg.ProfitTargetUsd > 0 && accumulated >= b.cfg.ProfitTargetUsd {
		effectiveRate = b.cfg.BounceRate * 0.5
	}

	if effectiveRate <= 0 {
		return false
	}

	// Float64 returns a random number in [0.0, 1.0)
	return b.rng.Float64() < effectiveRate
}

// RecordBounce adds stakeUsd to the house profit ledger and logs the update.
func (b *BounceTracker) RecordBounce(stakeUsd float64) {
	b.mu.Lock()
	b.accumulatedUsd += stakeUsd
	total := b.accumulatedUsd
	b.mu.Unlock()

	targetStr := "unlimited"
	if b.cfg.ProfitTargetUsd > 0 {
		if total >= b.cfg.ProfitTargetUsd {
			targetStr = "TARGET MET ✅"
		} else {
			targetStr = "target not yet met"
		}
	}
	log.Printf("[bounce] kept stake=%.2f | total_house_profit=%.2f | target=%s",
		stakeUsd, total, targetStr)
}

// Stats returns the current cumulative house profit captured by bouncing.
func (b *BounceTracker) Stats() (accumulatedUsd float64, targetMet bool) {
	b.mu.Lock()
	defer b.mu.Unlock()
	accumulatedUsd = b.accumulatedUsd
	targetMet = b.cfg.ProfitTargetUsd > 0 && accumulatedUsd >= b.cfg.ProfitTargetUsd
	return
}
