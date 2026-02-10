# SpeakSmooth

SpeakSmooth is a macOS menu bar app that captures your speech, improves grammar/naturalness, and saves the final sentence to Microsoft To Do.

## What it does

- Captures microphone audio with `AVAudioEngine`
- Detects speech segments with Silero VAD (`RealTimeCutVADLibrary`)
- Transcribes locally with WhisperKit (`openai/whisper-base.en`)
- Rewrites text using Apple Foundation Models (primary) or OpenRouter (fallback)
- Saves the revised sentence + corrections to Microsoft To Do via Graph API

## Requirements

- macOS 14+
- Xcode 16+
- XcodeGen (`brew install xcodegen`)
- mise (optional, recommended)

## Local setup

1. Generate project:

```bash
xcodegen generate
```

2. Configure app secrets/settings:

- Set `MSALClientId` in `SpeakSmooth/Resources/Info.plist`
- Keep redirect URI as `msauth.com.speaksmooth.app://auth` in Azure app config
- (Optional) Add OpenRouter API key in app Settings UI for rewrite fallback

3. Build and test:

```bash
xcodebuild -project SpeakSmooth.xcodeproj -scheme SpeakSmooth build
xcodebuild test -project SpeakSmooth.xcodeproj -scheme SpeakSmooth -destination 'platform=macOS'
```

## Dev commands (mise)

This repo includes `mise.toml`:

- `mise run dev` (alias `mise d`) - debug build
- `mise run test` (alias `mise t`) - run tests
- `mise run lint` (alias `mise l`) - run SwiftLint if available, otherwise compile-check

First time in this repo:

```bash
mise trust
```

## Release automation

### 1) release-please on `main`

Workflow: `.github/workflows/release-please.yml`

- Runs on pushes to `main`
- Opens/updates release PR based on conventional commits
- On merge, creates a GitHub Release + tag

Related files:

- `release-please-config.json`
- `.release-please-manifest.json`

### 2) Homebrew publish on release

Workflow: `.github/workflows/homebrew-release.yml`

- Triggers on `release.published`
- Builds Release app, zips `SpeakSmooth.app`, uploads release asset
- Updates Homebrew tap cask (`Casks/speak-smooth.rb`) and pushes to tap repo

Required GitHub settings:

- Repository variable `HOMEBREW_TAP_REPO` (example: `your-org/homebrew-tap`)
- Repository secret `HOMEBREW_TAP_GITHUB_TOKEN` (token with push access to tap repo)
- Optional secret `RELEASE_PLEASE_TOKEN` (PAT, if you do not want to rely on `GITHUB_TOKEN`)

## Notes

- The app is a menu bar utility (`LSUIElement=true`), so no dock icon.
- Tests cover core logic; microphone/auth/network end-to-end behavior still requires manual verification.
