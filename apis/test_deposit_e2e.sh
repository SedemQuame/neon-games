#!/usr/bin/env bash
# =============================================================================
# E2E Deposit Test — GameHub Payment Flow
# Tests the full deposit path: authenticate → deposit → check status
#
# Usage:
#   chmod +x test_deposit_e2e.sh
#   ./test_deposit_e2e.sh
#
# Prerequisites:
#   - Docker containers running (docker-compose up --build -d)
#   - curl and jq installed
# =============================================================================

set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────────────────
BASE_URL="${BASE_URL:-http://localhost:80}"
PHONE="0546744163"
AMOUNT="1.00"
CHANNEL="mtn-gh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

pass() { echo -e "${GREEN}✅ PASS${NC}: $1"; }
fail() { echo -e "${RED}❌ FAIL${NC}: $1"; echo -e "   ${RED}$2${NC}"; }
info() { echo -e "${CYAN}ℹ️  ${NC}$1"; }
step() { echo -e "\n${BOLD}${YELLOW}── Step $1: $2 ──${NC}"; }

# ─── Dependency Check ───────────────────────────────────────────────────────
for cmd in curl jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: '$cmd' is required but not installed."
    exit 1
  fi
done

echo -e "\n${BOLD}══════════════════════════════════════════════════${NC}"
echo -e "${BOLD}    GameHub E2E Deposit Test${NC}"
echo -e "${BOLD}══════════════════════════════════════════════════${NC}"
info "Base URL:  $BASE_URL"
info "Phone:     $PHONE"
info "Amount:    $AMOUNT GHS"
info "Channel:   $CHANNEL"

# ─── Step 0: Health Checks ──────────────────────────────────────────────────
step 0 "Service Health Checks"

echo -n "  Auth service... "
AUTH_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/v1/auth/health" 2>/dev/null || curl -s -o /dev/null -w "%{http_code}" "http://localhost:8001/health" 2>/dev/null || echo "000")
if [[ "$AUTH_HEALTH" == "200" ]]; then
  echo -e "${GREEN}OK${NC}"
else
  echo -e "${YELLOW}WARN (HTTP $AUTH_HEALTH via nginx, trying direct)${NC}"
fi

echo -n "  Payment gateway... "
PAY_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8003/health" 2>/dev/null || echo "000")
if [[ "$PAY_HEALTH" == "200" ]]; then
  echo -e "${GREEN}OK${NC}"
else
  echo -e "${RED}FAIL (HTTP $PAY_HEALTH)${NC}"
fi

# ─── Step 1: Authenticate (Guest Start) ────────────────────────────────────
step 1 "Authenticate via Guest Start"

AUTH_RESP=$(curl -s -X POST "$BASE_URL/api/v1/auth/guest/start" \
  -H 'Content-Type: application/json' \
  -d '{}' 2>&1)

echo "  Response: $(echo "$AUTH_RESP" | jq -c '.' 2>/dev/null || echo "$AUTH_RESP")"

ACCESS_TOKEN=$(echo "$AUTH_RESP" | jq -r '.accessToken // empty' 2>/dev/null)
USER_ID=$(echo "$AUTH_RESP" | jq -r '.user._id // .user.id // empty' 2>/dev/null)

if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
  fail "Could not obtain access token" "$AUTH_RESP"

  # Fallback: try direct connection to auth service
  info "Retrying with direct auth-service connection (port 8001)..."
  AUTH_RESP=$(curl -s -X POST "http://localhost:8001/api/v1/auth/guest/start" \
    -H 'Content-Type: application/json' \
    -d '{}' 2>&1)
  echo "  Response: $(echo "$AUTH_RESP" | jq -c '.' 2>/dev/null || echo "$AUTH_RESP")"

  ACCESS_TOKEN=$(echo "$AUTH_RESP" | jq -r '.accessToken // empty' 2>/dev/null)
  USER_ID=$(echo "$AUTH_RESP" | jq -r '.user._id // .user.id // empty' 2>/dev/null)

  if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
    fail "Authentication failed on both nginx and direct" "$AUTH_RESP"
    exit 1
  fi
fi

pass "Got access token (user: $USER_ID)"
info "Token: ${ACCESS_TOKEN:0:40}..."

# ─── Step 2: Check Wallet Balance ──────────────────────────────────────────
step 2 "Check Wallet Balance (pre-deposit)"

BALANCE_RESP=$(curl -s -X GET "$BASE_URL/api/v1/wallet/balance" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H 'Content-Type: application/json' 2>&1)

echo "  Response: $(echo "$BALANCE_RESP" | jq -c '.' 2>/dev/null || echo "$BALANCE_RESP")"

PRE_BALANCE=$(echo "$BALANCE_RESP" | jq -r '.balance // .balanceUsd // "unknown"' 2>/dev/null)
info "Pre-deposit balance: $PRE_BALANCE"

# ─── Step 3: Initiate MoMo Deposit ─────────────────────────────────────────
step 3 "Initiate MoMo Deposit"

DEPOSIT_PAYLOAD=$(jq -n \
  --arg phone "$PHONE" \
  --argjson amount "$AMOUNT" \
  --arg channel "$CHANNEL" \
  '{phone: $phone, amount: $amount, channel: $channel}')

info "Payload: $DEPOSIT_PAYLOAD"

DEPOSIT_RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/api/v1/payments/momo/deposit" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H 'Content-Type: application/json' \
  -d "$DEPOSIT_PAYLOAD" 2>&1)

HTTP_CODE=$(echo "$DEPOSIT_RESP" | tail -1)
DEPOSIT_BODY=$(echo "$DEPOSIT_RESP" | sed '$d')

