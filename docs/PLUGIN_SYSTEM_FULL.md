# LuxGram: полная реализация JS-плагинов (LuxGram)

Документ содержит **полные исходные тексты** всех Swift-файлов в **LuxGram**, которые относятся к системе плагинов: хуки, мост `PluginHost`, загрузчик `JavaScriptCore`, хранение в `SimpleSettings`, экраны списка/редактора/настроек плагина, строка списка плагинов, интеграция в LuxGram/SG settings.

Интеграция в **Telegram UI** (`submodules/TelegramUI`) — отдельный файл **`PLUGIN_SYSTEM_TELEGRAM_FULL.md`** (там все места, где вызываются `SGPluginHooks`, `PluginHost`, `PluginRunner`, `pluginsJavaScriptBridgeActive`).

## Оглавление (LuxGram, этот файл)

1. `LuxGram/SGSimpleSettings/Sources/LuxGramFeatures.swift`
2. `LuxGram/SGSimpleSettings/Sources/PluginHooks.swift`
3. `LuxGram/SGSimpleSettings/Sources/PluginHost.swift`
4. `LuxGram/SGSimpleSettings/Sources/SimpleSettings.swift`
5. `LuxGram/SGSettingsUI/Sources/PluginMetadata.swift`
6. `LuxGram/SGSettingsUI/Sources/PluginBridge.swift`
7. `LuxGram/SGSettingsUI/Sources/PluginBridgePythonKit.swift`
8. `LuxGram/SGSettingsUI/Sources/ItemListPluginRowItem.swift`
9. `LuxGram/SGSettingsUI/Sources/PluginListController.swift`
10. `LuxGram/SGSettingsUI/Sources/PluginCodeEditorController.swift`
11. `LuxGram/SGSettingsUI/Sources/PluginInstallPopupController.swift`
12. `LuxGram/SGSettingsUI/Sources/PluginSettingsController.swift`
13. `LuxGram/SGSettingsUI/Sources/PluginRunner.swift`
14. `LuxGram/SGSettingsUI/Sources/LuxGramSettingsController.swift`
15. `LuxGram/SGSettingsUI/Sources/SGSettingsController.swift`

---

## Полные файлы



### `LuxGram/SGSimpleSettings/Sources/LuxGramFeatures.swift`

```swift
import Foundation

/// Глобальные флаги функций LuxGram (LuxGram).
public enum LuxGramFeatures {
    /// Мастер-переключатель JS-плагинов отключён: без `PluginRunner`, без хуков в чате (меньше нагрузка и зависаний).
    public static let pluginsEnabled = true
}

```

### `LuxGram/SGSimpleSettings/Sources/PluginHooks.swift`

```swift
// MARK: LuxGram – Plugin hooks (simplified, Ghostgram-style API)
import Foundation

// MARK: - Outgoing message intercept

public enum SGPluginHookStrategy: String, Codable, Sendable {
    case passthrough
    case modify
    case cancel
}

public struct SGPluginHookResult: Codable, Sendable, Equatable {
    public var strategy: SGPluginHookStrategy
    public var message: String?

    public init(strategy: SGPluginHookStrategy = .passthrough, message: String? = nil) {
        self.strategy = strategy
        self.message = message
    }
}

/// Runner for outgoing message intercept: (accountPeerId, peerId, text, replyToMessageId?) → result
public typealias PluginMessageHookRunner = (Int64, Int64, String, Int64?) -> SGPluginHookResult?

/// Runner for incoming message notification: (accountId, peerId, messageId, text?, outgoing)
public typealias PluginIncomingMessageRunner = (Int64, Int64, Int64, String?, Bool) -> Void

// MARK: - Context menu items

public struct PluginChatMenuItem: Sendable {
    public let title: String
    public let action: @Sendable () -> Void

    public init(title: String, action: @escaping @Sendable () -> Void) {
        self.title = title
        self.action = action
    }
}

// MARK: - Notification names

/// Posted by TelegramCore on new message (userInfo: accountId, peerId, messageId, text, outgoing).
public let SGPluginIncomingMessageNotificationName = Notification.Name("SGPluginIncomingMessage")

/// Universal technical event (userInfo: eventName: String, params: [String: Any]).
public let SGPluginTechnicalEventNotificationName = Notification.Name("SGPluginTechnicalEvent")

// MARK: - Hook providers

/// All plugin hooks — set by PluginRunner, called by TelegramUI.
public enum SGPluginHooks {
    // Intercept
    public static var messageHookRunner: PluginMessageHookRunner?
    public static var didSendMessageRunner: ((Int64, Int64, String) -> Void)?
    public static var incomingMessageHookRunner: PluginIncomingMessageRunner?

    // Context menus
    public static var chatMenuItemsProvider: ((Int64, Int64, Int64?) -> [PluginChatMenuItem])?
    public static var profileMenuItemsProvider: ((Int64, Int64) -> [PluginChatMenuItem])?

    // Navigation
    public static var willOpenChatRunner: ((Int64, Int64) -> Void)?
    public static var willOpenProfileRunner: ((Int64, Int64) -> Void)?

    // URL
    public static var openUrlRunner: ((String) -> Bool)?

    // Message filtering
    public static var shouldShowMessageRunner: ((Int64, Int64, Int64, String?, Bool) -> Bool)?
    public static var shouldShowGiftButtonRunner: ((Int64, Int64) -> Bool)?

    // User display (Fake Profile)
    public static var userDisplayRunner: PluginUserDisplayRunner?

    // Events
    public static var eventRunner: ((String, [String: Any]) -> [String: Any]?)?

    // MARK: - Convenience

    public static func applyOutgoingMessageTextHooks(
        accountPeerId: Int64,
        peerId: Int64,
        text: String,
        replyToMessageId: Int64? = nil
    ) -> SGPluginHookResult {
        guard let runner = messageHookRunner else { return SGPluginHookResult() }
        return runner(accountPeerId, peerId, text, replyToMessageId) ?? SGPluginHookResult()
    }

    public static func applyOpenUrlHook(url: String) -> Bool {
        return openUrlRunner?(url) ?? false
    }

    public static func applyShouldShowMessageHook(accountId: Int64, peerId: Int64, messageId: Int64, text: String?, outgoing: Bool) -> Bool {
        return shouldShowMessageRunner?(accountId, peerId, messageId, text, outgoing) ?? true
    }

    public static func applyShouldShowGiftButtonHook(accountId: Int64, peerId: Int64) -> Bool {
        return shouldShowGiftButtonRunner?(accountId, peerId) ?? true
    }

    public static func emitEvent(_ name: String, _ params: [String: Any]) -> [String: Any]? {
        return eventRunner?(name, params)
    }
}

// MARK: - User display (kept for Fake Profile compatibility)

public struct PluginDisplayUser: Equatable, Sendable {
    public var firstName: String
    public var lastName: String
    public var username: String?
    public var phone: String?
    public var id: Int64
    public var isPremium: Bool
    public var isVerified: Bool
    public var isScam: Bool
    public var isFake: Bool
    public var isSupport: Bool
    public var isBot: Bool

    public init(firstName: String, lastName: String, username: String?, phone: String?, id: Int64, isPremium: Bool, isVerified: Bool, isScam: Bool, isFake: Bool, isSupport: Bool, isBot: Bool) {
        self.firstName = firstName
        self.lastName = lastName
        self.username = username
        self.phone = phone
        self.id = id
        self.isPremium = isPremium
        self.isVerified = isVerified
        self.isScam = isScam
        self.isFake = isFake
        self.isSupport = isSupport
        self.isBot = isBot
    }
}

public typealias PluginUserDisplayRunner = (Int64, PluginDisplayUser) -> PluginDisplayUser?

// MARK: - ReplyMessageInfo (kept for hook compatibility)

public struct ReplyMessageInfo: Sendable {
    public let messageId: Int64
    public let isDocument: Bool
    public let filePath: String?
    public let fileName: String?
    public let mimeType: String?

    public init(messageId: Int64, isDocument: Bool, filePath: String?, fileName: String?, mimeType: String?) {
        self.messageId = messageId
        self.isDocument = isDocument
        self.filePath = filePath
        self.fileName = fileName
        self.mimeType = mimeType
    }
}

```

### `LuxGram/SGSimpleSettings/Sources/PluginHost.swift`

```swift
// MARK: LuxGram – Plugin host (callbacks from plugins into iOS UI)
// Ghostgram-style API: LuxGram.ui, LuxGram.compose, LuxGram.chat, LuxGram.network, etc.

import Foundation

/// Toast/bulletin type.
public enum PluginBulletinType {
    case info
    case error
    case success
}

/// Host callbacks set by app so plugins can interact with UI and Telegram.
public final class PluginHost {
    public static let shared = PluginHost()

    // MARK: - LuxGram.ui

    /// Show alert (title, message).
    public var showAlert: ((String, String) -> Void)?

    /// Show prompt with text field (title, placeholder, callback with entered text or nil if cancelled).
    public var showPrompt: ((String, String, @escaping (String?) -> Void) -> Void)?

    /// Show confirm dialog OK/Cancel. Callback: true = OK, false = Cancel.
    public var showConfirm: ((String, String, @escaping (Bool) -> Void) -> Void)?

    /// Copy text to system clipboard.
    public var copyToClipboard: ((String) -> Void)?

    /// Show system share sheet for text.
    public var shareText: ((String) -> Void)?

    /// Haptic feedback: "success", "warning", "error", "light", "medium", "heavy".
    public var haptic: ((String) -> Void)?

    /// Open URL in browser or Telegram.
    public var openURL: ((String) -> Void)?

    /// Show toast/bulletin.
    public var showBulletin: ((String, PluginBulletinType) -> Void)?

    /// Simple toast (falls back to bulletin with .info).
    public var showToast: ((String) -> Void)?

    // MARK: - LuxGram.compose

    /// Get text from current chat input field.
    public var getInputText: (() -> String)?

    /// Set text in current chat input field.
    public var setInputText: ((String) -> Void)?

    /// Insert text at cursor position in current chat input field.
    public var insertText: ((String) -> Void)?

    /// Send current input message.
    public var sendInputMessage: (() -> Void)?

    /// Register callback for message submit (called before sending).
    public var onSubmitCallback: ((@escaping (String) -> Void) -> Void)?

    // MARK: - LuxGram.chat

    /// Returns (accountId, peerId) of currently open chat, or nil.
    public var getCurrentChat: (() -> (accountId: Int64, peerId: Int64)?)?

    /// Send message: (accountPeerId, peerId, text, replyToMessageId?, filePath?).
    public var sendMessage: ((Int64, Int64, String, Int64?, String?) -> Void)?

    /// Open chat by peerId.
    public var openChat: ((Int64) -> Void)?

    /// Edit message: (accountId, peerId, messageId, newText).
    public var editMessage: ((Int64, Int64, Int64, String) -> Void)?

    /// Delete message: (accountId, peerId, messageId).
    public var deleteMessage: ((Int64, Int64, Int64) -> Void)?

    // MARK: - LuxGram.network

    /// Fetch URL: (url, method, headers, body, callback(error?, responseString?)).
    public var fetch: ((String, String, [String: String]?, String?, @escaping (String?, String?) -> Void) -> Void)?

    // MARK: - Threading

    public var runOnMain: ((@escaping () -> Void) -> Void)?
    public var runOnBackground: ((@escaping () -> Void) -> Void)?

    // MARK: - LuxGram.settings (per-plugin storage)

    private let pluginSettingsPrefix = "sg_plugin_"

    public func getPluginSetting(pluginId: String, key: String) -> String? {
        let k = "\(pluginSettingsPrefix)\(pluginId)_\(key)"
        return UserDefaults.standard.string(forKey: k)
    }

    public func getPluginSettingBool(pluginId: String, key: String, default defaultValue: Bool) -> Bool {
        guard let s = getPluginSetting(pluginId: pluginId, key: key) else { return defaultValue }
        return s == "1" || s.lowercased() == "true"
    }

    public func setPluginSetting(pluginId: String, key: String, value: String) {
        UserDefaults.standard.set(value, forKey: "\(pluginSettingsPrefix)\(pluginId)_\(key)")
    }

    public func setPluginSettingBool(pluginId: String, key: String, value: Bool) {
        setPluginSetting(pluginId: pluginId, key: key, value: value ? "1" : "0")
    }

    /// Temp directory for a plugin.
    public func getPluginTempDirectory(pluginId: String) -> String {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Plugins", isDirectory: true)
            .appendingPathComponent(pluginId, isDirectory: true).path ?? NSTemporaryDirectory()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {
        runOnMain = { block in DispatchQueue.main.async(execute: block) }
        runOnBackground = { block in DispatchQueue.global(qos: .userInitiated).async(execute: block) }

        // Default fetch implementation using URLSession
        fetch = { url, method, headers, body, callback in
            guard let requestURL = URL(string: url) else {
                callback("Invalid URL", nil)
                return
            }
            var request = URLRequest(url: requestURL, timeoutInterval: 30)
            request.httpMethod = method.isEmpty ? "GET" : method.uppercased()
            if let headers = headers {
                for (key, value) in headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }
            if let body = body, !body.isEmpty {
                request.httpBody = body.data(using: .utf8)
            }
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    DispatchQueue.main.async { callback(error.localizedDescription, nil) }
                    return
                }
                let responseString = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                DispatchQueue.main.async { callback(nil, responseString) }
            }.resume()
        }

        // Default haptic implementation
        haptic = { style in
            DispatchQueue.main.async {
                switch style {
                case "success":
                    let gen = UINotificationFeedbackGenerator()
                    gen.notificationOccurred(.success)
                case "warning":
                    let gen = UINotificationFeedbackGenerator()
                    gen.notificationOccurred(.warning)
                case "error":
                    let gen = UINotificationFeedbackGenerator()
                    gen.notificationOccurred(.error)
                case "heavy":
                    let gen = UIImpactFeedbackGenerator(style: .heavy)
                    gen.impactOccurred()
                case "medium":
                    let gen = UIImpactFeedbackGenerator(style: .medium)
                    gen.impactOccurred()
                default:
                    let gen = UIImpactFeedbackGenerator(style: .light)
                    gen.impactOccurred()
                }
            }
        }
    }
}

// UIKit import for haptic generators
import UIKit

```

### `LuxGram/SGSimpleSettings/Sources/SimpleSettings.swift`

