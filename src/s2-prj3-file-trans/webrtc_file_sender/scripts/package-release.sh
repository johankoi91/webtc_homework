#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/webrtc_file_sender.xcodeproj"
SCHEME="webrtc_file_sender"
CONFIGURATION="Release"
BUILD_DIR="$ROOT_DIR/dist/build"
STAGE_DIR="$ROOT_DIR/dist/stage"
RELEASE_DIR="$ROOT_DIR/dist/release"
DMG_DIR="$ROOT_DIR/dist/dmg"
DMG_MOUNT_DIR="$ROOT_DIR/dist/dmg-mount"
SIGNALING_DIR="$STAGE_DIR/signaling-server"
APP_NAME="webrtc_file_sender.app"
APP_PATH="$STAGE_DIR/$APP_NAME"
APP_SOURCE="$BUILD_DIR/DerivedData/Build/Products/$CONFIGURATION/$APP_NAME"

TAG="${1:-${GITHUB_REF_NAME:-}}"
if [[ -z "$TAG" ]]; then
  echo "Usage: $0 <tag-or-version>"
  exit 1
fi

VERSION="${TAG#v}"
ARTIFACT_BASENAME="webrtc_file_sender-${VERSION}-macos"
RELEASE_SUPPORT_DIR="$RELEASE_DIR/$ARTIFACT_BASENAME"
ZIP_PATH="$RELEASE_DIR/$ARTIFACT_BASENAME.zip"
ZIP_CHECKSUM_PATH="$RELEASE_DIR/$ARTIFACT_BASENAME.zip.sha256"
DMG_PATH="$RELEASE_SUPPORT_DIR/$ARTIFACT_BASENAME.dmg"
DMG_TEMP_PATH="$RELEASE_SUPPORT_DIR/$ARTIFACT_BASENAME-temp.dmg"
DMG_CHECKSUM_PATH="$RELEASE_SUPPORT_DIR/$ARTIFACT_BASENAME.dmg.sha256"
NOTARIZATION_ZIP_PATH="$RELEASE_SUPPORT_DIR/$ARTIFACT_BASENAME-notarization.zip"
DMG_VOLUME_NAME="webrtc_file_sender ${VERSION}"
DMG_BACKGROUND_DIR="$DMG_DIR/.background"
DMG_BACKGROUND_PPM="$DMG_BACKGROUND_DIR/background.ppm"
DMG_BACKGROUND_PNG="$DMG_BACKGROUND_DIR/background.png"
APPLICATIONS_SYMLINK="$DMG_DIR/Applications"

ENABLE_CODESIGN="${ENABLE_CODESIGN:-false}"
ENABLE_NOTARIZATION="${ENABLE_NOTARIZATION:-false}"
MACOS_CERTIFICATE_NAME="${MACOS_CERTIFICATE_NAME:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_APP_SPECIFIC_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
DMG_CUSTOMIZED="false"

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

cleanup() {
  if [[ -d "$DMG_MOUNT_DIR" ]] && mount | grep -q "on $DMG_MOUNT_DIR "; then
    hdiutil detach "$DMG_MOUNT_DIR" -quiet || true
  fi
  rm -rf "$DMG_MOUNT_DIR"
  rm -f "$DMG_TEMP_PATH"
}

trap cleanup EXIT

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

create_dmg_background() {
  mkdir -p "$DMG_BACKGROUND_DIR"

  python3 - "$DMG_BACKGROUND_PPM" <<'PY'
import math
import sys

out_path = sys.argv[1]
width = 700
height = 440

left = (11, 15, 26)
right = (23, 46, 84)
accent = (78, 225, 195)
glow = (255, 186, 104)

with open(out_path, "w", encoding="ascii") as f:
    f.write(f"P3\n{width} {height}\n255\n")
    for y in range(height):
        row = []
        for x in range(width):
            mix = x / (width - 1)
            base = [round(left[i] * (1 - mix) + right[i] * mix) for i in range(3)]

            cx1, cy1 = width * 0.22, height * 0.32
            d1 = math.hypot(x - cx1, y - cy1)
            glow1 = max(0.0, 1.0 - d1 / 220.0)

            cx2, cy2 = width * 0.78, height * 0.72
            d2 = math.hypot(x - cx2, y - cy2)
            glow2 = max(0.0, 1.0 - d2 / 190.0)

            col = []
            for i in range(3):
                value = base[i]
                value += accent[i] * (glow1 ** 2) * 0.55
                value += glow[i] * (glow2 ** 2) * 0.35
                value = max(0, min(255, round(value)))
                col.append(str(value))
            row.append(" ".join(col))
        f.write(" ".join(row) + "\n")
PY

  sips -s format png "$DMG_BACKGROUND_PPM" --out "$DMG_BACKGROUND_PNG" >/dev/null
  rm -f "$DMG_BACKGROUND_PPM"
}

customize_mounted_dmg() {
  local mounted_background_path="$DMG_MOUNT_DIR/.background/background.png"

  osascript <<EOF
set dmgFolder to POSIX file "$DMG_MOUNT_DIR" as alias
set bgFile to POSIX file "$mounted_background_path" as alias

tell application "Finder"
  activate
  open dmgFolder
  repeat 20 times
    try
      set dmgWindow to container window of dmgFolder
      exit repeat
    on error
      delay 0.5
    end try
  end repeat

  set dmgWindow to container window of dmgFolder
  set current view of dmgWindow to icon view
  try
    set toolbar visible of dmgWindow to false
  end try
  try
    set statusbar visible of dmgWindow to false
  end try
  set the bounds of dmgWindow to {140, 120, 840, 560}

  set viewOptions to the icon view options of dmgWindow
  set arrangement of viewOptions to not arranged
  set icon size of viewOptions to 128
  set text size of viewOptions to 14
  set background picture of viewOptions to bgFile

  set position of item "$APP_NAME" of dmgFolder to {180, 210}
  set position of item "Applications" of dmgFolder to {520, 210}
  update dmgFolder without registering applications
  delay 1
  try
    close dmgWindow
  end try
end tell
EOF

  DMG_CUSTOMIZED="true"
}

