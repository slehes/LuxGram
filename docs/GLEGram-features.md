# LuxGram: описание функций и полный исходный код

Документ описывает реализацию в репозитории. Раздел про текст «Чаты» в шапке **не включён** (по запросу). Во всех примерах ниже приведён **полный** фрагмент или файл **без сокращений** (`...` не используется).

---

## 1. Двойное дно

**Смысл:** скрытые аккаунты, отдельные пароли в Keychain, при разблокировке приложения разные коды ведут к разным сценариям (основной пароль Telegram, «секретный» пароль, переключение на скрытый аккаунт по совпадению пароля). Флаги `isDoubleBottomOn` / `inDoubleBottom` хранятся в UserDefaults (`VarSystemNGSettings`). Экран настроек в LuxGram — `doubleBottomSettingsController`; проверки при вводе пароля приложения — в `AppDelegate` (`additionalPasscodeCheck`, `onUnlockWithPasscode`).

### `Nicegram/NGData/Sources/SystemNGSettings.swift` (полностью)

```swift
// From Nicegram NGData/Sources/NGSettings.swift – only SystemNGSettings for Double Bottom
import Foundation

public class SystemNGSettings {
 let UD = UserDefaults.standard
 
 public init() {}
 
 public var dbReset: Bool {
 get {
 return UD.bool(forKey: "ng_db_reset")
 }
 set {
 UD.set(newValue, forKey: "ng_db_reset")
 }
 }
 
 public var isDoubleBottomOn: Bool {
 get {
 return UD.bool(forKey: "isDoubleBottomOn")
 }
 set {
 UD.set(newValue, forKey: "isDoubleBottomOn")
 }
 }
 
 public var inDoubleBottom: Bool {
 get {
 return UD.bool(forKey: "inDoubleBottom")
 }
 set {
 UD.set(newValue, forKey: "inDoubleBottom")
 }
 }
}

public var VarSystemNGSettings = SystemNGSettings()
```

### `LuxGram/SGSettingsUI/Sources/DoubleBottomPasscodeStore.swift` (полностью)

```swift
// MARK: LuxGram – Keychain storage for hidden-account passcodes (Double Bottom)
import Foundation
import Security

private let serviceName = "LuxGramDoubleBottom"

/// Key for the single "secret" passcode (second password). When user unlocks with this, only one account is shown.
private let secretPasscodeAccountKey = "secret"

public enum DoubleBottomPasscodeStore {
    // MARK: - Secret passcode (second password → show only 1 account)

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

    // MARK: - Per-account passcodes (hidden accounts)

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
```

### `LuxGram/SGSettingsUI/Sources/DoubleBottomSettingsController.swift` (полностью)

```swift
// MARK: LuxGram – Double Bottom (full logic from Nicegram NGDoubleBottom/DoubleBottomListController)
// Ref: https://github.com/nicegram/Nicegram-iOS/blob/master/Nicegram/NGDoubleBottom/Sources/DoubleBottomListController.swift
import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import PasscodeUI
import SGSimpleSettings
import TelegramStringFormatting

// MARK: - Section (Nicegram: DoubleBottomControllerSection)

private enum DoubleBottomControllerSection: Int32 {
    case isOn = 0
}

// MARK: - Entry (Nicegram: isOn + info)

private enum DoubleBottomEntry: ItemListNodeEntry {
    case isOn(String, Bool, Bool)  // title, value, enabled
    case info(String)

    var section: ItemListSectionId { DoubleBottomControllerSection.isOn.rawValue }

    var stableId: Int32 {
        switch self {
        case .isOn: return 1000
        case .info: return 1100
        }
    }

    static func < (lhs: DoubleBottomEntry, rhs: DoubleBottomEntry) -> Bool {
        lhs.stableId < rhs.stableId
    }

    static func == (lhs: DoubleBottomEntry, rhs: DoubleBottomEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.isOn(lhsText, lhsBool, _), .isOn(rhsText, rhsBool, _)):
            return lhsText == rhsText && lhsBool == rhsBool
        case let (.info(lhsText), .info(rhsText)):
            return lhsText == rhsText
        default:
            return false
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! DoubleBottomArguments
        switch self {
        case let .isOn(text, value, enabled):
            return ItemListSwitchItem(
                presentationData: presentationData,
                title: text,
                value: value,
                enabled: enabled,
                sectionId: section,
                style: .blocks,
                updated: { value in
                    args.updated(value)
                }
            )
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        }
    }
}

// MARK: - Arguments (Nicegram: DoubleBottomControllerArguments)

private final class DoubleBottomArguments {
    let context: AccountContext
    let updated: (Bool) -> Void
    init(context: AccountContext, updated: @escaping (Bool) -> Void) {
        self.context = context
        self.updated = updated
    }
}

// MARK: - Controller (logic from Nicegram DoubleBottomListController)

public func doubleBottomSettingsController(context: AccountContext) -> ViewController {
    let lang = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
    let title = lang == "ru" ? "Двойное дно" : "Double Bottom"
    let toggleTitle = lang == "ru" ? "Двойное дно" : "Double Bottom"
    let noticeText = lang == "ru"
        ? "Скрытые аккаунты и вход по паролю. Разные пароли открывают разные профили."
        : "Hidden accounts and passcode access. Different passwords open different profiles."

    let arguments = DoubleBottomArguments(context: context, updated: { value in
        if value {
            SGSimpleSettings.shared.doubleBottomEnabled = true
            let setupController = PasscodeSetupController(context: context, mode: .setup(change: false, .digits6))
            setupController.complete = { passcode, _ in
                DoubleBottomPasscodeStore.setSecretPasscode(passcode)
                setupController.dismiss()
            }
            context.sharedContext.presentGlobalController(setupController, nil)
        } else {
            SGSimpleSettings.shared.doubleBottomEnabled = false
            DoubleBottomPasscodeStore.removeSecretPasscode()
            DoubleBottomViewingSecretStore.setViewingWithSecretPasscode(false)
            let accountManager = context.sharedContext.accountManager
            // Remove secret passcodes from Keychain for previously hidden accounts
            let _ = (accountManager.accountRecords()
                |> take(1)
                |> deliverOnMainQueue).start(next: { view in
                    for record in view.records where record.attributes.contains(where: { $0.isHiddenAccountAttribute }) {
                        DoubleBottomPasscodeStore.removePasscode(forAccountId: record.id.int64)
                    }
                })
            // Nicegram: single transaction – keep device passcode, remove HiddenAccount from all records
            let _ = accountManager.transaction { transaction in
                let challengeData = transaction.getAccessChallengeData()
                let challenge: PostboxAccessChallengeData
                switch challengeData {
                case .numericalPassword(let value):
                    challenge = .numericalPassword(value: value)
                case .plaintextPassword(let value):
                    challenge = .plaintextPassword(value: value)
                case .none:
                    challenge = .none
                }
                transaction.setAccessChallengeData(challenge)
                for record in transaction.getRecords() {
                    transaction.updateRecord(record.id) { current in
                        guard let current = current else { return nil }
                        var attributes = current.attributes
                        attributes.removeAll { $0.isHiddenAccountAttribute }
                        return AccountRecord(id: current.id, attributes: attributes, temporarySessionId: current.temporarySessionId)
                    }
                }
            }.start()
        }
    })

    let transactionStatus = context.sharedContext.accountManager.transaction { transaction -> (Bool, Bool) in
        let records = transaction.getRecords()
        let publicCount = records.filter { record in
            let attrs = record.attributes
            let hiddenOrLoggedOut = attrs.contains(where: { $0.isHiddenAccountAttribute || $0.isLoggedOutAccountAttribute })
            return !hiddenOrLoggedOut
        }.count
        let hasMoreThanOnePublic = publicCount > 1
        let hasMainPasscode = transaction.getAccessChallengeData() != .none
        return (hasMoreThanOnePublic, hasMainPasscode)
    }

    let signal: Signal<(ItemListControllerState, (ItemListNodeState, DoubleBottomArguments)), NoError> = combineLatest(context.sharedContext.presentationData, transactionStatus)
        |> map { presentationData, contextStatus -> (ItemListControllerState, (ItemListNodeState, DoubleBottomArguments)) in
            let isOn = SGSimpleSettings.shared.doubleBottomEnabled
            let enabled = isOn || (contextStatus.0 && contextStatus.1)
            let entries: [DoubleBottomEntry] = [
                .isOn(toggleTitle, isOn, enabled),
                .info(noticeText)
            ]
            let controllerState = ItemListControllerState(
                presentationData: ItemListPresentationData(presentationData),
                title: .text(title),
                leftNavigationButton: nil,
                rightNavigationButton: nil,
                backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
            )
            let listState = ItemListNodeState(
                presentationData: ItemListPresentationData(presentationData),
                entries: entries,
                style: .blocks,
                ensureVisibleItemTag: nil,
                footerItem: nil,
                initialScrollToItem: nil
            )
            return (controllerState, (listState, arguments))
        }

    return ItemListController(context: context, state: signal)
}

// MARK: - Passcode check (Nicegram: check(passcode:challengeData:) for device passcode validation)

public func doubleBottomCheckPasscode(_ passcode: String, challengeData: PostboxAccessChallengeData) -> Bool {
    let passcodeType: PasscodeEntryFieldType
    switch challengeData {
    case let .numericalPassword(value):
        passcodeType = value.count == 6 ? .digits6 : .digits4
    default:
        passcodeType = .alphanumeric
    }
    switch challengeData {
    case .none:
        return true
    case let .numericalPassword(code):
        if passcodeType == .alphanumeric {
            return false
        }
        return passcode == normalizeArabicNumeralString(code, type: .western)
    case let .plaintextPassword(code):
        if passcodeType != .alphanumeric {
            return false
        }
        return passcode == code
    }
}
```

