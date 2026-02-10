# SpeakSmooth — Design Document

> macOS menu bar app: voice input → STT → English rewrite → Microsoft To Do

**Date**: 2026-02-11
**Status**: Approved

---

## 1. Goal

A macOS menu bar app that:
1. Captures mic input
2. Detects speech segments via VAD + configurable silence timeout
3. Transcribes speech to English text (local STT)
4. Rewrites the transcript for grammar and natural spoken expression
5. Saves the rewritten sentence to a Microsoft To Do list

---

## 2. User-Configurable Settings

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `silenceTimeoutSeconds` | `Double` | `3.0` | Seconds of silence before segment is finalized |
| `selectedTodoListId` | `String?` | `nil` | Microsoft To Do target list |
| `selectedTodoListName` | `String?` | `nil` | Display name of selected list |
| `openRouterApiKey` | `String?` | `nil` | Optional, Keychain-stored, for LLM fallback |

---

## 3. Tech Stack

| Component | Choice | Rationale |
|-----------|--------|-----------|
| App / UI | Swift 6 + SwiftUI | Native macOS, MenuBarExtra support |
| Audio Capture | AVAudioEngine | First-class macOS API, real-time PCM tap |
| VAD | RealTimeCutVADLibrary (Silero v5 + WebRTC) | ML-based accuracy, noise suppression, delegate API |
| STT | WhisperKit (Argmax) | Apple-optimized CoreML, 111x realtime, native Swift SPM |
| Rewrite (primary) | Apple Foundation Models (macOS 26+) | On-device, free, offline, private |
| Rewrite (fallback) | OpenRouter API (URLSession) | Cloud LLM, free tier available |
| Auth | MSAL for iOS/macOS | Official Microsoft OAuth SDK |
| To Do API | Microsoft Graph REST (URLSession) | Minimal surface: GET lists, POST task |

### SPM Dependencies

| Package | Source |
|---------|--------|
| `WhisperKit` | `github.com/argmaxinc/WhisperKit` |
| `RealTimeCutVADLibrary` | `github.com/helloooideeeeea/RealTimeCutVADLibrary` |
| `MSAL` | `github.com/AzureAD/microsoft-authentication-library-for-objc` |

No additional LLM SDK. `FoundationModels` is a system framework; OpenRouter uses raw `URLSession`.

### Build Requirements

- Xcode 16+, Swift 6
- macOS 14+ deployment target (MenuBarExtra, WhisperKit)
- macOS 26+ for Apple Foundation Models (graceful fallback to OpenRouter)
- App Sandbox: Audio Input, Outgoing Connections (Client)
- Keychain Groups: `com.microsoft.identity.universalstorage`

### Azure AD App Registration

- App type: Public client / Mobile & desktop
- Redirect URI: `msauth.com.speaksmooth.app://auth`
- API permissions: `Tasks.ReadWrite` (delegated)

---

## 4. Architecture

### Pipeline

```
[Mic] → AVAudioEngine (48kHz Float32 PCM)
     → RealTimeCutVADLibrary (Silero v5 + WebRTC denoise)
     → Segment Builder (silenceTimeoutSeconds cutoff)
     → WhisperKit (local STT, base.en model)
     → LLM Rewrite (Apple Foundation Models → OpenRouter fallback)
     → Microsoft Graph (POST /me/todo/lists/{id}/tasks)
     → UI Feedback (popover status update)
```

### State Machine

```
Idle ──[tap mic]──→ Listening ──[voice detected]──→ Speaking
  ↑                                                    │
  │                              [silence detected]    ↓
  │                                          SilenceCountdown
  │                              [silenceTimeoutSeconds elapsed]
  │                                                    ↓
  │                                            FinalizingSTT
  │                                                    ↓
  │                                               Rewriting
  │                                                    ↓
  │                                                 Saving
  └──────────────[done / error]────────────────────────┘
```

Recording persists independently of popover lifecycle. Starting recording changes the menu bar icon; closing the popover does not stop recording.

---

## 5. Project Structure

