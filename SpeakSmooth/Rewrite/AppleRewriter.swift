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
