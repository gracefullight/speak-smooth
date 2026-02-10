# SpeakSmooth Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a macOS menu bar app that captures voice, transcribes via local STT, rewrites for grammar/naturalness, and saves to Microsoft To Do.

**Architecture:** Linear pipeline (Mic → VAD → STT → LLM Rewrite → Graph API) driven by an `@Observable` state machine. MenuBarExtra with `.window` style popover. Recording persists independent of popover lifecycle.

**Tech Stack:** Swift 6.2 / SwiftUI / macOS 14+ target. WhisperKit (STT), RealTimeCutVADLibrary (VAD), MSAL (auth), Apple Foundation Models + OpenRouter (rewrite).

**Design doc:** `docs/plans/2026-02-11-speak-smooth-design.md`

---

## Phase 1: Foundation

### Task 1: Project Scaffold (XcodeGen + SPM)

**Files:**
- Create: `project.yml`
- Create: `SpeakSmooth/Resources/Info.plist`
- Create: `SpeakSmooth/Resources/SpeakSmooth.entitlements`

**Step 1: Install XcodeGen (if needed)**

```bash
brew install xcodegen
```

**Step 2: Create `project.yml`**

```yaml
name: SpeakSmooth
options:
  bundleIdPrefix: com.speaksmooth
  deploymentTarget:
    macOS: "14.0"
  xcodeVersion: "16.0"
  minimumXcodeGenVersion: "2.40.0"
  groupSortPosition: top
  generateEmptyDirectories: true

settings:
  base:
    SWIFT_VERSION: "6.0"
    MACOSX_DEPLOYMENT_TARGET: "14.0"
    PRODUCT_BUNDLE_IDENTIFIER: com.speaksmooth.app
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: 1
    ENABLE_HARDENED_RUNTIME: true
    CODE_SIGN_ENTITLEMENTS: SpeakSmooth/Resources/SpeakSmooth.entitlements

packages:
  WhisperKit:
    url: https://github.com/argmaxinc/WhisperKit.git
    from: "0.10.0"
  RealTimeCutVADLibrary:
    url: https://github.com/helloooideeeeea/RealTimeCutVADLibrary.git
    from: "1.0.14"
  MSAL:
    url: https://github.com/AzureAD/microsoft-authentication-library-for-objc.git
    from: "1.6.1"

targets:
  SpeakSmooth:
    type: application
    platform: macOS
    sources:
      - path: SpeakSmooth
        excludes:
          - Resources/Info.plist
    info:
      path: SpeakSmooth/Resources/Info.plist
    entitlements:
      path: SpeakSmooth/Resources/SpeakSmooth.entitlements
    dependencies:
      - package: WhisperKit
      - package: RealTimeCutVADLibrary
      - package: MSAL
    settings:
      base:
        INFOPLIST_KEY_LSUIElement: true
        LD_RUNPATH_SEARCH_PATHS: "$(inherited) @executable_path/../Frameworks"

  SpeakSmoothTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: SpeakSmoothTests
    dependencies:
      - target: SpeakSmooth
    settings:
      base:
        BUNDLE_LOADER: "$(TEST_HOST)"
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/SpeakSmooth.app/Contents/MacOS/SpeakSmooth"
```

**Step 3: Create `Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSMicrophoneUsageDescription</key>
    <string>SpeakSmooth needs microphone access to transcribe your voice.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>SpeakSmooth uses speech recognition to convert your voice to text.</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>msauth.com.speaksmooth.app</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

**Step 4: Create `SpeakSmooth.entitlements`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>keychain-access-groups</key>
    <array>
        <string>$(AppIdentifierPrefix)com.microsoft.identity.universalstorage</string>
    </array>
</dict>
</plist>
```

**Step 5: Create directory structure and placeholder files**

```bash
mkdir -p SpeakSmooth/{Models,Audio,STT,Rewrite,Graph,Views/Components,Resources}
mkdir -p SpeakSmoothTests
touch SpeakSmooth/SpeakSmoothApp.swift
touch SpeakSmooth/Models/{AppState,Settings}.swift
touch SpeakSmooth/Audio/{AudioCaptureManager,SegmentBuilder}.swift
touch SpeakSmooth/STT/TranscriptionService.swift
touch SpeakSmooth/Rewrite/{RewriteService,AppleRewriter,OpenRouterRewriter}.swift
touch SpeakSmooth/Graph/{AuthManager,TodoClient}.swift
touch SpeakSmooth/Views/{MenuBarPopover,SettingsView}.swift
touch SpeakSmooth/Views/Components/{StatusIndicator,TaskPreviewCard}.swift
touch SpeakSmoothTests/SpeakSmoothTests.swift
```

**Step 6: Generate Xcode project**

```bash
xcodegen generate
```

Expected: `SpeakSmooth.xcodeproj` created with all targets and SPM dependencies.

**Step 7: Resolve packages and build**

```bash
xcodebuild -project SpeakSmooth.xcodeproj -scheme SpeakSmooth -resolvePackageDependencies
xcodebuild -project SpeakSmooth.xcodeproj -scheme SpeakSmooth build
```

Expected: Build succeeds (empty app, no errors).

**Step 8: Commit**

```bash
git add -A
git commit -m "chore: scaffold project with XcodeGen, SPM deps, and directory structure"
```

---

### Task 2: App Entry + MenuBarExtra Shell

**Files:**
- Modify: `SpeakSmooth/SpeakSmoothApp.swift`

**Step 1: Write the app entry point**

```swift
import SwiftUI

@main
struct SpeakSmoothApp: App {
    var body: some Scene {
        MenuBarExtra {
            VStack(spacing: 12) {
                Text("SpeakSmooth")
                    .font(.headline)
                Text("Ready")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(width: 300)
        } label: {
            Image(systemName: "mic")
        }
        .menuBarExtraStyle(.window)
    }
}
```

**Step 2: Build and verify**

```bash
xcodebuild -project SpeakSmooth.xcodeproj -scheme SpeakSmooth build
```

Expected: Build succeeds. Running the app shows a mic icon in the menu bar with a basic popover.

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add MenuBarExtra app shell with mic icon"
```

---

### Task 3: Settings Model

**Files:**
- Modify: `SpeakSmooth/Models/Settings.swift`
- Create: `SpeakSmoothTests/SettingsTests.swift`

**Step 1: Write the failing test**

```swift
// SpeakSmoothTests/SettingsTests.swift
import Testing
@testable import SpeakSmooth

@Suite("Settings Tests")
struct SettingsTests {
    @Test("Default silence timeout is 3.0")
    func defaultSilenceTimeout() {
        let settings = AppSettings()
        #expect(settings.silenceTimeoutSeconds == 3.0)
    }

