import Foundation
import Combine
import UIKit

@MainActor final class AppStore: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var messages: [ChatMessage] = []
    @Published var models: [Model] = []
    @Published var agents: [String] = ["build", "plan"]
    @Published var permissions: [JSONValue] = []
    @Published var questions: [JSONValue] = []
    @Published var selected: Session?
    @Published var modelID = UserDefaults.standard.string(forKey: "modelID") ?? ""
    @Published var agent = "build"
    @Published var draft = ""
    @Published var attachments: [JSONValue] = []
    @Published var busy = false
    @Published var sending = false
    @Published var connected = false
    @Published var error: String?
    @Published var directory = LocalRuntime.workspace.path
    @Published var revision = 0
    let runtime = LocalRuntime()
    let speech = SpeechService()
    private(set) var api: OpenCodeAPI?
    private var events: Task<Void, Never>?
    private var connecting = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    var selectedModel: Model? { models.first { $0.id == modelID } }
    var canSend: Bool { connected && !sending && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty) }
    func start() async {
        guard !connecting else { return }; connecting = true
        defer { connecting = false }
        do {
            let password = try Keychain.password()
            let client = OpenCodeAPI(baseURL: URL(string: "http://127.0.0.1:4096")!, password: password)
            api = client
            try runtime.start(password: password)
            for _ in 0..<60 {
                try Task.checkCancellation()
                if let health = try? await client.call("/global/health"), health["healthy"].bool {
                    runtime.markReady(); connected = true
                    try await refreshCatalog()
                    try await refreshSessions()
                    beginEvents()
                    return
                }
                try await Task.sleep(for: .seconds(1))
            }
            runtime.readLog()
            throw APIError(message: "The local engine did not become ready. Open Settings → Runtime to inspect its log.")
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription; connected = false; runtime.readLog() }
    }
    func foreground() async {
        if runtime.running {
            do { try await refreshSessions(); try await refreshChat(); beginEvents() }
            catch { self.error = error.localizedDescription; connected = false }
        }
        if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
    }
    func background() {
        speech.stop()
        guard busy, backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finish current response") { [weak self] in
            guard let self else { return }
            self.events?.cancel()
            UIApplication.shared.endBackgroundTask(self.backgroundTask)
            self.backgroundTask = .invalid
        }
    }
    func client() throws -> OpenCodeAPI { guard let api else { throw APIError(message: "Start the local engine first") }; return api }
    func refreshCatalog() async throws {
        let client = try client()
        let response = try await client.call("/config/providers")
        models = response["providers"].array.flatMap { provider in
            provider["models"].object.map { key, value in Model(provider: provider["id"].string, key: key, name: value["name"].string.isEmpty ? key : value["name"].string, context: value["limit"]["context"].number) }
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if !models.contains(where: { $0.id == modelID }) { modelID = models.first?.id ?? "" }
        let agentData = try await client.call("/agent")
        agents = agentData.array.filter { !$0["hidden"].bool && $0["mode"].string != "subagent" }.map { $0["name"].string }
        if !agents.contains(agent) { agent = agents.first ?? "build" }
    }
    func refreshSessions() async throws {
        let data = try await client().call("/session")
        sessions = data.array.filter { $0["parentID"].string.isEmpty && $0["time"]["archived"].number == 0 }.map(Session.init(raw:))
    }
    func open(_ session: Session) async {
        events?.cancel(); selected = session; directory = session.directory; messages = []; permissions = []; questions = []
        do { try await refreshChat(); beginEvents() } catch { self.error = error.localizedDescription }
    }
    func newChat() { selected = nil; messages = []; busy = false; permissions = []; questions = []; beginEvents() }
    func refreshChat() async throws {
        guard let selected else { return }
        let client = try client()
        async let history = client.call("/session/\(selected.id)/message", directory: directory)
        async let pending = client.call("/permission", directory: directory)
        async let asks = client.call("/question", directory: directory)
        async let statuses = client.call("/session/status", directory: directory)
        let (h, p, q, s) = try await (history, pending, asks, statuses)
        guard self.selected?.id == selected.id else { return }
        messages = h.array.map { ChatMessage(info: $0["info"], parts: $0["parts"].array) }
        permissions = p.array.filter { $0["sessionID"].string == selected.id }
        questions = q.array.filter { $0["sessionID"].string == selected.id }
        busy = ["busy", "retry"].contains(s[selected.id]["type"].string)
        revision += 1
    }
    func send() async {
        guard canSend else { return }; sending = true
        speech.stop()
        let text = draft
        let files = attachments
        defer { sending = false }
        do {
            let client = try client()
            if selected == nil {
                let created = try await client.call("/session", method: "POST", directory: directory, body: .object([:]))
                selected = Session(raw: created); beginEvents()
            }
            guard let selected else { return }
            var body: [String: JSONValue] = ["parts": .array((text.isEmpty ? [] : [.object(["type": .string("text"), "text": .string(text)])]) + files), "agent": .string(agent)]
            body["system"] = .string("You are cl0udly, the assistant in OpenCode mobile for iOS. State your real model if asked. Work in the selected project. This is iOS, not Linux: do not assume apt, proot or Android tools exist. The local memory folder is \(LocalRuntime.support.appendingPathComponent("memory").path). Read relevant memory before a task; save facts only when the user asks. Ask before destructive commands, publishing, or accessing files outside the chosen project. Never include provider secrets in responses or logs.")
            if let model = selectedModel { body["model"] = .object(["providerID": .string(model.provider), "modelID": .string(model.key)]) }
            _ = try await client.call("/session/\(selected.id)/prompt_async", method: "POST", directory: directory, body: .object(body))
            draft = ""; attachments = []; busy = true
            UserDefaults.standard.set(modelID, forKey: "modelID")
            try await refreshSessions(); try await refreshChat()
        } catch { self.error = error.localizedDescription }
    }
    func action(_ path: String, method: String = "POST", body: JSONValue? = nil) async {
        do { _ = try await client().call(path, method: method, directory: directory, body: body); try await refreshChat(); try await refreshSessions() }
        catch { self.error = error.localizedDescription }
    }
    private func beginEvents() {
        events?.cancel()
        guard let api, connected else { return }
        let dir = directory
        events = Task { [weak self] in
            var retry = 1
            while !Task.isCancelled {
                do {
                    try await api.events(directory: dir) { [weak self] event in await self?.receive(event) }
                } catch is CancellationError { return }
                catch { if Task.isCancelled { return } }
                guard let self, !Task.isCancelled else { return }
                try? await Task.sleep(for: .seconds(retry))
                do { try await self.refreshChat(); self.connected = true; retry = 1 }
                catch { self.connected = false; retry = min(retry * 2, 15) }
            }
        }
    }
    private func receive(_ event: JSONValue) async {
        let props = event["properties"]
        switch event["type"].string {
        case "message.updated":
            let info = props["info"]
            guard info["sessionID"].string == selected?.id else { return }
            if let index = messages.firstIndex(where: { $0.id == info["id"].string }) { messages[index].info = info }
            else { messages.append(ChatMessage(info: info, parts: [])) }
        case "message.part.updated":
            let part = props["part"]
            guard part["sessionID"].string == selected?.id else { return }
            if let i = messages.firstIndex(where: { $0.id == part["messageID"].string }) {
                if let j = messages[i].parts.firstIndex(where: { $0["id"].string == part["id"].string }) { messages[i].parts[j] = part }
                else { messages[i].parts.append(part) }
            } else { try? await refreshChat() }
        case "message.part.delta":
            guard props["sessionID"].string == selected?.id,
                  let i = messages.firstIndex(where: { $0.id == props["messageID"].string }),
                  let j = messages[i].parts.firstIndex(where: { $0["id"].string == props["partID"].string }) else { return }
            var part = messages[i].parts[j].object
            let field = props["field"].string
            part[field] = .string((part[field]?.string ?? "") + props["delta"].string)
            messages[i].parts[j] = .object(part)
        case "session.status":
            if props["sessionID"].string == selected?.id { busy = ["busy", "retry"].contains(props["status"]["type"].string) }
        case "permission.asked", "permission.replied", "question.asked", "question.replied", "question.rejected", "session.idle", "message.removed", "message.part.removed":
            try? await refreshChat()
        case "session.created", "session.updated", "session.deleted": try? await refreshSessions()
        case "session.error": error = props["error"]["data"]["message"].string; busy = false
        default: break
        }
        revision += 1
    }
}
