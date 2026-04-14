#!/usr/bin/env bash

set -euo pipefail

AUTH_SERVICE_PORT="${AUTH_SERVICE_PORT:-8001}"
GAME_SESSION_PORT="${GAME_SESSION_PORT:-8002}"
PAYMENT_GATEWAY_PORT="${PAYMENT_GATEWAY_PORT:-8003}"
WALLET_SERVICE_PORT="${WALLET_SERVICE_PORT:-8004}"
TRADER_POOL_PORT="${TRADER_POOL_PORT:-8005}"
GATEWAY_PORT="${GATEWAY_PORT:-80}"
START_EMBEDDED_REDIS="${START_EMBEDDED_REDIS:-true}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"
export PAYMENT_GATEWAY_URL="http://127.0.0.1:${PAYMENT_GATEWAY_PORT}"
export WALLET_SERVICE_URL="http://127.0.0.1:${WALLET_SERVICE_PORT}"
export GATEWAY_PORT

pids=()

cleanup() {
  for pid in "${pids[@]:-}"; do
    if kill -0 "${pid}" 2>/dev/null; then
      kill -TERM "${pid}" 2>/dev/null || true
    fi
  done
  wait || true
}

trap cleanup SIGINT SIGTERM

start_process() {
  "$@" &
  pids+=("$!")
}

if [[ "${START_EMBEDDED_REDIS}" == "true" ]]; then
  export REDIS_ADDR="127.0.0.1:6379"
  export REDIS_URL=""
  export REDISHOST=""
  export REDISPORT=""
  export REDISPASSWORD="${REDIS_PASSWORD}"

  mkdir -p /var/lib/redis
  redis_args=(
    --bind 127.0.0.1
    --port 6379
    --appendonly yes
    --dir /var/lib/redis
    --save 60 1000
    --loglevel warning
  )

  if [[ -n "${REDIS_PASSWORD}" ]]; then
    redis_args+=(--requirepass "${REDIS_PASSWORD}")
  fi

  start_process redis-server "${redis_args[@]}"

  for _ in {1..20}; do
    if [[ -n "${REDIS_PASSWORD}" ]]; then
      redis_ready_cmd=(redis-cli -h 127.0.0.1 -p 6379 -a "${REDIS_PASSWORD}" ping)
    else
      redis_ready_cmd=(redis-cli -h 127.0.0.1 -p 6379 ping)
    fi

    if "${redis_ready_cmd[@]}" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  if ! "${redis_ready_cmd[@]}" >/dev/null 2>&1; then
    echo "embedded redis did not become ready in time" >&2
    exit 1
  fi
fi

start_process env PORT="${AUTH_SERVICE_PORT}" /app/bin/auth-service
start_process env PORT="${WALLET_SERVICE_PORT}" /app/bin/wallet-service
start_process env PORT="${PAYMENT_GATEWAY_PORT}" /app/bin/payment-gateway
start_process env PORT="${TRADER_POOL_PORT}" /app/bin/trader-pool
start_process env PORT="${GAME_SESSION_PORT}" /app/bin/game-session-service
start_process env GATEWAY_PORT="${GATEWAY_PORT}" /app/bin/gateway

set +e
wait -n "${pids[@]}"
exit_code=$?
set -e

cleanup
exit "${exit_code}"
