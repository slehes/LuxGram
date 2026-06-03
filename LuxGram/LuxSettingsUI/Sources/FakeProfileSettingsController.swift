import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import SGItemListUI
import SGSimpleSettings

private enum FakeProfileSection: Int32, SGItemListSection {
    case targetUser = 0
    case personalData
    case badges
}

private enum FakeProfileEntry: ItemListNodeEntry {
    case targetHeader(id: Int, text: String)
    case targetUserId(id: Int, text: String, placeholder: String)
    case targetNotice(id: Int, text: String)
    case personalHeader(id: Int, text: String)
    case firstName(id: Int, text: String, placeholder: String)
    case lastName(id: Int, text: String, placeholder: String)
    case username(id: Int, text: String, placeholder: String)
    case phone(id: Int, text: String, placeholder: String)
    case fakeId(id: Int, text: String, placeholder: String)
    case personalNotice(id: Int, text: String)
    case badgesHeader(id: Int, text: String)
    case premium(id: Int, title: String, subtext: String?, value: Bool)
    case verified(id: Int, title: String, subtext: String?, value: Bool)
    case scam(id: Int, title: String, subtext: String?, value: Bool)
    case fake(id: Int, title: String, subtext: String?, value: Bool)
    case support(id: Int, title: String, subtext: String?, value: Bool)
    case bot(id: Int, title: String, subtext: String?, value: Bool)
    case badgesNotice(id: Int, text: String)

    var id: Int { stableId }
    var section: ItemListSectionId {
        switch self {
        case .targetHeader, .targetUserId, .targetNotice: return FakeProfileSection.targetUser.rawValue
        case .personalHeader, .firstName, .lastName, .username, .phone, .fakeId, .personalNotice: return FakeProfileSection.personalData.rawValue
        default: return FakeProfileSection.badges.rawValue
        }
    }
    var stableId: Int {
        switch self {
        case .targetHeader(let i, _), .targetUserId(let i, _, _), .targetNotice(let i, _),
             .personalHeader(let i, _), .firstName(let i, _, _), .lastName(let i, _, _), .username(let i, _, _),
             .phone(let i, _, _), .fakeId(let i, _, _), .personalNotice(let i, _),
             .badgesHeader(let i, _), .premium(let i, _, _, _), .verified(let i, _, _, _), .scam(let i, _, _, _),
             .fake(let i, _, _, _), .support(let i, _, _, _), .bot(let i, _, _, _), .badgesNotice(let i, _): return i
        }
    }
    static func < (lhs: FakeProfileEntry, rhs: FakeProfileEntry) -> Bool { lhs.stableId < rhs.stableId }
    static func == (lhs: FakeProfileEntry, rhs: FakeProfileEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.targetHeader(a, t1), .targetHeader(b, t2)): return a == b && t1 == t2
        case let (.targetUserId(a, t1, p1), .targetUserId(b, t2, p2)): return a == b && t1 == t2 && p1 == p2
        case let (.targetNotice(a, t1), .targetNotice(b, t2)): return a == b && t1 == t2
        case let (.personalHeader(a, t1), .personalHeader(b, t2)): return a == b && t1 == t2
        case let (.firstName(a, t1, p1), .firstName(b, t2, p2)): return a == b && t1 == t2 && p1 == p2
        case let (.lastName(a, t1, p1), .lastName(b, t2, p2)): return a == b && t1 == t2 && p1 == p2
        case let (.username(a, t1, p1), .username(b, t2, p2)): return a == b && t1 == t2 && p1 == p2
        case let (.phone(a, t1, p1), .phone(b, t2, p2)): return a == b && t1 == t2 && p1 == p2
        case let (.fakeId(a, t1, p1), .fakeId(b, t2, p2)): return a == b && t1 == t2 && p1 == p2
        case let (.personalNotice(a, t1), .personalNotice(b, t2)): return a == b && t1 == t2
        case let (.badgesHeader(a, t1), .badgesHeader(b, t2)): return a == b && t1 == t2
        case let (.premium(a, t1, s1, v1), .premium(b, t2, s2, v2)): return a == b && t1 == t2 && s1 == s2 && v1 == v2
        case let (.verified(a, t1, s1, v1), .verified(b, t2, s2, v2)): return a == b && t1 == t2 && s1 == s2 && v1 == v2
        case let (.scam(a, t1, s1, v1), .scam(b, t2, s2, v2)): return a == b && t1 == t2 && s1 == s2 && v1 == v2
        case let (.fake(a, t1, s1, v1), .fake(b, t2, s2, v2)): return a == b && t1 == t2 && s1 == s2 && v1 == v2
        case let (.support(a, t1, s1, v1), .support(b, t2, s2, v2)): return a == b && t1 == t2 && s1 == s2 && v1 == v2
        case let (.bot(a, t1, s1, v1), .bot(b, t2, s2, v2)): return a == b && t1 == t2 && s1 == s2 && v1 == v2
        case let (.badgesNotice(a, t1), .badgesNotice(b, t2)): return a == b && t1 == t2
        default: return false
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let theme = presentationData.theme
        let args = arguments as! FakeProfileArguments
        switch self {
        case .targetHeader(_, let text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: section)
        case .targetUserId(_, let text, let placeholder):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: "ID", textColor: theme.list.itemPrimaryTextColor), text: text, placeholder: placeholder, type: .regular(capitalization: false, autocorrection: false), clearType: .always, sectionId: section, textUpdated: { args.updateTargetUserId($0) }, action: {})
        case .targetNotice(_, let text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        case .personalHeader(_, let text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: section)
        case .firstName(_, let text, let placeholder):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: (presentationData.strings.baseLanguageCode == "ru" ? "Имя" : "First name"), textColor: theme.list.itemPrimaryTextColor), text: text, placeholder: placeholder, type: .regular(capitalization: true, autocorrection: false), clearType: .always, sectionId: section, textUpdated: { args.updateFirstName($0) }, action: {})
        case .lastName(_, let text, let placeholder):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: (presentationData.strings.baseLanguageCode == "ru" ? "Фамилия" : "Last name"), textColor: theme.list.itemPrimaryTextColor), text: text, placeholder: placeholder, type: .regular(capitalization: true, autocorrection: false), clearType: .always, sectionId: section, textUpdated: { args.updateLastName($0) }, action: {})
        case .username(_, let text, let placeholder):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: (presentationData.strings.baseLanguageCode == "ru" ? "Юзернейм (без @)" : "Username (no @)"), textColor: theme.list.itemPrimaryTextColor), text: text, placeholder: placeholder, type: .regular(capitalization: false, autocorrection: false), clearType: .always, sectionId: section, textUpdated: { args.updateUsername($0) }, action: {})
        case .phone(_, let text, let placeholder):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: (presentationData.strings.baseLanguageCode == "ru" ? "Телефон (без +)" : "Phone (no +)"), textColor: theme.list.itemPrimaryTextColor), text: text, placeholder: placeholder, type: .number, clearType: .always, sectionId: section, textUpdated: { args.updatePhone($0) }, action: {})
        case .fakeId(_, let text, let placeholder):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: "Telegram ID", textColor: theme.list.itemPrimaryTextColor), text: text, placeholder: placeholder, type: .number, clearType: .always, sectionId: section, textUpdated: { args.updateFakeId($0) }, action: {})
        case .personalNotice(_, let text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        case .badgesHeader(_, let text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: section)
        case .premium(_, let title, let subtext, let value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, text: subtext, value: value, sectionId: section, style: .blocks, updated: { args.updatePremium($0) })
        case .verified(_, let title, let subtext, let value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, text: subtext, value: value, sectionId: section, style: .blocks, updated: { args.updateVerified($0) })
        case .scam(_, let title, let subtext, let value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, text: subtext, value: value, sectionId: section, style: .blocks, updated: { args.updateScam($0) })
        case .fake(_, let title, let subtext, let value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, text: subtext, value: value, sectionId: section, style: .blocks, updated: { args.updateFake($0) })
        case .support(_, let title, let subtext, let value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, text: subtext, value: value, sectionId: section, style: .blocks, updated: { args.updateSupport($0) })
        case .bot(_, let title, let subtext, let value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, text: subtext, value: value, sectionId: section, style: .blocks, updated: { args.updateBot($0) })
        case .badgesNotice(_, let text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        }
    }
}

