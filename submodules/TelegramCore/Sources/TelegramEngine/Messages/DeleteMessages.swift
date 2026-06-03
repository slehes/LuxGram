import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi
#if canImport(SGDeletedMessages)
import SGDeletedMessages
#endif
#if canImport(SGSimpleSettings)
import SGSimpleSettings
#endif
#if canImport(SGLogging)
import SGLogging
#endif

func addMessageMediaResourceIdsToRemove(media: Media, resourceIds: inout [MediaResourceId]) {
    if let image = media as? TelegramMediaImage {
        for representation in image.representations {
            resourceIds.append(representation.resource.id)
        }
    } else if let file = media as? TelegramMediaFile {
        for representation in file.previewRepresentations {
            resourceIds.append(representation.resource.id)
        }
        resourceIds.append(file.resource.id)
    }
}

func addMessageMediaResourceIdsToRemove(message: Message, resourceIds: inout [MediaResourceId]) {
    for media in message.media {
        addMessageMediaResourceIdsToRemove(media: media, resourceIds: &resourceIds)
    }
}

/// Returns the message ids that were actually deleted.
public func _internal_forceDeleteMessages(transaction: Transaction, mediaBox: MediaBox, ids: [MessageId], deleteMedia: Bool = true, manualAddMessageThreadStatsDifference: ((MessageThreadKey, Int, Int) -> Void)? = nil) -> [MessageId] {
    let idsToDelete = ids
    var resourceIds: [MediaResourceId] = []
    if deleteMedia {
        for id in idsToDelete {
            if id.peerId.namespace == Namespaces.Peer.SecretChat {
                if let message = transaction.getMessage(id) {
                    addMessageMediaResourceIdsToRemove(message: message, resourceIds: &resourceIds)
                }
            }
        }
    }
    if !resourceIds.isEmpty {
        let _ = mediaBox.removeCachedResources(Array(Set(resourceIds)), force: true).start()
    }
    for id in idsToDelete {
        if id.peerId.namespace == Namespaces.Peer.CloudChannel && id.namespace == Namespaces.Message.Cloud {
            if let message = transaction.getMessage(id) {
                if let threadId = message.threadId {
                    let messageThreadKey = MessageThreadKey(peerId: message.id.peerId, threadId: threadId)
                    if id.peerId.namespace == Namespaces.Peer.CloudChannel {
                        if let manualAddMessageThreadStatsDifference = manualAddMessageThreadStatsDifference {
                            manualAddMessageThreadStatsDifference(messageThreadKey, 0, 1)
                        } else {
                            updateMessageThreadStats(transaction: transaction, threadKey: messageThreadKey, removedCount: 1, addedMessagePeers: [])
                        }
                    }
                }
            }
        }
    }
    transaction.deleteMessages(idsToDelete, forEachMedia: { _ in
    })
    return idsToDelete
}

