import Foundation

enum JSONValue: Codable, Hashable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    subscript(_ key: String) -> JSONValue { object[key] ?? .null }
    var object: [String: JSONValue] { if case .object(let v) = self { return v }; return [:] }
    var array: [JSONValue] { if case .array(let v) = self { return v }; return [] }
    var string: String { if case .string(let v) = self { return v }; return "" }
    var number: Double { if case .number(let v) = self { return v }; return 0 }
    var bool: Bool { if case .bool(let v) = self { return v }; return false }
    var pretty: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? String(data: encoder.encode(self), encoding: .utf8)) ?? ""
    }
}

struct Session: Identifiable, Hashable {
    let raw: JSONValue
    var id: String { raw["id"].string }
    var directory: String { raw["directory"].string }
    var title: String { raw["title"].string.isEmpty ? "New chat" : raw["title"].string }
}
struct ChatMessage: Identifiable {
    var info: JSONValue
    var parts: [JSONValue]
    var id: String { info["id"].string }
    var isUser: Bool { info["role"].string == "user" }
}
struct Model: Identifiable, Hashable {
    let provider: String
    let key: String
    let name: String
    let context: Double
    var id: String { provider + "/" + key }
}
