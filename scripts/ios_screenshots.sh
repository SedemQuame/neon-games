#!/usr/bin/env bash
set -euo pipefail

DEVICE_NAME="iPhone 15 Pro"
BASE_URL="${GAMEHUB_BASE_URL:-https://resectional-maxillipedary-sherika.ngrok-free.dev}"
LABELS=("login" "lobby" "gameplay")
OUT_DIR="screenshots/ios"

usage() {
  cat <<'USAGE'
Usage: ios_screenshots.sh [options]

Boots the requested iOS simulator, builds the Flutter app for simulator,
installs + launches it, and walks you through capturing high-res screenshots.
You physically arrange the UI for each label, then press Enter and the script
captures PNGs via `xcrun simctl io ... screenshot`.

Options:
  --device "iPhone 15 Pro"   Simulator name (default: iPhone 15 Pro)
  --base-url <url>           Override GAMEHUB_BASE_URL for the build
  --labels login,lobby,...   Comma separated list of screenshot labels
  --out screenshots/ios      Output directory for PNGs
  -h, --help                 Show this help.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device)
      DEVICE_NAME="$2"
      shift 2
      ;;
    --base-url)
      BASE_URL="$2"
      shift 2
      ;;
    --labels)
      IFS=',' read -r -a LABELS <<< "$2"
      shift 2
      ;;
    --out)
      OUT_DIR="$2"
      shift 2
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

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$REPO_ROOT/game_trader_app"
APP_BUNDLE_ID="com.glorygrid.glorygrid"
APP_PATH="$APP_DIR/build/ios/iphonesimulator/Runner.app"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd xcrun
require_cmd flutter
require_cmd plutil

echo "🔍 Locating simulator for \"$DEVICE_NAME\"..."
SIM_LINE="$(xcrun simctl list devices available | grep "$DEVICE_NAME (" | head -n1 || true)"
if [[ -z "$SIM_LINE" ]]; then
  echo "Could not find an available simulator named \"$DEVICE_NAME\"." >&2
  echo "Check available devices via: xcrun simctl list devices available" >&2
  exit 1
fi
SIM_UDID="$(echo "$SIM_LINE" | sed -n 's/.*(\([A-F0-9-]*\)).*/\1/p')"
echo "➡️  Using simulator UDID: $SIM_UDID"

echo "▶ Booting simulator (if needed)..."
xcrun simctl boot "$SIM_UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIM_UDID" -b
open -a Simulator --args -CurrentDeviceUDID "$SIM_UDID"

echo "▶ Building iOS app for simulator (may take a minute)..."
(cd "$APP_DIR" && flutter build ios --simulator --dart-define=GAMEHUB_BASE_URL="$BASE_URL")

echo "▶ Installing latest build onto simulator..."
xcrun simctl install "$SIM_UDID" "$APP_PATH"

echo "▶ Launching Glory Grid on the simulator..."
xcrun simctl launch "$SIM_UDID" "$APP_BUNDLE_ID" >/tmp/glorygrid-launch.log || true

mkdir -p "$REPO_ROOT/$OUT_DIR"
echo "📸 Ready to capture screenshots. Files saved to $OUT_DIR"

for label in "${LABELS[@]}"; do
  read -rp $'\nArrange the UI for '"$label"' then press Enter to capture...' _
  outfile="$REPO_ROOT/$OUT_DIR/${label}.png"
  xcrun simctl io "$SIM_UDID" screenshot "$outfile"
  echo "✅ Saved $outfile"
done

echo "All screenshots captured. Check $OUT_DIR for the PNG files."
