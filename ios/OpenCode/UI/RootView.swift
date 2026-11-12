import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @State private var sheet: Panel?
    @State private var importing = false
    @State private var pet = false
    enum Panel: String, Identifiable { case drawer, models, settings, projects, changes; var id: String { rawValue } }
    var body: some View {
        ZStack(alignment: .top) {
            Palette.background.ignoresSafeArea()
            CloudBackdrop()
            VStack(spacing: 0) {
                header.padding(.horizontal, 12).padding(.vertical, 8)
                if store.messages.isEmpty { welcome } else { transcript }
                if !store.permissions.isEmpty || !store.questions.isEmpty { approvals }
                if !store.connected {
                    Button { sheet = .settings } label: {
                        Label("Local engine is offline · Open settings", systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(Palette.dim).padding(8)
                    }
                }
                composer
            }
        }
        .foregroundStyle(Palette.text).preferredColorScheme(.dark)
        .sheet(item: $sheet) { panel in
            NavigationStack {
                Group {
                    switch panel {
                    case .drawer: drawer
                    case .models: ModelPicker()
                    case .settings: SettingsView()
                    case .projects: ProjectsView()
                    case .changes: ChangesView()
                    }
                }.toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { sheet = nil } } }
            }.tint(Palette.accent).preferredColorScheme(.dark)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image, .pdf, .plainText], allowsMultipleSelection: true) { result in
            do {
                for url in try result.get() {
                    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    guard data.count <= 10 * 1024 * 1024 else { throw APIError(message: "Attachments must be smaller than 10 MB") }
                    let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                    store.attachments.append(.object(["type": .string("file"), "mime": .string(mime), "filename": .string(url.lastPathComponent), "url": .string("data:\(mime);base64,\(data.base64EncodedString())")]))
                }
            } catch { store.error = error.localizedDescription }
        }
        .alert("OpenCode", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
    private var header: some View {
        HStack(spacing: 8) {
            RoundButton(symbol: "line.3.horizontal", label: "Menu") { sheet = .drawer }
            Button { sheet = .models } label: {
                HStack(spacing: 6) {
                    Text("OpenCode").foregroundStyle(Palette.text)
                    Text(store.selectedModel?.name ?? "Models").foregroundStyle(Palette.dim).lineLimit(1)
                }.font(.system(size: 16)).frame(maxWidth: .infinity).padding(.horizontal, 14).frame(height: 46)
                    .background(Palette.surface, in: Capsule()).overlay(Capsule().stroke(Palette.border))
            }.buttonStyle(.plain)
            RoundButton(symbol: store.busy ? "circle.dotted.circle" : "circle", label: "Changes") { sheet = .changes }
            RoundButton(symbol: "square.and.pencil", label: "New chat") { store.newChat() }
        }
    }
    private var welcome: some View {
        VStack {
            Spacer()
            PixelCloud().frame(width: 116).scaleEffect(pet ? 1.08 : 1).rotationEffect(.degrees(pet ? 5 : 0))
                .onTapGesture { withAnimation(.spring(response: 0.25)) { pet.toggle() }; UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            Text("Up, up and away,\nfriend. Where to?").font(.system(size: 25, weight: .semibold)).multilineTextAlignment(.center).padding(.top, 24)
            Spacer(); Spacer()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    shortcut("New project", icon: "doc.badge.plus") { sheet = .projects }
                    shortcut("Code", icon: "chevron.left.forwardslash.chevron.right") { sheet = .projects }
                    shortcut("Skills", icon: "sparkles") { sheet = .settings }
                }.padding(.horizontal, 12)
            }.padding(.bottom, 8)
        }
    }
    private func shortcut(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: icon).font(.system(size: 15)).padding(.horizontal, 20).frame(height: 48).background(Palette.surface, in: Capsule()) }.buttonStyle(.plain)
    }
    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(store.messages) { message in MessageView(message: message).id(message.id) }
                    if store.busy { HStack { ProgressView(); Text("Working…").font(.caption).foregroundStyle(Palette.dim) } }
                    Color.clear.frame(height: 1).id("bottom")
                }.padding(18)
            }.scrollDismissesKeyboard(.interactively)
                .onChange(of: store.messages.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }
    private var approvals: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(store.permissions, id: \.self) { permission in
                    VStack(alignment: .leading, spacing: 10) {
                        Label(permission["permission"].string, systemImage: "hand.raised.fill").bold()
                        Text(permission["patterns"].array.map(\.string).joined(separator: "\n")).font(.caption.monospaced()).textSelection(.enabled)
                        HStack {
                            permissionButton("Deny", request: permission, reply: "reject")
                            Spacer()
                            permissionButton("Always", request: permission, reply: "always")
                            permissionButton("Allow once", request: permission, reply: "once")
                        }
                    }.padding().background(Palette.high, in: RoundedRectangle(cornerRadius: 16))
                }
                ForEach(store.questions, id: \.self) { QuestionCard(request: $0) }
            }.padding(.horizontal, 12)
        }.frame(maxHeight: 260)
    }
    private func permissionButton(_ title: String, request: JSONValue, reply: String) -> some View {
        Button(title) { Task { await store.action("/permission/\(request["id"].string)/reply", body: .object(["reply": .string(reply)])) } }.buttonStyle(.bordered)
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !store.attachments.isEmpty {
                ScrollView(.horizontal) { HStack { ForEach(Array(store.attachments.enumerated()), id: \.offset) { index, file in
                    Button { store.attachments.remove(at: index) } label: { Label(file["filename"].string, systemImage: "xmark.circle").font(.caption) }
                } } }.padding(.horizontal)
            }
            if store.selected != nil {
                HStack {
                    Menu(store.agent.capitalized) { ForEach(store.agents, id: \.self) { agent in Button(agent.capitalized) { store.agent = agent } } }
                    Spacer(); Text(URL(fileURLWithPath: store.directory).lastPathComponent).lineLimit(1)
                }.font(.caption).foregroundStyle(Palette.dim).padding(.horizontal, 14)
            }
            HStack(alignment: .bottom, spacing: 10) {
                Button { importing = true } label: { Image(systemName: "plus").font(.title2).frame(width: 42, height: 42).background(Palette.high, in: Circle()) }.accessibilityLabel("Attach file")
                TextField("Ask me. Give me a task.", text: $store.draft, axis: .vertical).lineLimit(1...7).padding(.vertical, 11)
                if store.busy {
                    Button { if let session = store.selected { Task { await store.action("/session/\(session.id)/abort") } } } label: { Image(systemName: "stop.fill").frame(width: 42, height: 42).background(Palette.high, in: Circle()) }.accessibilityLabel("Stop response")
                } else {
                    Button { Task { await store.send() } } label: { Image(systemName: "arrow.up").font(.title3.bold()).frame(width: 42, height: 42).background(store.canSend ? Palette.text : Palette.high, in: Circle()).foregroundStyle(store.canSend ? Palette.background : Palette.dim) }.disabled(!store.canSend).accessibilityLabel("Send")
                }
            }.padding(8).background(Palette.surface, in: RoundedRectangle(cornerRadius: 30)).overlay(RoundedRectangle(cornerRadius: 30).stroke(Palette.border))
        }.padding(.horizontal, 12).padding(.bottom, 8)
    }
    private var drawer: some View {
        List {
            Section {
                Button { store.newChat(); sheet = nil } label: { Label("New chat", systemImage: "plus") }
                Button { sheet = .projects } label: { Label("Projects", systemImage: "folder") }
                Button { sheet = .settings } label: { Label("Settings", systemImage: "gearshape") }
            }
            Section("Recent chats") {
                ForEach(store.sessions) { session in
                    Button { Task { await store.open(session); sheet = nil } } label: { Text(session.title).foregroundStyle(Palette.text) }
                        .swipeActions { Button("Delete", role: .destructive) { Task { await store.action("/session/\(session.id)", method: "DELETE"); if store.selected?.id == session.id { store.newChat() } } } }
                }
            }
        }.navigationTitle("cl0udly").task { if store.connected { try? await store.refreshSessions() } }
    }
}

