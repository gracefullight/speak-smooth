// SpeakSmooth/Rewrite/OpenRouterRewriter.swift
import Foundation

final class OpenRouterRewriter: RewriteService, @unchecked Sendable {
    private let apiKey: String
    private let session: URLSession
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

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func rewrite(_ original: String) async throws -> RewriteResult {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("SpeakSmooth", forHTTPHeaderField: "X-Title")
        request.httpBody = Self.buildRequestBody(for: original)

        let (data, response) = try await session.data(for: request)

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

        guard let jsonData = content.data(using: .utf8) else {
            throw RewriteError.invalidResponse
        }

        return try JSONDecoder().decode(RewriteResult.self, from: jsonData)
    }
}
