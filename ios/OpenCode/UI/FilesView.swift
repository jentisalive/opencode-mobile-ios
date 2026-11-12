import SwiftUI

struct ProjectsView: View {
    @EnvironmentObject var store: AppStore
    @State private var name = ""
    @State private var folders: [URL] = []
    @State private var notice = ""
    var body: some View {
        List {
            Section("New project") {
                TextField("Project name", text: $name)
                Button("Create project") {
                    do {
                        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !clean.isEmpty, clean != ".", clean != "..", !clean.contains("/"), !clean.contains("\\") else { throw APIError(message: "Choose a valid folder name") }
                        let folder = LocalRuntime.workspace.appendingPathComponent(clean)
                        guard !FileManager.default.fileExists(atPath: folder.path) else { throw APIError(message: "This project already exists") }
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        name = ""; load()
                    } catch { notice = error.localizedDescription }
                }
            }
            if !notice.isEmpty { Text(notice).foregroundStyle(.red) }
            Section("Projects") {
                ForEach(folders, id: \.path) { folder in
                    VStack(alignment: .leading, spacing: 8) {
                        NavigationLink(folder.lastPathComponent) { FolderView(root: folder) }
                        Button(store.directory == folder.path ? "Selected" : "Use for new chat") { store.directory = folder.path; store.newChat() }.font(.caption)
                    }
                }
            }
            Section { Text("Projects are available in Files → On My iPhone → OpenCode. Copy folders there to import existing work.").font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("Projects").onAppear(perform: load)
    }
    private func load() {
        do {
            try FileManager.default.createDirectory(at: LocalRuntime.workspace, withIntermediateDirectories: true)
            folders = try FileManager.default.contentsOfDirectory(at: LocalRuntime.workspace, includingPropertiesForKeys: [.isDirectoryKey]).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch { notice = error.localizedDescription }
    }
}

struct FolderView: View {
    let root: URL
    @State private var files: [URL] = []
    @State private var notice = ""
    @State private var newName = ""
    var body: some View {
        List {
            Section("New text file") {
                TextField("Filename", text: $newName).autocorrectionDisabled().textInputAutocapitalization(.never)
                Button("Create") {
                    do {
                        guard !newName.isEmpty, newName != ".", newName != "..", !newName.contains("/"), !newName.contains("\\") else { throw APIError(message: "Invalid filename") }
                        let target = root.appendingPathComponent(newName)
                        guard !FileManager.default.fileExists(atPath: target.path) else { throw APIError(message: "File already exists") }
                        try Data().write(to: target, options: .withoutOverwriting); newName = ""; load()
                    } catch { notice = error.localizedDescription }
                }
            }
            if !notice.isEmpty { Text(notice).foregroundStyle(.red) }
            ForEach(files, id: \.path) { file in
                let values = try? file.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values?.isSymbolicLink == true { Label(file.lastPathComponent + " (symbolic link)", systemImage: "link").foregroundStyle(.secondary) }
                else if values?.isDirectory == true { NavigationLink { FolderView(root: file) } label: { Label(file.lastPathComponent, systemImage: "folder") } }
                else { NavigationLink { TextFileView(file: file) } label: { Label(file.lastPathComponent, systemImage: "doc.text") } }
            }
        }.navigationTitle(root.lastPathComponent).onAppear(perform: load)
    }
    private func load() {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]).sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch { notice = error.localizedDescription }
    }
}

struct TextFileView: View {
    let file: URL
    @State private var text = ""
    @State private var loaded = false
    @State private var notice = ""
    var body: some View {
        VStack {
            TextEditor(text: $text).font(.system(.callout, design: .monospaced)).autocorrectionDisabled().textInputAutocapitalization(.never).disabled(!loaded)
            if !notice.isEmpty { Text(notice).font(.caption).padding() }
        }.navigationTitle(file.lastPathComponent)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Save") { do { try text.write(to: file, atomically: true, encoding: .utf8); notice = "Saved" } catch { notice = error.localizedDescription } }.disabled(!loaded) }
                ToolbarItem(placement: .bottomBar) { ShareLink(item: file) }
            }.task {
                do {
                    let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 2 * 1024 * 1024 else { throw APIError(message: "This file is too large for the text editor. Use Share to open it in another app.") }
                    text = try String(contentsOf: file, encoding: .utf8); loaded = true
                } catch { notice = error.localizedDescription }
            }
    }
}

struct ChangesView: View {
    @EnvironmentObject var store: AppStore
    @State private var changes: [JSONValue] = []
    @State private var notice = ""
    var body: some View {
        List {
            if store.selected == nil { Text("Open a conversation to see its changes.") }
            else if changes.isEmpty { Text("No file changes reported.").foregroundStyle(.secondary) }
            if !notice.isEmpty { Text(notice).foregroundStyle(.red) }
            ForEach(changes, id: \.self) { file in
                DisclosureGroup(file["file"].string) {
                    Text("Before").bold(); Text(file["before"].string).font(.caption.monospaced()).textSelection(.enabled)
                    Text("After").bold(); Text(file["after"].string).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
            if let selected = store.selected { Button("Undo previous revert") { Task { await store.action("/session/\(selected.id)/unrevert") } } }
        }.navigationTitle("Changes").task {
            guard let session = store.selected else { return }
            do { changes = try await store.client().call("/session/\(session.id)/diff", directory: store.directory).array }
            catch { notice = error.localizedDescription }
        }
    }
}
