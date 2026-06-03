import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import SGSimpleSettings
import AVFoundation
import ObjectiveC
import UniformTypeIdentifiers

private var profileCoverImagePickerDelegateKey: UInt8 = 0
private var profileCoverVideoPickerDelegateKey: UInt8 = 0
private var profileCoverDocumentPickerDelegateKey: UInt8 = 0

private let profileCoverSubdirectory = "ProfileCover"
private let profileCoverPhotoName = "cover.jpg"
private let profileCoverVideoName = "cover.mov"

/// Post when profile cover is saved so the profile screen can refresh the cover.
public extension Notification.Name {
    static let SGProfileCoverDidChange = Notification.Name("SGProfileCoverDidChange")
}

private func profileCoverDirectoryURL() -> URL {
    let support: URL
    if #available(iOS 16.0, *) {
        support = URL.applicationSupportDirectory
    } else {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support not available")
        }
        support = dir
    }
    return support.appendingPathComponent(profileCoverSubdirectory, isDirectory: true)
}

private func saveProfileCoverPhoto(from image: UIImage) throws -> String {
    let fm = FileManager.default
    let dir = profileCoverDirectoryURL()
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent(profileCoverPhotoName)
    try? fm.removeItem(at: url)
    guard let data = image.jpegData(compressionQuality: 0.85) else { throw NSError(domain: "ProfileCover", code: 1, userInfo: nil) }
    try data.write(to: url)
    return url.path
}

private func saveProfileCoverVideo(from sourceURL: URL) throws -> String {
    let fm = FileManager.default
    let dir = profileCoverDirectoryURL()
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let dest = dir.appendingPathComponent(profileCoverVideoName)
    try? fm.removeItem(at: dest)
    try fm.copyItem(at: sourceURL, to: dest)
    return dest.path
}

private func removeProfileCoverMedia() {
    let fm = FileManager.default
    let dir = profileCoverDirectoryURL()
    try? fm.removeItem(at: dir.appendingPathComponent(profileCoverPhotoName))
    try? fm.removeItem(at: dir.appendingPathComponent(profileCoverVideoName))
}

private final class ProfileCoverPreviewItem: ListViewItem, ItemListItem {
    let presentationData: ItemListPresentationData
    let sectionId: ItemListSectionId
    let coverPath: String
    let isVideo: Bool

    init(presentationData: ItemListPresentationData, sectionId: ItemListSectionId, coverPath: String, isVideo: Bool) {
        self.presentationData = presentationData
        self.sectionId = sectionId
        self.coverPath = coverPath
        self.isVideo = isVideo
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = ProfileCoverPreviewItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            Queue.mainQueue().async {
                completion(node, { return (nil, { _ in apply(.None) }) })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            guard let nodeValue = node() as? ProfileCoverPreviewItemNode else { return completion(ListViewItemNodeLayout(contentSize: .zero, insets: .zero), { _ in }) }
            let makeLayout = nodeValue.asyncLayout()
            async {
                let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
                Queue.mainQueue().async {
                    completion(layout, { _ in apply(animation) })
                }
            }
        }
    }

    var selectable: Bool { false }
    static func == (lhs: ProfileCoverPreviewItem, rhs: ProfileCoverPreviewItem) -> Bool {
        lhs.coverPath == rhs.coverPath && lhs.isVideo == rhs.isVideo && lhs.sectionId == rhs.sectionId
    }
}

private final class ProfileCoverPreviewItemNode: ListViewItemNode {
    private let backgroundNode: ASDisplayNode
    private let imageNode: ASImageNode
    private let placeholderLabel: ImmediateTextNode
    private var item: ProfileCoverPreviewItem?

    init() {
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true
        self.imageNode = ASImageNode()
        self.imageNode.contentMode = .scaleAspectFill
        self.imageNode.clipsToBounds = true
        self.placeholderLabel = ImmediateTextNode()
        super.init(layerBacked: false)
        addSubnode(backgroundNode)
        addSubnode(imageNode)
        addSubnode(placeholderLabel)
    }

