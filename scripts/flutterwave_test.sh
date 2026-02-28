#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/apis/.env"

ENDPOINT="${FLW_ENDPOINT:-/v3/banks/gh}"
BASE_URL="${FLW_BASE_URL:-https://api.flutterwave.com}"
METHOD="${FLW_METHOD:-GET}"
PAYLOAD="${FLW_PAYLOAD:-}"

SECRET="${FLW_TEST_SECRET:-}"
if [[ -z "${SECRET}" && -f "${ENV_FILE}" ]]; then
  SECRET="$(grep -E '^FLUTTERWAVE_TEST_SECRET_KEY=' "${ENV_FILE}" | head -n1 | cut -d'=' -f2-)"
fi

if [[ -z "${SECRET}" ]]; then
  echo "error: set FLW_TEST_SECRET or FLUTTERWAVE_TEST_SECRET_KEY in apis/.env" >&2
  exit 1
fi

URL="${BASE_URL%/}${ENDPOINT}"
echo "→ ${METHOD} ${URL}"

if [[ -n "${PAYLOAD}" ]]; then
  echo "payload: ${PAYLOAD}"
fi

curl_args=(
  -sS
  -w "\nHTTP %{http_code}\n"
  -H "Authorization: Bearer ${SECRET}"
  -H "Content-Type: application/json"
  -X "${METHOD}"
)

if [[ -n "${PAYLOAD}" ]]; then
  curl_args+=(-d "${PAYLOAD}")
fi

TMP="$(mktemp)"
FMT="$(mktemp)"
trap 'rm -f "$TMP" "$FMT"' EXIT
curl "${curl_args[@]}" "${URL}" | tee "$TMP" >/dev/null
if python -m json.tool "$TMP" >"$FMT" 2>/dev/null; then
  cat "$FMT"
else
  cat "$TMP"
fi
