#!/usr/bin/env bash
#
# Build a drag-to-Applications DMG from a signed .app bundle.
#
# Usage:
#   scripts/make-dmg.sh <path/to/Floric.app> <path/to/output.dmg>

set -euo pipefail

APP_PATH="${1:?Usage: make-dmg.sh <app> <dmg>}"
DMG_PATH="${2:?Usage: make-dmg.sh <app> <dmg>}"
APP_NAME="$(basename "${APP_PATH}" .app)"
VOL_NAME="${APP_NAME}"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "✗ App not found: ${APP_PATH}" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d -t floric-dmg)"
trap 'rm -rf "${WORK_DIR}"' EXIT

STAGE="${WORK_DIR}/stage"
mkdir -p "${STAGE}"

# Layout: Floric.app + symlink to /Applications. Drag-to-install.
cp -R "${APP_PATH}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"

rm -f "${DMG_PATH}"
hdiutil create \
  -volname "${VOL_NAME}" \
  -srcfolder "${STAGE}" \
  -ov \
  -format UDZO \
  -fs HFS+ \
  "${DMG_PATH}"

# Sign DMG too if a Developer ID is available — required for Gatekeeper to
# trust the disk image directly (notarization of the app inside still applies).
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  codesign --sign "${DEVELOPER_ID_APPLICATION}" --timestamp "${DMG_PATH}"
fi

echo "✓ DMG: ${DMG_PATH}"
