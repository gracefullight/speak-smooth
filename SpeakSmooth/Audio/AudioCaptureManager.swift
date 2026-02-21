import AVFoundation
import AppKit

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

    static func openMicrophonePrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func start() throws {
        guard Self.isMicAuthorized else {
            throw AudioCaptureError.micPermissionDenied
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let nativeFormat = inputNode.inputFormat(forBus: 0)

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