### `submodules/TelegramUI/Sources/AppDelegate.swift` — класс кэша и хуки разблокировки (полные строки файла)

```swift
#if canImport(SGSettingsUI)
private final class DoubleBottomHiddenIdsCache {
    var hiddenIds: [Int64] = []
    var disposable: Disposable?

    init(accountManager: AccountManager<TelegramAccountManagerTypes>) {
        self.disposable = (accountManager.accountRecords()
            |> deliverOnMainQueue).start(next: { [weak self] view in
                self?.hiddenIds = view.records
                    .filter { $0.attributes.contains(where: { $0.isHiddenAccountAttribute }) }
                    .map { $0.id.int64 }
            })
    }
}
#endif
```

```swift
            #if canImport(SGSettingsUI)
            let doubleBottomHiddenIdsCache = DoubleBottomHiddenIdsCache(accountManager: accountManager)
            appLockContext.additionalPasscodeCheck = { passcode in
                guard VarSystemNGSettings.isDoubleBottomOn else { return false }
                if DoubleBottomPasscodeStore.secretPasscodeMatches(passcode) { return true }
                let ids = doubleBottomHiddenIdsCache.hiddenIds
                if !ids.isEmpty, DoubleBottomPasscodeStore.accountId(matchingPasscode: passcode, candidateIds: ids) != nil { return true }
                return false
            }
            appLockContext.onUnlockWithPasscode = { [weak sharedContext] passcode in
                guard let sharedContext = sharedContext, VarSystemNGSettings.isDoubleBottomOn else { return }
                let _ = (accountManager.accessChallengeData()
                    |> take(1)
                    |> deliverOnMainQueue).start(next: { [weak sharedContext] challengeView in
                        guard let sharedContext = sharedContext else { return }
                        let challengeData = challengeView.data
                        if doubleBottomCheckPasscode(passcode, challengeData: challengeData) {
                            DoubleBottomViewingSecretStore.setViewingWithSecretPasscode(false)
                        } else if DoubleBottomPasscodeStore.secretPasscodeMatches(passcode) {
                            DoubleBottomViewingSecretStore.setViewingWithSecretPasscode(true)
                        } else {
                            let _ = (accountManager.accountRecords()
                                |> take(1)
                                |> deliverOnMainQueue).start(next: { view in
                                    let hiddenIds = view.records
                                        .filter { $0.attributes.contains(where: { $0.isHiddenAccountAttribute }) }
                                        .map { $0.id.int64 }
                                    guard !hiddenIds.isEmpty,
                                          let matchedId = DoubleBottomPasscodeStore.accountId(matchingPasscode: passcode, candidateIds: hiddenIds) else { return }
                                    sharedContext.switchToAccount(id: AccountRecordId(rawValue: matchedId))
                                })
                        }
                    })
            }
            #endif
```

Точка входа в настройках LuxGram (пункты меню, не вся функция `gleGramAppearanceEntries`):

```swift
    entries.append(.header(id: id.count, section: .doubleBottom, text: (lang == "ru" ? "ДВОЙНОЕ ДНО" : "DOUBLE BOTTOM"), badge: nil))
    entries.append(.disclosure(id: id.count, section: .doubleBottom, link: .doubleBottomSettings, text: (lang == "ru" ? "Двойное дно" : "Double Bottom")))
    entries.append(.notice(id: id.count, section: .doubleBottom, text: (lang == "ru" ? "Скрытые аккаунты и вход по паролю. Разные пароли открывают разные профили." : "Hidden accounts and passcode access. Different passwords open different profiles.")))
```

---

## 2. Пароль при заходе в чат

**Смысл:** список защищённых peer id в UserDefaults; при открытии чата показывается `UIAlertController` с полем пароля; проверка либо через `doubleBottomCheckPasscode` (код Telegram на устройстве), либо через отдельный пароль в Keychain (`ProtectedChatsStore`).

### `LuxGram/SGSettingsUI/Sources/ProtectedChatsStore.swift` (полностью)

См. файл в репозитории — ниже идентичное содержимое.

```swift
// MARK: LuxGram – Password for selected chats/folders
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
```

### `LuxGram/SGSettingsUI/Sources/ProtectedChatsSettingsController.swift` (полностью)

```swift
// MARK: LuxGram – Password for selected chats/folders settings
import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import PasscodeUI

private enum ProtectedChatsEntry: ItemListNodeEntry {
    case enabled(String, Bool)
    case useDevicePasscode(String, Bool)
    case setCustomPasscode(String)
    case addChat(String)
    case protectedPeer(id: Int64, title: String)
    case notice(String)

    var section: ItemListSectionId {
        switch self {
        case .enabled, .useDevicePasscode, .setCustomPasscode, .notice: return 0
        case .addChat, .protectedPeer: return 1
        }
    }

    var stableId: Int {
        switch self {
        case .enabled: return 0
        case .useDevicePasscode: return 1
        case .setCustomPasscode: return 2
        case .addChat: return 3
        case .protectedPeer(let id, _): return 100 + Int(id % 100000)
        case .notice: return 200
        }
    }

    static func < (lhs: ProtectedChatsEntry, rhs: ProtectedChatsEntry) -> Bool {
        lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! ProtectedChatsArguments
        let lang = presentationData.strings.baseLanguageCode
        switch self {
        case let .enabled(title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: section, style: .blocks, updated: { args.toggleEnabled($0) })
        case let .useDevicePasscode(title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: section, style: .blocks, updated: { args.toggleUseDevicePasscode($0) })
        case let .setCustomPasscode(title):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: "", sectionId: section, style: .blocks, action: { args.setCustomPasscode() })
        case let .addChat(title):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: "", sectionId: section, style: .blocks, action: { args.addChat() })
        case let .protectedPeer(_, title):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: lang == "ru" ? "Удалить" : "Remove", sectionId: section, style: .blocks, action: { [self] in
                if case let .protectedPeer(peerId, _) = self { args.removePeer(peerId) }
            })
        case let .notice(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        }
    }
}

private final class ProtectedChatsArguments {
    let context: AccountContext
    let toggleEnabled: (Bool) -> Void
    let toggleUseDevicePasscode: (Bool) -> Void
    let setCustomPasscode: () -> Void
    let addChat: () -> Void
    let removePeer: (Int64) -> Void

    init(context: AccountContext, toggleEnabled: @escaping (Bool) -> Void, toggleUseDevicePasscode: @escaping (Bool) -> Void, setCustomPasscode: @escaping () -> Void, addChat: @escaping () -> Void, removePeer: @escaping (Int64) -> Void) {
        self.context = context
        self.toggleEnabled = toggleEnabled
        self.toggleUseDevicePasscode = toggleUseDevicePasscode
        self.setCustomPasscode = setCustomPasscode
        self.addChat = addChat
        self.removePeer = removePeer
    }
}

public func protectedChatsSettingsController(context: AccountContext) -> ViewController {
    let lang = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
    let title = lang == "ru" ? "Пароль для чатов" : "Password for chats"

    let statePromise = Promise<[(Int64, String)]>()
    let peerTitles: [(Int64, String)] = ProtectedChatsStore.protectedPeerIds.map { ($0, "Chat \($0)") }
    statePromise.set(.single(peerTitles))

    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = ProtectedChatsArguments(
        context: context,
        toggleEnabled: { value in
            ProtectedChatsStore.isEnabled = value
        },
        toggleUseDevicePasscode: { value in
            ProtectedChatsStore.useDevicePasscode = value
        },
        setCustomPasscode: {
            let setup = PasscodeSetupController(context: context, mode: .setup(change: false, .digits6))
            setup.complete = { passcode, _ in
                ProtectedChatsStore.setCustomPasscode(passcode)
                ProtectedChatsStore.useDevicePasscode = false
                _ = (setup.navigationController as? NavigationController)?.popViewController(animated: true)
            }
            pushControllerImpl?(setup)
        },
        addChat: {
            let filter: ChatListNodePeersFilter = [.onlyWriteable, .excludeDisabled, .doNotSearchMessages]
            let controller = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(
                context: context,
                filter: filter,
                hasContactSelector: false,
                hasGlobalSearch: true,
                title: lang == "ru" ? "Выберите чат" : "Select chat"
            ))
            controller.peerSelected = { [weak controller] peer, _ in
                let peerId = peer.id.toInt64()
                ProtectedChatsStore.addProtectedPeer(peerId)
                statePromise.set(.single(ProtectedChatsStore.protectedPeerIds.map { ($0, "Chat \($0)") }))
                _ = (controller?.navigationController as? NavigationController)?.popViewController(animated: true)
            }
            pushControllerImpl?(controller)
        },
        removePeer: { peerId in
            ProtectedChatsStore.removeProtectedPeer(peerId)
            statePromise.set(.single(ProtectedChatsStore.protectedPeerIds.map { ($0, "Chat \($0)") }))
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        statePromise.get()
    )
    |> map { presentationData, peerTitles -> (ItemListControllerState, (ItemListNodeState, ProtectedChatsArguments)) in
        let enabled = ProtectedChatsStore.isEnabled
        let useDevice = ProtectedChatsStore.useDevicePasscode
        let lang = presentationData.strings.baseLanguageCode

        var entries: [ProtectedChatsEntry] = []
        entries.append(.enabled(lang == "ru" ? "Пароль для чатов" : "Password for chats", enabled))
        if enabled {
            entries.append(.useDevicePasscode(lang == "ru" ? "Использовать пароль Telegram" : "Use Telegram passcode", useDevice))
            if !useDevice {
                entries.append(.setCustomPasscode(lang == "ru" ? "Установить отдельный пароль" : "Set separate passcode"))
            }
            entries.append(.notice(lang == "ru" ? "При открытии выбранных чатов будет запрашиваться пароль." : "Opening selected chats will require passcode."))
        }

        entries.append(.addChat(lang == "ru" ? "Добавить чат" : "Add chat"))
        for (id, t) in peerTitles.sorted(by: { $0.0 < $1.0 }) {
            entries.append(.protectedPeer(id: id, title: t))
        }

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(title),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks,
            ensureVisibleItemTag: nil,
            footerItem: nil,
            initialScrollToItem: nil
        )
        return (controllerState, (listState, arguments))
    }

    let signalTyped: Signal<(ItemListControllerState, (ItemListNodeState, ProtectedChatsArguments)), NoError> = signal
    let controller = ItemListController(context: context, state: signalTyped)
    pushControllerImpl = { [weak controller] (vc: ViewController) in
        (controller?.navigationController as? NavigationController)?.pushViewController(vc)
    }
    return controller
}
```

