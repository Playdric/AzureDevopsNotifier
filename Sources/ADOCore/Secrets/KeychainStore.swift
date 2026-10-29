import Foundation
import Security

public protocol SecretStore: Sendable {
    func read(account: String) throws -> String?
    func write(_ secret: String, account: String) throws
    func delete(account: String) throws
}

public struct KeychainError: Error, Equatable {
    public let status: OSStatus
}

/// PAT dans le Keychain, entrée créée par l'app (ACL liée à sa signature), jamais synchronisée.
public struct KeychainStore: SecretStore {
    public static let defaultService = "com.cedricnanteau.ado-notifier"
    private let service: String

    public init(service: String = KeychainStore.defaultService) {
        self.service = service
    }

    private func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    public func read(account: String) throws -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw KeychainError(status: status) }
        return String(decoding: data, as: UTF8.self)
    }

    public func write(_ secret: String, account: String) throws {
        let data = Data(secret.utf8)
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainError(status: status) }

        var add = query(account)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        add[kSecAttrLabel as String] = "ADO Notifier PAT"
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
    }

    public func delete(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}
