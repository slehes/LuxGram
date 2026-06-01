/*
 * LuxGram: Export chat history via API (like Telegram Desktop / AyuGram Desktop).
 * Uses messages.getHistory / messages.getReplies with pagination.
 */
import Foundation
import SwiftSignalKit
@preconcurrency import Postbox
import TelegramApi
import MtProtoKit

public struct ChatExportMessageItem {
    public let id: Int32
    public let timestamp: Int32
    public let authorId: PeerId?
    public let text: String

    public init(id: Int32, timestamp: Int32, authorId: PeerId?, text: String) {
        self.id = id
        self.timestamp = timestamp
        self.authorId = authorId
        self.text = text
    }
}

public enum ExportChatHistoryError {
    case peerNotFound
    case generic
}

/// Fetches chat message history from the API in pages (like Desktop export).
/// Returns messages in chronological order (oldest first) and merged peers from all responses.
public func _internal_exportChatHistory(
    account: Account,
    peerId: PeerId,
    threadId: Int64?,
    maxCount: Int
) -> Signal<([ChatExportMessageItem], [PeerId: Peer]), ExportChatHistoryError> {
    let limit: Int32 = 100
    let requestMaxCount = min(maxCount, 100_000)

    return account.postbox.transaction { transaction -> (Peer, Api.InputPeer, Bool)? in
        guard let peer = transaction.getPeer(peerId), let inputPeer = apiInputPeer(peer) else {
            return nil
        }
        let peerIsForum = peer.isForumOrMonoForum
        return (peer, inputPeer, peerIsForum)
    }
    |> mapToSignalPromotingError { value -> Signal<([ChatExportMessageItem], [PeerId: Peer]), ExportChatHistoryError> in
        guard let (_, inputPeer, peerIsForum) = value else {
            return .fail(.peerNotFound)
        }

        var allItems: [ChatExportMessageItem] = []
        var allPeers: [PeerId: Peer] = [:]
        var offsetId: Int32 = 0
        var onlyMyMessages = false

        func requestNextBatch() -> Signal<([ChatExportMessageItem], [PeerId: Peer]), ExportChatHistoryError> {
            if allItems.count >= requestMaxCount {
                return .single((allItems, allPeers))
            }

            let currentOffsetId = offsetId
            let currentOnlyMyMessages = onlyMyMessages

            let request: Signal<Api.messages.Messages, MTRpcError>
            if let topicRootId = threadId {
                request = account.network.request(
                    Api.functions.messages.getReplies(
                        peer: inputPeer,
                        msgId: Int32(clamping: topicRootId),
                        offsetId: currentOffsetId,
                        offsetDate: 0,
                        addOffset: 0,
                        limit: limit,
                        maxId: Int32.max,
                        minId: 0,
                        hash: 0
                    )
                )
            } else if currentOnlyMyMessages {
                let selfInputPeer = Api.InputPeer.inputPeerSelf
                request = account.network.request(
                    Api.functions.messages.search(
                        flags: 1 << 0,
                        peer: inputPeer,
                        q: "",
                        fromId: selfInputPeer,
                        savedPeerId: nil,
                        savedReaction: nil,
                        topMsgId: nil,
                        filter: .inputMessagesFilterEmpty,
                        minDate: 0,
                        maxDate: Int32.max,
                        offsetId: currentOffsetId,
                        addOffset: 0,
                        limit: limit,
                        maxId: Int32.max,
                        minId: 0,
                        hash: 0
                    )
                )
            } else {
                request = account.network.request(
                    Api.functions.messages.getHistory(
                        peer: inputPeer,
                        offsetId: currentOffsetId,
                        offsetDate: 0,
                        addOffset: 0,
                        limit: limit,
                        maxId: Int32.max,
                        minId: 0,
                        hash: 0
                    )
                )
            }

            return request
            |> mapError { _ in ExportChatHistoryError.generic }
            |> mapToSignal { result -> Signal<([ChatExportMessageItem], [PeerId: Peer]), ExportChatHistoryError> in
                let messages: [Api.Message]
                let chats: [Api.Chat]
                let users: [Api.User]

                switch result {
                case let .messages(messagesData):
                    messages = messagesData.messages
                    chats = messagesData.chats
                    users = messagesData.users
                case let .messagesSlice(messagesSliceData):
                    messages = messagesSliceData.messages
                    chats = messagesSliceData.chats
                    users = messagesSliceData.users
                case let .channelMessages(channelMessagesData):
                    messages = channelMessagesData.messages
                    chats = channelMessagesData.chats
                    users = channelMessagesData.users
                case .messagesNotModified:
                    messages = []
                    chats = []
                    users = []
                }

                let parsedPeers = AccumulatedPeers(chats: chats, users: users)
                var batchItems: [ChatExportMessageItem] = []
                var minIdInBatch: Int32?

                for apiMessage in messages {
                    guard let storeMessage = StoreMessage(
                        apiMessage: apiMessage,
                        accountPeerId: account.peerId,
                        peerIsForum: peerIsForum
                    ) else { continue }

                    guard case let .Id(messageId) = storeMessage.id else { continue }
                    if storeMessage.media.contains(where: { $0 is TelegramMediaAction }) {
                        continue
                    }
                    batchItems.append(ChatExportMessageItem(
                        id: messageId.id,
                        timestamp: storeMessage.timestamp,
                        authorId: storeMessage.authorId,
                        text: storeMessage.text
                    ))
                    if minIdInBatch == nil || messageId.id < minIdInBatch! {
                        minIdInBatch = messageId.id
                    }
                }

                for (pid, p) in parsedPeers.peers {
                    allPeers[pid] = p
                }
                for (pid, user) in parsedPeers.users {
                    allPeers[pid] = TelegramUser(user: user)
                }

                allItems.append(contentsOf: batchItems)

                if batchItems.isEmpty {
                    return .single((allItems, allPeers))
                }

                if let minId = minIdInBatch {
                    offsetId = minId
                }
                if allItems.count >= requestMaxCount {
                    return .single((allItems, allPeers))
                }

                return requestNextBatch()
            }
            |> `catch` { error -> Signal<([ChatExportMessageItem], [PeerId: Peer]), ExportChatHistoryError> in
                if case .generic = error, !currentOnlyMyMessages, peerId.namespace == Namespaces.Peer.CloudChannel {
                    onlyMyMessages = true
                    offsetId = 0
                    return requestNextBatch()
                }
                return .fail(error)
            }
        }

        return requestNextBatch()
    }
    |> map { items, peers in
        (items.reversed(), peers)
    }
}

extension ExportChatHistoryError: Error {}