### `submodules/TelegramUI/Sources/SharedAccountContext.swift` — проверка при открытии чата (полный фрагмент)

```swift
    public func isChatProtected(peerId: PeerId) -> Bool {
        #if canImport(SGSettingsUI)
        return ProtectedChatsStore.isEnabled && ProtectedChatsStore.isProtected(peerId: peerId.toInt64())
        #else
        return false
        #endif
    }
```

```swift
    public func navigateToChatController(_ params: NavigateToChatControllerParams) {
        if case let .peer(peer) = params.chatLocation {
            let accountId = params.context.account.peerId.toInt64()
            let peerId = peer.id.toInt64()
            SGPluginHooks.willOpenChatRunner?(accountId, peerId)
            if let eventResult = SGPluginHooks.emitEvent("chat.willOpen", ["accountId": accountId, "peerId": peerId, "subject": params.subject.map { String(describing: $0) } ?? ""]), eventResult["cancel"] as? Bool == true {
                return
            }
        }
        #if canImport(SGSettingsUI)
        /// Saved Messages «Chats» tab opens dialogs as `.replyThread` with `peerId == account` and real peer id in `threadId`.
        let peerIdValue: Int64 = {
            switch params.chatLocation {
            case let .peer(peer):
                return peer.id.toInt64()
            case let .replyThread(message):
                if message.peerId == params.context.account.peerId,
                   !message.isForumPost, !message.isChannelPost, !message.isMonoforumPost {
                    return message.threadId
                }
                return message.peerId.toInt64()
            }
        }()
        if ProtectedChatsStore.isEnabled && ProtectedChatsStore.isProtected(peerId: peerIdValue) {
            let presentationData = params.context.sharedContext.currentPresentationData.with { $0 }
            let strings = presentationData.strings
            let useDevice = ProtectedChatsStore.useDevicePasscode
            let title = presentationData.strings.baseLanguageCode == "ru" ? "Введите пароль" : "Enter passcode"
            let message = presentationData.strings.baseLanguageCode == "ru" ? "Этот чат защищён паролем." : "This chat is protected with a passcode."
            var textField: UITextField?
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addTextField { field in
                field.isSecureTextEntry = true
                field.placeholder = presentationData.strings.baseLanguageCode == "ru" ? "Пароль" : "Passcode"
                textField = field
            }
            let cancelTitle = strings.Common_Cancel
            let okTitle = strings.Common_OK
            alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel) { _ in })
            alert.addAction(UIAlertAction(title: okTitle, style: .default) { [weak self] _ in
                guard let self = self, let entered = textField?.text, !entered.isEmpty else { return }
                let accountManager = self.accountManager
                let proceed: () -> Void = {
                    DispatchQueue.main.async {
                        navigateToChatControllerImpl(params)
                    }
                }
                if useDevice {
                    let _ = (accountManager.accessChallengeData()
                        |> take(1)
                        |> deliverOnMainQueue).start(next: { view in
                            if doubleBottomCheckPasscode(entered, challengeData: view.data) {
                                alert.dismiss(animated: true, completion: proceed)
                            } else {
                                let err = UIAlertController(title: nil, message: presentationData.strings.baseLanguageCode == "ru" ? "Неверный пароль" : "Wrong passcode", preferredStyle: .alert)
                                err.addAction(UIAlertAction(title: strings.Common_OK, style: .default) { _ in })
                                alert.present(err, animated: true)
                            }
                        })
                } else {
                    if ProtectedChatsStore.customPasscodeMatches(entered) {
                        alert.dismiss(animated: true, completion: proceed)
                    } else {
                        let err = UIAlertController(title: nil, message: presentationData.strings.baseLanguageCode == "ru" ? "Неверный пароль" : "Wrong passcode", preferredStyle: .alert)
                        err.addAction(UIAlertAction(title: strings.Common_OK, style: .default) { _ in })
                        alert.present(err, animated: true)
                    }
                }
            })
            if let top = params.navigationController.viewControllers.last {
                top.present(alert, animated: true)
            } else {
                navigateToChatControllerImpl(params)
            }
            return
        }
        #endif
        navigateToChatControllerImpl(params)
    }
```

Пункты в LuxGram (фрагмент `LuxGramSettingsController.swift`):

```swift
    entries.append(.header(id: id.count, section: .protectedChats, text: (lang == "ru" ? "ПАРОЛЬ ДЛЯ ЧАТОВ" : "PASSWORD FOR CHATS"), badge: nil))
    entries.append(.disclosure(id: id.count, section: .protectedChats, link: .protectedChatsSettings, text: (lang == "ru" ? "Пароль при заходе в чат" : "Password when entering chat")))
    entries.append(.notice(id: id.count, section: .protectedChats, text: (lang == "ru" ? "Выберите чаты и/или папки, при открытии которых нужно вводить пароль (пароль Telegram или отдельный)." : "Select chats and/or folders that require a passcode to open (device passcode or a separate one).")))
```

---

## 3. Смена голоса (Voice Morpher)

**Смысл:** локальная обработка OGG голосовых сообщений: декодирование Opus → `AVAudioEngine` (тон, скорость, искажение) → снова OGG. Настройки и пресеты — `VoiceMorpherManager`; вызов нативного процессора — `VoiceMorpherEngine` → `VoiceMorpherProcessor`.

### Пункты в LuxGram (`LuxGram/SGSettingsUI/Sources/LuxGramSettingsController.swift`)

```swift
    // MARK: Voice Morpher (Privacy tab) — ghostgram-style local processing
    entries.append(.header(id: id.count, section: .voiceChanger, text: (lang == "ru" ? "СМЕНА ГОЛОСА" : "VOICE MORPHER"), badge: nil))
    let vm = VoiceMorpherManager.shared
    entries.append(.toggle(id: id.count, section: .voiceChanger, settingName: .voiceChangerEnabled, value: vm.isEnabled, text: (lang == "ru" ? "Изменять голос при записи" : "Change voice when recording"), enabled: true))
    let ru = lang == "ru"
    let displayedPreset: VoiceMorpherManager.VoicePreset = {
        if !vm.isEnabled { return .disabled }
        if vm.selectedPresetId == 0 { return .anonymous }
        return vm.selectedPreset
    }()
    let presetTitle = displayedPreset.title(langIsRu: ru)
    entries.append(.disclosure(id: id.count, section: .voiceChanger, link: .voiceChangerVoicePicker, text: (ru ? "Эффект: \(presetTitle)" : "Effect: \(presetTitle)")))
    entries.append(.notice(id: id.count, section: .voiceChanger, text: (ru
        ? "Локально: OGG → эффекты iOS (тон, искажение) → снова OGG. Без серверов. Как в ghostgram iOS."
        : "On-device: OGG → iOS audio effects (pitch, distortion) → OGG. No servers. Same approach as ghostgram iOS.")))
```

