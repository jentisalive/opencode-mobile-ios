import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        List {
            Section("On this iPhone") {
                NavigationLink("Runtime & diagnostics") { RuntimeView(runtime: store.runtime) }
                NavigationLink("Projects & files") { ProjectsView() }
            }
            Section("OpenCode") {
                NavigationLink("Models") { ModelPicker() }
                NavigationLink("Providers & sign-in") { ProvidersView() }
                NavigationLink("Skills") { EndpointList(title: "Skills", path: "/skill") }
                NavigationLink("Agents & team") { EndpointList(title: "Agents", path: "/agent") }
                NavigationLink("MCP servers") { MCPView() }
                NavigationLink("Memory") { FolderView(root: LocalRuntime.support.appendingPathComponent("memory")) }
                NavigationLink("Usage") { UsageView() }
                NavigationLink("Configuration") { ConfigView() }
            }
            Section("About") {
                Text("OpenCode mobile · iOS experimental").font(.callout)
                Text("Native client and on-device engine. Model inference still uses your selected provider. Background execution, shell tools and runtime compatibility depend on the device installation.").font(.caption).foregroundStyle(.secondary)
                Link("Source & known limitations", destination: URL(string: "https://github.com/jentisalive/opencode-mobile-ios/tree/ios-trollstore/ios")!)
            }
        }.navigationTitle("Settings")
    }
}

struct RuntimeView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var runtime: LocalRuntime
    @AppStorage("bootstrapPrefix") private var prefix = "/var/jb"
    @State private var starting = false
    var body: some View {
        List {
            Section("Local engine") {
                LabeledContent("Status", value: runtime.status)
                LabeledContent("OpenCode", value: "1.19.4")
                LabeledContent("Address", value: "127.0.0.1:4096")
                Button(starting ? "Starting…" : "Start engine") { starting = true; Task { await store.start(); starting = false } }.disabled(starting || store.connected)
                Button("Stop engine", role: .destructive) { runtime.stop(); store.connected = false }
            }
            Section {
                TextField("Bootstrap prefix", text: $prefix).textInputAutocapitalization(.never).autocorrectionDisabled()
                Text("For shell, git and other installed commands. RootHide may use a different prefix. Changing this takes effect after stopping and starting the engine.").font(.caption).foregroundStyle(.secondary)
            } header: { Text("Shell tools") }
            Section("Log") {
                Button("Refresh log") { runtime.readLog() }
                ShareLink("Export log", item: runtime.logURL)
                Text(runtime.log).font(.caption.monospaced()).textSelection(.enabled)
            }
        }.navigationTitle("Runtime").onAppear { runtime.readLog() }
    }
}

struct ModelPicker: View {
    @EnvironmentObject var store: AppStore
    @State private var query = ""
    var body: some View {
        List {
            if store.models.isEmpty { Text("Start the engine and connect a provider to load models.").foregroundStyle(.secondary) }
            ForEach(store.models.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.provider.localizedCaseInsensitiveContains(query) }) { model in
                Button {
                    store.modelID = model.id; UserDefaults.standard.set(model.id, forKey: "modelID")
                } label: {
                    HStack {
                        VStack(alignment: .leading) { Text(model.name).foregroundStyle(.primary); Text(model.provider).font(.caption).foregroundStyle(.secondary) }
                        Spacer(); if model.id == store.modelID { Image(systemName: "checkmark") }
                    }
                }
            }
        }.navigationTitle("Models").searchable(text: $query).task { if store.connected { do { try await store.refreshCatalog() } catch { store.error = error.localizedDescription } } }
    }
}

