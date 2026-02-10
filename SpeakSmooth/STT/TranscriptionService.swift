// SpeakSmooth/STT/TranscriptionService.swift
import Foundation
@preconcurrency import WhisperKit

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