### `submodules/TelegramCore/Sources/VoiceMorpher/VoiceMorpherManager.swift` (полностью)

```swift
import Foundation

/// LuxGram / ghostgram-style: local voice morphing for outgoing voice messages (UserDefaults).
public final class VoiceMorpherManager {
    public static let shared = VoiceMorpherManager()

    public enum VoicePreset: Int, CaseIterable {
        case disabled = 0
        case anonymous = 1
        case female = 2
        case male = 3
        case child = 4
        case robot = 5

        public func title(langIsRu: Bool) -> String {
            switch self {
            case .disabled:
                return langIsRu ? "Выключено" : "Off"
            case .anonymous:
                return langIsRu ? "Аноним" : "Anonymous"
            case .female:
                return langIsRu ? "Женский" : "Female"
            case .male:
                return langIsRu ? "Мужской" : "Male"
            case .child:
                return langIsRu ? "Ребёнок" : "Child"
            case .robot:
                return langIsRu ? "Робот" : "Robot"
            }
        }

        public func subtitle(langIsRu: Bool) -> String {
            switch self {
            case .disabled:
                return langIsRu ? "Без изменений" : "Unchanged"
            case .anonymous:
                return langIsRu ? "Искажённый голос" : "Distorted voice"
            case .female:
                return langIsRu ? "Выше тон" : "Higher pitch"
            case .male:
                return langIsRu ? "Ниже тон" : "Lower pitch"
            case .child:
                return langIsRu ? "Детский тон" : "Child-like"
            case .robot:
                return langIsRu ? "Металлический эффект" : "Metallic effect"
            }
        }
    }

    private enum Keys {
        static let isEnabled = "VoiceMorpher.isEnabled"
        static let selectedPreset = "VoiceMorpher.selectedPreset"
    }

    private let defaults = UserDefaults.standard

    public var isEnabled: Bool {
        get { defaults.bool(forKey: Keys.isEnabled) }
        set {
            defaults.set(newValue, forKey: Keys.isEnabled)
            notifyChanged()
        }
    }

    public var selectedPresetId: Int {
        get { defaults.integer(forKey: Keys.selectedPreset) }
        set {
            defaults.set(newValue, forKey: Keys.selectedPreset)
            notifyChanged()
        }
    }

    public var selectedPreset: VoicePreset {
        VoicePreset(rawValue: selectedPresetId) ?? .disabled
    }

    public var effectivePreset: VoicePreset {
        guard isEnabled else { return .disabled }
        return selectedPreset
    }

    public static let settingsChangedNotification = Notification.Name("VoiceMorpherSettingsChanged")

    private func notifyChanged() {
        NotificationCenter.default.post(name: Self.settingsChangedNotification, object: nil)
    }

    private init() {}
}
```

### `submodules/TelegramUI/Sources/VoiceMorpher/VoiceMorpherEngine.swift` (полностью)

```swift
import Foundation
import OpusBinding
import TelegramCore

/// Local OGG voice morphing (ghostgram-style): decode → AVAudioEngine effects → encode.
public final class VoiceMorpherEngine {
    public static let shared = VoiceMorpherEngine()

    private init() {}

    public func processOggData(
        _ inputData: Data,
        completion: @escaping (Swift.Result<Data, Error>) -> Void
    ) {
        let preset = VoiceMorpherManager.shared.effectivePreset

        guard preset != .disabled else {
            completion(.success(inputData))
            return
        }

        let objcPreset: VoiceMorpherPreset
        switch preset {
        case .disabled:
            objcPreset = .disabled
        case .anonymous:
            objcPreset = .anonymous
        case .female:
            objcPreset = .female
        case .male:
            objcPreset = .male
        case .child:
            objcPreset = .child
        case .robot:
            objcPreset = .robot
        }

        VoiceMorpherProcessor.processOggData(inputData, preset: objcPreset) { outputData, error in
            if let error {
                completion(.failure(error))
            } else if let outputData {
                completion(.success(outputData))
            } else {
                completion(.failure(VoiceMorpherError.processingFailed))
            }
        }
    }

    public enum VoiceMorpherError: Error, LocalizedError {
        case processingFailed

        public var errorDescription: String? {
            switch self {
            case .processingFailed:
                return "Voice morphing processing failed"
            }
        }
    }
}
```

### `submodules/OpusBinding/PublicHeaders/OpusBinding/VoiceMorpherProcessor.h` (полностью)

```objc
#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// VoiceMorpherProcessor - Processes OGG/Opus audio with voice effects
/// Decodes OGG -> applies effects -> re-encodes to OGG
@interface VoiceMorpherProcessor : NSObject

typedef NS_ENUM(NSInteger, VoiceMorpherPreset) {
    VoiceMorpherPresetDisabled = 0,
    VoiceMorpherPresetAnonymous = 1,
    VoiceMorpherPresetFemale = 2,
    VoiceMorpherPresetMale = 3,
    VoiceMorpherPresetChild = 4,
    VoiceMorpherPresetRobot = 5
};

/// Process OGG audio data with voice morphing effect
+ (void)processOggData:(NSData *)inputData
                preset:(VoiceMorpherPreset)preset
            completion:(void (^)(NSData *_Nullable outputData,
                                 NSError *_Nullable error))completion;

+ (float)pitchShiftForPreset:(VoiceMorpherPreset)preset;
+ (float)rateForPreset:(VoiceMorpherPreset)preset;

@end

NS_ASSUME_NONNULL_END
```

### `submodules/OpusBinding/Sources/VoiceMorpherProcessor.m` (полностью)