    @Test("Default todo list is nil")
    func defaultTodoList() {
        let settings = AppSettings()
        #expect(settings.selectedTodoListId == nil)
        #expect(settings.selectedTodoListName == nil)
    }

    @Test("Silence timeout clamps to valid range")
    func silenceTimeoutClamped() {
        var settings = AppSettings()
        settings.silenceTimeoutSeconds = 0.5
        #expect(settings.silenceTimeoutSeconds == 1.0)
        settings.silenceTimeoutSeconds = 15.0
        #expect(settings.silenceTimeoutSeconds == 10.0)
    }
}
```

**Step 2: Run test to verify it fails**

```bash
xcodebuild test -project SpeakSmooth.xcodeproj -scheme SpeakSmooth -destination 'platform=macOS'
```

Expected: FAIL — `AppSettings` not defined.

**Step 3: Write the implementation**

```swift
// SpeakSmooth/Models/Settings.swift
import SwiftUI

@Observable
final class AppSettings {
    private enum Keys {
        static let silenceTimeout = "silenceTimeoutSeconds"
        static let todoListId = "selectedTodoListId"
        static let todoListName = "selectedTodoListName"
    }

    var silenceTimeoutSeconds: Double {
        didSet {
            let clamped = min(max(silenceTimeoutSeconds, 1.0), 10.0)
            if silenceTimeoutSeconds != clamped { silenceTimeoutSeconds = clamped }
            UserDefaults.standard.set(clamped, forKey: Keys.silenceTimeout)
        }
    }

    var selectedTodoListId: String? {
        didSet { UserDefaults.standard.set(selectedTodoListId, forKey: Keys.todoListId) }
    }

    var selectedTodoListName: String? {
        didSet { UserDefaults.standard.set(selectedTodoListName, forKey: Keys.todoListName) }
    }

    var openRouterApiKey: String? // Keychain-stored separately, not in UserDefaults

    init() {
        let stored = UserDefaults.standard.double(forKey: Keys.silenceTimeout)
        self.silenceTimeoutSeconds = stored > 0 ? min(max(stored, 1.0), 10.0) : 3.0
        self.selectedTodoListId = UserDefaults.standard.string(forKey: Keys.todoListId)
        self.selectedTodoListName = UserDefaults.standard.string(forKey: Keys.todoListName)
    }
}
```

**Step 4: Run test to verify it passes**

```bash
xcodebuild test -project SpeakSmooth.xcodeproj -scheme SpeakSmooth -destination 'platform=macOS'
```

Expected: PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add AppSettings model with UserDefaults persistence"
```

---

### Task 4: AppState (State Machine)

**Files:**
- Modify: `SpeakSmooth/Models/AppState.swift`
- Create: `SpeakSmoothTests/AppStateTests.swift`

**Step 1: Write the failing test**

```swift
// SpeakSmoothTests/AppStateTests.swift
import Testing
@testable import SpeakSmooth

@Suite("AppState Tests")
struct AppStateTests {
    @Test("Initial state is idle")
    func initialState() {
        let state = AppState()
        #expect(state.pipelineState == .idle)
    }

    @Test("Menu bar icon name reflects state")
    func menuBarIconName() {
        let state = AppState()
        #expect(state.menuBarIconName == "mic")

        state.pipelineState = .listening
        #expect(state.menuBarIconName == "mic.fill")

        state.pipelineState = .finalizingSTT
        #expect(state.menuBarIconName == "mic.badge.ellipsis")

        state.pipelineState = .error("test")
        #expect(state.menuBarIconName == "mic.slash")
    }

    @Test("Can start recording from idle")
    func startFromIdle() {
        let state = AppState()
        state.startRecording()
        #expect(state.pipelineState == .listening)
    }

    @Test("Can stop recording from any active state")
    func stopFromActive() {
        let state = AppState()
        state.pipelineState = .speaking
        state.stopRecording()
        #expect(state.pipelineState == .idle)
    }

    @Test("Error auto-description")
    func errorState() {
        let state = AppState()
        state.pipelineState = .error("Network failed")
        #expect(state.statusText == "Network failed")
    }
}
```

**Step 2: Run test to verify it fails**

```bash
xcodebuild test -project SpeakSmooth.xcodeproj -scheme SpeakSmooth -destination 'platform=macOS'
```

Expected: FAIL — `AppState` not implemented.

**Step 3: Write the implementation**

```swift
// SpeakSmooth/Models/AppState.swift
import SwiftUI

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

struct SavedTask: Equatable {
    let graphTaskId: String
    let title: String
    let body: String?
    let savedAt: Date
}

@Observable
@MainActor
final class AppState {
    var pipelineState: PipelineState = .idle
    var lastSavedTask: SavedTask?

    var isRecording: Bool {
        switch pipelineState {
        case .idle, .error: return false
        default: return true
        }
    }

    var menuBarIconName: String {
        switch pipelineState {
        case .idle: return "mic"
        case .listening, .speaking, .silenceCountdown: return "mic.fill"
        case .finalizingSTT, .rewriting, .saving: return "mic.badge.ellipsis"
        case .error: return "mic.slash"
        }
    }

    var statusText: String {
        switch pipelineState {
        case .idle: return "Ready"
        case .listening: return "Listening..."
        case .speaking: return "Hearing you..."
        case .silenceCountdown: return "Waiting..."
        case .finalizingSTT: return "Transcribing..."
        case .rewriting: return "Rewriting..."
        case .saving: return "Saving to To Do..."
        case .error(let msg): return msg
        }
    }

    func startRecording() {
        guard pipelineState == .idle || pipelineState.isError else { return }
        pipelineState = .listening
    }

    func stopRecording() {
        pipelineState = .idle
    }

    func transitionTo(_ state: PipelineState) {
        pipelineState = state
    }

    func handleError(_ message: String) {
        pipelineState = .error(message)
        Task {
            try? await Task.sleep(for: .seconds(3))
            if case .error = pipelineState {
                pipelineState = .idle
            }
        }
    }
}

extension PipelineState {
    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}
```

**Step 4: Run test to verify it passes**

```bash
xcodebuild test -project SpeakSmooth.xcodeproj -scheme SpeakSmooth -destination 'platform=macOS'
```

Expected: PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add AppState with PipelineState machine and reactive properties"
```

---

## Phase 2: Audio Pipeline

### Task 5: Audio Capture Manager

**Files:**
- Modify: `SpeakSmooth/Audio/AudioCaptureManager.swift`

**Step 1: Write the implementation**

This component wraps AVAudioEngine. It's hardware-dependent and tested manually.

```swift
// SpeakSmooth/Audio/AudioCaptureManager.swift
import AVFoundation

