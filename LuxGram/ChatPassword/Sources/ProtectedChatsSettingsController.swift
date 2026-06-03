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