```objc
#import "VoiceMorpherProcessor.h"
#import "OggOpusReader.h"
#import "TGDataItem.h"
#import "TGOggOpusWriter.h"

@implementation VoiceMorpherProcessor

+ (float)pitchShiftForPreset:(VoiceMorpherPreset)preset {
  switch (preset) {
  case VoiceMorpherPresetDisabled:
    return 0;
  case VoiceMorpherPresetAnonymous:
    return -200;
  case VoiceMorpherPresetFemale:
    return 600; // More feminine - higher pitch
  case VoiceMorpherPresetMale:
    return -300;
  case VoiceMorpherPresetChild:
    return 600;
  case VoiceMorpherPresetRobot:
    return 0;
  }
}

+ (float)rateForPreset:(VoiceMorpherPreset)preset {
  switch (preset) {
  case VoiceMorpherPresetDisabled:
    return 1.0;
  case VoiceMorpherPresetAnonymous:
    return 0.95;
  case VoiceMorpherPresetFemale:
    return 1.08; // Slightly faster for feminine effect
  case VoiceMorpherPresetMale:
    return 0.95;
  case VoiceMorpherPresetChild:
    return 1.1;
  case VoiceMorpherPresetRobot:
    return 1.0;
  }
}

+ (void)processOggData:(NSData *)inputData
                preset:(VoiceMorpherPreset)preset
            completion:
                (void (^)(NSData *_Nullable, NSError *_Nullable))completion {

  if (preset == VoiceMorpherPresetDisabled) {
    completion(inputData, nil);
    return;
  }

  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                 ^{
                   NSError *error = nil;
                   NSData *result = [self processOggDataSync:inputData
                                                      preset:preset
                                                       error:&error];

                   // Call completion on background thread to avoid deadlock
                   // when caller uses semaphore on main thread
                   completion(result, error);
                 });
}

+ (NSData *_Nullable)processOggDataSync:(NSData *)inputData
                                 preset:(VoiceMorpherPreset)preset
                                  error:(NSError **)error {
  // Save input OGG to temp file for decoding
  NSString *tempInputPath = [NSTemporaryDirectory()
      stringByAppendingPathComponent:
          [NSString
              stringWithFormat:@"vm_in_%lld.ogg", (long long)[[NSDate date]
                                                      timeIntervalSince1970] *
                                                      1000]];

  [inputData writeToFile:tempInputPath atomically:YES];

  // Decode OGG to PCM
  OggOpusReader *reader = [[OggOpusReader alloc] initWithPath:tempInputPath];
  if (!reader) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"VoiceMorpher"
                     code:1
                 userInfo:@{
                   NSLocalizedDescriptionKey : @"Failed to open OGG file"
                 }];
    }
    [[NSFileManager defaultManager] removeItemAtPath:tempInputPath error:nil];
    return nil;
  }

  // Opus outputs 16-bit stereo at 48kHz
  NSMutableData *pcmData = [[NSMutableData alloc] init];
  int16_t buffer[5760 * 2]; // Max frame size * channels
  int32_t samplesRead;

  while ((samplesRead = [reader read:buffer
                             bufSize:sizeof(buffer) / sizeof(buffer[0])]) > 0) {
    [pcmData appendBytes:buffer length:samplesRead * sizeof(int16_t)];
  }

  [[NSFileManager defaultManager] removeItemAtPath:tempInputPath error:nil];

  if (pcmData.length == 0) {
    if (error) {
      *error =
          [NSError errorWithDomain:@"VoiceMorpher"
                              code:2
                          userInfo:@{
                            NSLocalizedDescriptionKey : @"No PCM data decoded"
                          }];
    }
    return nil;
  }

  // Apply voice effects using AVAudioEngine
  NSData *processedPcm = [self applyEffectsToPcmData:pcmData
                                              preset:preset
                                               error:error];
  if (!processedPcm) {
    return nil;
  }

  // Encode processed PCM back to OGG
  TGDataItem *dataItem = [[TGDataItem alloc] init];
  TGOggOpusWriter *writer = [[TGOggOpusWriter alloc] init];

  if (![writer beginWithDataItem:dataItem]) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"VoiceMorpher"
                     code:4
                 userInfo:@{
                   NSLocalizedDescriptionKey : @"Failed to begin OGG encoding"
                 }];
    }
    return nil;
  }

  // Write PCM data in frames (960 samples = 20ms at 48kHz)
  const int frameSize = 960 * sizeof(int16_t);
  const uint8_t *bytes = processedPcm.bytes;
  NSUInteger remaining = processedPcm.length;
  NSUInteger offset = 0;

  while (remaining >= frameSize) {
    [writer writeFrame:(uint8_t *)(bytes + offset) frameByteCount:frameSize];
    offset += frameSize;
    remaining -= frameSize;
  }

  if (remaining > 0) {
    uint8_t lastFrame[frameSize];
    memset(lastFrame, 0, frameSize);
    memcpy(lastFrame, bytes + offset, remaining);
    [writer writeFrame:lastFrame frameByteCount:frameSize];
  }

  return [dataItem data];
}

+ (NSData *_Nullable)applyEffectsToPcmData:(NSData *)pcmData
                                    preset:(VoiceMorpherPreset)preset
                                     error:(NSError **)error {
  NSUInteger sampleCount = pcmData.length / sizeof(int16_t);
  const int16_t *int16Samples = (const int16_t *)pcmData.bytes;

  float *floatSamples = (float *)malloc(sampleCount * sizeof(float));
  if (!floatSamples) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"VoiceMorpher"
                     code:5
                 userInfo:@{
                   NSLocalizedDescriptionKey : @"Memory allocation failed"
                 }];
    }
    return nil;
  }

  // Convert int16 to float (-1.0 to 1.0 range)
  for (NSUInteger i = 0; i < sampleCount; i++) {
    floatSamples[i] = (float)int16Samples[i] / 32768.0f;
  }

  // Create audio format (mono, 48kHz, float)
  AVAudioFormat *format =
      [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                       sampleRate:48000
                                         channels:1
                                      interleaved:NO];

  AVAudioFrameCount frameCount = (AVAudioFrameCount)sampleCount;
  AVAudioPCMBuffer *inputBuffer =
      [[AVAudioPCMBuffer alloc] initWithPCMFormat:format
                                    frameCapacity:frameCount];
  inputBuffer.frameLength = frameCount;

  memcpy(inputBuffer.floatChannelData[0], floatSamples,
         sampleCount * sizeof(float));
  free(floatSamples);

  // Create engine and nodes
  AVAudioEngine *engine = [[AVAudioEngine alloc] init];
  AVAudioPlayerNode *playerNode = [[AVAudioPlayerNode alloc] init];
  AVAudioUnitTimePitch *pitchNode = [[AVAudioUnitTimePitch alloc] init];

  pitchNode.pitch = [self pitchShiftForPreset:preset];
  pitchNode.rate = [self rateForPreset:preset];

  [engine attachNode:playerNode];
  [engine attachNode:pitchNode];
  [engine connect:playerNode to:pitchNode format:format];

  AVAudioNode *lastNode = pitchNode;

  if (preset == VoiceMorpherPresetRobot) {
    AVAudioUnitDistortion *distortion = [[AVAudioUnitDistortion alloc] init];
    [distortion loadFactoryPreset:AVAudioUnitDistortionPresetSpeechRadioTower];
    distortion.wetDryMix = 40;
    [engine attachNode:distortion];
    [engine connect:pitchNode to:distortion format:format];
    lastNode = distortion;
  } else if (preset == VoiceMorpherPresetAnonymous) {
    AVAudioUnitDistortion *distortion = [[AVAudioUnitDistortion alloc] init];
    [distortion
        loadFactoryPreset:AVAudioUnitDistortionPresetSpeechCosmicInterference];
    distortion.wetDryMix = 30;
    [engine attachNode:distortion];
    [engine connect:pitchNode to:distortion format:format];
    lastNode = distortion;
  }

  [engine connect:lastNode to:engine.mainMixerNode format:format];

  __block NSMutableData *outputData = [[NSMutableData alloc] init];

  [engine.mainMixerNode
      installTapOnBus:0
           bufferSize:4096
               format:format
                block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
                  float *samples = buffer.floatChannelData[0];
                  AVAudioFrameCount count = buffer.frameLength;

                  int16_t *int16Buffer =
                      (int16_t *)malloc(count * sizeof(int16_t));
                  for (AVAudioFrameCount i = 0; i < count; i++) {
                    float sample = samples[i];
                    if (sample > 1.0f)
                      sample = 1.0f;
                    if (sample < -1.0f)
                      sample = -1.0f;
                    int16Buffer[i] = (int16_t)(sample * 32767.0f);
                  }

                  [outputData appendBytes:int16Buffer
                                   length:count * sizeof(int16_t)];
                  free(int16Buffer);
                }];

  NSError *startError = nil;
  [engine startAndReturnError:&startError];
  if (startError) {
    if (error) {
      *error = startError;
    }
    return nil;
  }

  [playerNode scheduleBuffer:inputBuffer
                      atTime:nil
                     options:0
           completionHandler:nil];
  [playerNode play];

  float rate = [self rateForPreset:preset];
  NSTimeInterval duration = (double)sampleCount / 48000.0 / rate + 0.5;
  [NSThread sleepForTimeInterval:duration];

  [playerNode stop];
  [engine.mainMixerNode removeTapOnBus:0];
  [engine stop];

  return outputData;
}

@end
```

---

## 4. Поиск во вкладке сохранённых удалённых сообщений

**Смысл:** экран `savedDeletedMessagesListController` строит записи через `savedDeletedListEntries`, поле поиска — первая строка; `filterSavedDeletedListEntries` отфильтровывает секции без совпадений по запросу (имя чата, текст сообщения, дата, подписи кнопок).

### `LuxGram/SGSettingsUI/Sources/SavedDeletedMessagesListController.swift` (полностью)

Файл приведён целиком в репозитории (292 строки). Ниже — полная копия без изменений.