```
SpeakSmooth/
├── SpeakSmoothApp.swift            # @main, MenuBarExtra scene, owns AppState
├── Models/
│   ├── AppState.swift              # @Observable, PipelineState enum + transitions
│   └── Settings.swift              # UserDefaults-backed settings
├── Audio/
│   ├── AudioCaptureManager.swift   # AVAudioEngine setup, mic permission, PCM tap
│   └── SegmentBuilder.swift        # Wraps RealTimeCutVADLibrary, applies silenceTimeoutSeconds
├── STT/
│   └── TranscriptionService.swift  # WhisperKit integration, audio → originalTranscript
├── Rewrite/
│   ├── RewriteService.swift        # Protocol: rewrite(original) → RewriteResult
│   ├── AppleRewriter.swift         # FoundationModels implementation (primary)
│   └── OpenRouterRewriter.swift    # URLSession + OpenRouter API (fallback)
├── Graph/
│   ├── AuthManager.swift           # MSAL sign-in/out, token cache, silent refresh
│   └── TodoClient.swift            # GET lists, POST task, optional PATCH
├── Views/
│   ├── MenuBarPopover.swift        # Main popover: mic toggle, status, last saved task
│   ├── SettingsView.swift          # Settings: silence timeout, list picker, API key
│   └── Components/
│       ├── StatusIndicator.swift   # Colored dot/animation for current state
│       └── TaskPreviewCard.swift   # Shows revised + corrections + original
└── Resources/
    └── Info.plist                  # NSMicrophoneUsageDescription, MSAL redirect URI scheme
```

---

## 6. Key Types

```swift
// MARK: - State Machine
enum PipelineState: Equatable {
    case idle
    case listening
    case speaking
    case silenceCountdown
    case finalizingSTT
    case rewriting
    case saving
    case error(String)
}

// MARK: - Pipeline Data
struct AudioSegment {
    let wavData: Data
    let durationSeconds: Double
}

struct TranscriptResult {
    let originalTranscript: String
}

struct RewriteResult {
    let revised: String
    let alternatives: [String]    // 0-2 items
    let corrections: [String]     // 1-3 short labels of what was fixed
}

struct SavedTask {
    let graphTaskId: String
    let title: String             // = revised
    let body: String?             // = corrections + alternatives + originalTranscript
    let savedAt: Date
}

// MARK: - Rewrite Service Protocol
protocol RewriteService {
    func rewrite(_ original: String) async throws -> RewriteResult
}

// MARK: - Settings
struct AppSettings {
    var silenceTimeoutSeconds: Double = 3.0
    var selectedTodoListId: String?
    var selectedTodoListName: String?
    var openRouterApiKey: String?
}
```

---

## 7. LLM Rewrite Prompt

```
System:
You are an English writing assistant.
Rewrite the user's sentence: fix grammar, improve naturalness for spoken English.
Preserve the original meaning exactly. Do not add explanations.

Respond in JSON only:
{"revised": "...", "alternatives": ["...", "..."], "corrections": ["...", "..."]}

Rules:
- "revised": one corrected, natural-sounding sentence
- "alternatives": 0-2 variations with same meaning (omit if unnecessary)
- "corrections": 1-3 short labels of what was fixed (e.g. "verb tense", "missing article")
- No commentary beyond the JSON
```

### Fallback Chain

1. **Apple Foundation Models** (macOS 26+, on-device, free)
   - Fail conditions: OS too old, model unavailable, JSON parse error
2. **OpenRouter API** (requires API key in Keychain)
   - Model chain: `openrouter/free` → `deepseek-chat` → `gemini-flash`
3. **Raw save** — save `originalTranscript` as-is (never lose user input)

---

## 8. MSAL Auth Flow

```
1. App launch → AuthManager.trySilentTokenAcquisition()
   - Cached token valid → Ready
   - Refresh token valid → Silent refresh → Ready
   - Both expired → Show "Sign in" button
2. User taps "Sign in" → Interactive auth (system browser)
   - Scopes: ["Tasks.ReadWrite"]
   - Redirect: msauth.com.speaksmooth.app://auth
3. Token stored via MSAL's built-in Keychain cache
4. Every Graph call: AuthManager.getAccessToken() async throws → String
```

