// Ref: https://github.com/nicegram/Nicegram-iOS/blob/master/Nicegram/NGDoubleBottom/Sources/DoubleBottomListController.swift
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
import PasscodeUI
import DoubleBottom
import SGSimpleSettings
import TelegramStringFormatting

private enum DoubleBottomControllerSection: Int32 {
    case isOn = 0
}

private enum DoubleBottomEntry: ItemListNodeEntry {
    case isOn(String, Bool, Bool)  // title, value, enabled
    case info(String)

    var section: ItemListSectionId { DoubleBottomControllerSection.isOn.rawValue }

    var stableId: Int32 {
        switch self {
        case .isOn: return 1000
        case .info: return 1100
        }
    }

    static func < (lhs: DoubleBottomEntry, rhs: DoubleBottomEntry) -> Bool {
        lhs.stableId < rhs.stableId
    }

    static func == (lhs: DoubleBottomEntry, rhs: DoubleBottomEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.isOn(lhsText, lhsBool, _), .isOn(rhsText, rhsBool, _)):
            return lhsText == rhsText && lhsBool == rhsBool
        case let (.info(lhsText), .info(rhsText)):
            return lhsText == rhsText
        default:
            return false
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! DoubleBottomArguments
        switch self {
        case let .isOn(text, value, enabled):
            return ItemListSwitchItem(
                presentationData: presentationData,
                title: text,
                value: value,
                enabled: enabled,
                sectionId: section,
                style: .blocks,
                updated: { value in
                    args.updated(value)
                }
            )
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        }
    }
}

private final class DoubleBottomArguments {
    let context: AccountContext
    let updated: (Bool) -> Void
    init(context: AccountContext, updated: @escaping (Bool) -> Void) {
        self.context = context
        self.updated = updated
    }
}

public func doubleBottomSettingsController(context: AccountContext) -> ViewController {
    let lang = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
    let title = lang == "ru" ? "Двойное дно" : "Double Bottom"
    let toggleTitle = lang == "ru" ? "Двойное дно" : "Double Bottom"
    let noticeText = lang == "ru"
        ? "Скрытые аккаунты и вход по паролю. Разные пароли открывают разные профили."
        : "Hidden accounts and passcode access. Different passwords open different profiles."

    let arguments = DoubleBottomArguments(context: context, updated: { value in
        if value {
            SGSimpleSettings.shared.doubleBottomEnabled = true
            let setupController = PasscodeSetupController(context: context, mode: .setup(change: false, .digits6))
            setupController.complete = { passcode, _ in
                DoubleBottomPasscodeStore.setSecretPasscode(passcode)
                setupController.dismiss()
            }
            context.sharedContext.presentGlobalController(setupController, nil)
        } else {
            SGSimpleSettings.shared.doubleBottomEnabled = false
            DoubleBottomPasscodeStore.removeSecretPasscode()
            DoubleBottomViewingSecretStore.setViewingWithSecretPasscode(false)
            let accountManager = context.sharedContext.accountManager
            // Remove secret passcodes from Keychain for previously hidden accounts
            let _ = (accountManager.accountRecords()
                |> take(1)
                |> deliverOnMainQueue).start(next: { view in
                    for record in view.records where record.attributes.contains(where: { $0.isHiddenAccountAttribute }) {
                        DoubleBottomPasscodeStore.removePasscode(forAccountId: record.id.int64)
                    }
                })
            // Nicegram: single transaction - keep device passcode, remove HiddenAccount from all records
            let _ = accountManager.transaction { transaction in
                let challengeData = transaction.getAccessChallengeData()
                let challenge: PostboxAccessChallengeData
                switch challengeData {
                case .numericalPassword(let value):
                    challenge = .numericalPassword(value: value)
                case .plaintextPassword(let value):
                    challenge = .plaintextPassword(value: value)
                case .none:
                    challenge = .none
                }
                transaction.setAccessChallengeData(challenge)
                for record in transaction.getRecords() {
                    transaction.updateRecord(record.id) { current in
                        guard let current = current else { return nil }
                        var attributes = current.attributes
                        attributes.removeAll { $0.isHiddenAccountAttribute }
                        return AccountRecord(id: current.id, attributes: attributes, temporarySessionId: current.temporarySessionId)
                    }
                }
            }.start()
        }
    })

    let transactionStatus = context.sharedContext.accountManager.transaction { transaction -> (Bool, Bool) in
        let records = transaction.getRecords()
        let publicCount = records.filter { record in
            let attrs = record.attributes
            let hiddenOrLoggedOut = attrs.contains(where: { $0.isHiddenAccountAttribute || $0.isLoggedOutAccountAttribute })
            return !hiddenOrLoggedOut
        }.count
        let hasMoreThanOnePublic = publicCount > 1
        let hasMainPasscode = transaction.getAccessChallengeData() != .none
        return (hasMoreThanOnePublic, hasMainPasscode)
    }

    let signal: Signal<(ItemListControllerState, (ItemListNodeState, DoubleBottomArguments)), NoError> = combineLatest(context.sharedContext.presentationData, transactionStatus)
        |> map { presentationData, contextStatus -> (ItemListControllerState, (ItemListNodeState, DoubleBottomArguments)) in
            let isOn = SGSimpleSettings.shared.doubleBottomEnabled
            let enabled = isOn || (contextStatus.0 && contextStatus.1)
            let entries: [DoubleBottomEntry] = [
                .isOn(toggleTitle, isOn, enabled),
                .info(noticeText)
            ]
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

    return ItemListController(context: context, state: signal)
}

public func doubleBottomCheckPasscode(_ passcode: String, challengeData: PostboxAccessChallengeData) -> Bool {
    let passcodeType: PasscodeEntryFieldType
    switch challengeData {
    case let .numericalPassword(value):
        passcodeType = value.count == 6 ? .digits6 : .digits4
    default:
        passcodeType = .alphanumeric
    }
    switch challengeData {
    case .none:
        return true
    case let .numericalPassword(code):
        if passcodeType == .alphanumeric {
            return false
        }
        return passcode == normalizeArabicNumeralString(code, type: .western)
    case let .plaintextPassword(code):
        if passcodeType != .alphanumeric {
            return false
        }
        return passcode == code
    }
}
