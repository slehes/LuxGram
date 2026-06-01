// MARK: Swiftgram
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
import LocalizedPeerData
import LegacyUI
import LegacyMediaPickerUI
import SettingsUI
#if canImport(SGFakeLocation)
import SGFakeLocation
#endif
#if canImport(FaceScanScreen)
import FaceScanScreen
#endif
#if canImport(DoubleBottom)
import DoubleBottom
#endif
#if canImport(ChatPassword)
import ChatPassword
#endif
#if canImport(VoiceMorpher)
import VoiceMorpher
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
    case notifications
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
    case other
}

private func tab(for section: LuxGramSection) -> LuxGramTab {
    switch section {
    case .search: return .appearance
    case .functions, .links: return .appearance
    case .notifications: return .other
    case .localPremium, .interface, .appearance, .fontReplacement: return .appearance
    case .messages, .chatList, .onlineStatus, .readReceipts, .content, .fakeLocation, .onlineStatusRecording: return .security
    case .other: return .other
    }
}

private func sectionForEntry(_ entry: LuxGramEntry) -> LuxGramSection {
    switch entry {
    case .header(_, let s, _, _): return s
    case .toggle(_, let s, _, _, _, _): return s
    case .toggleWithIcon(_, let s, _, _, _, _, _): return s
    case .notice(_, let s, _): return s
    case .percentageSlider(_, let s, _, _): return s
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

/// Account info tuple for per-account notification toggles.
typealias AccountInfo = (recordId: Int64, peerId: Int64, name: String)

/// Root LuxGram screen: liquid-glass header with 3 tab buttons + ССЫЛКИ section.
/// The ФУНКЦИИ section is removed — tab navigation is now in the header buttons.
private func gleGramRootEntries(presentationData: PresentationData, accounts: [AccountInfo] = []) -> [LuxGramEntry] {
    let lang = presentationData.strings.baseLanguageCode
    var entries: [LuxGramEntry] = []
    let id = SGItemListCounter()
    let linksHeader = lang == "ru" ? "ССЫЛКИ" : "LINKS"
    let channelTitle = lang == "ru" ? "Канал" : "Channel"
    let chatTitle = lang == "ru" ? "Чат" : "Chat"
    let forumTitle = lang == "ru" ? "Форум" : "Forum"
    entries.append(.header(id: id.count, section: .links, text: linksHeader, badge: nil))
    entries.append(LuxGramEntry.disclosureWithIcon(id: id.count, section: .links, link: .channelLink, text: channelTitle, iconRef: "Settings/Menu/Channels"))
    entries.append(LuxGramEntry.disclosureWithIcon(id: id.count, section: .links, link: .chatLink, text: chatTitle, iconRef: "Settings/Menu/GroupChats"))
    entries.append(LuxGramEntry.disclosureWithIcon(id: id.count, section: .links, link: .forumLink, text: forumTitle, iconRef: "Settings/Menu/Topics"))

    return entries
}

private enum LuxGramSliderSetting: Hashable {
    case fontReplacementSize
    case ghostModeMessageSendDelay
}

private enum LuxGramOneFromManySetting: Hashable {
    case onlineStatusRecordingInterval
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
    /// Read receipts: peers to exclude from sending read receipts.
    case readReceiptsExclusions
    // MARK: - LuxGram — Double Bottom, Chat Password, Voice Morpher
    case doubleBottom
    case chatPassword
    case voiceMorpher
    case pluginList
    /// Links section: open t.me URLs.
    case channelLink
    case chatLink
    case forumLink
    /// Beta section: channel with beta versions.
    case betaChannel
}

private typealias LuxGramEntry = SGItemListUIEntry<LuxGramSection, SGBoolSetting, LuxGramSliderSetting, LuxGramOneFromManySetting, LuxGramDisclosureLink, AnyHashable>

private struct LuxGramSettingsControllerState: Equatable {
    var searchQuery: String?
    var selectedTab: LuxGramTab = .appearance
}

/// Removes gated toggle entries, their dependent entries (disclosures, sliders, actions), following notices,
/// and orphaned headers (headers whose sub-section contains only notices after filtering).
private func filterGatedFeatures(entries: [LuxGramEntry]) -> [LuxGramEntry] {
    let settings = SGSimpleSettings.shared

    // Collect which toggle keys are gated (not visible)
    var gatedKeys = Set<String>()
    for entry in entries {
        if case let .toggle(_, _, settingName, _, _, _) = entry {
            if !settings.isFeatureVisible(settingName.rawValue) {
                gatedKeys.insert(settingName.rawValue)
            }
        }
    }

    if gatedKeys.isEmpty { return entries }

    // Disclosures that should be hidden when their parent toggle is gated
    let dependentDisclosures: [LuxGramDisclosureLink: SGBoolSetting] = [
        .fakeProfileSettings: .fakeProfileEnabled,
        .fakeLocationPicker: .fakeLocationEnabled,
        .feelRichAmount: .feelRichEnabled,
        .readReceiptsExclusions: .disableMessageReadReceipt,
        .savedDeletedMessagesList: .showDeletedMessages,
    ]

    // Sliders that should be hidden when their parent toggle is gated
    let dependentSliders: [LuxGramSliderSetting: SGBoolSetting] = [
        .ghostModeMessageSendDelay: .disableOnlineStatus,
    ]

    // Actions that should be hidden when their parent toggle is gated
    let dependentActions: [String: SGBoolSetting] = [
        "clearDeletedMessages": .showDeletedMessages,
    ]

    // First pass: remove gated entries and their dependents + following notices
    var filtered: [LuxGramEntry] = []
    var skipNextNotice = false

    for entry in entries {
        if skipNextNotice {
            skipNextNotice = false
            if case .notice = entry { continue }
        }

        // Skip gated toggles
        if case let .toggle(_, _, settingName, _, _, _) = entry {
            if gatedKeys.contains(settingName.rawValue) {
                skipNextNotice = true
                continue
            }
        }

        // Skip dependent disclosures
        if case let .disclosure(_, _, link, _) = entry {
            if let parent = dependentDisclosures[link], gatedKeys.contains(parent.rawValue) {
                skipNextNotice = true
                continue
            }
        }

        // Skip dependent delay sliders
        if case let .delaySecondsSlider(_, _, settingName, _, _, _, _) = entry {
            if let parent = dependentSliders[settingName], gatedKeys.contains(parent.rawValue) {
                skipNextNotice = true
                continue
            }
        }

        // Skip dependent actions
        if case let .action(_, _, actionType, _, _) = entry {
            if let actionStr = actionType as? String,
               let parent = dependentActions[actionStr],
               gatedKeys.contains(parent.rawValue) {
                skipNextNotice = true
                continue
            }
        }

        filtered.append(entry)
    }

    // Second pass: remove orphaned headers.
    // A header is orphaned if all entries until the next header (or end) are only notices.
    var result: [LuxGramEntry] = []
    var i = 0
    while i < filtered.count {
        if case .header = filtered[i] {
            // Look ahead to find the extent of this sub-section
            var j = i + 1
            var hasContent = false
            while j < filtered.count {
                if case .header = filtered[j] { break }
                if case .notice = filtered[j] {
                    // notices alone don't count as content
                } else {
                    hasContent = true
                }
                j += 1
            }
            if hasContent {
                for k in i..<j {
                    result.append(filtered[k])
                }
            }
            // else: skip this header and its trailing notices
            i = j
        } else {
            result.append(filtered[i])
            i += 1
        }
    }

    return result
}

private func gleGramEntries(presentationData: PresentationData, contentSettingsConfiguration: ContentSettingsConfiguration?, state: LuxGramSettingsControllerState, mediaBoxBasePath: String, accounts: [AccountInfo] = []) -> [LuxGramEntry] {
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
                                 ? "Сохраняет оригинальный текст сообщений при редактировании (в т.ч. чужих)."
                                 : "Keeps original message text when messages are edited (including from others).")
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
    let sendToCount = SGSimpleSettings.shared.messageReadReceiptsSendToPeerIds.count
    let sendToText = (lang == "ru"
        ? "Отправлять отчёты выбранным" + (sendToCount > 0 ? " (\(sendToCount))" : "")
        : "Send receipts to selected" + (sendToCount > 0 ? " (\(sendToCount))" : ""))
    entries.append(.disclosure(id: id.count, section: .readReceipts, link: .readReceiptsExclusions, text: sendToText))
    let sendToNotice = (lang == "ru"
        ? "Пустой список = никому не отправлять. Иначе — только выбранным."
        : "Empty list = send to no one. Otherwise — only to selected.")
    entries.append(.notice(id: id.count, section: .readReceipts, text: sendToNotice))
    let disableStoryReadReceiptTitle = (lang == "ru" ? "Отчёты: истории" : i18n("DISABLE_STORY_READ_RECEIPT_TITLE", lang))
    entries.append(.toggle(id: id.count, section: .readReceipts, settingName: .disableStoryReadReceipt, value: SGSimpleSettings.shared.disableStoryReadReceipt, text: disableStoryReadReceiptTitle, enabled: true))
    entries.append(.notice(id: id.count, section: .readReceipts, text: i18n("DISABLE_STORY_READ_RECEIPT_SUBTITLE", lang)))

    // MARK: - LuxGram — Double Bottom
    let doubleBottomTitle = (lang == "ru" ? "Двойное дно" : "Double Bottom")
    entries.append(.disclosure(id: id.count, section: .readReceipts, link: .doubleBottom, text: doubleBottomTitle))

    // MARK: - LuxGram — Chat Password
    let chatPasswordTitle = (lang == "ru" ? "Пароль на чат" : "Chat Password")
    entries.append(.disclosure(id: id.count, section: .readReceipts, link: .chatPassword, text: chatPasswordTitle))

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
    let enableSavingSelfDestructTitle = (lang == "ru" ? "Сохранять самоуничтож." : i18n("ENABLE_SAVING_SELF_DESTRUCTING_MESSAGES_TITLE", lang))
    entries.append(.toggle(id: id.count, section: .content, settingName: .enableSavingSelfDestructingMessages, value: SGSimpleSettings.shared.enableSavingSelfDestructingMessages, text: enableSavingSelfDestructTitle, enabled: true))
    entries.append(.notice(id: id.count, section: .content, text: i18n("ENABLE_SAVING_SELF_DESTRUCTING_MESSAGES_SUBTITLE", lang)))
    let disableScreenshotDetectionTitle = (lang == "ru" ? "Скрыть скриншоты" : i18n("DISABLE_SCREENSHOT_DETECTION_TITLE", lang))
    entries.append(.toggle(id: id.count, section: .content, settingName: .disableScreenshotDetection, value: SGSimpleSettings.shared.disableScreenshotDetection, text: disableScreenshotDetectionTitle, enabled: true))
    entries.append(.notice(id: id.count, section: .content, text: i18n("DISABLE_SCREENSHOT_DETECTION_SUBTITLE", lang)))
    let disableSecretBlurTitle = (lang == "ru" ? "Не размывать секретные" : i18n("DISABLE_SECRET_CHAT_BLUR_ON_SCREENSHOT_TITLE", lang))
    entries.append(.toggle(id: id.count, section: .content, settingName: .disableSecretChatBlurOnScreenshot, value: SGSimpleSettings.shared.disableSecretChatBlurOnScreenshot, text: disableSecretBlurTitle, enabled: true))
    entries.append(.notice(id: id.count, section: .content, text: i18n("DISABLE_SECRET_CHAT_BLUR_ON_SCREENSHOT_SUBTITLE", lang)))
    
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
    
    // MARK: Local premium
    entries.append(.header(id: id.count, section: .localPremium, text: i18n("Settings.Other.LocalPremium", lang), badge: nil))
    entries.append(.toggle(id: id.count, section: .localPremium, settingName: .enableLocalPremium, value: SGSimpleSettings.shared.enableLocalPremium, text: i18n("Settings.Other.EnableLocalPremium", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .localPremium, text: i18n("Settings.Other.LocalPremium.Notice", lang)))
    
    // Tab Organizer removed (CallListSettings.tabOrder not in 12.5)
    
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
    // MARK: - LuxGram — Liquid Glass
    entries.append(.header(id: id.count, section: .appearance, text: (lang == "ru" ? "ЖИДКОЕ СТЕКЛО" : "LIQUID GLASS"), badge: nil))
    let liquidGlassTitle = (lang == "ru" ? "Жидкое стекло" : "Liquid Glass")
    let liquidGlassNotice = (lang == "ru"
        ? "Применяет эффект матового стекла к навигационной панели, вкладкам и тулбарам. Изменение вступает в силу сразу."
        : "Applies frosted-glass effect to navigation bar, tabs and toolbars. Takes effect immediately.")
    entries.append(.toggle(id: id.count, section: .appearance, settingName: .liquidGlassEnabled, value: SGSimpleSettings.shared.liquidGlassEnabled, text: liquidGlassTitle, enabled: true))
    entries.append(.notice(id: id.count, section: .appearance, text: liquidGlassNotice))
    // MARK: - End LuxGram

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
    
    let feelRichTitle = (lang == "ru" ? "Локальный баланс звёзд" : "Local stars balance")
    entries.append(.toggle(id: id.count, section: .other, settingName: .feelRichEnabled, value: SGSimpleSettings.shared.feelRichEnabled, text: feelRichTitle, enabled: true))
    entries.append(.disclosure(id: id.count, section: .other, link: .feelRichAmount, text: (lang == "ru" ? "Изменить сумму" : "Change amount") + " (\(SGSimpleSettings.shared.feelRichStarsAmount))"))

    // MARK: - LuxGram — Voice Morpher
    let voiceMorpherTitle = (lang == "ru" ? "Изменение голоса" : "Voice Morpher")
    entries.append(.disclosure(id: id.count, section: .other, link: .voiceMorpher, text: voiceMorpherTitle))

    // MARK: - LuxGram — Plugins
    let pluginsTitle = (lang == "ru" ? "Плагины" : "Plugins")
    entries.append(.toggle(id: id.count, section: .other, settingName: .pluginSystemEnabled, value: SGSimpleSettings.shared.pluginSystemEnabled, text: pluginsTitle, enabled: true))
    if SGSimpleSettings.shared.pluginSystemEnabled {
        entries.append(.disclosure(id: id.count, section: .other, link: .pluginList, text: (lang == "ru" ? "Управление плагинами" : "Manage Plugins")))
    }

    // MARK: Per-account notification mute
    if accounts.count > 1 {
        let notifHeader = lang == "ru" ? "УВЕДОМЛЕНИЯ" : "NOTIFICATIONS"
        entries.append(.header(id: id.count, section: .notifications, text: notifHeader, badge: nil))
        for account in accounts {
            let isMuted = SGSimpleSettings.shared.isAccountNotificationMuted(recordId: account.recordId)
            let stateText = isMuted ? (lang == "ru" ? " (выкл)" : " (off)") : ""
            let title = account.name + stateText
            entries.append(.action(id: id.count, section: .notifications, actionType: "toggleNotificationMute_\(account.recordId)" as AnyHashable, text: title, kind: .generic))
        }
        let notifNotice = lang == "ru"
            ? "Отключите уведомления для аккаунтов, от которых не нужны push-уведомления."
            : "Disable notifications for accounts that should not receive push notifications."
        entries.append(.notice(id: id.count, section: .notifications, text: notifNotice))
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
    
    // MARK: Gated features — hide toggles that are gated and not unlocked
    let filteredEntries = filterGatedFeatures(entries: entries)

    return filterSGItemListUIEntrires(entries: filteredEntries, by: state.searchQuery)
}

public func gleGramSettingsController(context: AccountContext) -> ViewController {
    let access = cachedAggregateAccess()

    // Primary gate: server-provided access flag (verified through integrity layers)
    let hasAccess = access.luxgramTab

    // Secondary gate: accumulator-derived access (independent verification path)
    let accumulatorOK = SupportersIntegrity.deriveGlegramTab()

    // Access granted only when BOTH paths agree (or accumulator not yet populated on cold start)
    let fragmentsReady = SupportersIntegrity.fragmentCount() >= 3
    let granted = hasAccess && (!fragmentsReady || accumulatorOK)

    if !granted, let promoData = cachedAggregatePromo() {
        return gleGramPaywallController(context: context, promo: promoData.promo, trialAvailable: promoData.trialAvailable)
    }

    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?
    #if canImport(FaceScanScreen)
    var presentAgeVerificationImpl: ((@escaping () -> Void) -> Void)?
    #endif
    
    let reloadPromise = ValuePromise(true, ignoreRepeated: false)
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
            case .disableStoryReadReceipt:
                SGSimpleSettings.shared.disableStoryReadReceipt = value
            case .disableAllAds:
                SGSimpleSettings.shared.disableAllAds = value
            case .hideProxySponsor:
                SGSimpleSettings.shared.hideProxySponsor = value
                NotificationCenter.default.post(name: .sgHideProxySponsorDidChange, object: nil)
            case .enableSavingProtectedContent:
                SGSimpleSettings.shared.enableSavingProtectedContent = value
            case .enableSavingSelfDestructingMessages:
                SGSimpleSettings.shared.enableSavingSelfDestructingMessages = value
            case .disableScreenshotDetection:
                SGSimpleSettings.shared.disableScreenshotDetection = value
            case .disableSecretChatBlurOnScreenshot:
                SGSimpleSettings.shared.disableSecretChatBlurOnScreenshot = value
            case .enableLocalPremium:
                SGSimpleSettings.shared.enableLocalPremium = value
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
            // MARK: - LuxGram — Liquid Glass
            case .liquidGlassEnabled:
                SGSimpleSettings.shared.liquidGlassEnabled = value
                NotificationCenter.default.post(name: .luxgramLiquidGlassDidChange, object: nil)
            // MARK: - End LuxGram
            case .fakeLocationEnabled:
                SGSimpleSettings.shared.fakeLocationEnabled = value
            case .keepRemovedChannels:
                SGSimpleSettings.shared.keepRemovedChannels = value
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
            default:
                break
            }
            reloadPromise.set(true)
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
                reloadPromise.set(true)
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
                        reloadPromise.set(true)
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
                context.sharedContext.openExternalUrl(context: context, urlContext: .generic, url: "https://t.me/luxgramios", forceExternal: true, presentationData: pd, navigationController: nil, dismissInput: {})
                return
            }
            if link == .chatLink {
                let pd = context.sharedContext.currentPresentationData.with { $0 }
                context.sharedContext.openExternalUrl(context: context, urlContext: .generic, url: "https://t.me/luxgramios_chat", forceExternal: true, presentationData: pd, navigationController: nil, dismissInput: {})
                return
            }
            if link == .forumLink {
                let pd = context.sharedContext.currentPresentationData.with { $0 }
                context.sharedContext.openExternalUrl(context: context, urlContext: .generic, url: "https://t.me/luxgram_forum", forceExternal: true, presentationData: pd, navigationController: nil, dismissInput: {})
                return
            }
            if link == .betaChannel {
                if let betaConfig = cachedAggregateBetaConfig(), let url = betaConfig.channelUrl, isUrlSafeForExternalOpen(url) {
                    let pd = context.sharedContext.currentPresentationData.with { $0 }
                    context.sharedContext.openExternalUrl(context: context, urlContext: .generic, url: url, forceExternal: false, presentationData: pd, navigationController: nil, dismissInput: {})
                }
                return
            }
            if link == .fakeLocationPicker {
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                #if canImport(SGFakeLocation)
                let pickerController = FakeLocationPickerController(presentationData: presentationData, onSave: {
                    reloadPromise.set(true)
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
                // TODO: LuxGram — TabOrganizerController disabled (CallListSettings.tabOrder not in 12.5)
                return
            }
            // MARK: - LuxGram — Double Bottom
            else if link == .doubleBottom {
                #if canImport(DoubleBottom)
                pushControllerImpl?(doubleBottomSettingsController(context: context))
                #else
                let pd = context.sharedContext.currentPresentationData.with { $0 }
                let lang = pd.strings.baseLanguageCode
                presentControllerImpl?(UndoOverlayController(
                    presentationData: pd,
                    content: .info(title: nil, text: (lang == "ru" ? "Модуль DoubleBottom не подключён." : "DoubleBottom module is not available."), timeout: 3.0, customUndoText: nil),
                    elevatedLayout: false,
                    action: { _ in return false }
                ), nil)
                #endif
                return
            }
            // MARK: - LuxGram — Chat Password
            else if link == .chatPassword {
                #if canImport(ChatPassword)
                pushControllerImpl?(protectedChatsSettingsController(context: context))
                #else
                let pd = context.sharedContext.currentPresentationData.with { $0 }
                let lang = pd.strings.baseLanguageCode
                presentControllerImpl?(UndoOverlayController(
                    presentationData: pd,
                    content: .info(title: nil, text: (lang == "ru" ? "Модуль ChatPassword не подключён." : "ChatPassword module is not available."), timeout: 3.0, customUndoText: nil),
                    elevatedLayout: false,
                    action: { _ in return false }
                ), nil)
                #endif
                return
            }
            // MARK: - LuxGram — Voice Morpher
            else if link == .voiceMorpher {
                #if canImport(VoiceMorpher)
                let pd = context.sharedContext.currentPresentationData.with { $0 }
                let lang = pd.strings.baseLanguageCode
                let actionSheet = ActionSheetController(presentationData: pd)
                let presets = VoiceMorpherManager.VoicePreset.allCases
                var items: [ActionSheetItem] = []
                for preset in presets where preset != .disabled {
                    let name: String
                    switch preset {
                    case .disabled: name = ""
                    case .anonymous: name = lang == "ru" ? "Анонимный" : "Anonymous"
                    case .female: name = lang == "ru" ? "Женский" : "Female"
                    case .male: name = lang == "ru" ? "Мужской" : "Male"
                    case .child: name = lang == "ru" ? "Детский" : "Child"
                    case .robot: name = lang == "ru" ? "Робот" : "Robot"
                    }
                    items.append(ActionSheetButtonItem(title: name, color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        VoiceMorpherManager.shared.selectedPresetId = preset.rawValue
                    }))
                }
                items.append(ActionSheetButtonItem(title: (lang == "ru" ? "Выключить" : "Disable"), color: .destructive, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    VoiceMorpherManager.shared.selectedPresetId = VoiceMorpherManager.VoicePreset.disabled.rawValue
                }))
                actionSheet.setItemGroups([
                    ActionSheetItemGroup(items: items),
                    ActionSheetItemGroup(items: [
                        ActionSheetButtonItem(title: pd.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                        })
                    ])
                ])
                presentControllerImpl?(actionSheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
                #else
                let pd = context.sharedContext.currentPresentationData.with { $0 }
                let lang = pd.strings.baseLanguageCode
                presentControllerImpl?(UndoOverlayController(
                    presentationData: pd,
                    content: .info(title: nil, text: (lang == "ru" ? "Модуль VoiceMorpher не подключён." : "VoiceMorpher module is not available."), timeout: 3.0, customUndoText: nil),
                    elevatedLayout: false,
                    action: { _ in return false }
                ), nil)
                #endif
                return
            }
            else if link == .pluginList {
                pushControllerImpl?(PluginListController(context: context, onPluginsChanged: { reloadPromise.set(true) }))
                return
            }
            else if link == .profileCover {
                pushControllerImpl?(ProfileCoverController(context: context))
            } else if link == .fakeProfileSettings {
                pushControllerImpl?(FakeProfileSettingsController(context: context, onSave: { reloadPromise.set(true) }))
            } else if link == .feelRichAmount {
                pushControllerImpl?(FeelRichAmountController(context: context, onSave: { reloadPromise.set(true) }))
            } else if link == .savedDeletedMessagesList {
                pushControllerImpl?(savedDeletedMessagesListController(context: context))
            } else if link == .readReceiptsExclusions {
                let stored = SGSimpleSettings.shared.messageReadReceiptsSendToPeerIds
                var peerIds: [PeerId] = []
                for key in stored {
                    let parts = key.split(separator: ":")
                    if parts.count == 2, let ns = Int32(parts[0]), let idVal = Int64(parts[1]) {
                        peerIds.append(PeerId(namespace: PeerId.Namespace._internalFromInt32Value(ns), id: PeerId.Id._internalFromInt64Value(idVal)))
                    }
                }
                let loadPeers: Signal<[PeerId: SelectivePrivacyPeer], NoError> = context.engine.data.get(
                    EngineDataMap(peerIds.map(TelegramEngine.EngineData.Item.Peer.Peer.init)),
                    EngineDataMap(peerIds.map(TelegramEngine.EngineData.Item.Peer.ParticipantCount.init))
                )
                |> map { peerMap, participantCountMap -> [PeerId: SelectivePrivacyPeer] in
                    var result: [PeerId: SelectivePrivacyPeer] = [:]
                    for peerId in peerIds {
                        if let maybePeer = peerMap[peerId], let peer = maybePeer {
                            var participantCount: Int32?
                            if case let .channel(channel) = peer, case .group = channel.info {
                                if let maybeCount = participantCountMap[peerId], let count = maybeCount {
                                    participantCount = Int32(count)
                                }
                            }
                            result[peer.id] = SelectivePrivacyPeer(peer: peer._asPeer(), participantCount: participantCount)
                        }
                    }
                    return result
                }
                let disposable = (loadPeers |> deliverOnMainQueue |> take(1)).start(next: { initialPeers in
                    let title = (context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode == "ru")
                        ? "Отправлять отчёты выбранным"
                        : "Send read receipts to"
                    let controller = selectivePrivacyPeersController(
                        context: context,
                        title: title,
                        footer: nil,
                        hideContacts: false,
                        initialPeers: initialPeers,
                        initialEnableForPremium: false,
                        displayPremiumCategory: false,
                        initialEnableForBots: false,
                        displayBotsCategory: false,
                        updated: { updatedPeerIds, _, _ in
                            var newSet: Set<String> = []
                            for (peerId, _) in updatedPeerIds {
                                newSet.insert("\(peerId.namespace._internalGetInt32Value()):\(peerId.id._internalGetInt64Value())")
                            }
                            SGSimpleSettings.shared.messageReadReceiptsSendToPeerIds = newSet
                            reloadPromise.set(true)
                        }
                    )
                    pushControllerImpl?(controller)
                })
                // Keep disposable alive for the async load
                _ = disposable
            } else if link == .fontReplacementPicker {
                let pickerController = FontReplacementPickerController(context: context, mode: .main, onSave: {
                    reloadPromise.set(true)
                    context.sharedContext.notifyFontSettingsChanged()
                })
                presentControllerImpl?(pickerController, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
            } else if link == .fontReplacementBoldPicker {
                let pickerController = FontReplacementPickerController(context: context, mode: .bold, onSave: {
                    reloadPromise.set(true)
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
                                let fontsDir = documentsURL.appendingPathComponent("SwiftgramFonts", isDirectory: true)
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
                            reloadPromise.set(true)
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
                                let fontsDir = documentsURL.appendingPathComponent("SwiftgramFonts", isDirectory: true)
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
                            reloadPromise.set(true)
                        }
                    }
                )
                presentControllerImpl?(picker, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
            }
        },
        action: { actionType in
            guard let actionString = actionType as? String else { return }

            // Per-account notification mute toggle
            if actionString.hasPrefix("toggleNotificationMute_") {
                let recordIdStr = String(actionString.dropFirst("toggleNotificationMute_".count))
                if let recordId = Int64(recordIdStr) {
                    let isMuted = SGSimpleSettings.shared.isAccountNotificationMuted(recordId: recordId)
                    SGSimpleSettings.shared.setAccountNotificationMuted(recordId: recordId, muted: !isMuted)
                    reloadPromise.set(true)
                }
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
                                reloadPromise.set(true)
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
                        reloadPromise.set(true)
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
                        reloadPromise.set(true)
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
        let tabSignal = combineLatest(reloadPromise.get(), statePromise.get(), context.sharedContext.presentationData, contentSettingsConfigurationPromise.get(), context.sharedContext.activeAccountsWithInfo)
        |> map { _, state, presentationData, contentSettingsConfiguration, accountsWithInfo -> (ItemListControllerState, (ItemListNodeState, SGItemListArguments<SGBoolSetting, LuxGramSliderSetting, LuxGramOneFromManySetting, LuxGramDisclosureLink, AnyHashable>)) in
            let lang = presentationData.strings.baseLanguageCode
            let tabTitles = lang == "ru" ? ["Оформление", "Приватность", "Другие функции"] : ["Appearance", "Privacy", "Other"]
            let tabTitle = tabTitles[tab.rawValue]
            var tabState = state
            tabState.selectedTab = tab
            let accounts: [AccountInfo] = accountsWithInfo.accounts.map { info in
                let recordId = info.account.id.int64
                let peerId = info.account.peerId.id._internalGetInt64Value()
                let name = EnginePeer(info.peer).displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                return (recordId: recordId, peerId: peerId, name: name)
            }
            let allEntries = gleGramEntries(presentationData: presentationData, contentSettingsConfiguration: contentSettingsConfiguration, state: tabState, mediaBoxBasePath: context.account.postbox.mediaBox.basePath, accounts: accounts)
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
    
    let signal: Signal<(ItemListControllerState, (ItemListNodeState, SGItemListArguments<SGBoolSetting, LuxGramSliderSetting, LuxGramOneFromManySetting, LuxGramDisclosureLink, AnyHashable>)), NoError> = combineLatest(reloadPromise.get(), context.sharedContext.presentationData, context.sharedContext.activeAccountsWithInfo)
    |> map { _, presentationData, accountsWithInfo -> (ItemListControllerState, (ItemListNodeState, SGItemListArguments<SGBoolSetting, LuxGramSliderSetting, LuxGramOneFromManySetting, LuxGramDisclosureLink, AnyHashable>)) in
        SGSimpleSettings.shared.currentAccountPeerId = "\(context.account.peerId.id._internalGetInt64Value())"
        let lang = presentationData.strings.baseLanguageCode
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("LuxGram"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let accounts: [AccountInfo] = accountsWithInfo.accounts.map { info in
            let recordId = info.account.id.int64
            let peerId = info.account.peerId.id._internalGetInt64Value()
            let name = EnginePeer(info.peer).displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
            return (recordId: recordId, peerId: peerId, name: name)
        }
        let entries = gleGramRootEntries(presentationData: presentationData, accounts: accounts)
        // MARK: - LuxGram liquid glass header with tab buttons
        let headerItem = LuxGramHeaderItem(
            theme: presentationData.theme,
            title: "LuxGram",
            subtitle: lang == "ru" ? "Следующий уровень общения" : "Next-level messenger",
            lang: lang,
            onAppearanceTap: { argumentsRef?.openDisclosureLink(.appearanceTab) },
            onPrivacyTap:    { argumentsRef?.openDisclosureLink(.securityTab) },
            onOtherTap:      { argumentsRef?.openDisclosureLink(.otherTab) }
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks,
            ensureVisibleItemTag: nil,
            headerItem: headerItem,
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

