// SpeakSmooth/STT/TranscriptionService.swift
import AVFoundation
import Foundation
import Speech
@preconcurrency import WhisperKit

struct TranscriptResult: Sendable {
    let originalTranscript: String
}

actor TranscriptionService {
    private enum STTEngine {
        case appleOnDevice
        case whisper
    }

    private var whisperKit: WhisperKit?
    private var speechRecognizer: SFSpeechRecognizer?
    private var sttEngine: STTEngine?
    private(set) var isModelLoaded = false
    private(set) var loadedModelName: String?

    func loadModel(allowSpeechPermissionPrompt: Bool = true) async throws {
        if isModelLoaded, sttEngine != nil { return }

        // During background preload, defer setup if speech permission has never been asked yet.
        // We'll request permission when the user actually records.
        if !allowSpeechPermissionPrompt, SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            return
        }

        if try await setupAppleOnDeviceSTT(allowPermissionPrompt: allowSpeechPermissionPrompt) {
            return
        }

        try await loadWhisperFallback()
    }

    func transcribe(_ segment: AudioSegment) async throws -> TranscriptResult {
        guard let sttEngine else {
            throw TranscriptionError.modelNotLoaded
        }

        switch sttEngine {
        case .appleOnDevice:
            do {
                return try await transcribeWithAppleSpeech(segment)
            } catch {
                try await loadWhisperFallback()
                return try await transcribeWithWhisper(segment)
            }
        case .whisper:
            return try await transcribeWithWhisper(segment)
        }
    }

    private func setupAppleOnDeviceSTT(allowPermissionPrompt: Bool) async throws -> Bool {
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) ?? SFSpeechRecognizer()
        guard let recognizer else { return false }

        let authorizationStatus: SFSpeechRecognizerAuthorizationStatus
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            authorizationStatus = .authorized
        case .notDetermined:
            guard allowPermissionPrompt else { return false }
            authorizationStatus = await requestSpeechAuthorization()
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }

        guard authorizationStatus == .authorized else { return false }
        guard recognizer.supportsOnDeviceRecognition else { return false }

        speechRecognizer = recognizer
        sttEngine = .appleOnDevice
        isModelLoaded = true
        loadedModelName = "apple-speech-on-device"
        return true
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func loadWhisperFallback() async throws {
        if sttEngine == .whisper, whisperKit != nil {
            isModelLoaded = true
            return
        }

        let candidateModels = [
            "base.en",
            "base",
            "tiny.en",
            "tiny",
            "openai_whisper-base.en",
            "openai_whisper-base"
        ]

        var lastError: Error?
        for modelName in candidateModels {
            do {
                whisperKit = try await WhisperKit(
                    model: modelName,
                    verbose: false,
                    load: true,
                    download: true
                )
                sttEngine = .whisper
                isModelLoaded = true
                loadedModelName = modelName
                return
            } catch {
                lastError = error
            }
        }

        throw TranscriptionError.modelLoadFailed(lastError?.localizedDescription ?? "Unknown model load failure")
    }

    private func transcribeWithWhisper(_ segment: AudioSegment) async throws -> TranscriptResult {
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

    private func transcribeWithAppleSpeech(_ segment: AudioSegment) async throws -> TranscriptResult {
        guard let speechRecognizer else {
            throw TranscriptionError.modelNotLoaded
        }

        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw TranscriptionError.speechPermissionDenied
        }

        guard speechRecognizer.supportsOnDeviceRecognition else {
            throw TranscriptionError.onDeviceSpeechUnavailable
        }

        let tempURL = try writeSegmentToTemporaryWav(segment)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let request = SFSpeechURLRecognitionRequest(url: tempURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        let text = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            var resumed = false
            var task: SFSpeechRecognitionTask?
            task = speechRecognizer.recognitionTask(with: request) { result, error in
                guard !resumed else { return }
                if let error {
                    resumed = true
                    task?.cancel()
                    continuation.resume(throwing: error)
                    return
                }
                guard let result, result.isFinal else { return }
                resumed = true
                task?.cancel()
                continuation.resume(
                    returning: result.bestTranscription.formattedString
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        }

        guard !text.isEmpty else {
            throw TranscriptionError.emptyTranscript
        }

        return TranscriptResult(originalTranscript: text)
    }

    private func writeSegmentToTemporaryWav(_ segment: AudioSegment) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("speaksmooth-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        guard let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1) else {
            throw TranscriptionError.audioFileBuildFailed
        }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(segment.pcmFloats.count)
        ) else {
            throw TranscriptionError.audioFileBuildFailed
        }

        buffer.frameLength = AVAudioFrameCount(segment.pcmFloats.count)
        guard let channel = buffer.floatChannelData?[0] else {
            throw TranscriptionError.audioFileBuildFailed
        }

        _ = segment.pcmFloats.withUnsafeBytes { sourceBytes in
            memcpy(channel, sourceBytes.baseAddress, sourceBytes.count)
        }

        let audioFile = try AVAudioFile(
            forWriting: tempURL,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try audioFile.write(from: buffer)
        return tempURL
    }
}

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case modelLoadFailed(String)
    case speechPermissionDenied
    case onDeviceSpeechUnavailable
    case audioFileBuildFailed
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "STT engine not loaded"
        case .modelLoadFailed(let reason): return "Failed to load STT model: \(reason)"
        case .speechPermissionDenied: return "Speech recognition permission denied"
        case .onDeviceSpeechUnavailable: return "On-device speech recognition unavailable"
        case .audioFileBuildFailed: return "Could not prepare audio for speech recognition"
        case .emptyTranscript: return "No speech detected in segment"
        }
    }
}
