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
