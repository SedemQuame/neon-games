#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APIS_DIR="${ROOT_DIR}/apis"
ENV_FILE="${APIS_DIR}/.env"
DEV_SECRETS_DIR="${APIS_DIR}/infra/dev-secrets"
MONGO_KEYFILE="${APIS_DIR}/infra/mongo/replica.key"
COMPOSE_FILE="${APIS_DIR}/docker-compose.yml"
NGROK_PID_FILE="${ROOT_DIR}/.ngrok.pid"
NGROK_LOG_FILE="${ROOT_DIR}/.ngrok.log"
NGROK_URL_REGEX='https://[a-z0-9-]+\.(?:ngrok\.io|ngrok-free\.(?:app|dev))'

usage() {
  cat <<'USAGE'
Usage: ./setup.sh <command>

Commands:
  init         Copy .env.example, generate dev RSA keys, and verify prerequisites
  infra        Start only shared infrastructure services (mongo, redis, vault)
  services     Start only the Go microservices (requires infra running)
  up           Build and start the full Glory Grid stack via docker compose
  bootstrap    Convenience: infra + services (same as running infra, then services)
  down         Stop all containers defined in docker-compose.yml
  status       Show docker compose service status
  mongo-init   Re-run the replica-set init job (useful after wiping Mongo volume)
  dev          Start the full stack then tail logs (Ctrl+C to stop tailing)
  restart-auth Rebuild auth-service and restart auth + nginx containers
  logs [s]     Tail docker compose logs (optionally pass a service name)
  tunnel       Launch an ngrok tunnel to port 80 and print the public URL
  flutter-run  Run the Flutter app with --dart-define=GAMEHUB_BASE_URL
  mobile       One-shot: bootstrap backend, start ngrok, run Flutter on device
  seed-wallet  Credit a user (by email) with USD (default \$150) in Mongo
USAGE
}

ensure_env() {
  if [[ ! -f "${ENV_FILE}" ]]; then
    cp "${APIS_DIR}/.env.example" "${ENV_FILE}"
    echo "Created ${ENV_FILE} from template."
  fi
  mkdir -p "${DEV_SECRETS_DIR}"
  if [[ ! -f "${DEV_SECRETS_DIR}/jwt_private.pem" ]]; then
    echo "Generating development RSA key pair..."
    openssl genrsa -out "${DEV_SECRETS_DIR}/jwt_private.pem" 2048 >/dev/null 2>&1
    openssl rsa -in "${DEV_SECRETS_DIR}/jwt_private.pem" -pubout \
      -out "${DEV_SECRETS_DIR}/jwt_public.pem" >/dev/null 2>&1
  fi
  if [[ ! -f "${MONGO_KEYFILE}" ]]; then
    echo "Creating MongoDB replica keyfile..."
    local current_umask
    current_umask="$(umask)"
    umask 177
    openssl rand -base64 756 > "${MONGO_KEYFILE}"
    umask "${current_umask}"
    chmod 400 "${MONGO_KEYFILE}"
  fi
}

ensure_compose() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is required but not found in PATH." >&2
    exit 1
  fi
  if ! docker compose version >/dev/null 2>&1; then
    echo "Docker Compose V2 is required (docker compose ...)." >&2
    exit 1
  fi
}

cmd_init() {
  ensure_compose
  ensure_env
  echo "Initialization complete."
}

cmd_infra() {
  cmd_init
  docker compose -f "${COMPOSE_FILE}" up -d mongo redis vault mongo-init
}

cmd_services() {
  cmd_init
  docker compose -f "${COMPOSE_FILE}" up -d \
    auth-service \
    wallet-service \
    payment-gateway \
    game-session-service \
    trader-pool \
    nginx
}

cmd_up() {
  cmd_init
  docker compose -f "${COMPOSE_FILE}" up -d
}

cmd_bootstrap() {
  echo "Starting shared infrastructure..."
  cmd_infra
  echo "Bringing up Go microservices..."
  cmd_services
  echo "Glory Grid stack is running. Use './setup.sh logs' to inspect logs or './setup.sh dev' to tail everything."
}

cmd_down() {
  ensure_compose
  docker compose -f "${COMPOSE_FILE}" down
}

cmd_logs() {
  ensure_compose
  local service="${1:-}"
  if [[ -n "${service}" ]]; then
    docker compose -f "${COMPOSE_FILE}" logs -f "${service}"
  else
    docker compose -f "${COMPOSE_FILE}" logs -f
  fi
}

cmd_status() {
  ensure_compose
  docker compose -f "${COMPOSE_FILE}" ps
}

cmd_mongo_init() {
  cmd_init
  echo "Re-running mongo-init job..."
  docker compose -f "${COMPOSE_FILE}" up mongo-init
}

cmd_dev() {
  cmd_up
  echo "Tailing docker logs (Ctrl+C to exit)..."
  cmd_logs "$@"
}

cmd_restart_auth() {
  cmd_init
  echo "Rebuilding auth-service..."
  docker compose -f "${COMPOSE_FILE}" build auth-service
  echo "Restarting auth-service and nginx..."
  docker compose -f "${COMPOSE_FILE}" up -d auth-service nginx
}

cmd_flutter_run() {
  if ! command -v flutter >/dev/null 2>&1; then
    echo "Flutter SDK is not installed or not in PATH." >&2
    exit 1
  fi

  local base_url
  base_url="${1:-}"
  if [[ -z "${base_url}" ]]; then
    if [[ -f "${NGROK_LOG_FILE}" ]]; then
      base_url=$(grep -oE "${NGROK_URL_REGEX}" "${NGROK_LOG_FILE}" | tail -n1 || true)
    fi
  fi
  if [[ -z "${base_url}" ]]; then
    echo "No ngrok URL found. Run './setup.sh tunnel' first or pass a URL explicitly:"
    echo "  ./setup.sh flutter-run https://example.ngrok-free.dev"
    exit 1
  fi

  echo "Running flutter run with GAMEHUB_BASE_URL=${base_url}"
  (cd "${ROOT_DIR}/game_trader_app" && flutter run --dart-define="GAMEHUB_BASE_URL=${base_url}" "$@")
}

