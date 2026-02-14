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

            let payload = """
            {
              "choices": [{
                "message": {
                  "content": "{\\\"revised\\\":\\\"I should have gone.\\\",\\\"alternatives\\\":[],\\\"corrections\\\":[\\\"verb form\\\"]}"
                }
              }]
            }
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(payload.utf8))
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
    @Test("Coordinator start/stop covers mic-denied path")
    func coordinatorStartStop() {
        let appState = AppState()
        let settings = AppSettings()
        let remindersManager = RemindersManager()
        let coordinator = PipelineCoordinator(appState: appState, settings: settings, remindersManager: remindersManager)

        coordinator.startRecording()
        if case .error = appState.pipelineState {
            #expect(true)
        } else {
            Issue.record("Expected error state after failed start")
        }

        coordinator.stopRecording()
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
        let settings = AppSettings()
        settings.selectedReminderListName = "English Practice"
        let remindersManager = RemindersManager()
        remindersManager.setAuthorizationStatusForTesting(.authorized)

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
        let popoverHost = NSHostingView(rootView: popover)
        popoverHost.layoutSubtreeIfNeeded()
        _ = popoverHost.fittingSize

        let settingsView = SettingsView()
            .environment(settings)
            .environment(remindersManager)
        let settingsHost = NSHostingView(rootView: settingsView)
        settingsHost.layoutSubtreeIfNeeded()
        _ = settingsHost.fittingSize

        let indicatorHost = NSHostingView(rootView: StatusIndicator(state: .rewriting))
        indicatorHost.layoutSubtreeIfNeeded()
        _ = indicatorHost.fittingSize

        let cardHost = NSHostingView(rootView: TaskPreviewCard(task: appState.lastSavedTask!))
        cardHost.layoutSubtreeIfNeeded()
        _ = cardHost.fittingSize
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
