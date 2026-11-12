import Foundation

struct MessageBlock: Equatable {
    enum Kind: Equatable { case text, code(String) }
    var kind: Kind
    var content: String

    // Keep incomplete fenced blocks visible while the model is streaming.
    static func parse(_ markdown: String) -> [MessageBlock] {
        var blocks: [MessageBlock] = []
        var lines: [String] = []
        var fence: Character?
        var length = 0
        var language = ""
        func flush(_ kind: Kind) {
            if !lines.isEmpty { blocks.append(MessageBlock(kind: kind, content: lines.joined(separator: "\n"))) }
            lines.removeAll()
        }
        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = line.prefix(while: { $0 == " " }).count
            let first = trimmed.first
            let count = trimmed.prefix(while: { $0 == first }).count
            if let active = fence {
                if indent <= 3 && first == active && count >= length && trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty {
                    flush(.code(language)); fence = nil
                } else { lines.append(line) }
            } else if indent <= 3 && (first == "`" || first == "~") && count >= 3 {
                flush(.text); fence = first; length = count
                language = String(trimmed.dropFirst(count)).trimmingCharacters(in: .whitespaces)
            } else { lines.append(line) }
        }
        flush(fence == nil ? .text : .code(language))
        return blocks
    }
}