/// Returns the message ids that were actually deleted (not marked as saved-deleted).
@discardableResult
public func _internal_deleteMessages(transaction: Transaction, mediaBox: MediaBox, ids: [MessageId], deleteMedia: Bool = true, manualAddMessageThreadStatsDifference: ((MessageThreadKey, Int, Int) -> Void)? = nil) -> [MessageId] {
    #if canImport(SGDeletedMessages)
    let savedSnapshots = SGDeletedMessages.saveSnapshots(
        ids: ids,
        transaction: transaction,
        shouldSave: { id, _ in
            #if canImport(SGSimpleSettings)
            // AyuGram-style: don't save bot chats if disabled
            if id.peerId.namespace == Namespaces.Peer.CloudUser,
               let peer = transaction.getPeer(id.peerId) as? TelegramUser,
               peer.botInfo != nil,
               !SGSimpleSettings.shared.saveDeletedMessagesForBots {
                return false
            }
            #endif
            return true
        },
        transformAttributes: { _, attributes in
            #if canImport(SGSimpleSettings)
            if !SGSimpleSettings.shared.saveDeletedMessagesReactions {
                attributes.removeAll(where: { $0 is ReactionsMessageAttribute })
            }
            #endif
        },
        transformMedia: { message, _ in
            // AyuGram-style: copy completed media resources to "Saved Attachments"
            return sgTransformMediaForSavedDeletedSnapshot(message: message, mediaBox: mediaBox)
        }
    )
    let idsToDelete = ids
    #if canImport(SGLogging)
    SGLogger.shared.log("SGDeletedMessages", "_internal_deleteMessages: ids=\(ids), savedSnapshots=\(savedSnapshots.count), deleting originals=\(idsToDelete.count)")
    #endif
    #else
    let idsToDelete = ids
    #endif
    var resourceIds: [MediaResourceId] = []
    if deleteMedia {
        for id in idsToDelete {
            if id.peerId.namespace == Namespaces.Peer.SecretChat {
                if let message = transaction.getMessage(id) {
                    #if canImport(SGDeletedMessages)
                    #if canImport(SGSimpleSettings)
                    // AyuGram-style: if we saved a snapshot and media saving is enabled,
                    // don't immediately purge cached resources for secret chats.
                    if savedSnapshots.contains(id) && SGSimpleSettings.shared.saveDeletedMessagesMedia {
                        continue
                    }
                    #endif
                    #endif
                    addMessageMediaResourceIdsToRemove(message: message, resourceIds: &resourceIds)
                }
            }
        }
    }
    if !resourceIds.isEmpty {
        let _ = mediaBox.removeCachedResources(Array(Set(resourceIds)), force: true).start()
    }

    // If we are deleting SavedDeleted snapshots, remove their copied attachments from disk.
    let savedDeletedToDelete = idsToDelete.filter { $0.namespace == Namespaces.Message.SavedDeleted }
    if !savedDeletedToDelete.isEmpty {
        for id in savedDeletedToDelete {
            if let message = transaction.getMessage(id) {
                sgDeleteSavedDeletedAttachmentsForMessage(message)
            }
        }
    }
    for id in idsToDelete {
        if id.peerId.namespace == Namespaces.Peer.CloudChannel && id.namespace == Namespaces.Message.Cloud {
            if let message = transaction.getMessage(id) {
                if let threadId = message.threadId {
                    let messageThreadKey = MessageThreadKey(peerId: message.id.peerId, threadId: threadId)
                    if id.peerId.namespace == Namespaces.Peer.CloudChannel {
                        if let manualAddMessageThreadStatsDifference = manualAddMessageThreadStatsDifference {
                            manualAddMessageThreadStatsDifference(messageThreadKey, 0, 1)
                        } else {
                            updateMessageThreadStats(transaction: transaction, threadKey: messageThreadKey, removedCount: 1, addedMessagePeers: [])
                        }
                    }
                }
            }
        }
    }
    transaction.deleteMessages(idsToDelete, forEachMedia: { _ in
    })
    return idsToDelete
}

func _internal_deleteMessagesInRangeSafely(transaction: Transaction, mediaBox: MediaBox, peerId: PeerId, namespace: MessageId.Namespace, minId: MessageId.Id, maxId: MessageId.Id, forEachMedia: ((Media) -> Void)?) {
    #if canImport(SGDeletedMessages)
    guard SGDeletedMessages.showDeletedMessages else {
        // If feature is disabled, use normal deletion
        var resourceIds: [MediaResourceId] = []
        transaction.deleteMessagesInRange(peerId: peerId, namespace: namespace, minId: minId, maxId: maxId, forEachMedia: { media in
            addMessageMediaResourceIdsToRemove(media: media, resourceIds: &resourceIds)
            forEachMedia?(media)
        })
        if !resourceIds.isEmpty {
            let _ = mediaBox.removeCachedResources(Array(Set(resourceIds)), force: true).start()
        }
        return
    }

    // Collect all message IDs in range (ascending order — stop early once past maxId)
    var messageIdsInRange: [MessageId] = []
    transaction.withAllMessages(peerId: peerId, namespace: namespace, reversed: false) { message in
        if message.id.id > maxId {
            return false // Past the range — stop scanning
        }
        if message.id.id >= minId {
            messageIdsInRange.append(message.id)
        }
        return true
    }

    #if canImport(SGLogging)
    SGLogger.shared.log("SGDeletedMessages", "_internal_deleteMessagesInRangeSafely: peerId=\(peerId), namespace=\(namespace), range=[\(minId)...\(maxId)], found \(messageIdsInRange.count) messages in range")
    #endif

    // Filter out saved deleted messages
    var idsToDelete: [MessageId] = []
    var idsToKeep: [MessageId] = []
    var resourceIds: [MediaResourceId] = []

    for messageId in messageIdsInRange {
        if let message = transaction.getMessage(messageId) {
            // Check if message is saved (marked as deleted but should be kept)
            let isSaved = message.sgDeletedAttribute.isDeleted
            if isSaved {
                idsToKeep.append(messageId)
                #if canImport(SGLogging)
                SGLogger.shared.log("SGDeletedMessages", "_internal_deleteMessagesInRangeSafely: KEEPING saved message \(messageId)")
                #endif
            } else {
                idsToDelete.append(messageId)
                // Collect media resources for deletion
                for media in message.media {
                    addMessageMediaResourceIdsToRemove(media: media, resourceIds: &resourceIds)
                    forEachMedia?(media)
                }
            }
        }
    }

    #if canImport(SGLogging)
    SGLogger.shared.log("SGDeletedMessages", "_internal_deleteMessagesInRangeSafely: keeping \(idsToKeep.count), deleting \(idsToDelete.count)")
    #endif

    // Delete only non-saved messages
    if !idsToDelete.isEmpty {
        _ = _internal_deleteMessages(transaction: transaction, mediaBox: mediaBox, ids: idsToDelete, deleteMedia: false)
    }

    if !resourceIds.isEmpty {
        let _ = mediaBox.removeCachedResources(Array(Set(resourceIds)), force: true).start()
    }
    #else
    // No SGDeletedMessages support - use normal deletion
    var resourceIds: [MediaResourceId] = []
    transaction.deleteMessagesInRange(peerId: peerId, namespace: namespace, minId: minId, maxId: maxId, forEachMedia: { media in
        addMessageMediaResourceIdsToRemove(media: media, resourceIds: &resourceIds)
        forEachMedia?(media)
    })
    if !resourceIds.isEmpty {
        let _ = mediaBox.removeCachedResources(Array(Set(resourceIds)), force: true).start()
    }
    #endif
}

