# Release guide for `test_webrtc_mac_framework`

This project uses a local-only release flow.
Build the macOS artifacts on your own machine, then upload them manually to GitHub Release.

## What gets built locally

Each local release build produces 4 artifacts:
- `test_webrtc_mac_framework-<version>-macos.zip`
- `test_webrtc_mac_framework-<version>-macos.zip.sha256`
- `test_webrtc_mac_framework-<version>-macos.dmg`
- `test_webrtc_mac_framework-<version>-macos.dmg.sha256`

The zip contains:
- `test_webrtc_mac_framework.app`
- `signaling-server/signaling-server.js`
- `signaling-server/package.json`
- `signaling-server/package-lock.json`
- `signaling-server/start-signaling.command`
- `README.txt`

The dmg contains:
- `test_webrtc_mac_framework.app`
- an `Applications` shortcut for drag-install
- a custom Finder background and icon layout for a more polished installer feel

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
- `dist/release/*.zip.sha256`
- `dist/release/*.dmg`
- `dist/release/*.dmg.sha256`

If you want a Finder-friendly installer style package, upload the `.dmg` to GitHub Release.
If you want the full bundle with signaling server included, upload the `.zip` too.
The generated `.dmg` opens with a styled window, custom background, and pre-positioned app / Applications icons.

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

## Recommended release process

From repo root:

```bash
git checkout main
git pull
cd src/s2-prj3-file-trans/test_webrtc_mac_framework
npm ci
npm run release:package -- v1.0.0
git add src/s2-prj3-file-trans/test_webrtc_mac_framework/package.json \
        src/s2-prj3-file-trans/test_webrtc_mac_framework/package-lock.json \
        src/s2-prj3-file-trans/test_webrtc_mac_framework/.gitignore \
        src/s2-prj3-file-trans/test_webrtc_mac_framework/scripts/package-release.sh \
        src/s2-prj3-file-trans/test_webrtc_mac_framework/RELEASE.md \
        src/s2-prj3-file-trans/test_webrtc_mac_framework/test_webrtc_mac_framework.xcodeproj/project.pbxproj
git commit -m "chore: update local macOS release packaging"
git push
```

Then create and push the tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

Then create a GitHub Release manually in the web UI and upload:
- `dist/release/test_webrtc_mac_framework-1.0.0-macos.dmg`
- `dist/release/test_webrtc_mac_framework-1.0.0-macos.dmg.sha256`
- `dist/release/test_webrtc_mac_framework-1.0.0-macos.zip`
- `dist/release/test_webrtc_mac_framework-1.0.0-macos.zip.sha256`

## Manual GitHub Release steps

1. Open your repository on GitHub.
2. Go to `Releases`.
3. Click `Draft a new release`.
4. Choose tag `v1.0.0`.
5. Set title to `test_webrtc_mac_framework v1.0.0`.
6. Upload the dmg, zip, and checksum files.
7. Add release notes, for example:

```text
Unsigned macOS build for coursework/demo use.
If macOS blocks the app on first launch, right click the app and choose Open.
```

8. Publish the release.

## Important notes

- This repo does not rely on GitHub Actions for release builds anymore.
- The project depends on repo-local and machine-local dependencies, so local packaging is the primary release path.
- Signing requires a valid Developer ID Application certificate.
- Notarization requires Apple credentials and works only after successful signing.
- If you publish unsigned builds, users may need to use right click -> Open on first launch.
