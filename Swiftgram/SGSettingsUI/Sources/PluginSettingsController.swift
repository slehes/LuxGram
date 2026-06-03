import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import SGSimpleSettings
import SGItemListUI

private func loadInstalledPlugins() -> [PluginInfo] {
    guard let data = SGSimpleSettings.shared.installedPluginsJson.data(using: .utf8),
          let list = try? JSONDecoder().decode([PluginInfo].self, from: data) else {
        return []
    }
    return list
}

private func saveInstalledPlugins(_ plugins: [PluginInfo]) {
    if let data = try? JSONEncoder().encode(plugins),
       let json = String(data: data, encoding: .utf8) {
        SGSimpleSettings.shared.installedPluginsJson = json
        SGSimpleSettings.shared.synchronizeShared()
    }
}

private enum PluginSettingsSection: Int32, SGItemListSection {
    case main
    case pluginOptions
    case info
}

private typealias PluginSettingsEntry = SGItemListUIEntry<PluginSettingsSection, SGBoolSetting, AnyHashable, AnyHashable, AnyHashable, AnyHashable>

private let userDisplayBoolKeys: [(key: String, titleRu: String, titleEn: String)] = [
    ("enabled", "Включить подмену профиля", "Enable profile override"),
    ("fake_premium", "Premium статус", "Premium status"),
    ("fake_verified", "Статус верификации", "Verified status"),
    ("fake_scam", "Scam статус", "Scam status"),
    ("fake_fake", "Fake статус", "Fake status"),
    ("fake_support", "Support статус", "Support status"),
    ("fake_bot", "Bot статус", "Bot status"),
]

private let userDisplayStringKeys: [(key: String, titleRu: String, titleEn: String)] = [
    ("target_user_id", "Telegram ID пользователя", "User Telegram ID"),
    ("fake_first_name", "Имя", "First name"),
    ("fake_last_name", "Фамилия", "Last name"),
    ("fake_username", "Юзернейм (без @)", "Username (no @)"),
    ("fake_phone", "Номер телефона", "Phone number"),
    ("fake_id", "Telegram ID (визуально)", "Telegram ID (display)"),
]

private func pluginSettingsEntries(presentationData: PresentationData, plugin: PluginInfo) -> [PluginSettingsEntry] {
    let lang = presentationData.strings.baseLanguageCode
    let isRu = lang == "ru"
    var entries: [PluginSettingsEntry] = []
    let id = SGItemListCounter()
    let host = PluginHost.shared
    let pluginId = plugin.metadata.id

    entries.append(.header(id: id.count, section: .main, text: isRu ? "ПЛАГИН" : "PLUGIN", badge: nil))
    let enableText = plugin.enabled ? (isRu ? "Выключить плагин" : "Disable plugin") : (isRu ? "Включить плагин" : "Enable plugin")
    entries.append(.action(id: id.count, section: .main, actionType: "toggleEnabled" as AnyHashable, text: enableText, kind: .generic))
    entries.append(.notice(id: id.count, section: .main, text: isRu ? "Включает функциональность плагина." : "Enables plugin functionality."))

    if plugin.metadata.hasUserDisplay {
        entries.append(.header(id: id.count, section: .pluginOptions, text: isRu ? "НАСТРОЙКИ ОТОБРАЖЕНИЯ" : "DISPLAY SETTINGS", badge: nil))
        entries.append(.notice(id: id.count, section: .pluginOptions, text: isRu ? "Оставьте поля пустыми, чтобы использовать реальные данные. Пустой «Telegram ID пользователя» — свой профиль." : "Leave fields empty to use real data. Empty «User Telegram ID» means your own profile."))
        for item in userDisplayBoolKeys {
            let value = host.getPluginSettingBool(pluginId: pluginId, key: item.key, default: false)
            let label = value ? (isRu ? "Вкл" : "On") : (isRu ? "Выкл" : "Off")
            let text = "\(isRu ? item.titleRu : item.titleEn): \(label)"
            entries.append(.action(id: id.count, section: .pluginOptions, actionType: "pluginBool:\(item.key)" as AnyHashable, text: text, kind: .generic))
        }
        for item in userDisplayStringKeys {
            let value = host.getPluginSetting(pluginId: pluginId, key: item.key) ?? ""
            let label = value.isEmpty ? (isRu ? "—" : "—") : value
            let text = "\(isRu ? item.titleRu : item.titleEn): \(label)"
            entries.append(.action(id: id.count, section: .pluginOptions, actionType: "pluginString:\(item.key)" as AnyHashable, text: text, kind: .generic))
        }
    } else if plugin.hasSettings {
        entries.append(.header(id: id.count, section: .pluginOptions, text: isRu ? "НАСТРОЙКИ" : "SETTINGS", badge: nil))
        entries.append(.notice(id: id.count, section: .pluginOptions, text: isRu ? "Настройки этого плагина задаются в файле .plugin (create_settings). Редактор для других типов плагинов в разработке." : "Settings for this plugin are defined in the .plugin file (create_settings). Editor for other plugin types coming later."))
    }

    entries.append(.header(id: id.count, section: .info, text: isRu ? "ИНФОРМАЦИЯ" : "INFORMATION", badge: nil))
    entries.append(PluginSettingsEntry.notice(id: id.count, section: .info, text: "\(plugin.metadata.name)\n\(isRu ? "Версия" : "Version") \(plugin.metadata.version)\n\(plugin.metadata.author)\n\n\(plugin.metadata.description)"))
    return entries
}