final class AudioCaptureManager: @unchecked Sendable {
    private var audioEngine: AVAudioEngine?
    private let bufferSize: AVAudioFrameCount = 4800
    var onAudioBuffer: ((_ buffer: UnsafePointer<Float>, _ count: UInt) -> Void)?

    var isRunning: Bool { audioEngine?.isRunning ?? false }

    static func requestMicPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    static var isMicAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func start() throws {
        guard Self.isMicAuthorized else {
            throw AudioCaptureError.micPermissionDenied
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let nativeFormat = inputNode.inputFormat(forBus: 0)

        // Request mono Float32 at native sample rate
        guard let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: nativeFormat.sampleRate,
            channels: 1,
            interleaved: true
        ) else {
            throw AudioCaptureError.formatError
        }

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: recordingFormat) { [weak self] buffer, _ in
            guard let self,
                  let channelData = buffer.floatChannelData else { return }
            let frameLength = UInt(buffer.frameLength)
            self.onAudioBuffer?(channelData[0], frameLength)
        }

        engine.prepare()
        try engine.start()
        self.audioEngine = engine
    }

    func stop() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
    }
}

enum AudioCaptureError: LocalizedError {
    case micPermissionDenied
    case formatError

    var errorDescription: String? {
        switch self {
        case .micPermissionDenied: return "Microphone permission denied"
        case .formatError: return "Could not create audio format"
        }
    }
}
```

**Step 2: Build**

```bash
xcodebuild -project SpeakSmooth.xcodeproj -scheme SpeakSmooth build
```

Expected: Build succeeds.

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add AudioCaptureManager with AVAudioEngine mic tap"
```

---

### Task 6: Segment Builder (VAD Integration)

**Files:**
- Modify: `SpeakSmooth/Audio/SegmentBuilder.swift`
- Create: `SpeakSmoothTests/SegmentBuilderTests.swift`

**Step 1: Write the failing test**

```swift
// SpeakSmoothTests/SegmentBuilderTests.swift
import Testing
@testable import SpeakSmooth

@Suite("SegmentBuilder Tests")
struct SegmentBuilderTests {
    @Test("Converts PCM Data to Float array")
    func pcmDataToFloats() {
        let floats: [Float] = [0.1, 0.5, -0.3, 0.0]
        let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        let result = SegmentBuilder.convertPCMDataToFloats(data)
        #expect(result.count == 4)
        #expect(abs(result[0] - 0.1) < 0.001)
        #expect(abs(result[1] - 0.5) < 0.001)
    }

    @Test("Calculates VAD frame count from seconds")
    func frameCountFromSeconds() {
        // Each Silero frame ≈ 32ms
        let frames = SegmentBuilder.vadFrameCount(forSeconds: 3.0)
        #expect(frames == 94) // 3.0 / 0.032 ≈ 93.75, rounded up
    }
}
```

**Step 2: Run test to verify it fails**

```bash
xcodebuild test -project SpeakSmooth.xcodeproj -scheme SpeakSmooth -destination 'platform=macOS'
```

Expected: FAIL — `SegmentBuilder` not defined.

**Step 3: Write the implementation**

```swift
// SpeakSmooth/Audio/SegmentBuilder.swift
import Foundation
import RealTimeCutVADLibrary

struct AudioSegment: Sendable {
    let pcmFloats: [Float]  // 16kHz mono
    let durationSeconds: Double
}

final class SegmentBuilder: NSObject, @unchecked Sendable {
    private var accumulatedPCMData = Data()
    private let pcmQueue = DispatchQueue(label: "com.speaksmooth.pcm")
    private var isAccumulating = false

    var onSegmentReady: ((AudioSegment) -> Void)?
    var onVoiceStarted: (() -> Void)?
    var onVoiceEnded: (() -> Void)?

    private let vadWrapper: VADWrapper

    init(sampleRate: SL = .SAMPLERATE_48, silenceTimeoutSeconds: Double = 3.0) {
        self.vadWrapper = VADWrapper()
        super.init()
        vadWrapper.delegate = self
        vadWrapper.setSileroModel(.v5)
        vadWrapper.setSamplerate(sampleRate)
        updateSilenceTimeout(silenceTimeoutSeconds)
    }

    func updateSilenceTimeout(_ seconds: Double) {
        let frameCount = Self.vadFrameCount(forSeconds: seconds)
        vadWrapper.setThresholdWithVadStartDetectionProbability(
            0.7,
            vadEndDetectionProbability: 0.7,
            voiceStartVadTrueRatio: 0.5,
            voiceEndVadFalseRatio: 0.95,
            voiceStartFrameCount: 10,
            voiceEndFrameCount: Int32(frameCount)
        )
    }

    func feedAudio(buffer: UnsafePointer<Float>, count: UInt) {
        vadWrapper.processAudioData(withBuffer: buffer, count: count)
    }

    // MARK: - Helpers

    static func convertPCMDataToFloats(_ data: Data) -> [Float] {
        data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return [] }
            let floatBuffer = baseAddress.assumingMemoryBound(to: Float.self)
            return Array(UnsafeBufferPointer(start: floatBuffer, count: data.count / MemoryLayout<Float>.size))
        }
    }

    static func vadFrameCount(forSeconds seconds: Double) -> Int {
        // Silero VAD frame duration ≈ 32ms
        let frameMs = 0.032
        return Int((seconds / frameMs).rounded(.up))
    }
}

// MARK: - VADDelegate
extension SegmentBuilder: VADDelegate {
    func voiceStarted() {
        pcmQueue.sync {
            accumulatedPCMData.removeAll()
            isAccumulating = true
        }
        onVoiceStarted?()
    }

    func voiceEnded(withWavData wavData: Data!) {
        var segment: AudioSegment?
        pcmQueue.sync {
            isAccumulating = false
            if !accumulatedPCMData.isEmpty {
                let floats = Self.convertPCMDataToFloats(accumulatedPCMData)
                let duration = Double(floats.count) / 16000.0
                segment = AudioSegment(pcmFloats: floats, durationSeconds: duration)
            }
            accumulatedPCMData.removeAll()
        }
        onVoiceEnded?()
        if let segment { onSegmentReady?(segment) }
    }

    func voiceDidContinue(withPCMFloat pcmFloatData: Data!) {
        guard let data = pcmFloatData else { return }
        pcmQueue.sync {
            if isAccumulating {
                accumulatedPCMData.append(data)
            }
        }
    }
}
```

**Step 4: Run test to verify it passes**

```bash
xcodebuild test -project SpeakSmooth.xcodeproj -scheme SpeakSmooth -destination 'platform=macOS'
```

