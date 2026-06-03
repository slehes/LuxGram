import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import SGSimpleSettings

// MARK: - State

private final class PluginCodeEditorStateHolder {
    var name: String
    var code: String
    init(name: String, code: String) {
        self.name = name
        self.code = code
    }
}

private struct PluginCodeEditorState: Equatable {
    var name: String
    var code: String
}

// MARK: - Entries

private enum PluginCodeEditorEntry: ItemListNodeEntry {
    case nameInput(id: Int, text: String, placeholder: String)
    case codeInput(id: Int, text: String, placeholder: String)
    case notice(id: Int, text: String)

    var section: ItemListSectionId {
        switch self {
        case .nameInput: return 0
        case .codeInput: return 1
        case .notice: return 2
        }
    }

    var stableId: Int {
        switch self {
        case .nameInput(let id, _, _): return id
        case .codeInput(let id, _, _): return id
        case .notice(let id, _): return id
        }
    }

    static func == (lhs: PluginCodeEditorEntry, rhs: PluginCodeEditorEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.nameInput(a, t1, p1), .nameInput(b, t2, p2)): return a == b && t1 == t2 && p1 == p2
        case let (.codeInput(a, t1, p1), .codeInput(b, t2, p2)): return a == b && t1 == t2 && p1 == p2
        case let (.notice(a, t1), .notice(b, t2)): return a == b && t1 == t2
        default: return false
        }
    }

    static func < (lhs: PluginCodeEditorEntry, rhs: PluginCodeEditorEntry) -> Bool {
        lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! PluginCodeEditorArguments
        switch self {
        case .nameInput(_, let text, let placeholder):
            return ItemListSingleLineInputItem(
                presentationData: presentationData,
                title: NSAttributedString(),
                text: text,
                placeholder: placeholder,
                sectionId: section,
                textUpdated: { newText in args.updatedName(newText) },
                action: {}
            )
        case .codeInput(_, let text, let placeholder):
            return ItemListMultilineInputItem(
                presentationData: presentationData,
                text: text,
                placeholder: placeholder,
                maxLength: nil,
                sectionId: section,
                style: .blocks,
                textUpdated: { newText in args.updatedCode(newText) },
                updatedFocus: nil,
                tag: nil,
                action: nil,
                inlineAction: nil
            )
        case .notice(_, let text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        }
    }
}

// MARK: - Arguments

private final class PluginCodeEditorArguments {
    var updatedName: (String) -> Void = { _ in }
    var updatedCode: (String) -> Void = { _ in }
}

private final class PluginCodeEditorNavActions {
    var cancel: (() -> Void)?
    var done: (() -> Void)?
}

// MARK: - Entries builder

private func pluginCodeEditorEntries(state: PluginCodeEditorState, presentationData: PresentationData) -> [PluginCodeEditorEntry] {
    let lang = presentationData.strings.baseLanguageCode
    var entries: [PluginCodeEditorEntry] = []
    entries.append(.nameInput(id: 0, text: state.name, placeholder: lang == "ru" ? "Имя плагина" : "Plugin name"))
    entries.append(.codeInput(id: 1, text: state.code, placeholder: lang == "ru" ? "JavaScript код..." : "JavaScript code..."))
    let noticeText = lang == "ru"
        ? "Используйте LuxGram.ui, LuxGram.chat, LuxGram.compose, LuxGram.messageActions, LuxGram.intercept, LuxGram.network, LuxGram.settings, LuxGram.events API."
        : "Use LuxGram.ui, LuxGram.chat, LuxGram.compose, LuxGram.messageActions, LuxGram.intercept, LuxGram.network, LuxGram.settings, LuxGram.events API."
    entries.append(.notice(id: 2, text: noticeText))
    return entries
}

// MARK: - Controller

