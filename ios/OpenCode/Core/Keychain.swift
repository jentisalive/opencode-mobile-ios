import Foundation
import Security

enum Keychain {
    static func password() throws -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrService as String: "app.ocmobile.ios.local-server",
                                  kSecAttrAccount as String: "opencode"]
        var read = query; read[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) { return value }
        guard status == errSecItemNotFound else { throw APIError(message: "Cannot read server password (Keychain \(status))") }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw APIError(message: "Cannot generate server password") }
        let value = Data(bytes).base64EncodedString()
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let saved = SecItemAdd(add as CFDictionary, nil)
        guard saved == errSecSuccess else { throw APIError(message: "Cannot save server password (Keychain \(saved))") }
        return value
    }
}