```swift
import Foundation
import SGAppGroupIdentifier
import SGLogging

let APP_GROUP_IDENTIFIER = sgAppGroupIdentifier()

/// Lightweight file-backed key-value store (replaces NSUserDefaults for sensitive keys).
private class SGFileStore {
    static let shared = SGFileStore()

    private var data: [String: Any] = [:]
    private let filePath: String
    private let lock = NSLock()

    private init() {
        let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()
        filePath = docs + "/sg_private_settings.plist"
        if let dict = NSDictionary(contentsOfFile: filePath) as? [String: Any] {
            data = dict
        }
    }

    func double(forKey key: String, default defaultValue: Double) -> Double {
        lock.lock()
        defer { lock.unlock() }
        return data[key] as? Double ?? defaultValue
    }

    func int32(forKey key: String, default defaultValue: Int32) -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        if let v = data[key] as? Int { return Int32(v) }
        if let v = data[key] as? Int32 { return v }
        return defaultValue
    }

    func set(_ value: Any, forKey key: String) {
        lock.lock()
        data[key] = value
        (data as NSDictionary).write(toFile: filePath, atomically: true)
        lock.unlock()
    }
}

public class SGSimpleSettings {
    
    public static let shared = SGSimpleSettings()
    
    /// When > 0, outgoing message read receipts are sent even if ghost mode (`disableMessageReadReceipt`) is enabled.
    private static let outgoingMessageReadReceiptBypassLock = NSLock()
    private static var outgoingMessageReadReceiptBypassDepth: Int = 0
    /// Read-state sync runs after the interactive transaction; allow pushes for a short window after user-triggered read.
    private static var readReceiptBypassUntilTimestamp: CFTimeInterval = 0
    
    /// True while ``performWithOutgoingMessageReadReceiptsAllowed(_:)`` is running (e.g. user chose «Read» or replied).
    public static var isOutgoingMessageReadReceiptBypassActive: Bool {
        outgoingMessageReadReceiptBypassLock.lock()
        defer { outgoingMessageReadReceiptBypassLock.unlock() }
        return outgoingMessageReadReceiptBypassDepth > 0
    }
    
    /// True shortly after a user explicitly allowed read receipts (covers async `SynchronizePeerReadState`).
    public static var isOutgoingReadReceiptTimeBypassActive: Bool {
        outgoingMessageReadReceiptBypassLock.lock()
        defer { outgoingMessageReadReceiptBypassLock.unlock() }
        return CFAbsoluteTimeGetCurrent() < readReceiptBypassUntilTimestamp
    }
    
    /// Extends the time window during which read receipts may be sent despite ghost mode.
    public static func extendOutgoingReadReceiptBypassTimeWindow(seconds: CFTimeInterval = 8.0) {
        outgoingMessageReadReceiptBypassLock.lock()
        let until = CFAbsoluteTimeGetCurrent() + seconds
        if until > readReceiptBypassUntilTimestamp {
            readReceiptBypassUntilTimestamp = until
        }
        outgoingMessageReadReceiptBypassLock.unlock()
    }
    
    /// Run `body` while allowing read receipts to be pushed to the server.
    public static func performWithOutgoingMessageReadReceiptsAllowed(_ body: () -> Void) {
        extendOutgoingReadReceiptBypassTimeWindow(seconds: 8.0)
        outgoingMessageReadReceiptBypassLock.lock()
        outgoingMessageReadReceiptBypassDepth += 1
        outgoingMessageReadReceiptBypassLock.unlock()
        defer {
            outgoingMessageReadReceiptBypassLock.lock()
            outgoingMessageReadReceiptBypassDepth -= 1
            outgoingMessageReadReceiptBypassLock.unlock()
        }
        body()
    }
    
    /// Combined bypass used by TelegramCore when ghost mode blocks read receipts.
    public static var allowsOutgoingMessageReadReceiptDespiteGhostMode: Bool {
        isOutgoingMessageReadReceiptBypassActive || isOutgoingReadReceiptTimeBypassActive
    }
    
    private init() {
        setDefaultValues()
        migrate()
        preCacheValues()
    }
    
    private func setDefaultValues() {
        UserDefaults.standard.register(defaults: SGSimpleSettings.defaultValues)
        // Just in case group defaults will be nil
        UserDefaults.standard.register(defaults: SGSimpleSettings.groupDefaultValues)
        if let groupUserDefaults = UserDefaults(suiteName: APP_GROUP_IDENTIFIER) {
            groupUserDefaults.register(defaults: SGSimpleSettings.groupDefaultValues)
        }
    }
    
    private func migrate() {
        let showRepostToStoryMigrationKey = "migrated_\(Keys.showRepostToStory.rawValue)"
        if let groupUserDefaults = UserDefaults(suiteName: APP_GROUP_IDENTIFIER) {
            if !groupUserDefaults.bool(forKey: showRepostToStoryMigrationKey) {
                self.showRepostToStoryV2 = self.showRepostToStory
                groupUserDefaults.set(true, forKey: showRepostToStoryMigrationKey)
                SGLogger.shared.log("SGSimpleSettings", "Migrated showRepostToStory. \(self.showRepostToStory) -> \(self.showRepostToStoryV2)")
            }
        } else {
            SGLogger.shared.log("SGSimpleSettings", "Unable to migrate showRepostToStory. Shared UserDefaults suite is not available for '\(APP_GROUP_IDENTIFIER)'.")
        }
        
        // MARK: AppBadge default migration
        // Older builds used an empty value which resulted in the classic badge being shown.
        if self.customAppBadge.isEmpty || self.customAppBadge == "Components/AppBadge" {
            self.customAppBadge = "SkyAppBadge"
        }
    }
    
    private func preCacheValues() {
        // let dispatchGroup = DispatchGroup()

        let tasks = [
//            { let _ = self.allChatsFolderPositionOverride },
            { let _ = self.tabBarSearchEnabled },
            { let _ = self.allChatsHidden },
            { let _ = self.hideTabBar },
            { let _ = self.bottomTabStyle },
            { let _ = self.compactChatList },
            { let _ = self.compactFolderNames },
            { let _ = self.disableSwipeToRecordStory },
            { let _ = self.rememberLastFolder },
            { let _ = self.quickTranslateButton },
            { let _ = self.stickerSize },
            { let _ = self.stickerTimestamp },
            { let _ = self.disableGalleryCamera },
            { let _ = self.disableSendAsButton },
            { let _ = self.disableSnapDeletionEffect },
            { let _ = self.startTelescopeWithRearCam },
            { let _ = self.hideRecordingButton },
            { let _ = self.inputToolbar },
            { let _ = self.dismissedSGSuggestions },
            { let _ = self.customAppBadge }
        ]

        tasks.forEach { task in
            DispatchQueue.global(qos: .background).async(/*group: dispatchGroup*/) {
                task()
            }
        }

        // dispatchGroup.notify(queue: DispatchQueue.main) {}
    }
    
    public func synchronizeShared() {
        if let groupUserDefaults = UserDefaults(suiteName: APP_GROUP_IDENTIFIER) {
            groupUserDefaults.synchronize()
        }
    }
    
    public enum Keys: String, CaseIterable {
        case hidePhoneInSettings
        case showTabNames
        case startTelescopeWithRearCam
        case accountColorsSaturation
        case uploadSpeedBoost
        case downloadSpeedBoost
        case bottomTabStyle
        case rememberLastFolder
        case lastAccountFolders
        case localDNSForProxyHost
        case sendLargePhotos
        case outgoingPhotoQuality
        case storyStealthMode
        case canUseStealthMode
        case disableSwipeToRecordStory
        case quickTranslateButton
        case outgoingLanguageTranslation
        case showRepostToStory
        case showRepostToStoryV2
        case contextShowSelectFromUser
        case contextShowSaveToCloud
        case contextShowRestrict
        // case contextShowBan
        case contextShowHideForwardName
        case contextShowReport
        case contextShowReply
        case contextShowPin
        case contextShowSaveMedia
        case contextShowMessageReplies
        case contextShowJson
        case disableScrollToNextChannel
        case disableScrollToNextTopic
        case disableChatSwipeOptions
        case disableDeleteChatSwipeOption
        case disableGalleryCamera
        case disableGalleryCameraPreview
        case disableSendAsButton
        case disableSnapDeletionEffect
        case stickerSize
        case stickerTimestamp
        case hideRecordingButton
        case hideTabBar
        case showDC
        case showCreationDate
        case showRegDate
        case regDateCache
        case compactChatList
        case compactFolderNames
        case allChatsTitleLengthOverride
//        case allChatsFolderPositionOverride
        case allChatsHidden
        case defaultEmojisFirst
        case messageDoubleTapActionOutgoing
        case wideChannelPosts
        case forceEmojiTab
        case forceBuiltInMic
        case secondsInMessages
        case hideChannelBottomButton
        case forceSystemSharing
        case confirmCalls
        case videoPIPSwipeDirection
        case legacyNotificationsFix
        case messageFilterKeywords
        case inputToolbar
        case pinnedMessageNotifications
        case mentionsAndRepliesNotifications
        case primaryUserId
        case status
        case dismissedSGSuggestions
        case duckyAppIconAvailable
        case transcriptionBackend
        case translationBackend
        case customAppBadge
        case canUseNY
        case nyStyle
        case wideTabBar
        case tabBarSearchEnabled
        case showDeletedMessages
        case saveEditHistory
        // MARK: Saved Deleted Messages (AyuGram-style)
        case saveDeletedMessagesMedia
        case saveDeletedMessagesReactions
        case saveDeletedMessagesForBots
        // Ghost Mode settings
        case ghostModeMessageSendDelaySeconds
        case disableOnlineStatus
        case disableTypingStatus
        case disableRecordingVideoStatus
        case disableUploadingVideoStatus
        case disableVCMessageRecordingStatus
        case disableVCMessageUploadingStatus
        case disableUploadingPhotoStatus
        case disableUploadingFileStatus
        case disableChoosingLocationStatus
        case disableChoosingContactStatus
        case disablePlayingGameStatus
        case disableRecordingRoundVideoStatus
        case disableUploadingRoundVideoStatus
        case disableSpeakingInGroupCallStatus
        case disableChoosingStickerStatus
        case disableEmojiInteractionStatus
        case disableEmojiAcknowledgementStatus
        case disableMessageReadReceipt
        /// When message read receipts are hidden (ghost): if true, replying to an incoming message marks it read on the server.
        case ghostModeMarkReadOnReply
        case disableStoryReadReceipt
        case disableAllAds
        case hideProxySponsor
        case enableSavingProtectedContent
        case forwardRestrictedAsCopy
        case disableScreenshotDetection
        case enableSavingSelfDestructingMessages
        case disableSecretChatBlurOnScreenshot
        case doubleBottomEnabled
        case enableLocalPremium
        case scrollToTopButtonEnabled
        case fakeLocationEnabled
        case enableVideoToCircleOrVoice
        case userProfileNotes
        case enableTelescope
        // Font replacement (A-Font style)
        case enableFontReplacement
        case fontReplacementName
        case fontReplacementBoldName
        case fontReplacementFilePath
        case fontReplacementBoldFilePath
        case enableLocalMessageEditing
        case disableCompactNumbers
        case disableZalgoText
        // Оформление
        case unlimitedFavoriteStickers
        // Запись времени в сети
        case enableOnlineStatusRecording
        case onlineStatusRecordingIntervalMinutes
        case savedOnlineStatusByPeerId
        case addMusicFromDeviceToProfile
        case hideReactions
        case pluginSystemEnabled
        case installedPluginsJson
        case chatExportEnabled
        case profileCoverMediaPath
        case profileCoverIsVideo
        case emojiDownloaderEnabled
        case feelRichEnabled
        case feelRichStarsAmount
        case giftIdEnabled
        case fakeProfileEnabled
        case fakeProfileTargetUserId
        case fakeProfileFirstName
        case fakeProfileLastName
        case fakeProfileUsername
        case fakeProfilePhone
        case fakeProfileId
        case fakeProfilePremium
        case fakeProfileVerified
        case fakeProfileScam
        case fakeProfileFake
        case fakeProfileSupport
        case fakeProfileBot
        case currentAccountPeerId
        case customProfileGiftSlugs
        case customProfileGiftShownSlugs
        case pinnedCustomProfileGiftSlugs
        case localProfileGiftStatusFileId
        case hookInspectorEnabled
        /// Square ↔ circle avatar rounding (LuxGram appearance).
        case customAvatarRoundingEnabled
        case avatarRoundingPercent
        /// Title for self-chat (Saved / My notes): default | displayName | username | custom
        case selfChatTitleMode
        case selfChatTitleCustomText
        /// Face blur in video messages (Vision framework).
        case faceBlurInVideoMessages
        /// Experimental: Puter-style voice conversion (see LuxGram Privacy). Processing not wired to send/calls in this build.
        case voiceChangerEnabled
        case puterVoiceChangerVoiceId
    }
    
    public enum DownloadSpeedBoostValues: String, CaseIterable {
        case none
        case medium
        case maximum
    }
    
    public enum BottomTabStyleValues: String, CaseIterable {
        case telegram
        case ios
    }
    
    public enum AllChatsTitleLengthOverride: String, CaseIterable {
        case none
        case short
        case long
    }
    
    public enum AllChatsFolderPositionOverride: String, CaseIterable {
        case none
        case last
        case hidden
    }
    
    public enum MessageDoubleTapAction: String, CaseIterable {
        case `default`
        case none
        case edit
    }
    
    public enum VideoPIPSwipeDirection: String, CaseIterable {
        case up
        case down
        case none
    }

    public enum TranscriptionBackend: String, CaseIterable {
        case `default`
        case apple
    }

    public enum TranslationBackend: String, CaseIterable {
        case `default`
        case gtranslate
        case system
        // Make sure to update TranslationConfiguration
    }
        
    public enum PinnedMessageNotificationsSettings: String, CaseIterable {
        case `default`
        case silenced
        case disabled
    }
    
    public enum MentionsAndRepliesNotificationsSettings: String, CaseIterable {
        case `default`
        case silenced
        case disabled
    }

    public enum NYStyle: String, CaseIterable {
        case `default`
        case snow
        case lightning
    }
    
    public static let defaultValues: [String: Any] = [
        Keys.hidePhoneInSettings.rawValue: true,
        Keys.showTabNames.rawValue: true,
        Keys.startTelescopeWithRearCam.rawValue: false,
        Keys.accountColorsSaturation.rawValue: 100,
        Keys.uploadSpeedBoost.rawValue: false,
        Keys.downloadSpeedBoost.rawValue: DownloadSpeedBoostValues.none.rawValue,
        Keys.rememberLastFolder.rawValue: false,
        Keys.bottomTabStyle.rawValue: BottomTabStyleValues.telegram.rawValue,
        Keys.lastAccountFolders.rawValue: [:],
        Keys.localDNSForProxyHost.rawValue: false,
        Keys.sendLargePhotos.rawValue: false,
        Keys.outgoingPhotoQuality.rawValue: 70,
        Keys.storyStealthMode.rawValue: false,
        Keys.canUseStealthMode.rawValue: true,
        Keys.disableSwipeToRecordStory.rawValue: false,
        Keys.quickTranslateButton.rawValue: false,
        Keys.outgoingLanguageTranslation.rawValue: [:],
        Keys.showRepostToStory.rawValue: true,
        Keys.contextShowSelectFromUser.rawValue: true,
        Keys.contextShowSaveToCloud.rawValue: true,
        Keys.contextShowRestrict.rawValue: true,
        // Keys.contextShowBan.rawValue: true,
        Keys.contextShowHideForwardName.rawValue: true,
        Keys.contextShowReport.rawValue: true,
        Keys.contextShowReply.rawValue: true,
        Keys.contextShowPin.rawValue: true,
        Keys.contextShowSaveMedia.rawValue: true,
        Keys.contextShowMessageReplies.rawValue: true,
        Keys.contextShowJson.rawValue: false,
        Keys.disableScrollToNextChannel.rawValue: false,
        Keys.disableScrollToNextTopic.rawValue: false,
        Keys.disableChatSwipeOptions.rawValue: false,
        Keys.disableDeleteChatSwipeOption.rawValue: false,
        Keys.disableGalleryCamera.rawValue: false,
        Keys.disableGalleryCameraPreview.rawValue: false,
        Keys.disableSendAsButton.rawValue: false,
        Keys.disableSnapDeletionEffect.rawValue: false,
        Keys.stickerSize.rawValue: 100,
        Keys.stickerTimestamp.rawValue: true,
        Keys.hideRecordingButton.rawValue: false,
        Keys.hideTabBar.rawValue: false,
        Keys.showDC.rawValue: false,
        Keys.showCreationDate.rawValue: true,
        Keys.showRegDate.rawValue: true,
        Keys.regDateCache.rawValue: [:],
        Keys.compactChatList.rawValue: false,
        Keys.compactFolderNames.rawValue: false,
        Keys.allChatsTitleLengthOverride.rawValue: AllChatsTitleLengthOverride.none.rawValue,
//        Keys.allChatsFolderPositionOverride.rawValue: AllChatsFolderPositionOverride.none.rawValue
        Keys.allChatsHidden.rawValue: false,
        Keys.defaultEmojisFirst.rawValue: false,
        Keys.messageDoubleTapActionOutgoing.rawValue: MessageDoubleTapAction.default.rawValue,
        Keys.wideChannelPosts.rawValue: false,
        Keys.forceEmojiTab.rawValue: false,
        Keys.hideChannelBottomButton.rawValue: false,
        Keys.secondsInMessages.rawValue: false,
        Keys.forceSystemSharing.rawValue: false,
        Keys.confirmCalls.rawValue: true,
        Keys.videoPIPSwipeDirection.rawValue: VideoPIPSwipeDirection.up.rawValue,
        Keys.messageFilterKeywords.rawValue: [],
        Keys.inputToolbar.rawValue: false,
        Keys.primaryUserId.rawValue: "",
        Keys.dismissedSGSuggestions.rawValue: [],
        Keys.duckyAppIconAvailable.rawValue: true,
        Keys.transcriptionBackend.rawValue: TranscriptionBackend.default.rawValue,
        Keys.translationBackend.rawValue: TranslationBackend.default.rawValue,
        // Default app badge (LuxGram Dark Purple)
        Keys.customAppBadge.rawValue: "SkyAppBadge",
        Keys.canUseNY.rawValue: false,
        Keys.nyStyle.rawValue: NYStyle.default.rawValue,
        Keys.wideTabBar.rawValue: false,
        Keys.tabBarSearchEnabled.rawValue: true,
        Keys.showDeletedMessages.rawValue: true,
        Keys.saveEditHistory.rawValue: true,
        // Saved Deleted Messages defaults (AyuGram-style)
        Keys.saveDeletedMessagesMedia.rawValue: true,
        Keys.saveDeletedMessagesReactions.rawValue: true,
        Keys.saveDeletedMessagesForBots.rawValue: true,
        // Ghost Mode defaults
        Keys.ghostModeMessageSendDelaySeconds.rawValue: 0,
        Keys.disableOnlineStatus.rawValue: false,
        Keys.disableTypingStatus.rawValue: false,
        Keys.disableRecordingVideoStatus.rawValue: false,
        Keys.disableUploadingVideoStatus.rawValue: false,
        Keys.disableVCMessageRecordingStatus.rawValue: false,
        Keys.disableVCMessageUploadingStatus.rawValue: false,
        Keys.disableUploadingPhotoStatus.rawValue: false,
        Keys.disableUploadingFileStatus.rawValue: false,
        Keys.disableChoosingLocationStatus.rawValue: false,
        Keys.disableChoosingContactStatus.rawValue: false,
        Keys.disablePlayingGameStatus.rawValue: false,
        Keys.disableRecordingRoundVideoStatus.rawValue: false,
        Keys.disableUploadingRoundVideoStatus.rawValue: false,
        Keys.disableSpeakingInGroupCallStatus.rawValue: false,
        Keys.disableChoosingStickerStatus.rawValue: false,
        Keys.disableEmojiInteractionStatus.rawValue: false,
        Keys.disableEmojiAcknowledgementStatus.rawValue: false,
        Keys.disableMessageReadReceipt.rawValue: false,
        Keys.ghostModeMarkReadOnReply.rawValue: true,
        Keys.disableStoryReadReceipt.rawValue: false,
        Keys.disableAllAds.rawValue: false,
        Keys.hideProxySponsor.rawValue: false,
        Keys.enableSavingProtectedContent.rawValue: false,
        Keys.disableScreenshotDetection.rawValue: false,
        Keys.enableSavingSelfDestructingMessages.rawValue: false,
        Keys.disableSecretChatBlurOnScreenshot.rawValue: false,
        Keys.doubleBottomEnabled.rawValue: false,
        Keys.enableLocalPremium.rawValue: false,
        Keys.scrollToTopButtonEnabled.rawValue: true,
        Keys.fakeLocationEnabled.rawValue: false,
        Keys.enableVideoToCircleOrVoice.rawValue: false,
        Keys.userProfileNotes.rawValue: [:],
        Keys.enableTelescope.rawValue: false,
        Keys.enableFontReplacement.rawValue: false,
        Keys.fontReplacementName.rawValue: "",
        Keys.fontReplacementBoldName.rawValue: "",
        Keys.fontReplacementFilePath.rawValue: "",
        Keys.fontReplacementBoldFilePath.rawValue: "",
        Keys.enableLocalMessageEditing.rawValue: false,
        Keys.disableCompactNumbers.rawValue: false,
        Keys.disableZalgoText.rawValue: false,
        Keys.unlimitedFavoriteStickers.rawValue: true,
        Keys.enableOnlineStatusRecording.rawValue: false,
        Keys.onlineStatusRecordingIntervalMinutes.rawValue: 5,
        Keys.savedOnlineStatusByPeerId.rawValue: "{}",
        Keys.addMusicFromDeviceToProfile.rawValue: false,
        Keys.hideReactions.rawValue: false,
        Keys.pluginSystemEnabled.rawValue: false,
        Keys.installedPluginsJson.rawValue: "[]",
        Keys.chatExportEnabled.rawValue: false,
        Keys.profileCoverMediaPath.rawValue: "",
        Keys.profileCoverIsVideo.rawValue: false,
        Keys.emojiDownloaderEnabled.rawValue: false,
        Keys.feelRichEnabled.rawValue: false,
        Keys.feelRichStarsAmount.rawValue: "1000",
        Keys.giftIdEnabled.rawValue: false,
        Keys.fakeProfileEnabled.rawValue: false,
        Keys.fakeProfileTargetUserId.rawValue: "",
        Keys.fakeProfileFirstName.rawValue: "",
        Keys.fakeProfileLastName.rawValue: "",
        Keys.fakeProfileUsername.rawValue: "",
        Keys.fakeProfilePhone.rawValue: "",
        Keys.fakeProfileId.rawValue: "",
        Keys.fakeProfilePremium.rawValue: false,
        Keys.fakeProfileVerified.rawValue: false,
        Keys.fakeProfileScam.rawValue: false,
        Keys.fakeProfileFake.rawValue: false,
        Keys.fakeProfileSupport.rawValue: false,
        Keys.fakeProfileBot.rawValue: false,
        Keys.currentAccountPeerId.rawValue: "",
        Keys.customProfileGiftSlugs.rawValue: [],
        Keys.customProfileGiftShownSlugs.rawValue: [],
        Keys.pinnedCustomProfileGiftSlugs.rawValue: [],
        Keys.localProfileGiftStatusFileId.rawValue: "",
        Keys.hookInspectorEnabled.rawValue: false,
        Keys.customAvatarRoundingEnabled.rawValue: false,
        Keys.avatarRoundingPercent.rawValue: Int32(0),
        Keys.selfChatTitleMode.rawValue: "default",
        Keys.selfChatTitleCustomText.rawValue: "",
        Keys.voiceChangerEnabled.rawValue: false,
        Keys.puterVoiceChangerVoiceId.rawValue: "21m00Tcm4TlvDq8ikWAM"
    ]
    
    public static let groupDefaultValues: [String: Any] = [
        Keys.legacyNotificationsFix.rawValue: false,
        Keys.pinnedMessageNotifications.rawValue: PinnedMessageNotificationsSettings.default.rawValue,
        Keys.mentionsAndRepliesNotifications.rawValue: MentionsAndRepliesNotificationsSettings.default.rawValue,
        Keys.status.rawValue: 1,
        Keys.showRepostToStoryV2.rawValue: true,
    ]
    
    @UserDefault(key: Keys.hidePhoneInSettings.rawValue)
    public var hidePhoneInSettings: Bool
    
    @UserDefault(key: Keys.showTabNames.rawValue)
    public var showTabNames: Bool
    
    @UserDefault(key: Keys.startTelescopeWithRearCam.rawValue)
    public var startTelescopeWithRearCam: Bool
    
    @UserDefault(key: Keys.accountColorsSaturation.rawValue)
    public var accountColorsSaturation: Int32
    
    @UserDefault(key: Keys.uploadSpeedBoost.rawValue)
    public var uploadSpeedBoost: Bool
    
    @UserDefault(key: Keys.downloadSpeedBoost.rawValue)
    public var downloadSpeedBoost: String
    
    @UserDefault(key: Keys.rememberLastFolder.rawValue)
    public var rememberLastFolder: Bool
    
    // Disabled while Telegram is migrating to Glass
    // @UserDefault(key: Keys.bottomTabStyle.rawValue)
    public var bottomTabStyle: String {
        set {}
        get {
            return BottomTabStyleValues.ios.rawValue
        }
    }
    
    public var lastAccountFolders = UserDefaultsBackedDictionary<String, Int32>(userDefaultsKey: Keys.lastAccountFolders.rawValue, threadSafe: false)
    
    @UserDefault(key: Keys.localDNSForProxyHost.rawValue)
    public var localDNSForProxyHost: Bool
    
    @UserDefault(key: Keys.sendLargePhotos.rawValue)
    public var sendLargePhotos: Bool
    
    @UserDefault(key: Keys.outgoingPhotoQuality.rawValue)
    public var outgoingPhotoQuality: Int32
    
    @UserDefault(key: Keys.storyStealthMode.rawValue)
    public var storyStealthMode: Bool
    
    @UserDefault(key: Keys.canUseStealthMode.rawValue)
    public var canUseStealthMode: Bool    
    
    @UserDefault(key: Keys.disableSwipeToRecordStory.rawValue)
    public var disableSwipeToRecordStory: Bool   
    
    @UserDefault(key: Keys.quickTranslateButton.rawValue)
    public var quickTranslateButton: Bool
    
    public var outgoingLanguageTranslation = UserDefaultsBackedDictionary<String, String>(userDefaultsKey: Keys.outgoingLanguageTranslation.rawValue, threadSafe: false)
    
    // @available(*, deprecated, message: "Use showRepostToStoryV2 instead")
    @UserDefault(key: Keys.showRepostToStory.rawValue)
    public var showRepostToStory: Bool

    @UserDefault(key: Keys.showRepostToStoryV2.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var showRepostToStoryV2: Bool

    @UserDefault(key: Keys.contextShowRestrict.rawValue)
    public var contextShowRestrict: Bool

    /*@UserDefault(key: Keys.contextShowBan.rawValue)
    public var contextShowBan: Bool*/

    @UserDefault(key: Keys.contextShowSelectFromUser.rawValue)
    public var contextShowSelectFromUser: Bool

    @UserDefault(key: Keys.contextShowSaveToCloud.rawValue)
    public var contextShowSaveToCloud: Bool

    @UserDefault(key: Keys.contextShowHideForwardName.rawValue)
    public var contextShowHideForwardName: Bool

    @UserDefault(key: Keys.contextShowReport.rawValue)
    public var contextShowReport: Bool

    @UserDefault(key: Keys.contextShowReply.rawValue)
    public var contextShowReply: Bool

    @UserDefault(key: Keys.contextShowPin.rawValue)
    public var contextShowPin: Bool

    @UserDefault(key: Keys.contextShowSaveMedia.rawValue)
    public var contextShowSaveMedia: Bool

    @UserDefault(key: Keys.contextShowMessageReplies.rawValue)
    public var contextShowMessageReplies: Bool
    
    @UserDefault(key: Keys.contextShowJson.rawValue)
    public var contextShowJson: Bool
    
    @UserDefault(key: Keys.disableScrollToNextChannel.rawValue)
    public var disableScrollToNextChannel: Bool

    @UserDefault(key: Keys.disableScrollToNextTopic.rawValue)
    public var disableScrollToNextTopic: Bool

    @UserDefault(key: Keys.disableChatSwipeOptions.rawValue)
    public var disableChatSwipeOptions: Bool

    @UserDefault(key: Keys.disableDeleteChatSwipeOption.rawValue)
    public var disableDeleteChatSwipeOption: Bool

    @UserDefault(key: Keys.disableGalleryCamera.rawValue)
    public var disableGalleryCamera: Bool

    @UserDefault(key: Keys.disableGalleryCameraPreview.rawValue)
    public var disableGalleryCameraPreview: Bool

    @UserDefault(key: Keys.disableSendAsButton.rawValue)
    public var disableSendAsButton: Bool

    @UserDefault(key: Keys.disableSnapDeletionEffect.rawValue)
    public var disableSnapDeletionEffect: Bool
    
    @UserDefault(key: Keys.stickerSize.rawValue)
    public var stickerSize: Int32
    
    @UserDefault(key: Keys.stickerTimestamp.rawValue)
    public var stickerTimestamp: Bool    

    @UserDefault(key: Keys.hideRecordingButton.rawValue)
    public var hideRecordingButton: Bool
    
    @UserDefault(key: Keys.hideTabBar.rawValue)
    public var hideTabBar: Bool
    
    @UserDefault(key: Keys.showDC.rawValue)
    public var showDC: Bool
    
    @UserDefault(key: Keys.showCreationDate.rawValue)
    public var showCreationDate: Bool

    @UserDefault(key: Keys.showRegDate.rawValue)
    public var showRegDate: Bool

    public var regDateCache = UserDefaultsBackedDictionary<String, Data>(userDefaultsKey: Keys.regDateCache.rawValue, threadSafe: false)
    
    @UserDefault(key: Keys.compactChatList.rawValue)
    public var compactChatList: Bool

    @UserDefault(key: Keys.compactFolderNames.rawValue)
    public var compactFolderNames: Bool
    
    @UserDefault(key: Keys.allChatsTitleLengthOverride.rawValue)
    public var allChatsTitleLengthOverride: String
//    
//    @UserDefault(key: Keys.allChatsFolderPositionOverride.rawValue)
//    public var allChatsFolderPositionOverride: String
    @UserDefault(key: Keys.allChatsHidden.rawValue)
    public var allChatsHidden: Bool

    @UserDefault(key: Keys.defaultEmojisFirst.rawValue)
    public var defaultEmojisFirst: Bool
    
    @UserDefault(key: Keys.messageDoubleTapActionOutgoing.rawValue)
    public var messageDoubleTapActionOutgoing: String
    
    @UserDefault(key: Keys.wideChannelPosts.rawValue)
    public var wideChannelPosts: Bool

    @UserDefault(key: Keys.forceEmojiTab.rawValue)
    public var forceEmojiTab: Bool
    
    @UserDefault(key: Keys.forceBuiltInMic.rawValue)
    public var forceBuiltInMic: Bool
    
    @UserDefault(key: Keys.secondsInMessages.rawValue)
    public var secondsInMessages: Bool
    
    @UserDefault(key: Keys.hideChannelBottomButton.rawValue)
    public var hideChannelBottomButton: Bool

    @UserDefault(key: Keys.forceSystemSharing.rawValue)
    public var forceSystemSharing: Bool

    @UserDefault(key: Keys.confirmCalls.rawValue)
    public var confirmCalls: Bool
    
    @UserDefault(key: Keys.videoPIPSwipeDirection.rawValue)
    public var videoPIPSwipeDirection: String

    @UserDefault(key: Keys.legacyNotificationsFix.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var legacyNotificationsFix: Bool
    
    @UserDefault(key: Keys.status.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var status: Int64

    public var ephemeralStatus: Int64 = 1
    
    @UserDefault(key: Keys.messageFilterKeywords.rawValue)
    public var messageFilterKeywords: [String]
    
    @UserDefault(key: Keys.inputToolbar.rawValue)
    public var inputToolbar: Bool
    
    @UserDefault(key: Keys.pinnedMessageNotifications.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var pinnedMessageNotifications: String
    
    @UserDefault(key: Keys.mentionsAndRepliesNotifications.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var mentionsAndRepliesNotifications: String
    
    @UserDefault(key: Keys.primaryUserId.rawValue)
    public var primaryUserId: String

    @UserDefault(key: Keys.dismissedSGSuggestions.rawValue)
    public var dismissedSGSuggestions: [String]

    @UserDefault(key: Keys.duckyAppIconAvailable.rawValue)
    public var duckyAppIconAvailable: Bool

    @UserDefault(key: Keys.transcriptionBackend.rawValue)
    public var transcriptionBackend: String

    @UserDefault(key: Keys.translationBackend.rawValue)
    public var translationBackend: String

    @UserDefault(key: Keys.customAppBadge.rawValue)
    public var customAppBadge: String
    
    @UserDefault(key: Keys.canUseNY.rawValue)
    public var canUseNY: Bool

    @UserDefault(key: Keys.nyStyle.rawValue)
    public var nyStyle: String

    @UserDefault(key: Keys.wideTabBar.rawValue)
    public var wideTabBar: Bool
    
    @UserDefault(key: Keys.tabBarSearchEnabled.rawValue)
    public var tabBarSearchEnabled: Bool
    
    @UserDefault(key: Keys.showDeletedMessages.rawValue)
    public var showDeletedMessages: Bool
    
    @UserDefault(key: Keys.saveEditHistory.rawValue)
    public var saveEditHistory: Bool
    
    // MARK: Saved Deleted Messages (AyuGram-style)
    @UserDefault(key: Keys.saveDeletedMessagesMedia.rawValue)
    public var saveDeletedMessagesMedia: Bool
    
    @UserDefault(key: Keys.saveDeletedMessagesReactions.rawValue)
    public var saveDeletedMessagesReactions: Bool
    
    @UserDefault(key: Keys.saveDeletedMessagesForBots.rawValue)
    public var saveDeletedMessagesForBots: Bool
    
    // Ghost Mode settings
    /// 0 = off, 12 / 30 / 45 = delay in seconds
    @UserDefault(key: Keys.ghostModeMessageSendDelaySeconds.rawValue)
    public var ghostModeMessageSendDelaySeconds: Int32

    @UserDefault(key: Keys.disableOnlineStatus.rawValue)
    public var disableOnlineStatus: Bool
    
    @UserDefault(key: Keys.disableTypingStatus.rawValue)
    public var disableTypingStatus: Bool
    
    @UserDefault(key: Keys.disableRecordingVideoStatus.rawValue)
    public var disableRecordingVideoStatus: Bool
    
    @UserDefault(key: Keys.disableUploadingVideoStatus.rawValue)
    public var disableUploadingVideoStatus: Bool
    
    @UserDefault(key: Keys.disableVCMessageRecordingStatus.rawValue)
    public var disableVCMessageRecordingStatus: Bool
    
    @UserDefault(key: Keys.disableVCMessageUploadingStatus.rawValue)
    public var disableVCMessageUploadingStatus: Bool
    
    @UserDefault(key: Keys.disableUploadingPhotoStatus.rawValue)
    public var disableUploadingPhotoStatus: Bool
    
    @UserDefault(key: Keys.disableUploadingFileStatus.rawValue)
    public var disableUploadingFileStatus: Bool
    
    @UserDefault(key: Keys.disableChoosingLocationStatus.rawValue)
    public var disableChoosingLocationStatus: Bool
    
    @UserDefault(key: Keys.disableChoosingContactStatus.rawValue)
    public var disableChoosingContactStatus: Bool
    
    @UserDefault(key: Keys.disablePlayingGameStatus.rawValue)
    public var disablePlayingGameStatus: Bool
    
    @UserDefault(key: Keys.disableRecordingRoundVideoStatus.rawValue)
    public var disableRecordingRoundVideoStatus: Bool
    
    @UserDefault(key: Keys.disableUploadingRoundVideoStatus.rawValue)
    public var disableUploadingRoundVideoStatus: Bool
    
    @UserDefault(key: Keys.disableSpeakingInGroupCallStatus.rawValue)
    public var disableSpeakingInGroupCallStatus: Bool
    
    @UserDefault(key: Keys.disableChoosingStickerStatus.rawValue)
    public var disableChoosingStickerStatus: Bool
    
    @UserDefault(key: Keys.disableEmojiInteractionStatus.rawValue)
    public var disableEmojiInteractionStatus: Bool
    
    @UserDefault(key: Keys.disableEmojiAcknowledgementStatus.rawValue)
    public var disableEmojiAcknowledgementStatus: Bool
    
    @UserDefault(key: Keys.disableMessageReadReceipt.rawValue)
    public var disableMessageReadReceipt: Bool

    /// If `true` (default), replying to an incoming message still sends a read receipt while message receipts are disabled. If `false`, reply does not mark as read (context menu «Read» is unchanged).
    @UserDefault(key: Keys.ghostModeMarkReadOnReply.rawValue)
    public var ghostModeMarkReadOnReply: Bool

    @UserDefault(key: Keys.disableStoryReadReceipt.rawValue)
    public var disableStoryReadReceipt: Bool
    
    @UserDefault(key: Keys.disableAllAds.rawValue)
    public var disableAllAds: Bool
    
    @UserDefault(key: Keys.hideProxySponsor.rawValue)
    public var hideProxySponsor: Bool
    
    @UserDefault(key: Keys.enableSavingProtectedContent.rawValue)
    public var enableSavingProtectedContent: Bool

    @UserDefault(key: Keys.forwardRestrictedAsCopy.rawValue)
    public var forwardRestrictedAsCopy: Bool
    
    @UserDefault(key: Keys.enableSavingSelfDestructingMessages.rawValue)
    public var enableSavingSelfDestructingMessages: Bool
    
    @UserDefault(key: Keys.disableSecretChatBlurOnScreenshot.rawValue)
    public var disableSecretChatBlurOnScreenshot: Bool

    @UserDefault(key: Keys.doubleBottomEnabled.rawValue)
    public var doubleBottomEnabled: Bool

    @UserDefault(key: Keys.enableLocalPremium.rawValue)
    public var enableLocalPremium: Bool
    
    @UserDefault(key: Keys.voiceChangerEnabled.rawValue)
    public var voiceChangerEnabled: Bool
    
    @UserDefault(key: Keys.puterVoiceChangerVoiceId.rawValue)
    public var puterVoiceChangerVoiceId: String
    
    @UserDefault(key: Keys.disableScreenshotDetection.rawValue)
    public var disableScreenshotDetection: Bool
    
    @UserDefault(key: Keys.scrollToTopButtonEnabled.rawValue)
    public var scrollToTopButtonEnabled: Bool

    @UserDefault(key: Keys.fakeLocationEnabled.rawValue)
    public var fakeLocationEnabled: Bool
    
    public var fakeLatitude: Double {
        get { SGFileStore.shared.double(forKey: "fakeLatitude", default: 0.0) }
        set { SGFileStore.shared.set(newValue, forKey: "fakeLatitude") }
    }

    public var fakeLongitude: Double {
        get { SGFileStore.shared.double(forKey: "fakeLongitude", default: 0.0) }
        set { SGFileStore.shared.set(newValue, forKey: "fakeLongitude") }
    }
    
    @UserDefault(key: Keys.enableVideoToCircleOrVoice.rawValue)
    public var enableVideoToCircleOrVoice: Bool

    public var userProfileNotes = UserDefaultsBackedDictionary<String, String>(userDefaultsKey: Keys.userProfileNotes.rawValue, threadSafe: false)

    @UserDefault(key: Keys.enableTelescope.rawValue)
    public var enableTelescope: Bool
    
    /// Font replacement (A-Font style): enable, main font name, bold font name, size multiplier (100 = 1.0)
    @UserDefault(key: Keys.enableFontReplacement.rawValue)
    public var enableFontReplacement: Bool
    
    @UserDefault(key: Keys.fontReplacementName.rawValue)
    public var fontReplacementName: String
    
    @UserDefault(key: Keys.fontReplacementBoldName.rawValue)
    public var fontReplacementBoldName: String
    
    /// Persistent path to copied main font file (so it survives app restart)
    @UserDefault(key: Keys.fontReplacementFilePath.rawValue)
    public var fontReplacementFilePath: String
    
    /// Persistent path to copied bold font file
    @UserDefault(key: Keys.fontReplacementBoldFilePath.rawValue)
    public var fontReplacementBoldFilePath: String
    
    public var fontReplacementSizeMultiplier: Int32 {
        get { SGFileStore.shared.int32(forKey: "fontReplacementSizeMultiplier", default: 100) }
        set { SGFileStore.shared.set(Int(newValue), forKey: "fontReplacementSizeMultiplier") }
    }
    
    @UserDefault(key: Keys.enableLocalMessageEditing.rawValue)
    public var enableLocalMessageEditing: Bool
    
    @UserDefault(key: Keys.disableCompactNumbers.rawValue)
    public var disableCompactNumbers: Bool
    
    @UserDefault(key: Keys.disableZalgoText.rawValue)
    public var disableZalgoText: Bool

    @UserDefault(key: Keys.unlimitedFavoriteStickers.rawValue)
    public var unlimitedFavoriteStickers: Bool
    
    @UserDefault(key: Keys.enableOnlineStatusRecording.rawValue)
    public var enableOnlineStatusRecording: Bool
    
    @UserDefault(key: Keys.onlineStatusRecordingIntervalMinutes.rawValue)
    public var onlineStatusRecordingIntervalMinutes: Int32
    
    @UserDefault(key: Keys.savedOnlineStatusByPeerId.rawValue)
    public var savedOnlineStatusByPeerId: String
    
    @UserDefault(key: Keys.addMusicFromDeviceToProfile.rawValue)
    public var addMusicFromDeviceToProfile: Bool
    
    @UserDefault(key: Keys.hideReactions.rawValue)
    public var hideReactions: Bool
    
    @UserDefault(key: Keys.pluginSystemEnabled.rawValue)
    public var pluginSystemEnabled: Bool
    
    @UserDefault(key: Keys.installedPluginsJson.rawValue)
    public var installedPluginsJson: String

    /// True if the installed-plugins list has at least one enabled entry with a `.js` path (used to wire plugin UI/hooks even when master `pluginSystemEnabled` is off).
    public var hasEnabledJavaScriptPluginInstalled: Bool {
        guard let data = installedPluginsJson.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return false
        }
        for obj in arr {
            guard (obj["enabled"] as? Bool) == true, let path = obj["path"] as? String else { continue }
            if (path as NSString).pathExtension.lowercased() == "js" { return true }
        }
        return false
    }

    /// Включён мастер «Plugin system» или в списке есть активный `.js` — нужно вешать `PluginHost` в чате и хуки. Учитывает `LuxGramFeatures.pluginsEnabled`.
    public var pluginsJavaScriptBridgeActive: Bool {
        guard LuxGramFeatures.pluginsEnabled else { return false }
        return pluginSystemEnabled || hasEnabledJavaScriptPluginInstalled
    }
    
    @UserDefault(key: Keys.chatExportEnabled.rawValue)
    public var chatExportEnabled: Bool

    @UserDefault(key: Keys.profileCoverMediaPath.rawValue)
    public var profileCoverMediaPath: String

    @UserDefault(key: Keys.profileCoverIsVideo.rawValue)
    public var profileCoverIsVideo: Bool
    
    @UserDefault(key: Keys.emojiDownloaderEnabled.rawValue)
    public var emojiDownloaderEnabled: Bool
    
    @UserDefault(key: Keys.feelRichEnabled.rawValue)
    public var feelRichEnabled: Bool
    
    @UserDefault(key: Keys.feelRichStarsAmount.rawValue)
    public var feelRichStarsAmount: String
    
    @UserDefault(key: Keys.giftIdEnabled.rawValue)
    public var giftIdEnabled: Bool

    @UserDefault(key: Keys.fakeProfileEnabled.rawValue)
    public var fakeProfileEnabled: Bool

    @UserDefault(key: Keys.fakeProfileTargetUserId.rawValue)
    public var fakeProfileTargetUserId: String

    @UserDefault(key: Keys.fakeProfileFirstName.rawValue)
    public var fakeProfileFirstName: String

    @UserDefault(key: Keys.fakeProfileLastName.rawValue)
    public var fakeProfileLastName: String

    @UserDefault(key: Keys.fakeProfileUsername.rawValue)
    public var fakeProfileUsername: String

    @UserDefault(key: Keys.fakeProfilePhone.rawValue)
    public var fakeProfilePhone: String

    @UserDefault(key: Keys.fakeProfileId.rawValue)
    public var fakeProfileId: String

    @UserDefault(key: Keys.fakeProfilePremium.rawValue)
    public var fakeProfilePremium: Bool

    @UserDefault(key: Keys.fakeProfileVerified.rawValue)
    public var fakeProfileVerified: Bool

    @UserDefault(key: Keys.fakeProfileScam.rawValue)
    public var fakeProfileScam: Bool

    @UserDefault(key: Keys.fakeProfileFake.rawValue)
    public var fakeProfileFake: Bool

    @UserDefault(key: Keys.fakeProfileSupport.rawValue)
    public var fakeProfileSupport: Bool

    @UserDefault(key: Keys.fakeProfileBot.rawValue)
    public var fakeProfileBot: Bool

    @UserDefault(key: Keys.currentAccountPeerId.rawValue)
    public var currentAccountPeerId: String

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

    @UserDefault(key: Keys.hookInspectorEnabled.rawValue)
    public var hookInspectorEnabled: Bool

    @UserDefault(key: Keys.faceBlurInVideoMessages.rawValue)
    public var faceBlurInVideoMessages: Bool

    @UserDefault(key: Keys.customAvatarRoundingEnabled.rawValue)
    public var customAvatarRoundingEnabled: Bool

    @UserDefault(key: Keys.avatarRoundingPercent.rawValue)
    public var avatarRoundingPercent: Int32

    @UserDefault(key: Keys.selfChatTitleMode.rawValue)
    public var selfChatTitleMode: String

    @UserDefault(key: Keys.selfChatTitleCustomText.rawValue)
    public var selfChatTitleCustomText: String

    /// Whether read receipts should be blocked for a specific peer (per-peer ghost mode).
    public func shouldBlockReadReceiptFor(peerIdNamespace: Int32, peerIdId: Int64) -> Bool {
        return false
    }

    /// Whether removed channels/user chats should be kept accessible.
    public var keepRemovedChannels: Bool {
        return false
    }

    /// Whether a specific channel was removed (for keep-removed-channels feature).
    public func isChannelRemoved(_ peerIdValue: Int64) -> Bool {
        return false
    }

    /// Whether a specific user chat was removed (for keep-removed-channels feature).
    public func isUserChatRemoved(_ peerIdValue: Int64) -> Bool {
        return false
    }

    /// Whether fake profile overlay should apply for this peer id (current account or target user).
    public func shouldApplyFakeProfile(peerId: Int64) -> Bool {
        guard fakeProfileEnabled else { return false }
        let target: String = fakeProfileTargetUserId.isEmpty ? currentAccountPeerId : fakeProfileTargetUserId
        guard let targetNum = Int64(target) else { return false }
        return peerId == targetNum
    }

    /// Display value for first name when fake profile is active.
    public func displayFirstName(peerId: Int64, real: String?) -> String {
        shouldApplyFakeProfile(peerId: peerId) && !fakeProfileFirstName.isEmpty ? fakeProfileFirstName : (real ?? "")
    }

    /// Display value for last name when fake profile is active.
    public func displayLastName(peerId: Int64, real: String?) -> String {
        shouldApplyFakeProfile(peerId: peerId) && !fakeProfileLastName.isEmpty ? fakeProfileLastName : (real ?? "")
    }

    /// Display value for username (without @) when fake profile is active.
    public func displayUsername(peerId: Int64, real: String?) -> String {
        shouldApplyFakeProfile(peerId: peerId) && !fakeProfileUsername.isEmpty ? fakeProfileUsername : (real ?? "")
    }

    /// Display value for phone when fake profile is active.
    public func displayPhone(peerId: Int64, real: String?) -> String {
        shouldApplyFakeProfile(peerId: peerId) && !fakeProfilePhone.isEmpty ? fakeProfilePhone : (real ?? "")
    }

    /// Display value for user id string when fake profile is active.
    public func displayId(peerId: Int64, real: String?) -> String {
        shouldApplyFakeProfile(peerId: peerId) && !fakeProfileId.isEmpty ? fakeProfileId : (real ?? "")
    }

    /// Saved "last seen" timestamps per peer (for online status recording). Key: peerId as Int64, value: timestamp.
    public var savedOnlineStatusByPeerIdDict: [Int64: Int32] {
        get {
            guard let data = savedOnlineStatusByPeerId.data(using: .utf8),
                  let dict = try? JSONDecoder().decode([String: Int32].self, from: data) else {
                return [:]
            }
            var result: [Int64: Int32] = [:]
            for (k, v) in dict where Int64(k) != nil {
                result[Int64(k)!] = v
            }
            return result
        }
        set {
            let dict = Dictionary(uniqueKeysWithValues: newValue.map { ("\($0.key)", $0.value) })
            if let data = try? JSONEncoder().encode(dict),
               let string = String(data: data, encoding: .utf8) {
                savedOnlineStatusByPeerId = string
                synchronizeShared()
            }
        }
    }
    
    public func getSavedOnlineStatusTimestamp(peerId: Int64) -> Int32? {
        return savedOnlineStatusByPeerIdDict[peerId]
    }
    
    public static let onlineStatusTimestampDidChangeNotification = Notification.Name("SGOnlineStatusTimestampDidChange")

    public func setSavedOnlineStatusTimestamp(peerId: Int64, timestamp: Int32) {
        var dict = savedOnlineStatusByPeerIdDict
        dict[peerId] = timestamp
        savedOnlineStatusByPeerIdDict = dict
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: SGSimpleSettings.onlineStatusTimestampDidChangeNotification, object: nil, userInfo: ["peerId": peerId])
        }
    }
    
    /// Strip Zalgo / combining characters from string (for display when disableZalgoText is on).
    public static func stripZalgo(_ string: String) -> String {
        return string.filter { char in
            !char.unicodeScalars.contains(where: { (scalar: Unicode.Scalar) in
                let cat = scalar.properties.generalCategory
                return cat == .nonspacingMark || cat == .spacingMark || cat == .enclosingMark
            })
        }
    }
    
}

extension SGSimpleSettings {
    public var isStealthModeEnabled: Bool {
        return storyStealthMode && canUseStealthMode
    }
    
    public static func makeOutgoingLanguageTranslationKey(accountId: Int64, peerId: Int64) -> String {
        return "\(accountId):\(peerId)"
    }
}

extension SGSimpleSettings {
    public var translationBackendEnum: SGSimpleSettings.TranslationBackend {
        return TranslationBackend(rawValue: translationBackend) ?? .default
    }
    
    public var transcriptionBackendEnum: SGSimpleSettings.TranscriptionBackend {
        return TranscriptionBackend(rawValue: transcriptionBackend) ?? .default
    }
}

extension SGSimpleSettings {
    public var isNYEnabled: Bool {
        return canUseNY && NYStyle(rawValue: nyStyle) != .default
    }
    
    /// Check if a peer should be treated as premium, considering local premium setting
    /// - Parameters:
    ///   - peerId: The peer ID to check
    ///   - accountPeerId: The current account's peer ID
    ///   - isPremium: The actual premium status from Telegram
    /// - Returns: True if the peer should be treated as premium (either has real premium or has local premium enabled for current user)
    public func isPremium(peerId: Int64, accountPeerId: Int64, isPremium: Bool) -> Bool {
        if isPremium {
            return true
        }
        // Local premium only applies to the current user
        if self.enableLocalPremium && peerId == accountPeerId {
            return true
        }
        // Fake profile: show premium badge for the substituted profile when enabled
        if self.shouldApplyFakeProfile(peerId: peerId) && self.fakeProfilePremium {
            return true
        }
        return false
    }
    
}

public func getSGDownloadPartSize(_ default: Int64, fileSize: Int64?) -> Int64 {
    let currentDownloadSetting = SGSimpleSettings.shared.downloadSpeedBoost
    // Increasing chunk size for small files make it worse in terms of overall download performance
    let smallFileSizeThreshold = 1 * 1024 * 1024 // 1 MB
    switch (currentDownloadSetting) {
        case SGSimpleSettings.DownloadSpeedBoostValues.medium.rawValue:
            if let fileSize, fileSize <= smallFileSizeThreshold {
                return `default`
            }
            return 512 * 1024
        case SGSimpleSettings.DownloadSpeedBoostValues.maximum.rawValue:
            if let fileSize, fileSize <= smallFileSizeThreshold {
                return `default`
            }
            return 1024 * 1024
        default:
            return `default`
    }
}

public func getSGMaxPendingParts(_ default: Int) -> Int {
    let currentDownloadSetting = SGSimpleSettings.shared.downloadSpeedBoost
    switch (currentDownloadSetting) {
        case SGSimpleSettings.DownloadSpeedBoostValues.medium.rawValue:
            return 8
        case SGSimpleSettings.DownloadSpeedBoostValues.maximum.rawValue:
            return 12
        default:
            return `default`
    }
}

public func sgUseShortAllChatsTitle(_ default: Bool) -> Bool {
    let currentOverride = SGSimpleSettings.shared.allChatsTitleLengthOverride
    switch (currentOverride) {
        case SGSimpleSettings.AllChatsTitleLengthOverride.short.rawValue:
            return true
        case SGSimpleSettings.AllChatsTitleLengthOverride.long.rawValue:
            return false
        default:
            return `default`
    }
}

// MARK: - LuxGram settings backup (export / import JSON)

public extension SGSimpleSettings {
    /// Must match `@UserDefault(..., userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER))` properties.
    static let keysUsingAppGroupUserDefaults: Set<String> = [
        Keys.showRepostToStoryV2.rawValue,
        Keys.legacyNotificationsFix.rawValue,
        Keys.status.rawValue,
        Keys.pinnedMessageNotifications.rawValue,
        Keys.mentionsAndRepliesNotifications.rawValue
    ]

    /// Writes a JSON file to the temp directory; use with document picker “export”.
    static func exportLuxGramSettingsJSONFile() throws -> URL {
        var entries: [String: Any] = [:]
        let standard = UserDefaults.standard
        let group = UserDefaults(suiteName: APP_GROUP_IDENTIFIER)
        for key in Keys.allCases {
            let k = key.rawValue
            if let object = standard.object(forKey: k) {
                entries[k] = object
            } else if let object = group?.object(forKey: k) {
                entries[k] = object
            }
        }
        let root: [String: Any] = [
            "format": "gleg_settings",
            "version": 1,
            "entries": entries
        ]
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LuxGram_settings.json")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Applies keys from exported JSON; returns number of keys written.
    @discardableResult
    static func importLuxGramSettingsJSON(data: Data) throws -> Int {
        let json = try JSONSerialization.jsonObject(with: data)
        let entries: [String: Any]
        if let root = json as? [String: Any] {
            if let e = root["entries"] as? [String: Any] {
                entries = e
            } else if root["format"] == nil, root.keys.contains(where: { Keys(rawValue: $0) != nil }) {
                entries = root
            } else {
                throw NSError(domain: "SGSimpleSettings", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid LuxGram settings file"])
            }
        } else {
            throw NSError(domain: "SGSimpleSettings", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid LuxGram settings file"])
        }
        let standard = UserDefaults.standard
        let group = UserDefaults(suiteName: APP_GROUP_IDENTIFIER)
        var count = 0
        for (key, value) in entries {
            guard Keys(rawValue: key) != nil else { continue }
            guard isValidUserDefaultsJSONImportValue(value) else { continue }
            if keysUsingAppGroupUserDefaults.contains(key) {
                group?.set(value, forKey: key)
            } else {
                standard.set(value, forKey: key)
            }
            count += 1
        }
        standard.synchronize()
        group?.synchronize()
        return count
    }

    private static func isValidUserDefaultsJSONImportValue(_ value: Any) -> Bool {
        if value is String || value is NSNumber || value is Bool {
            return true
        }
        if let arr = value as? [Any] {
            return arr.allSatisfy { isValidUserDefaultsJSONImportValue($0) }
        }
        if let dict = value as? [String: Any] {
            return dict.values.allSatisfy { isValidUserDefaultsJSONImportValue($0) }
        }
        return false
    }
}

public extension Notification.Name {
    /// Posted when “Hide Proxy Sponsor” is toggled so the chat list can refresh.
    static let sgHideProxySponsorDidChange = Notification.Name("SGHideProxySponsorDidChange")
    /// Posted when LuxGram avatar rounding toggle or slider changes.
    static let sgAvatarRoundingSettingsDidChange = Notification.Name("SGAvatarRoundingSettingsDidChange")
    /// Posted when main chats list title mode or custom text changes (root «Чаты» / Chats).
    static let sgSelfChatTitleSettingsDidChange = Notification.Name("SGSelfChatTitleSettingsDidChange")
    /// Posted when profile full-screen color or related LuxGram appearance toggles change (refresh Peer Info).
    static let sgPeerInfoAppearanceSettingsDidChange = Notification.Name("SGPeerInfoAppearanceSettingsDidChange")
    /// Posted when «Local Telegram Premium» is toggled so `AccountContext.isPremium` can refresh.
    static let sgEnableLocalPremiumDidChange = Notification.Name("SGEnableLocalPremiumDidChange")
    /// Posted when a custom badge image finishes caching so title views can refresh.
    static let sgBadgeImageDidCache = Notification.Name("SGBadgeImageDidCache")

}

/// How to show the title on the main chats tab (above stories), not in Saved/self-chat.
public enum SelfChatTitleMode: String, CaseIterable {
    case `default`
    case displayName
    case username
}

public extension SGSimpleSettings {
    var selfChatTitleModeValue: SelfChatTitleMode {
        get {
            let raw = self.selfChatTitleMode
            if raw == "custom" {
                return .default
            }
            return SelfChatTitleMode(rawValue: raw) ?? .default
        }
        set {
            self.selfChatTitleMode = newValue.rawValue
        }
    }
}

```

### `LuxGram/SGSettingsUI/Sources/PluginMetadata.swift`

```swift
// MARK: LuxGram – Plugin metadata (exteraGram-compatible .plugin file format)
import Foundation

/// Metadata parsed from a .plugin file (exteraGram plugin format).
public struct PluginMetadata: Codable, Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let version: String
    public let author: String
    /// Icon reference e.g. "ApplicationEmoji/141" or "glePlugins/1".
    public let iconRef: String?
    public let minVersion: String?
    /// If true, plugin modifies profile display (Fake Profile–style).
    public let hasUserDisplay: Bool
    /// Permissions requested by the plugin (e.g. ["ui", "chat", "network", "compose", "settings"]).
    public let permissions: [String]?

    public init(id: String, name: String, description: String, version: String, author: String, iconRef: String? = nil, minVersion: String? = nil, hasUserDisplay: Bool = false, permissions: [String]? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.version = version
        self.author = author
        self.iconRef = iconRef
        self.minVersion = minVersion
        self.hasUserDisplay = hasUserDisplay
        self.permissions = permissions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decode(String.self, forKey: .description)
        version = try c.decode(String.self, forKey: .version)
        author = try c.decode(String.self, forKey: .author)
        iconRef = try c.decodeIfPresent(String.self, forKey: .iconRef)
        minVersion = try c.decodeIfPresent(String.self, forKey: .minVersion)
        hasUserDisplay = try c.decodeIfPresent(Bool.self, forKey: .hasUserDisplay) ?? false
        permissions = try c.decodeIfPresent([String].self, forKey: .permissions)
    }
}

/// Installed plugin info (stored in settings).
public struct PluginInfo: Codable, Equatable {
    public var metadata: PluginMetadata
    public var path: String
    public var enabled: Bool
    public var hasSettings: Bool
    
    public init(metadata: PluginMetadata, path: String, enabled: Bool, hasSettings: Bool) {
        self.metadata = metadata
        self.path = path
        self.enabled = enabled
        self.hasSettings = hasSettings
    }
}

/// Parses exteraGram-style metadata from .plugin file content (Python script with __name__, __description__, etc.).
public enum PluginMetadataParser {
    private static let namePattern = #"__name__\s*=\s*["']([^"']+)["']"#
    private static let descriptionPattern = #"__description__\s*=\s*["']([^"']+)["']"#
    private static let versionPattern = #"__version__\s*=\s*["']([^"']+)["']"#
    private static let authorPattern = #"__author__\s*=\s*["']([^"']+)["']"#
    private static let idPattern = #"__id__\s*=\s*["']([^"']+)["']"#
    private static let iconPattern = #"__icon__\s*=\s*["']([^"']+)["']"#
    private static let minVersionPattern = #"__min_version__\s*=\s*["']([^"']+)["']"#
    private static let createSettingsPattern = #"def\s+create_settings\s*\("#
    /// Some plugins set __settings__ = True (e.g. panic_passcode_pro).
    private static let settingsFlagPattern = #"__settings__\s*=\s*True"#
    /// Plugins that modify profile display (Fake Profile–style) set __user_display__ = True.
    private static let userDisplayPattern = #"__user_display__\s*=\s*True"#

    public static func parse(content: String) -> PluginMetadata? {
        guard let name = firstMatch(in: content, pattern: namePattern),
              let id = firstMatch(in: content, pattern: idPattern) else {
            return nil
        }
        let description = firstMatch(in: content, pattern: descriptionPattern) ?? ""
        let version = firstMatch(in: content, pattern: versionPattern) ?? "1.0"
        let author = firstMatch(in: content, pattern: authorPattern) ?? ""
        let iconRef = firstMatch(in: content, pattern: iconPattern)
        let minVersion = firstMatch(in: content, pattern: minVersionPattern)
        let hasUserDisplay = content.range(of: userDisplayPattern, options: .regularExpression) != nil
        return PluginMetadata(id: id, name: name, description: description, version: version, author: author, iconRef: iconRef, minVersion: minVersion, hasUserDisplay: hasUserDisplay)
    }
    
    public static func hasCreateSettings(content: String) -> Bool {
        content.range(of: createSettingsPattern, options: .regularExpression) != nil
            || content.range(of: settingsFlagPattern, options: .regularExpression) != nil
    }
    
    /// Parses metadata from a JavaScript plugin file (LuxGram JS plugin format).
    /// Expects a global object: Plugin = { id?, name, author?, version?, description? } (single or double quotes).
    public static func parseJavaScript(content: String) -> PluginMetadata? {
        let idPattern = #"(?:["']id["']|\bid)\s*:\s*["']([^"']*)["']"#
        let namePattern = #"(?:["']name["']|\bname)\s*:\s*["']([^"']+)["']"#
        let authorPattern = #"(?:["']author["']|\bauthor)\s*:\s*["']([^"']*)["']"#
        let versionPattern = #"(?:["']version["']|\bversion)\s*:\s*["']([^"']*)["']"#
        let descriptionPattern = #"(?:["']description["']|\bdescription)\s*:\s*["']([^"']*)["']"#
        let name = firstMatch(in: content, pattern: namePattern)
        let id = firstMatch(in: content, pattern: idPattern)
            ?? name.map { $0.lowercased().replacingOccurrences(of: " ", with: "-").filter { $0.isLetter || $0.isNumber || $0 == "-" } }
        guard let id = id, !id.isEmpty, let name = name else { return nil }
        let author = firstMatch(in: content, pattern: authorPattern) ?? ""
        let version = firstMatch(in: content, pattern: versionPattern) ?? "1.0"
        let description = firstMatch(in: content, pattern: descriptionPattern) ?? ""
        // Parse permissions: ["ui", "chat", "network"]
        let permissionsPattern = #"(?:["']permissions["']|\bpermissions)\s*:\s*\[([^\]]*)\]"#
        var permissions: [String]?
        if let permStr = firstMatch(in: content, pattern: permissionsPattern) {
            let items = permStr.components(separatedBy: ",").compactMap { item -> String? in
                let trimmed = item.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                return trimmed.isEmpty ? nil : trimmed
            }
            if !items.isEmpty { permissions = items }
        }
        return PluginMetadata(id: id, name: name, description: description, version: version, author: author, iconRef: nil, minVersion: nil, hasUserDisplay: false, permissions: permissions)
    }

    private static func firstMatch(in string: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
              let range = Range(match.range(at: 1), in: string) else {
            return nil
        }
        return String(string[range])
    }
}

```

