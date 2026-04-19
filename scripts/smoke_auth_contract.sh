#!/usr/bin/env bash

set -euo pipefail

BASE_URL="${1:-${GAMEHUB_BASE_URL:-http://127.0.0.1:80}}"
BASE_URL="${BASE_URL%/}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

contains_status() {
  local wanted="$1"
  shift
  local candidate
  for candidate in "$@"; do
    if [[ "${candidate}" == "${wanted}" ]]; then
      return 0
    fi
  done
  return 1
}

check_post_contract() {
  local name="$1"
  local path="$2"
  local payload="$3"
  shift 3
  local allowed=("$@")

  local body_file="${tmp_dir}/$(echo "${name}" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' ).body"
  local status
  status="$(
    curl -sS -o "${body_file}" -w "%{http_code}" \
      -X POST "${BASE_URL}${path}" \
      -H "Content-Type: application/json" \
      -d "${payload}"
  )"

  echo "[${name}] POST ${BASE_URL}${path} -> ${status}"
  if [[ "${status}" == "404" ]]; then
    echo "Response body:"
    cat "${body_file}" || true
    fail "${name} returned 404 (route mismatch)"
  fi

  if ! contains_status "${status}" "${allowed[@]}"; then
    echo "Response body:"
    cat "${body_file}" || true
    fail "${name} returned unexpected status ${status}; expected one of: ${allowed[*]}"
  fi
}

echo "Running auth contract smoke checks against ${BASE_URL}"
check_post_contract "Firebase login" "/api/v1/auth/firebase/login" '{}' 400 401
check_post_contract "Google login" "/api/v1/auth/google/login" '{}' 400 401 503
echo "Auth contract smoke checks passed."
