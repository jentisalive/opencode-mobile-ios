import Foundation

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct OpenCodeAPI: Sendable {
    var baseURL: URL
    var password: String
    var session: URLSession = .shared

    func request(_ path: String, method: String = "GET", directory: String? = nil, body: JSONValue? = nil) throws -> URLRequest {
        guard var url = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(url.scheme ?? ""), url.host != nil else { throw APIError(message: "Invalid server URL") }
        url.path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path
        if !url.path.hasPrefix("/") { url.path = "/" + url.path }
        if let directory, !directory.isEmpty { url.queryItems = [URLQueryItem(name: "directory", value: directory)] }
        guard let endpoint = url.url else { throw APIError(message: "Invalid endpoint") }
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.timeoutInterval = path == "/global/health" ? 2 : (path.hasSuffix("/oauth/callback") ? 600 : 30)
        request.setValue("Basic " + Data("opencode:\(password)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if method == "POST" || method == "PATCH" { request.httpBody = Data("{}".utf8); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }
    func call(_ path: String, method: String = "GET", directory: String? = nil, body: JSONValue? = nil) async throws -> JSONValue {
        let (data, response) = try await session.data(for: request(path, method: method, directory: directory, body: body))
        guard let http = response as? HTTPURLResponse else { throw APIError(message: "Invalid server response") }
        guard (200..<300).contains(http.statusCode) else {
            let value = try? JSONDecoder().decode(JSONValue.self, from: data)
            let message = value?["message"].string ?? ""
            throw APIError(message: message.isEmpty ? "Server returned HTTP \(http.statusCode)" : message)
        }
        if data.isEmpty { return .null }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
    func events(directory: String?, onEvent: @escaping @Sendable (JSONValue) async -> Void) async throws {
        var req = try request("/event", directory: directory)
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 60
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 86400
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw APIError(message: "Event stream rejected") }
        var parser = SSEParser()
        for try await byte in bytes {
            try Task.checkCancellation()
            if let data = try parser.feed(byte: byte), let event = try? JSONDecoder().decode(JSONValue.self, from: Data(data.utf8)) {
                await onEvent(event)
            }
        }
    }
}

struct SSEParser {
    private var lines: [String] = []
    private var buffer = Data()
    private var previousCR = false
    private var eventSize = 0
    mutating func feed(byte: UInt8) throws -> String? {
        if byte == 10 && previousCR { previousCR = false; return nil }
        previousCR = byte == 13
        if byte == 10 || byte == 13 {
            let line = String(decoding: buffer, as: UTF8.self)
            buffer.removeAll(keepingCapacity: true)
            let event = feed(line)
            guard eventSize <= 8 * 1024 * 1024 else { throw APIError(message: "Server event exceeds the size limit") }
            return event
        }
        buffer.append(byte)
        guard buffer.count <= 8 * 1024 * 1024 else { throw APIError(message: "Server event line exceeds the size limit") }
        return nil
    }
    mutating func feed(_ line: String) -> String? {
        if line.isEmpty {
            defer { lines.removeAll(keepingCapacity: true); eventSize = 0 }
            return lines.isEmpty ? nil : lines.joined(separator: "\n")
        }
        if line.hasPrefix("data:") {
            var value = String(line.dropFirst(5))
            if value.hasPrefix(" ") { value.removeFirst() }
            lines.append(value)
            eventSize += value.utf8.count
        }
        return nil
    }
}