public func pluginCodeEditorController(context: AccountContext, existingPlugin: PluginInfo?, initialCode: String, onSave: @escaping (PluginInfo) -> Void) -> ViewController {
    let initialName = existingPlugin?.metadata.name ?? ""
    let stateHolder = PluginCodeEditorStateHolder(name: initialName, code: initialCode)
    let navActions = PluginCodeEditorNavActions()
    let statePromise = ValuePromise(PluginCodeEditorState(name: initialName, code: initialCode), ignoreRepeated: true)
    let arguments = PluginCodeEditorArguments()

    arguments.updatedName = { newName in
        stateHolder.name = newName
        statePromise.set(PluginCodeEditorState(name: newName, code: stateHolder.code))
    }
    arguments.updatedCode = { newCode in
        stateHolder.code = newCode
        statePromise.set(PluginCodeEditorState(name: stateHolder.name, code: newCode))
    }

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, PluginCodeEditorArguments)) in
        let lang = presentationData.strings.baseLanguageCode
        let title = existingPlugin != nil
            ? (lang == "ru" ? "Редактор" : "Editor")
            : (lang == "ru" ? "Новый плагин" : "New Plugin")
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(title),
            leftNavigationButton: ItemListNavigationButton(content: .text(presentationData.strings.Common_Cancel), style: .regular, enabled: true, action: { navActions.cancel?() }),
            rightNavigationButton: ItemListNavigationButton(content: .text(lang == "ru" ? "Сохранить" : "Save"), style: .bold, enabled: !state.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, action: { navActions.done?() }),
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let entries = pluginCodeEditorEntries(state: state, presentationData: presentationData)
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

    navActions.cancel = { [weak controller] in
        controller?.dismiss()
    }

    navActions.done = { [weak controller] in
        let code = stateHolder.code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }

        // Parse metadata from code
        var metadata: PluginMetadata
        if let parsed = PluginMetadataParser.parse(content: code) {
            metadata = parsed
        } else {
            let name = stateHolder.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let safeName = name.isEmpty ? "Untitled Plugin" : name
            let safeId = existingPlugin?.metadata.id ?? safeName.lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .filter { $0.isLetter || $0.isNumber || $0 == "-" }
            let id = safeId.isEmpty ? "plugin-\(UUID().uuidString.prefix(8))" : safeId
            metadata = PluginMetadata(id: id, name: safeName, description: "", version: "1.0", author: "")
        }

        // If editing, keep the same ID
        if let existing = existingPlugin {
            metadata = PluginMetadata(
                id: existing.metadata.id,
                name: metadata.name,
                description: metadata.description,
                version: metadata.version,
                author: metadata.author,
                iconRef: metadata.iconRef,
                minVersion: metadata.minVersion,
                hasUserDisplay: metadata.hasUserDisplay
            )
        }

        // Write file
        let fileManager = FileManager.default
        guard let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let pluginsDir = supportURL.appendingPathComponent("Plugins", isDirectory: true)
        try? fileManager.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
        let destURL = pluginsDir.appendingPathComponent("\(metadata.id).js")
        try? code.write(to: destURL, atomically: true, encoding: .utf8)

        // Update installed list
        let pluginInfo = PluginInfo(metadata: metadata, path: destURL.path, enabled: true, hasSettings: false)
        var plugins: [PluginInfo]
        if let data = SGSimpleSettings.shared.installedPluginsJson.data(using: .utf8),
           let existing = try? JSONDecoder().decode([PluginInfo].self, from: data) {
            plugins = existing
        } else {
            plugins = []
        }
        plugins.removeAll { $0.metadata.id == metadata.id }
        plugins.append(pluginInfo)
        if let data = try? JSONEncoder().encode(plugins),
           let json = String(data: data, encoding: .utf8) {
            SGSimpleSettings.shared.installedPluginsJson = json
            SGSimpleSettings.shared.synchronizeShared()
        }

        // Reload plugins
        PluginRunner.install()
        onSave(pluginInfo)
        controller?.dismiss()
    }

    return controller
}