struct ProvidersView: View {
    @EnvironmentObject var store: AppStore
    @State private var providers: [JSONValue] = []
    @State private var connected: [String] = []
    @State private var auth: JSONValue = .null
    @State private var error: String?
    @State private var query = ""
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(providers.filter { query.isEmpty || $0["name"].string.localizedCaseInsensitiveContains(query) }, id: \.self) { provider in
                NavigationLink {
                    ProviderAuthView(provider: provider, methods: auth[provider["id"].string].array)
                } label: {
                    HStack { Text(provider["name"].string); Spacer(); if connected.contains(provider["id"].string) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) } }
                }
            }
        }.navigationTitle("Providers").searchable(text: $query).task {
            do {
                let api = try store.client()
                let data = try await api.call("/provider")
                providers = data["all"].array; connected = data["connected"].array.map(\.string)
                auth = try await api.call("/provider/auth")
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct ProviderAuthView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.openURL) private var openURL
    let provider: JSONValue
    let methods: [JSONValue]
    @State private var key = ""
    @State private var code = ""
    @State private var authorize: JSONValue = .null
    @State private var method = 0
    @State private var working = false
    @State private var notice = ""
    var body: some View {
        Form {
            Section("API key") {
                SecureField("Provider API key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Save key") { run {
                    _ = try await store.client().call("/auth/\(provider["id"].string)", method: "PUT", body: .object(["type": .string("api"), "key": .string(key.trimmingCharacters(in: .whitespacesAndNewlines))]))
                    key = ""; try await reload(); notice = "Connected"
                } }.disabled(working || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ForEach(Array(methods.enumerated()), id: \.offset) { index, item in
                if item["type"].string == "oauth" {
                    Section {
                        Button(item["label"].string) { run {
                            method = index
                            authorize = try await store.client().call("/provider/\(provider["id"].string)/oauth/authorize", method: "POST", body: .object(["method": .number(Double(index))]))
                            if let url = URL(string: authorize["url"].string), ["https", "http"].contains(url.scheme ?? "") { openURL(url) }
                        } }.disabled(working)
                    }
                }
            }
            if authorize != .null {
                Section("Finish sign-in") {
                    Text(authorize["instructions"].string).textSelection(.enabled)
                    TextField("Authorization code, if requested", text: $code).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Complete sign-in") { run {
                        var body: [String: JSONValue] = ["method": .number(Double(method))]
                        if !code.isEmpty { body["code"] = .string(code) }
                        _ = try await store.client().call("/provider/\(provider["id"].string)/oauth/callback", method: "POST", body: .object(body))
                        try await reload(); notice = "Connected"; authorize = .null; code = ""
                    } }.disabled(working)
                }
            }
            if !notice.isEmpty { Text(notice).textSelection(.enabled) }
            Button("Disconnect provider", role: .destructive) { run {
                _ = try await store.client().call("/auth/\(provider["id"].string)", method: "DELETE"); try await reload(); notice = "Disconnected"
            } }.disabled(working)
        }.navigationTitle(provider["name"].string)
    }
    private func reload() async throws {
        _ = try await store.client().call("/global/dispose", method: "POST")
        try await store.refreshCatalog()
    }
    private func run(_ task: @escaping @MainActor () async throws -> Void) {
        working = true
        Task { defer { working = false }; do { try await task() } catch { notice = error.localizedDescription } }
    }
}

struct EndpointList: View {
    @EnvironmentObject var store: AppStore
    let title: String
    let path: String
    @State private var items: [JSONValue] = []
    @State private var error = ""
    var body: some View {
        List {
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            ForEach(items, id: \.self) { item in
                DisclosureGroup(item["name"].string) { Text(item.pretty).font(.caption.monospaced()).textSelection(.enabled) }
            }
            if items.isEmpty && error.isEmpty { Text("No \(title.lowercased()) found.").foregroundStyle(.secondary) }
        }.navigationTitle(title).task {
            do { items = try await store.client().call(path, directory: store.directory).array }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct MCPView: View {
    @EnvironmentObject var store: AppStore
    @State private var status: JSONValue = .null
    @State private var notice = ""
    var body: some View {
        List {
            Text("Add or edit MCP entries in Configuration.").font(.caption).foregroundStyle(.secondary)
            if !notice.isEmpty { Text(notice) }
            ForEach(status.object.keys.sorted(), id: \.self) { name in
                VStack(alignment: .leading) {
                    Text(name).bold(); Text(status[name].pretty).font(.caption.monospaced())
                    HStack {
                        Button("Connect") { change(name, "connect") }
                        Button("Disconnect") { change(name, "disconnect") }
                    }.buttonStyle(.bordered)
                }
            }
        }.navigationTitle("MCP servers").task { await load() }
    }
    private func load() async { do { status = try await store.client().call("/mcp") } catch { notice = error.localizedDescription } }
    private func change(_ name: String, _ action: String) { Task { do { _ = try await store.client().call("/mcp/\(name)/\(action)", method: "POST"); await load() } catch { notice = error.localizedDescription } } }
}

struct ConfigView: View {
    @EnvironmentObject var store: AppStore
    @State private var text = ""
    @State private var notice = ""
    var body: some View {
        VStack {
            Text("Edit providers, agents, permissions and MCP configuration.").font(.caption).foregroundStyle(.secondary).padding()
            TextEditor(text: $text).font(.system(.caption, design: .monospaced)).autocorrectionDisabled().textInputAutocapitalization(.never)
            if !notice.isEmpty { Text(notice).font(.caption) }
            Button("Save configuration") { Task {
                do {
                    let value = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
                    guard case .object = value else { throw APIError(message: "Configuration must be a JSON object") }
                    _ = try await store.client().call("/global/config", method: "PATCH", body: value)
                    try await store.refreshCatalog(); notice = "Saved"
                } catch { notice = error.localizedDescription }
            } }.buttonStyle(.borderedProminent).padding()
        }.navigationTitle("Configuration").task {
            do { text = try await store.client().call("/global/config").pretty }
            catch { notice = error.localizedDescription }
        }
    }
}

struct UsageView: View {
    @EnvironmentObject var store: AppStore
    var cost: Double { store.messages.reduce(0) { $0 + $1.info["cost"].number } }
    func tokens(_ key: String) -> Int { Int(store.messages.reduce(0) { $0 + $1.info["tokens"][key].number }) }
    var body: some View {
        List {
            Section("Current conversation") {
                LabeledContent("Reported cost", value: cost.formatted(.currency(code: "USD")))
                LabeledContent("Input tokens", value: "\(tokens("input"))")
                LabeledContent("Output tokens", value: "\(tokens("output"))")
                LabeledContent("Reasoning tokens", value: "\(tokens("reasoning"))")
                Text("Values reported by OpenCode; subscription limits and provider billing may differ.").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Usage")
    }
}