func _internal_deleteAllMessagesWithAuthor(transaction: Transaction, mediaBox: MediaBox, peerId: PeerId, authorId: PeerId, namespace: MessageId.Namespace) {
    var resourceIds: [MediaResourceId] = []
    transaction.removeAllMessagesWithAuthor(peerId, authorId: authorId, namespace: namespace, forEachMedia: { media in
        addMessageMediaResourceIdsToRemove(media: media, resourceIds: &resourceIds)
    })
    if !resourceIds.isEmpty {
        let _ = mediaBox.removeCachedResources(Array(Set(resourceIds))).start()
    }
}

func _internal_deleteAllMessagesWithForwardAuthor(transaction: Transaction, mediaBox: MediaBox, peerId: PeerId, forwardAuthorId: PeerId, namespace: MessageId.Namespace) {
    var resourceIds: [MediaResourceId] = []
    transaction.removeAllMessagesWithForwardAuthor(peerId, forwardAuthorId: forwardAuthorId, namespace: namespace, forEachMedia: { media in
        addMessageMediaResourceIdsToRemove(media: media, resourceIds: &resourceIds)
    })
    if !resourceIds.isEmpty {
        let _ = mediaBox.removeCachedResources(Array(Set(resourceIds)), force: true).start()
    }
}

func _internal_clearHistory(transaction: Transaction, mediaBox: MediaBox, peerId: PeerId, threadId: Int64?, namespaces: MessageIdNamespaces) {
    if peerId.namespace == Namespaces.Peer.SecretChat {
        var resourceIds: [MediaResourceId] = []
        transaction.withAllMessages(peerId: peerId, { message in
            addMessageMediaResourceIdsToRemove(message: message, resourceIds: &resourceIds)
            return true
        })
        if !resourceIds.isEmpty {
            let _ = mediaBox.removeCachedResources(Array(Set(resourceIds)), force: true).start()
        }
    }
    transaction.clearHistory(peerId, threadId: threadId, minTimestamp: nil, maxTimestamp: nil, namespaces: namespaces, forEachMedia: { _ in
    })
}

func _internal_clearHistoryInRange(transaction: Transaction, mediaBox: MediaBox, peerId: PeerId, threadId: Int64?, minTimestamp: Int32, maxTimestamp: Int32, namespaces: MessageIdNamespaces) {
    if peerId.namespace == Namespaces.Peer.SecretChat {
        var resourceIds: [MediaResourceId] = []
        transaction.withAllMessages(peerId: peerId, { message in
            if message.timestamp >= minTimestamp && message.timestamp <= maxTimestamp {
                addMessageMediaResourceIdsToRemove(message: message, resourceIds: &resourceIds)
            }
            return true
        })
        if !resourceIds.isEmpty {
            let _ = mediaBox.removeCachedResources(Array(Set(resourceIds)), force: true).start()
        }
    }
    transaction.clearHistory(peerId, threadId: threadId, minTimestamp: minTimestamp, maxTimestamp: maxTimestamp, namespaces: namespaces, forEachMedia: { _ in
    })
}