struct MessageView: View {
    @EnvironmentObject var store: AppStore
    let message: ChatMessage
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !message.isUser { Text("cl0udly").font(.caption.bold()).foregroundStyle(Palette.dim) }
            ForEach(Array(message.parts.enumerated()), id: \.offset) { _, part in
                switch part["type"].string {
                case "text": Text(LocalizedStringKey(part["text"].string)).textSelection(.enabled)
                case "reasoning": DisclosureGroup("Thinking") { Text(part["text"].string).font(.callout).foregroundStyle(Palette.dim).textSelection(.enabled) }
                case "tool":
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(part["state"]["input"].pretty)
                            Text(part["state"]["output"].string)
                            if !part["state"]["error"].string.isEmpty { Text(part["state"]["error"].string).foregroundStyle(.red) }
                        }.font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    } label: { Label(part["tool"].string + " · " + part["state"]["status"].string, systemImage: "terminal").font(.callout) }
                    .padding(12).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                case "file": Label(part["filename"].string.isEmpty ? "Attachment" : part["filename"].string, systemImage: "paperclip").font(.callout)
                default: EmptyView()
                }
            }
            if !message.info["error"]["data"]["message"].string.isEmpty { Text(message.info["error"]["data"]["message"].string).foregroundStyle(.red) }
        }
        .padding(message.isUser ? 16 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(message.isUser ? Palette.high : .clear, in: RoundedRectangle(cornerRadius: 20))
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.parts.filter { $0["type"].string == "text" }.map { $0["text"].string }.joined(separator: "\n") }
            if message.isUser, let session = store.selected {
                Button("Revert to this message", systemImage: "arrow.uturn.backward") { Task { await store.action("/session/\(session.id)/revert", body: .object(["messageID": .string(message.id)])) } }
            }
        }
    }
}