### `LuxGram/SGSettingsUI/Sources/PluginBridge.swift`

```swift
// MARK: LuxGram – Plugin bridge (Swift ↔ Python runtime for exteraGram .plugin files)
//
// This module provides a bridge to run or query exteraGram-style .plugin files (Python).
// - Default: metadata and settings detection via regex (PluginMetadataParser), works on iOS/macOS.
// - Optional: when PythonKit (https://github.com/pvieito/PythonKit) is available, use
//   PythonPluginRuntime to execute plugin code in a sandbox and read metadata from Python.
//
// swift-bridge (https://github.com/chinedufn/swift-bridge) is for Rust↔Swift; for Swift↔Python
// we use PythonKit. This protocol allows swapping implementations (regex-only vs PythonKit).

import Foundation

/// Runtime used to parse or execute .plugin file content (exteraGram Python format).
public protocol PluginRuntime: Sendable {
    /// Parses plugin metadata (__name__, __id__, __description__, etc.) from file content.
    func parseMetadata(content: String) -> PluginMetadata?
    /// Returns true if the plugin defines create_settings or __settings__ = True.
    func hasCreateSettings(content: String) -> Bool
}

/// Default implementation using regex-based parsing (no Python required). Works on iOS and macOS.
public final class DefaultPluginRuntime: PluginRuntime, @unchecked Sendable {
    public static let shared = DefaultPluginRuntime()
    
    public init() {}
    
    public func parseMetadata(content: String) -> PluginMetadata? {
        PluginMetadataParser.parse(content: content)
    }
    
    public func hasCreateSettings(content: String) -> Bool {
        PluginMetadataParser.hasCreateSettings(content: content)
    }
}

/// Current runtime used by the app. Set to a PythonKit-based runtime when Python is available.
public var currentPluginRuntime: PluginRuntime = DefaultPluginRuntime.shared

```

### `LuxGram/SGSettingsUI/Sources/PluginBridgePythonKit.swift`

```swift
// MARK: LuxGram – Plugin bridge via PythonKit (Swift ↔ Python)
//
// Uses PythonKit (https://github.com/pvieito/PythonKit) when available.
// exteraGram plugins import Android/Java (base_plugin, org.telegram.messenger, etc.);
// on iOS/macOS those are unavailable, so we use regex parsing by default. When PythonKit
// is linked, you can implement full execution with builtins.exec(code, globals, locals)
// and stub modules (base_plugin, java, ui, ...) so the script runs and exposes __name__, etc.
//
// To enable PythonKit: add as SPM dependency or vendored; on iOS embed a Python framework.

import Foundation

#if canImport(PythonKit)
import PythonKit

/// Runtime that can use Python to parse/run plugin content when PythonKit is available.
/// Currently delegates to regex parser; replace with exec()-based implementation when
/// stubs for base_plugin/java/android are ready.
public final class PythonPluginRuntime: PluginRuntime, @unchecked Sendable {
    public static let shared = PythonPluginRuntime()
    
    private init() {}
    
    public func parseMetadata(content: String) -> PluginMetadata? {
        // Optional: use Python builtins.exec(content, globals, locals) with stubbed
        // base_plugin, java, ui, etc., then read __name__, __id__, ... from globals.
        // For now use regex so it works without a full Python stub environment.
        return PluginMetadataParser.parse(content: content)
    }
    
    public func hasCreateSettings(content: String) -> Bool {
        PluginMetadataParser.hasCreateSettings(content: content)
    }
}
#else
// When PythonKit is not linked, PythonPluginRuntime is not compiled; app uses DefaultPluginRuntime.
#endif

```

### `LuxGram/SGSettingsUI/Sources/ItemListPluginRowItem.swift`

```swift
// MARK: LuxGram – Plugin row item (like Active sites: icon, name, author, description, switch)
import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import AppBundle

/// One row per plugin: icon, name, author, description; switch on the right (like Active sites).
final class ItemListPluginRowItem: ListViewItem, ItemListItem {
    let presentationData: ItemListPresentationData
    let plugin: PluginInfo
    let icon: UIImage?
    let sectionId: ItemListSectionId
    let toggle: (Bool) -> Void
    let action: (() -> Void)?
    
    init(presentationData: ItemListPresentationData, plugin: PluginInfo, icon: UIImage?, sectionId: ItemListSectionId, toggle: @escaping (Bool) -> Void, action: (() -> Void)? = nil) {
        self.presentationData = presentationData
        self.plugin = plugin
        self.icon = icon
        self.sectionId = sectionId
        self.toggle = toggle
        self.action = action
    }
    
    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = ItemListPluginRowItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            Queue.mainQueue().async {
                completion(node, { return (nil, { _ in apply(false) }) })
            }
        }
    }
    
    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? ItemListPluginRowItemNode {
                let makeLayout = nodeValue.asyncLayout()
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
                    Queue.mainQueue().async {
                        completion(layout, { _ in apply(animation.isAnimated) })
                    }
                }
            }
        }
    }
    
    var selectable: Bool { action != nil }
    func selected(listView: ListView) {
        listView.clearHighlightAnimated(true)
        action?()
    }
}

private let leftInsetNoIcon: CGFloat = 16.0
private let iconSize: CGFloat = 30.0
private let leftInsetWithIcon: CGFloat = 16.0 + iconSize + 13.0
private let switchWidth: CGFloat = 51.0
private let switchRightInset: CGFloat = 15.0

final class ItemListPluginRowItemNode: ListViewItemNode {
    private let backgroundNode: ASDisplayNode
    private let topStripeNode: ASDisplayNode
    private let bottomStripeNode: ASDisplayNode
    private let highlightedBackgroundNode: ASDisplayNode
    private let maskNode: ASImageNode
    
    private let iconNode: ASImageNode
    private let titleNode: TextNode
    private let authorNode: TextNode
    private let descriptionNode: TextNode
    private var switchNode: ASDisplayNode?
    private var switchView: UISwitch?
    
    private var layoutParams: (ItemListPluginRowItem, ListViewItemLayoutParams, ItemListNeighbors)?
    
    init() {
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true
        self.topStripeNode = ASDisplayNode()
        self.topStripeNode.isLayerBacked = true
        self.bottomStripeNode = ASDisplayNode()
        self.bottomStripeNode.isLayerBacked = true
        self.maskNode = ASImageNode()
        self.maskNode.isUserInteractionEnabled = false
        self.iconNode = ASImageNode()
        self.iconNode.contentMode = .scaleAspectFit
        self.iconNode.cornerRadius = 7.0
        self.iconNode.clipsToBounds = true
        self.iconNode.isLayerBacked = true
        self.titleNode = TextNode()
        self.titleNode.isUserInteractionEnabled = false
        self.titleNode.contentsScale = UIScreen.main.scale
        self.authorNode = TextNode()
        self.authorNode.isUserInteractionEnabled = false
        self.authorNode.contentsScale = UIScreen.main.scale
        self.descriptionNode = TextNode()
        self.descriptionNode.isUserInteractionEnabled = false
        self.descriptionNode.contentsScale = UIScreen.main.scale
        self.highlightedBackgroundNode = ASDisplayNode()
        self.highlightedBackgroundNode.isLayerBacked = true
        super.init(layerBacked: false, rotated: false, seeThrough: false)
        addSubnode(self.backgroundNode)
        addSubnode(self.topStripeNode)
        addSubnode(self.bottomStripeNode)
        addSubnode(self.maskNode)
        addSubnode(self.iconNode)
        addSubnode(self.titleNode)
        addSubnode(self.authorNode)
        addSubnode(self.descriptionNode)
    }
    
    func asyncLayout() -> (ItemListPluginRowItem, ListViewItemLayoutParams, ItemListNeighbors) -> (ListViewItemNodeLayout, (Bool) -> Void) {
        let makeTitle = TextNode.asyncLayout(self.titleNode)
        let makeAuthor = TextNode.asyncLayout(self.authorNode)
        let makeDescription = TextNode.asyncLayout(self.descriptionNode)
        return { item, params, neighbors in
            let titleFont = Font.medium(floor(item.presentationData.fontSize.itemListBaseFontSize * 16.0 / 17.0))
            let textFont = Font.regular(floor(item.presentationData.fontSize.itemListBaseFontSize * 14.0 / 17.0))
            let leftInset = leftInsetWithIcon + params.leftInset
            let rightInset = params.rightInset + switchWidth + switchRightInset
            let textWidth = params.width - leftInset - rightInset - 8.0
            
            let meta = item.plugin.metadata
            let titleAttr = NSAttributedString(string: meta.name, font: titleFont, textColor: item.presentationData.theme.list.itemPrimaryTextColor)
            let lang = item.presentationData.strings.baseLanguageCode
            let versionAuthor = (lang == "ru" ? "Версия " : "Version ") + "\(meta.version) · \(meta.author)"
            let authorAttr = NSAttributedString(string: versionAuthor, font: textFont, textColor: item.presentationData.theme.list.itemSecondaryTextColor)
            let descAttr = NSAttributedString(string: meta.description, font: textFont, textColor: item.presentationData.theme.list.itemPrimaryTextColor)
            
            let (titleLayout, titleApply) = makeTitle(TextNodeLayoutArguments(attributedString: titleAttr, backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: textWidth, height: .greatestFiniteMagnitude), alignment: .natural, cutout: nil, insets: .zero))
            let (authorLayout, authorApply) = makeAuthor(TextNodeLayoutArguments(attributedString: authorAttr, backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: textWidth, height: .greatestFiniteMagnitude), alignment: .natural, cutout: nil, insets: .zero))
            let (descLayout, descApply) = makeDescription(TextNodeLayoutArguments(attributedString: descAttr, backgroundColor: nil, maximumNumberOfLines: 2, truncationType: .end, constrainedSize: CGSize(width: textWidth, height: .greatestFiniteMagnitude), alignment: .natural, cutout: nil, insets: .zero))
            
            let verticalInset: CGFloat = 4.0
            let rowHeight: CGFloat = verticalInset * 2 + 10 + titleLayout.size.height + 4 + authorLayout.size.height + 4 + descLayout.size.height
            let contentHeight = max(75.0, rowHeight)
            let insets = itemListNeighborsGroupedInsets(neighbors, params)
            let layout = ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: contentHeight), insets: insets)
            let layoutSize = layout.size
            let separatorHeight = UIScreenPixel
            
            return (layout, { [weak self] animated in
                guard let self = self else { return }
                self.layoutParams = (item, params, neighbors)
                let theme = item.presentationData.theme
                self.topStripeNode.backgroundColor = theme.list.itemBlocksSeparatorColor
                self.bottomStripeNode.backgroundColor = theme.list.itemBlocksSeparatorColor
                self.backgroundNode.backgroundColor = theme.list.itemBlocksBackgroundColor
                self.highlightedBackgroundNode.backgroundColor = theme.list.itemHighlightedBackgroundColor
                self.iconNode.image = item.icon
                let _ = titleApply()
                let _ = authorApply()
                let _ = descApply()
                
                if self.switchView == nil {
                    let sw = UISwitch()
                    sw.addTarget(self, action: #selector(self.switchChanged(_:)), for: .valueChanged)
                    self.switchView = sw
                    self.switchNode = ASDisplayNode(viewBlock: { sw })
                    self.addSubnode(self.switchNode!)
                }
                self.switchView?.isOn = item.plugin.enabled
                self.switchView?.isUserInteractionEnabled = true
                
                let hasCorners = itemListHasRoundedBlockLayout(params)
                var hasTopCorners = false
                var hasBottomCorners = false
                switch neighbors.top {
                case .sameSection(false): self.topStripeNode.isHidden = true
                default: hasTopCorners = true; self.topStripeNode.isHidden = hasCorners
                }
                let bottomStripeInset: CGFloat
                switch neighbors.bottom {
                case .sameSection(false): bottomStripeInset = leftInsetWithIcon + params.leftInset
                default: bottomStripeInset = 0; hasBottomCorners = true; self.bottomStripeNode.isHidden = hasCorners
                }
                self.maskNode.image = hasCorners ? PresentationResourcesItemList.cornersImage(theme, top: hasTopCorners, bottom: hasBottomCorners, glass: false) : nil
                
                self.backgroundNode.frame = CGRect(origin: CGPoint(x: 0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: contentHeight + min(insets.top, separatorHeight) + min(insets.bottom, separatorHeight)))
                self.maskNode.frame = self.backgroundNode.frame.insetBy(dx: params.leftInset, dy: 0)
                self.topStripeNode.frame = CGRect(x: 0, y: -min(insets.top, separatorHeight), width: layoutSize.width, height: separatorHeight)
                self.bottomStripeNode.frame = CGRect(x: bottomStripeInset, y: contentHeight, width: layoutSize.width - bottomStripeInset - params.rightInset, height: separatorHeight)
                
                self.iconNode.frame = CGRect(x: params.leftInset + 16, y: verticalInset + 10, width: iconSize, height: iconSize)
                let textX = params.leftInset + 16 + iconSize + 13
                self.titleNode.frame = CGRect(origin: CGPoint(x: textX, y: verticalInset + 10), size: titleLayout.size)
                self.authorNode.frame = CGRect(origin: CGPoint(x: textX, y: verticalInset + 10 + titleLayout.size.height + 4), size: authorLayout.size)
                self.descriptionNode.frame = CGRect(origin: CGPoint(x: textX, y: verticalInset + 10 + titleLayout.size.height + 4 + authorLayout.size.height + 4), size: descLayout.size)
                
                let switchSize = self.switchView?.bounds.size ?? CGSize(width: switchWidth, height: 31)
                self.switchNode?.frame = CGRect(x: params.width - params.rightInset - switchWidth - switchRightInset, y: floor((contentHeight - switchSize.height) / 2.0), width: switchWidth, height: switchSize.height)
                self.highlightedBackgroundNode.frame = self.backgroundNode.frame
            })
        }
    }
    
    @objc private func switchChanged(_ sender: UISwitch) {
        if let item = self.layoutParams?.0 {
            item.toggle(sender.isOn)
        }
    }
    
    override func setHighlighted(_ highlighted: Bool, at point: CGPoint, animated: Bool) {
        super.setHighlighted(highlighted, at: point, animated: animated)
        if highlighted {
            self.highlightedBackgroundNode.alpha = 1
            if self.highlightedBackgroundNode.supernode == nil {
                self.insertSubnode(self.highlightedBackgroundNode, aboveSubnode: self.backgroundNode)
            }
        } else {
            if animated {
                self.highlightedBackgroundNode.layer.animateAlpha(from: self.highlightedBackgroundNode.alpha, to: 0, duration: 0.25)
            }
            self.highlightedBackgroundNode.alpha = 0
        }
    }
}

```

### `LuxGram/SGSettingsUI/Sources/PluginListController.swift`

```swift
// MARK: LuxGram – Plugin list (like Active sites: icon, name, author, description, switch; Settings below)
import Foundation
import UIKit
import ObjectiveC
import UniformTypeIdentifiers
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import SGSimpleSettings
import AppBundle

private var documentPickerDelegateKey: UInt8 = 0

private func loadInstalledPlugins() -> [PluginInfo] {
    guard let data = SGSimpleSettings.shared.installedPluginsJson.data(using: .utf8),
          let list = try? JSONDecoder().decode([PluginInfo].self, from: data) else {
        return []
    }
    return list
}

private func saveInstalledPlugins(_ plugins: [PluginInfo]) {
    if let data = try? JSONEncoder().encode(plugins),
       let json = String(data: data, encoding: .utf8) {
        SGSimpleSettings.shared.installedPluginsJson = json
        SGSimpleSettings.shared.synchronizeShared()
    }
}

// Master switch + Add plugin (.js) + installed plugins list.
private enum PluginListEntry: ItemListNodeEntry {
    case pluginSystemSwitch(id: Int, title: String, subtitle: String?, value: Bool)
    case addJsAction(id: Int, text: String)
    case createJsAction(id: Int, text: String)
    case listHeader(id: Int, text: String)
    case pluginRow(id: Int, plugin: PluginInfo)
    case pluginSettings(id: Int, pluginId: String, text: String)
    case pluginEditCode(id: Int, pluginId: String, text: String)
    case pluginDelete(id: Int, pluginId: String, text: String)
    case emptyNotice(id: Int, text: String)

    var id: Int { stableId }

    var section: ItemListSectionId {
        switch self {
        case .pluginSystemSwitch, .addJsAction, .createJsAction: return 0
        case .listHeader, .pluginRow, .pluginSettings, .pluginEditCode, .pluginDelete, .emptyNotice: return 1
        }
    }

    var stableId: Int {
        switch self {
        case .pluginSystemSwitch(let id, _, _, _), .addJsAction(let id, _), .createJsAction(let id, _), .listHeader(let id, _), .pluginRow(let id, _), .pluginSettings(let id, _, _), .pluginEditCode(let id, _, _), .pluginDelete(let id, _, _), .emptyNotice(let id, _): return id
        }
    }

    static func < (lhs: PluginListEntry, rhs: PluginListEntry) -> Bool { lhs.stableId < rhs.stableId }

    static func == (lhs: PluginListEntry, rhs: PluginListEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.pluginSystemSwitch(a, t1, s1, v1), .pluginSystemSwitch(b, t2, s2, v2)):
            return a == b && t1 == t2 && s1 == s2 && v1 == v2
        case let (.addJsAction(a, t1), .addJsAction(b, t2)): return a == b && t1 == t2
        case let (.createJsAction(a, t1), .createJsAction(b, t2)): return a == b && t1 == t2
        case let (.listHeader(a, t1), .listHeader(b, t2)): return a == b && t1 == t2
        case let (.pluginRow(a, p1), .pluginRow(b, p2)): return a == b && p1.metadata.id == p2.metadata.id && p1.enabled == p2.enabled
        case let (.pluginSettings(a, id1, t1), .pluginSettings(b, id2, t2)),
             let (.pluginEditCode(a, id1, t1), .pluginEditCode(b, id2, t2)),
             let (.pluginDelete(a, id1, t1), .pluginDelete(b, id2, t2)): return a == b && id1 == id2 && t1 == t2
        case let (.emptyNotice(a, t1), .emptyNotice(b, t2)): return a == b && t1 == t2
        default: return false
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! PluginListArguments
        switch self {
        case .pluginSystemSwitch(_, let title, let subtitle, let value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                title: title,
                text: subtitle,
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { args.setPluginSystemEnabled($0) },
                action: nil
            )
        case .addJsAction(_, let text):
            return ItemListActionItem(presentationData: presentationData, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: { args.addJsPlugin() })
        case .createJsAction(_, let text):
            return ItemListActionItem(presentationData: presentationData, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: { args.createJsPlugin() })
        case .listHeader(_, let text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case .pluginRow(_, let plugin):
            let icon = args.iconResolver(plugin.metadata.iconRef)
            return ItemListPluginRowItem(presentationData: presentationData, plugin: plugin, icon: icon, sectionId: self.section, toggle: { value in args.toggle(plugin.metadata.id, value) }, action: nil)
        case .pluginSettings(_, let pluginId, let text):
            return ItemListDisclosureItem(presentationData: presentationData, title: text, label: "", sectionId: self.section, style: .blocks, action: { args.openSettings(pluginId) })
        case .pluginEditCode(_, let pluginId, let text):
            return ItemListActionItem(presentationData: presentationData, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: { args.editPluginCode(pluginId) })
        case .pluginDelete(_, let pluginId, let text):
            return ItemListActionItem(presentationData: presentationData, title: text, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: { args.deletePlugin(pluginId) })
        case .emptyNotice(_, let text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private final class PluginListArguments {
    let setPluginSystemEnabled: (Bool) -> Void
    let toggle: (String, Bool) -> Void
    let openSettings: (String) -> Void
    let deletePlugin: (String) -> Void
    let addJsPlugin: () -> Void
    let createJsPlugin: () -> Void
    let editPluginCode: (String) -> Void
    let iconResolver: (String?) -> UIImage?

    init(setPluginSystemEnabled: @escaping (Bool) -> Void, toggle: @escaping (String, Bool) -> Void, openSettings: @escaping (String) -> Void, deletePlugin: @escaping (String) -> Void, addJsPlugin: @escaping () -> Void, createJsPlugin: @escaping () -> Void, editPluginCode: @escaping (String) -> Void, iconResolver: @escaping (String?) -> UIImage?) {
        self.setPluginSystemEnabled = setPluginSystemEnabled
        self.toggle = toggle
        self.openSettings = openSettings
        self.deletePlugin = deletePlugin
        self.addJsPlugin = addJsPlugin
        self.createJsPlugin = createJsPlugin
        self.editPluginCode = editPluginCode
        self.iconResolver = iconResolver
    }
}

private func pluginListEntries(presentationData: PresentationData, plugins: [PluginInfo]) -> [PluginListEntry] {
    let lang = presentationData.strings.baseLanguageCode
    var entries: [PluginListEntry] = []
    var id = 0
    let systemTitle = lang == "ru" ? "Система плагинов" : "Plugin system"
    let systemSubtitle = lang == "ru"
        ? "Включает JS-плагины и хуки (отправка сообщений, меню и т.д.)."
        : "Enables JS plugins and hooks (outgoing messages, menus, etc.)."
    entries.append(.pluginSystemSwitch(id: id, title: systemTitle, subtitle: systemSubtitle, value: SGSimpleSettings.shared.pluginSystemEnabled))
    id += 1
    entries.append(.addJsAction(id: id, text: lang == "ru" ? "Добавить плагин (.js)" : "Add plugin (.js)"))
    id += 1
    entries.append(.createJsAction(id: id, text: lang == "ru" ? "Редактор кода" : "Code Editor"))
    id += 1
    entries.append(.listHeader(id: id, text: lang == "ru" ? "УСТАНОВЛЕННЫЕ ПЛАГИНЫ" : "INSTALLED PLUGINS"))
    id += 1
    for plugin in plugins {
        let meta = plugin.metadata
        entries.append(.pluginRow(id: id, plugin: plugin))
        id += 1
        if plugin.hasSettings {
            entries.append(.pluginSettings(id: id, pluginId: meta.id, text: lang == "ru" ? "Настройки" : "Settings"))
            id += 1
        }
        entries.append(.pluginEditCode(id: id, pluginId: meta.id, text: lang == "ru" ? "Редактировать код" : "Edit code"))
        id += 1
        entries.append(.pluginDelete(id: id, pluginId: meta.id, text: lang == "ru" ? "Удалить" : "Remove"))
        id += 1
    }
    if plugins.isEmpty {
        entries.append(.emptyNotice(id: id, text: lang == "ru" ? "Нет установленных плагинов." : "No installed plugins."))
    }
    return entries
}

public func PluginListController(context: AccountContext, onPluginsChanged: @escaping () -> Void) -> ViewController {
    let reloadPromise = ValuePromise(true, ignoreRepeated: false)
    var presentJsPicker: (() -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?
    var backAction: (() -> Void)?

    let arguments = PluginListArguments(
        setPluginSystemEnabled: { value in
            SGSimpleSettings.shared.pluginSystemEnabled = value
            if value {
                PluginRunner.shared.ensureLoaded()
            } else {
                PluginRunner.shared.shutdown()
            }
            reloadPromise.set(true)
            onPluginsChanged()
        },
        toggle: { pluginId, value in
            var plugins = loadInstalledPlugins()
            if let idx = plugins.firstIndex(where: { $0.metadata.id == pluginId }) {
                let isJs = (plugins[idx].path as NSString).pathExtension.lowercased() == "js"
                if isJs && !value {
                    PluginRunner.shared.unload(pluginId: pluginId)
                }
                plugins[idx].enabled = value
                saveInstalledPlugins(plugins)
                if isJs && value {
                    PluginRunner.shared.ensureLoaded()
                }
                reloadPromise.set(true)
                onPluginsChanged()
            }
        },
        openSettings: { pluginId in
            let plugins = loadInstalledPlugins()
            guard let plugin = plugins.first(where: { $0.metadata.id == pluginId }) else { return }
            let settingsController = PluginSettingsController(context: context, plugin: plugin, onSave: {
                reloadPromise.set(true)
                onPluginsChanged()
            })
            pushControllerImpl?(settingsController)
        },
        deletePlugin: { pluginId in
            PluginRunner.shared.unload(pluginId: pluginId)
            var plugins = loadInstalledPlugins()
            plugins.removeAll { $0.metadata.id == pluginId }
            saveInstalledPlugins(plugins)
            reloadPromise.set(true)
            onPluginsChanged()
        },
        addJsPlugin: { presentJsPicker?() },
        createJsPlugin: {
            let editor = pluginCodeEditorController(context: context, existingPlugin: nil, initialCode: "", onSave: { _ in
                reloadPromise.set(true)
                onPluginsChanged()
            })
            pushControllerImpl?(editor)
        },
        editPluginCode: { pluginId in
            let plugins = loadInstalledPlugins()
            guard let plugin = plugins.first(where: { $0.metadata.id == pluginId }) else { return }
            let code = (try? String(contentsOfFile: plugin.path, encoding: .utf8)) ?? ""
            let editor = pluginCodeEditorController(context: context, existingPlugin: plugin, initialCode: code, onSave: { _ in
                reloadPromise.set(true)
                onPluginsChanged()
            })
            pushControllerImpl?(editor)
        },
        iconResolver: { iconRef in
            guard let ref = iconRef, !ref.isEmpty else { return nil }
            if let img = UIImage(bundleImageName: ref) { return img }
            return UIImage(bundleImageName: "glePlugins/1")
        }
    )
    
    let signal = combineLatest(reloadPromise.get(), context.sharedContext.presentationData)
    |> map { _, presentationData -> (ItemListControllerState, (ItemListNodeState, PluginListArguments)) in
        let plugins = loadInstalledPlugins()
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(presentationData.strings.baseLanguageCode == "ru" ? "Плагины" : "Plugins"),
            leftNavigationButton: ItemListNavigationButton(content: .text(presentationData.strings.Common_Back), style: .regular, enabled: true, action: { backAction?() }),
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let entries = pluginListEntries(presentationData: presentationData, plugins: plugins)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, ensureVisibleItemTag: nil, initialScrollToItem: nil)
        return (controllerState, (listState, arguments))
    }
    
    let controller = ItemListController(context: context, state: signal)
    backAction = { [weak controller] in controller?.dismiss() }

    presentJsPicker = { [weak controller] in
        guard let controller = controller else { return }
        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            let jsType = UTType(filenameExtension: "js") ?? .plainText
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [jsType], asCopy: true)
        } else {
            picker = UIDocumentPickerViewController(documentTypes: ["public.javascript", "public.plain-text"], in: .import)
        }
        let delegate = PluginDocumentPickerDelegate(
            context: context,
            onPick: { url in
                _ = url.startAccessingSecurityScopedResource()
                defer { url.stopAccessingSecurityScopedResource() }
                let content = try? String(contentsOf: url, encoding: .utf8)
                let fileName = url.lastPathComponent
                let metadata: PluginMetadata
                if let content = content, let parsed = PluginMetadataParser.parseJavaScript(content: content) {
                    metadata = parsed
                } else {
                    let id = (fileName as NSString).deletingPathExtension
                    let name = id.isEmpty ? fileName : id
                    metadata = PluginMetadata(id: id.isEmpty ? "plugin_\(UUID().uuidString.prefix(8))" : id, name: name, description: "", version: "1.0", author: "", iconRef: nil, minVersion: nil, hasUserDisplay: false)
                }
                let fileManager = FileManager.default
                guard let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
                let pluginsDir = supportURL.appendingPathComponent("Plugins", isDirectory: true)
                try? fileManager.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
                let destURL = pluginsDir.appendingPathComponent("\(metadata.id).js")
                try? fileManager.removeItem(at: destURL)
                try? fileManager.copyItem(at: url, to: destURL)
                var plugins = loadInstalledPlugins()
                plugins.append(PluginInfo(metadata: metadata, path: destURL.path, enabled: true, hasSettings: false))
                saveInstalledPlugins(plugins)
                PluginRunner.shared.ensureLoaded()
                reloadPromise.set(true)
                onPluginsChanged()
            }
        )
        picker.delegate = delegate
        objc_setAssociatedObject(picker, &documentPickerDelegateKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        controller.present(picker, animated: true)
    }
    pushControllerImpl = { [weak controller] vc in controller?.push(vc) }

    return controller
}

private final class PluginDocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    let context: AccountContext
    let onPick: (URL) -> Void
    init(context: AccountContext, onPick: @escaping (URL) -> Void) {
        self.context = context
        self.onPick = onPick
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        onPick(url)
    }
}

```

### `LuxGram/SGSettingsUI/Sources/PluginCodeEditorController.swift`

```swift
// MARK: LuxGram – Plugin code editor (create/edit JS plugins inline)
import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import SGSimpleSettings

// MARK: - State

private final class PluginCodeEditorStateHolder {
    var name: String
    var code: String
    init(name: String, code: String) {
        self.name = name
        self.code = code
    }
}

private struct PluginCodeEditorState: Equatable {
    var name: String
    var code: String
}

// MARK: - Entries

private enum PluginCodeEditorEntry: ItemListNodeEntry {
    case nameInput(id: Int, text: String, placeholder: String)
    case codeInput(id: Int, text: String, placeholder: String)
    case notice(id: Int, text: String)

    var section: ItemListSectionId {
        switch self {
        case .nameInput: return 0
        case .codeInput: return 1
        case .notice: return 2
        }
    }

    var stableId: Int {
        switch self {
        case .nameInput(let id, _, _): return id
        case .codeInput(let id, _, _): return id
        case .notice(let id, _): return id
        }
    }

    static func == (lhs: PluginCodeEditorEntry, rhs: PluginCodeEditorEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.nameInput(a, t1, p1), .nameInput(b, t2, p2)): return a == b && t1 == t2 && p1 == p2
        case let (.codeInput(a, t1, p1), .codeInput(b, t2, p2)): return a == b && t1 == t2 && p1 == p2
        case let (.notice(a, t1), .notice(b, t2)): return a == b && t1 == t2
        default: return false
        }
    }

    static func < (lhs: PluginCodeEditorEntry, rhs: PluginCodeEditorEntry) -> Bool {
        lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! PluginCodeEditorArguments
        switch self {
        case .nameInput(_, let text, let placeholder):
            return ItemListSingleLineInputItem(
                presentationData: presentationData,
                title: NSAttributedString(),
                text: text,
                placeholder: placeholder,
                sectionId: section,
                textUpdated: { newText in args.updatedName(newText) },
                action: {}
            )
        case .codeInput(_, let text, let placeholder):
            return ItemListMultilineInputItem(
                presentationData: presentationData,
                text: text,
                placeholder: placeholder,
                maxLength: nil,
                sectionId: section,
                style: .blocks,
                textUpdated: { newText in args.updatedCode(newText) },
                updatedFocus: nil,
                tag: nil,
                action: nil,
                inlineAction: nil
            )
        case .notice(_, let text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        }
    }
}

// MARK: - Arguments

private final class PluginCodeEditorArguments {
    var updatedName: (String) -> Void = { _ in }
    var updatedCode: (String) -> Void = { _ in }
}

private final class PluginCodeEditorNavActions {
    var cancel: (() -> Void)?
    var done: (() -> Void)?
}

// MARK: - Entries builder

private func pluginCodeEditorEntries(state: PluginCodeEditorState, presentationData: PresentationData) -> [PluginCodeEditorEntry] {
    let lang = presentationData.strings.baseLanguageCode
    var entries: [PluginCodeEditorEntry] = []
    entries.append(.nameInput(id: 0, text: state.name, placeholder: lang == "ru" ? "Имя плагина" : "Plugin name"))
    entries.append(.codeInput(id: 1, text: state.code, placeholder: lang == "ru" ? "JavaScript код..." : "JavaScript code..."))
    let noticeText = lang == "ru"
        ? "Используйте LuxGram.ui, LuxGram.chat, LuxGram.compose, LuxGram.messageActions, LuxGram.intercept, LuxGram.network, LuxGram.settings, LuxGram.events API."
        : "Use LuxGram.ui, LuxGram.chat, LuxGram.compose, LuxGram.messageActions, LuxGram.intercept, LuxGram.network, LuxGram.settings, LuxGram.events API."
    entries.append(.notice(id: 2, text: noticeText))
    return entries
}

// MARK: - Controller

public func pluginCodeEditorController(context: AccountContext, existingPlugin: PluginInfo?, initialCode: String, onSave: @escaping (PluginInfo) -> Void) -> ViewController {
    let initialName = existingPlugin?.metadata.name ?? ""
    let stateHolder = PluginCodeEditorStateHolder(name: initialName, code: initialCode)
    let navActions = PluginCodeEditorNavActions()
    let statePromise = ValuePromise(PluginCodeEditorState(name: initialName, code: initialCode), ignoreRepeated: true)
    let arguments = PluginCodeEditorArguments()

    arguments.updatedName = { newName in
        stateHolder.name = newName
        statePromise.set(PluginCodeEditorState(name: newName, code: stateHolder.code))
    }
    arguments.updatedCode = { newCode in
        stateHolder.code = newCode
        statePromise.set(PluginCodeEditorState(name: stateHolder.name, code: newCode))
    }

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, PluginCodeEditorArguments)) in
        let lang = presentationData.strings.baseLanguageCode
        let title = existingPlugin != nil
            ? (lang == "ru" ? "Редактор" : "Editor")
            : (lang == "ru" ? "Новый плагин" : "New Plugin")
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(title),
            leftNavigationButton: ItemListNavigationButton(content: .text(presentationData.strings.Common_Cancel), style: .regular, enabled: true, action: { navActions.cancel?() }),
            rightNavigationButton: ItemListNavigationButton(content: .text(lang == "ru" ? "Сохранить" : "Save"), style: .bold, enabled: !state.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, action: { navActions.done?() }),
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let entries = pluginCodeEditorEntries(state: state, presentationData: presentationData)
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

    navActions.cancel = { [weak controller] in
        controller?.dismiss()
    }

    navActions.done = { [weak controller] in
        let code = stateHolder.code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }

        // Parse metadata from code
        var metadata: PluginMetadata
        if let parsed = PluginMetadataParser.parseJavaScript(content: code) {
            metadata = parsed
        } else {
            let name = stateHolder.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let safeName = name.isEmpty ? "Untitled Plugin" : name
            let safeId = existingPlugin?.metadata.id ?? safeName.lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .filter { $0.isLetter || $0.isNumber || $0 == "-" }
            let id = safeId.isEmpty ? "plugin-\(UUID().uuidString.prefix(8))" : safeId
            metadata = PluginMetadata(id: id, name: safeName, description: "", version: "1.0", author: "")
        }

        // If editing, keep the same ID
        if let existing = existingPlugin {
            metadata = PluginMetadata(
                id: existing.metadata.id,
                name: metadata.name,
                description: metadata.description,
                version: metadata.version,
                author: metadata.author,
                iconRef: metadata.iconRef,
                minVersion: metadata.minVersion,
                hasUserDisplay: metadata.hasUserDisplay,
                permissions: metadata.permissions
            )
        }

        // Write file
        let fileManager = FileManager.default
        guard let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let pluginsDir = supportURL.appendingPathComponent("Plugins", isDirectory: true)
        try? fileManager.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
        let destURL = pluginsDir.appendingPathComponent("\(metadata.id).js")
        try? code.write(to: destURL, atomically: true, encoding: .utf8)

        // Unload old version if editing
        if existingPlugin != nil {
            PluginRunner.shared.unload(pluginId: metadata.id)
        }

        // Update installed list
        let pluginInfo = PluginInfo(metadata: metadata, path: destURL.path, enabled: true, hasSettings: false)
        var plugins: [PluginInfo]
        if let data = SGSimpleSettings.shared.installedPluginsJson.data(using: .utf8),
           let existing = try? JSONDecoder().decode([PluginInfo].self, from: data) {
            plugins = existing
        } else {
            plugins = []
        }
        plugins.removeAll { $0.metadata.id == metadata.id }
        plugins.append(pluginInfo)
        if let data = try? JSONEncoder().encode(plugins),
           let json = String(data: data, encoding: .utf8) {
            SGSimpleSettings.shared.installedPluginsJson = json
            SGSimpleSettings.shared.synchronizeShared()
        }

        // Reload plugins
        PluginRunner.shared.ensureLoaded()
        onSave(pluginInfo)
        controller?.dismiss()
    }

    return controller
}

```

