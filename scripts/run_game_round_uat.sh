#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/game_trader_app"
GAME_SESSION_DIR="$ROOT_DIR/apis/game-session-service"
BASE_URL="${GAMEHUB_BASE_URL:-https://neon-games-production.up.railway.app}"

echo "Running Glory Grid UAT baseline checks"
echo "Backend URL: $BASE_URL"

(
  cd "$APP_DIR"
  flutter analyze
  flutter build web --dart-define=GAMEHUB_BASE_URL="$BASE_URL"
)

(
  cd "$GAME_SESSION_DIR"
  go test ./...
)

cat <<EOF

Baseline checks passed.

Continue the visual UAT checklist in:
  docs/uat/game-round-uat-2026-05-05.md

For full real-money multiplayer acceptance, use two funded accounts in the same
room and measure tap-to-acknowledgement timing for every round type.
EOF
