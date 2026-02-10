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