public enum ClearCallHistoryError {
    case generic
}

func _internal_clearCallHistory(account: Account, forEveryone: Bool) -> Signal<Never, ClearCallHistoryError> {
    return account.postbox.transaction { transaction -> Signal<Void, NoError> in
        var flags: Int32 = 0
        if forEveryone {
            flags |= 1 << 0
        }
        
        let signal = account.network.request(Api.functions.messages.deletePhoneCallHistory(flags: flags))
        |> map { result -> Api.messages.AffectedFoundMessages? in
            return result
        }
        |> `catch` { _ -> Signal<Api.messages.AffectedFoundMessages?, Bool> in
            return .fail(false)
        }
        |> mapToSignal { result -> Signal<Void, Bool> in
            if let result = result {
                switch result {
                case let .affectedFoundMessages(affectedFoundMessagesData):
                    let (pts, ptsCount, offset) = (affectedFoundMessagesData.pts, affectedFoundMessagesData.ptsCount, affectedFoundMessagesData.offset)
                    account.stateManager.addUpdateGroups([.updatePts(pts: pts, ptsCount: ptsCount)])
                    if offset == 0 {
                        return .fail(true)
                    } else {
                        return .complete()
                    }
                }
            } else {
                return .fail(true)
            }
        }
        return (signal
        |> restart)
        |> `catch` { success -> Signal<Void, NoError> in
            if success {
                return account.postbox.transaction { transaction -> Void in
                    transaction.removeAllMessagesWithGlobalTag(tag: GlobalMessageTags.Calls)
                }
            } else {
                return .complete()
            }
        }
    }
    |> switchToLatest
    |> ignoreValues
    |> castError(ClearCallHistoryError.self)
}

public enum SetChatMessageAutoremoveTimeoutError {
    case generic
}

func _internal_setChatMessageAutoremoveTimeoutInteractively(account: Account, peerId: PeerId, timeout: Int32?) -> Signal<Never, SetChatMessageAutoremoveTimeoutError> {
    return account.postbox.transaction { transaction -> Api.InputPeer? in
        return transaction.getPeer(peerId).flatMap(apiInputPeer)
    }
    |> castError(SetChatMessageAutoremoveTimeoutError.self)
    |> mapToSignal { inputPeer -> Signal<Never, SetChatMessageAutoremoveTimeoutError> in
        guard let inputPeer = inputPeer else {
            return .fail(.generic)
        }
        return account.network.request(Api.functions.messages.setHistoryTTL(peer: inputPeer, period: timeout ?? 0))
        |> map(Optional.init)
        |> `catch` { _ -> Signal<Api.Updates?, NoError> in
            return .single(nil)
        }
        |> castError(SetChatMessageAutoremoveTimeoutError.self)
        |> mapToSignal { result -> Signal<Never, SetChatMessageAutoremoveTimeoutError> in
            if let result = result {
                account.stateManager.addUpdates(result)
                
                return account.postbox.transaction { transaction -> Void in
                    transaction.updatePeerCachedData(peerIds: [peerId], update: { _, current in
                        let updatedTimeout: CachedPeerAutoremoveTimeout
                        if let timeout = timeout {
                            updatedTimeout = .known(CachedPeerAutoremoveTimeout.Value(peerValue: timeout))
                        } else {
                            updatedTimeout = .known(nil)
                        }
                        
                        if peerId.namespace == Namespaces.Peer.CloudUser {
                            let current = (current as? CachedUserData) ?? CachedUserData()
                            return current.withUpdatedAutoremoveTimeout(updatedTimeout)
                        } else if peerId.namespace == Namespaces.Peer.CloudChannel {
                            let current = (current as? CachedChannelData) ?? CachedChannelData()
                            return current.withUpdatedAutoremoveTimeout(updatedTimeout)
                        } else if peerId.namespace == Namespaces.Peer.CloudGroup {
                            let current = (current as? CachedGroupData) ?? CachedGroupData()
                            return current.withUpdatedAutoremoveTimeout(updatedTimeout)
                        } else {
                            return current
                        }
                    })
                }
                |> castError(SetChatMessageAutoremoveTimeoutError.self)
                |> ignoreValues
            } else {
                return .fail(.generic)
            }
        }
        |> `catch` { _ -> Signal<Never, SetChatMessageAutoremoveTimeoutError> in
            return .complete()
        }
    }
}
