#!/usr/bin/env bash
#
# Build a signed, hardened, notarized, universal Floric.app and wrap it in a
# DMG ready for distribution.
#
# Required env vars:
#   DEVELOPER_ID_APPLICATION  Common-name of the Developer ID Application cert
#                             (e.g. "Developer ID Application: Acme LLC (TEAMID)").
#   APPLE_TEAM_ID             Apple Developer team ID (10-char string).
#
# Required for notarization (skip with SKIP_NOTARIZE=1 for offline test runs):
#   APPLE_ID                  Apple ID e-mail.
#   APPLE_APP_PASSWORD        App-specific password from appleid.apple.com.
#
# Optional:
#   CONFIGURATION             Default: Release.
#   BUILD_DIR                 Default: build/.
#
# Usage:
#   scripts/build-release.sh

set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-Release}"
BUILD_DIR="${BUILD_DIR:-build}"
SCHEME="Floric"
PROJECT="Floric.xcodeproj"
APP_NAME="Floric"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"
APP_PATH="${EXPORT_DIR}/${APP_NAME}.app"

: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION (e.g. 'Developer ID Application: Acme LLC (TEAMID)')}"
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID (10-char Apple Developer team ID)}"

echo "→ Regenerating Xcode project"
xcodegen generate

echo "→ Cleaning ${BUILD_DIR}"
rm -rf "${BUILD_DIR}"
mkdir -p "${EXPORT_DIR}"

echo "→ Archiving universal (arm64 + x86_64) ${CONFIGURATION} build"
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "generic/platform=macOS" \
  -archivePath "${ARCHIVE_PATH}" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="${DEVELOPER_ID_APPLICATION}" \
  DEVELOPMENT_TEAM="${APPLE_TEAM_ID}" \
  ENABLE_HARDENED_RUNTIME=YES \
  archive | xcbeautify || true

if [[ ! -d "${ARCHIVE_PATH}" ]]; then
  echo "✗ Archive failed: ${ARCHIVE_PATH} not found" >&2
  exit 1
fi

echo "→ Exporting .app from archive"
EXPORT_PLIST="${BUILD_DIR}/ExportOptions.plist"
cat > "${EXPORT_PLIST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>manual</string>
  <key>teamID</key><string>${APPLE_TEAM_ID}</string>
  <key>signingCertificate</key><string>${DEVELOPER_ID_APPLICATION}</string>
</dict>
</plist>
PLIST

xcodebuild \
  -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportPath "${EXPORT_DIR}" \
  -exportOptionsPlist "${EXPORT_PLIST}"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "✗ Export failed: ${APP_PATH} not found" >&2
  exit 1
fi

echo "→ Verifying universal binary"
EXEC_PATH="${APP_PATH}/Contents/MacOS/${APP_NAME}"
lipo -archs "${EXEC_PATH}"
if ! lipo -archs "${EXEC_PATH}" | grep -q "arm64" || ! lipo -archs "${EXEC_PATH}" | grep -q "x86_64"; then
  echo "✗ Binary is not universal" >&2
  exit 1
fi

echo "→ Verifying signature & hardened runtime"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
codesign --display --verbose=2 "${APP_PATH}" 2>&1 | grep -q "flags=.*runtime" \
  || { echo "✗ Hardened runtime not enabled"; exit 1; }

if [[ "${SKIP_NOTARIZE:-0}" != "1" ]]; then
  : "${APPLE_ID:?Set APPLE_ID for notarization (or SKIP_NOTARIZE=1)}"
  : "${APPLE_APP_PASSWORD:?Set APPLE_APP_PASSWORD for notarization (or SKIP_NOTARIZE=1)}"

  echo "→ Notarizing"
  ZIP_PATH="${BUILD_DIR}/${APP_NAME}.zip"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"
  xcrun notarytool submit "${ZIP_PATH}" \
    --apple-id "${APPLE_ID}" \
    --password "${APPLE_APP_PASSWORD}" \
    --team-id "${APPLE_TEAM_ID}" \
    --wait

  echo "→ Stapling ticket"
  xcrun stapler staple "${APP_PATH}"
  xcrun stapler validate "${APP_PATH}"
else
  echo "→ Skipping notarization (SKIP_NOTARIZE=1)"
fi

echo "→ Building DMG"
"$(dirname "$0")/make-dmg.sh" "${APP_PATH}" "${BUILD_DIR}/${APP_NAME}.dmg"

echo "✓ Done: ${BUILD_DIR}/${APP_NAME}.dmg"