Expected: PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add SegmentBuilder with Silero VAD and configurable silence timeout"
```

---

## Phase 3: Processing

### Task 7: Transcription Service (WhisperKit)

**Files:**
- Modify: `SpeakSmooth/STT/TranscriptionService.swift`

**Step 1: Write the implementation**

```swift
// SpeakSmooth/STT/TranscriptionService.swift
import WhisperKit

struct TranscriptResult: Sendable {
    let originalTranscript: String
}

actor TranscriptionService {
    private var whisperKit: WhisperKit?
    private(set) var isModelLoaded = false

    func loadModel() async throws {
        whisperKit = try await WhisperKit(
            model: "openai/whisper-base.en",
            verbose: false,
            load: true,
            download: true
        )
        isModelLoaded = true
    }

    func transcribe(_ segment: AudioSegment) async throws -> TranscriptResult {
        guard let whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        let options = DecodingOptions(
            language: "en",
            temperature: 0.0,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )

        let results = try await whisperKit.transcribe(
            audioArray: segment.pcmFloats,
            decodeOptions: options
        )

        let text = results
            .compactMap { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            throw TranscriptionError.emptyTranscript
        }

        return TranscriptResult(originalTranscript: text)
    }
}

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "WhisperKit model not loaded"
        case .emptyTranscript: return "No speech detected in segment"
        }
    }
}
```

**Step 2: Build**

```bash
xcodebuild -project SpeakSmooth.xcodeproj -scheme SpeakSmooth build
```

Expected: Build succeeds.

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add TranscriptionService with WhisperKit base.en model"
```

---

### Task 8: Rewrite Service Protocol + Apple Foundation Models

**Files:**
- Modify: `SpeakSmooth/Rewrite/RewriteService.swift`
- Modify: `SpeakSmooth/Rewrite/AppleRewriter.swift`
- Create: `SpeakSmoothTests/RewriteTests.swift`

**Step 1: Write the failing test**

```swift
// SpeakSmoothTests/RewriteTests.swift
import Testing
@testable import SpeakSmooth

@Suite("Rewrite Tests")
struct RewriteTests {
    @Test("RewriteResult from valid JSON")
    func parseValidJSON() throws {
        let json = """
        {"revised": "I should have gone.", "alternatives": ["I ought to have gone."], "corrections": ["verb form"]}
        """
        let data = json.data(using: .utf8)!
        let result = try JSONDecoder().decode(RewriteResult.self, from: data)
        #expect(result.revised == "I should have gone.")
        #expect(result.alternatives.count == 1)
        #expect(result.corrections.first == "verb form")
    }

    @Test("RewriteResult with empty alternatives")
    func parseEmptyAlternatives() throws {
        let json = """
        {"revised": "Hello.", "alternatives": [], "corrections": ["capitalization"]}
        """
        let data = json.data(using: .utf8)!
        let result = try JSONDecoder().decode(RewriteResult.self, from: data)
        #expect(result.alternatives.isEmpty)
    }

    @Test("Task body formatting")
    func taskBodyFormat() {
        let result = RewriteResult(
            revised: "I should have gone.",
            alternatives: ["I ought to have gone."],
            corrections: ["verb form", "missing article"]
        )
        let body = result.formatTaskBody(original: "I should went.")
        #expect(body.contains("verb form"))
        #expect(body.contains("I should went."))
        #expect(body.contains("I ought to have gone."))
    }
}
```

**Step 2: Run test to verify it fails**

```bash
xcodebuild test -project SpeakSmooth.xcodeproj -scheme SpeakSmooth -destination 'platform=macOS'
```

Expected: FAIL — types not defined.

**Step 3: Write the protocol and types**

```swift
// SpeakSmooth/Rewrite/RewriteService.swift
import Foundation

struct RewriteResult: Codable, Sendable, Equatable {
    let revised: String
    let alternatives: [String]
    let corrections: [String]

    func formatTaskBody(original: String) -> String {
        var lines: [String] = []
        if !corrections.isEmpty {
            lines.append("Corrections: \(corrections.joined(separator: ", "))")
        }
        for (i, alt) in alternatives.enumerated() {
            lines.append("Alt \(i + 1): \(alt)")
        }
        lines.append("Original: \(original)")
        return lines.joined(separator: "\n")
    }
}

protocol RewriteService: Sendable {
    func rewrite(_ original: String) async throws -> RewriteResult
}

enum RewriteError: LocalizedError {
    case unavailable
    case invalidResponse
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Rewrite service unavailable"
        case .invalidResponse: return "Could not parse rewrite response"
        case .networkError(let e): return "Network error: \(e.localizedDescription)"
        }
    }
}
```

**Step 4: Write the Apple Foundation Models implementation**

```swift
// SpeakSmooth/Rewrite/AppleRewriter.swift
import Foundation
import FoundationModels

@available(macOS 26.0, *)
@Generable
struct GenerableRewriteResult {
    @Guide(description: "The corrected, natural-sounding English sentence. Preserve original meaning.")
    var revised: String

    @Guide(description: "0-2 alternative phrasings with the same meaning.", .maximumCount(2))
    var alternatives: [String]

    @Guide(description: "1-3 short labels of what grammar or expression issues were fixed.", .maximumCount(3))
    var corrections: [String]
}

@available(macOS 26.0, *)
final class AppleRewriter: RewriteService, @unchecked Sendable {
    private let session: LanguageModelSession

    init() {
        self.session = LanguageModelSession(
            instructions: """
            You are an English writing assistant.
            Rewrite the user's sentence: fix grammar, improve naturalness for spoken English.
            Preserve the original meaning exactly. Do not add explanations.
            """
        )
    }

    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    func rewrite(_ original: String) async throws -> RewriteResult {
        guard Self.isAvailable else { throw RewriteError.unavailable }

        let response = try await session.respond(
            to: original,
            generating: GenerableRewriteResult.self
        )

        let generated = response.content
        return RewriteResult(
            revised: generated.revised,
            alternatives: generated.alternatives,
            corrections: generated.corrections
        )
    }
}
```

**Step 5: Run test to verify it passes**

```bash
xcodebuild test -project SpeakSmooth.xcodeproj -scheme SpeakSmooth -destination 'platform=macOS'
```

Expected: PASS

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: add RewriteService protocol and AppleRewriter with @Generable structured output"
```

---

### Task 9: OpenRouter Rewriter (Fallback)

**Files:**
- Modify: `SpeakSmooth/Rewrite/OpenRouterRewriter.swift`
- Create: `SpeakSmoothTests/OpenRouterRewriterTests.swift`

**Step 1: Write the failing test**

```swift
// SpeakSmoothTests/OpenRouterRewriterTests.swift
import Testing
@testable import SpeakSmooth