    func asyncLayout() -> (ProfileCoverPreviewItem, ListViewItemLayoutParams, ItemListNeighbors) -> (ListViewItemNodeLayout, (ListViewItemUpdateAnimation) -> Void) {
        return { item, params, neighbors in
            let height: CGFloat = 180.0
            let contentSize = CGSize(width: params.width, height: height)
            let insets = itemListNeighborsGroupedInsets(neighbors, params)
            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: insets)

            return (layout, { [weak self] animation in
                guard let self else { return }
                self.item = item
                self.backgroundNode.backgroundColor = item.presentationData.theme.list.itemBlocksBackgroundColor
                self.backgroundNode.frame = CGRect(origin: .zero, size: contentSize)
                self.imageNode.frame = CGRect(x: params.leftInset, y: 0, width: params.width - params.leftInset - params.rightInset, height: height)
                self.imageNode.isHidden = item.coverPath.isEmpty

                if !item.coverPath.isEmpty {
                    if item.isVideo {
                        self.loadVideoThumbnail(path: item.coverPath)
                    } else {
                        self.imageNode.image = UIImage(contentsOfFile: item.coverPath)
                    }
                } else {
                    self.imageNode.image = nil
                    self.placeholderLabel.attributedText = NSAttributedString(string: item.presentationData.strings.baseLanguageCode == "ru" ? "Обложка не выбрана" : "No cover selected", font: Font.regular(15), textColor: item.presentationData.theme.list.itemSecondaryTextColor)
                    let labelSize = self.placeholderLabel.updateLayout(CGSize(width: params.width - 32, height: 60))
                    self.placeholderLabel.frame = CGRect(x: (params.width - labelSize.width) / 2, y: (height - labelSize.height) / 2, width: labelSize.width, height: labelSize.height)
                    self.placeholderLabel.isHidden = false
                }
                self.placeholderLabel.isHidden = !item.coverPath.isEmpty
            })
        }
    }

    private func loadVideoThumbnail(path: String) {
        let url = URL(fileURLWithPath: path)
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)
        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: .zero)]) { [weak self] _, cgImage, _, _, _ in
            Queue.mainQueue().async {
                self?.imageNode.image = cgImage.flatMap { UIImage(cgImage: $0) }
            }
        }
    }
}

private enum ProfileCoverEntry: ItemListNodeEntry {
    case previewHeader(id: Int, text: String)
    case preview(id: Int, path: String, isVideo: Bool)
    case mediaHeader(id: Int, text: String)
    case uploadPhoto(id: Int, text: String)
    case setVideo(id: Int, text: String)
    case uploadFromFiles(id: Int, text: String)
    case deleteMedia(id: Int, text: String)

    var id: Int { stableId }
    var section: ItemListSectionId {
        switch self {
        case .previewHeader, .preview: return 0
        default: return 1
        }
    }
    var stableId: Int {
        switch self {
        case .previewHeader(let i, _), .preview(let i, _, _), .mediaHeader(let i, _), .uploadPhoto(let i, _), .setVideo(let i, _), .uploadFromFiles(let i, _), .deleteMedia(let i, _): return i
        }
    }
    static func < (lhs: ProfileCoverEntry, rhs: ProfileCoverEntry) -> Bool { lhs.stableId < rhs.stableId }
    static func == (lhs: ProfileCoverEntry, rhs: ProfileCoverEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.previewHeader(a, t1), .previewHeader(b, t2)): return a == b && t1 == t2
        case let (.preview(a, p1, v1), .preview(b, p2, v2)): return a == b && p1 == p2 && v1 == v2
        case let (.mediaHeader(a, t1), .mediaHeader(b, t2)): return a == b && t1 == t2
        case let (.uploadPhoto(a, t1), .uploadPhoto(b, t2)): return a == b && t1 == t2
        case let (.setVideo(a, t1), .setVideo(b, t2)): return a == b && t1 == t2
        case let (.uploadFromFiles(a, t1), .uploadFromFiles(b, t2)): return a == b && t1 == t2
        case let (.deleteMedia(a, t1), .deleteMedia(b, t2)): return a == b && t1 == t2
        default: return false
        }
    }
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! ProfileCoverArguments
        switch self {
        case .previewHeader(_, let text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case .preview(_, let path, let isVideo):
            return ProfileCoverPreviewItem(presentationData: presentationData, sectionId: self.section, coverPath: path, isVideo: isVideo)
        case .mediaHeader(_, let text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case .uploadPhoto(_, let text):
            return ItemListActionItem(presentationData: presentationData, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: { args.uploadPhoto() })
        case .setVideo(_, let text):
            return ItemListActionItem(presentationData: presentationData, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: { args.setVideo() })
        case .uploadFromFiles(_, let text):
            return ItemListActionItem(presentationData: presentationData, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: { args.uploadFromFiles() })
        case .deleteMedia(_, let text):
            return ItemListActionItem(presentationData: presentationData, title: text, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: { args.deleteMedia() })
        }
    }
}

