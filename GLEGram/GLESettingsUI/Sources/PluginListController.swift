// MARK: Swiftgram – Plugin list (like Active sites: icon, name, author, description, switch; Settings below)
import Foundation
import UIKit
import ObjectiveC
import UniformTypeIdentifiers
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import SGSimpleSettings
import AppBundle

private var documentPickerDelegateKey: UInt8 = 0

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

// Custom entries: .plugin plugins + .deb/.dylib tweaks.
private enum PluginListEntry: ItemListNodeEntry {
    case addHeader(id: Int, text: String)
    case addAction(id: Int, text: String)
    case addNotice(id: Int, text: String)
    case addDebAction(id: Int, text: String)
    case addDebNotice(id: Int, text: String)
    case listHeader(id: Int, text: String)
    case pluginRow(id: Int, plugin: PluginInfo)
    case pluginSettings(id: Int, pluginId: String, text: String)
    case pluginDelete(id: Int, pluginId: String, text: String)
    case emptyNotice(id: Int, text: String)
    case tweaksChannelLink(id: Int, text: String, url: String)
    case tweaksHeader(id: Int, text: String)
    case installLiveContainer(id: Int, text: String)
    case tweaksDylibHeader(id: Int, text: String)
    case tweakRow(id: Int, filename: String)
    case tweakDelete(id: Int, filename: String, text: String)
    case tweaksEmptyNotice(id: Int, text: String)
    
    var id: Int { stableId }
    
    var section: ItemListSectionId {
        switch self {
        case .addHeader, .addAction, .addNotice, .addDebAction, .addDebNotice: return 0
        case .listHeader, .pluginRow, .pluginSettings, .pluginDelete, .emptyNotice: return 1
        case .tweaksChannelLink, .tweaksHeader, .installLiveContainer, .tweaksDylibHeader, .tweakRow, .tweakDelete, .tweaksEmptyNotice: return 2
        }
    }
    
    var stableId: Int {
        switch self {
        case .addHeader(let id, _), .addAction(let id, _), .addNotice(let id, _), .addDebAction(let id, _), .addDebNotice(let id, _),
             .listHeader(let id, _), .pluginRow(let id, _), .pluginSettings(let id, _, _), .pluginDelete(let id, _, _), .emptyNotice(let id, _),
             .tweaksChannelLink(let id, _, _), .tweaksHeader(let id, _), .installLiveContainer(let id, _), .tweaksDylibHeader(let id, _), .tweakRow(let id, _), .tweakDelete(let id, _, _), .tweaksEmptyNotice(let id, _): return id
        }
    }
    
    static func < (lhs: PluginListEntry, rhs: PluginListEntry) -> Bool { lhs.stableId < rhs.stableId }
    
