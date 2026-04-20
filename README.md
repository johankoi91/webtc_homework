# webtc_homework

This repository contains WebRTC and build-training homework projects.

## Quick navigation

- `src/s1/`: GN / Ninja learning exercises
- `src/s2-prj3-file-trans/`: main macOS WebRTC file transfer projec
- `include/`: shared headers / support files
- `lib/`: local frameworks and libraries used by the projects


## Quick webrtc_file_sender app use guide

To quickly run the project from the GitHub release page:

- Open [v1.0.0 release page](https://github.com/johankoi91/webtc_homework/releases/tag/v1.0.0)
- Download `webrtc_file_sender-1.0.0-macos.zip`
- Unzip it
- Open `webrtc_file_sender-1.0.0-macos/`

Inside that directory you will get:
- `webrtc_file_sender-1.0.0-macos.dmg`
- `webrtc_file_sender-1.0.0-macos.dmg.sha256`
- `DEPLOY_SIGNALLING_SERVER.md`
- `signaling-server/`

### Quick run steps

1. Open `webrtc_file_sender-1.0.0-macos/signaling-server/`.
2. Start the signaling server:

```bash
cd signaling-server
./start-signaling.command
```

3. Keep the signaling server process running.
4. Open `webrtc_file_sender-1.0.0-macos.dmg`.
5. Drag `webrtc_file_sender.app` into `Applications`.
6. Launch the app on both Macs.
7. Make sure both peers point to the same local signaling server.



## Local macOS packaging

Before packaging, installing, or trying to run the app in this coursework setup, make sure these two prerequisites are satisfied:
- `lib/mac/` in this repository already contains the currently built WebRTC framework used by this project.

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
- `webrtc_file_sender-<version>-macos/`
  - `webrtc_file_sender-<version>-macos.dmg`
  - `webrtc_file_sender-<version>-macos.dmg.sha256`
  - `DEPLOY_SIGNALLING_SERVER.md`
  - `signaling-server/`

The zip contains:
- `webrtc_file_sender-<version>-macos.dmg`
- `DEPLOY_SIGNALLING_SERVER.md`
- `signaling-server/`

This zip is now a release container for the macOS installer plus the signaling-server deployment materials.
DEPLOY_SIGNALLING_SERVER.md contains the signaling-server deployment notes.
You must deploy and start the local `signaling-server` before trying to connect peers.




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
8. Publish the release.
