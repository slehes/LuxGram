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
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: ""), text: query, placeholder: presentationData.strings.Common_Search, type: .regular(capitalization: false, autocorrection: false), spacing: 0.0, clearType: .always, tag: nil, sectionId: section, textUpdated: { args.searchUpdated($0) }, action: {})
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

private let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
}()

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

/// Filter by search query - two-pass, keep search, keep sections that have matches.
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
