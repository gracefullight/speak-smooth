import Foundation
import Testing
@testable import SpeakSmooth

@Suite("TodoClient Tests")
struct TodoClientTests {
    @Test("Builds create task request body correctly")
    func createTaskRequestBody() throws {
        let body = TodoClient.buildCreateTaskBody(
            title: "I should have gone.",
            bodyText: "Corrections: verb form\nOriginal: I should went."
        )
        let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        #expect(json["title"] as? String == "I should have gone.")
        let bodyObj = json["body"] as! [String: String]
        #expect(bodyObj["contentType"] == "text")
        #expect(bodyObj["content"]!.contains("verb form"))
    }

    @Test("Parses todo list response")
    func parseTodoListsResponse() throws {
        let json = """
        {
          "value": [
            {"id": "list-1", "displayName": "English Practice"},
            {"id": "list-2", "displayName": "Tasks"}
          ]
        }
        """
        let data = json.data(using: .utf8)!
        let lists = try TodoClient.parseTodoLists(data)
        #expect(lists.count == 2)
        #expect(lists[0].id == "list-1")
        #expect(lists[0].displayName == "English Practice")
    }

    @Test("Omits body when bodyText is nil")
    func createTaskRequestBodyWithoutBody() throws {
        let body = TodoClient.buildCreateTaskBody(
            title: "Clean title",
            bodyText: nil
        )
        let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        #expect(json["title"] as? String == "Clean title")
        #expect(json["body"] == nil)
    }
}