    static func == (lhs: PluginListEntry, rhs: PluginListEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.addHeader(a, t1), .addHeader(b, t2)), let (.addNotice(a, t1), .addNotice(b, t2)), let (.emptyNotice(a, t1), .emptyNotice(b, t2)): return a == b && t1 == t2
        case let (.addAction(a, t1), .addAction(b, t2)), let (.addDebAction(a, t1), .addDebAction(b, t2)), let (.addDebNotice(a, t1), .addDebNotice(b, t2)): return a == b && t1 == t2
        case let (.listHeader(a, t1), .listHeader(b, t2)), let (.tweaksHeader(a, t1), .tweaksHeader(b, t2)), let (.tweaksDylibHeader(a, t1), .tweaksDylibHeader(b, t2)): return a == b && t1 == t2
        case let (.tweaksChannelLink(a, t1, u1), .tweaksChannelLink(b, t2, u2)): return a == b && t1 == t2 && u1 == u2
        case let (.installLiveContainer(a, t1), .installLiveContainer(b, t2)): return a == b && t1 == t2
        case let (.pluginRow(a, p1), .pluginRow(b, p2)): return a == b && p1.metadata.id == p2.metadata.id && p1.enabled == p2.enabled
        case let (.pluginSettings(a, id1, t1), .pluginSettings(b, id2, t2)), let (.pluginDelete(a, id1, t1), .pluginDelete(b, id2, t2)): return a == b && id1 == id2 && t1 == t2
        case let (.tweakRow(a, f1), .tweakRow(b, f2)): return a == b && f1 == f2
        case let (.tweakDelete(a, f1, t1), .tweakDelete(b, f2, t2)): return a == b && f1 == f2 && t1 == t2
        case let (.tweaksEmptyNotice(a, t1), .tweaksEmptyNotice(b, t2)): return a == b && t1 == t2
        default: return false
        }
    }
    
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! PluginListArguments
        switch self {
        case .addHeader(_, let text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case .addAction(_, let text):
            return ItemListActionItem(presentationData: presentationData, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: { args.addPlugin() })
        case .addNotice(_, let text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case .addDebAction(_, let text):
            return ItemListActionItem(presentationData: presentationData, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: { args.addDeb() })
        case .addDebNotice(_, let text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case .listHeader(_, let text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case .pluginRow(_, let plugin):
            let icon = args.iconResolver(plugin.metadata.iconRef)
            return ItemListPluginRowItem(presentationData: presentationData, plugin: plugin, icon: icon, sectionId: self.section, toggle: { value in args.toggle(plugin.metadata.id, value) }, action: nil)
        case .pluginSettings(_, let pluginId, let text):
            return ItemListDisclosureItem(presentationData: presentationData, title: text, label: "", sectionId: self.section, style: .blocks, action: { args.openSettings(pluginId) })
        case .pluginDelete(_, let pluginId, let text):
            return ItemListActionItem(presentationData: presentationData, title: text, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: { args.deletePlugin(pluginId) })
        case .emptyNotice(_, let text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case .tweaksChannelLink(_, let text, let url):
            return ItemListDisclosureItem(presentationData: presentationData, title: text, label: "", sectionId: self.section, style: .blocks, action: { args.openTweaksChannel(url) })
        case .tweaksHeader(_, let text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case .installLiveContainer(_, let text):
            return ItemListActionItem(presentationData: presentationData, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: { args.openLiveContainer() })
        case .tweaksDylibHeader(_, let text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case .tweakRow(_, let filename):
            return ItemListDisclosureItem(presentationData: presentationData, title: filename, label: "", sectionId: self.section, style: .blocks, action: nil)
        case .tweakDelete(_, let filename, let text):
            return ItemListActionItem(presentationData: presentationData, title: text, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: { args.removeTweak(filename) })
        case .tweaksEmptyNotice(_, let text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private final class PluginListArguments {
    let toggle: (String, Bool) -> Void
    let openSettings: (String) -> Void
    let deletePlugin: (String) -> Void
    let addPlugin: () -> Void
    let addDeb: () -> Void
    let openTweaksChannel: (String) -> Void
    let openLiveContainer: () -> Void
    let removeTweak: (String) -> Void
    let iconResolver: (String?) -> UIImage?
    
    init(toggle: @escaping (String, Bool) -> Void, openSettings: @escaping (String) -> Void, deletePlugin: @escaping (String) -> Void, addPlugin: @escaping () -> Void, addDeb: @escaping () -> Void, openTweaksChannel: @escaping (String) -> Void, openLiveContainer: @escaping () -> Void, removeTweak: @escaping (String) -> Void, iconResolver: @escaping (String?) -> UIImage?) {
        self.toggle = toggle
        self.openSettings = openSettings
        self.deletePlugin = deletePlugin
        self.addPlugin = addPlugin
        self.addDeb = addDeb
        self.openTweaksChannel = openTweaksChannel
        self.openLiveContainer = openLiveContainer
        self.removeTweak = removeTweak
        self.iconResolver = iconResolver
    }
}

private func pluginListEntries(presentationData: PresentationData, plugins: [PluginInfo], tweakFilenames: [String]) -> [PluginListEntry] {
    let lang = presentationData.strings.baseLanguageCode
    var entries: [PluginListEntry] = []
    var id = 0
    entries.append(.addHeader(id: id, text: lang == "ru" ? "ДОБАВИТЬ ПЛАГИН" : "ADD PLUGIN"))
    id += 1
    entries.append(.addAction(id: id, text: lang == "ru" ? "Выбрать файл .plugin" : "Select .plugin file"))
    id += 1
    entries.append(.addNotice(id: id, text: lang == "ru" ? "Файлы плагинов .plugin можно устанавливать здесь." : "Plugin .plugin files can be installed here."))
    id += 1
    entries.append(.addDebAction(id: id, text: lang == "ru" ? "Установить пакет .deb (твики)" : "Install .deb package (tweaks)"))
    id += 1
    entries.append(.addDebNotice(id: id, text: lang == "ru" ? "Пакеты .deb (Cydia/Sileo) — из них извлекаются .dylib и устанавливаются. Перезапустите приложение после установки." : ".deb packages (Cydia/Sileo): .dylib files are extracted and installed. Restart the app after installing."))
    id += 1
    entries.append(.listHeader(id: id, text: lang == "ru" ? "УСТАНОВЛЕННЫЕ ПЛАГИНЫ" : "INSTALLED PLUGINS"))
    id += 1
    for plugin in plugins {
        let meta = plugin.metadata
        entries.append(.pluginRow(id: id, plugin: plugin))
        id += 1
        if plugin.hasSettings {
            entries.append(.pluginSettings(id: id, pluginId: meta.id, text: lang == "ru" ? "Настройки" : "Settings"))
            id += 1
        }
        entries.append(.pluginDelete(id: id, pluginId: meta.id, text: lang == "ru" ? "Удалить" : "Remove"))
        id += 1
    }
    if plugins.isEmpty {
        entries.append(.emptyNotice(id: id, text: lang == "ru" ? "Нет установленных плагинов." : "No installed plugins."))
    }
    id += 1
    entries.append(.tweaksChannelLink(id: id, text: lang == "ru" ? "Скачать твики (канал)" : "Download tweaks (channel)", url: "https://t.me/luxgramiostweaks"))
    id += 1
    entries.append(.tweaksHeader(id: id, text: lang == "ru" ? "УСТАНОВИТЬ В" : "INSTALL IN"))
    id += 1
    entries.append(.installLiveContainer(id: id, text: lang == "ru" ? "Установить в LiveContainer" : "Install in LiveContainer"))
    id += 1
    entries.append(.tweaksDylibHeader(id: id, text: lang == "ru" ? "УСТАНОВЛЕННЫЕ ТВИКИ (.dylib)" : "INSTALLED TWEAKS (.dylib)"))
    id += 1
    for filename in tweakFilenames {
        entries.append(.tweakRow(id: id, filename: filename))
        id += 1
        entries.append(.tweakDelete(id: id, filename: filename, text: lang == "ru" ? "Удалить" : "Remove"))
        id += 1
    }
    if tweakFilenames.isEmpty {
        entries.append(.tweaksEmptyNotice(id: id, text: lang == "ru" ? "Нет установленных твиков. Установите .deb." : "No installed tweaks. Install a .deb package."))
    }
    return entries
}

public func PluginListController(context: AccountContext, onPluginsChanged: @escaping () -> Void) -> ViewController {
    let reloadPromise = ValuePromise(true, ignoreRepeated: false)
    var presentDocumentPicker: (() -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?
    var backAction: (() -> Void)?
    
    var presentDebPicker: (() -> Void)?
    var openLiveContainerImpl: (() -> Void)?
    var showDebResultAlertImpl: ((String, String) -> Void)?
    let arguments = PluginListArguments(
        toggle: { pluginId, value in
            var plugins = loadInstalledPlugins()
            if let idx = plugins.firstIndex(where: { $0.metadata.id == pluginId }) {
                plugins[idx].enabled = value
                saveInstalledPlugins(plugins)
                reloadPromise.set(true)
                onPluginsChanged()
            }
        },
        openSettings: { pluginId in
            let plugins = loadInstalledPlugins()
            guard let plugin = plugins.first(where: { $0.metadata.id == pluginId }) else { return }
            let settingsController = PluginSettingsController(context: context, plugin: plugin, onSave: {
                reloadPromise.set(true)
                onPluginsChanged()
            })
            pushControllerImpl?(settingsController)
        },
        deletePlugin: { pluginId in
            var plugins = loadInstalledPlugins()
            plugins.removeAll { $0.metadata.id == pluginId }
            saveInstalledPlugins(plugins)
            reloadPromise.set(true)
            onPluginsChanged()
        },
        addPlugin: { presentDocumentPicker?() },
        addDeb: { presentDebPicker?() },
        openTweaksChannel: { url in
            if let u = URL(string: url) { UIApplication.shared.open(u) }
        },
        openLiveContainer: { openLiveContainerImpl?() },
        removeTweak: { filename in
            try? TweakLoader.removeTweak(filename: filename)
            reloadPromise.set(true)
            onPluginsChanged()
        },
        iconResolver: { iconRef in
            guard let ref = iconRef, !ref.isEmpty else { return nil }
            if let img = UIImage(bundleImageName: ref) { return img }
            return UIImage(bundleImageName: "glePlugins/1")
        }
    )
    
    let signal = combineLatest(reloadPromise.get(), context.sharedContext.presentationData)
    |> map { _, presentationData -> (ItemListControllerState, (ItemListNodeState, PluginListArguments)) in
        let plugins = loadInstalledPlugins()
        let tweakFilenames = TweakLoader.installedTweakFilenames()
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(presentationData.strings.baseLanguageCode == "ru" ? "Плагины" : "Plugins"),
            leftNavigationButton: ItemListNavigationButton(content: .text(presentationData.strings.Common_Back), style: .regular, enabled: true, action: { backAction?() }),
            rightNavigationButton: ItemListNavigationButton(content: .text("+"), style: .bold, enabled: true, action: { presentDocumentPicker?() }),
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let entries = pluginListEntries(presentationData: presentationData, plugins: plugins, tweakFilenames: tweakFilenames)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, ensureVisibleItemTag: nil, initialScrollToItem: nil)
        return (controllerState, (listState, arguments))
    }
    
    let controller = ItemListController(context: context, state: signal)
    backAction = { [weak controller] in controller?.dismiss() }
    
    presentDocumentPicker = { [weak controller] in
        guard let controller = controller else { return }
        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            let pluginType = UTType(filenameExtension: "plugin") ?? .plainText
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [pluginType], asCopy: true)
        } else {
            picker = UIDocumentPickerViewController(documentTypes: ["public.plain-text", "public.data"], in: .import)
        }
        let delegate = PluginDocumentPickerDelegate(
            context: context,
            onPick: { url in
                _ = url.startAccessingSecurityScopedResource()
                defer { url.stopAccessingSecurityScopedResource() }
                guard let content = try? String(contentsOf: url, encoding: .utf8),
                      let metadata = currentPluginRuntime.parseMetadata(content: content) else { return }
                let hasSettings = currentPluginRuntime.hasCreateSettings(content: content)
                let fileManager = FileManager.default
                guard let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
                let pluginsDir = supportURL.appendingPathComponent("Plugins", isDirectory: true)
                try? fileManager.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
                let destURL = pluginsDir.appendingPathComponent("\(metadata.id).plugin")
                try? fileManager.removeItem(at: destURL)
                try? fileManager.copyItem(at: url, to: destURL)
                var plugins = loadInstalledPlugins()
                plugins.append(PluginInfo(metadata: metadata, path: destURL.path, enabled: true, hasSettings: hasSettings))
                saveInstalledPlugins(plugins)
                reloadPromise.set(true)
                onPluginsChanged()
            }
        )
        picker.delegate = delegate
        objc_setAssociatedObject(picker, &documentPickerDelegateKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        controller.present(picker, animated: true)
    }
    presentDebPicker = { [weak controller] in
        guard let controller = controller else { return }
        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            let debType = UTType(filenameExtension: "deb") ?? .data
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [debType], asCopy: true)
        } else {
            picker = UIDocumentPickerViewController(documentTypes: ["public.data"], in: .import)
        }
        let delegate = PluginDocumentPickerDelegate(context: context, onPick: { url in
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            let lang = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
            do {
                let tweaksDir = TweakLoader.ensureTweaksDirectory()
                let result = try DebExtractor.installDeb(from: url, tweaksDirectory: tweaksDir)
                let names = result.installedDylibs.joined(separator: ", ")
                let pkg = result.packageName ?? "Tweak"
                let ver = result.packageVersion.map { " \($0)" } ?? ""
                showDebResultAlertImpl?(lang == "ru" ? "Установлено" : "Installed", "\(pkg)\(ver): \(names)\n\n" + (lang == "ru" ? "Перезапустите приложение." : "Restart the app."))
                reloadPromise.set(true)
                onPluginsChanged()
            } catch {
                showDebResultAlertImpl?(lang == "ru" ? "Ошибка" : "Error", error.localizedDescription)
            }
        })
        picker.delegate = delegate
        objc_setAssociatedObject(picker, &documentPickerDelegateKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        controller.present(picker, animated: true)
    }
    pushControllerImpl = { [weak controller] vc in controller?.push(vc) }
    let showNoAppAlert: () -> Void = { [weak controller] in
        guard let ctrl = controller, let window = ctrl.view.window, let root = window.rootViewController else { return }
        let lang = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
        let msg = lang == "ru" ? "Нет нужного приложения" : "No required app"
        let alert = UIAlertController(title: nil, message: msg, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(alert, animated: true)
    }
    openLiveContainerImpl = {
        guard let url = URL(string: "livecontainer://") else { return }
        UIApplication.shared.open(url, options: [:]) { opened in if !opened { showNoAppAlert() } }
    }
    showDebResultAlertImpl = { [weak controller] title, message in
        guard let controller = controller, let window = controller.view.window, let root = window.rootViewController else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(alert, animated: true)
    }
    
    return controller
}

private final class PluginDocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    let context: AccountContext
    let onPick: (URL) -> Void
    init(context: AccountContext, onPick: @escaping (URL) -> Void) {
        self.context = context
        self.onPick = onPick
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        onPick(url)
    }
}
