import AVFoundation
import AppKit

protocol AudioCapturing: AnyObject {
    var isRunning: Bool { get }
    var onAudioBuffer: (@Sendable (_ buffer: UnsafePointer<Float>, _ count: UInt) -> Void)? { get set }
    func start() throws
    func stop()
}

final class AudioCaptureManager: AudioCapturing, @unchecked Sendable {
    private var audioEngine: AVAudioEngine?
    private let bufferSize: AVAudioFrameCount = 4800
    var onAudioBuffer: (@Sendable (_ buffer: UnsafePointer<Float>, _ count: UInt) -> Void)?

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
        guard !isRunning else { return }
        guard Self.isMicAuthorized else {
            throw AudioCaptureError.micPermissionDenied
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        guard nativeFormat.sampleRate > 0, nativeFormat.channelCount > 0 else {
            throw AudioCaptureError.formatError
        }

        guard let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: nativeFormat, to: recordingFormat) else {
            throw AudioCaptureError.formatError
        }

        let onAudioBuffer = self.onAudioBuffer
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: nativeFormat) { buffer, _ in
            guard let output = Self.resample(buffer, using: converter),
                  let channel = output.floatChannelData?[0] else { return }
            onAudioBuffer?(channel, UInt(output.frameLength))
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw error
        }
        self.audioEngine = engine
    }

    static func resample(_ buffer: AVAudioPCMBuffer, using converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        let target = converter.outputFormat
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        let input = ConverterInput(buffer: buffer)
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in input.next(status: status) }
        return error == nil && output.frameLength > 0 ? output : nil
    }

    func stop() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        onAudioBuffer = nil
    }
}

// AVAudioConverter invokes this input provider synchronously during conversion.
private final class ConverterInput: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    private var supplied = false
    init(buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    func next(status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard !supplied else {
            status.pointee = .noDataNow
            return nil
        }
        supplied = true
        status.pointee = .haveData
        return buffer
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
