# Release guide for `test_webrtc_mac_framework`

This project now supports both:
- standard GitHub Release packaging
- optional macOS `codesign + notarization + stapler`

## What gets published

Each release uploads 2 assets:
- `test_webrtc_mac_framework-<version>-macos.zip`
- `test_webrtc_mac_framework-<version>-macos.sha256`

The zip contains:
- `test_webrtc_mac_framework.app`
- `signaling-server/signaling-server.js`
- `signaling-server/package.json`
- `signaling-server/package-lock.json`
- `signaling-server/start-signaling.command`
- `README.txt`

## Local packaging

From this directory:

```bash
npm run release:package -- v1.0.0
```

Or directly:

```bash
bash ./scripts/package-release.sh v1.0.0
```

Output goes to:
- `dist/release/*.zip`
- `dist/release/*.sha256`

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
5. package the final stapled app into the release zip

## GitHub Release automation

Workflow file:
- `.github/workflows/release-test-webrtc-mac-framework.yml`

### Trigger modes

#### Mode 1: push a semver tag

```bash
git tag v1.0.0
git push origin v1.0.0
```

This will build and publish automatically.

#### Mode 2: run manually from GitHub Actions

Manual workflow inputs now support:
- `version`
- `create_tag`
- `draft`
- `prerelease`
- `notarize`

This means you can trigger a release from the GitHub UI and optionally let the workflow create/push the tag for you.

## Recommended GitHub release setup

Add these repository secrets before enabling signing/notarization in CI:

- `MACOS_CERTIFICATE_P12_BASE64`
- `MACOS_CERTIFICATE_PASSWORD`
- `MACOS_CERTIFICATE_NAME`
- `APPLE_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`
- `APPLE_TEAM_ID`

### Secret meanings

- `MACOS_CERTIFICATE_P12_BASE64`: base64 of your exported Developer ID Application `.p12`
- `MACOS_CERTIFICATE_PASSWORD`: password used when exporting the `.p12`
- `MACOS_CERTIFICATE_NAME`: exact certificate common name, for example `Developer ID Application: Your Name (TEAMID)`
- `APPLE_ID`: Apple account used for notarization
- `APPLE_APP_SPECIFIC_PASSWORD`: app-specific password for that Apple ID
- `APPLE_TEAM_ID`: Apple Developer Team ID

If the signing secrets are missing, CI still produces an unsigned release bundle.
If the notarization secrets are also present and workflow input `notarize=true`, CI produces a signed + notarized bundle.

## Recommended release process

From repo root:

```bash
git checkout main
git pull
cd src/s2-prj3-file-trans/test_webrtc_mac_framework
npm ci
npm run release:package -- v1.0.0
git add .github/workflows/release-test-webrtc-mac-framework.yml \
        src/s2-prj3-file-trans/test_webrtc_mac_framework/package.json \
        src/s2-prj3-file-trans/test_webrtc_mac_framework/package-lock.json \
        src/s2-prj3-file-trans/test_webrtc_mac_framework/.gitignore \
        src/s2-prj3-file-trans/test_webrtc_mac_framework/scripts/package-release.sh \
        src/s2-prj3-file-trans/test_webrtc_mac_framework/RELEASE.md
git commit -m "chore: add macOS release automation"
git push
```

Then choose one of these:

### Option A: traditional tag push

```bash
git tag v1.0.0
git push origin v1.0.0
```

### Option B: manual release from GitHub UI

Use `workflow_dispatch` and set:
- `version=1.0.0`
- `create_tag=true`
- `draft=true/false`
- `prerelease=true/false`
- `notarize=true/false`

## Release UX improvements already included

The workflow now also provides:
- stable release title: `test_webrtc_mac_framework vX.Y.Z`
- automatic GitHub release notes
- optional `draft` support
- optional `prerelease` support
- manual version-driven publishing
- optional automatic tag creation during manual dispatch
- upload of both zip and checksum as workflow artifacts and release assets

## Important notes

- The project depends on repo-local `lib/mac/WebRTC.framework`, so that framework must remain committed in the repository for CI packaging to work.
- Signing requires a valid Developer ID Application certificate.
- Notarization requires Apple credentials and works only after successful signing.
- If you publish unsigned builds, users may need to use right click -> Open on first launch.