@Suite("OpenRouterRewriter Tests")
struct OpenRouterRewriterTests {
    @Test("Parses valid OpenRouter response body")
    func parseResponseBody() throws {
        let responseJSON = """
        {
          "id": "gen-123",
          "choices": [{
            "message": {
              "role": "assistant",
              "content": "{\\"revised\\": \\"Hello there.\\", \\"alternatives\\": [], \\"corrections\\": [\\"greeting\\"]}"
            },
            "finish_reason": "stop"
          }],
          "model": "openrouter/free"
        }
        """
        let data = responseJSON.data(using: .utf8)!
        let result = try OpenRouterRewriter.parseResponse(data)
        #expect(result.revised == "Hello there.")
        #expect(result.corrections == ["greeting"])
    }

    @Test("Builds correct request body")
    func buildRequestBody() throws {
        let body = OpenRouterRewriter.buildRequestBody(for: "I has a dog.")
        let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        let messages = json["messages"] as! [[String: String]]
        #expect(messages.count == 2)
        #expect(messages[0]["role"] == "system")
        #expect(messages[1]["content"] == "I has a dog.")
    }
}
```

**Step 2: Run test to verify it fails**

```bash
xcodebuild test -project SpeakSmooth.xcodeproj -scheme SpeakSmooth -destination 'platform=macOS'
```

Expected: FAIL

**Step 3: Write the implementation**

```swift
// SpeakSmooth/Rewrite/OpenRouterRewriter.swift
import Foundation

final class OpenRouterRewriter: RewriteService, @unchecked Sendable {
    private let apiKey: String
    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    private static let systemPrompt = """
    You are an English writing assistant.
    Rewrite the user's sentence: fix grammar, improve naturalness for spoken English.
    Preserve the original meaning exactly. Do not add explanations.

    Respond in JSON only:
    {"revised": "...", "alternatives": ["...", "..."], "corrections": ["...", "..."]}

    Rules:
    - "revised": one corrected, natural-sounding sentence
    - "alternatives": 0-2 variations with same meaning (omit array items if unnecessary)
    - "corrections": 1-3 short labels of what was fixed (e.g. "verb tense", "missing article")
    - No commentary beyond the JSON
    """

    private static let modelFallback = [
        "openrouter/free",
        "deepseek/deepseek-chat",
        "google/gemini-2.0-flash-exp:free"
    ]

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func rewrite(_ original: String) async throws -> RewriteResult {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("SpeakSmooth", forHTTPHeaderField: "X-Title")
        request.httpBody = Self.buildRequestBody(for: original)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw RewriteError.networkError(
                NSError(domain: "OpenRouter", code: (response as? HTTPURLResponse)?.statusCode ?? 0)
            )
        }

        return try Self.parseResponse(data)
    }

    // MARK: - Testable Helpers

    static func buildRequestBody(for text: String) -> Data {
        let body: [String: Any] = [
            "model": modelFallback[0],
            "models": modelFallback,
            "route": "fallback",
            "temperature": 0.3,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: body)
    }

    static func parseResponse(_ data: Data) throws -> RewriteResult {
        struct OpenRouterResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let response = try JSONDecoder().decode(OpenRouterResponse.self, from: data)
        guard let content = response.choices.first?.message.content else {
            throw RewriteError.invalidResponse
        }

        // The content is a JSON string embedded in the message
        guard let jsonData = content.data(using: .utf8) else {
            throw RewriteError.invalidResponse
        }

        return try JSONDecoder().decode(RewriteResult.self, from: jsonData)
    }
}
```

**Step 4: Run test to verify it passes**

```bash
xcodebuild test -project SpeakSmooth.xcodeproj -scheme SpeakSmooth -destination 'platform=macOS'
```

Expected: PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add OpenRouterRewriter with model fallback chain and JSON parsing"
```

---

## Phase 4: Microsoft Integration

### Task 10: Auth Manager (MSAL)

**Files:**
- Modify: `SpeakSmooth/Graph/AuthManager.swift`

**Step 1: Write the implementation**

```swift
// SpeakSmooth/Graph/AuthManager.swift
import MSAL

@Observable
@MainActor
final class AuthManager {
    private static let clientId = "YOUR_CLIENT_ID" // TODO: Replace with Azure AD app registration
    private static let redirectUri = "msauth.com.speaksmooth.app://auth"
    private static let authority = "https://login.microsoftonline.com/common"
    private static let scopes = ["Tasks.ReadWrite"]

    private var application: MSALPublicClientApplication?
    private var currentAccount: MSALAccount?

    private(set) var isSignedIn = false
    private(set) var accountName: String?

    init() {
        setupMSAL()
    }

    private func setupMSAL() {
        guard let authorityURL = URL(string: Self.authority) else { return }
        do {
            let authority = try MSALAADAuthority(url: authorityURL)
            let config = MSALPublicClientApplicationConfig(
                clientId: Self.clientId,
                redirectUri: Self.redirectUri,
                authority: authority
            )
            self.application = try MSALPublicClientApplication(configuration: config)
            loadAccount()
        } catch {
            print("MSAL setup error: \(error)")
        }
    }

    private func loadAccount() {
        guard let application else { return }
        do {
            let accounts = try application.allAccounts()
            if let account = accounts.first {
                currentAccount = account
                isSignedIn = true
                accountName = account.username
            }
        } catch {
            print("Load account error: \(error)")
        }
    }

    func signIn() async throws {
        guard let application else { throw AuthError.notConfigured }

        let parameters = MSALInteractiveTokenParameters(
            scopes: Self.scopes,
            webviewParameters: MSALWebviewParameters()
        )
        parameters.promptType = .selectAccount

        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MSALResult, Error>) in
            application.acquireToken(with: parameters) { result, error in
                if let error { continuation.resume(throwing: error) }
                else if let result { continuation.resume(returning: result) }
                else { continuation.resume(throwing: AuthError.unknown) }
            }
        }

        currentAccount = result.account
        isSignedIn = true
        accountName = result.account.username
    }

    func signOut() throws {
        guard let application, let account = currentAccount else { return }
        try application.remove(account)
        currentAccount = nil
        isSignedIn = false
        accountName = nil
    }

    func getAccessToken() async throws -> String {
        guard let application, let account = currentAccount else {
            throw AuthError.notSignedIn
        }

        // Try silent first
        let silentParams = MSALSilentTokenParameters(scopes: Self.scopes, account: account)
        do {
            let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MSALResult, Error>) in
                application.acquireTokenSilent(with: silentParams) { result, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let result { continuation.resume(returning: result) }
                    else { continuation.resume(throwing: AuthError.unknown) }
                }
            }
            return result.accessToken
        } catch {
            // Silent failed — try interactive
            let interactiveParams = MSALInteractiveTokenParameters(
                scopes: Self.scopes,
                webviewParameters: MSALWebviewParameters()
            )
            let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MSALResult, Error>) in
                application.acquireToken(with: interactiveParams) { result, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let result { continuation.resume(returning: result) }
                    else { continuation.resume(throwing: AuthError.unknown) }
                }
            }
            currentAccount = result.account
            return result.accessToken
        }
    }
}

enum AuthError: LocalizedError {
    case notConfigured
    case notSignedIn
    case unknown

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "MSAL not configured"
        case .notSignedIn: return "Not signed in to Microsoft"
        case .unknown: return "Unknown auth error"
        }
    }
}
```