### `LuxGram/SGSettingsUI/Sources/PluginInstallPopupController.swift`

```swift
// MARK: LuxGram – Plugin install popup (tap .plugin file in chat)
import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import SGSimpleSettings
import AppBundle

private func loadInstalledPlugins() -> [PluginInfo] {
    guard let data = SGSimpleSettings.shared.installedPluginsJson.data(using: .utf8),
          let list = try? JSONDecoder().decode([PluginInfo].self, from: data) else {
        return []
    }
    return list
}

private func saveInstalledPlugins(_ plugins: [PluginInfo]) {
    if let data = try? JSONEncoder().encode(plugins),
       let json = String(data: data, encoding: .utf8) {
        SGSimpleSettings.shared.installedPluginsJson = json
        SGSimpleSettings.shared.synchronizeShared()
    }
}

/// Modal popup when user taps a .plugin file in chat: shows plugin info and "Install" button.
public final class PluginInstallPopupController: ViewController {
    private let context: AccountContext
    private let message: Message
    private let file: TelegramMediaFile
    private var onInstalled: (() -> Void)?
    
    private var loadDisposable: Disposable?
    private var state: State = .loading {
        didSet { applyState() }
    }
    
    private enum State {
        case loading
        case loaded(metadata: PluginMetadata, hasSettings: Bool, filePath: String)
        case error(String)
    }
    
    private let contentNode: PluginInstallPopupContentNode
    
    public init(context: AccountContext, message: Message, file: TelegramMediaFile, onInstalled: (() -> Void)? = nil) {
        self.context = context
        self.message = message
        self.file = file
        self.onInstalled = onInstalled
        self.contentNode = PluginInstallPopupContentNode()
        super.init(navigationBarPresentationData: nil)
        self.blocksBackgroundWhenInOverlay = true
    }
    
    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        loadDisposable?.dispose()
    }
    
    override public func loadDisplayNode() {
        self.displayNode = contentNode
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        contentNode.backgroundColor = presentationData.theme.list.itemBlocksBackgroundColor
        contentNode.controller = self
        contentNode.installAction = { [weak self] enableAfterInstall in
            self?.performInstall(enableAfterInstall: enableAfterInstall)
        }
        contentNode.closeAction = { [weak self] in
            self?.dismiss()
        }
        contentNode.shareAction = { [weak self] in
            self?.sharePlugin()
        }
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: presentationData.strings.Common_Close, style: .plain, target: self, action: #selector(closeTapped))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareTapped))
        applyState()
        startLoading()
    }
    
    @objc private func closeTapped() {
        dismiss()
    }
    
    @objc private func shareTapped() {
        sharePlugin()
    }
    
    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    private func startLoading() {
        let postbox = context.account.postbox
        let resource = file.resource
        loadDisposable?.dispose()
        loadDisposable = (postbox.mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: true))
            |> filter { $0.complete }
            |> take(1)
            |> deliverOnMainQueue
        ).start(next: { [weak self] data in
            guard let self = self else { return }
            guard let content = try? String(contentsOfFile: data.path, encoding: .utf8) else {
                self.state = .error("Не удалось прочитать файл")
                return
            }
            guard let metadata = currentPluginRuntime.parseMetadata(content: content) else {
                self.state = .error("Неверный формат плагина")
                return
            }
            let hasSettings = currentPluginRuntime.hasCreateSettings(content: content)
            self.state = .loaded(metadata: metadata, hasSettings: hasSettings, filePath: data.path)
        })
    }
    
    private func applyState() {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        switch state {
        case .loading:
            contentNode.setLoading(presentationData: presentationData)
        case .loaded(let metadata, let hasSettings, _):
            contentNode.setLoaded(presentationData: presentationData, metadata: metadata, hasSettings: hasSettings)
        case .error(let message):
            contentNode.setError(presentationData: presentationData, message: message, retry: { [weak self] in
                self?.state = .loading
                self?.startLoading()
            })
        }
    }
    
    private func performInstall(enableAfterInstall: Bool) {
        guard case .loaded(let metadata, let hasSettings, let filePath) = state else { return }
        let fileManager = FileManager.default
        guard let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let pluginsDir = supportURL.appendingPathComponent("Plugins", isDirectory: true)
        let destPath = pluginsDir.appendingPathComponent("\(metadata.id).plugin").path
        do {
            try fileManager.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
            let destURL = URL(fileURLWithPath: destPath)
            try? fileManager.removeItem(at: destURL)
            try fileManager.copyItem(at: URL(fileURLWithPath: filePath), to: destURL)
        } catch {
            contentNode.showError("Не удалось установить: \(error.localizedDescription)")
            return
        }
        var plugins = loadInstalledPlugins()
        plugins.removeAll { $0.metadata.id == metadata.id }
        plugins.append(PluginInfo(metadata: metadata, path: destPath, enabled: enableAfterInstall, hasSettings: hasSettings))
        saveInstalledPlugins(plugins)
        onInstalled?()
        dismiss()
    }
    
    private func sharePlugin() {
        guard case .loaded(_, _, let filePath) = state else { return }
        let url = URL(fileURLWithPath: filePath)
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let window = self.view.window, let root = window.rootViewController {
            var top = root
            while let presented = top.presentedViewController { top = presented }
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = view
                popover.sourceRect = CGRect(x: view.bounds.midX, y: 60, width: 0, height: 0)
                popover.permittedArrowDirections = .up
            }
            top.present(activityVC, animated: true)
        }
    }
}

// MARK: - Content node (icon, name, version, description, Install, checkbox)
private final class PluginInstallPopupContentNode: ViewControllerTracingNode {
    weak var controller: PluginInstallPopupController?
    var installAction: ((Bool) -> Void)?
    var closeAction: (() -> Void)?
    var shareAction: (() -> Void)?
    var retryBlock: (() -> Void)?
    
    private let scrollNode = ASScrollNode()
    private let iconNode = ASImageNode()
    private let nameNode = ImmediateTextNode()
    private let versionNode = ImmediateTextNode()
    private let descriptionNode = ImmediateTextNode()
    private let installButton = ASButtonNode()
    private let enableAfterContainer = ASDisplayNode()
    private let enableAfterLabel = ImmediateTextNode()
    private let loadingNode = ASDisplayNode()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let errorLabel = ImmediateTextNode()
    private let retryButton = ASButtonNode()
    
    private var enableAfterInstall: Bool = true
    private var currentMetadata: PluginMetadata?
    private var switchView: UISwitch?
    
    override init() {
        super.init()
        addSubnode(scrollNode)
        scrollNode.addSubnode(iconNode)
        scrollNode.addSubnode(nameNode)
        scrollNode.addSubnode(versionNode)
        scrollNode.addSubnode(descriptionNode)
        scrollNode.addSubnode(installButton)
        scrollNode.addSubnode(enableAfterContainer)
        scrollNode.addSubnode(enableAfterLabel)
        addSubnode(loadingNode)
        addSubnode(errorLabel)
        addSubnode(retryButton)
        iconNode.contentMode = .scaleAspectFit
        installButton.addTarget(self, action: #selector(installTapped), forControlEvents: .touchUpInside)
        retryButton.addTarget(self, action: #selector(retryTapped), forControlEvents: .touchUpInside)
    }
    
    func setLoading(presentationData: PresentationData) {
        backgroundColor = presentationData.theme.list.itemBlocksBackgroundColor
        loadingNode.isHidden = false
        loadingNode.view.addSubview(loadingIndicator)
        loadingIndicator.startAnimating()
        scrollNode.isHidden = true
        errorLabel.isHidden = true
        retryButton.isHidden = true
    }
    
    func setLoaded(presentationData: PresentationData, metadata: PluginMetadata, hasSettings: Bool) {
        backgroundColor = presentationData.theme.list.itemBlocksBackgroundColor
        currentMetadata = metadata
        loadingNode.isHidden = true
        loadingIndicator.stopAnimating()
        errorLabel.isHidden = true
        retryButton.isHidden = true
        scrollNode.isHidden = false
        
        let theme = presentationData.theme
        let lang = presentationData.strings.baseLanguageCode
        let isRu = lang == "ru"
        
        iconNode.image = (metadata.iconRef.flatMap { UIImage(bundleImageName: $0) }) ?? UIImage(bundleImageName: "glePlugins/1")
        
        nameNode.attributedText = NSAttributedString(string: metadata.name, font: Font.bold(22), textColor: theme.list.itemPrimaryTextColor)
        nameNode.maximumNumberOfLines = 1
        nameNode.truncationMode = .byTruncatingTail
        
        let versionAuthor = (isRu ? "Версия " : "Version ") + "\(metadata.version)" + (metadata.author.isEmpty ? "" : " • \(metadata.author)")
        versionNode.attributedText = NSAttributedString(string: versionAuthor, font: Font.regular(15), textColor: theme.list.itemSecondaryTextColor)
        versionNode.maximumNumberOfLines = 1
        
        descriptionNode.attributedText = NSAttributedString(string: metadata.description.isEmpty ? (isRu ? "Нет описания." : "No description.") : metadata.description, font: Font.regular(15), textColor: theme.list.itemPrimaryTextColor)
        descriptionNode.maximumNumberOfLines = 6
        descriptionNode.truncationMode = .byTruncatingTail
        
        installButton.setTitle(isRu ? "Установить" : "Install", with: Font.semibold(17), with: .white, for: .normal)
        installButton.backgroundColor = theme.list.itemAccentColor
        installButton.cornerRadius = 12
        installButton.contentEdgeInsets = UIEdgeInsets(top: 14, left: 24, bottom: 14, right: 24)
        
        enableAfterLabel.attributedText = NSAttributedString(string: isRu ? "Включить после установки" : "Enable after installation", font: Font.regular(16), textColor: theme.list.itemPrimaryTextColor)
        enableAfterLabel.maximumNumberOfLines = 1
        
        if switchView == nil {
            let sw = UISwitch()
            sw.isOn = enableAfterInstall
            sw.addTarget(self, action: #selector(enableAfterChanged(_:)), for: .valueChanged)
            enableAfterContainer.view.addSubview(sw)
            switchView = sw
        }
        switchView?.isOn = enableAfterInstall
        
        layoutContent()
    }
    
    @objc private func enableAfterChanged(_ sender: UISwitch) {
        enableAfterInstall = sender.isOn
    }
    
    func setError(presentationData: PresentationData, message: String, retry: @escaping () -> Void) {
        backgroundColor = presentationData.theme.list.itemBlocksBackgroundColor
        retryBlock = retry
        currentMetadata = nil
        loadingNode.isHidden = true
        scrollNode.isHidden = true
        errorLabel.isHidden = false
        retryButton.isHidden = false
        errorLabel.attributedText = NSAttributedString(string: message, font: Font.regular(16), textColor: presentationData.theme.list.itemDestructiveColor)
        let retryTitle = (presentationData.strings.baseLanguageCode == "ru" ? "Повторить" : "Retry")
        retryButton.setTitle(retryTitle, with: Font.regular(17), with: presentationData.theme.list.itemAccentColor, for: .normal)
        layoutContent()
    }
    
    func showError(_ message: String) {
        errorLabel.attributedText = NSAttributedString(string: message, font: Font.regular(16), textColor: .red)
        errorLabel.isHidden = false
        errorLabel.frame = CGRect(x: 24, y: 120, width: bounds.width - 48, height: 60)
    }
    
    @objc private func installTapped() {
        installAction?(enableAfterInstall)
    }
    
    @objc private func retryTapped() {
        guard let retry = retryBlock else { return }
        retry()
    }
    
    private func layoutContent() {
        let b = bounds
        let w = b.width > 0 ? b.width : 320
        let pad: CGFloat = 24
        
        loadingIndicator.center = CGPoint(x: b.midX, y: b.midY)
        loadingNode.frame = b
        errorLabel.frame = CGRect(x: pad, y: b.midY - 40, width: w - pad * 2, height: 60)
        retryButton.frame = CGRect(x: pad, y: b.midY + 20, width: w - pad * 2, height: 44)
        
        scrollNode.frame = b
        let contentW = w - pad * 2
        
        iconNode.frame = CGRect(x: pad, y: 20, width: 56, height: 56)
        
        nameNode.frame = CGRect(x: pad, y: 86, width: contentW, height: 28)
        
        versionNode.frame = CGRect(x: pad, y: 118, width: contentW, height: 22)
        
        let descY: CGFloat = 150
        let descMaxH: CGFloat = 80
        if let att = descriptionNode.attributedText {
            let descSize = att.boundingRect(with: CGSize(width: contentW, height: descMaxH), options: .usesLineFragmentOrigin, context: nil).size
            descriptionNode.frame = CGRect(x: pad, y: descY, width: contentW, height: min(descMaxH, ceil(descSize.height)))
        } else {
            descriptionNode.frame = CGRect(x: pad, y: descY, width: contentW, height: 22)
        }
        
        let buttonY: CGFloat = 240
        installButton.frame = CGRect(x: pad, y: buttonY, width: contentW, height: 50)
        
        let rowY: CGFloat = 306
        let switchW: CGFloat = 51
        let switchH: CGFloat = 31
        enableAfterLabel.frame = CGRect(x: pad, y: rowY, width: contentW - switchW - 12, height: 24)
        enableAfterContainer.frame = CGRect(x: w - pad - switchW, y: rowY, width: switchW, height: switchH)
        switchView?.frame = CGRect(origin: .zero, size: CGSize(width: switchW, height: switchH))
        
        let contentHeight: CGFloat = 360
        scrollNode.view.contentSize = CGSize(width: w, height: contentHeight)
    }
    
    override func layout() {
        super.layout()
        layoutContent()
    }
}


```

### `LuxGram/SGSettingsUI/Sources/PluginSettingsController.swift`

```swift
// MARK: LuxGram – Plugin settings screen
import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import SGSimpleSettings
import SGItemListUI

private func loadInstalledPlugins() -> [PluginInfo] {
    guard let data = SGSimpleSettings.shared.installedPluginsJson.data(using: .utf8),
          let list = try? JSONDecoder().decode([PluginInfo].self, from: data) else {
        return []
    }
    return list
}

private func saveInstalledPlugins(_ plugins: [PluginInfo]) {
    if let data = try? JSONEncoder().encode(plugins),
       let json = String(data: data, encoding: .utf8) {
        SGSimpleSettings.shared.installedPluginsJson = json
        SGSimpleSettings.shared.synchronizeShared()
    }
}

private enum PluginSettingsSection: Int32, SGItemListSection {
    case main
    case pluginOptions
    case info
}

private typealias PluginSettingsEntry = SGItemListUIEntry<PluginSettingsSection, SGBoolSetting, AnyHashable, AnyHashable, AnyHashable, AnyHashable>

private let userDisplayBoolKeys: [(key: String, titleRu: String, titleEn: String)] = [
    ("enabled", "Включить подмену профиля", "Enable profile override"),
    ("fake_premium", "Premium статус", "Premium status"),
    ("fake_verified", "Статус верификации", "Verified status"),
    ("fake_scam", "Scam статус", "Scam status"),
    ("fake_fake", "Fake статус", "Fake status"),
    ("fake_support", "Support статус", "Support status"),
    ("fake_bot", "Bot статус", "Bot status"),
]

private let userDisplayStringKeys: [(key: String, titleRu: String, titleEn: String)] = [
    ("target_user_id", "Telegram ID пользователя", "User Telegram ID"),
    ("fake_first_name", "Имя", "First name"),
    ("fake_last_name", "Фамилия", "Last name"),
    ("fake_username", "Юзернейм (без @)", "Username (no @)"),
    ("fake_phone", "Номер телефона", "Phone number"),
    ("fake_id", "Telegram ID (визуально)", "Telegram ID (display)"),
]

private func pluginSettingsEntries(presentationData: PresentationData, plugin: PluginInfo) -> [PluginSettingsEntry] {
    let lang = presentationData.strings.baseLanguageCode
    let isRu = lang == "ru"
    var entries: [PluginSettingsEntry] = []
    let id = SGItemListCounter()
    let host = PluginHost.shared
    let pluginId = plugin.metadata.id

    entries.append(.header(id: id.count, section: .main, text: isRu ? "ПЛАГИН" : "PLUGIN", badge: nil))
    let enableText = plugin.enabled ? (isRu ? "Выключить плагин" : "Disable plugin") : (isRu ? "Включить плагин" : "Enable plugin")
    entries.append(.action(id: id.count, section: .main, actionType: "toggleEnabled" as AnyHashable, text: enableText, kind: .generic))
    entries.append(.notice(id: id.count, section: .main, text: isRu ? "Включает функциональность плагина." : "Enables plugin functionality."))

    if plugin.metadata.hasUserDisplay {
        entries.append(.header(id: id.count, section: .pluginOptions, text: isRu ? "НАСТРОЙКИ ОТОБРАЖЕНИЯ" : "DISPLAY SETTINGS", badge: nil))
        entries.append(.notice(id: id.count, section: .pluginOptions, text: isRu ? "Оставьте поля пустыми, чтобы использовать реальные данные. Пустой «Telegram ID пользователя» — свой профиль." : "Leave fields empty to use real data. Empty «User Telegram ID» means your own profile."))
        for item in userDisplayBoolKeys {
            let value = host.getPluginSettingBool(pluginId: pluginId, key: item.key, default: false)
            let label = value ? (isRu ? "Вкл" : "On") : (isRu ? "Выкл" : "Off")
            let text = "\(isRu ? item.titleRu : item.titleEn): \(label)"
            entries.append(.action(id: id.count, section: .pluginOptions, actionType: "pluginBool:\(item.key)" as AnyHashable, text: text, kind: .generic))
        }
        for item in userDisplayStringKeys {
            let value = host.getPluginSetting(pluginId: pluginId, key: item.key) ?? ""
            let label = value.isEmpty ? (isRu ? "—" : "—") : value
            let text = "\(isRu ? item.titleRu : item.titleEn): \(label)"
            entries.append(.action(id: id.count, section: .pluginOptions, actionType: "pluginString:\(item.key)" as AnyHashable, text: text, kind: .generic))
        }
    } else if plugin.hasSettings {
        entries.append(.header(id: id.count, section: .pluginOptions, text: isRu ? "НАСТРОЙКИ" : "SETTINGS", badge: nil))
        entries.append(.notice(id: id.count, section: .pluginOptions, text: isRu ? "Настройки этого плагина задаются в файле .plugin (create_settings). Редактор для других типов плагинов в разработке." : "Settings for this plugin are defined in the .plugin file (create_settings). Editor for other plugin types coming later."))
    }

    entries.append(.header(id: id.count, section: .info, text: isRu ? "ИНФОРМАЦИЯ" : "INFORMATION", badge: nil))
    entries.append(PluginSettingsEntry.notice(id: id.count, section: .info, text: "\(plugin.metadata.name)\n\(isRu ? "Версия" : "Version") \(plugin.metadata.version)\n\(plugin.metadata.author)\n\n\(plugin.metadata.description)"))
    return entries
}

public func PluginSettingsController(context: AccountContext, plugin: PluginInfo, onSave: @escaping () -> Void) -> ViewController {
    let reloadPromise = ValuePromise(true, ignoreRepeated: false)
    var backAction: (() -> Void)?
    var presentAlertImpl: ((String, String, String, @escaping (String) -> Void) -> Void)?
    let pluginId = plugin.metadata.id
    let host = PluginHost.shared

    let arguments = SGItemListArguments<SGBoolSetting, AnyHashable, AnyHashable, AnyHashable, AnyHashable>(
        context: context,
        setBoolValue: { _, _ in },
        updateSliderValue: { _, _ in },
        setOneFromManyValue: { _ in },
        openDisclosureLink: { _ in },
        action: { actionType in
            guard let s = actionType as? String else { return }
            if s == "toggleEnabled" {
                var plugins = loadInstalledPlugins()
                if let idx = plugins.firstIndex(where: { $0.metadata.id == pluginId }) {
                    plugins[idx].enabled.toggle()
                    saveInstalledPlugins(plugins)
                    reloadPromise.set(true)
                    onSave()
                }
            } else if s.hasPrefix("pluginBool:") {
                let key = String(s.dropFirst("pluginBool:".count))
                let current = host.getPluginSettingBool(pluginId: pluginId, key: key, default: false)
                host.setPluginSettingBool(pluginId: pluginId, key: key, value: !current)
                reloadPromise.set(true)
                onSave()
            } else if s.hasPrefix("pluginString:") {
                let key = String(s.dropFirst("pluginString:".count))
                let current = host.getPluginSetting(pluginId: pluginId, key: key) ?? ""
                let titleRu = userDisplayStringKeys.first(where: { $0.key == key })?.titleRu ?? key
                let titleEn = userDisplayStringKeys.first(where: { $0.key == key })?.titleEn ?? key
                let lang = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
                let title = lang == "ru" ? titleRu : titleEn
                presentAlertImpl?(key, title, current) { newValue in
                    host.setPluginSetting(pluginId: pluginId, key: key, value: newValue)
                    reloadPromise.set(true)
                    onSave()
                }
            }
        },
        searchInput: { _ in }
    )

    let signal = combineLatest(
        reloadPromise.get(),
        context.sharedContext.presentationData
    )
    |> map { _, presentationData -> (ItemListControllerState, (ItemListNodeState, SGItemListArguments<SGBoolSetting, AnyHashable, AnyHashable, AnyHashable, AnyHashable>)) in
        let plugins = loadInstalledPlugins()
        let currentPlugin = plugins.first(where: { $0.metadata.id == plugin.metadata.id }) ?? plugin
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(currentPlugin.metadata.name),
            leftNavigationButton: ItemListNavigationButton(content: .text(presentationData.strings.Common_Back), style: .regular, enabled: true, action: { backAction?() }),
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let entries = pluginSettingsEntries(presentationData: presentationData, plugin: currentPlugin)
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
    backAction = { [weak controller] in controller?.dismiss() }

    presentAlertImpl = { [weak controller] key, title, currentValue, completion in
        guard let c = controller else { return }
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = currentValue
            tf.placeholder = title
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
        }
        let okTitle = context.sharedContext.currentPresentationData.with { $0 }.strings.Common_OK
        let cancelTitle = context.sharedContext.currentPresentationData.with { $0 }.strings.Common_Cancel
        alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel))
        alert.addAction(UIAlertAction(title: okTitle, style: .default) { _ in
            let newValue = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            completion(newValue)
        })
        c.present(alert, animated: true)
    }

    return controller
}

```

### `LuxGram/SGSettingsUI/Sources/PluginRunner.swift`

