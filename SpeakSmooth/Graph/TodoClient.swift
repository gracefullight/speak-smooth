// SpeakSmooth/Graph/TodoClient.swift
import Foundation

struct TodoList: Codable, Identifiable, Sendable {
    let id: String
    let displayName: String
}

final class TodoClient: Sendable {
    private static let graphBase = "https://graph.microsoft.com/v1.0"
    private let getAccessToken: @Sendable () async throws -> String
    private let session: URLSession

    init(
        getAccessToken: @escaping @Sendable () async throws -> String,
        session: URLSession = .shared
    ) {
        self.getAccessToken = getAccessToken
        self.session = session
    }

    // MARK: - List Todo Lists

    func fetchTodoLists() async throws -> [TodoList] {
        let token = try await getAccessToken()
        let url = URL(string: "\(Self.graphBase)/me/todo/lists")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try Self.validateResponse(response)
        return try Self.parseTodoLists(data)
    }

    // MARK: - Create Task

    func createTask(
        listId: String,
        title: String,
        bodyText: String?
    ) async throws -> String {
        let token = try await getAccessToken()
        let url = URL(string: "\(Self.graphBase)/me/todo/lists/\(listId)/tasks")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.buildCreateTaskBody(title: title, bodyText: bodyText)

        let (data, response) = try await session.data(for: request)
        try Self.validateResponse(response)

        struct TaskResponse: Decodable { let id: String }
        let created = try JSONDecoder().decode(TaskResponse.self, from: data)
        return created.id
    }

    // MARK: - Testable Helpers

    static func buildCreateTaskBody(title: String, bodyText: String?) -> Data {
        var body: [String: Any] = ["title": title]
        if let bodyText, !bodyText.isEmpty {
            body["body"] = [
                "content": bodyText,
                "contentType": "text"
            ]
        }
        return try! JSONSerialization.data(withJSONObject: body)
    }

    static func parseTodoLists(_ data: Data) throws -> [TodoList] {
        struct ListsResponse: Decodable { let value: [TodoList] }
        return try JSONDecoder().decode(ListsResponse.self, from: data).value
    }

    private static func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw TodoClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TodoClientError.httpError(http.statusCode)
        }
    }
}

enum TodoClientError: LocalizedError {
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from Graph API"
        case .httpError(let code): return "Graph API error: HTTP \(code)"
        }
    }
}
