import Foundation
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
