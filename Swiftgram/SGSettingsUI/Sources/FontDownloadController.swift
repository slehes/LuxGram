import SGSimpleSettings
import Foundation
import UIKit
import CoreText
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import AccountContext

/// Downloaded fonts directory name under Documents/LuxGramFonts/
private let kDownloadedFontsSubdir = "Downloaded"

/// Register all .ttf files in the downloaded fonts directory so they appear in the font picker.
public func registerAllDownloadedFonts() {
    guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
    let base = documents.appendingPathComponent("LuxGramFonts", isDirectory: true).appendingPathComponent(kDownloadedFontsSubdir, isDirectory: true)
    guard let contents = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { return }
    let ttfUrls = contents.filter { $0.pathExtension.lowercased() == "ttf" }
    if ttfUrls.isEmpty { return }
    CTFontManagerRegisterFontURLs(ttfUrls as CFArray, .process, true, nil)
}

/// Static list: (display name, .ttf URL). Google Fonts from GitHub raw.
private let kDownloadableFonts: [(name: String, url: String)] = [
    ("Roboto", "https://github.com/google/fonts/raw/main/apache/roboto/Roboto-Regular.ttf"),
    ("Roboto Condensed", "https://github.com/google/fonts/raw/main/apache/robotocondensed/RobotoCondensed-Regular.ttf"),
    ("Open Sans", "https://github.com/google/fonts/raw/main/apache/opensans/OpenSans-Regular.ttf"),
    ("Lato", "https://github.com/google/fonts/raw/main/ofl/lato/Lato-Regular.ttf"),
    ("Oswald", "https://github.com/google/fonts/raw/main/ofl/oswald/Oswald-Regular.ttf"),
    ("Source Sans 3", "https://github.com/google/fonts/raw/main/ofl/sourcesans3/SourceSans3-Regular.ttf"),
    ("Montserrat", "https://github.com/google/fonts/raw/main/ofl/montserrat/Montserrat-Regular.ttf"),
    ("Raleway", "https://github.com/google/fonts/raw/main/ofl/raleway/Raleway-Regular.ttf"),
    ("PT Sans", "https://github.com/google/fonts/raw/main/ofl/ptsans/PT_Sans-Regular.ttf"),
    ("Merriweather", "https://github.com/google/fonts/raw/main/ofl/merriweather/Merriweather-Regular.ttf"),
    ("Nunito", "https://github.com/google/fonts/raw/main/ofl/nunito/Nunito-Regular.ttf"),
    ("Fira Sans", "https://github.com/google/fonts/raw/main/ofl/firasans/FiraSans-Regular.ttf"),
    ("Ubuntu", "https://github.com/google/fonts/raw/main/ufl/ubuntu/Ubuntu-Regular.ttf"),
    ("Playfair Display", "https://github.com/google/fonts/raw/main/ofl/playfairdisplay/PlayfairDisplay-Regular.ttf"),
    ("Oxygen", "https://github.com/google/fonts/raw/main/ofl/oxygen/Oxygen-Regular.ttf"),
    ("Manrope", "https://github.com/google/fonts/raw/main/ofl/manrope/Manrope-Regular.ttf"),
    ("Inter", "https://github.com/google/fonts/raw/main/ofl/inter/Inter-Regular.ttf"),
    ("Poppins", "https://github.com/google/fonts/raw/main/ofl/poppins/Poppins-Regular.ttf"),
    ("Work Sans", "https://github.com/google/fonts/raw/main/ofl/worksans/WorkSans-Regular.ttf"),
    ("Rubik", "https://github.com/google/fonts/raw/main/ofl/rubik/Rubik-Regular.ttf"),
]

private enum FontDownloadEntry: ItemListNodeEntry {
    case search(entryId: Int, query: String)
    case font(entryId: Int, name: String, url: String, isDownloading: Bool, isDownloaded: Bool)

    var section: ItemListSectionId { 0 }
    var stableId: Int {
        switch self {
        case .search(let id, _): return id
        case .font(let id, _, _, _, _): return id
        }
    }
    var id: Int { stableId }

