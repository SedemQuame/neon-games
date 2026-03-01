#!/usr/bin/env bash
# =============================================================================
# monetize.sh — GameHub Monetization Management Script
#
# Usage:
#   ./monetize.sh status                       Show current configuration
#   ./monetize.sh bounce   --rate 0.20         Set bounce rate (e.g. 20%)
#   ./monetize.sh bounce   --off               Disable bouncing
#   ./monetize.sh rake     --rate 0.05         Set win rake to 5%
#   ./monetize.sh rake     --off               Disable win rake
#   ./monetize.sh deposit-fee --rate 0.05      Set deposit fee to 5%
#   ./monetize.sh deposit-fee --off            Disable deposit fee
#   ./monetize.sh multiplier  --value 1.75     Set simulated payout multiplier
#   ./monetize.sh profit-target --value 100    Set house profit target ($)
#   ./monetize.sh profit-target --off          Disable profit target
#   ./monetize.sh apply                        Restart affected services
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$(cd "$SCRIPT_DIR/.." && pwd)/.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ── helpers ───────────────────────────────────────────────────────────────────

read_env() {
  local key="$1" default="${2:-0}"
  grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | tail -1 | cut -d'=' -f2 | tr -d ' ' || echo "$default"
}

set_env() {
  local key="$1" value="$2"
  if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
    # Replace existing line (macOS-compatible sed)
    sed -i.bak "s|^${key}=.*|${key}=${value}|" "$ENV_FILE" && rm -f "${ENV_FILE}.bak"
  else
    echo "${key}=${value}" >> "$ENV_FILE"
  fi
  echo -e "${GREEN}✓ ${key} = ${value}${RESET}"
}

feature_status() {
  local name="$1" key="$2" threshold="${3:-0}"
  local val
  val=$(read_env "$key" "0")
  local num
  num=$(echo "$val" | awk '{printf "%.4f", $1}')
  if awk "BEGIN{exit !($num > $threshold)}"; then
    echo -e "  ${GREEN}● ON${RESET}  ${BOLD}${name}${RESET}: $val"
  else
    echo -e "  ${RED}○ OFF${RESET} ${BOLD}${name}${RESET}: $val"
  fi
}

pct() {
  local val="$1"
  awk "BEGIN{printf \"%.0f%%\", $val * 100}"
}

# ── status ────────────────────────────────────────────────────────────────────

cmd_status() {
  echo ""
  echo -e "${CYAN}${BOLD}━━━ GameHub Monetization Status ━━━${RESET}"
  echo ""

  BR=$(read_env "BOUNCE_RATE" "0")
  PT=$(read_env "PROFIT_TARGET_USD" "0")
  RK=$(read_env "WIN_RAKE_RATE" "0")
  PM=$(read_env "PAYOUT_MULTIPLIER" "1.9")
  DF=$(read_env "DEPOSIT_FEE_RATE" "0")

  # Bounce
  if awk "BEGIN{exit !($BR > 0)}"; then
    echo -e "  ${GREEN}● ON${RESET}  ${BOLD}Bounce Rate${RESET}:       $(pct $BR) of bets intercepted"
    if awk "BEGIN{exit !($PT > 0)}"; then
      echo -e "             ${BOLD}Profit Target${RESET}: \$$PT (rate halves when reached)"
    else
      echo -e "             ${BOLD}Profit Target${RESET}: disabled"
    fi
  else
    echo -e "  ${RED}○ OFF${RESET} ${BOLD}Bounce Rate${RESET}:       0%"
  fi

  # Win Rake
  if awk "BEGIN{exit !($RK > 0)}"; then
    echo -e "  ${GREEN}● ON${RESET}  ${BOLD}Win Rake${RESET}:          $(pct $RK) of profits taken on each WIN"
  else
    echo -e "  ${RED}○ OFF${RESET} ${BOLD}Win Rake${RESET}:          0%"
  fi

  # Payout Multiplier
  echo -e "  ${CYAN}▸    ${BOLD}Payout Multiplier${RESET}: ${PM}x  (used in simulation mode)"

  # Deposit Fee
  if awk "BEGIN{exit !($DF > 0)}"; then
    echo -e "  ${GREEN}● ON${RESET}  ${BOLD}Deposit Fee${RESET}:       $(pct $DF) deducted from all deposits"
  else
    echo -e "  ${RED}○ OFF${RESET} ${BOLD}Deposit Fee${RESET}:       0%"
  fi

  echo ""
  echo -e "${YELLOW}Run './monetize.sh apply' to restart services and apply any pending changes.${RESET}"
  echo ""
}

# ── subcommands ───────────────────────────────────────────────────────────────

cmd_bounce() {
  case "${1:-}" in
    --off)   set_env "BOUNCE_RATE" "0.0" ;;
    --rate)  set_env "BOUNCE_RATE" "$2" ;;
    *) echo "Usage: bounce --rate <0.0-1.0> | --off"; exit 1 ;;
  esac
}

cmd_profit_target() {
  case "${1:-}" in
    --off)    set_env "PROFIT_TARGET_USD" "0.0" ;;
    --value)  set_env "PROFIT_TARGET_USD" "$2" ;;
    *) echo "Usage: profit-target --value <amount> | --off"; exit 1 ;;
  esac
}

cmd_rake() {
  case "${1:-}" in
    --off)   set_env "WIN_RAKE_RATE" "0.0" ;;
    --rate)  set_env "WIN_RAKE_RATE" "$2" ;;
    *) echo "Usage: rake --rate <0.0-1.0> | --off"; exit 1 ;;
  esac
}

cmd_multiplier() {
  case "${1:-}" in
    --value) set_env "PAYOUT_MULTIPLIER" "$2" ;;
    *) echo "Usage: multiplier --value <number, e.g. 1.75>"; exit 1 ;;
  esac
}

cmd_deposit_fee() {
  case "${1:-}" in
    --off)   set_env "DEPOSIT_FEE_RATE" "0.0" ;;
    --rate)  set_env "DEPOSIT_FEE_RATE" "$2" ;;
    *) echo "Usage: deposit-fee --rate <0.0-1.0> | --off"; exit 1 ;;
  esac
}

cmd_apply() {
  COMPOSE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
  echo -e "${CYAN}Restarting affected services…${RESET}"
  docker-compose -f "$COMPOSE_DIR/docker-compose.yml" restart trader-pool payment-gateway
  echo -e "${GREEN}✓ Services restarted. Changes are live.${RESET}"
}

# ── router ────────────────────────────────────────────────────────────────────

if [[ ! -f "$ENV_FILE" ]]; then
  echo -e "${RED}Error: .env not found at $ENV_FILE${RESET}"
  exit 1
fi

COMMAND="${1:-status}"
shift || true

case "$COMMAND" in
  status)        cmd_status ;;
  bounce)        cmd_bounce "$@" ;;
  profit-target) cmd_profit_target "$@" ;;
  rake)          cmd_rake "$@" ;;
  multiplier)    cmd_multiplier "$@" ;;
  deposit-fee)   cmd_deposit_fee "$@" ;;
  apply)         cmd_apply ;;
  *)
    echo "Unknown command: $COMMAND"
    echo "Commands: status | bounce | profit-target | rake | multiplier | deposit-fee | apply"
    exit 1
    ;;
esac
