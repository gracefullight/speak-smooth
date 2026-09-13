import AppKit
import EventKit
import Foundation
import SwiftUI
import Testing
@testable import SpeakSmooth

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (URLResponse, Data))?
    private static let lock = NSLock()

    static func setHandler(_ handler: @escaping (URLRequest) throws -> (URLResponse, Data)) {
        lock.lock()
        requestHandler = handler
        lock.unlock()
    }

    static func clearHandler() {
        lock.lock()
        requestHandler = nil
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.requestHandler
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "MockURLProtocol", code: -1))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite("Coverage Boost Tests", .serialized)
struct CoverageBoostTests {
    private func makeMockSession(handler: @escaping (URLRequest) throws -> (URLResponse, Data)) -> URLSession {
        MockURLProtocol.setHandler(handler)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    @Test("OpenRouter rewrite success path")
    func openRouterRewriteSuccess() async throws {
        defer { MockURLProtocol.clearHandler() }

        let session = makeMockSession { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
            #expect(request.value(forHTTPHeaderField: "X-Title") == "SpeakSmooth")

            let result = RewriteResult(revised: "I should have gone.", alternatives: [], corrections: ["verb form"])
            let content = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
            let payload = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]])
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, payload)
        }

        let rewriter = OpenRouterRewriter(apiKey: "sk-test", session: session)
        let result = try await rewriter.rewrite("I should went.")
        #expect(result.revised == "I should have gone.")
        #expect(result.corrections == ["verb form"])
    }

    @Test("OpenRouter rewrite maps HTTP errors")
    func openRouterRewriteHttpError() async {
        defer { MockURLProtocol.clearHandler() }

        let session = makeMockSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let rewriter = OpenRouterRewriter(apiKey: "sk-test", session: session)

        do {
            _ = try await rewriter.rewrite("text")
            Issue.record("Expected RewriteError.networkError")
        } catch let error as RewriteError {
            switch error {
            case .networkError:
                #expect(true)
            default:
                Issue.record("Expected networkError, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @MainActor
    @Test("Coordinator start/stop is stable")
    func coordinatorStartStop() async {
        let appState = AppState()
        let settings = makeTestSettings()
        let remindersManager = RemindersManager()
        let coordinator = PipelineCoordinator(appState: appState, settings: settings, remindersManager: remindersManager)

        coordinator.startRecording()

        coordinator.stopRecording()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(appState.pipelineState == .idle)
    }

    @Test("TranscriptionService throws when model not loaded")
    func transcriptionModelNotLoaded() async {
        let service = TranscriptionService()
        let segment = AudioSegment(pcmFloats: [0.1, 0.2], durationSeconds: 0.01)

        do {
            _ = try await service.transcribe(segment)
            Issue.record("Expected modelNotLoaded")
        } catch let error as TranscriptionError {
            switch error {
            case .modelNotLoaded:
                #expect(true)
            default:
                Issue.record("Expected modelNotLoaded, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @MainActor
    @Test("SwiftUI views render under key branches")
    func viewsRender() {
        let appState = AppState()
        let settings = makeTestSettings()
        settings.selectedReminderListName = "English Practice"
        let remindersManager = RemindersManager()
        remindersManager.setAuthorizationStatusForTesting(.fullAccess)

        appState.pipelineState = .speaking
        appState.lastSavedTask = SavedTask(
            reminderId: "reminder-1",
            title: "I should have gone.",
            body: "Corrections: verb form",
            savedAt: .now
        )

        let coordinator = PipelineCoordinator(appState: appState, settings: settings, remindersManager: remindersManager)

        let popover = MenuBarPopover(coordinator: coordinator)
            .environment(appState)
            .environment(settings)
            .environment(remindersManager)
            .background(Color(nsColor: .windowBackgroundColor))
        let popoverHost = NSHostingView(rootView: popover)
        popoverHost.layoutSubtreeIfNeeded()
        #expect(popoverHost.fittingSize.width == 360)
        exportSnapshot(popoverHost, name: "saved", size: NSSize(width: 360, height: 500))

        appState.startRecording()
        appState.queuedSegmentCount = 2
        appState.transitionTo(.rewriting)
        exportSnapshot(popoverHost, name: "recording", size: NSSize(width: 360, height: 560))
        appState.stopRecording()
        appState.queuedSegmentCount = 0
        appState.handleError("The selected Reminders list is no longer available. Choose another list in Settings and retry saving.")
        appState.pendingReminders = [PendingReminder(title: "I should have gone to the meeting earlier.", body: "Original: I should went.", listId: "missing")]
        exportSnapshot(popoverHost, name: "save-failure", size: NSSize(width: 360, height: 650))

        let settingsView = SettingsView()
            .environment(settings)
            .environment(remindersManager)
            .background(Color(nsColor: .windowBackgroundColor))
        let settingsHost = NSHostingView(rootView: settingsView)
        settingsHost.layoutSubtreeIfNeeded()
        #expect(settingsHost.fittingSize.width >= 460)
        exportSnapshot(settingsHost, name: "settings", size: NSSize(width: 500, height: 680))

        let indicatorHost = NSHostingView(rootView: StatusIndicator(state: .rewriting))
        indicatorHost.layoutSubtreeIfNeeded()
        _ = indicatorHost.fittingSize

        let cardHost = NSHostingView(rootView: TaskPreviewCard(task: appState.lastSavedTask!))
        cardHost.layoutSubtreeIfNeeded()
        _ = cardHost.fittingSize
    }

    @MainActor
    private func exportSnapshot(_ view: NSView, name: String, size: NSSize) {
        guard let path = ProcessInfo.processInfo.environment["SPEAKSMOOTH_SNAPSHOT_DIR"] else { return }
        do {
            let directory = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let size = name == "settings" ? size : NSSize(width: size.width, height: view.fittingSize.height)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = view
            view.frame = NSRect(origin: .zero, size: size)
            view.layoutSubtreeIfNeeded()
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: directory.appendingPathComponent("\(name).png"))
            window.contentView = nil
        } catch {
            Issue.record("Snapshot failed: \(error)")
        }
    }

    @Test("Error descriptions remain stable")
    func errorDescriptions() {
        #expect(RewriteError.unavailable.errorDescription == "Rewrite service unavailable")
        #expect(RewriteError.invalidResponse.errorDescription == "Could not parse rewrite response")
        #expect(RemindersError.accessDenied.errorDescription == "Reminders access is not allowed")
        #expect(RemindersError.listNotFound.errorDescription == "Selected Reminders list not found")
        #expect(AudioCaptureError.micPermissionDenied.errorDescription == "Microphone permission denied")
        #expect(TranscriptionError.emptyTranscript.errorDescription == "No speech detected in segment")
        #expect(PipelineState.error("x").isError)
        #expect(!PipelineState.idle.isError)
    }
}