echo "  HTTP Status: $HTTP_CODE"
echo "  Response: $(echo "$DEPOSIT_BODY" | jq -c '.' 2>/dev/null || echo "$DEPOSIT_BODY")"

if [[ "$HTTP_CODE" == "202" ]]; then
  pass "Deposit initiated successfully (HTTP 202)"
  REFERENCE=$(echo "$DEPOSIT_BODY" | jq -r '.reference // empty' 2>/dev/null)
  PROVIDER_REF=$(echo "$DEPOSIT_BODY" | jq -r '.providerReference // empty' 2>/dev/null)
  info "Reference:          $REFERENCE"
  info "Provider Reference: $PROVIDER_REF"
elif [[ "$HTTP_CODE" == "500" ]]; then
  fail "Deposit failed (HTTP 500)" "$DEPOSIT_BODY"
  
  # Check payment-gateway container logs for the actual error
  echo -e "\n${YELLOW}  ── Payment Gateway Logs (last 20 lines) ──${NC}"
  docker logs gamehub_payment --tail 20 2>&1 | while IFS= read -r line; do
    echo "  $line"
  done

  # Also try direct connection to payment gateway (bypass nginx)
  info "Retrying with direct payment-gateway connection (port 8003)..."
  DEPOSIT_RESP2=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:8003/api/v1/payments/momo/deposit" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H 'Content-Type: application/json' \
    -d "$DEPOSIT_PAYLOAD" 2>&1)

  HTTP_CODE2=$(echo "$DEPOSIT_RESP2" | tail -1)
  DEPOSIT_BODY2=$(echo "$DEPOSIT_RESP2" | sed '$d')
  echo "  Direct HTTP Status: $HTTP_CODE2"
  echo "  Direct Response: $(echo "$DEPOSIT_BODY2" | jq -c '.' 2>/dev/null || echo "$DEPOSIT_BODY2")"

  if [[ "$HTTP_CODE2" == "202" ]]; then
    pass "Deposit succeeded via direct connection"
    REFERENCE=$(echo "$DEPOSIT_BODY2" | jq -r '.reference // empty' 2>/dev/null)
  else
    fail "Deposit also failed via direct connection" "$DEPOSIT_BODY2"
    echo -e "\n${YELLOW}  ── Latest Payment Gateway Logs ──${NC}"
    docker logs gamehub_payment --tail 30 2>&1 | grep -i "error\|ERROR\|fail\|FAIL\|InsertOne" | while IFS= read -r line; do
      echo "  $line"
    done
    REFERENCE=""
  fi
else
  fail "Unexpected HTTP status: $HTTP_CODE" "$DEPOSIT_BODY"
  REFERENCE=""
fi

# ─── Step 4: Check Deposit Status ──────────────────────────────────────────
if [[ -n "${REFERENCE:-}" ]]; then
  step 4 "Check Deposit Status"

  sleep 2
  STATUS_RESP=$(curl -s -X GET "$BASE_URL/api/v1/payments/momo/status/$REFERENCE" \
    -H "Authorization: Bearer $ACCESS_TOKEN" 2>&1)

  echo "  Response: $(echo "$STATUS_RESP" | jq -c '.' 2>/dev/null || echo "$STATUS_RESP")"

  STATUS=$(echo "$STATUS_RESP" | jq -r '.status // empty' 2>/dev/null)
  info "Payment status: $STATUS"

  # Poll a few times if still pending
  for i in 1 2 3; do
    if [[ "$STATUS" == "PENDING" ]]; then
      info "Still pending, waiting 5s (attempt $i/3)..."
      sleep 5
      STATUS_RESP=$(curl -s -X GET "$BASE_URL/api/v1/payments/momo/status/$REFERENCE" \
        -H "Authorization: Bearer $ACCESS_TOKEN" 2>&1)
      STATUS=$(echo "$STATUS_RESP" | jq -r '.status // empty' 2>/dev/null)
      echo "  Status: $STATUS"
    fi
  done

  if [[ "$STATUS" == "COMPLETED" || "$STATUS" == "SUCCESSFUL" ]]; then
    pass "Deposit completed!"
  elif [[ "$STATUS" == "PENDING" ]]; then
    info "Deposit still pending (Flutterwave test mode — MoMo prompt may need approval)"
  else
    info "Final status: $STATUS"
  fi
fi

# ─── Step 5: Check Wallet Balance (post-deposit) ──────────────────────────
step 5 "Check Wallet Balance (post-deposit)"

BALANCE_RESP2=$(curl -s -X GET "$BASE_URL/api/v1/wallet/balance" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H 'Content-Type: application/json' 2>&1)

echo "  Response: $(echo "$BALANCE_RESP2" | jq -c '.' 2>/dev/null || echo "$BALANCE_RESP2")"

POST_BALANCE=$(echo "$BALANCE_RESP2" | jq -r '.balance // .balanceUsd // "unknown"' 2>/dev/null)
info "Post-deposit balance: $POST_BALANCE"

# ─── Summary ────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}══════════════════════════════════════════════════${NC}"
echo -e "${BOLD}    Test Summary${NC}"
echo -e "${BOLD}══════════════════════════════════════════════════${NC}"
echo "  User ID:          ${USER_ID:-N/A}"
echo "  Reference:        ${REFERENCE:-N/A}"
echo "  Pre-balance:      ${PRE_BALANCE:-unknown}"
echo "  Post-balance:     ${POST_BALANCE:-unknown}"
echo "  Final HTTP code:  ${HTTP_CODE}"
echo ""
