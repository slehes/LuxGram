import Foundation
import Security

private let serviceName = "LuxGramDoubleBottom"

/// Key for the single "secret" passcode (second password). When user unlocks with this, only one account is shown.
private let secretPasscodeAccountKey = "secret"

public enum DoubleBottomPasscodeStore {

    public static func setSecretPasscode(_ passcode: String) {
        let data = passcode.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: secretPasscodeAccountKey
        ]
        var addQuery = query
        addQuery[kSecValueData as String] = data
        var status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            SecItemDelete(query as CFDictionary)
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    public static func secretPasscodeMatches(_ passcode: String) -> Bool {
        guard let stored = secretPasscode() else { return false }
        return stored == passcode
    }

    public static func hasSecretPasscode() -> Bool {
        return secretPasscode() != nil
    }

    public static func removeSecretPasscode() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: secretPasscodeAccountKey
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func secretPasscode() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: secretPasscodeAccountKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    public static func setPasscode(_ passcode: String, forAccountId accountId: Int64) {
        let account = "\(accountId)"
        let data = passcode.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        var addQuery = query
        addQuery[kSecValueData as String] = data
        var status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            SecItemDelete(query as CFDictionary)
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    public static func passcode(forAccountId accountId: Int64) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: "\(accountId)",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    public static func removePasscode(forAccountId accountId: Int64) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: "\(accountId)"
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Returns the account id whose passcode matches the given value, or nil.
    public static func accountId(matchingPasscode passcode: String, candidateIds: [Int64]) -> Int64? {
        for id in candidateIds {
            if Self.passcode(forAccountId: id) == passcode {
                return id
            }
        }
        return nil
    }
}