cmd_mobile() {
  cmd_bootstrap
  cmd_tunnel
  local base_url
  base_url=$(grep -oE "${NGROK_URL_REGEX}" "${NGROK_LOG_FILE}" | tail -n1 || true)
  if [[ -z "${base_url}" ]]; then
    echo "Unable to retrieve ngrok URL after starting tunnel." >&2
    exit 1
  fi
  cmd_flutter_run "${base_url}"
}

cmd_tunnel() {
  if ! command -v ngrok >/dev/null 2>&1; then
    echo "ngrok is not installed. Visit https://ngrok.com/download and install it first." >&2
    exit 1
  fi
  if [[ -f "${NGROK_PID_FILE}" ]]; then
    local old_pid
    old_pid="$(cat "${NGROK_PID_FILE}" 2>/dev/null || true)"
    if [[ -n "${old_pid}" ]] && kill -0 "${old_pid}" >/dev/null 2>&1; then
      echo "Ngrok tunnel already running (PID ${old_pid}). Stop it first (kill ${old_pid}) or remove ${NGROK_PID_FILE}."
      return
    else
      rm -f "${NGROK_PID_FILE}"
    fi
  fi

  echo "Starting ngrok http 80 ..."
  ngrok http 80 --log=stdout > "${NGROK_LOG_FILE}" 2>&1 &
  local ngrok_pid=$!
  echo "${ngrok_pid}" > "${NGROK_PID_FILE}"
  echo "Waiting for public URL..."

  local public_url=""
  for _ in {1..20}; do
    if public_url=$(grep -oE "${NGROK_URL_REGEX}" "${NGROK_LOG_FILE}" | tail -n1); then
      if [[ -n "${public_url}" ]]; then
        break
      fi
    fi
    sleep 1
  done

  if [[ -z "${public_url}" ]]; then
    echo "Failed to obtain ngrok URL. Check ${NGROK_LOG_FILE} for details."
    return 1
  fi

  echo "Ngrok tunnel is live: ${public_url}"
  echo "Remember to point GAMEHUB_BASE_URL to this URL when running Flutter (e.g. --dart-define=GAMEHUB_BASE_URL=${public_url})."
  echo "To stop the tunnel, run: kill ${ngrok_pid} && rm -f ${NGROK_PID_FILE}"
}

cmd_seed_wallet() {
  local email="${1:-}"
  local amount="${2:-150}"
  if [[ -z "${email}" ]]; then
    echo "Usage: ./setup.sh seed-wallet <email> [amount]" >&2
    exit 1
  fi
  cmd_init
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a

  ensure_compose
  docker compose -f "${COMPOSE_FILE}" up -d mongo >/dev/null 2>&1

  local escaped_email
  escaped_email=$(printf '%s' "${email}" | sed 's/"/\\"/g')
  local amount_value="${amount}"

  echo "Seeding \$${amount_value} for ${email}..."
  docker compose -f "${COMPOSE_FILE}" exec -T \
    -e SEED_EMAIL="${escaped_email}" \
    -e SEED_AMOUNT="${amount_value}" \
    mongo mongosh \
    -u "${MONGO_INITDB_ROOT_USERNAME}" \
    -p "${MONGO_INITDB_ROOT_PASSWORD}" \
    --authenticationDatabase admin \
    gamehub --quiet <<'EOF'
const email = (process.env.SEED_EMAIL || "").trim();
const amount = parseFloat(process.env.SEED_AMOUNT || "0");
if (!email) { console.log("Email required"); quit(1); }
if (!amount || isNaN(amount)) { console.log("Amount must be numeric"); quit(1); }
const normalizedEmail = email.toLowerCase();
const user = db.users.findOne({
  $expr: { $eq: [ { $toLower: "$email" }, normalizedEmail ] }
});
if (!user) {
  console.log("No user found with email " + email);
  quit(1);
}
const userId = user._id.toString();
const now = new Date();
db.wallet_balances.updateOne(
  { userId },
  {
    $setOnInsert: { userId, reservedUsd: 0, createdAt: now },
    $set: { updatedAt: now },
    $inc: { availableUsd: amount }
  },
  { upsert: true }
);
db.ledger_entries.insertOne({
  userId,
  type: "DEV_SEED",
  amountUsd: amount,
  reference: "DEV_SEED_" + now.getTime(),
  createdAt: now,
  metadata: { note: "seeded via setup.sh" }
});
const latest = db.wallet_balances.findOne({ userId }) || { availableUsd: 0 };
print("Wallet topped up successfully for " + email + " (userId=" + userId + "). Available now: $" + (latest.availableUsd || 0));
EOF
}

command="${1:-help}"
shift || true

case "${command}" in
  init) cmd_init ;;
  infra) cmd_infra ;;
  services) cmd_services ;;
  up) cmd_up ;;
  bootstrap) cmd_bootstrap ;;
  down) cmd_down ;;
  status) cmd_status ;;
  mongo-init) cmd_mongo_init ;;
  dev) cmd_dev "$@" ;;
  restart-auth) cmd_restart_auth ;;
  flutter-run) cmd_flutter_run "$@" ;;
  mobile) cmd_mobile ;;
  tunnel) cmd_tunnel ;;
  seed-wallet) cmd_seed_wallet "$@" ;;
  logs) cmd_logs "$@" ;;
  help|*) usage ;;
esac
