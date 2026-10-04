import Foundation
import Security

// MARK: - Secrets (Trousseau macOS)
// Every token Oli uses lives in the login Keychain under the service « studio.oculot.oli ».
// Values are read once at launch into memory; nothing is ever written to disk or logged.

enum SecretKey: String, CaseIterable, Sendable {
    case espaceToken      = "espace-token"
    case espaceURL        = "espace-url"
    case agendaURL        = "agenda-ics-url"
    case pagespeed        = "pagespeed-api-key"
    case instagramToken   = "instagram-token"
    case instagramAccount = "instagram-user-id"
    case anthropic        = "anthropic-api-key"
}

extension Notification.Name {
    static let oliSecretsChanged = Notification.Name("studio.oculot.oli.secretsChanged")
}

final class Secrets: @unchecked Sendable {
    static let shared = Secrets()
    static let service = "studio.oculot.oli"

    private var values: [SecretKey: String] = [:]
    private let lock = NSLock()

    private init() {
        for key in SecretKey.allCases {
            if let v = Self.read(key.rawValue) { values[key] = v }
        }
    }

    subscript(key: SecretKey) -> String? {
        lock.withLock { values[key].flatMap { $0.isEmpty ? nil : $0 } }
    }

    func has(_ key: SecretKey) -> Bool { self[key] != nil }

    /// Saves (or removes, when empty) a secret and tells the app.
    func set(_ key: SecretKey, _ value: String) {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let before = lock.withLock { values[key] }
        guard before != (v.isEmpty ? nil : v) else { return }
        lock.withLock { values[key] = v.isEmpty ? nil : v }
        if v.isEmpty { Self.delete(key.rawValue) } else { Self.write(key.rawValue, v) }
        DispatchQueue.main.async { NotificationCenter.default.post(name: .oliSecretsChanged, object: key.rawValue) }
    }

    // MARK: Keychain

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func read(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    private static func write(_ account: String, _ value: String) {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query(account)
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(q as CFDictionary, nil)
        }
    }

    private static func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
