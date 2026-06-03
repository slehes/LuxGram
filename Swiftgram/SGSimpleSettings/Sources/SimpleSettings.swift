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
        
        // Older builds used an empty value which resulted in the classic badge being shown.
        if self.customAppBadge.isEmpty || self.customAppBadge == "Components/AppBadge" {
            self.customAppBadge = "SkyAppBadge"
        }

        let chatListLinesMigrationKey = "migrated_\(Keys.chatListLines.rawValue)"
        if !UserDefaults.standard.bool(forKey: chatListLinesMigrationKey) {
            let legacyCompactMessagePreviewKey = "compactMessagePreview"
            if UserDefaults.standard.object(forKey: legacyCompactMessagePreviewKey) != nil {
                if UserDefaults.standard.bool(forKey: legacyCompactMessagePreviewKey) {
                    self.chatListLines = ChatListLines.one.rawValue
                }
                UserDefaults.standard.removeObject(forKey: legacyCompactMessagePreviewKey)
                SGLogger.shared.log("SGSimpleSettings", "Migrated compactMessagePreview -> chatListLines. \(self.chatListLines)")
            }
            UserDefaults.standard.set(true, forKey: chatListLinesMigrationKey)
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
            { let _ = self.chatListLines },
            { let _ = self.compactFolderNames },
            { let _ = self.disableSwipeToRecordStory },
            { let _ = self.rememberLastFolder },
            { let _ = self.quickTranslateButton },
            { let _ = self.stickerSize },
            { let _ = self.stickerTimestamp },
            { let _ = self.hideReactions },
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
        case hideStories
        case warnOnStoriesOpen
        case showProfileId
        case sendWithReturnKey
        case chatListLines
        case showDeletedMessages
        case saveEditHistory
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
        case disableStoryReadReceipt
        case disableAllAds
        case hideProxySponsor
        case enableSavingProtectedContent
        case disableScreenshotDetection
        case enableSavingSelfDestructingMessages
        case disableSecretChatBlurOnScreenshot
        case enableLocalPremium
        case scrollToTopButtonEnabled
        case fakeLocationEnabled
        case keepRemovedChannels
        case enableVideoToCircleOrVoice
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
        case notificationMutedAccountRecordIds
        case gatedFeatureKeys
        case unlockedFeatureKeys
        case liquidGlassEnabled
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
    
    public enum ChatListLines: String, CaseIterable {
        case three = "3"
        case two = "2"
        case one = "1"

        public static let defaultValue: ChatListLines = .three
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
        Keys.hideStories.rawValue: false,
        Keys.warnOnStoriesOpen.rawValue: false,
        Keys.showProfileId.rawValue: true,
        Keys.sendWithReturnKey.rawValue: false,
        Keys.chatListLines.rawValue: ChatListLines.defaultValue.rawValue,
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
        Keys.disableStoryReadReceipt.rawValue: false,
        Keys.disableAllAds.rawValue: false,
        Keys.hideProxySponsor.rawValue: false,
        Keys.enableSavingProtectedContent.rawValue: false,
        Keys.disableScreenshotDetection.rawValue: false,
        Keys.enableSavingSelfDestructingMessages.rawValue: false,
        Keys.disableSecretChatBlurOnScreenshot.rawValue: false,
        Keys.enableLocalPremium.rawValue: false,
        Keys.scrollToTopButtonEnabled.rawValue: true,
        Keys.fakeLocationEnabled.rawValue: false,
        Keys.keepRemovedChannels.rawValue: false,
        Keys.enableVideoToCircleOrVoice.rawValue: false,
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
        Keys.liquidGlassEnabled.rawValue: false,
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
        Keys.gatedFeatureKeys.rawValue: [] as [String],
        Keys.unlockedFeatureKeys.rawValue: [] as [String]
    ]
    
    public static let groupDefaultValues: [String: Any] = [
        Keys.legacyNotificationsFix.rawValue: false,
        Keys.pinnedMessageNotifications.rawValue: PinnedMessageNotificationsSettings.default.rawValue,
        Keys.mentionsAndRepliesNotifications.rawValue: MentionsAndRepliesNotificationsSettings.default.rawValue,
        Keys.status.rawValue: 1,
        Keys.showRepostToStoryV2.rawValue: true,
        Keys.notificationMutedAccountRecordIds.rawValue: [] as [String],
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

    /// Account record IDs (as strings) for which push notifications are muted.
    @UserDefault(key: Keys.notificationMutedAccountRecordIds.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var notificationMutedAccountRecordIds: [String]

    public func isAccountNotificationMuted(recordId: Int64) -> Bool {
        return notificationMutedAccountRecordIds.contains(String(recordId))
    }

    public func setAccountNotificationMuted(recordId: Int64, muted: Bool) {
        let key = String(recordId)
        var current = notificationMutedAccountRecordIds
        if muted {
            if !current.contains(key) {
                current.append(key)
            }
        } else {
            current.removeAll { $0 == key }
        }
        notificationMutedAccountRecordIds = current
    }

    @UserDefault(key: Keys.gatedFeatureKeys.rawValue)
    public var gatedFeatureKeys: [String]

    @UserDefault(key: Keys.unlockedFeatureKeys.rawValue)
    public var unlockedFeatureKeys: [String]

    /// A gated feature is visible only if it's been unlocked (or if it's not gated at all).
    public func isFeatureVisible(_ settingKey: String) -> Bool {
        if !gatedFeatureKeys.contains(settingKey) { return true }
        return unlockedFeatureKeys.contains(settingKey)
    }

    public func unlockFeature(_ settingKey: String) {
        var current = unlockedFeatureKeys
        if !current.contains(settingKey) {
            current.append(settingKey)
            unlockedFeatureKeys = current
        }
    }

    /// Deeplink path → feature key mapping (cached from server)
    private static let gatedDeeplinkMapKey = "sg_gatedDeeplinkMap"

    public var gatedDeeplinkMap: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: Self.gatedDeeplinkMapKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.gatedDeeplinkMapKey) }
    }

    /// Update gated features from server response
    public func updateGatedFeatures(_ features: [(key: String, deeplinkPath: String)]) {
        gatedFeatureKeys = features.map { $0.key }
        var map: [String: String] = [:]
        for f in features { map[f.deeplinkPath] = f.key }
        gatedDeeplinkMap = map
    }

    /// Handle deeplink path. For single paths, unlocks locally and returns the key.
    /// For group paths (not in map), returns nil — server will handle and return keys.
    public func handleFeatureDeeplink(_ path: String) -> String? {
        guard let key = gatedDeeplinkMap[path] else {
            // Group path (e.g. "unlock-all", "ghost-mode") — not in local map.
            // Server will resolve and return unlocked keys.
            return nil
        }
        unlockFeature(key)
        return key
    }

    /// Unlock multiple features at once (used for group deeplinks after server response).
    public func unlockFeatures(_ keys: [String]) {
        var current = unlockedFeatureKeys
        for key in keys {
            if !current.contains(key) {
                current.append(key)
            }
        }
        unlockedFeatureKeys = current
    }

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

    @UserDefault(key: Keys.hideStories.rawValue)
    public var hideStories: Bool

    @UserDefault(key: Keys.warnOnStoriesOpen.rawValue)
    public var warnOnStoriesOpen: Bool

    @UserDefault(key: Keys.showProfileId.rawValue)
    public var showProfileId: Bool

    @UserDefault(key: Keys.chatListLines.rawValue)
    public var chatListLines: String

    @UserDefault(key: Keys.sendWithReturnKey.rawValue)
    public var sendWithReturnKey: Bool

    @UserDefault(key: Keys.showDeletedMessages.rawValue)
    public var showDeletedMessages: Bool
    
    @UserDefault(key: Keys.saveEditHistory.rawValue)
    public var saveEditHistory: Bool
    
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
    
    /// Peer IDs (as "namespace:id") to whom read receipts ARE sent (whitelist). Empty = send to all.
    public var messageReadReceiptsSendToPeerIds: Set<String> {
        get {
            if let data = UserDefaults.standard.data(forKey: "messageReadReceiptsSendToPeerIds"),
               let array = try? JSONDecoder().decode([String].self, from: data) {
                return Set(array)
            }
            return []
        }
        set {
            if let data = try? JSONEncoder().encode(Array(newValue)) {
                UserDefaults.standard.set(data, forKey: "messageReadReceiptsSendToPeerIds")
                synchronizeShared()
            }
        }
    }
    
    /// Check if read receipts should be blocked for this peer (when disableMessageReadReceipt is false).
    /// Whitelist: empty list = send to no one; non-empty = send only to peers in list.
    public func shouldBlockReadReceiptFor(peerIdNamespace: Int32, peerIdId: Int64) -> Bool {
        let list = messageReadReceiptsSendToPeerIds
        if list.isEmpty { return true }
        let key = "\(peerIdNamespace):\(peerIdId)"
        return !list.contains(key)
    }
    
    @UserDefault(key: Keys.disableStoryReadReceipt.rawValue)
    public var disableStoryReadReceipt: Bool
    
    @UserDefault(key: Keys.disableAllAds.rawValue)
    public var disableAllAds: Bool
    
    @UserDefault(key: Keys.hideProxySponsor.rawValue)
    public var hideProxySponsor: Bool
    
    @UserDefault(key: Keys.enableSavingProtectedContent.rawValue)
    public var enableSavingProtectedContent: Bool
    
    @UserDefault(key: Keys.enableSavingSelfDestructingMessages.rawValue)
    public var enableSavingSelfDestructingMessages: Bool
    
    @UserDefault(key: Keys.disableSecretChatBlurOnScreenshot.rawValue)
    public var disableSecretChatBlurOnScreenshot: Bool
    
    @UserDefault(key: Keys.enableLocalPremium.rawValue)
    public var enableLocalPremium: Bool
    
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
    
    @UserDefault(key: Keys.keepRemovedChannels.rawValue)
    public var keepRemovedChannels: Bool
    
    @UserDefault(key: Keys.enableVideoToCircleOrVoice.rawValue)
    public var enableVideoToCircleOrVoice: Bool
    
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
    
    @UserDefault(key: Keys.chatExportEnabled.rawValue)
    public var chatExportEnabled: Bool

    @UserDefault(key: Keys.liquidGlassEnabled.rawValue)
    public var liquidGlassEnabled: Bool

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
    
    public var removedChannels: [Int64] {
        get {
            if let data = UserDefaults.standard.data(forKey: "removedChannels"),
               let array = try? JSONDecoder().decode([Int64].self, from: data) {
                return array
            }
            return []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "removedChannels")
                synchronizeShared()
            }
        }
    }
    
    public func isChannelRemoved(_ peerId: Int64) -> Bool {
        return keepRemovedChannels && removedChannels.contains(peerId)
    }
    
    public func markChannelAsRemoved(_ peerId: Int64) {
        if !removedChannels.contains(peerId) {
            removedChannels.append(peerId)
        }
    }
    
    public func unmarkChannelAsRemoved(_ peerId: Int64) {
        removedChannels.removeAll { $0 == peerId }
    }
    
    public var removedUserChats: [Int64] {
        get {
            if let data = UserDefaults.standard.data(forKey: "removedUserChats"),
               let array = try? JSONDecoder().decode([Int64].self, from: data) {
                return array
            }
            return []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "removedUserChats")
                synchronizeShared()
            }
        }
    }
    
    public func isUserChatRemoved(_ peerId: Int64) -> Bool {
        return keepRemovedChannels && removedUserChats.contains(peerId)
    }
    
    public func markUserChatAsRemoved(_ peerId: Int64) {
        if !removedUserChats.contains(peerId) {
            removedUserChats.append(peerId)
        }
    }
    
    public func unmarkUserChatAsRemoved(_ peerId: Int64) {
        removedUserChats.removeAll { $0 == peerId }
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

public extension Notification.Name {
    /// Posted when "Hide Proxy Sponsor" is toggled so the chat list can refresh.
    static let sgHideProxySponsorDidChange = Notification.Name("SGHideProxySponsorDidChange")
    /// Posted when a badge image finishes downloading so the UI can re-render.
    static let sgBadgeImageDidCache = Notification.Name("SGBadgeImageDidCache")
}
