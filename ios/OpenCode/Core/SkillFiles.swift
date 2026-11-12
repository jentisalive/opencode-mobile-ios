import Foundation

struct SkillFiles {
    let root: URL
    func list() throws -> [URL] {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey])
            .filter { (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true }
            .map { $0.appendingPathComponent("SKILL.md") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted { $0.path < $1.path }
    }
    @discardableResult func create(name: String, markdown: String) throws -> URL {
        guard name.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil, name.utf8.count <= 64 else {
            throw APIError(message: "Use a lowercase skill name with letters, numbers and dashes (up to 64 characters).")
        }
        let folder = root.appendingPathComponent(name, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: folder.path) else { throw APIError(message: "A skill with this name already exists") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("SKILL.md")
        do { try Data(markdown.utf8).write(to: file, options: .withoutOverwriting) }
        catch { try? FileManager.default.removeItem(at: folder); throw error }
        return file
    }
    func importMarkdown(_ text: String) throws {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}")).components(separatedBy: "\n")
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---"),
              let field = lines[1..<end].first(where: { $0.hasPrefix("name:") }) else {
            throw APIError(message: "SKILL.md needs a YAML header containing name: your-skill-name.")
        }
        let name = field.dropFirst(5).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        try create(name: name, markdown: text)
    }
    static func render(name: String, description: String, instructions: String) throws -> String {
        func quote(_ value: String) throws -> String { String(decoding: try JSONEncoder().encode(value), as: UTF8.self) }
        return "---\nname: \(try quote(name))\ndescription: \(try quote(description))\n---\n\n\(instructions)\n"
    }
}
