import Foundation

/// Swiftgram – iOS plugin hook integration (`.plugin` Python files).
///
/// Swift-сторона хуков: TelegramUI вызывает эти точки; рантайм Python (например PythonKit / CPython) задаёт провайдеры.
public enum SGPluginHookStrategy: String, Codable, Sendable {
    /// Keep original message.
    case passthrough
    /// Replace outgoing message text.
    case modify
    /// Cancel sending (plugin handled it itself).
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

/// Info about the message being replied to (for FileViewer-style plugins: open file in reply).
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

/// Optional runner for outgoing message hook (e.g. PythonKit-based). Set by app/SGSettingsUI when Python is available.
/// When replying to a document, replyInfo may contain local file path and name for plugins like FileViewer.
public typealias PluginMessageHookRunner = (Int64, Int64, String, Int64?, ReplyMessageInfo?) -> SGPluginHookResult?

/// Display info for peer/user (Fake Profile–style plugins can modify before UI shows).
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

/// Optional runner for user/peer display hook (Fake Profile style). Set when Python runtime is available.
public typealias PluginUserDisplayRunner = (Int64, PluginDisplayUser) -> PluginDisplayUser?

/// Called when a new message is received (updateNewMessage / updateNewChannelMessage). Set by runner; observer posts from TelegramCore.
public typealias PluginIncomingMessageRunner = (Int64, Int64, Int64, String?, Bool) -> Void

/// One item to add to the chat context menu (CHAT_ACTION_MENU style). Plugins register these via chatMenuItemsProvider.
public struct PluginChatMenuItem: Sendable {
    public let title: String
    public let action: @Sendable () -> Void

    public init(title: String, action: @escaping @Sendable () -> Void) {
        self.title = title
        self.action = action
    }
}

/// Notification name posted by TelegramCore when a new message is processed (updateNewMessage / updateNewChannelMessage).
/// userInfo: accountId (Int64), peerId (Int64), messageId (Int64), text (String), outgoing (Bool).
public let SGPluginIncomingMessageNotificationName = Notification.Name("SGPluginIncomingMessage")

/// Возвращает true, если плагин обработал URL (клиент не должен открывать его сам).
public typealias PluginOpenUrlRunner = (String) -> Bool

/// Уведомление перед открытием профиля (accountId, peerId).
public typealias PluginWillOpenProfileRunner = (Int64, Int64) -> Void

/// Уведомление перед открытием чата (accountId, peerId).
public typealias PluginWillOpenChatRunner = (Int64, Int64) -> Void

/// Возвращает false, чтобы скрыть сообщение в списке (например, фильтр по ключевым словам). accountId, peerId, messageId, text, outgoing.
public typealias PluginShouldShowMessageRunner = (Int64, Int64, Int64, String?, Bool) -> Bool

/// Возвращает false, чтобы скрыть кнопку подарка в чате. accountId, peerId.
public typealias PluginShouldShowGiftButtonRunner = (Int64, Int64) -> Bool

/// Дополнительные пункты контекстного меню в профиле пользователя/канала. accountId, peerId.
public typealias PluginProfileMenuItemsProvider = (Int64, Int64) -> [PluginChatMenuItem]

/// Entry point used by TelegramUI just before enqueueing outgoing messages.
///
/// If `messageHookRunner` is set and returns a result, that result is used; otherwise `.passthrough`.
public enum SGPluginHooks {
    /// When set, called for each outgoing text message. Return nil to fall back to .passthrough.
    public static var messageHookRunner: PluginMessageHookRunner?

    /// When set, called when building user/peer display (Fake Profile style). Return nil to keep original.
    public static var userDisplayRunner: PluginUserDisplayRunner?

    /// When set, called when a new message is received (see notification SGPluginIncomingMessage). Used by sender-style plugins.
    public static var incomingMessageHookRunner: PluginIncomingMessageRunner?

    /// When set, returns extra items for the chat message context menu (CHAT_ACTION_MENU). accountId, peerId.
    public static var chatMenuItemsProvider: ((Int64, Int64) -> [PluginChatMenuItem])?

    /// Когда задан, вызывается при открытии URL (tg://, t.me и т.д.). Возврат true = плагин обработал, клиент не открывает.
    public static var openUrlRunner: PluginOpenUrlRunner?

    /// Когда задан, вызывается перед открытием экрана профиля (accountId, peerId).
    public static var willOpenProfileRunner: PluginWillOpenProfileRunner?

    /// Когда задан, вызывается перед открытием чата (accountId, peerId).
    public static var willOpenChatRunner: PluginWillOpenChatRunner?

    /// Когда задан, вызывается для каждого сообщения при отображении. Возврат false скрывает сообщение в списке.
    public static var shouldShowMessageRunner: PluginShouldShowMessageRunner?

    /// Когда задан, возврат false скрывает кнопку подарка в чате (accountId, peerId).
    public static var shouldShowGiftButtonRunner: PluginShouldShowGiftButtonRunner?

    /// Когда задан, возвращает доп. пункты контекстного меню в профиле (accountId, peerId).
    public static var profileMenuItemsProvider: PluginProfileMenuItemsProvider?

    public static func applyOutgoingMessageTextHooks(
        accountPeerId: Int64,
        peerId: Int64,
        text: String,
        replyToMessageId: Int64? = nil,
        replyMessageInfo: ReplyMessageInfo? = nil
    ) -> SGPluginHookResult {
        guard SGSimpleSettings.shared.pluginSystemEnabled else {
            return SGPluginHookResult(strategy: .passthrough)
        }
        if let result = messageHookRunner?(accountPeerId, peerId, text, replyToMessageId, replyMessageInfo), result.strategy != .passthrough {
            return result
        }
        return SGPluginHookResult(strategy: .passthrough)
    }

    /// Apply plugin display hooks (Fake Profile). Call when building peer title; returns modified user display or original.
    public static func applyUserDisplayHooks(accountId: Int64, user: PluginDisplayUser) -> PluginDisplayUser {
        guard SGSimpleSettings.shared.pluginSystemEnabled else { return user }
        return userDisplayRunner?(accountId, user) ?? user
    }

    /// Вызвать перед открытием URL. Возвращает true, если плагин обработал URL и клиент не должен открывать его.
    public static func applyOpenUrlHook(url: String) -> Bool {
        guard SGSimpleSettings.shared.pluginSystemEnabled else { return false }
        return openUrlRunner?(url) ?? false
    }

    /// Вызвать при отображении сообщения в списке. Возвращает false, чтобы скрыть сообщение.
    public static func applyShouldShowMessageHook(accountId: Int64, peerId: Int64, messageId: Int64, text: String?, outgoing: Bool) -> Bool {
        guard SGSimpleSettings.shared.pluginSystemEnabled else { return true }
        return shouldShowMessageRunner?(accountId, peerId, messageId, text, outgoing) ?? true
    }

    /// Вызвать при решении показывать ли кнопку подарка в чате. Возвращает false, чтобы скрыть.
    public static func applyShouldShowGiftButtonHook(accountId: Int64, peerId: Int64) -> Bool {
        guard SGSimpleSettings.shared.pluginSystemEnabled else { return true }
        return shouldShowGiftButtonRunner?(accountId, peerId) ?? true
    }
}