private final class ProfileCoverArguments {
    let uploadPhoto: () -> Void
    let setVideo: () -> Void
    let uploadFromFiles: () -> Void
    let deleteMedia: () -> Void
    init(uploadPhoto: @escaping () -> Void, setVideo: @escaping () -> Void, uploadFromFiles: @escaping () -> Void, deleteMedia: @escaping () -> Void) {
        self.uploadPhoto = uploadPhoto
        self.setVideo = setVideo
        self.uploadFromFiles = uploadFromFiles
        self.deleteMedia = deleteMedia
    }
}

private func profileCoverEntries(presentationData: PresentationData, path: String, isVideo: Bool) -> [ProfileCoverEntry] {
    let lang = presentationData.strings.baseLanguageCode
    var list: [ProfileCoverEntry] = []
    var id = 0
    list.append(.previewHeader(id: id, text: lang == "ru" ? "ПРЕДПРОСМОТР" : "PREVIEW"))
    id += 1
    list.append(.preview(id: id, path: path, isVideo: isVideo))
    id += 1
    list.append(.mediaHeader(id: id, text: lang == "ru" ? "МЕДИА" : "MEDIA"))
    id += 1
    list.append(.uploadPhoto(id: id, text: lang == "ru" ? "Загрузить фото" : "Upload photo"))
    id += 1
    list.append(.setVideo(id: id, text: lang == "ru" ? "Установить видео" : "Set video"))
    id += 1
    list.append(.uploadFromFiles(id: id, text: lang == "ru" ? "Загрузить из файлов" : "Load from files"))
    id += 1
    list.append(.deleteMedia(id: id, text: lang == "ru" ? "Удалить медиа" : "Delete media"))
    return list
}

