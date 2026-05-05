import Foundation
import Security

enum SessionStoreError: Error {
    case encodeFailed
    case keychain(OSStatus)
}

protocol SessionStoring {
    func load() -> AuthSession?
    func save(_ session: AuthSession) throws
    func clear()
}

final class KeychainSessionStore: SessionStoring {
    private let service = "ca.totalfree.admin"
    private let account = "staff-session"

    func load() -> AuthSession? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    func save(_ session: AuthSession) throws {
        guard let data = try? JSONEncoder().encode(session) else {
            throw SessionStoreError.encodeFailed
        }
        clear()
        var item = baseQuery()
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw SessionStoreError.keychain(status) }
    }

    func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
