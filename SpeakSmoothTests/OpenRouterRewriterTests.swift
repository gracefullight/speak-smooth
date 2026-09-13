import Foundation
import Testing
@testable import SpeakSmooth

@Suite("OpenRouterRewriter Tests")
struct OpenRouterRewriterTests {
    @Test("Parses valid OpenRouter response body")
    func parseResponseBody() throws {
        let resultJSON = RewriteResult(revised: "Hello there.", alternatives: [], corrections: ["greeting"])
        let content = String(decoding: try JSONEncoder().encode(resultJSON), as: UTF8.self)
        let data = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]])
        let result = try OpenRouterRewriter.parseResponse(data)
        #expect(result.revised == "Hello there.")
        #expect(result.corrections == ["greeting"])
    }

    @Test("Parses fenced JSON and trims the revised sentence")
    func fencedJSON() throws {
        let content = "```json\n{\"revised\":\" Hello. \",\"alternatives\":[],\"corrections\":[]}\n```"
        let data = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]])
        #expect(try OpenRouterRewriter.parseResponse(data).revised == "Hello.")
    }

    @Test("Rejects blank revisions and empty choices")
    func invalidResponses() throws {
        let content = "{\"revised\":\" \",\"alternatives\":[],\"corrections\":[]}"
        let blank = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]])
        #expect(throws: (any Error).self) { try OpenRouterRewriter.parseResponse(blank) }
        #expect(throws: (any Error).self) { try OpenRouterRewriter.parseResponse(Data("{\"choices\":[]}".utf8)) }
    }

    @Test("Builds correct request body")
    func buildRequestBody() throws {
        let body = OpenRouterRewriter.buildRequestBody(for: "I has a dog.")
        let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        let messages = json["messages"] as! [[String: String]]
        #expect(messages.count == 2)
        #expect(messages[0]["role"] == "system")
        #expect(messages[1]["content"] == "I has a dog.")
    }
}
