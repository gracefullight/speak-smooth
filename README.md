# SpeakSmooth

SpeakSmooth is a macOS menu bar app that captures your speech, improves grammar/naturalness, and saves the final sentence to Apple Reminders.

## Installation

Install with Homebrew Cask:

```bash
brew install --cask gracefullight/homebrew-tap/speak-smooth
```

Or tap first, then install:

```bash
brew tap gracefullight/homebrew-tap
brew install --cask speak-smooth
```

Update to the latest release:

```bash
brew upgrade --cask speak-smooth
```

## What it does

- Captures microphone audio with `AVAudioEngine`
- Detects speech segments with Silero VAD (`RealTimeCutVADLibrary`)
- Transcribes locally with Apple on-device Speech recognition, with WhisperKit as a fallback
- Rewrites text using Apple Foundation Models (primary) or OpenRouter (fallback)
- Saves the revised sentence + corrections to an Apple Reminders list

## Requirements

- macOS 15.4+ (required by the bundled voice activity detection framework)
- Xcode 26+ to build; Apple Intelligence rewriting requires macOS 26 and a supported device
- XcodeGen (`brew install xcodegen`)
- mise (optional, recommended)

## Local setup

1. Generate project:

```bash
xcodegen generate
```

2. Configure app secrets/settings:

- Open Settings, enable Reminders access, and select a writable list
- (Optional) Add an OpenRouter API key and click **Save Key**. The key is stored in macOS Keychain
- Click **Start Recording** and grant microphone and speech recognition access when requested
- Wait for speech recognition preparation to finish before speaking. Whisper fallback may download a model on first use

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
- **Stop Recording** turns off the microphone while queued sentences finish processing.
- Changes to the destination list and silence timeout apply to the next recording. API key changes apply to the next sentence processed.
- Failed reminder saves remain in the popover. Select a writable list and use **Retry Save**, or copy the unsaved text before quitting. Unsaved sentences are held only for the current app session.
- When rewriting is unavailable, the original transcript is saved. With OpenRouter configured, transcript text is sent to OpenRouter and its model provider; microphone audio is processed locally.
- The popover provides sentence copying, an **Open Reminders** button, and a quit button that checks for unfinished work.
- Tests cover settings persistence with an isolated credential store, sequential processing, save recovery, response parsing, audio segmentation, and view rendering. Real microphone capture, system permission dialogs, Apple Intelligence, live OpenRouter requests, and real Reminders writes require manual verification.
- Release builds use Xcode 26.3 on the [GitHub macOS 15 runner](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md). Homebrew gates installation to Sequoia or later; the app requires at least 15.4.