**Step 2: Build**

```bash
xcodebuild -project SpeakSmooth.xcodeproj -scheme SpeakSmooth build
```

Expected: Build succeeds.

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add AuthManager with MSAL sign-in/out and silent token refresh"
```

---

### Task 11: Todo Client (Graph API)

**Files:**
- Modify: `SpeakSmooth/Graph/TodoClient.swift`
- Create: `SpeakSmoothTests/TodoClientTests.swift`

**Step 1: Write the failing test**

```swift
// SpeakSmoothTests/TodoClientTests.swift
import Testing
@testable import SpeakSmooth

@Suite("TodoClient Tests")
struct TodoClientTests {
    @Test("Builds create task request body correctly")
    func createTaskRequestBody() throws {
        let body = TodoClient.buildCreateTaskBody(
            title: "I should have gone.",
            bodyText: "Corrections: verb form\nOriginal: I should went."
        )
        let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        #expect(json["title"] as? String == "I should have gone.")
        let bodyObj = json["body"] as! [String: String]
        #expect(bodyObj["contentType"] == "text")
        #expect(bodyObj["content"]!.contains("verb form"))
    }

    @Test("Parses todo list response")
    func parseTodoListsResponse() throws {
        let json = """
        {
          "value": [
            {"id": "list-1", "displayName": "English Practice"},
            {"id": "list-2", "displayName": "Tasks"}
          ]
        }
        """
        let data = json.data(using: .utf8)!
        let lists = try TodoClient.parseTodoLists(data)
        #expect(lists.count == 2)
        #expect(lists[0].id == "list-1")
        #expect(lists[0].displayName == "English Practice")
    }
}
```

**Step 2: Run test to verify it fails**

```bash
xcodebuild test -project SpeakSmooth.xcodeproj -scheme SpeakSmooth -destination 'platform=macOS'
```

Expected: FAIL

**Step 3: Write the implementation**

```swift
// SpeakSmooth/Graph/TodoClient.swift
import Foundation

struct TodoList: Codable, Identifiable, Sendable {
    let id: String
    let displayName: String
}

final class TodoClient: Sendable {
    private static let graphBase = "https://graph.microsoft.com/v1.0"
    private let getAccessToken: @Sendable () async throws -> String

    init(getAccessToken: @escaping @Sendable () async throws -> String) {
        self.getAccessToken = getAccessToken
    }

    // MARK: - List Todo Lists

    func fetchTodoLists() async throws -> [TodoList] {
        let token = try await getAccessToken()
        let url = URL(string: "\(Self.graphBase)/me/todo/lists")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validateResponse(response)
        return try Self.parseTodoLists(data)
    }

    // MARK: - Create Task

    func createTask(
        listId: String,
        title: String,
        bodyText: String?
    ) async throws -> String {
        let token = try await getAccessToken()
        let url = URL(string: "\(Self.graphBase)/me/todo/lists/\(listId)/tasks")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.buildCreateTaskBody(title: title, bodyText: bodyText)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validateResponse(response)

        struct TaskResponse: Decodable { let id: String }
        let created = try JSONDecoder().decode(TaskResponse.self, from: data)
        return created.id
    }

    // MARK: - Testable Helpers

    static func buildCreateTaskBody(title: String, bodyText: String?) -> Data {
        var body: [String: Any] = ["title": title]
        if let bodyText, !bodyText.isEmpty {
            body["body"] = [
                "content": bodyText,
                "contentType": "text"
            ]
        }
        return try! JSONSerialization.data(withJSONObject: body)
    }

    static func parseTodoLists(_ data: Data) throws -> [TodoList] {
        struct ListsResponse: Decodable { let value: [TodoList] }
        return try JSONDecoder().decode(ListsResponse.self, from: data).value
    }

    private static func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw TodoClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TodoClientError.httpError(http.statusCode)
        }
    }
}

enum TodoClientError: LocalizedError {
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from Graph API"
        case .httpError(let code): return "Graph API error: HTTP \(code)"
        }
    }
}
```

**Step 4: Run test to verify it passes**

```bash
xcodebuild test -project SpeakSmooth.xcodeproj -scheme SpeakSmooth -destination 'platform=macOS'
```

Expected: PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add TodoClient with Graph API list/create operations"
```

---

## Phase 5: Orchestration & UI

### Task 12: Pipeline Coordinator

**Files:**
- Create: `SpeakSmooth/PipelineCoordinator.swift`

**Step 1: Write the implementation**

This wires all components together and drives the state machine.

