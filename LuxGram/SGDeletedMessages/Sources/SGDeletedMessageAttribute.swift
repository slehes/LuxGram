import Foundation
import Postbox

public final class SGDeletedMessageAttribute: MessageAttribute, Equatable {
    public var isDeleted: Bool
    public var originalText: String?
    /// Full edit history: [original, edit1, edit2, ...]. First is original, last is previous before current.
    public var editHistory: [String]
    // For SavedDeleted snapshots, keep a reference to the original message id.
    public var originalNamespace: Int32?
    public var originalId: Int32?
    
    public init(isDeleted: Bool = false, originalText: String? = nil, editHistory: [String] = [], originalNamespace: Int32? = nil, originalId: Int32? = nil) {
        self.isDeleted = isDeleted
        self.originalText = originalText
        self.editHistory = editHistory
        self.originalNamespace = originalNamespace
        self.originalId = originalId
    }
    
    public init(decoder: PostboxDecoder) {
        self.isDeleted = decoder.decodeInt32ForKey("d", orElse: 0) != 0
        self.originalText = decoder.decodeOptionalStringForKey("ot")
        self.editHistory = decoder.decodeOptionalStringArrayForKey("eh") ?? []
        self.originalNamespace = decoder.decodeOptionalInt32ForKey("on")
        self.originalId = decoder.decodeOptionalInt32ForKey("oi")
    }
    
    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.isDeleted ? 1 : 0, forKey: "d")
        if let originalText = self.originalText {
            encoder.encodeString(originalText, forKey: "ot")
        }
        if !editHistory.isEmpty {
            encoder.encodeStringArray(editHistory, forKey: "eh")
        }
        if let originalNamespace = self.originalNamespace {
            encoder.encodeInt32(originalNamespace, forKey: "on")
        }
        if let originalId = self.originalId {
            encoder.encodeInt32(originalId, forKey: "oi")
        }
    }
    
    public static func ==(lhs: SGDeletedMessageAttribute, rhs: SGDeletedMessageAttribute) -> Bool {
        return lhs.isDeleted == rhs.isDeleted && lhs.originalText == rhs.originalText && lhs.editHistory == rhs.editHistory && lhs.originalNamespace == rhs.originalNamespace && lhs.originalId == rhs.originalId
    }
    
    /// All text versions in chronological order: [original, edit1, edit2, ..., current].
    public func allEditVersions(currentText: String) -> [String] {
        var versions: [String] = []
        if let ot = originalText, !ot.isEmpty {
            versions.append(ot)
        }
        for h in editHistory where !h.isEmpty && h != versions.last {
            versions.append(h)
        }
        if !currentText.isEmpty && currentText != versions.last {
            versions.append(currentText)
        }
        return versions
    }
}

public extension Message {
    var sgDeletedAttribute: SGDeletedMessageAttribute {
        for attribute in self.attributes {
            if let deletedAttribute = attribute as? SGDeletedMessageAttribute {
                return deletedAttribute
            }
        }
        return SGDeletedMessageAttribute()
    }
}

public extension Transaction {
    func updateSGDeletedAttribute(messageId: MessageId, _ block: (inout SGDeletedMessageAttribute) -> Void) {
        self.updateMessage(messageId) { message in
            var attributes = message.attributes
            attributes.updateSGDeletedAttribute(block)
            let storeForwardInfo = message.forwardInfo.flatMap(StoreMessageForwardInfo.init)
            return .update(StoreMessage(
                id: message.id,
                customStableId: nil,
                globallyUniqueId: message.globallyUniqueId,
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
                media: message.media
            ))
        }
    }
}

public extension StoreMessage {
    func updatingSGDeletedAttributeOnEdit(previousMessage: Message) -> StoreMessage {
        let newAttr = self.attributes.compactMap { $0 as? SGDeletedMessageAttribute }.first
        let attr = newAttr ?? previousMessage.sgDeletedAttribute
        
        if attr.originalText == nil {
            attr.originalText = previousMessage.text
        }
        // Append previous text to full edit history (skip if same as last)
        let prev = previousMessage.text
        if !prev.isEmpty {
            let last = attr.editHistory.last ?? attr.originalText
            if prev != last {
                attr.editHistory.append(prev)
            }
        }
        
        var attributes = self.attributes
        attributes.updateSGDeletedAttribute {
            $0 = attr
        }
        
        return self.withUpdatedAttributes(attributes)
    }
}

private extension Array<MessageAttribute> {
    mutating func updateSGDeletedAttribute(_ block: (inout SGDeletedMessageAttribute) -> Void) {
        for (index, attribute) in self.enumerated() {
            if var deletedAttribute = attribute as? SGDeletedMessageAttribute {
                block(&deletedAttribute)
                self[index] = deletedAttribute
                return
            }
        }
        
        var deletedAttribute = SGDeletedMessageAttribute()
        block(&deletedAttribute)
        self.append(deletedAttribute)
    }
}
