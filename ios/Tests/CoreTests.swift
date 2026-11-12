import XCTest
@testable import OpenCode

final class CoreTests: XCTestCase {
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