private final class FakeProfileArguments {
    let reload: () -> Void
    init(reload: @escaping () -> Void) { self.reload = reload }

    func updateTargetUserId(_ value: String) {
        SGSimpleSettings.shared.fakeProfileTargetUserId = value
        reload()
    }
    func updateFirstName(_ value: String) {
        SGSimpleSettings.shared.fakeProfileFirstName = value
        reload()
    }
    func updateLastName(_ value: String) {
        SGSimpleSettings.shared.fakeProfileLastName = value
        reload()
    }
    func updateUsername(_ value: String) {
        SGSimpleSettings.shared.fakeProfileUsername = value
        reload()
    }
    func updatePhone(_ value: String) {
        SGSimpleSettings.shared.fakeProfilePhone = value
        reload()
    }
    func updateFakeId(_ value: String) {
        SGSimpleSettings.shared.fakeProfileId = value
        reload()
    }
    func updatePremium(_ value: Bool) {
        SGSimpleSettings.shared.fakeProfilePremium = value
        reload()
    }
    func updateVerified(_ value: Bool) {
        SGSimpleSettings.shared.fakeProfileVerified = value
        reload()
    }
    func updateScam(_ value: Bool) {
        SGSimpleSettings.shared.fakeProfileScam = value
        reload()
    }
    func updateFake(_ value: Bool) {
        SGSimpleSettings.shared.fakeProfileFake = value
        reload()
    }
    func updateSupport(_ value: Bool) {
        SGSimpleSettings.shared.fakeProfileSupport = value
        reload()
    }
    func updateBot(_ value: Bool) {
        SGSimpleSettings.shared.fakeProfileBot = value
        reload()
    }
}