```swift
// SpeakSmooth/PipelineCoordinator.swift
import Foundation

@MainActor
final class PipelineCoordinator {
    let appState: AppState
    let settings: AppSettings
    let authManager: AuthManager

    private let audioCaptureManager = AudioCaptureManager()
    private var segmentBuilder: SegmentBuilder?
    private let transcriptionService = TranscriptionService()
    private var todoClient: TodoClient?

    private var rewriter: (any RewriteService)?

    init(appState: AppState, settings: AppSettings, authManager: AuthManager) {
        self.appState = appState
        self.settings = settings
        self.authManager = authManager
        self.todoClient = TodoClient { [weak authManager] in
            guard let authManager else { throw AuthError.notSignedIn }
            return try await authManager.getAccessToken()
        }
        setupRewriter()
    }

    // MARK: - Setup

    private func setupRewriter() {
        if #available(macOS 26.0, *), AppleRewriter.isAvailable {
            rewriter = AppleRewriter()
        } else if let apiKey = settings.openRouterApiKey, !apiKey.isEmpty {
            rewriter = OpenRouterRewriter(apiKey: apiKey)
        }
    }

    func loadSTTModel() async {
        do {
            try await transcriptionService.loadModel()
        } catch {
            appState.handleError("Failed to load STT model: \(error.localizedDescription)")
        }
    }

    // MARK: - Recording Control

    func startRecording() {
        appState.startRecording()

        let builder = SegmentBuilder(
            sampleRate: .SAMPLERATE_48,
            silenceTimeoutSeconds: settings.silenceTimeoutSeconds
        )

        builder.onVoiceStarted = { [weak self] in
            Task { @MainActor in
                self?.appState.transitionTo(.speaking)
            }
        }

        builder.onVoiceEnded = { [weak self] in
            Task { @MainActor in
                guard self?.appState.pipelineState == .speaking else { return }
                self?.appState.transitionTo(.silenceCountdown)
            }
        }

        builder.onSegmentReady = { [weak self] segment in
            Task { @MainActor in
                await self?.processSegment(segment)
            }
        }

        audioCaptureManager.onAudioBuffer = { buffer, count in
            builder.feedAudio(buffer: buffer, count: count)
        }

        do {
            try audioCaptureManager.start()
            self.segmentBuilder = builder
        } catch {
            appState.handleError(error.localizedDescription)
        }
    }

    func stopRecording() {
        audioCaptureManager.stop()
        segmentBuilder = nil
        appState.stopRecording()
    }

    // MARK: - Pipeline Processing

    private func processSegment(_ segment: AudioSegment) async {
        // STT
        appState.transitionTo(.finalizingSTT)
        let transcript: TranscriptResult
        do {
            transcript = try await transcriptionService.transcribe(segment)
        } catch {
            appState.handleError("STT failed: \(error.localizedDescription)")
            appState.transitionTo(.listening) // Resume listening
            return
        }

        // Rewrite
        appState.transitionTo(.rewriting)
        var rewriteResult: RewriteResult
        do {
            if let rewriter {
                rewriteResult = try await rewriter.rewrite(transcript.originalTranscript)
            } else {
                // No rewriter available — use original as-is
                rewriteResult = RewriteResult(
                    revised: transcript.originalTranscript,
                    alternatives: [],
                    corrections: []
                )
            }
        } catch {
            // Fallback to OpenRouter if Apple FM failed
            if let apiKey = settings.openRouterApiKey, !apiKey.isEmpty {
                let fallback = OpenRouterRewriter(apiKey: apiKey)
                do {
                    rewriteResult = try await fallback.rewrite(transcript.originalTranscript)
                } catch {
                    // Ultimate fallback: save original
                    rewriteResult = RewriteResult(
                        revised: transcript.originalTranscript,
                        alternatives: [],
                        corrections: ["(rewrite unavailable)"]
                    )
                }
            } else {
                rewriteResult = RewriteResult(
                    revised: transcript.originalTranscript,
                    alternatives: [],
                    corrections: ["(rewrite unavailable)"]
                )
            }
        }

        // Save to To Do
        appState.transitionTo(.saving)
        guard let listId = settings.selectedTodoListId else {
            appState.handleError("No To Do list selected")
            appState.transitionTo(.listening)
            return
        }

        do {
            let bodyText = rewriteResult.formatTaskBody(original: transcript.originalTranscript)
            let taskId = try await todoClient!.createTask(
                listId: listId,
                title: rewriteResult.revised,
                bodyText: bodyText
            )

            appState.lastSavedTask = SavedTask(
                graphTaskId: taskId,
                title: rewriteResult.revised,
                body: bodyText,
                savedAt: Date()
            )
        } catch {
            appState.handleError("Save failed: \(error.localizedDescription)")
        }

        // Return to listening
        appState.transitionTo(.listening)
    }
}
```

**Step 2: Build**

```bash
xcodebuild -project SpeakSmooth.xcodeproj -scheme SpeakSmooth build
```

Expected: Build succeeds.

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add PipelineCoordinator wiring all services together"
```

---

### Task 13: MenuBar Popover UI

**Files:**
- Modify: `SpeakSmooth/Views/MenuBarPopover.swift`
- Modify: `SpeakSmooth/Views/Components/StatusIndicator.swift`
- Modify: `SpeakSmooth/Views/Components/TaskPreviewCard.swift`

**Step 1: Write StatusIndicator**

```swift
// SpeakSmooth/Views/Components/StatusIndicator.swift
import SwiftUI

struct StatusIndicator: View {
    let state: PipelineState

    private var color: Color {
        switch state {
        case .idle: return .secondary
        case .listening: return .green
        case .speaking, .silenceCountdown: return .red
        case .finalizingSTT, .rewriting, .saving: return .orange
        case .error: return .yellow
        }
    }

    private var shouldPulse: Bool {
        switch state {
        case .speaking, .finalizingSTT, .rewriting, .saving: return true
        default: return false
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .opacity(shouldPulse ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: shouldPulse)
    }
}
```

**Step 2: Write TaskPreviewCard**

```swift
// SpeakSmooth/Views/Components/TaskPreviewCard.swift
import SwiftUI

struct TaskPreviewCard: View {
    let task: SavedTask

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.title)
                .font(.body.weight(.medium))
                .lineLimit(3)

            if let body = task.body {
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            }

