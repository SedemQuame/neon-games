#!/bin/sh

set -eu

# App Store uploads can fail when Flutter native-asset frameworks are embedded
# without matching dSYMs inside the archive. Generate any missing framework
# dSYMs during archive/install builds so Xcode can include them automatically.
if [ "${ACTION:-}" != "install" ]; then
  exit 0
fi

frameworks_dir="${TARGET_BUILD_DIR:-}/${FRAMEWORKS_FOLDER_PATH:-}"
dsym_dir="${DWARF_DSYM_FOLDER_PATH:-}"

if [ -z "$frameworks_dir" ] || [ -z "$dsym_dir" ] || [ ! -d "$frameworks_dir" ]; then
  exit 0
fi

mkdir -p "$dsym_dir"

find "$frameworks_dir" -maxdepth 1 -type d -name '*.framework' | while IFS= read -r framework; do
  framework_name="$(basename "$framework")"
  binary_name="${framework_name%.framework}"
  binary_path="$framework/$binary_name"
  dsym_path="$dsym_dir/$framework_name.dSYM"
  info_plist="$framework/Info.plist"

  bundle_id=""
  if [ -f "$info_plist" ]; then
    bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist" 2>/dev/null || true)"
  fi

  case "$bundle_id" in
    io.flutter.flutter.native-assets.*) ;;
    *) continue ;;
  esac

  if [ ! -f "$binary_path" ] || [ -d "$dsym_path" ]; then
    continue
  fi

  if /usr/bin/dsymutil "$binary_path" -o "$dsym_path" >/dev/null 2>&1; then
    echo "Generated dSYM for $framework_name"
  else
    rm -rf "$dsym_path"
    echo "warning: Failed to generate dSYM for $framework_name" >&2
  fi
done
