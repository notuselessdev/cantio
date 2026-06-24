#!/usr/bin/env bash
#
# Build an UNSIGNED, ad-hoc-signed, universal (arm64 + x86_64) Cantio.app and
# wrap it in a DMG for Homebrew-cask distribution. No Apple Developer account
# required — the app is ad-hoc signed ("-"), so it runs once the quarantine
# attribute is absent (the user right-clicks → Open, or runs
# `xattr -dr com.apple.quarantine`).
#
# This is the no-notarization sibling of build-release.sh. Prints the DMG path
# and its sha256 (the value the cask needs).
#
# Usage:
#   scripts/build-unsigned.sh
#
# Optional env:
#   BUILD_DIR   Default: build/

set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_DIR="${BUILD_DIR:-build}"
SCHEME="Cantio"
PROJECT="Cantio.xcodeproj"
APP_NAME="Cantio"
DERIVED="${BUILD_DIR}/DerivedData"
APP_PATH="${DERIVED}/Build/Products/Release/${APP_NAME}.app"
DMG_PATH="${BUILD_DIR}/${APP_NAME}.dmg"

echo "→ Regenerating Xcode project"
xcodegen generate

echo "→ Cleaning ${BUILD_DIR}"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

echo "→ Building universal (arm64 + x86_64) Release, unsigned"
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -derivedDataPath "${DERIVED}" \
  -destination "generic/platform=macOS" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "${APP_PATH}" ]]; then
  echo "✗ Build failed: ${APP_PATH} not found" >&2
  exit 1
fi

echo "→ Verifying universal binary"
EXEC_PATH="${APP_PATH}/Contents/MacOS/${APP_NAME}"
lipo -archs "${EXEC_PATH}"
lipo -archs "${EXEC_PATH}" | grep -q "arm64"  || { echo "✗ missing arm64";  exit 1; }
lipo -archs "${EXEC_PATH}" | grep -q "x86_64" || { echo "✗ missing x86_64"; exit 1; }

echo "→ Ad-hoc signing (so launch works once quarantine is cleared)"
codesign --force --deep --sign - "${APP_PATH}"
codesign --verify --deep --strict "${APP_PATH}"

echo "→ Building DMG"
"$(dirname "$0")/make-dmg.sh" "${APP_PATH}" "${DMG_PATH}"

echo
echo "✓ DMG:    ${DMG_PATH}"
echo "  sha256: $(shasum -a 256 "${DMG_PATH}" | awk '{print $1}')"
echo "  version: $(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "${APP_PATH}/Contents/Info.plist")"
