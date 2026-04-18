#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/test_webrtc_mac_framework.xcodeproj"
SCHEME="test_webrtc_mac_framework"
CONFIGURATION="Release"
BUILD_DIR="$ROOT_DIR/dist/build"
STAGE_DIR="$ROOT_DIR/dist/stage"
RELEASE_DIR="$ROOT_DIR/dist/release"
SIGNALING_DIR="$STAGE_DIR/signaling-server"
APP_NAME="test_webrtc_mac_framework.app"
APP_PATH="$STAGE_DIR/$APP_NAME"
APP_SOURCE="$BUILD_DIR/DerivedData/Build/Products/$CONFIGURATION/$APP_NAME"

TAG="${1:-${GITHUB_REF_NAME:-}}"
if [[ -z "$TAG" ]]; then
  echo "Usage: $0 <tag-or-version>"
  exit 1
fi

VERSION="${TAG#v}"
ZIP_BASENAME="test_webrtc_mac_framework-${VERSION}-macos"
ZIP_PATH="$RELEASE_DIR/$ZIP_BASENAME.zip"
CHECKSUM_PATH="$RELEASE_DIR/$ZIP_BASENAME.sha256"
NOTARIZATION_ZIP_PATH="$RELEASE_DIR/$ZIP_BASENAME-notarization.zip"

ENABLE_CODESIGN="${ENABLE_CODESIGN:-false}"
ENABLE_NOTARIZATION="${ENABLE_NOTARIZATION:-false}"
MACOS_CERTIFICATE_NAME="${MACOS_CERTIFICATE_NAME:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_APP_SPECIFIC_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 is required but not installed"
    exit 1
  fi
}

require_env() {
  local name="$1"
  local value="${!name:-}"
  if [[ -z "$value" ]]; then
    echo "$name is required"
    exit 1
  fi
}

codesign_app() {
  require_env MACOS_CERTIFICATE_NAME

  echo "Signing app with Developer ID certificate"
  /usr/bin/codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --sign "$MACOS_CERTIFICATE_NAME" \
    "$APP_PATH"

  /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
  /usr/sbin/spctl --assess --type execute --verbose=2 "$APP_PATH"
}

notarize_app() {
  require_command xcrun
  require_env APPLE_ID
  require_env APPLE_APP_SPECIFIC_PASSWORD
  require_env APPLE_TEAM_ID

  echo "Preparing notarization archive"
  rm -f "$NOTARIZATION_ZIP_PATH"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$NOTARIZATION_ZIP_PATH"

  echo "Submitting app for notarization"
  xcrun notarytool submit "$NOTARIZATION_ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait

  echo "Stapling notarization ticket"
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"

  rm -f "$NOTARIZATION_ZIP_PATH"
}

require_command xcodebuild
require_command npm
require_command shasum

rm -rf "$BUILD_DIR" "$STAGE_DIR"
mkdir -p "$BUILD_DIR" "$SIGNALING_DIR" "$RELEASE_DIR"

npm ci --prefix "$ROOT_DIR"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' \
  build

if [[ ! -d "$APP_SOURCE" ]]; then
  echo "Built app not found at $APP_SOURCE"
  exit 1
fi

cp -R "$APP_SOURCE" "$APP_PATH"
cp "$ROOT_DIR/signaling-server.js" "$SIGNALING_DIR/"
cp "$ROOT_DIR/package.json" "$ROOT_DIR/package-lock.json" "$SIGNALING_DIR/"

cat > "$SIGNALING_DIR/start-signaling.command" <<'EOF'
#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
npm ci
node signaling-server.js
EOF
chmod +x "$SIGNALING_DIR/start-signaling.command"

BUNDLE_STATUS="unsigned"
if [[ "$ENABLE_CODESIGN" == "true" ]]; then
  codesign_app
  BUNDLE_STATUS="signed"
fi

if [[ "$ENABLE_NOTARIZATION" == "true" ]]; then
  notarize_app
  BUNDLE_STATUS="signed + notarized"
fi

cat > "$STAGE_DIR/README.txt" <<EOF
Test WebRTC macOS release bundle
Version: $VERSION
Bundle status: $BUNDLE_STATUS

Contents:
- $APP_NAME
- signaling-server/signaling-server.js
- signaling-server/start-signaling.command

Quick start:
1. Open Terminal in signaling-server and run ./start-signaling.command
2. Launch $APP_NAME on both Macs
3. Keep both devices on the same signaling endpoint

Notes:
- Signed/notarized output depends on release environment secrets.
- If Gatekeeper blocks an unsigned build, use right click -> Open.
EOF

rm -f "$ZIP_PATH" "$CHECKSUM_PATH"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$STAGE_DIR" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH" | awk '{print $1}' > "$CHECKSUM_PATH"

echo "Created: $ZIP_PATH"
echo "Checksum: $CHECKSUM_PATH"
echo "Bundle status: $BUNDLE_STATUS"
