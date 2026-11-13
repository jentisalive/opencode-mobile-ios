import XCTest
import Network
@testable import OpenCode

final class CoreTests: XCTestCase {
    func testAppCanReachAuthenticatedLoopbackServer() async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let queue = DispatchQueue(label: "test.loopback")
        let ready = expectation(description: "Local listener ready")
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            var request = Data()
            func receive() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, complete, error in
                    if let data { request.append(data) }
                    if String(decoding: request, as: UTF8.self).contains("\r\n\r\n") {
                        let authorized = String(decoding: request, as: UTF8.self).lowercased().contains("authorization: basic " + Data("opencode:test-only".utf8).base64EncodedString().lowercased())
                        let body = authorized ? "{\"healthy\":true}" : "{}"
                        let status = authorized ? "200 OK" : "401 Unauthorized"
                        let response = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                    } else if error != nil || complete { connection.cancel() }
                    else { receive() }
                }
            }
            receive()
        }
        listener.start(queue: queue)
        defer { listener.cancel() }
        await fulfillment(of: [ready], timeout: 10)
        let port = try XCTUnwrap(listener.port)
        let api = OpenCodeAPI(baseURL: URL(string: "http://127.0.0.1:\(port.rawValue)")!, password: "test-only")
        let health = try await api.call("/global/health")
        XCTAssertTrue(health["healthy"].bool)
    }
    func testSkillImportRejectsTraversalAndPreservesExistingSkill() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let skills = SkillFiles(root: root)
        XCTAssertThrowsError(try skills.importMarkdown("---\nname: ../outside\n---\nUnsafe path"))
        let markdown = try SkillFiles.render(name: "review-code", description: "Review: code\nKeep quotes: \"yes\"", instructions: "Read the diff.")
        try skills.importMarkdown(markdown)
        XCTAssertThrowsError(try skills.importMarkdown(markdown + "Overwrite"))
        let files = try skills.list()
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(files.first), encoding: .utf8), markdown)
    }
    func testStreamingCodeKeepsIndentationAndEmbeddedFences() {
        let blocks = MessageBlock.parse("Example:\n````swift\n  let x = 1\n```\n````\nDone.\n~~~python\nprint('still streaming')")
        XCTAssertEqual(blocks, [
            MessageBlock(kind: .text, content: "Example:"),
            MessageBlock(kind: .code("swift"), content: "  let x = 1\n```"),
            MessageBlock(kind: .text, content: "Done."),
            MessageBlock(kind: .code("python"), content: "print('still streaming')")
        ])
    }
    func testSSEByteBoundariesCRLFAndUTF8() throws {
        var parser = SSEParser()
        var events: [String] = []
        for byte in Data("data: привет\r\n\r\ndata: second\n\ndata: third\r\r".utf8) {
            if let event = try parser.feed(byte: byte) { events.append(event) }
        }
        XCTAssertEqual(events, ["привет", "second", "third"])
    }
    func testSSEMultilineAndHeartbeat() {
        var parser = SSEParser()
        XCTAssertNil(parser.feed(": heartbeat"))
        XCTAssertNil(parser.feed(""))
        XCTAssertNil(parser.feed("event: message"))
        XCTAssertNil(parser.feed("data: {\"type\":\"message.updated\","))
        XCTAssertNil(parser.feed("data: \"properties\":{}}"))
        XCTAssertEqual(parser.feed(""), "{\"type\":\"message.updated\",\n\"properties\":{}}")
        XCTAssertNil(parser.feed(""))
    }
    func testRequestKeepsPasswordOutOfURLAndEscapesDirectory() throws {
        let api = OpenCodeAPI(baseURL: URL(string: "http://127.0.0.1:4096")!, password: "a:b&secret")
        let request = try api.request("/session", method: "POST", directory: "/Projects/A & B/日本語", body: .object(["title": .string("Hello")]))
        let url = try XCTUnwrap(request.url)
        XCTAssertFalse(url.absoluteString.contains("secret"))
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "/Projects/A & B/日本語")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic " + Data("opencode:a:b&secret".utf8).base64EncodedString())
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(request.httpBody))["title"].string, "Hello")
    }
    func testToolMessageRoundTrip() throws {
        let example = Data("[{\"info\":{\"id\":\"m1\",\"role\":\"assistant\",\"tokens\":{\"input\":10}},\"parts\":[{\"id\":\"p1\",\"type\":\"tool\",\"state\":{\"status\":\"completed\",\"output\":\"ok\"}}]}]".utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: example)
        let message = ChatMessage(info: value.array[0]["info"], parts: value.array[0]["parts"].array)
        XCTAssertEqual(message.id, "m1")
        XCTAssertFalse(message.isUser)
        XCTAssertEqual(message.parts[0]["state"]["output"].string, "ok")
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)), value)
    }
}