```swift
// MARK: LuxGram – JavaScript plugin runner (Ghostgram-style LuxGram.* API)
import Foundation
@preconcurrency import JavaScriptCore
import UIKit
import SGSimpleSettings

// MARK: - Plugin state

/// State for a single loaded JS plugin.
private final class JSPluginState {
    let context: JSContext
    var settingsItems: [(section: String, title: String, actionId: String, callback: JSValue)] = []
    var chatMenuItems: [(title: String, callback: JSValue)] = []
    var profileMenuItems: [(title: String, callback: JSValue)] = []
    var onOutgoingMessage: JSValue?
    var onIncomingMessage: JSValue?
    var onOpenChat: JSValue?
    var onOpenProfile: JSValue?
    var openUrlHandler: JSValue?
    var shouldShowMessage: JSValue?
    var eventHandlers: [(eventName: String, callback: JSValue)] = []

    init(context: JSContext) {
        self.context = context
    }
}

// MARK: - JS Bridge (Swift ↔ JavaScript)

/// JSExport protocol — all methods listed here are exposed to the JS runtime.
@objc private protocol LuxGramJSBridgeExport: JSExport {
    // ui
    func uiAlert(_ title: String, _ message: String)
    func uiPrompt(_ title: String, _ placeholder: String, _ callback: JSValue)
    func uiHaptic(_ style: String)
    func uiOpenURL(_ url: String)
    func uiToast(_ message: String)
    // compose
    func composeGetText() -> String
    func composeSetText(_ text: String)
    func composeInsertText(_ text: String)
    func composeOnSubmit(_ callback: JSValue)
    // message actions
    func messageActionsAddItem(_ title: String, _ callback: JSValue)
    // intercept
    func interceptOutgoing(_ callback: JSValue)
    func interceptIncoming(_ callback: JSValue)
    // network
    func networkFetch(_ url: String, _ opts: NSDictionary, _ callback: JSValue)
    // chat
    func chatGetActive() -> NSDictionary?
    func chatSend(_ peerId: Int64, _ text: String)
    func chatEdit(_ peerId: Int64, _ msgId: Int64, _ text: String)
    func chatDelete(_ peerId: Int64, _ msgId: Int64)
    // profile
    func profileAddAction(_ title: String, _ callback: JSValue)
    // settings
    func settingsAddItem(_ section: String, _ title: String, _ actionId: String, _ callback: JSValue)
    func storageGet(_ key: String) -> String?
    func storageSet(_ key: String, _ value: String)
    // events
    func eventsOn(_ name: String, _ callback: JSValue)
    func eventsEmit(_ name: String, _ params: NSDictionary)
    // ui extended
    func uiConfirm(_ title: String, _ message: String, _ callback: JSValue)
    func uiCopyToClipboard(_ text: String)
    func uiShare(_ text: String)
}

/// Bridge object exposed to JS as `_bridge`. All LuxGram.* methods call through here.
private final class LuxGramJSBridge: NSObject, LuxGramJSBridgeExport {
    @objc var pluginId: String = ""
    weak var runner: PluginRunner?

    // MARK: LuxGram.ui
    @objc func uiAlert(_ title: String, _ message: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let show = PluginHost.shared.showAlert {
                show(title, message)
            } else {
                let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
                let window = scene?.windows.first(where: { $0.isKeyWindow }) ?? UIApplication.shared.windows.first(where: { $0.isKeyWindow })
                if let root = window?.rootViewController {
                    var top = root
                    while let presented = top.presentedViewController {
                        top = presented
                    }
                    let alert = UIAlertController(title: title.isEmpty ? nil : title, message: message, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    top.present(alert, animated: true)
                }
            }
        }
    }

    @objc func uiPrompt(_ title: String, _ placeholder: String, _ callback: JSValue) {
        DispatchQueue.main.async {
            if let prompt = PluginHost.shared.showPrompt {
                prompt(title, placeholder) { result in
                    callback.call(withArguments: [result ?? NSNull()])
                }
            } else if let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }),
                      let root = window.rootViewController {
                let top = root.presentedViewController ?? root
                let alert = UIAlertController(title: title.isEmpty ? nil : title, message: nil, preferredStyle: .alert)
                alert.addTextField { tf in tf.placeholder = placeholder }
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                    callback.call(withArguments: [NSNull()])
                })
                alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                    let text = alert.textFields?.first?.text ?? ""
                    callback.call(withArguments: [text])
                })
                top.present(alert, animated: true)
            }
        }
    }

    @objc func uiHaptic(_ style: String) {
        PluginHost.shared.haptic?(style)
    }

    @objc func uiOpenURL(_ url: String) {
        DispatchQueue.main.async {
            if let openURL = PluginHost.shared.openURL {
                openURL(url)
            } else if let u = URL(string: url) {
                UIApplication.shared.open(u)
            }
        }
    }

    @objc func uiToast(_ message: String) {
        DispatchQueue.main.async {
            if let toast = PluginHost.shared.showToast {
                toast(message)
            } else {
                PluginHost.shared.showBulletin?(message, .info)
            }
        }
    }

    @objc func uiConfirm(_ title: String, _ message: String, _ callback: JSValue) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let confirm = PluginHost.shared.showConfirm {
                confirm(title, message) { result in
                    DispatchQueue.main.async { callback.call(withArguments: [result]) }
                }
            } else if let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }),
                      let root = window.rootViewController {
                let top = root.presentedViewController ?? root
                let alert = UIAlertController(title: title.isEmpty ? nil : title, message: message.isEmpty ? nil : message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in callback.call(withArguments: [true]) })
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in callback.call(withArguments: [false]) })
                top.present(alert, animated: true)
            }
        }
    }

    @objc func uiCopyToClipboard(_ text: String) {
        DispatchQueue.main.async {
            if let copy = PluginHost.shared.copyToClipboard {
                copy(text)
            } else {
                UIPasteboard.general.string = text
            }
        }
    }

    @objc func uiShare(_ text: String) {
        DispatchQueue.main.async {
            if let share = PluginHost.shared.shareText {
                share(text)
            } else if let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }),
                      let root = window.rootViewController {
                let top = root.presentedViewController ?? root
                let vc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
                top.present(vc, animated: true)
            }
        }
    }

    // MARK: LuxGram.compose
    @objc func composeGetText() -> String {
        return PluginHost.shared.getInputText?() ?? ""
    }

    @objc func composeSetText(_ text: String) {
        DispatchQueue.main.async {
            PluginHost.shared.setInputText?(text)
        }
    }

    @objc func composeInsertText(_ text: String) {
        DispatchQueue.main.async {
            if let insert = PluginHost.shared.insertText {
                insert(text)
            } else {
                // Fallback: append to existing text
                let current = PluginHost.shared.getInputText?() ?? ""
                PluginHost.shared.setInputText?(current + text)
            }
        }
    }

    @objc func composeOnSubmit(_ callback: JSValue) {
        guard !pluginId.isEmpty else { return }
        runner?.setOnSubmitCallback(pluginId: pluginId, callback: callback)
    }

    // MARK: LuxGram.messageActions
    @objc func messageActionsAddItem(_ title: String, _ callback: JSValue) {
        guard !pluginId.isEmpty, !callback.isUndefined, !callback.isNull else { return }
        runner?.addChatMenuItem(pluginId: pluginId, title: title, callback: callback)
    }

    // MARK: LuxGram.intercept
    @objc func interceptOutgoing(_ callback: JSValue) {
        guard !pluginId.isEmpty else { return }
        runner?.setOnOutgoingMessage(pluginId: pluginId, callback: callback)
    }

    @objc func interceptIncoming(_ callback: JSValue) {
        guard !pluginId.isEmpty else { return }
        runner?.setOnIncomingMessage(pluginId: pluginId, callback: callback)
    }

    // MARK: LuxGram.network
    @objc func networkFetch(_ url: String, _ opts: NSDictionary, _ callback: JSValue) {
        let method = opts["method"] as? String ?? "GET"
        let headers = opts["headers"] as? [String: String]
        let body = opts["body"] as? String
        PluginHost.shared.fetch?(url, method, headers, body) { error, data in
            DispatchQueue.main.async {
                if let error = error {
                    callback.call(withArguments: [error, NSNull()])
                } else {
                    callback.call(withArguments: [NSNull(), data ?? ""])
                }
            }
        }
    }

    // MARK: LuxGram.chat
    @objc func chatGetActive() -> NSDictionary? {
        guard let chat = PluginHost.shared.getCurrentChat?() else { return nil }
        return ["accountId": NSNumber(value: chat.accountId), "peerId": NSNumber(value: chat.peerId)]
    }

    @objc func chatSend(_ peerId: Int64, _ text: String) {
        guard let chat = PluginHost.shared.getCurrentChat?() else { return }
        PluginHost.shared.sendMessage?(chat.accountId, peerId, text, nil, nil)
    }

    @objc func chatEdit(_ peerId: Int64, _ msgId: Int64, _ text: String) {
        guard let chat = PluginHost.shared.getCurrentChat?() else { return }
        PluginHost.shared.editMessage?(chat.accountId, peerId, msgId, text)
    }

    @objc func chatDelete(_ peerId: Int64, _ msgId: Int64) {
        guard let chat = PluginHost.shared.getCurrentChat?() else { return }
        PluginHost.shared.deleteMessage?(chat.accountId, peerId, msgId)
    }

    // MARK: LuxGram.peerProfile
    @objc func profileAddAction(_ title: String, _ callback: JSValue) {
        guard !pluginId.isEmpty, !callback.isUndefined, !callback.isNull else { return }
        runner?.addProfileMenuItem(pluginId: pluginId, title: title, callback: callback)
    }

    // MARK: LuxGram.settings
    @objc func settingsAddItem(_ section: String, _ title: String, _ actionId: String, _ callback: JSValue) {
        guard !pluginId.isEmpty, !callback.isUndefined, !callback.isNull else { return }
        runner?.addSettingsItem(pluginId: pluginId, section: section, title: title, actionId: actionId, callback: callback)
    }

    @objc func storageGet(_ key: String) -> String? {
        guard !pluginId.isEmpty else { return nil }
        return PluginHost.shared.getPluginSetting(pluginId: pluginId, key: key)
    }

    @objc func storageSet(_ key: String, _ value: String) {
        guard !pluginId.isEmpty else { return }
        PluginHost.shared.setPluginSetting(pluginId: pluginId, key: key, value: value)
    }

    // MARK: LuxGram.events
    @objc func eventsOn(_ name: String, _ callback: JSValue) {
        guard !pluginId.isEmpty, !callback.isUndefined, !callback.isNull else { return }
        runner?.addEventListener(pluginId: pluginId, eventName: name, callback: callback)
    }

    @objc func eventsEmit(_ name: String, _ params: NSDictionary) {
        let dict = params as? [String: Any] ?? [:]
        _ = SGPluginHooks.emitEvent(name, dict)
    }
}

// MARK: - Plugin Runner

/// Singleton that manages JavaScript plugins via JavaScriptCore.
public final class PluginRunner {
    public static let shared = PluginRunner()

    private let queue = DispatchQueue(label: "LuxGramPluginRunner", qos: .userInitiated)
    private var loadedPlugins: [String: JSPluginState] = [:]
    private let lock = NSLock()
    private let loadLock = NSLock()
    private static var incomingMessageObserver: NSObjectProtocol?
    private static var technicalEventObserver: NSObjectProtocol?

    // MARK: - Bootstrap Script (LuxGram.* API)

    private static let bootstrapScript = """
    (function() {
        if (typeof LuxGram !== 'undefined') return;
        var b = (typeof _bridge !== 'undefined') ? _bridge : null;
        function s(v) { return v != null ? String(v) : ''; }
        LuxGram = {
            ui: {
                alert: function(title, msg) { if (b && b.uiAlert) b.uiAlert(s(title), s(msg)); },
                prompt: function(title, placeholder, cb) { if (b && b.uiPrompt && cb) b.uiPrompt(s(title), s(placeholder), cb); },
                haptic: function(style) { if (b && b.uiHaptic) b.uiHaptic(s(style) || 'light'); },
                openURL: function(url) { if (b && b.uiOpenURL) b.uiOpenURL(s(url)); },
                toast: function(msg) { if (b && b.uiToast) b.uiToast(s(msg)); },
                confirm: function(title, msg, cb) { if (b && b.uiConfirm && cb) b.uiConfirm(s(title), s(msg || ''), cb); },
                copyToClipboard: function(text) { if (b && b.uiCopyToClipboard) b.uiCopyToClipboard(s(text)); },
                share: function(text) { if (b && b.uiShare) b.uiShare(s(text)); }
            },
            compose: {
                getText: function() { return b && b.composeGetText ? b.composeGetText() : ''; },
                setText: function(text) { if (b && b.composeSetText) b.composeSetText(s(text)); },
                insertText: function(text) { if (b && b.composeInsertText) b.composeInsertText(s(text)); },
                onSubmit: function(cb) { if (b && b.composeOnSubmit) b.composeOnSubmit(cb); }
            },
            messageActions: {
                addItem: function(title, cb) { if (b && b.messageActionsAddItem && cb) b.messageActionsAddItem(s(title), cb); }
            },
            intercept: {
                outgoingMessage: function(cb) { if (b && b.interceptOutgoing) b.interceptOutgoing(cb); },
                incomingMessage: function(cb) { if (b && b.interceptIncoming) b.interceptIncoming(cb); }
            },
            network: {
                fetch: function(url, opts, cb) { if (b && b.networkFetch && cb) b.networkFetch(s(url), opts || {}, cb); }
            },
            chat: {
                getActiveChat: function() { return b && b.chatGetActive ? b.chatGetActive() : null; },
                sendMessage: function(peerId, text) { if (b && b.chatSend) b.chatSend(Number(peerId) || 0, s(text)); },
                editMessage: function(peerId, msgId, text) { if (b && b.chatEdit) b.chatEdit(Number(peerId) || 0, Number(msgId) || 0, s(text)); },
                deleteMessage: function(peerId, msgId) { if (b && b.chatDelete) b.chatDelete(Number(peerId) || 0, Number(msgId) || 0); }
            },
            peerProfile: {
                addAction: function(title, cb) { if (b && b.profileAddAction && cb) b.profileAddAction(s(title), cb); }
            },
            settings: {
                addItem: function(section, title, actionId, cb) { if (b && b.settingsAddItem && cb) b.settingsAddItem(s(section), s(title), s(actionId), cb); },
                getStorage: function(key) { return b && b.storageGet ? (b.storageGet(s(key)) || null) : null; },
                setStorage: function(key, val) { if (b && b.storageSet) b.storageSet(s(key), s(val)); }
            },
            events: {
                on: function(name, cb) { if (b && b.eventsOn) b.eventsOn(s(name), cb); },
                emit: function(name, params) { if (b && b.eventsEmit) b.eventsEmit(s(name), params || {}); }
            }
        };
    })();
    """

    public init() {}

    // MARK: - Load / Unload

    public func ensureLoaded() {
        queue.async { [weak self] in self?.ensureLoadedSync() }
    }

    private func ensureLoadedSync() {
        guard LuxGramFeatures.pluginsEnabled else {
            shutdown()
            return
        }
        guard SGSimpleSettings.shared.pluginsJavaScriptBridgeActive else {
            shutdown()
            return
        }
        loadLock.lock()
        defer { loadLock.unlock() }

        var toLoad: [(id: String, path: String, name: String)] = []
        if let data = SGSimpleSettings.shared.installedPluginsJson.data(using: .utf8),
           let plugins = try? JSONDecoder().decode([PluginInfo].self, from: data) {
            for plugin in plugins where plugin.enabled && (plugin.path as NSString).pathExtension.lowercased() == "js" {
                let id = plugin.metadata.id
                lock.lock()
                let alreadyLoaded = loadedPlugins[id] != nil
                lock.unlock()
                if !alreadyLoaded {
                    toLoad.append((id, plugin.path, plugin.metadata.name))
                }
            }
        }
        for (id, path, name) in toLoad {
            loadPluginSync(id: id, path: path, name: name)
        }
        registerAllHooks()
    }

    /// Load a single plugin. Shows alert on success if showNotification is true.
    private func loadPluginSync(id: String, path: String, name: String, showNotification: Bool = true) {
        guard LuxGramFeatures.pluginsEnabled else { return }
        guard (path as NSString).pathExtension.lowercased() == "js" else { return }

        // Resolve path: try disk first, then bundle
        var resolvedPath = path
        if !FileManager.default.fileExists(atPath: resolvedPath) {
            if let bundlePath = Bundle.main.path(forResource: id, ofType: "js", inDirectory: "Plugins") {
                resolvedPath = bundlePath
            }
        }
        guard let script = try? String(contentsOf: URL(fileURLWithPath: resolvedPath), encoding: .utf8) else {
            NSLog("[LuxGram PluginRunner] Failed to read: \(path)")
            return
        }

        let context = JSContext()!
        let state = JSPluginState(context: context)

        // Register state BEFORE evaluating script so bridge calls can store items
        lock.lock()
        loadedPlugins[id] = state
        lock.unlock()

        let bridge = LuxGramJSBridge()
        bridge.pluginId = id
        bridge.runner = self
        context.setObject(bridge, forKeyedSubscript: "_bridge" as NSString)
        context.exceptionHandler = { _, value in
            if let v = value, !v.isUndefined {
                NSLog("[LuxGram Plugin %@] JS error: %@", id, v.toString() ?? "")
            }
        }

        // Evaluate bootstrap
        context.exception = nil
        context.evaluateScript(PluginRunner.bootstrapScript)
        if context.exception != nil {
            NSLog("[LuxGram PluginRunner] Bootstrap error in \(id): \(context.exception!.toString() ?? "")")
            lock.lock()
            loadedPlugins.removeValue(forKey: id)
            lock.unlock()
            return
        }

        // Evaluate plugin script
        context.exception = nil
        context.evaluateScript(script)
        if context.exception != nil {
            NSLog("[LuxGram PluginRunner] Script error in \(id): \(context.exception!.toString() ?? "")")
            lock.lock()
            loadedPlugins.removeValue(forKey: id)
            lock.unlock()
            return
        }

        NSLog("[LuxGram PluginRunner] Loaded plugin: \(id)")

        // Show success alert
        if showNotification {
            let displayName = name.isEmpty ? id : name
            DispatchQueue.main.async {
                if let bulletin = PluginHost.shared.showBulletin {
                    bulletin("Плагин «\(displayName)» запущен", .success)
                } else if let alert = PluginHost.shared.showAlert {
                    alert("Плагин запущен", "«\(displayName)» успешно загружен и работает.")
                }
            }
        }
    }

    public func unload(pluginId: String) {
        lock.lock()
        loadedPlugins.removeValue(forKey: pluginId)
        lock.unlock()
        registerAllHooks()
    }

    public func shutdown() {
        lock.lock()
        loadedPlugins.removeAll()
        lock.unlock()
        if let o = PluginRunner.incomingMessageObserver {
            NotificationCenter.default.removeObserver(o)
            PluginRunner.incomingMessageObserver = nil
        }
        if let o = PluginRunner.technicalEventObserver {
            NotificationCenter.default.removeObserver(o)
            PluginRunner.technicalEventObserver = nil
        }
        SGPluginHooks.willOpenChatRunner = nil
        SGPluginHooks.willOpenProfileRunner = nil
        SGPluginHooks.chatMenuItemsProvider = nil
        SGPluginHooks.profileMenuItemsProvider = nil
        SGPluginHooks.messageHookRunner = nil
        SGPluginHooks.didSendMessageRunner = nil
        SGPluginHooks.incomingMessageHookRunner = nil
        SGPluginHooks.openUrlRunner = nil
        SGPluginHooks.shouldShowMessageRunner = nil
        SGPluginHooks.shouldShowGiftButtonRunner = nil
        SGPluginHooks.userDisplayRunner = nil
        SGPluginHooks.eventRunner = nil
    }

    // MARK: - State setters (called by bridge during script evaluation)

    func addSettingsItem(pluginId: String, section: String, title: String, actionId: String, callback: JSValue) {
        lock.lock()
        loadedPlugins[pluginId]?.settingsItems.append((section: section, title: title, actionId: actionId, callback: callback))
        lock.unlock()
    }

    func addChatMenuItem(pluginId: String, title: String, callback: JSValue) {
        lock.lock()
        loadedPlugins[pluginId]?.chatMenuItems.append((title: title, callback: callback))
        lock.unlock()
    }

    func addProfileMenuItem(pluginId: String, title: String, callback: JSValue) {
        lock.lock()
        loadedPlugins[pluginId]?.profileMenuItems.append((title: title, callback: callback))
        lock.unlock()
    }

    func setOnOutgoingMessage(pluginId: String, callback: JSValue) {
        lock.lock()
        loadedPlugins[pluginId]?.onOutgoingMessage = callback
        lock.unlock()
    }

    func setOnIncomingMessage(pluginId: String, callback: JSValue) {
        lock.lock()
        loadedPlugins[pluginId]?.onIncomingMessage = callback
        lock.unlock()
    }

    func setOnSubmitCallback(pluginId: String, callback: JSValue) {
        // Store as event handler with special name
        lock.lock()
        loadedPlugins[pluginId]?.eventHandlers.append((eventName: "__compose.onSubmit", callback: callback))
        lock.unlock()
    }

    func addEventListener(pluginId: String, eventName: String, callback: JSValue) {
        lock.lock()
        loadedPlugins[pluginId]?.eventHandlers.append((eventName: eventName, callback: callback))
        lock.unlock()
    }

    // MARK: - Hook registration

    private func registerAllHooks() {
        guard LuxGramFeatures.pluginsEnabled else { shutdown(); return }

        let block = { [weak self] in
            guard let self = self else { return }
            SGPluginHooks.willOpenChatRunner = { [weak self] accountId, peerId in
                self?.notifyOpenChat(accountId: accountId, peerId: peerId)
            }
            SGPluginHooks.willOpenProfileRunner = { [weak self] accountId, peerId in
                self?.notifyOpenProfile(accountId: accountId, peerId: peerId)
            }
            SGPluginHooks.chatMenuItemsProvider = { [weak self] accountId, peerId, messageId in
                self?.getChatMenuItems(accountId: accountId, peerId: peerId, messageId: messageId) ?? []
            }
            SGPluginHooks.profileMenuItemsProvider = { [weak self] accountId, peerId in
                self?.getProfileMenuItems(accountId: accountId, peerId: peerId) ?? []
            }
            SGPluginHooks.messageHookRunner = { [weak self] accountPeerId, peerId, text, replyTo in
                guard SGSimpleSettings.shared.pluginsJavaScriptBridgeActive else { return nil }
                return self?.applyOutgoingMessageHook(accountPeerId: accountPeerId, peerId: peerId, text: text, replyToMessageId: replyTo)
            }
            SGPluginHooks.didSendMessageRunner = { [weak self] accountId, peerId, text in
                guard SGSimpleSettings.shared.pluginsJavaScriptBridgeActive else { return }
                _ = self?.applyEvent(name: "message.didSend", params: ["accountId": accountId, "peerId": peerId, "text": text])
            }
            SGPluginHooks.incomingMessageHookRunner = { [weak self] accountId, peerId, messageId, text, outgoing in
                guard SGSimpleSettings.shared.pluginsJavaScriptBridgeActive else { return }
                self?.notifyIncomingMessage(accountId: accountId, peerId: peerId, messageId: messageId, text: text, outgoing: outgoing)
            }
            SGPluginHooks.openUrlRunner = { [weak self] url in
                guard SGSimpleSettings.shared.pluginsJavaScriptBridgeActive else { return false }
                return self?.applyOpenUrlHook(url: url) ?? false
            }
            SGPluginHooks.shouldShowMessageRunner = { [weak self] accountId, peerId, messageId, text, outgoing in
                guard SGSimpleSettings.shared.pluginsJavaScriptBridgeActive else { return true }
                return self?.applyShouldShowMessage(accountId: accountId, peerId: peerId, messageId: messageId, text: text, outgoing: outgoing) ?? true
            }
            SGPluginHooks.shouldShowGiftButtonRunner = { _, _ in true }
            SGPluginHooks.eventRunner = { [weak self] name, params in
                guard SGSimpleSettings.shared.pluginsJavaScriptBridgeActive else { return nil }
                return self?.applyEvent(name: name, params: params)
            }

            // Observe incoming messages
            if PluginRunner.incomingMessageObserver == nil {
                PluginRunner.incomingMessageObserver = NotificationCenter.default.addObserver(
                    forName: SGPluginIncomingMessageNotificationName, object: nil, queue: .main
                ) { [weak self] note in
                    guard let u = note.userInfo else { return }
                    self?.notifyIncomingMessage(
                        accountId: (u["accountId"] as? NSNumber)?.int64Value ?? 0,
                        peerId: (u["peerId"] as? NSNumber)?.int64Value ?? 0,
                        messageId: (u["messageId"] as? NSNumber)?.int64Value ?? 0,
                        text: u["text"] as? String,
                        outgoing: (u["outgoing"] as? NSNumber)?.boolValue ?? false
                    )
                }
            }
            if PluginRunner.technicalEventObserver == nil {
                PluginRunner.technicalEventObserver = NotificationCenter.default.addObserver(
                    forName: SGPluginTechnicalEventNotificationName, object: nil, queue: .main
                ) { [weak self] note in
                    guard let u = note.userInfo,
                          let eventName = u["eventName"] as? String,
                          let params = u["params"] as? [String: Any] else { return }
                    _ = self?.applyEvent(name: eventName, params: params)
                }
            }
        }
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }

    // MARK: - Hook execution

    public func getChatMenuItems(accountId: Int64, peerId: Int64, messageId: Int64? = nil) -> [PluginChatMenuItem] {
        guard LuxGramFeatures.pluginsEnabled else { return [] }
        let msgId = messageId ?? 0
        var items: [PluginChatMenuItem] = []
        lock.lock()
        for (_, state) in loadedPlugins {
            for item in state.chatMenuItems {
                nonisolated(unsafe) let cb = item.callback
                items.append(PluginChatMenuItem(title: item.title, action: {
                    DispatchQueue.main.async {
                        let ctx: [String: Any] = ["peerId": NSNumber(value: peerId), "messageId": NSNumber(value: msgId)]
                        cb.call(withArguments: [ctx])
                    }
                }))
            }
        }
        lock.unlock()
        return items
    }

    public func getProfileMenuItems(accountId: Int64, peerId: Int64) -> [PluginChatMenuItem] {
        guard LuxGramFeatures.pluginsEnabled else { return [] }
        var items: [PluginChatMenuItem] = []
        lock.lock()
        for (_, state) in loadedPlugins {
            for item in state.profileMenuItems {
                nonisolated(unsafe) let cb = item.callback
                items.append(PluginChatMenuItem(title: item.title, action: {
                    DispatchQueue.main.async {
                        let ctx: [String: Any] = ["peerId": NSNumber(value: peerId)]
                        cb.call(withArguments: [ctx])
                    }
                }))
            }
        }
        lock.unlock()
        return items
    }

    /// Run a settings action by pluginId and actionId.
    public func runAction(pluginId: String, actionId: String) {
        DispatchQueue.main.async { [weak self] in
            self?.lock.lock()
            guard let state = self?.loadedPlugins[pluginId] else { self?.lock.unlock(); return }
            guard let item = state.settingsItems.first(where: { $0.actionId == actionId }) else { self?.lock.unlock(); return }
            let callback = item.callback
            self?.lock.unlock()
            callback.call(withArguments: [])
        }
    }

    /// Get settings items filtered by section (compatibility with LuxGramSettingsController).
    public func getSettingsItems(section: String) -> [(pluginId: String, section: String, title: String, actionId: String)] {
        return allSettingsItems().filter { $0.section.lowercased() == section.lowercased() }
    }

    /// Get all settings items from loaded plugins.
    public func allSettingsItems() -> [(pluginId: String, section: String, title: String, actionId: String)] {
        lock.lock()
        defer { lock.unlock() }
        var result: [(pluginId: String, section: String, title: String, actionId: String)] = []
        for (pid, state) in loadedPlugins {
            for item in state.settingsItems {
                result.append((pluginId: pid, section: item.section, title: item.title, actionId: item.actionId))
            }
        }
        return result
    }

    private func applyOutgoingMessageHook(accountPeerId: Int64, peerId: Int64, text: String, replyToMessageId: Int64?) -> SGPluginHookResult? {
        lock.lock()
        let plugins = loadedPlugins.compactMap { _, state -> JSValue? in
            guard let cb = state.onOutgoingMessage, !cb.isUndefined else { return nil }
            return cb
        }
        lock.unlock()
        guard !plugins.isEmpty else { return nil }

        let replyId = replyToMessageId ?? 0
        let msg: [String: Any] = [
            "accountId": NSNumber(value: accountPeerId),
            "peerId": NSNumber(value: peerId),
            "text": text,
            "replyTo": NSNumber(value: replyId)
        ]
        func run() -> SGPluginHookResult? {
            for callback in plugins {
                guard let res = callback.call(withArguments: [msg]), !res.isUndefined, !res.isNull else { continue }
                if let action = res.forProperty("action")?.toString() {
                    if action == "modify", let newText = res.forProperty("text")?.toString() {
                        return SGPluginHookResult(strategy: .modify, message: newText)
                    }
                    if action == "cancel" {
                        return SGPluginHookResult(strategy: .cancel)
                    }
                }
            }
            return nil
        }
        if Thread.isMainThread { return run() }
        var result: SGPluginHookResult?
        DispatchQueue.main.sync { result = run() }
        return result
    }

    private func notifyIncomingMessage(accountId: Int64, peerId: Int64, messageId: Int64, text: String?, outgoing: Bool) {
        lock.lock()
        let callbacks = loadedPlugins.compactMap { _, state -> JSValue? in
            guard let cb = state.onIncomingMessage, !cb.isUndefined else { return nil }
            return cb
        }
        lock.unlock()
        let msg: [String: Any] = [
            "accountId": NSNumber(value: accountId),
            "peerId": NSNumber(value: peerId),
            "messageId": NSNumber(value: messageId),
            "text": text ?? "",
            "outgoing": outgoing
        ]
        for cb in callbacks {
            cb.call(withArguments: [msg])
        }
    }

    private func notifyOpenChat(accountId: Int64, peerId: Int64) {
        lock.lock()
        let callbacks = loadedPlugins.compactMap { _, state -> JSValue? in
            guard let cb = state.onOpenChat, !cb.isUndefined else { return nil }
            return cb
        }
        lock.unlock()
        for cb in callbacks {
            cb.call(withArguments: [NSNumber(value: accountId), NSNumber(value: peerId)])
        }
    }

    private func notifyOpenProfile(accountId: Int64, peerId: Int64) {
        lock.lock()
        let callbacks = loadedPlugins.compactMap { _, state -> JSValue? in
            guard let cb = state.onOpenProfile, !cb.isUndefined else { return nil }
            return cb
        }
        lock.unlock()
        for cb in callbacks {
            cb.call(withArguments: [NSNumber(value: accountId), NSNumber(value: peerId)])
        }
    }

    private func applyOpenUrlHook(url: String) -> Bool {
        lock.lock()
        let callbacks = loadedPlugins.compactMap { _, state -> JSValue? in
            guard let cb = state.openUrlHandler, !cb.isUndefined else { return nil }
            return cb
        }
        lock.unlock()
        for cb in callbacks {
            if let res = cb.call(withArguments: [url]), res.toBool() { return true }
        }
        return false
    }

    private func applyShouldShowMessage(accountId: Int64, peerId: Int64, messageId: Int64, text: String?, outgoing: Bool) -> Bool {
        lock.lock()
        let callbacks = loadedPlugins.compactMap { _, state -> JSValue? in
            guard let cb = state.shouldShowMessage, !cb.isUndefined else { return nil }
            return cb
        }
        lock.unlock()
        for cb in callbacks {
            if let res = cb.call(withArguments: [NSNumber(value: accountId), NSNumber(value: peerId), NSNumber(value: messageId), text ?? "", outgoing]) {
                if !res.isUndefined && !res.isNull && !res.toBool() { return false }
            }
        }
        return true
    }

    private func applyEvent(name: String, params: [String: Any]) -> [String: Any]? {
        lock.lock()
        let handlers = loadedPlugins.flatMap { _, state in
            state.eventHandlers.filter { $0.eventName == name }.map { $0.callback }
        }
        lock.unlock()
        for cb in handlers {
            if let res = cb.call(withArguments: [params as NSDictionary]), !res.isUndefined, !res.isNull {
                if let dict = res.toDictionary() as? [String: Any] {
                    if dict["cancel"] as? Bool == true { return dict }
                }
            }
        }
        return nil
    }

    /// Fire a wg-style hook for compatibility. Fires event with given name for all plugins.
    public func fireWgHook(_ hookName: String, args: [Any]) {
        guard LuxGramFeatures.pluginsEnabled else { return }
        _ = applyEvent(name: hookName, params: ["args": args])
    }

    /// Run a wg-style hook (compatibility shim).
    public func runWgHook(pluginId: String, hookName: String, peerId: Int64 = 0, messageId: Int64 = 0) {
        // No-op: wg API removed. Kept for compile compatibility.
    }

    public func runWgHookSync(pluginId: String, hookName: String, args: [Any]) {
        // No-op: wg API removed.
    }

    /// Returns wg settings rows (compatibility shim, empty).
    public func wgSettingsRows(for pluginId: String) -> [(id: String, title: String, subtitle: String, hookName: String)] {
        return []
    }

    /// Returns wg context menu items (compatibility shim, empty).
    public func wgContextMenuItems(for pluginId: String) -> [(title: String, hookName: String)] {
        return []
    }
}

// MARK: - Public settings items struct (for LuxGramSettingsController compatibility)

public struct JSPluginSettingsItem {
    public let pluginId: String
    public let section: String
    public let title: String
    public let actionId: String
    public let callback: JSValue
}

```

### `LuxGram/SGSettingsUI/Sources/LuxGramSettingsController.swift`