---

## 9. Segment Builder Logic

```
VAD voiceStarted()       → state = .speaking, start accumulating PCM
VAD voiceDidContinue()   → append to buffer, reset silence timer
VAD voiceEnded()         → start silenceTimeoutSeconds countdown
  - Voice resumes before timeout → cancel timer, continue accumulating
  - Timeout elapses → finalize segment, emit AudioSegment, reset buffer
```

This prevents cutting mid-thought (e.g. "I want to... buy groceries").

---

## 10. To Do Task Format

```
Title: I should have gone to the store earlier.

Body:
  Corrections: verb form ("went" → "have gone"), missing article, adverb form
  Alt 1: I should've headed to the store sooner.
  Original: I should went to store more early.
```

### Graph API Call

```
POST /me/todo/lists/{selectedTodoListId}/tasks
Authorization: Bearer {accessToken}
Content-Type: application/json

{
  "title": "{revised}",
  "body": {
    "content": "Corrections: {corrections}\n{alternatives}\nOriginal: {originalTranscript}",
    "contentType": "text"
  }
}
```

---

## 11. UI Layout

### Menu Bar Icon States

| State | Icon | Color |
|-------|------|-------|
| Idle | `mic` | Gray |
| Recording (listening/speaking) | `mic.fill` | Red / accent, pulse animation |
| Processing (STT/rewrite/save) | `mic.fill` | Orange |
| Error | `mic.slash` | Yellow |

Recording persists when popover is closed. Icon reflects current state at all times.

### Popover (~320x400pt)

```
┌─────────────────────────────┐
│  SpeakSmooth          ⚙️    │  Header + settings gear
├─────────────────────────────┤
│                             │
│       [ Start / Stop ]      │  Toggle mic button
│                             │
│    Status: Ready            │  StatusIndicator + label
│                             │
├─────────────────────────────┤
│  Last saved:                │
│  ┌────────────────────────┐ │
│  │ "I should have gone    │ │  revised (title)
│  │  to the store earlier."│ │
│  │                        │ │
│  │ verb form, missing     │ │  corrections
│  │ article, adverb form   │ │
│  │                        │ │
│  │ Original: "I should    │ │  originalTranscript
│  │ went to store more..." │ │
│  └────────────────────────┘ │
├─────────────────────────────┤
│  To Do: ✅ Signed in        │  Auth status
│  List: "English Practice"   │  Selected list name
└─────────────────────────────┘
```

### Settings View

```
┌─────────────────────────────┐
│  Settings                   │
├─────────────────────────────┤
│  Silence timeout:  [3.0]s   │  Stepper, 1.0-10.0
│                             │
│  Microsoft Account:         │
│  [Sign In / Sign Out]       │
│                             │
│  To Do List:                │
│  [ ▼ English Practice    ]  │  Picker from /me/todo/lists
│                             │
│  OpenRouter API Key:        │
│  [••••••••••••]  (optional) │  Keychain-stored, fallback only
└─────────────────────────────┘
```

---

## 12. Error Handling

| Error | Behavior |
|-------|----------|
| Mic permission denied | Show system prompt, disable Start button |
| WhisperKit model not downloaded | Auto-download on first launch, show progress |
| LLM rewrite fails (both engines) | Save originalTranscript as-is, show warning |
| Graph API 401 | Trigger silent token refresh, retry once |
| Graph API other error | Show error in popover, auto-dismiss after 3s |
| Network unavailable | Queue task locally, retry when online (stretch) |

All errors transition state to `.error(message)`, auto-reset to `.idle` after 3 seconds.

---

## 13. Graph API Surface

| Operation | Endpoint | When |
|-----------|----------|------|
| List todo lists | `GET /me/todo/lists` | Settings: list picker |
| Create task | `POST /me/todo/lists/{listId}/tasks` | After rewrite completes |
| Update task (optional) | `PATCH /me/todo/lists/{listId}/tasks/{taskId}` | Future: edit saved tasks |
