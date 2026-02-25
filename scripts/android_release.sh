#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: android_release.sh [options]

Builds the Flutter Android release binaries (APK + AAB) and optionally installs
the APK on a connected adb device for a smoke test.

Options:
  --base-url <url>      Override GAMEHUB_BASE_URL for this invocation.
  --device <serial>     Push APK to a specific adb serial.
  --skip-install        Build only; do not install after building.
  --skip-bundle         Skip generating the .aab bundle.
  -h, --help            Show this message.

Environment:
  FLUTTER               Path to flutter (default: flutter on PATH).
  GAMEHUB_BASE_URL      Default backend URL (falls back to ngrok dev URL).
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$REPO_ROOT/game_trader_app"
FLUTTER_BIN="${FLUTTER:-flutter}"
BASE_URL="${GAMEHUB_BASE_URL:-https://resectional-maxillipedary-sherika.ngrok-free.dev}"
INSTALL_AFTER_BUILD=1
BUILD_BUNDLE=1
DEVICE_ID=""

ensure_java() {
  local selected="${JAVA_HOME:-}"
  if [[ -n "$selected" ]]; then
    if ! "$selected/bin/java" -version 2>&1 | grep -q 'version "1[7-9]\.'; then
      selected=""
    fi
  fi
  if [[ -z "$selected" ]]; then
    if /usr/libexec/java_home -v 19 >/dev/null 2>&1; then
      selected="$(/usr/libexec/java_home -v 19)"
    elif /usr/libexec/java_home -v 17 >/dev/null 2>&1; then
      selected="$(/usr/libexec/java_home -v 17)"
    fi
  fi
  if [[ -n "$selected" ]]; then
    export JAVA_HOME="$selected"
    export PATH="$JAVA_HOME/bin:$PATH"
  else
    echo "Warning: could not locate a Java 17+ runtime; Gradle may fail." >&2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url)
      [[ $# -ge 2 ]] || { echo "--base-url requires a value" >&2; exit 1; }
      BASE_URL="$2"
      shift 2
      ;;
    --device)
      [[ $# -ge 2 ]] || { echo "--device requires a serial" >&2; exit 1; }
      DEVICE_ID="$2"
      shift 2
      ;;
    --skip-install)
      INSTALL_AFTER_BUILD=0
      shift
      ;;
    --skip-bundle)
      BUILD_BUNDLE=0
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

info() { printf '\n▶ %s\n' "$1"; }
run_flutter() {
  ( cd "$APP_DIR" && "$FLUTTER_BIN" "$@" )
}

ensure_java

if ! command -v "$FLUTTER_BIN" >/dev/null 2>&1; then
  echo "Flutter binary '$FLUTTER_BIN' not found on PATH" >&2
  exit 1
fi

APK_PATH="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"
AAB_PATH="$APP_DIR/build/app/outputs/bundle/release/app-release.aab"

info "Running flutter pub get"
run_flutter pub get

info "Building release APK with base URL $BASE_URL"
run_flutter build apk --release --dart-define=GAMEHUB_BASE_URL="$BASE_URL"

if [[ $BUILD_BUNDLE -eq 1 ]]; then
  info "Building release app bundle (.aab)"
  run_flutter build appbundle --release --dart-define=GAMEHUB_BASE_URL="$BASE_URL"
fi

if [[ $INSTALL_AFTER_BUILD -eq 1 ]]; then
  if ! command -v adb >/dev/null 2>&1; then
    echo "adb not found; skipping device install." >&2
  else
    if [[ -z "$DEVICE_ID" ]]; then
      devices=$(adb devices | awk 'NR>1 && $2=="device" {print $1}')
      if [[ -z "$devices" ]]; then
        echo "No adb devices available; skipping install." >&2
        INSTALL_AFTER_BUILD=0
      else
        first_device=$(printf '%s\n' "$devices" | head -n1)
        count=$(printf '%s\n' "$devices" | sed '/^$/d' | wc -l | tr -d ' ')
        if [[ "$count" -gt 1 ]]; then
          echo "Multiple adb devices detected:"
          printf '  %s\n' $devices
          echo "Re-run with --device <serial> to select one." >&2
          INSTALL_AFTER_BUILD=0
        else
          DEVICE_ID="$first_device"
        fi
      fi
    fi

    if [[ $INSTALL_AFTER_BUILD -eq 1 ]]; then
      info "Installing release APK to $DEVICE_ID"
      adb -s "$DEVICE_ID" install -r "$APK_PATH"
    fi
  fi
fi

cat <<SUMMARY

✅ Android binaries ready
  APK : $APK_PATH
  AAB : $AAB_PATH

Upload the bundle to the Play Console (Internal testing track) or share the APK via Firebase App Distribution as needed.
SUMMARY