            Text(task.savedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
```

**Step 3: Write MenuBarPopover**

```swift
// SpeakSmooth/Views/MenuBarPopover.swift
import SwiftUI

struct MenuBarPopover: View {
    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings
    @Environment(AuthManager.self) private var authManager
    var coordinator: PipelineCoordinator?

    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("SpeakSmooth")
                    .font(.headline)
                Spacer()
                Button {
                    showSettings.toggle()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Main content
            VStack(spacing: 12) {
                // Mic toggle
                Button {
                    if appState.isRecording {
                        coordinator?.stopRecording()
                    } else {
                        coordinator?.startRecording()
                    }
                } label: {
                    Label(
                        appState.isRecording ? "Stop" : "Start",
                        systemImage: appState.isRecording ? "stop.circle.fill" : "mic.circle.fill"
                    )
                    .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(appState.isRecording ? .red : .accentColor)

                // Status
                HStack(spacing: 6) {
                    StatusIndicator(state: appState.pipelineState)
                    Text(appState.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 12)

            Divider()

            // Last saved task
            VStack(alignment: .leading, spacing: 6) {
                if let task = appState.lastSavedTask {
                    Text("Last saved:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TaskPreviewCard(task: task)
                } else {
                    Text("No tasks saved yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // Auth status
            HStack {
                Image(systemName: authManager.isSignedIn ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(authManager.isSignedIn ? .green : .secondary)
                VStack(alignment: .leading) {
                    Text(authManager.isSignedIn ? "Signed in" : "Not signed in")
                        .font(.caption)
                    if let listName = settings.selectedTodoListName {
                        Text("List: \(listName)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 320)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}
```

**Step 4: Build**

```bash
xcodebuild -project SpeakSmooth.xcodeproj -scheme SpeakSmooth build
```

Expected: Build succeeds.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add MenuBarPopover UI with status indicator and task preview"
```

---

### Task 14: Settings View

**Files:**
- Modify: `SpeakSmooth/Views/SettingsView.swift`

**Step 1: Write the implementation**

```swift
// SpeakSmooth/Views/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var todoLists: [TodoList] = []
    @State private var isLoadingLists = false
    @State private var apiKeyInput = ""

    var body: some View {
        @Bindable var settings = settings

        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.title2.weight(.semibold))

            // Silence timeout
            VStack(alignment: .leading, spacing: 4) {
                Text("Silence timeout")
                    .font(.headline)
                HStack {
                    Slider(value: $settings.silenceTimeoutSeconds, in: 1.0...10.0, step: 0.5)
                    Text("\(settings.silenceTimeoutSeconds, specifier: "%.1f")s")
                        .monospacedDigit()
                        .frame(width: 40)
                }
            }

            Divider()

            // Microsoft Account
            VStack(alignment: .leading, spacing: 8) {
                Text("Microsoft Account")
                    .font(.headline)

                if authManager.isSignedIn {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(authManager.accountName ?? "Signed in")
                        Spacer()
                        Button("Sign Out") {
                            try? authManager.signOut()
                        }
                    }
                } else {
                    Button("Sign In with Microsoft") {
                        Task { try? await authManager.signIn() }
                    }
                }
            }

            // To Do List picker
            if authManager.isSignedIn {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("To Do List")
                            .font(.headline)
                        Spacer()
                        if isLoadingLists {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }

                    Picker("List", selection: $settings.selectedTodoListId) {
                        Text("Select a list").tag(String?.none)
                        ForEach(todoLists) { list in
                            Text(list.displayName).tag(Optional(list.id))
                        }
                    }
                    .labelsHidden()
                    .onChange(of: settings.selectedTodoListId) { _, newValue in
                        settings.selectedTodoListName = todoLists.first { $0.id == newValue }?.displayName
                    }
                }
            }

            Divider()

            // OpenRouter API Key (optional)
            VStack(alignment: .leading, spacing: 4) {
                Text("OpenRouter API Key")
                    .font(.headline)
                Text("Optional. Used as LLM fallback when Apple Intelligence is unavailable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("sk-or-...", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        settings.openRouterApiKey = apiKeyInput.isEmpty ? nil : apiKeyInput
                    }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400, height: 480)
        .task {
            if authManager.isSignedIn {
                await loadLists()
            }
        }
    }

    private func loadLists() async {
        isLoadingLists = true
        defer { isLoadingLists = false }
        let client = TodoClient { try await authManager.getAccessToken() }
        do {
            todoLists = try await client.fetchTodoLists()
        } catch {
            print("Failed to load lists: \(error)")
        }
    }
}
```

**Step 2: Build**

```bash
xcodebuild -project SpeakSmooth.xcodeproj -scheme SpeakSmooth build
```

Expected: Build succeeds.

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add SettingsView with auth, list picker, and API key config"
```

---

### Task 15: Wire App Entry Point + Dynamic Icon

**Files:**
- Modify: `SpeakSmooth/SpeakSmoothApp.swift`

**Step 1: Update the app entry to wire everything together**

```swift
// SpeakSmooth/SpeakSmoothApp.swift
import SwiftUI

@main
struct SpeakSmoothApp: App {
    @State private var appState = AppState()
    @State private var settings = AppSettings()
    @State private var authManager = AuthManager()
    @State private var coordinator: PipelineCoordinator?

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(coordinator: coordinator)
                .environment(appState)
                .environment(settings)
                .environment(authManager)
        } label: {
            Image(systemName: appState.menuBarIconName)
        }
        .menuBarExtraStyle(.window)
        .onChange(of: appState.pipelineState) { _, _ in }
        .onAppear {
            let coord = PipelineCoordinator(
                appState: appState,
                settings: settings,
                authManager: authManager
            )
            coordinator = coord
            Task { await coord.loadSTTModel() }
        }
    }
}
```

> **Note:** `onAppear` on `MenuBarExtra` may not fire. If not, move initialization to an `init()` method or `NSApplicationDelegateAdaptor`. This may need adjustment during manual testing.

**Step 2: Build the full app**

```bash
xcodebuild -project SpeakSmooth.xcodeproj -scheme SpeakSmooth build
```

Expected: Build succeeds.

**Step 3: Run all tests**

```bash
xcodebuild test -project SpeakSmooth.xcodeproj -scheme SpeakSmooth -destination 'platform=macOS'
```

Expected: All tests pass (Settings, AppState, Rewrite parsing, TodoClient).

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: wire SpeakSmoothApp entry point with coordinator and dynamic menu bar icon"
```

---

## Phase 6: Polish & Manual Testing

### Task 16: Manual Integration Test

**Not automatable.** Run the app and verify each pipeline stage:

1. **Mic permission**: First launch should prompt. Grant it.
2. **Menu bar icon**: Appears as gray mic. Clicking opens popover.
3. **Start recording**: Tap Start. Icon turns red. Popover can close; icon stays red.
4. **Speak**: Say "I should went to store more early." Status should show "Hearing you..."
5. **Silence**: Wait 3 seconds. Status transitions through STT → Rewrite → Save.
6. **Settings**: Open settings. Sign into Microsoft. Select a To Do list.
7. **Full pipeline**: Record again. After silence, verify task appears in Microsoft To Do.
8. **Stop**: Tap Stop. Icon returns to gray.
9. **Error recovery**: Disconnect network. Record. Verify error shows and auto-dismisses.

### Task 17: Final Cleanup & Commit

1. Remove any `TODO: Replace` placeholder values (Azure AD client ID)
2. Verify `.gitignore` excludes build artifacts and Xcode user state
3. Run final build + test

```bash
# .gitignore
cat << 'EOF' > .gitignore
.DS_Store
*.xcodeproj/xcuserdata/
*.xcodeproj/project.xcworkspace/xcuserdata/
DerivedData/
build/
*.ipa
*.dSYM.zip
*.dSYM
EOF

git add -A
git commit -m "chore: add gitignore, final cleanup"
```

---

## Summary

| Phase | Tasks | Key Components |
|-------|-------|---------------|
| 1: Foundation | 1-4 | XcodeGen, MenuBarExtra, Settings, AppState |
| 2: Audio | 5-6 | AVAudioEngine, Silero VAD, SegmentBuilder |
| 3: Processing | 7-9 | WhisperKit STT, Apple FM Rewriter, OpenRouter fallback |
| 4: Microsoft | 10-11 | MSAL Auth, Graph API TodoClient |
| 5: Orchestration & UI | 12-15 | PipelineCoordinator, Popover, Settings, Icon |
| 6: Polish | 16-17 | Manual testing, cleanup |

**Total: 17 tasks, ~15 commits**

**Test coverage:** Settings, AppState, RewriteResult parsing, OpenRouter response parsing, TodoClient request/response formatting. Hardware-dependent components (audio, MSAL) tested manually.