private func fakeProfileEntries(presentationData: PresentationData) -> [FakeProfileEntry] {
    let lang = presentationData.strings.baseLanguageCode
    let s = SGSimpleSettings.shared
    var entries: [FakeProfileEntry] = []
    var id = 0

    entries.append(.targetHeader(id: id, text: lang == "ru" ? "ЦЕЛЕВОЙ ПОЛЬЗОВАТЕЛЬ" : "TARGET USER"))
    id += 1
    entries.append(.targetUserId(id: id, text: s.fakeProfileTargetUserId, placeholder: lang == "ru" ? "Оставьте пустым для своего профиля" : "Leave empty for your profile"))
    id += 1
    entries.append(.targetNotice(id: id, text: lang == "ru" ? "Чтобы узнать ID, используйте @userinfobot" : "Use @userinfobot to get user ID"))
    id += 1

    entries.append(.personalHeader(id: id, text: lang == "ru" ? "ЛИЧНЫЕ ДАННЫЕ" : "PERSONAL DATA"))
    id += 1
    entries.append(.firstName(id: id, text: s.fakeProfileFirstName, placeholder: lang == "ru" ? "Имя" : "First name"))
    id += 1
    entries.append(.lastName(id: id, text: s.fakeProfileLastName, placeholder: lang == "ru" ? "Фамилия" : "Last name"))
    id += 1
    entries.append(.username(id: id, text: s.fakeProfileUsername, placeholder: lang == "ru" ? "без @" : "no @"))
    id += 1
    entries.append(.phone(id: id, text: s.fakeProfilePhone, placeholder: lang == "ru" ? "без +" : "no +"))
    id += 1
    entries.append(.fakeId(id: id, text: s.fakeProfileId, placeholder: lang == "ru" ? "Визуально изменить ID" : "Override displayed ID"))
    id += 1
    entries.append(.personalNotice(id: id, text: lang == "ru" ? "Пустые поля — реальные данные." : "Empty = real data."))
    id += 1

    entries.append(.badgesHeader(id: id, text: lang == "ru" ? "СТАТУСЫ И ЗНАЧКИ" : "BADGES"))
    id += 1
    let premiumTitle = lang == "ru" ? "Premium" : "Premium"
    let premiumSub = lang == "ru" ? "Визуально добавляет иконку Premium." : "Shows Premium badge."
    entries.append(.premium(id: id, title: premiumTitle, subtext: premiumSub, value: s.fakeProfilePremium))
    id += 1
    let verifiedTitle = lang == "ru" ? "Верификация" : "Verified"
    let verifiedSub = lang == "ru" ? "Визуально добавляет галочку." : "Shows verification badge."
    entries.append(.verified(id: id, title: verifiedTitle, subtext: verifiedSub, value: s.fakeProfileVerified))
    id += 1
    let scamTitle = lang == "ru" ? "Scam" : "Scam"
    let scamSub = lang == "ru" ? "Помечает как скам." : "Marks as scam."
    entries.append(.scam(id: id, title: scamTitle, subtext: scamSub, value: s.fakeProfileScam))
    id += 1
    let fakeTitle = lang == "ru" ? "Fake" : "Fake"
    let fakeSub = lang == "ru" ? "Помечает как фейк." : "Marks as fake."
    entries.append(.fake(id: id, title: fakeTitle, subtext: fakeSub, value: s.fakeProfileFake))
    id += 1
    let supportTitle = lang == "ru" ? "Support" : "Support"
    let supportSub = lang == "ru" ? "Официальная поддержка." : "Official support badge."
    entries.append(.support(id: id, title: supportTitle, subtext: supportSub, value: s.fakeProfileSupport))
    id += 1
    let botTitle = lang == "ru" ? "Бот" : "Bot"
    let botSub = lang == "ru" ? "Помечает как бота." : "Marks as bot."
    entries.append(.bot(id: id, title: botTitle, subtext: botSub, value: s.fakeProfileBot))
    id += 1
    entries.append(.badgesNotice(id: id, text: lang == "ru" ? "Для полного применения может потребоваться перезапуск." : "Restart may be required for full effect."))
    return entries
}

/// Fake Profile settings: target user ID, first/last name, username, phone, fake ID, badge toggles.
public func FakeProfileSettingsController(context: AccountContext, onSave: @escaping () -> Void) -> ViewController {
    let reloadPromise = ValuePromise(true, ignoreRepeated: false)
    let arguments = FakeProfileArguments(reload: { reloadPromise.set(true) })

    let signal = combineLatest(reloadPromise.get(), context.sharedContext.presentationData)
    |> map { _, presentationData -> (ItemListControllerState, (ItemListNodeState, FakeProfileArguments)) in
        let lang = presentationData.strings.baseLanguageCode
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(lang == "ru" ? "Настройки Fake Profile" : "Fake Profile settings"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let entries = fakeProfileEntries(presentationData: presentationData)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, ensureVisibleItemTag: nil, initialScrollToItem: nil)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    return controller
}
