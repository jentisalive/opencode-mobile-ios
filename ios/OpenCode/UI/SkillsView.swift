import SwiftUI
import UniformTypeIdentifiers

struct SkillsView: View {
    @EnvironmentObject var store: AppStore
    @State private var files: [URL] = []
    @State private var notice = ""
    @State private var creating = false
    @State private var importing = false
    private var library: SkillFiles { SkillFiles(root: LocalRuntime.support.appendingPathComponent("config/opencode/skills")) }
    var body: some View {
        List {
            Section {
                Button("Create skill", systemImage: "plus") { creating = true }
                Button("Import SKILL.md", systemImage: "square.and.arrow.down") { importing = true }
                Button("Create with agent", systemImage: "sparkles") {
                    store.newChat()
                    store.draft = "Help me create a skill. Ask what it should do, then save SKILL.md in \(library.root.path)/<name>/ with YAML name and description fields."
                    notice = "A new message is ready. Close Settings to send it."
                }
                NavigationLink("All available skills") { EndpointList(title: "Skills", path: "/skill") }
            }
            if !notice.isEmpty { Text(notice).font(.caption).textSelection(.enabled) }
            Section("Your skills") {
                ForEach(files, id: \.path) { file in
                    NavigationLink(file.deletingLastPathComponent().lastPathComponent) {
                        TextFileView(file: file, onSave: { Task { await reloadEngine() } })
                    }
                }
                if files.isEmpty { Text("Create or import a skill to give the agent reusable instructions.").foregroundStyle(.secondary) }
            }
        }.navigationTitle("Skills").onAppear(perform: load)
            .sheet(isPresented: $creating, onDismiss: load) {
                NavigationStack { CreateSkillView(library: library) { Task { await reloadEngine() } } }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "md") ?? .plainText, .plainText]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 1024 * 1024 else { throw APIError(message: "SKILL.md must be smaller than 1 MB") }
                    try library.importMarkdown(String(contentsOf: url, encoding: .utf8))
                    load(); Task { await reloadEngine() }
                } catch { notice = error.localizedDescription }
            }
    }
    private func load() { do { files = try library.list() } catch { notice = error.localizedDescription } }
    private func reloadEngine() async {
        guard store.connected else { notice = "Saved. The skill will load when you start the engine."; return }
        guard !store.busy else { notice = "Saved. Restart the engine after the current response to reload skills."; return }
        do { _ = try await store.client().call("/global/dispose", method: "POST"); notice = "Saved. Skills reloaded." }
        catch { notice = "Saved, but reload failed: \(error.localizedDescription)" }
    }
}

private struct CreateSkillView: View {
    @Environment(\.dismiss) private var dismiss
    let library: SkillFiles
    let saved: () -> Void
    @State private var name = ""
    @State private var description = ""
    @State private var instructions = ""
    @State private var error = ""
    var body: some View {
        Form {
            TextField("short-skill-name", text: $name).textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("What it does and when to use it", text: $description, axis: .vertical)
            Section("Instructions") { TextEditor(text: $instructions).frame(minHeight: 220) }
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
        }.navigationTitle("New skill").toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") {
                do {
                    try library.create(name: name, markdown: SkillFiles.render(name: name, description: description, instructions: instructions))
                    saved(); dismiss()
                } catch { self.error = error.localizedDescription }
            }.disabled(name.isEmpty || description.isEmpty || instructions.isEmpty) }
        }
    }
}