```swift
// MARK: LuxGram – Saved Deleted Messages List
import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
#if canImport(SGDeletedMessages)
import SGDeletedMessages
#endif

// MARK: - Entry

private enum SavedDeletedListEntry: ItemListNodeEntry {
    case search(id: Int, query: String)
    case empty(id: Int, text: String)
    case peerHeader(id: Int, sectionIndex: Int32, text: String)
    case messageRow(id: Int, sectionIndex: Int32, text: String, dateText: String, peerId: PeerId, messageId: MessageId, searchableText: String)
    case deleteAction(id: Int, sectionIndex: Int32, text: String, peerId: PeerId)

    var stableId: Int {
        switch self {
        case .search(let id, _): return id
        case .empty(let id, _): return id
        case .peerHeader(let id, _, _): return id
        case .messageRow(let id, _, _, _, _, _, _): return id
        case .deleteAction(let id, _, _, _): return id
        }
    }

    var section: ItemListSectionId {
        switch self {
        case .search(_, _): return 0
        case .empty: return 0
        case .peerHeader(_, let s, _): return s
        case .messageRow(_, let s, _, _, _, _, _): return s
        case .deleteAction(_, let s, _, _): return s
        }
    }

    static func < (lhs: SavedDeletedListEntry, rhs: SavedDeletedListEntry) -> Bool {
        lhs.stableId < rhs.stableId
    }

    static func == (lhs: SavedDeletedListEntry, rhs: SavedDeletedListEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.search(a, q1), .search(b, q2)): return a == b && q1 == q2
        case let (.empty(a, t1), .empty(b, t2)): return a == b && t1 == t2
        case let (.peerHeader(a, s1, t1), .peerHeader(b, s2, t2)): return a == b && s1 == s2 && t1 == t2
        case let (.messageRow(a, s1, t1, d1, p1, m1, _), .messageRow(b, s2, t2, d2, p2, m2, _)): return a == b && s1 == s2 && t1 == t2 && d1 == d2 && p1 == p2 && m1 == m2
        case let (.deleteAction(a, s1, t1, p1), .deleteAction(b, s2, t2, p2)): return a == b && s1 == s2 && t1 == t2 && p1 == p2
        default: return false
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! SavedDeletedListArguments
        switch self {
        case .search(_, let query):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: "🔍"), text: query, placeholder: presentationData.strings.Common_Search, type: .regular(capitalization: false, autocorrection: false), spacing: 0.0, clearType: .always, tag: nil, sectionId: section, textUpdated: { args.searchUpdated($0) }, action: {})
        case .empty(_, let text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        case .peerHeader(_, _, let text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: section)
        case .messageRow(_, _, let text, let dateText, let peerId, let messageId, _):
            return ItemListDisclosureItem(presentationData: presentationData, title: text, label: dateText, sectionId: section, style: .blocks, action: {
                args.openMessage(peerId, messageId)
            })
        case .deleteAction(_, _, let text, let peerId):
            return ItemListActionItem(presentationData: presentationData, title: text, kind: .destructive, alignment: .natural, sectionId: section, style: .blocks, action: {
                args.deleteMessagesForPeer(peerId)
            })
        }
    }
}

// MARK: - Arguments

private final class SearchQueryRef {
    var value: String = ""
}

private final class SavedDeletedListArguments {
    let searchQueryRef: SearchQueryRef
    var searchQuery: String { searchQueryRef.value }
    let searchUpdated: (String) -> Void
    let deleteMessagesForPeer: (PeerId) -> Void
    let openMessage: (PeerId, MessageId) -> Void
    init(searchQueryRef: SearchQueryRef, searchUpdated: @escaping (String) -> Void, deleteMessagesForPeer: @escaping (PeerId) -> Void, openMessage: @escaping (PeerId, MessageId) -> Void) {
        self.searchQueryRef = searchQueryRef
        self.searchUpdated = searchUpdated
        self.deleteMessagesForPeer = deleteMessagesForPeer
        self.openMessage = openMessage
    }
}

// MARK: - Date formatting

private let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
}()

// MARK: - Entries builder (full list, no filter — like LuxGram settings)

#if canImport(SGDeletedMessages)
private func savedDeletedListEntries(
    data: [(peer: Peer?, peerId: PeerId, messages: [Message])],
    lang: String
) -> [SavedDeletedListEntry] {
    var entries: [SavedDeletedListEntry] = []
    var id = 0

    entries.append(.search(id: id, query: ""))
    id += 1

    if data.isEmpty {
        let text = (lang == "ru" ? "Нет сохранённых удалённых сообщений." : "No saved deleted messages.")
        entries.append(.empty(id: id, text: text))
        return entries
    }

    var sectionIndex: Int32 = 0
    for group in data {
        let peerName: String
        if let peer = group.peer {
            peerName = peer.debugDisplayTitle
        } else {
            peerName = "Peer \(group.peerId.id._internalGetInt64Value())"
        }
        sectionIndex += 1
        let countStr = lang == "ru" ? "\(group.messages.count) сообщ." : "\(group.messages.count) msg"
        entries.append(.peerHeader(id: id, sectionIndex: sectionIndex, text: "\(peerName.uppercased()) (\(countStr))"))
        id += 1

        for message in group.messages {
            let text = message.text.isEmpty
                ? (lang == "ru" ? "[медиа]" : "[media]")
                : String(message.text.prefix(120)).replacingOccurrences(of: "\n", with: " ")
            let searchableText = (message.text + " " + (message.sgDeletedAttribute.originalText ?? "")).trimmingCharacters(in: .whitespacesAndNewlines)
            let date = dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(message.timestamp)))
            entries.append(.messageRow(id: id, sectionIndex: sectionIndex, text: text, dateText: date, peerId: group.peerId, messageId: message.id, searchableText: searchableText))
            id += 1
        }

        let deleteText = lang == "ru" ? "Удалить все для этого чата" : "Delete all for this chat"
        entries.append(.deleteAction(id: id, sectionIndex: sectionIndex, text: deleteText, peerId: group.peerId))
        id += 1
    }

    return entries
}

/// Filter by search query — same logic as filterSGItemListUIEntrires in LuxGram settings: two-pass, keep search, keep sections that have matches.
private func filterSavedDeletedListEntries(_ entries: [SavedDeletedListEntry], by searchQuery: String?, lang: String) -> [SavedDeletedListEntry] {
    guard let query = searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !query.isEmpty else {
        return entries
    }
    var sectionIdsWithMatches: Set<Int32> = []
    for entry in entries {
        switch entry {
        case .search(_, _), .empty:
            break
        case .peerHeader(_, let s, let text):
            if text.lowercased().contains(query) { sectionIdsWithMatches.insert(s) }
        case .messageRow(_, let s, _, let dateText, _, _, let searchableText):
            if searchableText.lowercased().contains(query) || dateText.lowercased().contains(query) { sectionIdsWithMatches.insert(s) }
        case .deleteAction(_, let s, let text, _):
            if text.lowercased().contains(query) { sectionIdsWithMatches.insert(s) }
        }
    }
    var filtered: [SavedDeletedListEntry] = []
    for entry in entries {
        switch entry {
        case .search(_, _):
            filtered.append(entry)
        case .empty:
            continue
        case .peerHeader(_, let s, _), .messageRow(_, let s, _, _, _, _, _), .deleteAction(_, let s, _, _):
            if sectionIdsWithMatches.contains(s) {
                filtered.append(entry)
            }
        }
    }
    if filtered.count == 1, case .search(_, _) = filtered[0] {
        filtered.append(.empty(id: Int.max, text: lang == "ru" ? "Ничего не найдено." : "No results."))
    }
    return filtered
}
#endif

// MARK: - Controller

public func savedDeletedMessagesListController(context: AccountContext) -> ViewController {
    #if canImport(SGDeletedMessages)
    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?
    let reloadPromise = ValuePromise(true, ignoreRepeated: false)
    let searchQueryPromise = ValuePromise("", ignoreRepeated: false)
    let searchQueryRef = SearchQueryRef()

    let arguments = SavedDeletedListArguments(
        searchQueryRef: searchQueryRef,
        searchUpdated: { value in
            searchQueryRef.value = value
            searchQueryPromise.set(value)
        },
        deleteMessagesForPeer: { peerId in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let lang = presentationData.strings.baseLanguageCode
            let title = lang == "ru" ? "Удалить" : "Delete"
            let text = lang == "ru" ? "Удалить все сохранённые удалённые сообщения для этого чата?" : "Delete all saved deleted messages for this chat?"
            let alert = textAlertController(
                context: context,
                title: title,
                text: text,
                actions: [
                    TextAlertAction(type: .destructiveAction, title: presentationData.strings.Common_Delete, action: {
                        let _ = (SGDeletedMessages.getAllSavedDeletedMessages(postbox: context.account.postbox)
                        |> mapToSignal { groups -> Signal<Void, NoError> in
                            var idsToDelete: [MessageId] = []
                            for group in groups where group.peerId == peerId {
                                idsToDelete.append(contentsOf: group.messages.map { $0.id })
                            }
                            return SGDeletedMessages.deleteSavedDeletedMessages(ids: idsToDelete, postbox: context.account.postbox)
                        }
                        |> deliverOnMainQueue).start(completed: {
                            reloadPromise.set(true)
                        })
                    }),
                    TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_Cancel, action: {})
                ]
            )
            presentControllerImpl?(alert, nil)
        },
        openMessage: { peerId, messageId in
            let chatController = context.sharedContext.makeChatController(context: context, chatLocation: .peer(id: peerId), subject: .message(id: .id(messageId), highlight: nil, timecode: nil, setupReply: false), botStart: nil, mode: .standard(.default), params: nil)
            pushControllerImpl?(chatController)
        }
    )

    let dataSignal = reloadPromise.get()
    |> mapToSignal { _ -> Signal<[(peer: Peer?, peerId: PeerId, messages: [Message])], NoError> in
        return SGDeletedMessages.getAllSavedDeletedMessages(postbox: context.account.postbox)
    }

    let signal = combineLatest(dataSignal, searchQueryPromise.get(), context.sharedContext.presentationData)
    |> map { data, searchQuery, presentationData -> (ItemListControllerState, (ItemListNodeState, SavedDeletedListArguments)) in
        let lang = presentationData.strings.baseLanguageCode
        let title = lang == "ru" ? "Сохранённые удалённые" : "Saved Deleted"
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(title),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let allEntries = savedDeletedListEntries(data: data, lang: lang)
        let entriesWithQuery = allEntries.map { entry -> SavedDeletedListEntry in
            if case .search(let id, _) = entry { return .search(id: id, query: searchQuery) }
            return entry
        }
        let entries = filterSavedDeletedListEntries(entriesWithQuery, by: searchQuery, lang: lang)
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks,
            ensureVisibleItemTag: nil,
            initialScrollToItem: nil
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c, a in
        controller?.present(c, in: PresentationContextType.window(PresentationSurfaceLevel.root), with: a)
    }
    pushControllerImpl = { [weak controller] c in
        controller?.navigationController?.pushViewController(c, animated: true)
    }
    return controller
    #else
    return ViewController(navigationBarPresentationData: nil)
    #endif
}
```