struct QuestionCard: View {
    @EnvironmentObject var store: AppStore
    let request: JSONValue
    @State private var answers: [Int: Set<String>] = [:]
    @State private var custom: [Int: String] = [:]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(request["questions"].array.enumerated()), id: \.offset) { index, question in
                Text(question["question"].string).bold()
                ForEach(question["options"].array, id: \.self) { option in
                    Button {
                        let label = option["label"].string
                        if question["multiple"].bool { if answers[index, default: []].contains(label) { answers[index]?.remove(label) } else { answers[index, default: []].insert(label) } }
                        else { answers[index] = [label]; custom[index] = "" }
                    } label: { Label(option["label"].string, systemImage: answers[index, default: []].contains(option["label"].string) ? "checkmark.circle.fill" : "circle") }
                }
                if question["custom"] != .bool(false) { TextField("Your answer", text: Binding(get: { custom[index] ?? "" }, set: { custom[index] = $0 })).textFieldStyle(.roundedBorder) }
            }
            HStack {
                Button("Dismiss") { Task { await store.action("/question/\(request["id"].string)/reject") } }
                Spacer()
                Button("Reply") {
                    let values = request["questions"].array.indices.map { index -> JSONValue in
                        let text = (custom[index] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let selected = (answers[index] ?? []).sorted()
                        return .array((text.isEmpty ? selected : (request["questions"].array[index]["multiple"].bool ? selected + [text] : [text])).map(JSONValue.string))
                    }
                    Task { await store.action("/question/\(request["id"].string)/reply", body: .object(["answers": .array(values)])) }
                }.disabled(request["questions"].array.indices.contains { (answers[$0] ?? []).isEmpty && (custom[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            }
        }.padding().background(Palette.high, in: RoundedRectangle(cornerRadius: 16))
    }
}
