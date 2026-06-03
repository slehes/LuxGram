import Foundation
import Security

private let enabledKey = "sg_protected_chats_enabled"
private let peerIdsKey = "sg_protected_chat_peer_ids"
private let folderIdsKey = "sg_protected_folder_ids"
private let useDevicePasscodeKey = "sg_protected_chats_use_device_passcode"
private let serviceName = "LuxGramProtectedChats"
private let customPasscodeAccount = "chats"

public enum ProtectedChatsStore {
    public static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    public static var useDevicePasscode: Bool {
        get { UserDefaults.standard.object(forKey: useDevicePasscodeKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: useDevicePasscodeKey) }
    }

    public static var protectedPeerIds: Set<Int64> {
        get {
            let list = UserDefaults.standard.array(forKey: peerIdsKey) as? [Int64] ?? []
            return Set(list)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: peerIdsKey)
        }
    }

    public static var protectedFolderIds: Set<Int32> {
        get {
            let list = UserDefaults.standard.array(forKey: folderIdsKey) as? [Int32] ?? []
            return Set(list)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: folderIdsKey)
        }
    }

    public static func addProtectedPeer(_ peerId: Int64) {
        var set = protectedPeerIds
        set.insert(peerId)
        protectedPeerIds = set
    }

    public static func removeProtectedPeer(_ peerId: Int64) {
        var set = protectedPeerIds
        set.remove(peerId)
        protectedPeerIds = set
    }

    public static func addProtectedFolder(_ folderId: Int32) {
        var set = protectedFolderIds
        set.insert(folderId)
        protectedFolderIds = set
    }

    public static func removeProtectedFolder(_ folderId: Int32) {
        var set = protectedFolderIds
        set.remove(folderId)
        protectedFolderIds = set
    }

    public static func isProtected(peerId: Int64) -> Bool {
        isEnabled && protectedPeerIds.contains(peerId)
    }

    public static func isProtected(folderId: Int32) -> Bool {
        isEnabled && protectedFolderIds.contains(folderId)
    }

    // MARK: - Custom passcode (when not using device passcode)

    public static func setCustomPasscode(_ passcode: String) {
        let data = passcode.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: customPasscodeAccount
        ]
        var addQuery = query
        addQuery[kSecValueData as String] = data
        var status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            SecItemDelete(query as CFDictionary)
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    public static func customPasscodeMatches(_ passcode: String) -> Bool {
        guard let stored = getCustomPasscode() else { return false }
        return stored == passcode
    }

    public static func hasCustomPasscode() -> Bool {
        getCustomPasscode() != nil
    }

    public static func removeCustomPasscode() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: customPasscodeAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func getCustomPasscode() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: customPasscodeAccount,
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
}