create_dmg() {
  rm -rf "$DMG_DIR" "$DMG_MOUNT_DIR"
  mkdir -p "$DMG_DIR" "$DMG_MOUNT_DIR"
  cp -R "$APP_PATH" "$DMG_DIR/$APP_NAME"
  ln -s /Applications "$APPLICATIONS_SYMLINK"
  create_dmg_background

  rm -f "$DMG_TEMP_PATH" "$DMG_PATH"
  hdiutil create \
    -volname "$DMG_VOLUME_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov \
    -format UDRW \
    "$DMG_TEMP_PATH" >/dev/null

  hdiutil attach \
    -readwrite \
    -noverify \
    -noautoopen \
    -mountpoint "$DMG_MOUNT_DIR" \
    "$DMG_TEMP_PATH" >/dev/null

  customize_mounted_dmg
  sync
  hdiutil detach "$DMG_MOUNT_DIR" -quiet
  rm -rf "$DMG_MOUNT_DIR"

  hdiutil convert "$DMG_TEMP_PATH" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null
}

write_checksums() {
  rm -f "$ZIP_CHECKSUM_PATH" "$DMG_CHECKSUM_PATH"
  shasum -a 256 "$ZIP_PATH" | awk '{print $1}' > "$ZIP_CHECKSUM_PATH"
  shasum -a 256 "$DMG_PATH" | awk '{print $1}' > "$DMG_CHECKSUM_PATH"
}

populate_release_support_dir() {
  rm -rf "$RELEASE_SUPPORT_DIR"
  mkdir -p "$RELEASE_SUPPORT_DIR/signaling-server"

  cp "$ROOT_DIR/signaling-server.js" "$RELEASE_SUPPORT_DIR/signaling-server/"
  cp "$ROOT_DIR/package.json" "$ROOT_DIR/package-lock.json" "$RELEASE_SUPPORT_DIR/signaling-server/"
  cp "$SIGNALING_DIR/start-signaling.command" "$RELEASE_SUPPORT_DIR/signaling-server/"

  cat > "$RELEASE_SUPPORT_DIR/DEPLOY_SIGNALLING_SERVER.md" <<EOF
# webrtc_file_sender signaling-server deployment guide

Version: $VERSION

## Directory contents
- signaling-server/signaling-server.js
- signaling-server/package.json
- signaling-server/package-lock.json
- signaling-server/start-signaling.command

## Local deployment
Use this when the signaling server runs on the same machine, or on a Mac in the same local network.

1. Open Terminal
2. Run:

       cd "$(basename "$RELEASE_SUPPORT_DIR")/signaling-server"
       npm ci
       node signaling-server.js

3. Keep the process running while both sender/receiver apps connect

## Quick start on macOS
- You can also double click ./start-signaling.command from Finder.
- The script runs npm ci and then starts node signaling-server.js.

## Prerequisites for using the dmg-installed app
1. lib/mac/ in this repository must already contain the currently built WebRTC framework used by this project.
2. You must deploy and start the local signaling-server before trying to connect peers.

## Network notes
- The default signaling server listens on the port defined in signaling-server.js.
- Make sure both Macs can reach this host and port over the same local network.
- If macOS firewall prompts for Node.js access, choose Allow.

## Production-style deployment suggestion
- Copy the signaling-server/ folder to a dedicated host or Mac mini.
- Install Node.js.
- Run npm ci once.
- Start with node signaling-server.js.
- Keep it alive with tmux, screen, launchd, or another process manager.

## App-side usage
- In the app, point both peers to the same signaling server address.
- After signaling succeeds, WebRTC handles the peer-to-peer data path directly.
EOF
}

require_command xcodebuild
require_command npm
require_command shasum
require_command hdiutil
require_command osascript
require_command sips
require_command python3

rm -rf "$BUILD_DIR" "$STAGE_DIR" "$DMG_DIR" "$DMG_MOUNT_DIR" "$RELEASE_SUPPORT_DIR"
mkdir -p "$BUILD_DIR" "$SIGNALING_DIR" "$RELEASE_DIR" "$RELEASE_SUPPORT_DIR"

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

Also generated under dist/release:
- $(basename "$RELEASE_SUPPORT_DIR")/signaling-server/
- $(basename "$RELEASE_SUPPORT_DIR")/DEPLOY_SIGNALLING_SERVER.md
- $(basename "$DMG_PATH")

Notes:
- Signed/notarized output depends on release environment secrets.
- If Gatekeeper blocks an unsigned build, use right click -> Open.
EOF

populate_release_support_dir

rm -f "$ZIP_PATH" "$DMG_PATH" "$DMG_CHECKSUM_PATH"
create_dmg
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$RELEASE_SUPPORT_DIR" "$ZIP_PATH"
write_checksums

echo "Created: $ZIP_PATH"
echo "Created: $DMG_PATH"
echo "Checksum: $ZIP_CHECKSUM_PATH"
echo "Checksum: $DMG_CHECKSUM_PATH"
echo "Bundle status: $BUNDLE_STATUS"
echo "DMG customized: $DMG_CUSTOMIZED"
