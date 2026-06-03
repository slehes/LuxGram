import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import SGSimpleSettings

private enum FeelRichAmountEntry: ItemListNodeEntry {
    case header(id: Int, text: String)
    case amount(id: Int, text: String, placeholder: String)

    var id: Int { stableId }
    var section: ItemListSectionId { 0 }
    var stableId: Int {
        switch self {
        case .header(let id, _), .amount(let id, _, _): return id
        }
    }
    static func < (lhs: FeelRichAmountEntry, rhs: FeelRichAmountEntry) -> Bool { lhs.stableId < rhs.stableId }
    static func == (lhs: FeelRichAmountEntry, rhs: FeelRichAmountEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.header(a, t1), .header(b, t2)): return a == b && t1 == t2
        case let (.amount(a, t1, p1), .amount(b, t2, p2)): return a == b && t1 == t2 && p1 == p2
        default: return false
        }
    }
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let theme = presentationData.theme
        let args = arguments as! FeelRichAmountArguments
        switch self {
        case .header(_, let text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: section)
        case .amount(_, let text, let placeholder):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: (presentationData.strings.baseLanguageCode == "ru" ? "Сумма (звёзды)" : "Amount (stars)"), textColor: theme.list.itemPrimaryTextColor), text: text, placeholder: placeholder, type: .number, clearType: .always, sectionId: section, textUpdated: { args.updateAmount($0) }, action: {})
        }
    }
}

private final class FeelRichAmountArguments {
    let reload: () -> Void
    init(reload: @escaping () -> Void) { self.reload = reload }
    func updateAmount(_ value: String) {
        SGSimpleSettings.shared.feelRichStarsAmount = value
        reload()
    }
}

private func feelRichAmountEntries(presentationData: PresentationData) -> [FeelRichAmountEntry] {
    let lang = presentationData.strings.baseLanguageCode
    var entries: [FeelRichAmountEntry] = []
    var id = 0
    entries.append(.header(id: id, text: lang == "ru" ? "БАЛАНС ЗВЁЗД" : "STARS BALANCE"))
    id += 1
    entries.append(.amount(id: id, text: SGSimpleSettings.shared.feelRichStarsAmount, placeholder: "1000"))
    return entries
}

/// Edit local stars balance amount.
public func FeelRichAmountController(context: AccountContext, onSave: @escaping () -> Void) -> ViewController {
    let reloadPromise = ValuePromise(true, ignoreRepeated: false)
    let arguments = FeelRichAmountArguments(reload: { reloadPromise.set(true) })

    let signal = combineLatest(reloadPromise.get(), context.sharedContext.presentationData)
    |> map { _, presentationData -> (ItemListControllerState, (ItemListNodeState, FeelRichAmountArguments)) in
        let lang = presentationData.strings.baseLanguageCode
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(lang == "ru" ? "Сумма звёзд" : "Stars amount"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let entries = feelRichAmountEntries(presentationData: presentationData)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, ensureVisibleItemTag: nil, initialScrollToItem: nil)
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