### `LuxGram/SGDeletedMessages/Sources/SGDeletedMessages.swift` (полностью)

```swift
import Foundation
import Postbox
import SwiftSignalKit
import SGSimpleSettings
#if canImport(SGLogging)
import SGLogging
#endif

// Local constants to avoid circular dependency with TelegramCore (SyncCore_Namespaces).
// Namespaces.Message.Cloud = 0
private let messageNamespaceCloud: Int32 = 0
// Namespaces.Message.SavedDeleted = 1338
private let messageNamespaceSavedDeleted: Int32 = 1338

public struct SGDeletedMessages {
    public static var showDeletedMessages: Bool {
        get {
            return SGSimpleSettings.shared.showDeletedMessages
        }
        set {
            SGSimpleSettings.shared.showDeletedMessages = newValue
        }
    }
    
    private static func savedDeletedId(for originalId: MessageId) -> MessageId {
        return MessageId(peerId: originalId.peerId, namespace: messageNamespaceSavedDeleted, id: originalId.id)
    }
    
    /// AyuGram-style: create a local SavedDeleted snapshot (separate namespace) and return `true` if saved.
    private static func saveSnapshotIfPossible(
        originalId: MessageId,
        transaction: Transaction,
        shouldSave: ((MessageId, Message) -> Bool)?,
        transformAttributes: ((Message, inout [MessageAttribute]) -> Void)?,
        transformMedia: ((Message, [Media]) -> [Media])?
    ) -> Bool {
        // If we're deleting an already-saved snapshot, don't re-save it.
        if originalId.namespace == messageNamespaceSavedDeleted {
            return false
        }
        
        guard let message = transaction.getMessage(originalId) else {
            // No local copy -> can't save (AyuGram behavior).
            return false
        }
        
        if let shouldSave, !shouldSave(originalId, message) {
            return false
        }
        
        let snapshotId = savedDeletedId(for: originalId)
        if transaction.messageExists(id: snapshotId) {
            return true
        }
        
        let storeForwardInfo = message.forwardInfo.flatMap(StoreMessageForwardInfo.init)
        var attributes = message.attributes
        var hasDeletedAttribute = false
        for attribute in attributes {
            if let deletedAttribute = attribute as? SGDeletedMessageAttribute {
                deletedAttribute.isDeleted = true
                if deletedAttribute.originalText == nil {
                    deletedAttribute.originalText = message.text
                }
                deletedAttribute.originalNamespace = originalId.namespace
                deletedAttribute.originalId = originalId.id
                hasDeletedAttribute = true
                break
            }
        }
        if !hasDeletedAttribute {
            attributes.append(SGDeletedMessageAttribute(isDeleted: true, originalText: message.text, originalNamespace: originalId.namespace, originalId: originalId.id))
        }
        
        transformAttributes?(message, &attributes)
        
        let media: [Media]
        if let transformMedia {
            media = transformMedia(message, message.media)
        } else {
            media = message.media
        }
        
        // Important: this is a local-only snapshot, so we don't keep a globallyUniqueId
        // (to avoid collisions with the original message).
        let storeMessage = StoreMessage(
            id: snapshotId,
            customStableId: nil,
            globallyUniqueId: nil,
            groupingKey: message.groupingKey,
            threadId: message.threadId,
            timestamp: message.timestamp,
            flags: StoreMessageFlags(message.flags),
            tags: message.tags,
            globalTags: message.globalTags,
            localTags: message.localTags,
            forwardInfo: storeForwardInfo,
            authorId: message.author?.id,
            text: message.text,
            attributes: attributes,
            media: media
        )
        let _ = transaction.addMessages([storeMessage], location: .UpperHistoryBlock)
        #if canImport(SGLogging)
        SGLogger.shared.log("SGDeletedMessages", "saveSnapshotIfPossible: saved snapshot \(snapshotId) for original \(originalId)")
        #endif
        return true
    }
    
    /// AyuGram-style: save snapshots (when possible).
    /// Returns the set of message ids for which a snapshot exists (created or already present).
    public static func saveSnapshots(
        ids: [MessageId],
        transaction: Transaction,
        shouldSave: ((MessageId, Message) -> Bool)? = nil,
        transformAttributes: ((Message, inout [MessageAttribute]) -> Void)? = nil,
        transformMedia: ((Message, [Media]) -> [Media])? = nil
    ) -> Set<MessageId> {
        guard showDeletedMessages, !ids.isEmpty else { return Set() }
        
        var result = Set<MessageId>()
        result.reserveCapacity(ids.count)
        
        for id in ids {
            if saveSnapshotIfPossible(originalId: id, transaction: transaction, shouldSave: shouldSave, transformAttributes: transformAttributes, transformMedia: transformMedia) {
                result.insert(id)
            }
        }
        return result
    }
    
    /// AyuGram-style: for delete-by-global-id pipelines, save snapshots for locally-present messages.
    public static func saveSnapshotsForGlobalIds(
        _ globalIds: [Int32],
        transaction: Transaction,
        shouldSave: ((MessageId, Message) -> Bool)? = nil,
        transformAttributes: ((Message, inout [MessageAttribute]) -> Void)? = nil,
        transformMedia: ((Message, [Media]) -> [Media])? = nil
    ) {
        guard showDeletedMessages else { return }
        for globalId in globalIds {
            if let id = transaction.messageIdsForGlobalIds([globalId]).first {
                _ = saveSnapshotIfPossible(originalId: id, transaction: transaction, shouldSave: shouldSave, transformAttributes: transformAttributes, transformMedia: transformMedia)
            }
        }
    }
    
    /// AyuGram-style: save snapshots (when possible) and return ids to physically delete.
    /// If the id itself is already a SavedDeleted snapshot, it will be deleted (no resave).
    public static func saveSnapshotsAndReturnIdsToDelete(ids: [MessageId], transaction: Transaction) -> [MessageId] {
        _ = saveSnapshots(ids: ids, transaction: transaction, shouldSave: nil, transformAttributes: nil, transformMedia: nil)
        return ids
    }
    
    /// Check if message is marked as deleted (using extension like Nicegram)
    public static func isMessageDeleted(_ message: Message) -> Bool {
        return message.sgDeletedAttribute.isDeleted
    }
    
    /// Get original text from message attribute (for edit history, using extension like Nicegram)
    public static func getOriginalText(_ message: Message) -> String? {
        return message.sgDeletedAttribute.originalText
    }
    
    /// Returns the combined on-disk size (in bytes) of the saved-deleted-attachments folder.
    public static func storageSizeBytes(mediaBoxBasePath: String) -> Int64 {
        let attachmentsPath = mediaBoxBasePath + "/saved-deleted-attachments"
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: attachmentsPath),
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    /// Fetch all saved deleted messages grouped by peer.
    public static func getAllSavedDeletedMessages(
        postbox: Postbox
    ) -> Signal<[(peer: Peer?, peerId: PeerId, messages: [Message])], NoError> {
        return postbox.transaction { transaction -> [(peer: Peer?, peerId: PeerId, messages: [Message])] in
            var result: [(peer: Peer?, peerId: PeerId, messages: [Message])] = []
            let allPeerIds = transaction.chatListGetAllPeerIds()
            for peerId in allPeerIds {
                var messages: [Message] = []
                transaction.scanMessageAttributes(peerId: peerId, namespace: messageNamespaceSavedDeleted, limit: Int.max) { messageId, _ in
                    if let message = transaction.getMessage(messageId) {
                        messages.append(message)
                    }
                    return true
                }
                if !messages.isEmpty {
                    messages.sort { $0.timestamp > $1.timestamp }
                    let peer = transaction.getPeer(peerId)
                    result.append((peer: peer, peerId: peerId, messages: messages))
                }
            }
            result.sort { ($0.messages.first?.timestamp ?? 0) > ($1.messages.first?.timestamp ?? 0) }
            return result
        }
    }

    /// Delete specific saved deleted messages by their IDs.
    public static func deleteSavedDeletedMessages(
        ids: [MessageId],
        postbox: Postbox
    ) -> Signal<Void, NoError> {
        return postbox.transaction { transaction -> Void in
            if !ids.isEmpty {
                transaction.deleteMessages(ids, forEachMedia: { _ in })
            }
        }
    }

    /// Clear all saved deleted messages (actually delete them). Returns the number of deleted messages.
    public static func clearAllDeletedMessages(
        postbox: Postbox
    ) -> Signal<Int, NoError> {
        return postbox.transaction { transaction -> Int in
            // Remove saved attachment copies (AyuGram-style "Saved Attachments").
            let attachmentsPath = postbox.mediaBox.basePath + "/saved-deleted-attachments"
            let _ = try? FileManager.default.removeItem(atPath: attachmentsPath)
            let _ = try? FileManager.default.createDirectory(atPath: attachmentsPath, withIntermediateDirectories: true, attributes: nil)

            // All messages in the SavedDeleted namespace (1338) are snapshots — no attribute check needed.
            var messageIdsToDelete: [MessageId] = []
            let allPeerIds = transaction.chatListGetAllPeerIds()
            for peerId in allPeerIds {
                transaction.scanMessageAttributes(peerId: peerId, namespace: messageNamespaceSavedDeleted, limit: Int.max) { messageId, _ in
                    messageIdsToDelete.append(messageId)
                    return true
                }
            }

            let count = messageIdsToDelete.count
            if !messageIdsToDelete.isEmpty {
                transaction.deleteMessages(messageIdsToDelete, forEachMedia: { _ in })
            }

            return count
        }
    }
}
```