public func ProfileCoverController(context: AccountContext) -> ViewController {
    let reloadPromise = ValuePromise(true, ignoreRepeated: false)
    var presentImagePicker: (() -> Void)?
    var presentVideoPicker: (() -> Void)?
    var presentDocumentPicker: (() -> Void)?
    var backAction: (() -> Void)?

    let arguments = ProfileCoverArguments(
        uploadPhoto: { presentImagePicker?() },
        setVideo: { presentVideoPicker?() },
        uploadFromFiles: { presentDocumentPicker?() },
        deleteMedia: {
            removeProfileCoverMedia()
            SGSimpleSettings.shared.profileCoverMediaPath = ""
            SGSimpleSettings.shared.profileCoverIsVideo = false
            SGSimpleSettings.shared.synchronizeShared()
            reloadPromise.set(true)
        }
    )

    let signal = combineLatest(reloadPromise.get(), context.sharedContext.presentationData)
        |> map { _, presentationData -> (ItemListControllerState, (ItemListNodeState, ProfileCoverArguments)) in
            let path = SGSimpleSettings.shared.profileCoverMediaPath
            let isVideo = SGSimpleSettings.shared.profileCoverIsVideo
            let lang = presentationData.strings.baseLanguageCode
            let controllerState = ItemListControllerState(
                presentationData: ItemListPresentationData(presentationData),
                title: .text(lang == "ru" ? "Обложка профиля" : "Profile cover"),
                leftNavigationButton: ItemListNavigationButton(content: .text(presentationData.strings.Common_Back), style: .regular, enabled: true, action: { backAction?() }),
                rightNavigationButton: nil,
                backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
            )
            let entries = profileCoverEntries(presentationData: presentationData, path: path, isVideo: isVideo)
            let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, ensureVisibleItemTag: nil, initialScrollToItem: nil)
            return (controllerState, (listState, arguments))
        }

    let controller = ItemListController(context: context, state: signal)
    backAction = { [weak controller] in controller?.dismiss() }

    presentImagePicker = { [weak controller] in
        guard let controller = controller else { return }
        // UIImagePickerController надёжнее PHPicker при выборе из галереи (iOS 16+)
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.mediaTypes = ["public.image"]
        let delegate = ProfileCoverImagePickerDelegate(
            onPick: { image in
                do {
                    let savedPath = try saveProfileCoverPhoto(from: image)
                    SGSimpleSettings.shared.profileCoverMediaPath = savedPath
                    SGSimpleSettings.shared.profileCoverIsVideo = false
                    SGSimpleSettings.shared.synchronizeShared()
                    reloadPromise.set(true)
                    NotificationCenter.default.post(name: .SGProfileCoverDidChange, object: nil)
                } catch {}
            }
        )
        picker.delegate = delegate
        objc_setAssociatedObject(picker, &profileCoverImagePickerDelegateKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        controller.present(picker, animated: true)
    }

    presentVideoPicker = { [weak controller] in
        guard let controller = controller else { return }
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.mediaTypes = ["public.movie"]
        picker.videoMaximumDuration = 30
        let delegate = ProfileCoverVideoPickerDelegate(
            onPick: { url in
                let needsStop = url.startAccessingSecurityScopedResource()
                defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
                do {
                    let savedPath = try saveProfileCoverVideo(from: url)
                    SGSimpleSettings.shared.profileCoverMediaPath = savedPath
                    SGSimpleSettings.shared.profileCoverIsVideo = true
                    SGSimpleSettings.shared.synchronizeShared()
                    reloadPromise.set(true)
                    NotificationCenter.default.post(name: .SGProfileCoverDidChange, object: nil)
                } catch {}
            }
        )
        picker.delegate = delegate
        objc_setAssociatedObject(picker, &profileCoverVideoPickerDelegateKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        controller.present(picker, animated: true)
    }

    presentDocumentPicker = { [weak controller] in
        guard let controller = controller else { return }
        let onPick: (URL) -> Void = { url in
            // With asCopy: true the file is in app sandbox; only some sources need security-scoped access
            let needsStop = url.startAccessingSecurityScopedResource()
            defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
            let ext = url.pathExtension.lowercased()
            let isVideo = ["mov", "mp4", "m4v"].contains(ext)
            if isVideo {
                do {
                    let savedPath = try saveProfileCoverVideo(from: url)
                    SGSimpleSettings.shared.profileCoverMediaPath = savedPath
                    SGSimpleSettings.shared.profileCoverIsVideo = true
                    SGSimpleSettings.shared.synchronizeShared()
                    reloadPromise.set(true)
                    NotificationCenter.default.post(name: .SGProfileCoverDidChange, object: nil)
                } catch {}
            } else {
                guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return }
                do {
                    let savedPath = try saveProfileCoverPhoto(from: image)
                    SGSimpleSettings.shared.profileCoverMediaPath = savedPath
                    SGSimpleSettings.shared.profileCoverIsVideo = false
                    SGSimpleSettings.shared.synchronizeShared()
                    reloadPromise.set(true)
                    NotificationCenter.default.post(name: .SGProfileCoverDidChange, object: nil)
                } catch {}
            }
        }
        if #available(iOS 14.0, *) {
            let types: [UTType] = [.image, .movie]
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
            let delegate = ProfileCoverDocumentPickerDelegate(onPick: onPick)
            picker.delegate = delegate
            objc_setAssociatedObject(picker, &profileCoverDocumentPickerDelegateKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            controller.present(picker, animated: true)
        } else {
            let picker = UIDocumentPickerViewController(documentTypes: ["public.image", "public.movie"], in: .import)
            let delegate = ProfileCoverDocumentPickerDelegate(onPick: onPick)
            picker.delegate = delegate
            objc_setAssociatedObject(picker, &profileCoverDocumentPickerDelegateKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            controller.present(picker, animated: true)
        }
    }

    return controller
}

private final class ProfileCoverImagePickerDelegate: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let onPick: (UIImage) -> Void
    init(onPick: @escaping (UIImage) -> Void) { self.onPick = onPick }
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage else { return }
        onPick(image)
    }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

private final class ProfileCoverVideoPickerDelegate: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let onPick: (URL) -> Void
    init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let url = info[.mediaURL] as? URL else { return }
        onPick(url)
    }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

private final class ProfileCoverDocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    let onPick: (URL) -> Void
    init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        onPick(url)
    }
}