```swift
// MARK: LuxGram
import SGSimpleSettings
import SGStrings
import SGItemListUI
import SGSupporters
#if canImport(SGDeletedMessages)
import SGDeletedMessages
#endif

import Foundation
import UIKit
import AppBundle
import CoreText
import CoreGraphics
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
import Display
import PromptUI
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import OverlayStatusController
import UndoUI
import AccountContext
import LegacyUI
import LegacyMediaPickerUI
#if canImport(SGFakeLocation)
import SGFakeLocation
#endif
#if canImport(FaceScanScreen)
import FaceScanScreen
#endif

// MARK: - Back button helper

private class BackButtonTarget: NSObject {
    private weak var controller: UIViewController?

    init(controller: UIViewController) {
        self.controller = controller
    }

    @objc func backAction() {
        if let nav = controller?.navigationController, nav.viewControllers.count > 1 {
            nav.popViewController(animated: true)
        } else {
            controller?.dismiss(animated: true)
        }
    }
}

private var backButtonTargetKey: UInt8 = 0

private func makeBackBarButtonItem(presentationData: PresentationData, controller: ViewController) -> UIBarButtonItem {
    let target = BackButtonTarget(controller: controller)
    objc_setAssociatedObject(controller, &backButtonTargetKey, target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    return UIBarButtonItem(backButtonAppearanceWithTitle: presentationData.strings.Common_Back, target: target, action: #selector(BackButtonTarget.backAction))
}

/// Масштабирует изображение до maxSize по большей стороне с чётким рендером (как иконки «Канал, Чат, Форум»).
private func scaleImageForListIcon(_ image: UIImage, maxSize: CGFloat) -> UIImage? {
    let size = image.size
    guard size.width > 0, size.height > 0 else { return image }
    guard size.width > maxSize || size.height > maxSize else { return image }
    let scale = min(maxSize / size.width, maxSize / size.height)
    let newSizePt = CGSize(width: size.width * scale, height: size.height * scale)
    let screenScale = UIScreen.main.scale
    let format = UIGraphicsImageRendererFormat()
    format.scale = screenScale
    format.opaque = false
    let renderer = UIGraphicsImageRenderer(size: newSizePt, format: format)
    return renderer.image { ctx in
        ctx.cgContext.interpolationQuality = .high
        image.draw(in: CGRect(origin: .zero, size: newSizePt))
    }
}

private enum LuxGramTab: Int, CaseIterable {
    case appearance = 0
    case security
    case other
}

private enum LuxGramSection: Int32, SGItemListSection {
    case search
    case functions
    case links
    case messages
    case chatList
    case onlineStatus
    case readReceipts
    case content
    case localPremium
    case interface
    case appearance
    case fontReplacement
    case fakeLocation
    case onlineStatusRecording
    case doubleBottom
    case protectedChats
    case voiceChanger
    case other
}

private func tab(for section: LuxGramSection) -> LuxGramTab {
    switch section {
    case .search: return .appearance
    case .functions, .links: return .appearance
    case .localPremium, .interface, .appearance, .fontReplacement: return .appearance
    case .messages, .chatList, .onlineStatus, .readReceipts, .content, .fakeLocation, .onlineStatusRecording, .doubleBottom, .protectedChats, .voiceChanger: return .security
    case .other: return .other
    }
}

private func sectionForEntry(_ entry: LuxGramEntry) -> LuxGramSection {
    switch entry {
    case .header(_, let s, _, _): return s
    case .toggle(_, let s, _, _, _, _): return s
    case .toggleWithIcon(_, let s, _, _, _, _, _): return s
    case .notice(_, let s, _): return s
    case .percentageSlider(_, let s, _, _, _, _): return s
    case .delaySecondsSlider(_, let s, _, _, _, _, _): return s
    case .fontSizeMultiplierSlider(_, let s, _, _): return s
    case .oneFromManySelector(_, let s, _, _, _, _): return s
    case .disclosure(_, let s, _, _): return s
    case .disclosureWithIcon(_, let s, _, _, _): return s
    case .peerColorDisclosurePreview(_, let s, _, _): return s
    case .action(_, let s, _, _, _): return s
    case .searchInput(_, let s, _, _, _): return s
    case .reorderableRow(_, let s, _, _, _): return s
    }
}

private func gleGramEntriesFiltered(by selectedTab: LuxGramTab, entries: [LuxGramEntry]) -> [LuxGramEntry] {
    entries.filter { entry in
        let sec = sectionForEntry(entry)
        return sec == .search || tab(for: sec) == selectedTab
    }
}

private func glegSelfChatTitleModeLabel(_ mode: SelfChatTitleMode, lang: String) -> String {
    switch mode {
    case .default:
        return lang == "ru" ? "Как в Telegram" : "Like Telegram"
    case .displayName:
        return lang == "ru" ? "Имя профиля" : "Display name"
    case .username:
        return "@username"
    }
}

/// Root LuxGram screen: exteraGram-style — header (icon + title + tagline), Функции (4 tabs), Ссылки (Канал, Чат, Форум).
private func gleGramRootEntries(presentationData: PresentationData) -> [LuxGramEntry] {
    let lang = presentationData.strings.baseLanguageCode
    var entries: [LuxGramEntry] = []
    let id = SGItemListCounter()
    let functionsHeader = lang == "ru" ? "ФУНКЦИИ" : "FEATURES"
    let linksHeader = lang == "ru" ? "ССЫЛКИ" : "LINKS"
    let appearanceTitle = lang == "ru" ? "Оформление" : "Appearance"
    let securityTitle = lang == "ru" ? "Приватность" : "Privacy"
    let otherTitle = lang == "ru" ? "Другие функции" : "Other"
    let channelTitle = lang == "ru" ? "Канал" : "Channel"
    let chatTitle = lang == "ru" ? "Чат" : "Chat"
    let forumTitle = lang == "ru" ? "Форум" : "Forum"
    entries.append(.header(id: id.count, section: .functions, text: functionsHeader, badge: nil))
    entries.append(LuxGramEntry.disclosureWithIcon(id: id.count, section: .functions, link: .appearanceTab, text: appearanceTitle, iconRef: "LuxGramTabAppearance"))
    entries.append(LuxGramEntry.disclosureWithIcon(id: id.count, section: .functions, link: .securityTab, text: securityTitle, iconRef: "LuxGramTabSecurity"))
    entries.append(LuxGramEntry.disclosureWithIcon(id: id.count, section: .functions, link: .otherTab, text: otherTitle, iconRef: "LuxGramTabOther"))
    if LuxGramFeatures.pluginsEnabled {
        let pluginsTitle = lang == "ru" ? "Плагины" : "Plugins"
        entries.append(LuxGramEntry.disclosureWithIcon(id: id.count, section: .functions, link: .pluginsSettings, text: pluginsTitle, iconRef: "glePlugins/1"))
    }
    entries.append(.header(id: id.count, section: .links, text: linksHeader, badge: nil))
    entries.append(LuxGramEntry.disclosureWithIcon(id: id.count, section: .links, link: .channelLink, text: channelTitle, iconRef: "Settings/Menu/Channels"))
    entries.append(LuxGramEntry.disclosureWithIcon(id: id.count, section: .links, link: .chatLink, text: chatTitle, iconRef: "Settings/Menu/GroupChats"))
    entries.append(LuxGramEntry.disclosureWithIcon(id: id.count, section: .links, link: .forumLink, text: forumTitle, iconRef: "Settings/Menu/Topics"))
    if let status = cachedLuxGramUserStatus(), status.access.betaBuilds, let betaConfig = status.betaConfig, betaConfig.channelUrl != nil {
        let betaHeader = lang == "ru" ? "БЕТА" : "BETA"
        entries.append(.header(id: id.count, section: .links, text: betaHeader, badge: nil))
        let betaChannelTitle = lang == "ru" ? "Перейти в канал с бета-версиями" : "Go to Beta Channel"
        entries.append(LuxGramEntry.disclosure(id: id.count, section: .links, link: .betaChannel, text: betaChannelTitle))
    }

    return entries
}

private enum LuxGramSliderSetting: Hashable {
    case fontReplacementSize
    case ghostModeMessageSendDelay
    case avatarRoundingPercent
}

private enum LuxGramOneFromManySetting: Hashable {
    case onlineStatusRecordingInterval
    case selfChatTitleMode
}

private enum LuxGramDisclosureLink: Hashable {
    case fakeLocationPicker
    case tabOrganizer
    case profileCover
    case fontReplacementPicker
    case fontReplacementBoldPicker
    case fontReplacementImportFile
    case fontReplacementBoldImportFile
    case appearanceTab
    case securityTab
    case otherTab
    case fakeProfileSettings
    case feelRichAmount
    case savedDeletedMessagesList
    case doubleBottomSettings
    case protectedChatsSettings
    /// LuxGram root: Plugins list (JS + .plugin).
    case pluginsSettings
    /// Links section: open t.me URLs.
    case channelLink
    case chatLink
    case forumLink
    /// Beta section: channel with beta versions.
    case betaChannel
    /// Voice Morpher preset (ghostgram-style local DSP).
    case voiceChangerVoicePicker
}

private typealias LuxGramEntry = SGItemListUIEntry<LuxGramSection, SGBoolSetting, LuxGramSliderSetting, LuxGramOneFromManySetting, LuxGramDisclosureLink, AnyHashable>

private struct LuxGramSettingsControllerState: Equatable {
    var searchQuery: String?
    var selectedTab: LuxGramTab = .appearance
}

private func gleGramEntries(presentationData: PresentationData, contentSettingsConfiguration: ContentSettingsConfiguration?, state: LuxGramSettingsControllerState, mediaBoxBasePath: String) -> [LuxGramEntry] {
    let lang = presentationData.strings.baseLanguageCode
    let strings = presentationData.strings
    var entries: [LuxGramEntry] = []
    let id = SGItemListCounter()
    
    entries.append(.searchInput(id: id.count, section: .search, title: NSAttributedString(string: "🔍"), text: state.searchQuery ?? "", placeholder: strings.Common_Search))
    
    // MARK: Messages
    entries.append(.header(id: id.count, section: .messages, text: i18n("Settings.DeletedMessages.Header", lang), badge: nil))

    let showDeleted = SGSimpleSettings.shared.showDeletedMessages
    entries.append(.toggle(id: id.count, section: .messages, settingName: .showDeletedMessages, value: showDeleted, text: i18n("Settings.DeletedMessages.Save", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .messages, text: i18n("Settings.DeletedMessages.Save.Notice", lang)))

    entries.append(.toggle(id: id.count, section: .messages, settingName: .saveDeletedMessagesMedia, value: SGSimpleSettings.shared.saveDeletedMessagesMedia, text: i18n("Settings.DeletedMessages.SaveMedia", lang), enabled: showDeleted))
    entries.append(.toggle(id: id.count, section: .messages, settingName: .saveDeletedMessagesReactions, value: SGSimpleSettings.shared.saveDeletedMessagesReactions, text: i18n("Settings.DeletedMessages.SaveReactions", lang), enabled: showDeleted))
    entries.append(.toggle(id: id.count, section: .messages, settingName: .saveDeletedMessagesForBots, value: SGSimpleSettings.shared.saveDeletedMessagesForBots, text: i18n("Settings.DeletedMessages.SaveForBots", lang), enabled: showDeleted))
    let storageSizeFormatted = ByteCountFormatter.string(fromByteCount: SGDeletedMessages.storageSizeBytes(mediaBoxBasePath: mediaBoxBasePath), countStyle: .file)
    entries.append(.notice(id: id.count, section: .messages, text: i18n("Settings.DeletedMessages.StorageSize", lang) + ": " + storageSizeFormatted))
    entries.append(.disclosure(id: id.count, section: .messages, link: .savedDeletedMessagesList, text: (lang == "ru" ? "Просмотреть сохранённые" : "View saved messages")))
    entries.append(.action(id: id.count, section: .messages, actionType: "clearDeletedMessages" as AnyHashable, text: i18n("Settings.DeletedMessages.Clear", lang), kind: .destructive))
    
    let saveEditHistoryTitle = (lang == "ru" ? "Сохранять историю редактирования" : "Save edit history")
    let saveEditHistoryNotice = (lang == "ru"
                                 ? "Сохраняет оригинальный текст сообщений при редактировании."
                                 : "Keeps original message text when you edit messages.")
    entries.append(.toggle(id: id.count, section: .messages, settingName: .saveEditHistory, value: SGSimpleSettings.shared.saveEditHistory, text: saveEditHistoryTitle, enabled: true))
    entries.append(.notice(id: id.count, section: .messages, text: saveEditHistoryNotice))
    
    let localEditTitle = (lang == "ru" ? "Редактировать сообщения собеседника (локально)" : "Edit other's messages (local only)")
    let localEditNotice = (lang == "ru"
                          ? "В контекстном меню входящих сообщений появится «Редактировать». Изменения видны только на вашем устройстве."
                          : "Adds «Edit» to context menu for incoming messages. Changes are visible only on your device.")
    entries.append(.toggle(id: id.count, section: .messages, settingName: .enableLocalMessageEditing, value: SGSimpleSettings.shared.enableLocalMessageEditing, text: localEditTitle, enabled: true))
    entries.append(.notice(id: id.count, section: .messages, text: localEditNotice))
    
    // MARK: Chat list / Read all
    entries.append(.header(id: id.count, section: .chatList, text: i18n("READ_ALL_HEADER", lang), badge: nil))
    entries.append(.action(id: id.count, section: .chatList, actionType: "markAllReadLocal" as AnyHashable, text: i18n("READ_ALL_LOCAL_TITLE", lang), kind: .generic))
    entries.append(.notice(id: id.count, section: .chatList, text: i18n("READ_ALL_LOCAL_SUBTITLE", lang)))
    entries.append(.action(id: id.count, section: .chatList, actionType: "markAllReadServer" as AnyHashable, text: i18n("READ_ALL_SERVER_TITLE", lang), kind: .generic))
    entries.append(.notice(id: id.count, section: .chatList, text: i18n("READ_ALL_SERVER_SUBTITLE", lang)))
    // MARK: Online status / Ghost mode
    entries.append(.header(id: id.count, section: .onlineStatus, text: (lang == "ru" ? "ОНЛАЙН-СТАТУС" : "ONLINE STATUS"), badge: nil))
    entries.append(.toggle(id: id.count, section: .onlineStatus, settingName: .disableOnlineStatus, value: SGSimpleSettings.shared.disableOnlineStatus, text: i18n("DISABLE_ONLINE_STATUS_TITLE", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .onlineStatus, text: i18n("DISABLE_ONLINE_STATUS_SUBTITLE", lang)))
    let delaySeconds = SGSimpleSettings.shared.ghostModeMessageSendDelaySeconds
    let delayLeftLabel = lang == "ru" ? "Выкл" : "Off"
    let delayRightLabel = lang == "ru" ? "45 сек" : "45 sec"
    let delayCenterLabels = lang == "ru" ? ["Выкл", "12 сек", "30 сек", "45 сек"] : ["Off", "12 sec", "30 sec", "45 sec"]
    entries.append(.delaySecondsSlider(id: id.count, section: .onlineStatus, settingName: .ghostModeMessageSendDelay, value: delaySeconds, leftLabel: delayLeftLabel, rightLabel: delayRightLabel, centerLabels: delayCenterLabels))
    let delayNotice = (lang == "ru" ? "При включённой задержке сообщения будут отправляться через выбранный интервал (12, 30 или 45 секунд). Онлайн-статус не будет отображаться во время отправки." : "When delay is enabled, messages will be sent after the selected interval (12, 30 or 45 seconds). Online status will not appear during sending.")
    entries.append(.notice(id: id.count, section: .onlineStatus, text: delayNotice))
    entries.append(.toggle(id: id.count, section: .onlineStatus, settingName: .disableTypingStatus, value: SGSimpleSettings.shared.disableTypingStatus, text: i18n("DISABLE_TYPING_STATUS_TITLE", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .onlineStatus, text: i18n("DISABLE_TYPING_STATUS_SUBTITLE", lang)))
    entries.append(.toggle(id: id.count, section: .onlineStatus, settingName: .disableRecordingVideoStatus, value: SGSimpleSettings.shared.disableRecordingVideoStatus, text: i18n("DISABLE_RECORDING_VIDEO_STATUS_TITLE", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .onlineStatus, text: i18n("DISABLE_RECORDING_VIDEO_STATUS_SUBTITLE", lang)))
    entries.append(.toggle(id: id.count, section: .onlineStatus, settingName: .disableUploadingVideoStatus, value: SGSimpleSettings.shared.disableUploadingVideoStatus, text: i18n("DISABLE_UPLOADING_VIDEO_STATUS_TITLE", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .onlineStatus, text: i18n("DISABLE_UPLOADING_VIDEO_STATUS_SUBTITLE", lang)))
    entries.append(.toggle(id: id.count, section: .onlineStatus, settingName: .disableVCMessageRecordingStatus, value: SGSimpleSettings.shared.disableVCMessageRecordingStatus, text: i18n("DISABLE_VC_MESSAGE_RECORDING_STATUS_TITLE", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .onlineStatus, text: i18n("DISABLE_VC_MESSAGE_RECORDING_STATUS_SUBTITLE", lang)))
    entries.append(.toggle(id: id.count, section: .onlineStatus, settingName: .disableVCMessageUploadingStatus, value: SGSimpleSettings.shared.disableVCMessageUploadingStatus, text: i18n("DISABLE_VC_MESSAGE_UPLOADING_STATUS_TITLE", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .onlineStatus, text: i18n("DISABLE_VC_MESSAGE_UPLOADING_STATUS_SUBTITLE", lang)))
    entries.append(.toggle(id: id.count, section: .onlineStatus, settingName: .disableUploadingPhotoStatus, value: SGSimpleSettings.shared.disableUploadingPhotoStatus, text: i18n("DISABLE_UPLOADING_PHOTO_STATUS_TITLE", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .onlineStatus, text: i18n("DISABLE_UPLOADING_PHOTO_STATUS_SUBTITLE", lang)))
    entries.append(.toggle(id: id.count, section: .onlineStatus, settingName: .disableUploadingFileStatus, value: SGSimpleSettings.shared.disableUploadingFileStatus, text: i18n("DISABLE_UPLOADING_FILE_STATUS_TITLE", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .onlineStatus, text: i18n("DISABLE_UPLOADING_FILE_STATUS_SUBTITLE", lang)))
    entries.append(.toggle(id: id.count, section: .onlineStatus, settingName: .disableChoosingLocationStatus, value: SGSimpleSettings.shared.disableChoosingLocationStatus, text: i18n("DISABLE_CHOOSING_LOCATION_STATUS_TITLE", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .onlineStatus, text: i18n("DISABLE_CHOOSING_LOCATION_STATUS_SUBTITLE", lang)))
    entries.append(.toggle(id: id.count, section: .onlineStatus, settingName: .disableChoosingContactStatus, value: SGSimpleSettings.shared.disableChoosingContactStatus, text: i18n("DISABLE_CHOOSING_CONTACT_TITLE", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .onlineStatus, text: i18n("DISABLE_CHOOSING_CONTACT_SUBTITLE", lang)))
    entries.append(.toggle(id: id.count, section: .onlineStatus, settingName: .disablePlayingGameStatus, value: SGSimpleSettings.shared.disablePlayingGameStatus, text: i18n("DISABLE_PLAYING_GAME_STATUS_TITLE", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .onlineStatus, text: i18n("DISABLE_PLAYING_GAME_STATUS_SUBTITLE", lang)))
    entries.append(.toggle(id: id.count, section: .onlineStatus, settingName: .disableRecordingRoundVideoStatus, value: SGSimpleSettings.shared.disableRecordingRoundVideoStatus, text: i18n("DISABLE_RECORDING_ROUND_VIDEO_STATUS_TITLE", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .onlineStatus, text: i18n("DISABLE_RECORDING_ROUND_VIDEO_STATUS_SUBTITLE", lang)))
    entries.append(.toggle(id: id.count, section: .onlineStatus, settingName: .disableUploadingRoundVideoStatus, value: SGSimpleSettings.shared.disableUploadingRoundVideoStatus, text: i18n("DISABLE_UPLOADING_ROUND_VIDEO_STATUS_TITLE", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .onlineStatus, settingName: .disableSpeakingInGroupCallStatus, value: SGSimpleSettings.shared.disableSpeakingInGroupCallStatus, text: i18n("DISABLE_SPEAKING_IN_GROUP_CALL_STATUS_TITLE", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .onlineStatus, text: i18n("DISABLE_SPEAKING_IN_GROUP_CALL_STATUS_SUBTITLE", lang)))
    entries.append(.toggle(id: id.count, section: .onlineStatus, settingName: .disableChoosingStickerStatus, value: SGSimpleSettings.shared.disableChoosingStickerStatus, text: i18n("DISABLE_CHOOSING_STICKER_STATUS_TITLE", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .onlineStatus, text: i18n("DISABLE_CHOOSING_STICKER_STATUS_SUBTITLE", lang)))
    entries.append(.toggle(id: id.count, section: .onlineStatus, settingName: .disableEmojiInteractionStatus, value: SGSimpleSettings.shared.disableEmojiInteractionStatus, text: i18n("DISABLE_EMOJI_INTERACTION_STATUS_TITLE", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .onlineStatus, text: i18n("DISABLE_EMOJI_INTERACTION_STATUS_SUBTITLE", lang)))
    entries.append(.toggle(id: id.count, section: .onlineStatus, settingName: .disableEmojiAcknowledgementStatus, value: SGSimpleSettings.shared.disableEmojiAcknowledgementStatus, text: i18n("DISABLE_EMOJI_ACKNOWLEDGEMENT_STATUS_TITLE", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .onlineStatus, text: i18n("DISABLE_EMOJI_ACKNOWLEDGEMENT_STATUS_SUBTITLE", lang)))
    
    // MARK: Read receipts
    entries.append(.header(id: id.count, section: .readReceipts, text: (lang == "ru" ? "ОТЧЁТЫ О ПРОЧТЕНИИ" : "READ RECEIPTS"), badge: nil))
    let disableMessageReadReceiptTitle = (lang == "ru" ? "Отчёты: сообщения" : i18n("DISABLE_MESSAGE_READ_RECEIPT_TITLE", lang))
    entries.append(.toggle(id: id.count, section: .readReceipts, settingName: .disableMessageReadReceipt, value: SGSimpleSettings.shared.disableMessageReadReceipt, text: disableMessageReadReceiptTitle, enabled: true))
    entries.append(.notice(id: id.count, section: .readReceipts, text: i18n("DISABLE_MESSAGE_READ_RECEIPT_SUBTITLE", lang)))
    let ghostMarkReadOnReplyTitle = (lang == "ru" ? "Помечать прочитанным при ответе" : "Mark as read when replying")
    let ghostMarkReadOnReplyNotice = (lang == "ru"
        ? "Если отключены отчёты о прочтении сообщений: при ответе на входящее оно может помечаться прочитанным на сервере. Выключите, чтобы ответ не менял статус прочтения."
        : "When message read receipts are off: replying to an incoming message can still mark it read on the server. Turn off to keep replies from updating read status.")
    entries.append(.toggle(id: id.count, section: .readReceipts, settingName: .ghostModeMarkReadOnReply, value: SGSimpleSettings.shared.ghostModeMarkReadOnReply, text: ghostMarkReadOnReplyTitle, enabled: true))
    entries.append(.notice(id: id.count, section: .readReceipts, text: ghostMarkReadOnReplyNotice))
    let disableStoryReadReceiptTitle = (lang == "ru" ? "Отчёты: истории" : i18n("DISABLE_STORY_READ_RECEIPT_TITLE", lang))
    entries.append(.toggle(id: id.count, section: .readReceipts, settingName: .disableStoryReadReceipt, value: SGSimpleSettings.shared.disableStoryReadReceipt, text: disableStoryReadReceiptTitle, enabled: true))
    entries.append(.notice(id: id.count, section: .readReceipts, text: i18n("DISABLE_STORY_READ_RECEIPT_SUBTITLE", lang)))
    
    // MARK: Content / security / ads
    entries.append(.header(id: id.count, section: .content, text: (lang == "ru" ? "КОНТЕНТ И БЕЗОПАСНОСТЬ" : "CONTENT & SECURITY"), badge: nil))
    let disableAllAdsTitle = (lang == "ru" ? "Отключить рекламу" : i18n("DISABLE_ALL_ADS_TITLE", lang))
    entries.append(.toggle(id: id.count, section: .content, settingName: .disableAllAds, value: SGSimpleSettings.shared.disableAllAds, text: disableAllAdsTitle, enabled: true))
    entries.append(.notice(id: id.count, section: .content, text: i18n("DISABLE_ALL_ADS_SUBTITLE", lang)))
    let hideProxySponsorTitle = (lang == "ru" ? "Скрыть спонсора прокси" : i18n("HIDE_PROXY_SPONSOR_TITLE", lang))
    entries.append(.toggle(id: id.count, section: .content, settingName: .hideProxySponsor, value: SGSimpleSettings.shared.hideProxySponsor, text: hideProxySponsorTitle, enabled: true))
    entries.append(.notice(id: id.count, section: .content, text: i18n("HIDE_PROXY_SPONSOR_SUBTITLE", lang)))
    let enableSavingProtectedTitle = (lang == "ru" ? "Сохранять защищённый контент" : i18n("ENABLE_SAVING_PROTECTED_CONTENT_TITLE", lang))
    entries.append(.toggle(id: id.count, section: .content, settingName: .enableSavingProtectedContent, value: SGSimpleSettings.shared.enableSavingProtectedContent, text: enableSavingProtectedTitle, enabled: true))
    entries.append(.notice(id: id.count, section: .content, text: i18n("ENABLE_SAVING_PROTECTED_CONTENT_SUBTITLE", lang)))
    let forwardRestrictedTitle = (lang == "ru" ? "Пересылать защищённые сообщения" : "Forward restricted messages")
    entries.append(.toggle(id: id.count, section: .content, settingName: .forwardRestrictedAsCopy, value: SGSimpleSettings.shared.forwardRestrictedAsCopy, text: forwardRestrictedTitle, enabled: true))
    let forwardRestrictedNotice = (lang == "ru" ? "Текст защищённого сообщения будет скопирован и отправлен от вашего имени." : "Text from restricted messages will be copied and sent as your own.")
    entries.append(.notice(id: id.count, section: .content, text: forwardRestrictedNotice))
    let enableSavingSelfDestructTitle = (lang == "ru" ? "Сохранять самоуничтож." : i18n("ENABLE_SAVING_SELF_DESTRUCTING_MESSAGES_TITLE", lang))
    entries.append(.toggle(id: id.count, section: .content, settingName: .enableSavingSelfDestructingMessages, value: SGSimpleSettings.shared.enableSavingSelfDestructingMessages, text: enableSavingSelfDestructTitle, enabled: true))
    entries.append(.notice(id: id.count, section: .content, text: i18n("ENABLE_SAVING_SELF_DESTRUCTING_MESSAGES_SUBTITLE", lang)))
    let disableScreenshotDetectionTitle = (lang == "ru" ? "Скрыть скриншоты" : i18n("DISABLE_SCREENSHOT_DETECTION_TITLE", lang))
    entries.append(.toggle(id: id.count, section: .content, settingName: .disableScreenshotDetection, value: SGSimpleSettings.shared.disableScreenshotDetection, text: disableScreenshotDetectionTitle, enabled: true))
    entries.append(.notice(id: id.count, section: .content, text: i18n("DISABLE_SCREENSHOT_DETECTION_SUBTITLE", lang)))
    let disableSecretBlurTitle = (lang == "ru" ? "Не размывать секретные" : i18n("DISABLE_SECRET_CHAT_BLUR_ON_SCREENSHOT_TITLE", lang))
    entries.append(.toggle(id: id.count, section: .content, settingName: .disableSecretChatBlurOnScreenshot, value: SGSimpleSettings.shared.disableSecretChatBlurOnScreenshot, text: disableSecretBlurTitle, enabled: true))
    entries.append(.notice(id: id.count, section: .content, text: i18n("DISABLE_SECRET_CHAT_BLUR_ON_SCREENSHOT_SUBTITLE", lang)))

    // MARK: LuxGram — Face blur in video messages
    let faceBlurTitle = lang == "ru" ? "Скрытие лица в видеосообщениях" : "Face blur in video messages"
    entries.append(.toggle(id: id.count, section: .content, settingName: .faceBlurInVideoMessages, value: SGSimpleSettings.shared.faceBlurInVideoMessages, text: faceBlurTitle, enabled: true))
    let faceBlurNotice = lang == "ru" ? "При записи видеосообщения (кружка) ваше лицо будет автоматически заблюрено перед отправкой." : "Your face will be automatically blurred in video messages before sending."
    entries.append(.notice(id: id.count, section: .content, text: faceBlurNotice))

    // MARK: 18+ / Sensitive content (server-side)
    if let contentSettingsConfiguration {
        let canAdjust = contentSettingsConfiguration.canAdjustSensitiveContent
        let sensitiveTitle = (lang == "ru" ? "Разрешить 18+ контент" : presentationData.strings.Settings_SensitiveContent)
        let sensitiveInfo = presentationData.strings.Settings_SensitiveContentInfo
        entries.append(.toggle(
            id: id.count,
            section: .content,
            settingName: .sensitiveContentEnabled,
            value: contentSettingsConfiguration.sensitiveContentEnabled,
            text: sensitiveTitle,
            enabled: canAdjust
        ))
        entries.append(.notice(id: id.count, section: .content, text: canAdjust ? sensitiveInfo : (lang == "ru" ? "Сервер Telegram не разрешает менять эту настройку для данного аккаунта." : "Telegram server does not allow changing this setting for this account.")))
    } else {
        // Configuration not loaded yet — show disabled placeholder.
        let sensitiveTitle = (lang == "ru" ? "Разрешить 18+ контент" : "Sensitive content")
        entries.append(.toggle(
            id: id.count,
            section: .content,
            settingName: .sensitiveContentEnabled,
            value: false,
            text: sensitiveTitle,
            enabled: false
        ))
        entries.append(.notice(id: id.count, section: .content, text: (lang == "ru" ? "Загрузка настроек… (нужен доступ к серверу Telegram)" : "Loading settings… (requires Telegram server access)")))
    }
    
    // MARK: Double Bottom (hidden accounts / second passcode)
    entries.append(.header(id: id.count, section: .doubleBottom, text: (lang == "ru" ? "ДВОЙНОЕ ДНО" : "DOUBLE BOTTOM"), badge: nil))
    entries.append(.disclosure(id: id.count, section: .doubleBottom, link: .doubleBottomSettings, text: (lang == "ru" ? "Двойное дно" : "Double Bottom")))
    entries.append(.notice(id: id.count, section: .doubleBottom, text: (lang == "ru" ? "Скрытые аккаунты и вход по паролю. Разные пароли открывают разные профили." : "Hidden accounts and passcode access. Different passwords open different profiles.")))

    // MARK: Password for chats / folders
    entries.append(.header(id: id.count, section: .protectedChats, text: (lang == "ru" ? "ПАРОЛЬ ДЛЯ ЧАТОВ" : "PASSWORD FOR CHATS"), badge: nil))
    entries.append(.disclosure(id: id.count, section: .protectedChats, link: .protectedChatsSettings, text: (lang == "ru" ? "Пароль при заходе в чат" : "Password when entering chat")))
    entries.append(.notice(id: id.count, section: .protectedChats, text: (lang == "ru" ? "Выберите чаты и/или папки, при открытии которых нужно вводить пароль (пароль Telegram или отдельный)." : "Select chats and/or folders that require a passcode to open (device passcode or a separate one).")))
    
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
    
    // MARK: Local premium
    entries.append(.header(id: id.count, section: .localPremium, text: i18n("Settings.Other.LocalPremium", lang), badge: nil))
    entries.append(.toggle(id: id.count, section: .localPremium, settingName: .enableLocalPremium, value: SGSimpleSettings.shared.enableLocalPremium, text: i18n("Settings.Other.EnableLocalPremium", lang), enabled: true))
    let localPremiumNotice = lang == "ru"
        ? "Локально разблокирует лимиты Premium, эмодзи-статус, цвета имени и профиля в оформлении (без подписки Telegram Premium)."
        : "Locally unlocks Premium limits, emoji status, and name/profile appearance colors (without a Telegram Premium subscription)."
    entries.append(.notice(id: id.count, section: .localPremium, text: localPremiumNotice))
    
    // MARK: Interface (appearance tab: only tab organizer)
    entries.append(.header(id: id.count, section: .interface, text: (lang == "ru" ? "ИНТЕРФЕЙС" : "INTERFACE"), badge: nil))
    entries.append(.disclosure(id: id.count, section: .interface, link: .tabOrganizer, text: (lang == "ru" ? "Органайзер таббара" : "Tab Bar Organizer")))
    entries.append(.notice(id: id.count, section: .interface, text: (lang == "ru" ? "Порядок и видимость вкладок внизу экрана (Чаты, Контакты, Звонки, Настройки)." : "Order and visibility of bottom tabs (Chats, Contacts, Calls, Settings).")))
    
    // MARK: Оформление (Appearance)
    entries.append(.header(id: id.count, section: .appearance, text: (lang == "ru" ? "ОБЛОЖКА ПРОФИЛЯ" : "PROFILE COVER"), badge: nil))
    entries.append(.disclosure(id: id.count, section: .appearance, link: .profileCover, text: (lang == "ru" ? "Обложка профиля" : "Profile cover")))
    entries.append(.notice(id: id.count, section: .appearance, text: (lang == "ru" ? "Фото или видео вместо цвета в профиле (видно только вам)." : "Photo or video instead of color in profile (visible only to you).")))
    let giftIdTitle = (lang == "ru" ? "Показывать ID подарка" : "Show gift ID")
    let giftIdNotice = (lang == "ru" ? "При нажатии на информацию о подарке отображается его ID." : "When tapping gift info, its ID is shown.")
    entries.append(.toggle(id: id.count, section: .appearance, settingName: .giftIdEnabled, value: SGSimpleSettings.shared.giftIdEnabled, text: giftIdTitle, enabled: true))
    entries.append(.notice(id: id.count, section: .appearance, text: giftIdNotice))
    entries.append(.header(id: id.count, section: .appearance, text: (lang == "ru" ? "ПОДМЕНА ПРОФИЛЯ" : "FAKE PROFILE"), badge: nil))
    let fakeProfileTitle = (lang == "ru" ? "Подмена профиля" : "Fake profile")
    entries.append(.toggle(id: id.count, section: .appearance, settingName: .fakeProfileEnabled, value: SGSimpleSettings.shared.fakeProfileEnabled, text: fakeProfileTitle, enabled: true))
    entries.append(.disclosure(id: id.count, section: .appearance, link: .fakeProfileSettings, text: (lang == "ru" ? "Изменить" : "Change")))
    entries.append(.header(id: id.count, section: .appearance, text: (lang == "ru" ? "ЗАМЕНА ШРИФТА" : "FONT REPLACEMENT"), badge: nil))
    entries.append(.toggle(id: id.count, section: .appearance, settingName: .enableFontReplacement, value: SGSimpleSettings.shared.enableFontReplacement, text: (lang == "ru" ? "Замена шрифта" : "Font replacement"), enabled: true))
    let fontLabelApp = SGSimpleSettings.shared.fontReplacementName.isEmpty ? (lang == "ru" ? "Системный" : "System") : SGSimpleSettings.shared.fontReplacementName
    entries.append(.disclosure(id: id.count, section: .appearance, link: .fontReplacementPicker, text: (lang == "ru" ? "Шрифт" : "Font")))
    entries.append(.disclosure(id: id.count, section: .appearance, link: .fontReplacementImportFile, text: (lang == "ru" ? "Загрузить из файла (.ttf)" : "Import from file (.ttf)")))
    entries.append(.notice(id: id.count, section: .appearance, text: (lang == "ru" ? "Текущий: " : "Current: ") + fontLabelApp))
    let boldFontLabelApp = SGSimpleSettings.shared.fontReplacementBoldName.isEmpty ? (lang == "ru" ? "Авто" : "Auto") : SGSimpleSettings.shared.fontReplacementBoldName
    entries.append(.disclosure(id: id.count, section: .appearance, link: .fontReplacementBoldPicker, text: (lang == "ru" ? "Жирный шрифт" : "Bold font")))
    entries.append(.disclosure(id: id.count, section: .appearance, link: .fontReplacementBoldImportFile, text: i18n("FONT_IMPORT_BOLD_FROM_FILE", lang)))
    entries.append(.notice(id: id.count, section: .appearance, text: (lang == "ru" ? "Текущий: " : "Current: ") + boldFontLabelApp))
    entries.append(.fontSizeMultiplierSlider(id: id.count, section: .appearance, settingName: .fontReplacementSize, value: max(50, min(150, SGSimpleSettings.shared.fontReplacementSizeMultiplier))))
    entries.append(.notice(id: id.count, section: .appearance, text: (lang == "ru" ? "Размер шрифта (50–150%)." : "Font size (50–150%).")))
    let avatarRoundingBadge: String? = {
        guard SGSimpleSettings.shared.customAvatarRoundingEnabled else {
            return nil
        }
        let p = SGSimpleSettings.shared.avatarRoundingPercent
        if p <= 0 {
            return lang == "ru" ? "КВАДРАТ" : "SQUARE"
        }
        if p >= 100 {
            return lang == "ru" ? "КРУГ" : "CIRCLE"
        }
        return "\(p)%"
    }()
    entries.append(.header(id: id.count, section: .appearance, text: (lang == "ru" ? "АВАТАРЫ" : "AVATARS"), badge: avatarRoundingBadge))
    entries.append(.toggle(id: id.count, section: .appearance, settingName: .customAvatarRoundingEnabled, value: SGSimpleSettings.shared.customAvatarRoundingEnabled, text: (lang == "ru" ? "Закругление аватаров" : "Avatar rounding"), enabled: true))
    entries.append(.notice(id: id.count, section: .appearance, text: (lang == "ru" ? "Ползунок ниже влияет на аватары и кольцо историй." : "The slider below affects avatars and the story ring.")))
    if SGSimpleSettings.shared.customAvatarRoundingEnabled {
        let square = lang == "ru" ? "Квадрат" : "Square"
        let circle = lang == "ru" ? "Круг" : "Circle"
        let pct = max(Int32(0), min(Int32(100), SGSimpleSettings.shared.avatarRoundingPercent))
        entries.append(.percentageSlider(id: id.count, section: .appearance, settingName: .avatarRoundingPercent, value: pct, leftEdgeLabel: square, rightEdgeLabel: circle))
    }
    entries.append(.header(id: id.count, section: .appearance, text: (lang == "ru" ? "ГЛАВНЫЙ ЭКРАН" : "MAIN SCREEN"), badge: nil))
    let selfChatMode = SGSimpleSettings.shared.selfChatTitleModeValue
    entries.append(.oneFromManySelector(id: id.count, section: .appearance, settingName: .selfChatTitleMode, text: (lang == "ru" ? "Текст «Чаты» в шапке" : "«Chats» title in header"), value: glegSelfChatTitleModeLabel(selfChatMode, lang: lang), enabled: true))
    entries.append(.notice(id: id.count, section: .appearance, text: (lang == "ru" ? "Заголовок над лентой историй на вкладке чатов (не чат «Избранное»)." : "Title above the stories row on the Chats tab (not Saved Messages chat).")))
    entries.append(.header(id: id.count, section: .appearance, text: (lang == "ru" ? "ТЕКСТ И ЧИСЛА" : "TEXT & NUMBERS"), badge: nil))
    let disableCompactNumbersTitle = (lang == "ru" ? "Полные числа вместо округления" : "Full numbers instead of rounding")
    let disableCompactNumbersNotice = (lang == "ru" ? "Просмотры на постах будут показываться полным числом (например 1400 вместо 1.4K)." : "View counts on posts will show full number (e.g. 1400 instead of 1.4K).")
    entries.append(.toggle(id: id.count, section: .appearance, settingName: .disableCompactNumbers, value: SGSimpleSettings.shared.disableCompactNumbers, text: disableCompactNumbersTitle, enabled: true))
    entries.append(.notice(id: id.count, section: .appearance, text: disableCompactNumbersNotice))
    let disableZalgoTitle = (lang == "ru" ? "Убирать символы Zalgo" : "Remove Zalgo characters")
    let disableZalgoNotice = (lang == "ru" ? "Убирает искажающие текст символы Zalgo в именах и сообщениях." : "Removes Zalgo text distortion in names and messages.")
    entries.append(.toggle(id: id.count, section: .appearance, settingName: .disableZalgoText, value: SGSimpleSettings.shared.disableZalgoText, text: disableZalgoTitle, enabled: true))
    entries.append(.notice(id: id.count, section: .appearance, text: disableZalgoNotice))

    // MARK: Other (Другие функции)
    entries.append(.header(id: id.count, section: .other, text: (lang == "ru" ? "НАСТРОЙКИ GLEGRAM" : "GLEGRAM SETTINGS"), badge: nil))
    entries.append(.action(id: id.count, section: .other, actionType: "glegExportSettings" as AnyHashable, text: (lang == "ru" ? "Экспортировать настройки" : "Export settings"), kind: .generic))
    entries.append(.action(id: id.count, section: .other, actionType: "glegImportSettings" as AnyHashable, text: (lang == "ru" ? "Загрузить настройки" : "Import settings"), kind: .generic))
    entries.append(.notice(id: id.count, section: .other, text: (lang == "ru" ? "JSON с включёнными функциями и значениями. Импорт перезаписывает совпадающие ключи." : "JSON with enabled features and values. Import overwrites matching keys.")))
    entries.append(.header(id: id.count, section: .other, text: (lang == "ru" ? "ДРУГИЕ ФУНКЦИИ" : "OTHER"), badge: nil))
    let chatExportTitle = (lang == "ru" ? "Экспорт чата" : "Export chat")
    let chatExportNotice = (lang == "ru"
        ? "В профиле пользователя во вкладке «Ещё» появится пункт «Экспорт чата» — экспорт истории в JSON, TXT или HTML."
        : "In the user profile under «More» a «Export chat» item will appear — export history to JSON, TXT or HTML.")
    entries.append(.toggle(id: id.count, section: .other, settingName: .chatExportEnabled, value: SGSimpleSettings.shared.chatExportEnabled, text: chatExportTitle, enabled: true))
    entries.append(.notice(id: id.count, section: .other, text: chatExportNotice))
    entries.append(.toggle(id: id.count, section: .other, settingName: .scrollToTopButtonEnabled, value: SGSimpleSettings.shared.scrollToTopButtonEnabled, text: i18n("SCROLL_TO_TOP_TITLE", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .other, text: i18n("SCROLL_TO_TOP_NOTICE", lang)))
    let unlimitedFavTitle = (lang == "ru" ? "Неограниченные избранные стикеры" : "Unlimited favorite stickers")
    let unlimitedFavNotice = (lang == "ru" ? "Убирает ограничение на число стикеров в избранном." : "Removes the limit on favorite stickers count.")
    entries.append(.toggle(id: id.count, section: .other, settingName: .unlimitedFavoriteStickers, value: SGSimpleSettings.shared.unlimitedFavoriteStickers, text: unlimitedFavTitle, enabled: true))
    entries.append(.notice(id: id.count, section: .other, text: unlimitedFavNotice))
    let telescopeTitle = (lang == "ru" ? "Создание видео кружков и голосовых сообщений" : "Creating video circles and voice messages")
    let telescopeNotice = (lang == "ru"
                          ? "Позволяет создавать видео кружки и голосовые сообщения из видео."
                          : "Allows creating video circles and voice messages from video.")
    entries.append(.toggle(id: id.count, section: .other, settingName: .enableTelescope, value: SGSimpleSettings.shared.enableTelescope, text: telescopeTitle, enabled: true))
    entries.append(.notice(id: id.count, section: .other, text: telescopeNotice))
    
    let emojiDownloadTitle = (lang == "ru" ? "Скачивать эмодзи и стикеры в галерею" : "Download emoji and stickers to gallery")
    let emojiDownloadNotice = (lang == "ru" ? "При зажатии эмодзи или стикера в контекстном меню появится сохранение в галерею." : "When you long-press an emoji or sticker, save to gallery appears in the context menu.")
    entries.append(.toggle(id: id.count, section: .other, settingName: .emojiDownloaderEnabled, value: SGSimpleSettings.shared.emojiDownloaderEnabled, text: emojiDownloadTitle, enabled: true))
    entries.append(.notice(id: id.count, section: .other, text: emojiDownloadNotice))
    
    let feelRichTitle = (lang == "ru" ? "Локальный баланс звёзд" : "Local stars balance")
    entries.append(.toggle(id: id.count, section: .other, settingName: .feelRichEnabled, value: SGSimpleSettings.shared.feelRichEnabled, text: feelRichTitle, enabled: true))
    let starsAmountText: String = {
        let raw = SGSimpleSettings.shared.feelRichStarsAmount
        if raw.isEmpty { return "—" }
        let trimmed = String(raw.prefix(32))
        return trimmed
    }()
    entries.append(.disclosure(id: id.count, section: .other, link: .feelRichAmount, text: (lang == "ru" ? "Изменить сумму" : "Change amount") + " (\(starsAmountText))"))
    if LuxGramFeatures.pluginsEnabled {
        let pluginItems = PluginRunner.shared.allSettingsItems()
        if !pluginItems.isEmpty {
            // Group by section name preserving order
            var sectionOrder: [String] = []
            var sectionMap: [String: [(pluginId: String, section: String, title: String, actionId: String)]] = [:]
            for item in pluginItems {
                let sec = item.section
                if sectionMap[sec] == nil {
                    sectionOrder.append(sec)
                    sectionMap[sec] = []
                }
                sectionMap[sec]?.append(item)
            }
            for sec in sectionOrder {
                entries.append(.header(id: id.count, section: .other, text: sec.uppercased(), badge: nil))
                for item in sectionMap[sec] ?? [] {
                    entries.append(.action(id: id.count, section: .other, actionType: "plugin:\(item.pluginId):\(item.actionId)" as AnyHashable, text: item.title, kind: .generic))
                }
            }
        }
    }
    
    // MARK: Fake Location
    entries.append(.header(id: id.count, section: .fakeLocation, text: (lang == "ru" ? "ФЕЙКОВАЯ ГЕОЛОКАЦИЯ" : "FAKE LOCATION"), badge: nil))
    let fakeLocationTitle = (lang == "ru" ? "Включить фейковую геолокацию" : "Enable Fake Location")
    let fakeLocationNotice = (lang == "ru"
                              ? "Подменяет ваше реальное местоположение на выбранное. Работает во всех приложениях, использующих геолокацию."
                              : "Replaces your real location with the selected one. Works in all apps that use location services.")
    entries.append(.toggle(id: id.count, section: .fakeLocation, settingName: .fakeLocationEnabled, value: SGSimpleSettings.shared.fakeLocationEnabled, text: fakeLocationTitle, enabled: true))
    entries.append(.notice(id: id.count, section: .fakeLocation, text: fakeLocationNotice))
    
    let pickLocationTitle = (lang == "ru" ? "Выбрать местоположение" : "Pick Location")
    entries.append(.disclosure(id: id.count, section: .fakeLocation, link: .fakeLocationPicker, text: pickLocationTitle))
    
    // Show current coordinates if set
    if SGSimpleSettings.shared.fakeLatitude != 0.0 && SGSimpleSettings.shared.fakeLongitude != 0.0 {
        let coordsText = String(format: (lang == "ru" ? "Текущие координаты: lat: %.6f lon: %.6f" : "Current coordinates: lat: %.6f lon: %.6f"), SGSimpleSettings.shared.fakeLatitude, SGSimpleSettings.shared.fakeLongitude)
        entries.append(.notice(id: id.count, section: .fakeLocation, text: coordsText))
    } else {
        let noCoordsText = (lang == "ru" ? "Координаты не выбраны. Нажмите 'Выбрать местоположение' для настройки." : "No coordinates selected. Tap 'Pick Location' to configure.")
        entries.append(.notice(id: id.count, section: .fakeLocation, text: noCoordsText))
    }
    
    // MARK: Подглядеть онлайн (Peek online)
    entries.append(.header(id: id.count, section: .onlineStatusRecording, text: (lang == "ru" ? "ПОДГЛЯДЕТЬ ОНЛАЙН" : "PEEK ONLINE"), badge: nil))
    let peekOnlineTitle = (lang == "ru" ? "Включить «Подглядеть онлайн»" : "Enable «Peek online»")
    let peekOnlineNotice = (lang == "ru"
        ? "Эмулирует возможность Premium «Время захода»: показывает последний онлайн у тех, кто не скрывал время захода, но скрыл его от вас. Пользователи с надписью «когда?» в профиле — время можно подсмотреть. Подписчикам Premium не нужно. Принцип: 1) Если аккаунтов несколько — статус может быть взят через другой аккаунт (мост). 2) Краткосрочная инверсия: на долю секунды «Видно всем» → фиксируется и показывается статус → настройки возвращаются."
        : "Emulates Premium «Last seen»: shows last online for users who did not hide it from everyone but hid it from you. Users with «when?» in profile can be peeked. Not needed for Premium subscribers. How: 1) With multiple accounts, status may be fetched via another account (bridge). 2) Short inversion: «Visible to everyone» for a fraction of a second → status captured and shown → settings restored.")
    entries.append(.toggle(id: id.count, section: .onlineStatusRecording, settingName: .enableOnlineStatusRecording, value: SGSimpleSettings.shared.enableOnlineStatusRecording, text: peekOnlineTitle, enabled: true))
    entries.append(.notice(id: id.count, section: .onlineStatusRecording, text: peekOnlineNotice))
    
    return filterSGItemListUIEntrires(entries: entries, by: state.searchQuery)
}

public func gleGramSettingsController(context: AccountContext) -> ViewController {
    if let status = cachedLuxGramUserStatus(), !status.access.glegramTab, let promo = status.glegramPromo {
        return gleGramPaywallController(context: context, promo: promo, trialAvailable: status.trialAvailable)
    }

    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?
    #if canImport(FaceScanScreen)
    var presentAgeVerificationImpl: ((@escaping () -> Void) -> Void)?
    #endif
    
    /// Monotonic tick so pushed tab `ItemListController` always gets a new combineLatest emission (Bool `true`→`true` was unreliable for some flows).
    final class LuxGramSettingsReloadBump {
        private var generation: UInt64 = 0
        let promise = ValuePromise(UInt64(0), ignoreRepeated: false)
        func bump() {
            generation += 1
            promise.set(generation)
        }
    }
    let reloadBump = LuxGramSettingsReloadBump()
    var fontNotifyWorkItem: DispatchWorkItem?
    let initialState = LuxGramSettingsControllerState()
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((LuxGramSettingsControllerState) -> LuxGramSettingsControllerState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }
    
    let updateSensitiveContentDisposable = MetaDisposable()
    
    let updatedContentSettingsConfiguration = contentSettingsConfiguration(network: context.account.network)
    |> map(Optional.init)
    let contentSettingsConfigurationPromise = Promise<ContentSettingsConfiguration?>()
    contentSettingsConfigurationPromise.set(.single(nil)
    |> then(updatedContentSettingsConfiguration))
    
    var argumentsRef: SGItemListArguments<SGBoolSetting, LuxGramSliderSetting, LuxGramOneFromManySetting, LuxGramDisclosureLink, AnyHashable>?
    let arguments = SGItemListArguments<SGBoolSetting, LuxGramSliderSetting, LuxGramOneFromManySetting, LuxGramDisclosureLink, AnyHashable>(
        context: context,
        setBoolValue: { setting, value in
            switch setting {
            case .showDeletedMessages:
                SGSimpleSettings.shared.showDeletedMessages = value
            case .saveDeletedMessagesMedia:
                SGSimpleSettings.shared.saveDeletedMessagesMedia = value
            case .saveDeletedMessagesReactions:
                SGSimpleSettings.shared.saveDeletedMessagesReactions = value
            case .saveDeletedMessagesForBots:
                SGSimpleSettings.shared.saveDeletedMessagesForBots = value
            case .saveEditHistory:
                SGSimpleSettings.shared.saveEditHistory = value
            case .enableLocalMessageEditing:
                SGSimpleSettings.shared.enableLocalMessageEditing = value
            case .disableOnlineStatus:
                SGSimpleSettings.shared.disableOnlineStatus = value
            case .disableTypingStatus:
                SGSimpleSettings.shared.disableTypingStatus = value
            case .disableRecordingVideoStatus:
                SGSimpleSettings.shared.disableRecordingVideoStatus = value
            case .disableUploadingVideoStatus:
                SGSimpleSettings.shared.disableUploadingVideoStatus = value
            case .disableVCMessageRecordingStatus:
                SGSimpleSettings.shared.disableVCMessageRecordingStatus = value
            case .disableVCMessageUploadingStatus:
                SGSimpleSettings.shared.disableVCMessageUploadingStatus = value
            case .disableUploadingPhotoStatus:
                SGSimpleSettings.shared.disableUploadingPhotoStatus = value
            case .disableUploadingFileStatus:
                SGSimpleSettings.shared.disableUploadingFileStatus = value
            case .disableChoosingLocationStatus:
                SGSimpleSettings.shared.disableChoosingLocationStatus = value
            case .disableChoosingContactStatus:
                SGSimpleSettings.shared.disableChoosingContactStatus = value
            case .disablePlayingGameStatus:
                SGSimpleSettings.shared.disablePlayingGameStatus = value
            case .disableRecordingRoundVideoStatus:
                SGSimpleSettings.shared.disableRecordingRoundVideoStatus = value
            case .disableUploadingRoundVideoStatus:
                SGSimpleSettings.shared.disableUploadingRoundVideoStatus = value
            case .disableSpeakingInGroupCallStatus:
                SGSimpleSettings.shared.disableSpeakingInGroupCallStatus = value
            case .disableChoosingStickerStatus:
                SGSimpleSettings.shared.disableChoosingStickerStatus = value
            case .disableEmojiInteractionStatus:
                SGSimpleSettings.shared.disableEmojiInteractionStatus = value
            case .disableEmojiAcknowledgementStatus:
                SGSimpleSettings.shared.disableEmojiAcknowledgementStatus = value
            case .disableMessageReadReceipt:
                SGSimpleSettings.shared.disableMessageReadReceipt = value
            case .ghostModeMarkReadOnReply:
                SGSimpleSettings.shared.ghostModeMarkReadOnReply = value
            case .disableStoryReadReceipt:
                SGSimpleSettings.shared.disableStoryReadReceipt = value
            case .disableAllAds:
                SGSimpleSettings.shared.disableAllAds = value
            case .hideProxySponsor:
                SGSimpleSettings.shared.hideProxySponsor = value
                NotificationCenter.default.post(name: .sgHideProxySponsorDidChange, object: nil)
            case .enableSavingProtectedContent:
                SGSimpleSettings.shared.enableSavingProtectedContent = value
            case .forwardRestrictedAsCopy:
                SGSimpleSettings.shared.forwardRestrictedAsCopy = value
            case .enableSavingSelfDestructingMessages:
                SGSimpleSettings.shared.enableSavingSelfDestructingMessages = value
            case .faceBlurInVideoMessages:
                SGSimpleSettings.shared.faceBlurInVideoMessages = value
            case .disableScreenshotDetection:
                SGSimpleSettings.shared.disableScreenshotDetection = value
            case .disableSecretChatBlurOnScreenshot:
                SGSimpleSettings.shared.disableSecretChatBlurOnScreenshot = value
            case .enableLocalPremium:
                SGSimpleSettings.shared.enableLocalPremium = value
                NotificationCenter.default.post(name: .sgEnableLocalPremiumDidChange, object: nil)
            case .voiceChangerEnabled:
                VoiceMorpherManager.shared.isEnabled = value
                if value, VoiceMorpherManager.shared.selectedPresetId == 0 {
                    VoiceMorpherManager.shared.selectedPresetId = VoiceMorpherManager.VoicePreset.anonymous.rawValue
                }
                SGSimpleSettings.shared.voiceChangerEnabled = value
            case .scrollToTopButtonEnabled:
                SGSimpleSettings.shared.scrollToTopButtonEnabled = value
            case .hideReactions:
                SGSimpleSettings.shared.hideReactions = value
            case .chatExportEnabled:
                SGSimpleSettings.shared.chatExportEnabled = value
            case .disableCompactNumbers:
                SGSimpleSettings.shared.disableCompactNumbers = value
            case .disableZalgoText:
                SGSimpleSettings.shared.disableZalgoText = value
            case .fakeLocationEnabled:
                SGSimpleSettings.shared.fakeLocationEnabled = value
            case .enableVideoToCircleOrVoice:
                SGSimpleSettings.shared.enableVideoToCircleOrVoice = value
            case .enableTelescope:
                SGSimpleSettings.shared.enableTelescope = value
            case .enableFontReplacement:
                SGSimpleSettings.shared.enableFontReplacement = value
                context.sharedContext.notifyFontSettingsChanged()
            case .unlimitedFavoriteStickers:
                SGSimpleSettings.shared.unlimitedFavoriteStickers = value
            case .enableOnlineStatusRecording:
                SGSimpleSettings.shared.enableOnlineStatusRecording = value
            case .sensitiveContentEnabled:
                let update = {
                    let _ = (contentSettingsConfigurationPromise.get()
                    |> take(1)
                    |> deliverOnMainQueue).start(next: { [weak contentSettingsConfigurationPromise] settings in
                        if var settings {
                            settings.sensitiveContentEnabled = value
                            contentSettingsConfigurationPromise?.set(.single(settings))
                        }
                    })
                    updateSensitiveContentDisposable.set(updateRemoteContentSettingsConfiguration(postbox: context.account.postbox, network: context.account.network, sensitiveContentEnabled: value).start())
                }
                
                if value {
                    #if canImport(FaceScanScreen)
                    if requireAgeVerification(context: context) {
                        presentAgeVerificationImpl?(update)
                    } else {
                        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                        let alertController = textAlertController(
                            context: context,
                            title: presentationData.strings.SensitiveContent_Enable_Title,
                            text: presentationData.strings.SensitiveContent_Enable_Text,
                            actions: [
                                TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                                TextAlertAction(type: .defaultAction, title: presentationData.strings.SensitiveContent_Enable_Confirm, action: {
                                    update()
                                })
                            ]
                        )
                        presentControllerImpl?(alertController, nil)
                    }
                    #else
                    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                    let alertController = textAlertController(
                        context: context,
                        title: presentationData.strings.SensitiveContent_Enable_Title,
                        text: presentationData.strings.SensitiveContent_Enable_Text,
                        actions: [
                            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                            TextAlertAction(type: .defaultAction, title: presentationData.strings.SensitiveContent_Enable_Confirm, action: {
                                update()
                            })
                        ]
                    )
                    presentControllerImpl?(alertController, nil)
                    #endif
                } else {
                    update()
                }
            case .emojiDownloaderEnabled:
                SGSimpleSettings.shared.emojiDownloaderEnabled = value
            case .feelRichEnabled:
                SGSimpleSettings.shared.feelRichEnabled = value
            case .giftIdEnabled:
                SGSimpleSettings.shared.giftIdEnabled = value
            case .fakeProfileEnabled:
                SGSimpleSettings.shared.fakeProfileEnabled = value
            case .customAvatarRoundingEnabled:
                SGSimpleSettings.shared.customAvatarRoundingEnabled = value
                NotificationCenter.default.post(name: .sgAvatarRoundingSettingsDidChange, object: nil)
            default:
                break
            }
            reloadBump.bump()
        },
        updateSliderValue: { setting, value in
            if case .fontReplacementSize = setting {
                SGSimpleSettings.shared.fontReplacementSizeMultiplier = value
                // Троттлинг: не перезагружаем список (подпись обновляется в ноде), notifyFontSettingsChanged — раз в 120 мс
                fontNotifyWorkItem?.cancel()
                let item = DispatchWorkItem { [weak context] in
                    context?.sharedContext.notifyFontSettingsChanged()
                }
                fontNotifyWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
                // reloadPromise не вызываем — SliderFontSizeMultiplierItemNode обновляет подпись локально
            } else if case .ghostModeMessageSendDelay = setting {
                SGSimpleSettings.shared.ghostModeMessageSendDelaySeconds = value
                reloadBump.bump()
            } else if case .avatarRoundingPercent = setting {
                SGSimpleSettings.shared.avatarRoundingPercent = value
                NotificationCenter.default.post(name: .sgAvatarRoundingSettingsDidChange, object: nil)
                reloadBump.bump()
            }
        },
        setOneFromManyValue: { setting in
            if case .onlineStatusRecordingInterval = setting {
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let lang = presentationData.strings.baseLanguageCode
                let actionSheet = ActionSheetController(presentationData: presentationData)
                let intervals: [Int32] = [5, 10, 15, 20, 30, 60]
                var items: [ActionSheetItem] = []
                for min in intervals {
                    let title = lang == "ru" ? "\(min) мин" : "\(min) min"
                    items.append(ActionSheetButtonItem(title: title, color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        SGSimpleSettings.shared.onlineStatusRecordingIntervalMinutes = min
                        reloadBump.bump()
                    }))
                }
                actionSheet.setItemGroups([ActionSheetItemGroup(items: items), ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                    })
                ])])
                presentControllerImpl?(actionSheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
                return
            }
            if case .selfChatTitleMode = setting {
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let lang = presentationData.strings.baseLanguageCode
                let actionSheet = ActionSheetController(presentationData: presentationData)
                var items: [ActionSheetItem] = []
                for mode in SelfChatTitleMode.allCases {
                    items.append(ActionSheetButtonItem(title: glegSelfChatTitleModeLabel(mode, lang: lang), color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        SGSimpleSettings.shared.selfChatTitleModeValue = mode
                        NotificationCenter.default.post(name: .sgSelfChatTitleSettingsDidChange, object: nil)
                        reloadBump.bump()
                        DispatchQueue.main.async {
                            reloadBump.bump()
                        }
                    }))
                }
                actionSheet.setItemGroups([ActionSheetItemGroup(items: items), ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                    })
                ])])
                presentControllerImpl?(actionSheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
                return
            }
        },
        openDisclosureLink: { link in
            if link == .channelLink {
                let pd = context.sharedContext.currentPresentationData.with { $0 }
                context.sharedContext.openExternalUrl(context: context, urlContext: .generic, url: "https://t.me/glegramios", forceExternal: true, presentationData: pd, navigationController: nil, dismissInput: {})
                return
            }
            if link == .chatLink {
                let pd = context.sharedContext.currentPresentationData.with { $0 }
                context.sharedContext.openExternalUrl(context: context, urlContext: .generic, url: "https://t.me/glegramios_chat", forceExternal: true, presentationData: pd, navigationController: nil, dismissInput: {})
                return
            }
            if link == .forumLink {
                let pd = context.sharedContext.currentPresentationData.with { $0 }
                context.sharedContext.openExternalUrl(context: context, urlContext: .generic, url: "https://t.me/glegram_forum", forceExternal: true, presentationData: pd, navigationController: nil, dismissInput: {})
                return
            }
            if link == .betaChannel {
                if let status = cachedLuxGramUserStatus(), let betaConfig = status.betaConfig, let url = betaConfig.channelUrl, isUrlSafeForExternalOpen(url) {
                    let pd = context.sharedContext.currentPresentationData.with { $0 }
                    context.sharedContext.openExternalUrl(context: context, urlContext: .generic, url: url, forceExternal: false, presentationData: pd, navigationController: nil, dismissInput: {})
                }
                return
            }
            if link == .voiceChangerVoicePicker {
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let lang = presentationData.strings.baseLanguageCode
                let ru = lang == "ru"
                let actionSheet = ActionSheetController(presentationData: presentationData)
                var items: [ActionSheetItem] = []
                for preset in VoiceMorpherManager.VoicePreset.allCases where preset != .disabled {
                    let title = preset.title(langIsRu: ru)
                    let subtitle = preset.subtitle(langIsRu: ru)
                    items.append(ActionSheetButtonItem(title: "\(title) — \(subtitle)", color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        VoiceMorpherManager.shared.selectedPresetId = preset.rawValue
                        reloadBump.bump()
                    }))
                }
                actionSheet.setItemGroups([ActionSheetItemGroup(items: items), ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                    })
                ])])
                presentControllerImpl?(actionSheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
                return
            }
            if link == .fakeLocationPicker {
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                #if canImport(SGFakeLocation)
                let pickerController = FakeLocationPickerController(presentationData: presentationData, onSave: {
                    reloadBump.bump()
                })
                pushControllerImpl?(pickerController)
                #endif
            } else if link == .appearanceTab {
                pushControllerImpl?(buildLuxGramTabController(tab: .appearance, args: argumentsRef!))
            } else if link == .securityTab {
                pushControllerImpl?(buildLuxGramTabController(tab: .security, args: argumentsRef!))
            } else if link == .otherTab {
                pushControllerImpl?(buildLuxGramTabController(tab: .other, args: argumentsRef!))
            } else if link == .tabOrganizer {
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let tabOrganizerController = TabOrganizerController(context: context, presentationData: presentationData, onSave: {
                    reloadBump.bump()
                })
                pushControllerImpl?(tabOrganizerController)
            } else if link == .profileCover {
                pushControllerImpl?(ProfileCoverController(context: context))
            } else if link == .fakeProfileSettings {
                pushControllerImpl?(FakeProfileSettingsController(context: context, onSave: { reloadBump.bump() }))
            } else if link == .feelRichAmount {
                pushControllerImpl?(FeelRichAmountController(context: context, onSave: { reloadBump.bump() }))
            } else if link == .savedDeletedMessagesList {
                pushControllerImpl?(savedDeletedMessagesListController(context: context))
            } else if link == .doubleBottomSettings {
                pushControllerImpl?(doubleBottomSettingsController(context: context))
            } else if link == .protectedChatsSettings {
                pushControllerImpl?(protectedChatsSettingsController(context: context))
            } else if link == .pluginsSettings, LuxGramFeatures.pluginsEnabled {
                PluginRunner.shared.ensureLoaded()
                pushControllerImpl?(PluginListController(context: context, onPluginsChanged: {
                    PluginRunner.shared.ensureLoaded()
                    reloadBump.bump()
                }))
            } else if link == .fontReplacementPicker {
                let pickerController = FontReplacementPickerController(context: context, mode: .main, onSave: {
                    reloadBump.bump()
                    context.sharedContext.notifyFontSettingsChanged()
                })
                presentControllerImpl?(pickerController, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
            } else if link == .fontReplacementBoldPicker {
                let pickerController = FontReplacementPickerController(context: context, mode: .bold, onSave: {
                    reloadBump.bump()
                    context.sharedContext.notifyFontSettingsChanged()
                })
                presentControllerImpl?(pickerController, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
            } else if link == .fontReplacementBoldImportFile {
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let picker = legacyICloudFilePicker(
                    theme: presentationData.theme,
                    mode: .import,
                    documentTypes: ["public.font", "public.truetype-ttf-font", "public.opentype"],
                    dismissed: {},
                    completion: { urls in
                        guard let url = urls.first else { return }
                        _ = url.startAccessingSecurityScopedResource()
                        defer { url.stopAccessingSecurityScopedResource() }
                        if let provider = CGDataProvider(url: url as CFURL),
                           let cgFont = CGFont(provider),
                           let name = cgFont.postScriptName as String?, !name.isEmpty {
                            let fileManager = FileManager.default
                            if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                                let fontsDir = documentsURL.appendingPathComponent("LuxGramFonts", isDirectory: true)
                                try? fileManager.createDirectory(at: fontsDir, withIntermediateDirectories: true)
                                let destURL = fontsDir.appendingPathComponent("bold.ttf")
                                try? fileManager.removeItem(at: destURL)
                                if (try? fileManager.copyItem(at: url, to: destURL)) != nil {
                                    SGSimpleSettings.shared.fontReplacementBoldFilePath = destURL.path
                                }
                            }
                            CTFontManagerRegisterFontURLs([url] as CFArray, .process, true, nil)
                            SGSimpleSettings.shared.fontReplacementBoldName = name
                            context.sharedContext.notifyFontSettingsChanged()
                            reloadBump.bump()
                        }
                    }
                )
                presentControllerImpl?(picker, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
            } else if link == .fontReplacementImportFile {
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let picker = legacyICloudFilePicker(
                    theme: presentationData.theme,
                    mode: .import,
                    documentTypes: ["public.font", "public.truetype-ttf-font", "public.opentype"],
                    dismissed: {},
                    completion: { urls in
                        guard let url = urls.first else { return }
                        _ = url.startAccessingSecurityScopedResource()
                        defer { url.stopAccessingSecurityScopedResource() }
                        if let provider = CGDataProvider(url: url as CFURL),
                           let cgFont = CGFont(provider),
                           let name = cgFont.postScriptName as String?, !name.isEmpty {
                            let fileManager = FileManager.default
                            if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                                let fontsDir = documentsURL.appendingPathComponent("LuxGramFonts", isDirectory: true)
                                try? fileManager.createDirectory(at: fontsDir, withIntermediateDirectories: true)
                                let destURL = fontsDir.appendingPathComponent("main.ttf")
                                try? fileManager.removeItem(at: destURL)
                                if (try? fileManager.copyItem(at: url, to: destURL)) != nil {
                                    SGSimpleSettings.shared.fontReplacementFilePath = destURL.path
                                }
                            }
                            CTFontManagerRegisterFontURLs([url] as CFArray, .process, true, nil)
                            SGSimpleSettings.shared.fontReplacementName = name
                            context.sharedContext.notifyFontSettingsChanged()
                            reloadBump.bump()
                        }
                    }
                )
                presentControllerImpl?(picker, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
            }
        },
        action: { actionType in
            guard let actionString = actionType as? String else { return }
            if actionString.hasPrefix("plugin:") {
                guard LuxGramFeatures.pluginsEnabled else { return }
                let parts = actionString.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
                if parts.count >= 3 {
                    let pluginId = String(parts[1])
                    let actionId = String(parts[2])
                    PluginRunner.shared.runAction(pluginId: pluginId, actionId: actionId)
                }
                return
            }
            if actionString == "glegExportSettings" {
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let lang = presentationData.strings.baseLanguageCode
                do {
                    let url = try SGSimpleSettings.exportLuxGramSettingsJSONFile()
                    let picker = legacyICloudFilePicker(
                        theme: presentationData.theme,
                        mode: .export,
                        url: url,
                        documentTypes: ["public.json"],
                        dismissed: {
                            try? FileManager.default.removeItem(at: url)
                        },
                        completion: { _ in
                            try? FileManager.default.removeItem(at: url)
                        }
                    )
                    presentControllerImpl?(picker, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
                } catch {
                    let alert = textAlertController(
                        context: context,
                        title: lang == "ru" ? "Ошибка" : "Error",
                        text: error.localizedDescription,
                        actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
                    )
                    presentControllerImpl?(alert, nil)
                }
                return
            }
            if actionString == "glegImportSettings" {
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let lang = presentationData.strings.baseLanguageCode
                let picker = legacyICloudFilePicker(
                    theme: presentationData.theme,
                    mode: .import,
                    documentTypes: ["public.json", "public.text", "public.plain-text"],
                    dismissed: {},
                    completion: { urls in
                        guard let url = urls.first else { return }
                        let accessed = url.startAccessingSecurityScopedResource()
                        defer {
                            if accessed {
                                url.stopAccessingSecurityScopedResource()
                            }
                        }
                        guard let data = try? Data(contentsOf: url) else {
                            return
                        }
                        do {
                            let count = try SGSimpleSettings.importLuxGramSettingsJSON(data: data)
                            context.sharedContext.notifyFontSettingsChanged()
                            NotificationCenter.default.post(name: .sgAvatarRoundingSettingsDidChange, object: nil)
                            NotificationCenter.default.post(name: .sgSelfChatTitleSettingsDidChange, object: nil)
                            NotificationCenter.default.post(name: .sgPeerInfoAppearanceSettingsDidChange, object: nil)
                            NotificationCenter.default.post(name: .sgHideProxySponsorDidChange, object: nil)
                            reloadBump.bump()
                            let okLine = lang == "ru" ? "Импортировано ключей: \(count)" : "Imported keys: \(count)"
                            let restartLine = i18n("Common.RestartRequired", lang)
                            let okText = okLine + "\n" + restartLine
                            presentControllerImpl?(UndoOverlayController(
                                presentationData: presentationData,
                                content: .succeed(text: okText, timeout: 4.0, customUndoText: nil),
                                elevatedLayout: false,
                                action: { _ in return false }
                            ), nil)
                        } catch {
                            let alert = textAlertController(
                                context: context,
                                title: lang == "ru" ? "Импорт" : "Import",
                                text: error.localizedDescription,
                                actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
                            )
                            presentControllerImpl?(alert, nil)
                        }
                    }
                )
                presentControllerImpl?(picker, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
                return
            }
            if actionString == "clearDeletedMessages" {
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let lang = presentationData.strings.baseLanguageCode
                let alertController = textAlertController(
                    context: context,
                    title: i18n("Settings.DeletedMessages.Clear.Title", lang),
                    text: i18n("Settings.DeletedMessages.Clear.Text", lang),
                    actions: [
                        TextAlertAction(type: .destructiveAction, title: presentationData.strings.Common_Delete, action: {
                            let _ = (SGDeletedMessages.clearAllDeletedMessages(postbox: context.account.postbox)
                                     |> deliverOnMainQueue).start(next: { count in
                                reloadBump.bump()
                                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                                let text: String
                                if count > 0 {
                                    text = lang == "ru"
                                        ? "Удалено сообщений: \(count)"
                                        : "Deleted messages: \(count)"
                                } else {
                                    text = lang == "ru"
                                        ? "Нет сохранённых удалённых сообщений"
                                        : "No saved deleted messages"
                                }
                                presentControllerImpl?(UndoOverlayController(
                                    presentationData: presentationData,
                                    content: .succeed(text: text, timeout: 3.0, customUndoText: nil),
                                    elevatedLayout: false,
                                    action: { _ in return false }
                                ), nil)
                            })
                        }),
                        TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_Cancel, action: {})
                    ]
                )
                presentControllerImpl?(alertController, nil)
            }

            if actionString == "markAllReadLocal" {
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let statusController = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
                presentControllerImpl?(statusController, nil)
                let markItems: [(groupId: EngineChatList.Group, filterPredicate: ChatListFilterPredicate?)] = [
                    (.root, nil),
                    (.archive, nil)
                ]
                let _ = (context.engine.messages.markAllChatsAsReadLocallyOnly(items: markItems)
                    |> deliverOnMainQueue).start(completed: {
                        statusController.dismiss()
                        reloadBump.bump()
                        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                        presentControllerImpl?(OverlayStatusController(theme: presentationData.theme, type: .success), nil)
                    })
            }

            if actionString == "markAllReadServer" {
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let statusController = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
                presentControllerImpl?(statusController, nil)
                let _ = (context.engine.messages.markAllChatsAsRead()
                    |> deliverOnMainQueue).start(completed: {
                        statusController.dismiss()
                        reloadBump.bump()
                        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                        presentControllerImpl?(OverlayStatusController(theme: presentationData.theme, type: .success), nil)
                    })
            }
            
        },
        searchInput: { searchQuery in
            updateState { state in
                var updatedState = state
                updatedState.searchQuery = searchQuery
                return updatedState
            }
        },
        iconResolver: { ref in
            guard let ref = ref else { return nil }
            guard let img = UIImage(bundleImageName: ref) else { return nil }
            // Иконки вкладок (LuxGramTab*) масштабируем до размера как у «Канал, Чат, Форум» (~29 pt)
            return scaleImageForListIcon(img, maxSize: 29.0) ?? img
        }
    )
    argumentsRef = arguments
    
    func buildLuxGramTabController(tab: LuxGramTab, args: SGItemListArguments<SGBoolSetting, LuxGramSliderSetting, LuxGramOneFromManySetting, LuxGramDisclosureLink, AnyHashable>) -> ViewController {
        let tabSignal = combineLatest(reloadBump.promise.get(), statePromise.get(), context.sharedContext.presentationData, contentSettingsConfigurationPromise.get())
        |> map { _, state, presentationData, contentSettingsConfiguration -> (ItemListControllerState, (ItemListNodeState, SGItemListArguments<SGBoolSetting, LuxGramSliderSetting, LuxGramOneFromManySetting, LuxGramDisclosureLink, AnyHashable>)) in
            let lang = presentationData.strings.baseLanguageCode
            let tabTitles = lang == "ru" ? ["Оформление", "Приватность", "Другие функции"] : ["Appearance", "Privacy", "Other"]
            let tabTitle = tabTitles[tab.rawValue]
            var tabState = state
            tabState.selectedTab = tab
            let allEntries = gleGramEntries(presentationData: presentationData, contentSettingsConfiguration: contentSettingsConfiguration, state: tabState, mediaBoxBasePath: context.account.postbox.mediaBox.basePath)
            let entriesFilteredByTab = gleGramEntriesFiltered(by: tab, entries: allEntries)
            let entries = filterSGItemListUIEntrires(entries: entriesFilteredByTab, by: tabState.searchQuery)
            let controllerState = ItemListControllerState(
                presentationData: ItemListPresentationData(presentationData),
                title: .text(tabTitle),
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
            return (controllerState, (listState, args))
        }
        let tabController = ItemListController(context: context, state: tabSignal)
        tabController.navigationItem.leftBarButtonItem = makeBackBarButtonItem(presentationData: context.sharedContext.currentPresentationData.with({ $0 }), controller: tabController)
        return tabController
    }
    
    let signal: Signal<(ItemListControllerState, (ItemListNodeState, SGItemListArguments<SGBoolSetting, LuxGramSliderSetting, LuxGramOneFromManySetting, LuxGramDisclosureLink, AnyHashable>)), NoError> = combineLatest(reloadBump.promise.get(), context.sharedContext.presentationData)
    |> map { _, presentationData -> (ItemListControllerState, (ItemListNodeState, SGItemListArguments<SGBoolSetting, LuxGramSliderSetting, LuxGramOneFromManySetting, LuxGramDisclosureLink, AnyHashable>)) in
        SGSimpleSettings.shared.currentAccountPeerId = "\(context.account.peerId.id._internalGetInt64Value())"
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("LuxGram"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let entries = gleGramRootEntries(presentationData: presentationData)
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
    
    let controller = ItemListController(context: context, state: signal)
    controller.navigationItem.leftBarButtonItem = makeBackBarButtonItem(presentationData: context.sharedContext.currentPresentationData.with({ $0 }), controller: controller)
    pushControllerImpl = { [weak controller] vc in controller?.push(vc) }
    presentControllerImpl = { [weak controller] c, a in
        guard let controller = controller else { return }
        // Present from the topmost VC in the navigation stack: when a tab controller
        // is pushed, the root controller's view is removed from the hierarchy by
        // UINavigationController, making its `window` nil and `present` a no-op.
        if let navController = controller.navigationController as? NavigationController,
           let topController = navController.viewControllers.last as? ViewController {
            topController.present(c, in: .window(.root), with: a)
        } else {
            controller.present(c, in: .window(.root), with: a)
        }
    }
    #if canImport(FaceScanScreen)
    presentAgeVerificationImpl = { [weak controller] update in
        guard let controller else {
            return
        }
        presentAgeVerification(context: context, parentController: controller, completion: {
            update()
        })
    }
    #endif
    
    return controller
}


```