    static func == (lhs: FontDownloadEntry, rhs: FontDownloadEntry) -> Bool {
        switch (lhs, rhs) {
        case (.search(let id1, let q1), .search(let id2, let q2)): return id1 == id2 && q1 == q2
        case (.font(let id1, let n1, _, let d1, let i1), .font(let id2, let n2, _, let d2, let i2)): return id1 == id2 && n1 == n2 && d1 == d2 && i1 == i2
        default: return false
        }
    }
    static func < (lhs: FontDownloadEntry, rhs: FontDownloadEntry) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FontDownloadArguments
        switch self {
        case .search(_, let query):
            let placeholder = presentationData.strings.baseLanguageCode == "ru" ? "Поиск шрифта" : "Search font"
            return ItemListSingleLineInputItem(
                presentationData: presentationData,
                title: NSAttributedString(),
                text: query,
                placeholder: placeholder,
                returnKeyType: .search,
                spacing: 0,
                clearType: .always,
                sectionId: section,
                textUpdated: { args.updateSearch($0) },
                shouldUpdateText: { _ in true },
                action: {}
            )
        case .font(_, let name, let url, let isDownloading, let isDownloaded):
            let label: String
            if isDownloading {
                label = presentationData.strings.baseLanguageCode == "ru" ? "Загрузка…" : "Downloading…"
            } else if isDownloaded {
                label = presentationData.strings.baseLanguageCode == "ru" ? "Установлен" : "Installed"
            } else {
                label = ""
            }
            return ItemListDisclosureItem(
                presentationData: presentationData,
                title: name,
                enabled: !isDownloading,
                label: label,
                sectionId: section,
                style: .blocks,
                action: isDownloading ? nil : { args.download(name, url) }
            )
        }
    }
}

private struct FontDownloadArguments {
    let updateSearch: (String) -> Void
    let download: (String, String) -> Void
}

private struct FontDownloadState: Equatable {
    var searchQuery: String
    var downloadingNames: Set<String>
    var downloadedNames: Set<String>
}

public func FontDownloadController(context: AccountContext, onFontAdded: @escaping () -> Void) -> ViewController {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    var state = FontDownloadState(searchQuery: "", downloadingNames: [], downloadedNames: [])

    func downloadedFontsDirectory() -> URL? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let base = documents.appendingPathComponent("LuxGramFonts", isDirectory: true).appendingPathComponent(kDownloadedFontsSubdir, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    func isFontDownloaded(displayName: String) -> Bool {
        guard let dir = downloadedFontsDirectory() else { return false }
        let sanitized = displayName.replacingOccurrences(of: " ", with: "_")
        let path = dir.appendingPathComponent(sanitized + ".ttf").path
        return FileManager.default.fileExists(atPath: path)
    }

    let statePromise = ValuePromise<FontDownloadState>(state, ignoreRepeated: true)
    let updateState: ((String?, Set<String>?, Set<String>?) -> Void) = { query, downloading, downloaded in
        if let q = query { state.searchQuery = q }
        if let d = downloading { state.downloadingNames = d }
        if let d = downloaded { state.downloadedNames = d }
        statePromise.set(state)
    }

    let arguments = FontDownloadArguments(
        updateSearch: { updateState($0, nil, nil) },
        download: { name, urlString in
            updateState(nil, { var s = state.downloadingNames; s.insert(name); return s }(), nil)
            guard let url = URL(string: urlString), let dir = downloadedFontsDirectory() else {
                updateState(nil, { var s = state.downloadingNames; s.remove(name); return s }(), nil)
                return
            }
            let task = URLSession.shared.dataTask(with: url) { data, _, _ in
                DispatchQueue.main.async {
                    updateState(nil, { var s = state.downloadingNames; s.remove(name); return s }(), nil)
                    guard let data = data, !data.isEmpty else { return }
                    let sanitized = name.replacingOccurrences(of: " ", with: "_")
                    let file = dir.appendingPathComponent(sanitized + ".ttf")
                    do {
                        try data.write(to: file)
                        CTFontManagerRegisterFontURLs([file] as CFArray, .process, true, nil)
                        updateState(nil, nil, { var s = state.downloadedNames; s.insert(name); return s }())
                        onFontAdded()
                    } catch {}
                }
            }
            task.resume()
        }
    )

    let controllerState = ItemListControllerState(
        presentationData: ItemListPresentationData(presentationData),
        title: .text(presentationData.strings.baseLanguageCode == "ru" ? "Загрузить шрифт" : "Download font"),
        leftNavigationButton: nil,
        rightNavigationButton: nil,
        backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
    )

    let signal: Signal<(ItemListControllerState, (ItemListNodeState, FontDownloadArguments)), NoError> = statePromise.get()
        |> map { (s: FontDownloadState) -> (ItemListControllerState, (ItemListNodeState, FontDownloadArguments)) in
            var entries: [FontDownloadEntry] = []
            entries.append(.search(entryId: 0, query: s.searchQuery))
            let filtered = kDownloadableFonts.filter { s.searchQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(s.searchQuery) }
            for (idx, item) in filtered.enumerated() {
                let id = idx + 1
                let isDl = s.downloadingNames.contains(item.name)
                let isDone = s.downloadedNames.contains(item.name) || isFontDownloaded(displayName: item.name)
                entries.append(.font(entryId: id, name: item.name, url: item.url, isDownloading: isDl, isDownloaded: isDone))
            }
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
    return controller
}
