import Foundation
import SwiftSignalKit

public class SGLocalPremium {
    public static let shared = SGLocalPremium()

    private var currentAccountId: String?
    public var currentAccountPeerId: (id: Int64, namespace: Int32)?

    private init() {}

    public func setAccountPeerId(_ peerId: Int64, namespace: Int32) {
        self.currentAccountId = "\(namespace)_\(peerId)"
        self.currentAccountPeerId = (id: peerId, namespace: namespace)
    }

    private func accountKey(_ key: String) -> String {
        guard let accountId = currentAccountId else {
            return key
        }
        return "\(key)_\(accountId)"
    }

    public var emulatePremium: Bool {
        get {
            return UserDefaults.standard.bool(forKey: accountKey("localPremiumEmulate"))
        }
        set {
            UserDefaults.standard.set(newValue, forKey: accountKey("localPremiumEmulate"))
            UserDefaults.standard.synchronize()
        }
    }

    public var showPremiumBadge: Bool { return emulatePremium }
    public var unlimitedPinnedChats: Bool { return emulatePremium }
    public var unlimitedFolders: Bool { return emulatePremium }
    public var unlimitedChatsPerFolder: Bool { return emulatePremium }
    public var unlimitedSavedMessageTags: Bool { return emulatePremium }
    public var allowFolderReordering: Bool { return emulatePremium }
    public var shouldDisableServerSync: Bool { return emulatePremium }

    public func getMaxPinnedChatCount(_ original: Int32) -> Int32 {
        if unlimitedPinnedChats {
            return Int32.max
        }
        return original
    }

    public func getMaxFoldersCount(_ original: Int32) -> Int32 {
        if unlimitedFolders {
            return Int32.max
        }
        return original
    }

    public func getMaxFolderChatsCount(_ original: Int32) -> Int32 {
        if unlimitedChatsPerFolder {
            return Int32.max
        }
        return original
    }

    public func canReorderAllChats(isPremium: Bool) -> Bool {
        if isPremium {
            return true
        }
        return allowFolderReordering
    }
}