### `LuxGram/SGSettingsUI/Sources/SGSettingsController.swift`

```swift
// MARK: LuxGram
import SGLogging
import SGSimpleSettings
import SGStrings
import SGAPIToken
#if canImport(SGDeletedMessages)
import SGDeletedMessages
#endif

import SGItemListUI
import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import MtProtoKit
import MessageUI
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import OverlayStatusController
import AccountContext
import AppBundle
import WebKit
import PeerNameColorScreen
import UndoUI


private enum SGControllerSection: Int32, SGItemListSection {
    case search
    case trending
    case content
    case tabs
    case folders
    case chatList
    case profiles
    case stories
    case translation
    case voiceMessages
    case calls
    case photo
    case stickers
    case videoNotes
    case contextMenu
    case accountColors
    case ghostMode
    case other
}

enum SGBoolSetting: String {
    case hidePhoneInSettings
    case showTabNames
    case showContactsTab
    case showCallsTab
    case wideTabBar
    case foldersAtBottom
    case startTelescopeWithRearCam
    case hideStories
    case uploadSpeedBoost
    case showProfileId
    case warnOnStoriesOpen
    case sendWithReturnKey
    case rememberLastFolder
    case sendLargePhotos
    case storyStealthMode
    case disableSwipeToRecordStory
    case disableDeleteChatSwipeOption
    case quickTranslateButton
    case showRepostToStory
    case contextShowSelectFromUser
    case contextShowSaveToCloud
    case contextShowHideForwardName
    case contextShowRestrict
    case contextShowReport
    case contextShowReply
    case contextShowPin
    case contextShowSaveMedia
    case contextShowMessageReplies
    case contextShowJson
    case disableScrollToNextChannel
    case disableScrollToNextTopic
    case disableChatSwipeOptions
    case disableGalleryCamera
    case disableGalleryCameraPreview
    case disableSendAsButton
    case disableSnapDeletionEffect
    case stickerTimestamp
    case hideRecordingButton
    case hideTabBar
    case showDC
    case showCreationDate
    case showRegDate
    case compactChatList
    case compactFolderNames
    case allChatsHidden
    case defaultEmojisFirst
    case messageDoubleTapActionOutgoingEdit
    case wideChannelPosts
    case forceEmojiTab
    case forceBuiltInMic
    case secondsInMessages
    case hideChannelBottomButton
    case confirmCalls
    case swipeForVideoPIP
    case enableVoipTcp
    case nyStyleSnow
    case nyStyleLightning
    case tabBarSearchEnabled
    case showDeletedMessages
    case saveDeletedMessagesMedia
    case saveDeletedMessagesReactions
    case saveDeletedMessagesForBots
    case saveEditHistory
    case enableLocalMessageEditing
    // Ghost Mode settings
    case disableOnlineStatus
    case disableTypingStatus
    case disableRecordingVideoStatus
    case disableUploadingVideoStatus
    case disableVCMessageRecordingStatus
    case disableVCMessageUploadingStatus
    case disableUploadingPhotoStatus
    case disableUploadingFileStatus
    case disableChoosingLocationStatus
    case disableChoosingContactStatus
    case disablePlayingGameStatus
    case disableRecordingRoundVideoStatus
    case disableUploadingRoundVideoStatus
    case disableSpeakingInGroupCallStatus
    case disableChoosingStickerStatus
    case disableEmojiInteractionStatus
    case disableEmojiAcknowledgementStatus
    case disableMessageReadReceipt
    case ghostModeMarkReadOnReply
    case disableStoryReadReceipt
    case disableAllAds
    case hideProxySponsor
    case enableSavingProtectedContent
    case forwardRestrictedAsCopy
    case sensitiveContentEnabled
    case disableScreenshotDetection
    case enableSavingSelfDestructingMessages
    case disableSecretChatBlurOnScreenshot
    case enableLocalPremium
    case scrollToTopButtonEnabled
    case fakeLocationEnabled
    case enableVideoToCircleOrVoice
    case enableTelescope
    case enableFontReplacement
    case disableCompactNumbers
    case disableZalgoText
    case unlimitedFavoriteStickers
    case enableOnlineStatusRecording
    case addMusicFromDeviceToProfile
    case hideReactions
    case pluginSystemEnabled
    case chatExportEnabled
    case emojiDownloaderEnabled
    case feelRichEnabled
    case giftIdEnabled
    case fakeProfileEnabled
    case faceBlurInVideoMessages
    case customAvatarRoundingEnabled
    case voiceChangerEnabled
}

private enum SGOneFromManySetting: String {
    case nyStyle
    case bottomTabStyle
    case downloadSpeedBoost
    case allChatsTitleLengthOverride
//    case allChatsFolderPositionOverride
    case translationBackend
    case transcriptionBackend
}

private enum SGSliderSetting: String {
    case accountColorsSaturation
    case outgoingPhotoQuality
    case stickerSize
}

private enum SGDisclosureLink: String {
    case contentSettings
    case languageSettings
}

private struct PeerNameColorScreenState: Equatable {
    var updatedNameColor: PeerNameColor?
    var updatedBackgroundEmojiId: Int64?
}

private struct SGSettingsControllerState: Equatable {
    var searchQuery: String?
}

private typealias SGControllerEntry = SGItemListUIEntry<SGControllerSection, SGBoolSetting, SGSliderSetting, SGOneFromManySetting, SGDisclosureLink, AnyHashable>

private func SGControllerEntries(presentationData: PresentationData, callListSettings: CallListSettings, experimentalUISettings: ExperimentalUISettings, SGSettings: SGUISettings, appConfiguration: AppConfiguration, nameColors: PeerNameColors, state: SGSettingsControllerState) -> [SGControllerEntry] {
    
    let lang = presentationData.strings.baseLanguageCode
    let strings = presentationData.strings
    let newStr = strings.Settings_New
    var entries: [SGControllerEntry] = []
    
    let id = SGItemListCounter()
    
    entries.append(.searchInput(id: id.count, section: .search, title: NSAttributedString(string: "🔍"), text: state.searchQuery ?? "", placeholder: strings.Common_Search))
    
    
    if SGSimpleSettings.shared.canUseNY {
        entries.append(.header(id: id.count, section: .trending, text: i18n("Settings.NY.Header", lang), badge: newStr))
        entries.append(.toggle(id: id.count, section: .trending, settingName: .nyStyleSnow, value: SGSimpleSettings.shared.nyStyle == SGSimpleSettings.NYStyle.snow.rawValue, text: i18n("Settings.NY.Style.snow", lang), enabled: true))
        entries.append(.toggle(id: id.count, section: .trending, settingName: .nyStyleLightning, value: SGSimpleSettings.shared.nyStyle == SGSimpleSettings.NYStyle.lightning.rawValue, text: i18n("Settings.NY.Style.lightning", lang), enabled: true))
        // entries.append(.oneFromManySelector(id: id.count, section: .trending, settingName: .nyStyle, text: i18n("Settings.NY.Style", lang), value: i18n("Settings.NY.Style.\(SGSimpleSettings.shared.nyStyle)", lang), enabled: true))
        entries.append(.notice(id: id.count, section: .trending, text: i18n("Settings.NY.Notice", lang)))
    } else {
        id.increment(3)
    }
    
    if appConfiguration.sgWebSettings.global.canEditSettings {
        entries.append(.disclosure(id: id.count, section: .content, link: .contentSettings, text: i18n("Settings.ContentSettings", lang)))
    } else {
        id.increment(1)
    }

    
    entries.append(.header(id: id.count, section: .tabs, text: i18n("Settings.Tabs.Header", lang), badge: nil))
    entries.append(.toggle(id: id.count, section: .tabs, settingName: .hideTabBar, value: SGSimpleSettings.shared.hideTabBar, text: i18n("Settings.Tabs.HideTabBar", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .tabs, settingName: .showContactsTab, value: callListSettings.showContactsTab, text: i18n("Settings.Tabs.ShowContacts", lang), enabled: !SGSimpleSettings.shared.hideTabBar))
    entries.append(.toggle(id: id.count, section: .tabs, settingName: .showCallsTab, value: callListSettings.showTab, text: strings.CallSettings_TabIcon, enabled: !SGSimpleSettings.shared.hideTabBar))
    entries.append(.toggle(id: id.count, section: .tabs, settingName: .showTabNames, value: SGSimpleSettings.shared.showTabNames, text: i18n("Settings.Tabs.ShowNames", lang), enabled: !SGSimpleSettings.shared.hideTabBar))
    entries.append(.toggle(id: id.count, section: .tabs, settingName: .tabBarSearchEnabled, value: SGSimpleSettings.shared.tabBarSearchEnabled, text: i18n("Settings.Tabs.SearchButton", lang), enabled: !SGSimpleSettings.shared.hideTabBar))
    entries.append(.toggle(id: id.count, section: .tabs, settingName: .wideTabBar, value: SGSimpleSettings.shared.wideTabBar, text: i18n("Settings.Tabs.WideTabBar", lang), enabled: !SGSimpleSettings.shared.hideTabBar))
    entries.append(.notice(id: id.count, section: .tabs, text: i18n("Settings.Tabs.WideTabBar.Notice", lang)))
    
    entries.append(.header(id: id.count, section: .folders, text: strings.Settings_ChatFolders.uppercased(), badge: nil))
    entries.append(.toggle(id: id.count, section: .folders, settingName: .foldersAtBottom, value: experimentalUISettings.foldersTabAtBottom, text: i18n("Settings.Folders.BottomTab", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .folders, settingName: .allChatsHidden, value: SGSimpleSettings.shared.allChatsHidden, text: i18n("Settings.Folders.AllChatsHidden", lang, strings.ChatList_Tabs_AllChats), enabled: true))
    #if DEBUG
//    entries.append(.oneFromManySelector(id: id.count, section: .folders, settingName: .allChatsFolderPositionOverride, text: i18n("Settings.Folders.AllChatsPlacement", lang), value: i18n("Settings.Folders.AllChatsPlacement.\(SGSimpleSettings.shared.allChatsFolderPositionOverride)", lang), enabled: true))
    #endif
    entries.append(.toggle(id: id.count, section: .folders, settingName: .compactFolderNames, value: SGSimpleSettings.shared.compactFolderNames, text: i18n("Settings.Folders.CompactNames", lang), enabled: true))
    entries.append(.oneFromManySelector(id: id.count, section: .folders, settingName: .allChatsTitleLengthOverride, text: i18n("Settings.Folders.AllChatsTitle", lang), value: i18n("Settings.Folders.AllChatsTitle.\(SGSimpleSettings.shared.allChatsTitleLengthOverride)", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .folders, settingName: .rememberLastFolder, value: SGSimpleSettings.shared.rememberLastFolder, text: i18n("Settings.Folders.RememberLast", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .folders, text: i18n("Settings.Folders.RememberLast.Notice", lang)))
    
    entries.append(.header(id: id.count, section: .chatList, text: i18n("Settings.ChatList.Header", lang), badge: nil))
    entries.append(.toggle(id: id.count, section: .chatList, settingName: .compactChatList, value: SGSimpleSettings.shared.compactChatList, text: i18n("Settings.CompactChatList", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .chatList, settingName: .disableChatSwipeOptions, value: !SGSimpleSettings.shared.disableChatSwipeOptions, text: i18n("Settings.ChatSwipeOptions", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .chatList, settingName: .disableDeleteChatSwipeOption, value: !SGSimpleSettings.shared.disableDeleteChatSwipeOption, text: i18n("Settings.DeleteChatSwipeOption", lang), enabled: !SGSimpleSettings.shared.disableChatSwipeOptions))
    
    entries.append(.header(id: id.count, section: .profiles, text: i18n("Settings.Profiles.Header", lang), badge: nil))
    entries.append(.toggle(id: id.count, section: .profiles, settingName: .showProfileId, value: SGSettings.showProfileId, text: i18n("Settings.ShowProfileID", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .profiles, settingName: .showDC, value: SGSimpleSettings.shared.showDC, text: i18n("Settings.ShowDC", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .profiles, settingName: .showRegDate, value: SGSimpleSettings.shared.showRegDate, text: i18n("Settings.ShowRegDate", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .profiles, text: i18n("Settings.ShowRegDate.Notice", lang)))
    entries.append(.toggle(id: id.count, section: .profiles, settingName: .showCreationDate, value: SGSimpleSettings.shared.showCreationDate, text: i18n("Settings.ShowCreationDate", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .profiles, text: i18n("Settings.ShowCreationDate.Notice", lang)))
    entries.append(.toggle(id: id.count, section: .profiles, settingName: .confirmCalls, value: SGSimpleSettings.shared.confirmCalls, text: i18n("Settings.CallConfirmation", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .profiles, text: i18n("Settings.CallConfirmation.Notice", lang)))
    
    entries.append(.header(id: id.count, section: .stories, text: strings.AutoDownloadSettings_Stories.uppercased(), badge: nil))
    entries.append(.toggle(id: id.count, section: .stories, settingName: .hideStories, value: SGSettings.hideStories, text: i18n("Settings.Stories.Hide", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .stories, settingName: .disableSwipeToRecordStory, value: SGSimpleSettings.shared.disableSwipeToRecordStory, text: i18n("Settings.Stories.DisableSwipeToRecord", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .stories, settingName: .warnOnStoriesOpen, value: SGSettings.warnOnStoriesOpen, text: i18n("Settings.Stories.WarnBeforeView", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .stories, settingName: .showRepostToStory, value: SGSimpleSettings.shared.showRepostToStoryV2, text: strings.Share_RepostToStory.replacingOccurrences(of: "\n", with: " "), enabled: true))
    if SGSimpleSettings.shared.canUseStealthMode {
        entries.append(.toggle(id: id.count, section: .stories, settingName: .storyStealthMode, value: SGSimpleSettings.shared.storyStealthMode, text: strings.Story_StealthMode_Title, enabled: true))
        entries.append(.notice(id: id.count, section: .stories, text: strings.Story_StealthMode_ControlText))
    } else {
        id.increment(2)
    }

    
    entries.append(.header(id: id.count, section: .translation, text: strings.Localization_TranslateMessages.uppercased(), badge: nil))
    entries.append(.oneFromManySelector(id: id.count, section: .translation, settingName: .translationBackend, text: i18n("Settings.Translation.Backend", lang), value: i18n("Settings.Translation.Backend.\(SGSimpleSettings.shared.translationBackend)", lang), enabled: true))
    if SGSimpleSettings.shared.translationBackendEnum != .gtranslate {
        entries.append(.notice(id: id.count, section: .translation, text: i18n("Settings.Translation.Backend.Notice", lang, "Settings.Translation.Backend.\(SGSimpleSettings.TranslationBackend.gtranslate.rawValue)".i18n(lang))))
    } else {
        id.increment(1)
    }
    entries.append(.toggle(id: id.count, section: .translation, settingName: .quickTranslateButton, value: SGSimpleSettings.shared.quickTranslateButton, text: i18n("Settings.Translation.QuickTranslateButton", lang), enabled: true))
    entries.append(.disclosure(id: id.count, section: .translation, link: .languageSettings, text: strings.Localization_TranslateEntireChat))
    entries.append(.notice(id: id.count, section: .translation, text: i18n("Common.NoTelegramPremiumNeeded", lang, strings.Settings_Premium)))

    entries.append(.header(id: id.count, section: .voiceMessages, text: "Settings.Transcription.Header".i18n(lang), badge: nil))
    entries.append(.oneFromManySelector(id: id.count, section: .voiceMessages, settingName: .transcriptionBackend, text: i18n("Settings.Transcription.Backend", lang), value: i18n("Settings.Transcription.Backend.\(SGSimpleSettings.shared.transcriptionBackend)", lang), enabled: true))
    if SGSimpleSettings.shared.transcriptionBackendEnum != .apple {
        entries.append(.notice(id: id.count, section: .voiceMessages, text: i18n("Settings.Transcription.Backend.Notice", lang, "Settings.Transcription.Backend.\(SGSimpleSettings.TranscriptionBackend.apple.rawValue)".i18n(lang))))
    } else {
        id.increment(1)
    }
    entries.append(.header(id: id.count, section: .voiceMessages, text: strings.Privacy_VoiceMessages.uppercased(), badge: nil))
    entries.append(.toggle(id: id.count, section: .voiceMessages, settingName: .forceBuiltInMic, value: SGSimpleSettings.shared.forceBuiltInMic, text: i18n("Settings.forceBuiltInMic", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .voiceMessages, text: i18n("Settings.forceBuiltInMic.Notice", lang)))

    entries.append(.header(id: id.count, section: .calls, text: strings.Calls_TabTitle.uppercased(), badge: nil))
    entries.append(.toggle(id: id.count, section: .calls, settingName: .enableVoipTcp, value: experimentalUISettings.enableVoipTcp, text: "Force TCP", enabled: true))
    entries.append(.notice(id: id.count, section: .calls, text: "Common.KnowWhatYouDo".i18n(lang)))
    
    entries.append(.header(id: id.count, section: .photo, text: strings.NetworkUsageSettings_MediaImageDataSection, badge: nil))
    entries.append(.header(id: id.count, section: .photo, text: strings.PhotoEditor_QualityTool.uppercased(), badge: nil))
    entries.append(.percentageSlider(id: id.count, section: .photo, settingName: .outgoingPhotoQuality, value: SGSimpleSettings.shared.outgoingPhotoQuality, leftEdgeLabel: nil, rightEdgeLabel: nil))
    entries.append(.notice(id: id.count, section: .photo, text: i18n("Settings.Photo.Quality.Notice", lang)))
    entries.append(.toggle(id: id.count, section: .photo, settingName: .sendLargePhotos, value: SGSimpleSettings.shared.sendLargePhotos, text: i18n("Settings.Photo.SendLarge", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .photo, text: i18n("Settings.Photo.SendLarge.Notice", lang)))
    
    entries.append(.header(id: id.count, section: .stickers, text: strings.StickerPacksSettings_Title.uppercased(), badge: nil))
    entries.append(.header(id: id.count, section: .stickers, text: i18n("Settings.Stickers.Size", lang), badge: nil))
    entries.append(.percentageSlider(id: id.count, section: .stickers, settingName: .stickerSize, value: SGSimpleSettings.shared.stickerSize, leftEdgeLabel: nil, rightEdgeLabel: nil))
    entries.append(.toggle(id: id.count, section: .stickers, settingName: .stickerTimestamp, value: SGSimpleSettings.shared.stickerTimestamp, text: i18n("Settings.Stickers.Timestamp", lang), enabled: true))
    
    
    entries.append(.header(id: id.count, section: .videoNotes, text: i18n("Settings.VideoNotes.Header", lang), badge: nil))
    entries.append(.toggle(id: id.count, section: .videoNotes, settingName: .startTelescopeWithRearCam, value: SGSimpleSettings.shared.startTelescopeWithRearCam, text: i18n("Settings.VideoNotes.StartWithRearCam", lang), enabled: true))
    
    entries.append(.header(id: id.count, section: .contextMenu, text: i18n("Settings.ContextMenu", lang), badge: nil))
    entries.append(.notice(id: id.count, section: .contextMenu, text: i18n("Settings.ContextMenu.Notice", lang)))
    entries.append(.toggle(id: id.count, section: .contextMenu, settingName: .contextShowSaveToCloud, value: SGSimpleSettings.shared.contextShowSaveToCloud, text: i18n("ContextMenu.SaveToCloud", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .contextMenu, settingName: .contextShowHideForwardName, value: SGSimpleSettings.shared.contextShowHideForwardName, text: strings.Conversation_ForwardOptions_HideSendersNames, enabled: true))
    entries.append(.toggle(id: id.count, section: .contextMenu, settingName: .contextShowSelectFromUser, value: SGSimpleSettings.shared.contextShowSelectFromUser, text: i18n("ContextMenu.SelectFromUser", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .contextMenu, settingName: .contextShowRestrict, value: SGSimpleSettings.shared.contextShowRestrict, text: strings.Conversation_ContextMenuBan, enabled: true))
    entries.append(.toggle(id: id.count, section: .contextMenu, settingName: .contextShowReport, value: SGSimpleSettings.shared.contextShowReport, text: strings.Conversation_ContextMenuReport, enabled: true))
    entries.append(.toggle(id: id.count, section: .contextMenu, settingName: .contextShowReply, value: SGSimpleSettings.shared.contextShowReply, text: strings.Conversation_ContextMenuReply, enabled: true))
    entries.append(.toggle(id: id.count, section: .contextMenu, settingName: .contextShowPin, value: SGSimpleSettings.shared.contextShowPin, text: strings.Conversation_Pin, enabled: true))
    entries.append(.toggle(id: id.count, section: .contextMenu, settingName: .contextShowSaveMedia, value: SGSimpleSettings.shared.contextShowSaveMedia, text: strings.Conversation_SaveToFiles, enabled: true))
    entries.append(.toggle(id: id.count, section: .contextMenu, settingName: .contextShowMessageReplies, value: SGSimpleSettings.shared.contextShowMessageReplies, text: strings.Conversation_ContextViewThread, enabled: true))
    entries.append(.toggle(id: id.count, section: .contextMenu, settingName: .contextShowJson, value: SGSimpleSettings.shared.contextShowJson, text: "JSON", enabled: true))
    /* entries.append(.toggle(id: id.count, section: .contextMenu, settingName: .contextShowRestrict, value: SGSimpleSettings.shared.contextShowRestrict, text: strings.Conversation_ContextMenuBan)) */
    
    entries.append(.header(id: id.count, section: .accountColors, text: i18n("Settings.CustomColors.Header", lang), badge: nil))
    entries.append(.header(id: id.count, section: .accountColors, text: i18n("Settings.CustomColors.Saturation", lang), badge: nil))
    let accountColorSaturation = SGSimpleSettings.shared.accountColorsSaturation
    entries.append(.percentageSlider(id: id.count, section: .accountColors, settingName: .accountColorsSaturation, value: accountColorSaturation, leftEdgeLabel: nil, rightEdgeLabel: nil))
//    let nameColor: PeerNameColor
//    if let updatedNameColor = state.updatedNameColor {
//        nameColor = updatedNameColor
//    } else {
//        nameColor = .blue
//    }
//    let _ = nameColors.get(nameColor, dark: presentationData.theme.overallDarkAppearance)
//    entries.append(.peerColorPicker(id: entries.count, section: .other,
//        colors: nameColors,
//        currentColor: nameColor, // TODO: PeerNameColor(rawValue: <#T##Int32#>)
//        currentSaturation: accountColorSaturation
//    ))
    
    if accountColorSaturation == 0 {
        id.increment(100)
        entries.append(.peerColorDisclosurePreview(id: id.count, section: .accountColors, name: "\(strings.UserInfo_FirstNamePlaceholder) \(strings.UserInfo_LastNamePlaceholder)", color:         presentationData.theme.chat.message.incoming.accentTextColor))
    } else {
        id.increment(200)
        for index in nameColors.displayOrder.prefix(3) {
            let color: PeerNameColor = PeerNameColor(rawValue: index)
            let colors = nameColors.get(color, dark: presentationData.theme.overallDarkAppearance)
            entries.append(.peerColorDisclosurePreview(id: id.count, section: .accountColors, name: "\(strings.UserInfo_FirstNamePlaceholder) \(strings.UserInfo_LastNamePlaceholder)", color: colors.main))
        }
    }
    entries.append(.notice(id: id.count, section: .accountColors, text: i18n("Settings.CustomColors.Saturation.Notice", lang)))
    
    id.increment(10000)
    entries.append(.header(id: id.count, section: .other, text: strings.Appearance_Other.uppercased(), badge: nil))
    entries.append(.toggle(id: id.count, section: .other, settingName: .swipeForVideoPIP, value: SGSimpleSettings.shared.videoPIPSwipeDirection == SGSimpleSettings.VideoPIPSwipeDirection.up.rawValue, text: i18n("Settings.swipeForVideoPIP", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .other, text: i18n("Settings.swipeForVideoPIP.Notice", lang)))
    entries.append(.toggle(id: id.count, section: .other, settingName: .hideChannelBottomButton, value: !SGSimpleSettings.shared.hideChannelBottomButton, text: i18n("Settings.showChannelBottomButton", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .wideChannelPosts, value: SGSimpleSettings.shared.wideChannelPosts, text: i18n("Settings.wideChannelPosts", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .secondsInMessages, value: SGSimpleSettings.shared.secondsInMessages, text: i18n("Settings.secondsInMessages", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .messageDoubleTapActionOutgoingEdit, value: SGSimpleSettings.shared.messageDoubleTapActionOutgoing == SGSimpleSettings.MessageDoubleTapAction.edit.rawValue, text: i18n("Settings.messageDoubleTapActionOutgoingEdit", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .hideRecordingButton, value: !SGSimpleSettings.shared.hideRecordingButton, text: i18n("Settings.RecordingButton", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .disableSnapDeletionEffect, value: !SGSimpleSettings.shared.disableSnapDeletionEffect, text: i18n("Settings.SnapDeletionEffect", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .disableSendAsButton, value: !SGSimpleSettings.shared.disableSendAsButton, text: i18n("Settings.SendAsButton", lang, strings.Conversation_SendMesageAs), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .disableGalleryCamera, value: !SGSimpleSettings.shared.disableGalleryCamera, text: i18n("Settings.GalleryCamera", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .disableGalleryCameraPreview, value: !SGSimpleSettings.shared.disableGalleryCameraPreview, text: i18n("Settings.GalleryCameraPreview", lang), enabled: !SGSimpleSettings.shared.disableGalleryCamera))
    entries.append(.toggle(id: id.count, section: .other, settingName: .disableScrollToNextChannel, value: !SGSimpleSettings.shared.disableScrollToNextChannel, text: i18n("Settings.PullToNextChannel", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .disableScrollToNextTopic, value: !SGSimpleSettings.shared.disableScrollToNextTopic, text: i18n("Settings.PullToNextTopic", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .hideReactions, value: SGSimpleSettings.shared.hideReactions, text: i18n("Settings.HideReactions", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .uploadSpeedBoost, value: SGSimpleSettings.shared.uploadSpeedBoost, text: i18n("Settings.UploadsBoost", lang), enabled: true))
    entries.append(.oneFromManySelector(id: id.count, section: .other, settingName: .downloadSpeedBoost, text: i18n("Settings.DownloadsBoost", lang), value: i18n("Settings.DownloadsBoost.\(SGSimpleSettings.shared.downloadSpeedBoost)", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .other, text: i18n("Settings.DownloadsBoost.Notice", lang)))
    entries.append(.toggle(id: id.count, section: .other, settingName: .sendWithReturnKey, value: SGSettings.sendWithReturnKey, text: i18n("Settings.SendWithReturnKey", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .forceEmojiTab, value: SGSimpleSettings.shared.forceEmojiTab, text: i18n("Settings.ForceEmojiTab", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .other, settingName: .defaultEmojisFirst, value: SGSimpleSettings.shared.defaultEmojisFirst, text: i18n("Settings.DefaultEmojisFirst", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .other, text: i18n("Settings.DefaultEmojisFirst.Notice", lang)))
    entries.append(.toggle(id: id.count, section: .other, settingName: .hidePhoneInSettings, value: SGSimpleSettings.shared.hidePhoneInSettings, text: i18n("Settings.HidePhoneInSettingsUI", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .other, text: i18n("Settings.HidePhoneInSettingsUI.Notice", lang)))
    // NOTE: LuxGram-specific privacy/content toggles were moved to LuxGram.
    
    return filterSGItemListUIEntrires(entries: entries, by: state.searchQuery)
}

public func sgSettingsController(context: AccountContext/*, focusOnItemTag: Int? = nil*/) -> ViewController {
    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?
//    var getRootControllerImpl: (() -> UIViewController?)?
//    var getNavigationControllerImpl: (() -> NavigationController?)?
    var askForRestart: (() -> Void)?
    
    let initialState = SGSettingsControllerState()
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((SGSettingsControllerState) -> SGSettingsControllerState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }
    
//    let sliderPromise = ValuePromise(SGSimpleSettings.shared.accountColorsSaturation, ignoreRepeated: true)
//    let sliderStateValue = Atomic(value: SGSimpleSettings.shared.accountColorsSaturation)
//    let _: ((Int32) -> Int32) -> Void = { f in
//        sliderPromise.set(sliderStateValue.modify( {f($0)}))
//    }
    
    let simplePromise = ValuePromise(true, ignoreRepeated: false)
    
    let arguments = SGItemListArguments<SGBoolSetting, SGSliderSetting, SGOneFromManySetting, SGDisclosureLink, AnyHashable>(
        context: context,
        /*updatePeerColor: { color in
          updateState { state in
              var updatedState = state
              updatedState.updatedNameColor = color
              return updatedState
          }
        },*/ setBoolValue: { setting, value in
        switch setting {
        case .hidePhoneInSettings:
            SGSimpleSettings.shared.hidePhoneInSettings = value
            askForRestart?()
        case .showTabNames:
            SGSimpleSettings.shared.showTabNames = value
            askForRestart?()
        case .showContactsTab:
            let _ = (
                updateCallListSettingsInteractively(
                    accountManager: context.sharedContext.accountManager, { $0.withUpdatedShowContactsTab(value) }
                )
            ).start()
        case .showCallsTab:
            let _ = (
                updateCallListSettingsInteractively(
                    accountManager: context.sharedContext.accountManager, { $0.withUpdatedShowTab(value) }
                )
            ).start()
        case .tabBarSearchEnabled:
            SGSimpleSettings.shared.tabBarSearchEnabled = value
        case .wideTabBar:
            SGSimpleSettings.shared.wideTabBar = value
            askForRestart?()
        case .foldersAtBottom:
            let _ = (
                updateExperimentalUISettingsInteractively(accountManager: context.sharedContext.accountManager, { settings in
                        var settings = settings
                        settings.foldersTabAtBottom = value
                        return settings
                    }
                )
            ).start()
        case .startTelescopeWithRearCam:
            SGSimpleSettings.shared.startTelescopeWithRearCam = value
        case .hideStories:
            let _ = (
                updateSGUISettings(engine: context.engine, { settings in
                    var settings = settings
                    settings.hideStories = value
                    return settings
                })
            ).start()
        case .showProfileId:
            let _ = (
                updateSGUISettings(engine: context.engine, { settings in
                    var settings = settings
                    settings.showProfileId = value
                    return settings
                })
            ).start()
        case .warnOnStoriesOpen:
            let _ = (
                updateSGUISettings(engine: context.engine, { settings in
                    var settings = settings
                    settings.warnOnStoriesOpen = value
                    return settings
                })
            ).start()
        case .sendWithReturnKey:
            let _ = (
                updateSGUISettings(engine: context.engine, { settings in
                    var settings = settings
                    settings.sendWithReturnKey = value
                    return settings
                })
            ).start()
        case .rememberLastFolder:
            SGSimpleSettings.shared.rememberLastFolder = value
        case .sendLargePhotos:
            SGSimpleSettings.shared.sendLargePhotos = value
        case .storyStealthMode:
            SGSimpleSettings.shared.storyStealthMode = value
        case .disableSwipeToRecordStory:
            SGSimpleSettings.shared.disableSwipeToRecordStory = value
        case .quickTranslateButton:
            SGSimpleSettings.shared.quickTranslateButton = value
        case .uploadSpeedBoost:
            SGSimpleSettings.shared.uploadSpeedBoost = value
        case .unlimitedFavoriteStickers:
            SGSimpleSettings.shared.unlimitedFavoriteStickers = value
        case .faceBlurInVideoMessages:
            SGSimpleSettings.shared.faceBlurInVideoMessages = value
        case .customAvatarRoundingEnabled:
            SGSimpleSettings.shared.customAvatarRoundingEnabled = value
            NotificationCenter.default.post(name: .sgAvatarRoundingSettingsDidChange, object: nil)
        case .enableOnlineStatusRecording:
            SGSimpleSettings.shared.enableOnlineStatusRecording = value
        case .showRepostToStory:
            SGSimpleSettings.shared.showRepostToStoryV2 = value
        case .contextShowSelectFromUser:
            SGSimpleSettings.shared.contextShowSelectFromUser = value
        case .contextShowSaveToCloud:
            SGSimpleSettings.shared.contextShowSaveToCloud = value
        case .contextShowRestrict:
            SGSimpleSettings.shared.contextShowRestrict = value
        case .contextShowHideForwardName:
            SGSimpleSettings.shared.contextShowHideForwardName = value
        case .addMusicFromDeviceToProfile:
            SGSimpleSettings.shared.addMusicFromDeviceToProfile = value
        case .hideReactions:
            SGSimpleSettings.shared.hideReactions = value
        case .pluginSystemEnabled:
            guard LuxGramFeatures.pluginsEnabled else { return }
            SGSimpleSettings.shared.pluginSystemEnabled = value
            if value {
                PluginRunner.shared.ensureLoaded()
            }
            askForRestart?()
        case .chatExportEnabled:
            SGSimpleSettings.shared.chatExportEnabled = value
        case .disableScrollToNextChannel:
            SGSimpleSettings.shared.disableScrollToNextChannel = !value
        case .disableScrollToNextTopic:
            SGSimpleSettings.shared.disableScrollToNextTopic = !value
        case .disableChatSwipeOptions:
            SGSimpleSettings.shared.disableChatSwipeOptions = !value
            simplePromise.set(true) // Trigger update for 'enabled' field of other toggles
            askForRestart?()
        case .disableDeleteChatSwipeOption:
            SGSimpleSettings.shared.disableDeleteChatSwipeOption = !value
            askForRestart?()
        case .disableGalleryCamera:
            SGSimpleSettings.shared.disableGalleryCamera = !value
            simplePromise.set(true)
        case .disableGalleryCameraPreview:
            SGSimpleSettings.shared.disableGalleryCameraPreview = !value
        case .disableSendAsButton:
            SGSimpleSettings.shared.disableSendAsButton = !value
        case .disableSnapDeletionEffect:
            SGSimpleSettings.shared.disableSnapDeletionEffect = !value
        case .contextShowReport:
            SGSimpleSettings.shared.contextShowReport = value
        case .contextShowReply:
            SGSimpleSettings.shared.contextShowReply = value
        case .contextShowPin:
            SGSimpleSettings.shared.contextShowPin = value
        case .contextShowSaveMedia:
            SGSimpleSettings.shared.contextShowSaveMedia = value
        case .contextShowMessageReplies:
            SGSimpleSettings.shared.contextShowMessageReplies = value
        case .stickerTimestamp:
            SGSimpleSettings.shared.stickerTimestamp = value
        case .contextShowJson:
            SGSimpleSettings.shared.contextShowJson = value
        case .hideRecordingButton:
            SGSimpleSettings.shared.hideRecordingButton = !value
        case .hideTabBar:
            SGSimpleSettings.shared.hideTabBar = value
            simplePromise.set(true) // Trigger update for 'enabled' field of other toggles
            askForRestart?()
        case .showDC:
            SGSimpleSettings.shared.showDC = value
        case .showCreationDate:
            SGSimpleSettings.shared.showCreationDate = value
        case .showRegDate:
            SGSimpleSettings.shared.showRegDate = value
        case .compactChatList:
            SGSimpleSettings.shared.compactChatList = value
            askForRestart?()
        case .compactFolderNames:
            SGSimpleSettings.shared.compactFolderNames = value
            askForRestart?()
        case .allChatsHidden:
            SGSimpleSettings.shared.allChatsHidden = value
            askForRestart?()
        case .defaultEmojisFirst:
            SGSimpleSettings.shared.defaultEmojisFirst = value
        case .messageDoubleTapActionOutgoingEdit:
            SGSimpleSettings.shared.messageDoubleTapActionOutgoing = value ? SGSimpleSettings.MessageDoubleTapAction.edit.rawValue : SGSimpleSettings.MessageDoubleTapAction.default.rawValue
        case .wideChannelPosts:
            SGSimpleSettings.shared.wideChannelPosts = value
        case .forceEmojiTab:
            SGSimpleSettings.shared.forceEmojiTab = value
        case .forceBuiltInMic:
            SGSimpleSettings.shared.forceBuiltInMic = value
        case .hideChannelBottomButton:
            SGSimpleSettings.shared.hideChannelBottomButton = !value
        case .secondsInMessages:
            SGSimpleSettings.shared.secondsInMessages = value
        case .confirmCalls:
            SGSimpleSettings.shared.confirmCalls = value
        case .swipeForVideoPIP:
            SGSimpleSettings.shared.videoPIPSwipeDirection = value ? SGSimpleSettings.VideoPIPSwipeDirection.up.rawValue : SGSimpleSettings.VideoPIPSwipeDirection.none.rawValue
        case .enableVoipTcp:
            let _ = (
                updateExperimentalUISettingsInteractively(accountManager: context.sharedContext.accountManager, { settings in
                        var settings = settings
                        settings.enableVoipTcp = value
                        return settings
                    }
                )
            ).start()
        case .nyStyleSnow:
            SGSimpleSettings.shared.nyStyle = value ? SGSimpleSettings.NYStyle.snow.rawValue : SGSimpleSettings.NYStyle.default.rawValue
            simplePromise.set(true) // Trigger update for 'enabled' field of other toggles
        case .nyStyleLightning:
            SGSimpleSettings.shared.nyStyle = value ? SGSimpleSettings.NYStyle.lightning.rawValue : SGSimpleSettings.NYStyle.default.rawValue
            simplePromise.set(true) // Trigger update for 'enabled' field of other toggles
        case .showDeletedMessages:
            SGSimpleSettings.shared.showDeletedMessages = value
        case .saveDeletedMessagesMedia:
            SGSimpleSettings.shared.saveDeletedMessagesMedia = value
        case .saveDeletedMessagesReactions:
            SGSimpleSettings.shared.saveDeletedMessagesReactions = value
        case .saveDeletedMessagesForBots:
            SGSimpleSettings.shared.saveDeletedMessagesForBots = value
        case .saveEditHistory:
            SGSimpleSettings.shared.saveEditHistory = value
        case .enableLocalMessageEditing:
            SGSimpleSettings.shared.enableLocalMessageEditing = value
        case .enableFontReplacement:
            SGSimpleSettings.shared.enableFontReplacement = value
        case .disableCompactNumbers:
            SGSimpleSettings.shared.disableCompactNumbers = value
        case .disableZalgoText:
            SGSimpleSettings.shared.disableZalgoText = value
        // Ghost Mode settings
        case .disableOnlineStatus:
            SGSimpleSettings.shared.disableOnlineStatus = value
        case .disableTypingStatus:
            SGSimpleSettings.shared.disableTypingStatus = value
        case .disableRecordingVideoStatus:
            SGSimpleSettings.shared.disableRecordingVideoStatus = value
        case .disableUploadingVideoStatus:
            SGSimpleSettings.shared.disableUploadingVideoStatus = value
        case .disableVCMessageRecordingStatus:
            SGSimpleSettings.shared.disableVCMessageRecordingStatus = value
        case .disableVCMessageUploadingStatus:
            SGSimpleSettings.shared.disableVCMessageUploadingStatus = value
        case .disableUploadingPhotoStatus:
            SGSimpleSettings.shared.disableUploadingPhotoStatus = value
        case .disableUploadingFileStatus:
            SGSimpleSettings.shared.disableUploadingFileStatus = value
        case .disableChoosingLocationStatus:
            SGSimpleSettings.shared.disableChoosingLocationStatus = value
        case .disableChoosingContactStatus:
            SGSimpleSettings.shared.disableChoosingContactStatus = value
        case .disablePlayingGameStatus:
            SGSimpleSettings.shared.disablePlayingGameStatus = value
        case .disableRecordingRoundVideoStatus:
            SGSimpleSettings.shared.disableRecordingRoundVideoStatus = value
        case .disableUploadingRoundVideoStatus:
            SGSimpleSettings.shared.disableUploadingRoundVideoStatus = value
        case .disableSpeakingInGroupCallStatus:
            SGSimpleSettings.shared.disableSpeakingInGroupCallStatus = value
        case .disableChoosingStickerStatus:
            SGSimpleSettings.shared.disableChoosingStickerStatus = value
        case .disableEmojiInteractionStatus:
            SGSimpleSettings.shared.disableEmojiInteractionStatus = value
        case .disableEmojiAcknowledgementStatus:
            SGSimpleSettings.shared.disableEmojiAcknowledgementStatus = value
        case .disableMessageReadReceipt:
            SGSimpleSettings.shared.disableMessageReadReceipt = value
        case .ghostModeMarkReadOnReply:
            SGSimpleSettings.shared.ghostModeMarkReadOnReply = value
        case .disableStoryReadReceipt:
            SGSimpleSettings.shared.disableStoryReadReceipt = value
        case .disableAllAds:
            SGSimpleSettings.shared.disableAllAds = value
        case .hideProxySponsor:
            SGSimpleSettings.shared.hideProxySponsor = value
            NotificationCenter.default.post(name: .sgHideProxySponsorDidChange, object: nil)
        case .enableSavingProtectedContent:
            SGSimpleSettings.shared.enableSavingProtectedContent = value
        case .forwardRestrictedAsCopy:
            SGSimpleSettings.shared.forwardRestrictedAsCopy = value
        case .disableScreenshotDetection:
            SGSimpleSettings.shared.disableScreenshotDetection = value
        case .enableSavingSelfDestructingMessages:
            SGSimpleSettings.shared.enableSavingSelfDestructingMessages = value
        case .disableSecretChatBlurOnScreenshot:
            SGSimpleSettings.shared.disableSecretChatBlurOnScreenshot = value
        case .enableLocalPremium:
            SGSimpleSettings.shared.enableLocalPremium = value
            NotificationCenter.default.post(name: .sgEnableLocalPremiumDidChange, object: nil)
        case .voiceChangerEnabled:
            VoiceMorpherManager.shared.isEnabled = value
            if value, VoiceMorpherManager.shared.selectedPresetId == 0 {
                VoiceMorpherManager.shared.selectedPresetId = VoiceMorpherManager.VoicePreset.anonymous.rawValue
            }
            SGSimpleSettings.shared.voiceChangerEnabled = value
        case .sensitiveContentEnabled:
            // Intentionally not handled here.
            // This setting lives in LuxGram and is applied via Telegram server-side content settings.
            break
        case .scrollToTopButtonEnabled:
            SGSimpleSettings.shared.scrollToTopButtonEnabled = value
        case .fakeLocationEnabled:
            SGSimpleSettings.shared.fakeLocationEnabled = value
        case .enableVideoToCircleOrVoice:
            SGSimpleSettings.shared.enableVideoToCircleOrVoice = value
        case .enableTelescope:
            SGSimpleSettings.shared.enableTelescope = value
        case .emojiDownloaderEnabled:
            SGSimpleSettings.shared.emojiDownloaderEnabled = value
        case .feelRichEnabled:
            SGSimpleSettings.shared.feelRichEnabled = value
        case .giftIdEnabled:
            SGSimpleSettings.shared.giftIdEnabled = value
        case .fakeProfileEnabled:
            SGSimpleSettings.shared.fakeProfileEnabled = value
        }
    }, updateSliderValue: { setting, value in
        switch (setting) {
            case .accountColorsSaturation:
                if SGSimpleSettings.shared.accountColorsSaturation != value {
                    SGSimpleSettings.shared.accountColorsSaturation = value
                    simplePromise.set(true)
                }
            case .outgoingPhotoQuality:
                if SGSimpleSettings.shared.outgoingPhotoQuality != value {
                    SGSimpleSettings.shared.outgoingPhotoQuality = value
                    simplePromise.set(true)
                }
            case .stickerSize:
                if SGSimpleSettings.shared.stickerSize != value {
                    SGSimpleSettings.shared.stickerSize = value
                    simplePromise.set(true)
                }
        }

    }, setOneFromManyValue: { setting in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let actionSheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = []
        
        switch (setting) {
            case .downloadSpeedBoost:
                let setAction: (String) -> Void = { value in
                    SGSimpleSettings.shared.downloadSpeedBoost = value
                    
                    let enableDownloadX: Bool
                    switch (value) {
                        case SGSimpleSettings.DownloadSpeedBoostValues.none.rawValue:
                            enableDownloadX = false
                        default:
                            enableDownloadX = true
                    }
                    
                    // Updating controller
                    simplePromise.set(true)

                    let _ = updateNetworkSettingsInteractively(postbox: context.account.postbox, network: context.account.network, { settings in
                        var settings = settings
                        settings.useExperimentalDownload = enableDownloadX
                        return settings
                    }).start(completed: {
                        Queue.mainQueue().async {
                            askForRestart?()
                        }
                    })
                }

                for value in SGSimpleSettings.DownloadSpeedBoostValues.allCases {
                    items.append(ActionSheetButtonItem(title: i18n("Settings.DownloadsBoost.\(value.rawValue)", presentationData.strings.baseLanguageCode), color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        setAction(value.rawValue)
                    }))
                }
            case .bottomTabStyle:
                let setAction: (String) -> Void = { value in
                    SGSimpleSettings.shared.bottomTabStyle = value
                    simplePromise.set(true)
                }

                for value in SGSimpleSettings.BottomTabStyleValues.allCases {
                    items.append(ActionSheetButtonItem(title: i18n("Settings.Folders.BottomTabStyle.\(value.rawValue)", presentationData.strings.baseLanguageCode), color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        setAction(value.rawValue)
                    }))
                }
            case .allChatsTitleLengthOverride:
                let setAction: (String) -> Void = { value in
                    SGSimpleSettings.shared.allChatsTitleLengthOverride = value
                    simplePromise.set(true)
                }

                for value in SGSimpleSettings.AllChatsTitleLengthOverride.allCases {
                    let title: String
                    switch (value) {
                        case SGSimpleSettings.AllChatsTitleLengthOverride.short:
                            title = "\"\(presentationData.strings.ChatList_Tabs_All)\""
                        case SGSimpleSettings.AllChatsTitleLengthOverride.long:
                            title = "\"\(presentationData.strings.ChatList_Tabs_AllChats)\""
                        default:
                            title = i18n("Settings.Folders.AllChatsTitle.none", presentationData.strings.baseLanguageCode)
                    }
                    items.append(ActionSheetButtonItem(title: title, color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        setAction(value.rawValue)
                    }))
                }
//        case .allChatsFolderPositionOverride:
//            let setAction: (String) -> Void = { value in
//                SGSimpleSettings.shared.allChatsFolderPositionOverride = value
//                simplePromise.set(true)
//            }
//
//            for value in SGSimpleSettings.AllChatsFolderPositionOverride.allCases {
//                items.append(ActionSheetButtonItem(title: i18n("Settings.Folders.AllChatsTitle.\(value)", presentationData.strings.baseLanguageCode), color: .accent, action: { [weak actionSheet] in
//                    actionSheet?.dismissAnimated()
//                    setAction(value.rawValue)
//                }))
//            }
            case .translationBackend:
                let setAction: (String) -> Void = { value in
                    SGSimpleSettings.shared.translationBackend = value
                    simplePromise.set(true)
                }

                for value in SGSimpleSettings.TranslationBackend.allCases {
                    if value == .system {
                        if #available(iOS 18.0, *) {
                        } else {
                            continue // System translation is not available on iOS 17 and below
                        }
                    }
                    items.append(ActionSheetButtonItem(title: i18n("Settings.Translation.Backend.\(value.rawValue)", presentationData.strings.baseLanguageCode), color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        setAction(value.rawValue)
                    }))
                }
            case .transcriptionBackend:
                let setAction: (String) -> Void = { value in
                    SGSimpleSettings.shared.transcriptionBackend = value
                    simplePromise.set(true)
                }

                for value in SGSimpleSettings.TranscriptionBackend.allCases {
                    if #available(iOS 13.0, *) {
                    } else {
                        if value == .apple {
                            continue // Apple recognition is not available on iOS 12
                        }
                    }
                    items.append(ActionSheetButtonItem(title: i18n("Settings.Transcription.Backend.\(value.rawValue)", presentationData.strings.baseLanguageCode), color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        setAction(value.rawValue)
                    }))
                }
            case .nyStyle:
                let setAction: (String) -> Void = { value in
                    SGSimpleSettings.shared.nyStyle = value
                    simplePromise.set(true)
                }

                for value in SGSimpleSettings.NYStyle.allCases {
                    items.append(ActionSheetButtonItem(title: i18n("Settings.NY.Style.\(value.rawValue)", presentationData.strings.baseLanguageCode), color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        setAction(value.rawValue)
                    }))
                }
        }
        
        actionSheet.setItemGroups([ActionSheetItemGroup(items: items), ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })
        ])])
        presentControllerImpl?(actionSheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
    }, openDisclosureLink: { link in
        switch (link) {
            case .languageSettings:
                pushControllerImpl?(context.sharedContext.makeLocalizationListController(context: context))
            case .contentSettings:
                let _ = (getSGSettingsURL(context: context) |> deliverOnMainQueue).start(next: { [weak context] url in
                    guard let strongContext = context else {
                        return
                    }
                    strongContext.sharedContext.applicationBindings.openUrl(url)
                })
        }
    }, action: { actionType in
        #if canImport(SGDeletedMessages)
        if let actionString = actionType as? String, actionString == "clearDeletedMessages" {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let alertController = textAlertController(
                context: context,
                title: presentationData.strings.baseLanguageCode == "ru" ? "Очистить все сохраненные удаленные сообщения?" : "Clear All Saved Deleted Messages?",
                text: presentationData.strings.baseLanguageCode == "ru" ? "Это действие удалит все сообщения, которые были помечены как удаленные. Это действие нельзя отменить." : "This action will permanently delete all messages that were marked as deleted. This action cannot be undone.",
                actions: [
                    TextAlertAction(type: .destructiveAction, title: presentationData.strings.Common_Delete, action: {
                        let statusController = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
                        presentControllerImpl?(statusController, nil)
                        
                        let _ = (SGDeletedMessages.clearAllDeletedMessages(postbox: context.account.postbox)
                            |> deliverOnMainQueue).start(completed: {
                                statusController.dismiss()
                                
                                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                                presentControllerImpl?(OverlayStatusController(theme: presentationData.theme, type: .success), nil)
                            })
                    }),
                    TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_Cancel, action: {})
                ]
            )
            presentControllerImpl?(alertController, nil)
        }
        #endif
    }, searchInput: { searchQuery in
        updateState { state in
            var updatedState = state
            updatedState.searchQuery = searchQuery
            return updatedState
        }
    })
    
    let sharedData = context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.callListSettings, ApplicationSpecificSharedDataKeys.experimentalUISettings])
    let preferences = context.account.postbox.preferencesView(keys: [ApplicationSpecificPreferencesKeys.SGUISettings, PreferencesKeys.appConfiguration])
    let updatedContentSettingsConfiguration = contentSettingsConfiguration(network: context.account.network)
    |> map(Optional.init)
    let contentSettingsConfiguration = Promise<ContentSettingsConfiguration?>()
    contentSettingsConfiguration.set(.single(nil)
    |> then(updatedContentSettingsConfiguration))
    
    let signal = combineLatest(simplePromise.get(), /*sliderPromise.get(),*/ statePromise.get(), context.sharedContext.presentationData, sharedData, preferences, contentSettingsConfiguration.get(),
        context.engine.accountData.observeAvailableColorOptions(scope: .replies),
        context.engine.accountData.observeAvailableColorOptions(scope: .profile)
    )
    |> map { _, /*sliderValue,*/ state, presentationData, sharedData, view, contentSettingsConfiguration, availableReplyColors, availableProfileColors ->  (ItemListControllerState, (ItemListNodeState, Any)) in
        
        let sgUISettings: SGUISettings = view.values[ApplicationSpecificPreferencesKeys.SGUISettings]?.get(SGUISettings.self) ?? SGUISettings.default
        let appConfiguration: AppConfiguration = view.values[PreferencesKeys.appConfiguration]?.get(AppConfiguration.self) ?? AppConfiguration.defaultValue
        let callListSettings: CallListSettings = sharedData.entries[ApplicationSpecificSharedDataKeys.callListSettings]?.get(CallListSettings.self) ?? CallListSettings.defaultSettings
        let experimentalUISettings: ExperimentalUISettings = sharedData.entries[ApplicationSpecificSharedDataKeys.experimentalUISettings]?.get(ExperimentalUISettings.self) ?? ExperimentalUISettings.defaultSettings
        
        let entries = SGControllerEntries(presentationData: presentationData, callListSettings: callListSettings, experimentalUISettings: experimentalUISettings, SGSettings: sgUISettings, appConfiguration: appConfiguration, nameColors: PeerNameColors.with(availableReplyColors: availableReplyColors, availableProfileColors: availableProfileColors), state: state)
        
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("LuxGram"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        
        // TODO(swiftgram): focusOnItemTag support
        /* var index = 0
        var scrollToItem: ListViewScrollToItem?
         if let focusOnItemTag = focusOnItemTag {
            for entry in entries {
                if entry.tag?.isEqual(to: focusOnItemTag) ?? false {
                    scrollToItem = ListViewScrollToItem(index: index, position: .top(0.0), animated: false, curve: .Default(duration: 0.0), directionHint: .Up)
                }
                index += 1
            }
        } */
        
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, ensureVisibleItemTag: /*focusOnItemTag*/ nil, initialScrollToItem: nil /* scrollToItem*/ )
        
        return (controllerState, (listState, arguments))
    }
    
    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c, a in
        controller?.present(c, in: .window(.root), with: a)
    }
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
//    getRootControllerImpl = { [weak controller] in
//        return controller?.view.window?.rootViewController
//    }
//    getNavigationControllerImpl = { [weak controller] in
//        return controller?.navigationController as? NavigationController
//    }
    askForRestart = { [weak context] in
        guard let context = context else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(
            UndoOverlayController(
                presentationData: presentationData, 
                content: .info(title: nil, // i18n("Common.RestartRequired", presentationData.strings.baseLanguageCode),
                    text: i18n("Common.RestartRequired", presentationData.strings.baseLanguageCode),
                    timeout: nil,
                    customUndoText: i18n("Common.RestartNow", presentationData.strings.baseLanguageCode) //presentationData.strings.Common_Yes
                ),
                elevatedLayout: false,
                action: { action in if action == .undo { exit(0) }; return true }
            ),
            nil
        )
    }
    return controller

}

```

