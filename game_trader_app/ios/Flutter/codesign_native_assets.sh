#!/bin/sh
set -eu

if [ "${CODE_SIGNING_ALLOWED:-NO}" != "YES" ]; then
  exit 0
fi

if [ -z "${EXPANDED_CODE_SIGN_IDENTITY:-}" ] || [ "${EXPANDED_CODE_SIGN_IDENTITY}" = "-" ]; then
  exit 0
fi

frameworks_dir="${TARGET_BUILD_DIR:-}/${FRAMEWORKS_FOLDER_PATH:-}"
if [ ! -d "$frameworks_dir" ]; then
  exit 0
fi

for framework in "$frameworks_dir"/*.framework; do
  [ -d "$framework" ] || continue

  if /usr/bin/codesign -dv "$framework" 2>&1 | /usr/bin/grep -q "Signature=adhoc"; then
    /usr/bin/codesign \
      --force \
      --sign "$EXPANDED_CODE_SIGN_IDENTITY" \
      --timestamp=none \
      --preserve-metadata=identifier \
      "$framework"
  fi
done
