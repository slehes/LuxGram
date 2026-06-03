import SGSimpleSettings
import Foundation
import UIKit
import CoreText
import CoreGraphics
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import AccountContext

/// Bundled default fonts shown at the top of the picker (display name, bundle filename without extension).
private let bundledDefaultFonts: [(displayName: String, fileName: String)] = [
    (displayName: "Minecraft Default Bold", fileName: "MinecraftDefault-Bold-2"),
]

/// Registers a .ttf from the given bundle if present and returns its PostScript name, or nil.
private func registerBundledFont(bundle: Bundle, fileName: String) -> String? {
    guard let path = bundle.path(forResource: fileName, ofType: "ttf") else {
        return nil
    }
    let url = URL(fileURLWithPath: path)
    guard let provider = CGDataProvider(url: url as CFURL),
          let cgFont = CGFont(provider),
          let name = cgFont.postScriptName as String?, !name.isEmpty else {
        return nil
    }
    CTFontManagerRegisterFontURLs([url] as CFArray, .process, true, nil)
    return name
}

public enum FontReplacementPickerMode {
    case main
    case bold
}

private struct FontReplacementPickerArguments {
    let selectFont: (String) -> Void
    let dismiss: () -> Void
}

private struct FontReplacementPickerEntry: ItemListNodeEntry {
    let entryId: Int
    let fontName: String
    let displayTitle: String
    
    var section: ItemListSectionId { 0 }
    var stableId: Int { entryId }
    var id: Int { entryId }
    
    static func == (lhs: FontReplacementPickerEntry, rhs: FontReplacementPickerEntry) -> Bool {
        lhs.entryId == rhs.entryId && lhs.fontName == rhs.fontName
    }
    static func < (lhs: FontReplacementPickerEntry, rhs: FontReplacementPickerEntry) -> Bool {
        lhs.entryId < rhs.entryId
    }
    
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FontReplacementPickerArguments
        let fontSize = presentationData.fontSize.itemListBaseFontSize
        let textColor = presentationData.theme.list.itemAccentColor
        let attributedTitle: NSAttributedString?
        if fontName.isEmpty {
            attributedTitle = nil
        } else if let font = UIFont(name: fontName, size: fontSize) {
            attributedTitle = NSAttributedString(string: displayTitle, font: font, textColor: textColor)
        } else {
            attributedTitle = nil
        }
        return ItemListDisclosureItem(
            presentationData: presentationData,
            title: displayTitle,
            attributedTitle: attributedTitle,
            label: "",
            sectionId: section,
            style: .blocks,
            disclosureStyle: .none,
            action: {
                args.selectFont(self.fontName)
                args.dismiss()
            }
        )
    }
}

public func FontReplacementPickerController(context: AccountContext, mode: FontReplacementPickerMode, onSave: @escaping () -> Void) -> ViewController {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    var dismissImpl: (() -> Void)?
    
    // Re-register downloaded fonts so they appear in the list
    registerAllDownloadedFonts()
    
    let (fontNames, bundledDisplayNames): ([String], [String: String]) = {
        var list: [String] = []
        var bundledMap: [String: String] = [:]
        for (displayName, fileName) in bundledDefaultFonts {
            if let postScriptName = registerBundledFont(bundle: .main, fileName: fileName), !list.contains(postScriptName) {
                list.append(postScriptName)
                bundledMap[postScriptName] = displayName
            }
        }
        for family in UIFont.familyNames.sorted() {
            for name in UIFont.fontNames(forFamilyName: family).sorted() {
                if !list.contains(name) {
                    list.append(name)
                }
            }
        }
        return (list.sorted(), bundledMap)
    }()
    
    let selectFont: (String) -> Void = { name in
        switch mode {
        case .main:
            SGSimpleSettings.shared.fontReplacementName = name
            SGSimpleSettings.shared.fontReplacementFilePath = "" // only "Import from file" sets path
        case .bold:
            SGSimpleSettings.shared.fontReplacementBoldName = name
            SGSimpleSettings.shared.fontReplacementBoldFilePath = ""
        }
        onSave()
        dismissImpl?()
    }
    
    let arguments = FontReplacementPickerArguments(
        selectFont: selectFont,
        dismiss: { dismissImpl?() }
    )
    
    var entries: [FontReplacementPickerEntry] = []
    let systemTitle = presentationData.strings.baseLanguageCode == "ru" ? "Системный" : "System"
    let autoTitle = presentationData.strings.baseLanguageCode == "ru" ? "Авто" : "Auto"
    entries.append(FontReplacementPickerEntry(entryId: 0, fontName: "", displayTitle: mode == .main ? systemTitle : autoTitle))
    for (idx, name) in fontNames.enumerated() {
        let displayTitle = bundledDisplayNames[name] ?? name
        entries.append(FontReplacementPickerEntry(entryId: idx + 1, fontName: name, displayTitle: displayTitle))
    }
    
    let controllerState = ItemListControllerState(
        presentationData: ItemListPresentationData(presentationData),
        title: .text(mode == .main ? (presentationData.strings.baseLanguageCode == "ru" ? "Шрифт" : "Font") : (presentationData.strings.baseLanguageCode == "ru" ? "Жирный шрифт" : "Bold font")),
        leftNavigationButton: nil,
        rightNavigationButton: nil,
        backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
    )
    
    let listState = ItemListNodeState(
        presentationData: ItemListPresentationData(presentationData),
        entries: entries,
        style: .blocks,
        ensureVisibleItemTag: nil,
        initialScrollToItem: nil
    )
    
    let signal: Signal<(ItemListControllerState, (ItemListNodeState, FontReplacementPickerArguments)), NoError> = .single((controllerState, (listState, arguments)))
    
    let controller = ItemListController(context: context, state: signal)
    dismissImpl = { [weak controller] in
        controller?.dismiss()
    }
    return controller
}
