import Foundation
import Testing
@testable import SpeakSmooth

@Suite("OpenRouterRewriter Tests")
struct OpenRouterRewriterTests {
    @Test("Parses valid OpenRouter response body")
    func parseResponseBody() throws {
        let responseJSON = """
        {
          "id": "gen-123",
          "choices": [{
            "message": {
              "role": "assistant",
              "content": "{\\"revised\\": \\"Hello there.\\", \\"alternatives\\": [], \\"corrections\\": [\\"greeting\\"]}"
            },
            "finish_reason": "stop"
          }],
          "model": "openrouter/free"
        }
        """
        let data = responseJSON.data(using: .utf8)!
        let result = try OpenRouterRewriter.parseResponse(data)
        #expect(result.revised == "Hello there.")
        #expect(result.corrections == ["greeting"])
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