---

## 5. Ответ на удалённое сообщение: цитата оформляется сущностью `.Pre`

**Смысл:** если ответ идёт на сообщение с признаком «удалённое» (`sgDeletedAttribute.isDeleted`), вместо обычного `ReplyMessageAttribute` текст исходного сообщения вставляется **перед** вашим текстом с переводом строки, а диапазон цитаты помечается `MessageTextEntity` с типом `.Pre(language: nil)` (в клиентах Telegram это отображается как моноширинный / «блок кода» блок — визуальное выделение цитаты).

### `submodules/TelegramCore/Sources/PendingMessages/EnqueueMessage.swift` — полный фрагмент `if let replyToMessageId = replyToMessageId { ... }`

```swift
                    if let replyToMessageId = replyToMessageId {
                        #if canImport(SGDeletedMessages)
                        let useDeletedCitation: Bool = {
                            if let replyMessage = transaction.getMessage(replyToMessageId.messageId) {
                                return replyMessage.sgDeletedAttribute.isDeleted
                            }
                            return false
                        }()
                        #else
                        let useDeletedCitation = false
                        #endif
                        if useDeletedCitation {
                            #if canImport(SGDeletedMessages)
                            if let replyMessage = transaction.getMessage(replyToMessageId.messageId) {
                                let quoteText = replyMessage.sgDeletedAttribute.originalText ?? replyMessage.text
                                let citationPrefix = quoteText + "\n"
                                effectiveText = citationPrefix + text
                                let offset = citationPrefix.count
                                let citationEntities = [MessageTextEntity(range: 0..<offset, type: .Pre(language: nil))]
                                var foundEntities = false
                                for i in attributes.indices {
                                    if let entityAttr = attributes[i] as? TextEntitiesMessageAttribute {
                                        let shifted = entityAttr.entities.map { MessageTextEntity(range: $0.range.lowerBound + offset ..< $0.range.upperBound + offset, type: $0.type) }
                                        attributes[i] = TextEntitiesMessageAttribute(entities: citationEntities + shifted)
                                        foundEntities = true
                                        break
                                    }
                                }
                                if !foundEntities {
                                    attributes.append(TextEntitiesMessageAttribute(entities: citationEntities))
                                }
                            }
                            #endif
                        } else {
                            var threadMessageId: MessageId?
                            var quote = replyToMessageId.quote
                            let isQuote = quote != nil
                            if let replyMessage = transaction.getMessage(replyToMessageId.messageId) {
                                if replyMessage.id.namespace == Namespaces.Message.Cloud, let threadId = replyMessage.threadId {
                                    threadMessageId = MessageId(peerId: replyMessage.id.peerId, namespace: Namespaces.Message.Cloud, id: Int32(clamping: threadId))
                                }
                                if quote == nil, replyToMessageId.messageId.peerId != peerId {
                                    let nsText = replyMessage.text as NSString
                                    var replyMedia: Media?
                                    for m in replyMessage.media {
                                        switch m {
                                        case _ as TelegramMediaImage, _ as TelegramMediaFile:
                                            replyMedia = m
                                        default:
                                            break
                                        }
                                    }
                                    quote = EngineMessageReplyQuote(text: replyMessage.text, offset: nil, entities: messageTextEntitiesInRange(entities: replyMessage.textEntitiesAttribute?.entities ?? [], range: NSRange(location: 0, length: nsText.length), onlyQuoteable: true), media: replyMedia)
                                }
                            }
                            attributes.append(ReplyMessageAttribute(messageId: replyToMessageId.messageId, threadMessageId: threadMessageId, quote: quote, isQuote: isQuote, todoItemId: replyToMessageId.todoItemId))
                        }
                    }
```

---

## 6. Добавление «чужих» подарков в свой профиль (локально, только у вас)

**Смысл:** в профиле **другого** пользователя по долгому нажатию на уникальный подарок появляется пункт «Добавить в свой профиль (только вы увидите)». Slug подарка сохраняется в `SGSimpleSettings.customProfileGiftSlugs` и `customProfileGiftShownSlugs`; в своём профиле можно удалить запись из списка.

### Фрагмент `submodules/TelegramUI/Components/PeerInfo/PeerInfoVisualMediaPaneNode/Sources/PeerInfoGiftsPaneNode.swift`

```swift
        #if canImport(SGSimpleSettings)
        let isMyProfile = self.peerId == self.context.account.peerId
        if !isMyProfile, case let .unique(uniqueGift) = gift.gift {
            let slug = uniqueGift.slug
            let alreadyAdded = SGSimpleSettings.shared.customProfileGiftSlugs.contains(slug)
            if !alreadyAdded {
                let addTitle = presentationData.strings.baseLanguageCode == "ru" ? "Добавить в свой профиль (только вы увидите)" : "Add to my profile (only you will see)"
                items.append(.action(ContextMenuActionItem(text: addTitle, icon: { theme in generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Add"), color: theme.contextMenu.primaryColor) }, action: { [weak self] c, _ in
                    var slugs = SGSimpleSettings.shared.customProfileGiftSlugs
                    if !slugs.contains(slug) {
                        slugs.append(slug)
                        SGSimpleSettings.shared.customProfileGiftSlugs = slugs
                    }
                    var shown = SGSimpleSettings.shared.customProfileGiftShownSlugs
                    if !shown.contains(slug) {
                        shown.append(slug)
                        SGSimpleSettings.shared.customProfileGiftShownSlugs = shown
                    }
                    self?.giftsListView.triggerCustomShownRefresh()
                    c?.dismiss(completion: nil)
                })))
                items.append(.separator)
            }
        } else if isMyProfile, case let .slug(slug) = gift.reference {
            let removeTitle = presentationData.strings.baseLanguageCode == "ru" ? "Удалить из профиля" : "Remove from profile"
            items.append(.action(ContextMenuActionItem(text: removeTitle, icon: { theme in generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Delete"), color: theme.contextMenu.destructiveColor) }, action: { [weak self] _, _ in
                var slugs = SGSimpleSettings.shared.customProfileGiftSlugs
                slugs.removeAll { $0 == slug }
                SGSimpleSettings.shared.customProfileGiftSlugs = slugs
                var shown = SGSimpleSettings.shared.customProfileGiftShownSlugs
                shown.removeAll { $0 == slug }
                SGSimpleSettings.shared.customProfileGiftShownSlugs = shown
                self?.giftsListView.triggerCustomShownRefresh()
            })))
            items.append(.separator)
        }
        #endif
```

### Ключи и свойства в `LuxGram/SGSimpleSettings/Sources/SimpleSettings.swift`

```swift
        case customProfileGiftSlugs
        case customProfileGiftShownSlugs
        case pinnedCustomProfileGiftSlugs
        case localProfileGiftStatusFileId
```

```swift
    @UserDefault(key: Keys.customProfileGiftSlugs.rawValue)
    public var customProfileGiftSlugs: [String]

    /// Slugs of custom gifts that are shown on profile (worn). Persisted locally so "Show/Hide" state doesn't reset.
    @UserDefault(key: Keys.customProfileGiftShownSlugs.rawValue)
    public var customProfileGiftShownSlugs: [String]

    @UserDefault(key: Keys.pinnedCustomProfileGiftSlugs.rawValue)
    public var pinnedCustomProfileGiftSlugs: [String]

    /// When set, show this fileId as emoji status on my profile (so gift status doesn't disappear).
    @UserDefault(key: Keys.localProfileGiftStatusFileId.rawValue)
    public var localProfileGiftStatusFileId: String
```

---

*Файл: `LuxGram-features.md` в корне репозитория.*
