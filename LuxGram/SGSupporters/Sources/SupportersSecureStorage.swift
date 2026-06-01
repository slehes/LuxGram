import Foundation
import Security
import CryptoKit

/// Key derivation for local encryption (key not stored — derived from app identity).
private func deriveLocalKey() -> SymmetricKey {
    let salt = "sg_local_v1_7f3a9e"
    let seed = (Bundle.main.bundleIdentifier ?? "sg") + salt
    let hash = SHA256.hash(data: Data(Array(seed.utf8)))
    return SymmetricKey(data: hash)
}

/// AES-256-GCM encrypt before Keychain write. Protects against Keychain-substitution tweaks.
private func encryptForStorage(_ plaintext: Data) -> Data? {
    let key = deriveLocalKey()
    let nonce = AES.GCM.Nonce()
    guard let sealed = try? AES.GCM.seal(plaintext, using: key, nonce: nonce),
          let combined = sealed.combined else { return nil }
    return combined
}

/// AES-256-GCM decrypt after Keychain read.
private func decryptFromStorage(_ ciphertext: Data) -> Data? {
    let key = deriveLocalKey()
    guard let sealed = try? AES.GCM.SealedBox(combined: ciphertext),
          let decrypted = try? AES.GCM.open(sealed, using: key) else { return nil }
    return decrypted
}

/// Keychain + AES-256-GCM. Data is encrypted before Keychain; substitution tweaks get ciphertext only.
private enum SupportersSecureStorage {
    private static let service = "sg_luxgram_secure"
    private static let accessibility = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

    static func getData(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let ciphertext = result as? Data else {
            return nil
        }
        return decryptFromStorage(ciphertext)
    }

    static func setData(_ plaintext: Data, account: String) -> Bool {
        guard let ciphertext = encryptForStorage(plaintext) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: accessibility
        ]
        var status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let updateQuery: [String: Any] = [kSecValueData as String: ciphertext]
            status = SecItemUpdate(query as CFDictionary, updateQuery as CFDictionary)
            return status == errSecSuccess
        } else if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = ciphertext
            status = SecItemAdd(addQuery as CFDictionary, nil)
            return status == errSecSuccess
        }
        return false
    }

    static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

func supportersSecureLoadJSON(account: String) -> [String: Any]? {
    guard let data = SupportersSecureStorage.getData(account: account),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }
    return json
}

func supportersSecureSaveJSON(_ dict: [String: Any], account: String) -> Bool {
    guard let data = try? JSONSerialization.data(withJSONObject: dict) else {
        return false
    }
    return SupportersSecureStorage.setData(data, account: account)
}
