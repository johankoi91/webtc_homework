# webtc_homework

This repository contains WebRTC and build-training homework projects.

## Quick navigation

- `src/s2-prj3-file-trans/webrtc_file_sender/`: main macOS WebRTC file transfer project
- `src/s2-prj3-file-trans/webrtc_file_sender/webrtc_file_sender.xcodeproj`: Xcode project file
- `src/s2-prj3-file-trans/webrtc_file_sender/signaling-server.js`: local signaling server
- `src/s2-prj3-file-trans/webrtc_file_sender/scripts/package-release.sh`: local release packaging script
- `src/s1/build_training/`: GN / Ninja learning exercises
- `src/s1/gn_ninja/`: notes for the GN / Ninja training section
- `include/`: shared headers / support files
- `lib/`: local frameworks and libraries used by the projects

## Repository structure

### `src/s1/`
Build system training content.

- `src/s1/build_training/`: step-by-step GN / Ninja experiments
- `src/s1/gn_ninja/`: markdown notes and learning summaries

### `src/s2-prj3-file-trans/`
Project work for WebRTC-based file transfer.

- `src/s2-prj3-file-trans/webrtc_file_sender/`: macOS app project root
- `src/s2-prj3-file-trans/webrtc_file_sender/webrtc_file_sender/`: Objective-C / Cocoa app source files
- `src/s2-prj3-file-trans/webrtc_file_sender/webrtc_file_sender.xcodeproj/`: Xcode project configuration
- `src/s2-prj3-file-trans/webrtc_file_sender/scripts/`: local packaging and release scripts

## Main project in this repository

The primary app project is:

- `src/s2-prj3-file-trans/webrtc_file_sender/`

It includes:
- a macOS app target: `webrtc_file_sender.app`
- a local signaling server: `signaling-server.js`
- local packaging scripts for `.zip` and `.dmg`
- optional local signing / notarization support

## Local macOS packaging

From the project directory:

```bash
cd src/s2-prj3-file-trans/webrtc_file_sender
npm ci
npm run release:package -- v1.0.0
```

This produces release artifacts under:

```bash
src/s2-prj3-file-trans/webrtc_file_sender/dist/release/
```

Artifacts include:
- `webrtc_file_sender-<version>-macos.zip`
- `webrtc_file_sender-<version>-macos.zip.sha256`
- `webrtc_file_sender-<version>-macos.dmg`
- `webrtc_file_sender-<version>-macos.dmg.sha256`

The zip contains:
- `webrtc_file_sender.app`
- `signaling-server/signaling-server.js`
- `signaling-server/package.json`
- `signaling-server/package-lock.json`
- `signaling-server/start-signaling.command`
- `README.txt`

The dmg contains:
- `webrtc_file_sender.app`
- an `Applications` shortcut for drag-install
- a custom Finder background and icon layout for a more polished installer feel

The generated `.dmg` uses a styled Finder window and drag-to-Applications layout.

## Release download guide

When a release is published on GitHub, prefer downloading these files from the `Releases` page:

### For normal macOS users
Download:
- `webrtc_file_sender-<version>-macos.dmg`
- optionally `webrtc_file_sender-<version>-macos.dmg.sha256`

Use the `.dmg` if you want the normal drag-to-Applications installation flow.

### For users who also need the signaling bundle
Download:
- `webrtc_file_sender-<version>-macos.zip`
- optionally `webrtc_file_sender-<version>-macos.zip.sha256`

Use the `.zip` if you want:
- the app bundle
- the local signaling server
- the packaged startup script for signaling

### Checksum verification
If you want to verify an artifact after download:

```bash
shasum -a 256 webrtc_file_sender-1.0.0-macos.dmg
cat webrtc_file_sender-1.0.0-macos.dmg.sha256
```

Or for the zip:

```bash
shasum -a 256 webrtc_file_sender-1.0.0-macos.zip
cat webrtc_file_sender-1.0.0-macos.zip.sha256
```

## Local signed build

If you already have a valid Developer ID Application certificate in your local keychain:

```bash
export ENABLE_CODESIGN=true
export MACOS_CERTIFICATE_NAME="Developer ID Application: Your Name (TEAMID)"
bash ./scripts/package-release.sh v1.0.0
```

## Local signed + notarized build

```bash
export ENABLE_CODESIGN=true
export ENABLE_NOTARIZATION=true
export MACOS_CERTIFICATE_NAME="Developer ID Application: Your Name (TEAMID)"
export APPLE_ID="your-apple-id@example.com"
export APPLE_APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
export APPLE_TEAM_ID="TEAMID"
bash ./scripts/package-release.sh v1.0.0
```

When notarization is enabled, the script will:
1. sign the app
2. submit it with `notarytool`
3. wait for notarization to finish
4. staple the notarization ticket to the app
5. package the final stapled app into both the release zip and dmg

## GitHub Release flow

This repository now uses a **local-only release flow** for the macOS app.

Reason:
- some build dependencies are only available locally and are not committed to GitHub
- GitHub Actions is not used for release builds anymore

Recommended release steps:

```bash
git checkout main
git pull
cd src/s2-prj3-file-trans/webrtc_file_sender
npm ci
npm run release:package -- v1.0.0
git tag v1.0.0
git push origin v1.0.0
```

Then create a GitHub Release manually and upload:
- `dist/release/webrtc_file_sender-1.0.0-macos.dmg`
- `dist/release/webrtc_file_sender-1.0.0-macos.dmg.sha256`
- `dist/release/webrtc_file_sender-1.0.0-macos.zip`
- `dist/release/webrtc_file_sender-1.0.0-macos.zip.sha256`

## Manual GitHub Release steps

1. Open your repository on GitHub.
2. Go to `Releases`.
3. Click `Draft a new release`.
4. Choose tag `v1.0.0`.
5. Set title to `webrtc_file_sender v1.0.0`.
6. Upload the dmg, zip, and checksum files.
7. Add release notes, for example:

```text
Unsigned macOS build for coursework/demo use.
If macOS blocks the app on first launch, right click the app and choose Open.
```

8. Publish the release.

## Notes

- Unsigned macOS builds may require right click -> `Open` on first launch.
- Signing requires a valid Developer ID Application certificate.
- Notarization requires Apple credentials and works only after successful signing.
- The project depends on repo-local and machine-local dependencies, so local packaging is the primary release path.
