import XCTest
@testable import OpenCode

private final class ChatURLProtocol: URLProtocol {
    static var handler: ((ChatURLProtocol) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.handler?(self) }
    override func stopLoading() {}

    func reply(statusCode: Int = 200) {
        let path = request.url!.path
        let body: String
        if path.hasSuffix("/message") {
            body = #"[{"info":{"id":"old-message","role":"assistant"},"parts":[]}]"#
        } else if path.hasSuffix("/status") {
            body = #"{"session-a":{"type":"busy"}}"#
        } else if path == "/permission" {
            body = #"[{"id":"permission-a","sessionID":"session-a"}]"#
        } else { body = "[]" }
        let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

private final class PendingRequests {
    private let lock = NSLock()
    private var requests: [ChatURLProtocol] = []
    let received: XCTestExpectation
    init(received: XCTestExpectation) { self.received = received }
    func accept(_ request: ChatURLProtocol) {
        lock.lock(); requests.append(request); lock.unlock()
        received.fulfill()
    }
    func release(statusCode: Int = 200) {
        lock.lock(); let pending = requests; requests = []; lock.unlock()
        pending.forEach { $0.reply(statusCode: statusCode) }
    }
}

final class ChatStateTests: XCTestCase {
    private let session = Session(raw: .object(["id": .string("session-a"), "directory": .string("/project")]))

    @MainActor private func makeStore(_ pending: PendingRequests) -> AppStore {
        ChatURLProtocol.handler = { pending.accept($0) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ChatURLProtocol.self]
        let api = OpenCodeAPI(baseURL: URL(string: "http://127.0.0.1:4096")!, password: "test", session: URLSession(configuration: configuration))
        let store = AppStore(api: api)
        store.selected = session
        store.directory = session.directory
        return store
    }

    @MainActor func testOldHistoryCannotRepopulateReopenedConversation() async throws {
        let received = expectation(description: "History and state requests started")
        received.expectedFulfillmentCount = 4
        let pending = PendingRequests(received: received)
        let store = makeStore(pending)
        let refresh = Task { try await store.refreshChat() }
        await fulfillment(of: [received], timeout: 5)
        store.newChat()
        // Returning to the same session ID must still invalidate the old load.
        store.selected = session
        pending.release()
        try await refresh.value
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertFalse(store.busy)
    }

    @MainActor func testHistorySnapshotCannotOverwriteNewerStreamedText() async throws {
        let received = expectation(description: "Snapshot requested")
        received.expectedFulfillmentCount = 4
        let pending = PendingRequests(received: received)
        let store = makeStore(pending)
        let refresh = Task { try await store.refreshChat() }
        await fulfillment(of: [received], timeout: 5)
        store.messages = [ChatMessage(info: .object(["id": .string("live-message")]), parts: [])]
        store.revision += 1
        pending.release()
        try await refresh.value
        XCTAssertEqual(store.messages.map(\.id), ["live-message"])
        XCTAssertEqual(store.permissions.first?["id"].string, "permission-a")
    }

    @MainActor func testStoppingInvalidatesPendingHistory() async throws {
        let received = expectation(description: "Snapshot requested before stop")
        received.expectedFulfillmentCount = 4
        let pending = PendingRequests(received: received)
        let store = makeStore(pending)
        let refresh = Task { try await store.refreshChat() }
        await fulfillment(of: [received], timeout: 5)
        store.stop()
        pending.release()
        try await refresh.value
        XCTAssertFalse(store.connected)
        XCTAssertFalse(store.busy)
        XCTAssertTrue(store.permissions.isEmpty)
    }

    @MainActor func testFailedDeletionPreservesOpenConversation() async {
        let received = expectation(description: "Delete requested")
        let pending = PendingRequests(received: received)
        let store = makeStore(pending)
        let deletion = Task { await store.deleteSession(session) }
        await fulfillment(of: [received], timeout: 5)
        pending.release(statusCode: 500)
        await deletion.value
        XCTAssertEqual(store.selected?.id, session.id)
        XCTAssertNotNil(store.error)
    }

    @MainActor func testBusyConversationCannotSendAnotherPrompt() {
        let store = AppStore()
        store.connected = true
        store.draft = "Next task"
        XCTAssertTrue(store.canSend)
        store.busy = true
        XCTAssertFalse(store.canSend)
        store.newChat()
        XCTAssertFalse(store.busy)
        XCTAssertTrue(store.draft.isEmpty)
    }

    @MainActor func testStoppingIdleRuntimeKeepsStoppedStatus() {
        let runtime = LocalRuntime()
        runtime.stop()
        XCTAssertEqual(runtime.status, "Stopped")
        XCTAssertFalse(runtime.running)
    }
}