public func PluginSettingsController(context: AccountContext, plugin: PluginInfo, onSave: @escaping () -> Void) -> ViewController {
    let reloadPromise = ValuePromise(true, ignoreRepeated: false)
    var backAction: (() -> Void)?
    var presentAlertImpl: ((String, String, String, @escaping (String) -> Void) -> Void)?
    let pluginId = plugin.metadata.id
    let host = PluginHost.shared

    let arguments = SGItemListArguments<SGBoolSetting, AnyHashable, AnyHashable, AnyHashable, AnyHashable>(
        context: context,
        setBoolValue: { _, _ in },
        updateSliderValue: { _, _ in },
        setOneFromManyValue: { _ in },
        openDisclosureLink: { _ in },
        action: { actionType in
            guard let s = actionType as? String else { return }
            if s == "toggleEnabled" {
                var plugins = loadInstalledPlugins()
                if let idx = plugins.firstIndex(where: { $0.metadata.id == pluginId }) {
                    plugins[idx].enabled.toggle()
                    saveInstalledPlugins(plugins)
                    reloadPromise.set(true)
                    onSave()
                }
            } else if s.hasPrefix("pluginBool:") {
                let key = String(s.dropFirst("pluginBool:".count))
                let current = host.getPluginSettingBool(pluginId: pluginId, key: key, default: false)
                host.setPluginSettingBool(pluginId: pluginId, key: key, value: !current)
                reloadPromise.set(true)
                onSave()
            } else if s.hasPrefix("pluginString:") {
                let key = String(s.dropFirst("pluginString:".count))
                let current = host.getPluginSetting(pluginId: pluginId, key: key) ?? ""
                let titleRu = userDisplayStringKeys.first(where: { $0.key == key })?.titleRu ?? key
                let titleEn = userDisplayStringKeys.first(where: { $0.key == key })?.titleEn ?? key
                let lang = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
                let title = lang == "ru" ? titleRu : titleEn
                presentAlertImpl?(key, title, current) { newValue in
                    host.setPluginSetting(pluginId: pluginId, key: key, value: newValue)
                    reloadPromise.set(true)
                    onSave()
                }
            }
        },
        searchInput: { _ in }
    )

    let signal = combineLatest(
        reloadPromise.get(),
        context.sharedContext.presentationData
    )
    |> map { _, presentationData -> (ItemListControllerState, (ItemListNodeState, SGItemListArguments<SGBoolSetting, AnyHashable, AnyHashable, AnyHashable, AnyHashable>)) in
        let plugins = loadInstalledPlugins()
        let currentPlugin = plugins.first(where: { $0.metadata.id == plugin.metadata.id }) ?? plugin
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(currentPlugin.metadata.name),
            leftNavigationButton: ItemListNavigationButton(content: .text(presentationData.strings.Common_Back), style: .regular, enabled: true, action: { backAction?() }),
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let entries = pluginSettingsEntries(presentationData: presentationData, plugin: currentPlugin)
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
    backAction = { [weak controller] in controller?.dismiss() }

    presentAlertImpl = { [weak controller] key, title, currentValue, completion in
        guard let c = controller else { return }
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = currentValue
            tf.placeholder = title
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
        }
        let okTitle = context.sharedContext.currentPresentationData.with { $0 }.strings.Common_OK
        let cancelTitle = context.sharedContext.currentPresentationData.with { $0 }.strings.Common_Cancel
        alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel))
        alert.addAction(UIAlertAction(title: okTitle, style: .default) { _ in
            let newValue = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            completion(newValue)
        })
        c.present(alert, animated: true)
    }

    return controller
}
