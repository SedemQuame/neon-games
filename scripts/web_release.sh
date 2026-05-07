#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$REPO_ROOT/game_trader_app"
FLUTTER_BIN="${FLUTTER:-flutter}"
DEFAULT_BASE_URL="https://neon-games-production.up.railway.app"
ENV_FILE="${GAMEHUB_ENV_FILE:-$APP_DIR/.env.production}"

usage() {
  cat <<'USAGE'
Usage: web_release.sh [options]

Builds the Flutter web release with GAMEHUB_BASE_URL baked into the app.

Options:
  --base-url <url>        Override GAMEHUB_BASE_URL for this invocation.
  --env-file <path>       Load env vars from a file (default: game_trader_app/.env.production).
  --no-release            Build without --release.
  -h, --help              Show this message.

Environment:
  FLUTTER                 Path to flutter (default: flutter on PATH).
  GAMEHUB_BASE_URL        Backend URL used by the compiled web app.
  GAMEHUB_ENV_FILE        Env file to load before building.
USAGE
}

RELEASE_FLAG="--release"
BASE_URL="${GAMEHUB_BASE_URL:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url)
      [[ $# -ge 2 ]] || { echo "--base-url requires a value" >&2; exit 1; }
      BASE_URL="$2"
      shift 2
      ;;
    --env-file)
      [[ $# -ge 2 ]] || { echo "--env-file requires a value" >&2; exit 1; }
      ENV_FILE="$2"
      shift 2
      ;;
    --no-release)
      RELEASE_FLAG=""
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

BASE_URL="${BASE_URL:-${GAMEHUB_BASE_URL:-$DEFAULT_BASE_URL}}"

if ! command -v "$FLUTTER_BIN" >/dev/null 2>&1; then
  echo "Flutter binary '$FLUTTER_BIN' not found on PATH" >&2
  exit 1
fi

echo "Building Flutter web with GAMEHUB_BASE_URL=$BASE_URL"
(cd "$APP_DIR" && "$FLUTTER_BIN" build web $RELEASE_FLAG --dart-define=GAMEHUB_BASE_URL="$BASE_URL")
