import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import SGSimpleSettings
import AppBundle

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

/// Modal popup when user taps a .plugin file in chat: shows plugin info and "Install" button.
public final class PluginInstallPopupController: ViewController {
    private let context: AccountContext
    private let message: Message
    private let file: TelegramMediaFile
    private var onInstalled: (() -> Void)?
    
    private var loadDisposable: Disposable?
    private var state: State = .loading {
        didSet { applyState() }
    }
    
    private enum State {
        case loading
        case loaded(metadata: PluginMetadata, hasSettings: Bool, filePath: String)
        case error(String)
    }
    
    private let contentNode: PluginInstallPopupContentNode
    
    public init(context: AccountContext, message: Message, file: TelegramMediaFile, onInstalled: (() -> Void)? = nil) {
        self.context = context
        self.message = message
        self.file = file
        self.onInstalled = onInstalled
        self.contentNode = PluginInstallPopupContentNode()
        super.init(navigationBarPresentationData: nil)
        self.blocksBackgroundWhenInOverlay = true
    }
    
    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        loadDisposable?.dispose()
    }
    
    override public func loadDisplayNode() {
        self.displayNode = contentNode
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        contentNode.backgroundColor = presentationData.theme.list.itemBlocksBackgroundColor
        contentNode.controller = self
        contentNode.installAction = { [weak self] enableAfterInstall in
            self?.performInstall(enableAfterInstall: enableAfterInstall)
        }
        contentNode.closeAction = { [weak self] in
            self?.dismiss()
        }
        contentNode.shareAction = { [weak self] in
            self?.sharePlugin()
        }
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: presentationData.strings.Common_Close, style: .plain, target: self, action: #selector(closeTapped))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareTapped))
        applyState()
        startLoading()
    }
    
    @objc private func closeTapped() {
        dismiss()
    }
    
    @objc private func shareTapped() {
        sharePlugin()
    }
    
    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    private func startLoading() {
        let postbox = context.account.postbox
        let resource = file.resource
        loadDisposable?.dispose()
        loadDisposable = (postbox.mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: true))
            |> filter { $0.complete }
            |> take(1)
            |> deliverOnMainQueue
        ).start(next: { [weak self] data in
            guard let self = self else { return }
            guard let content = try? String(contentsOfFile: data.path, encoding: .utf8) else {
                self.state = .error("Не удалось прочитать файл")
                return
            }
            guard let metadata = currentPluginRuntime.parseMetadata(content: content) else {
                self.state = .error("Неверный формат плагина")
                return
            }
            let hasSettings = currentPluginRuntime.hasCreateSettings(content: content)
            self.state = .loaded(metadata: metadata, hasSettings: hasSettings, filePath: data.path)
        })
    }
    
    private func applyState() {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        switch state {
        case .loading:
            contentNode.setLoading(presentationData: presentationData)
        case .loaded(let metadata, let hasSettings, _):
            contentNode.setLoaded(presentationData: presentationData, metadata: metadata, hasSettings: hasSettings)
        case .error(let message):
            contentNode.setError(presentationData: presentationData, message: message, retry: { [weak self] in
                self?.state = .loading
                self?.startLoading()
            })
        }
    }
    
    private func performInstall(enableAfterInstall: Bool) {
        guard case .loaded(let metadata, let hasSettings, let filePath) = state else { return }
        let fileManager = FileManager.default
        guard let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let pluginsDir = supportURL.appendingPathComponent("Plugins", isDirectory: true)
        let destPath = pluginsDir.appendingPathComponent("\(metadata.id).plugin").path
        do {
            try fileManager.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
            let destURL = URL(fileURLWithPath: destPath)
            try? fileManager.removeItem(at: destURL)
            try fileManager.copyItem(at: URL(fileURLWithPath: filePath), to: destURL)
        } catch {
            contentNode.showError("Не удалось установить: \(error.localizedDescription)")
            return
        }
        var plugins = loadInstalledPlugins()
        plugins.removeAll { $0.metadata.id == metadata.id }
        plugins.append(PluginInfo(metadata: metadata, path: destPath, enabled: enableAfterInstall, hasSettings: hasSettings))
        saveInstalledPlugins(plugins)
        onInstalled?()
        dismiss()
    }
    
    private func sharePlugin() {
        guard case .loaded(_, _, let filePath) = state else { return }
        let url = URL(fileURLWithPath: filePath)
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let window = self.view.window, let root = window.rootViewController {
            var top = root
            while let presented = top.presentedViewController { top = presented }
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = view
                popover.sourceRect = CGRect(x: view.bounds.midX, y: 60, width: 0, height: 0)
                popover.permittedArrowDirections = .up
            }
            top.present(activityVC, animated: true)
        }
    }
}

// MARK: - Content node (icon, name, version, description, Install, checkbox)
private final class PluginInstallPopupContentNode: ViewControllerTracingNode {
    weak var controller: PluginInstallPopupController?
    var installAction: ((Bool) -> Void)?
    var closeAction: (() -> Void)?
    var shareAction: (() -> Void)?
    var retryBlock: (() -> Void)?
    
    private let scrollNode = ASScrollNode()
    private let iconNode = ASImageNode()
    private let nameNode = ImmediateTextNode()
    private let versionNode = ImmediateTextNode()
    private let descriptionNode = ImmediateTextNode()
    private let installButton = ASButtonNode()
    private let enableAfterContainer = ASDisplayNode()
    private let enableAfterLabel = ImmediateTextNode()
    private let loadingNode = ASDisplayNode()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let errorLabel = ImmediateTextNode()
    private let retryButton = ASButtonNode()
    
    private var enableAfterInstall: Bool = true
    private var currentMetadata: PluginMetadata?
    private var switchView: UISwitch?
    
    override init() {
        super.init()
        addSubnode(scrollNode)
        scrollNode.addSubnode(iconNode)
        scrollNode.addSubnode(nameNode)
        scrollNode.addSubnode(versionNode)
        scrollNode.addSubnode(descriptionNode)
        scrollNode.addSubnode(installButton)
        scrollNode.addSubnode(enableAfterContainer)
        scrollNode.addSubnode(enableAfterLabel)
        addSubnode(loadingNode)
        addSubnode(errorLabel)
        addSubnode(retryButton)
        iconNode.contentMode = .scaleAspectFit
        installButton.addTarget(self, action: #selector(installTapped), forControlEvents: .touchUpInside)
        retryButton.addTarget(self, action: #selector(retryTapped), forControlEvents: .touchUpInside)
    }
    
    func setLoading(presentationData: PresentationData) {
        backgroundColor = presentationData.theme.list.itemBlocksBackgroundColor
        loadingNode.isHidden = false
        loadingNode.view.addSubview(loadingIndicator)
        loadingIndicator.startAnimating()
        scrollNode.isHidden = true
        errorLabel.isHidden = true
        retryButton.isHidden = true
    }
    
    func setLoaded(presentationData: PresentationData, metadata: PluginMetadata, hasSettings: Bool) {
        backgroundColor = presentationData.theme.list.itemBlocksBackgroundColor
        currentMetadata = metadata
        loadingNode.isHidden = true
        loadingIndicator.stopAnimating()
        errorLabel.isHidden = true
        retryButton.isHidden = true
        scrollNode.isHidden = false
        
        let theme = presentationData.theme
        let lang = presentationData.strings.baseLanguageCode
        let isRu = lang == "ru"
        
        iconNode.image = (metadata.iconRef.flatMap { UIImage(bundleImageName: $0) }) ?? UIImage(bundleImageName: "glePlugins/1")
        
        nameNode.attributedText = NSAttributedString(string: metadata.name, font: Font.bold(22), textColor: theme.list.itemPrimaryTextColor)
        nameNode.maximumNumberOfLines = 1
        nameNode.truncationMode = .byTruncatingTail
        
        let versionAuthor = (isRu ? "Версия " : "Version ") + "\(metadata.version)" + (metadata.author.isEmpty ? "" : " • \(metadata.author)")
        versionNode.attributedText = NSAttributedString(string: versionAuthor, font: Font.regular(15), textColor: theme.list.itemSecondaryTextColor)
        versionNode.maximumNumberOfLines = 1
        
        descriptionNode.attributedText = NSAttributedString(string: metadata.description.isEmpty ? (isRu ? "Нет описания." : "No description.") : metadata.description, font: Font.regular(15), textColor: theme.list.itemPrimaryTextColor)
        descriptionNode.maximumNumberOfLines = 6
        descriptionNode.truncationMode = .byTruncatingTail
        
        installButton.setTitle(isRu ? "Установить" : "Install", with: Font.semibold(17), with: .white, for: .normal)
        installButton.backgroundColor = theme.list.itemAccentColor
        installButton.cornerRadius = 12
        installButton.contentEdgeInsets = UIEdgeInsets(top: 14, left: 24, bottom: 14, right: 24)
        
        enableAfterLabel.attributedText = NSAttributedString(string: isRu ? "Включить после установки" : "Enable after installation", font: Font.regular(16), textColor: theme.list.itemPrimaryTextColor)
        enableAfterLabel.maximumNumberOfLines = 1
        
        if switchView == nil {
            let sw = UISwitch()
            sw.isOn = enableAfterInstall
            sw.addTarget(self, action: #selector(enableAfterChanged(_:)), for: .valueChanged)
            enableAfterContainer.view.addSubview(sw)
            switchView = sw
        }
        switchView?.isOn = enableAfterInstall
        
        layoutContent()
    }
    
    @objc private func enableAfterChanged(_ sender: UISwitch) {
        enableAfterInstall = sender.isOn
    }
    
    func setError(presentationData: PresentationData, message: String, retry: @escaping () -> Void) {
        backgroundColor = presentationData.theme.list.itemBlocksBackgroundColor
        retryBlock = retry
        currentMetadata = nil
        loadingNode.isHidden = true
        scrollNode.isHidden = true
        errorLabel.isHidden = false
        retryButton.isHidden = false
        errorLabel.attributedText = NSAttributedString(string: message, font: Font.regular(16), textColor: presentationData.theme.list.itemDestructiveColor)
        let retryTitle = (presentationData.strings.baseLanguageCode == "ru" ? "Повторить" : "Retry")
        retryButton.setTitle(retryTitle, with: Font.regular(17), with: presentationData.theme.list.itemAccentColor, for: .normal)
        layoutContent()
    }
    
    func showError(_ message: String) {
        errorLabel.attributedText = NSAttributedString(string: message, font: Font.regular(16), textColor: .red)
        errorLabel.isHidden = false
        errorLabel.frame = CGRect(x: 24, y: 120, width: bounds.width - 48, height: 60)
    }
    
    @objc private func installTapped() {
        installAction?(enableAfterInstall)
    }
    
    @objc private func retryTapped() {
        guard let retry = retryBlock else { return }
        retry()
    }
    
    private func layoutContent() {
        let b = bounds
        let w = b.width > 0 ? b.width : 320
        let pad: CGFloat = 24
        
        loadingIndicator.center = CGPoint(x: b.midX, y: b.midY)
        loadingNode.frame = b
        errorLabel.frame = CGRect(x: pad, y: b.midY - 40, width: w - pad * 2, height: 60)
        retryButton.frame = CGRect(x: pad, y: b.midY + 20, width: w - pad * 2, height: 44)
        
        scrollNode.frame = b
        let contentW = w - pad * 2
        
        iconNode.frame = CGRect(x: pad, y: 20, width: 56, height: 56)
        
        nameNode.frame = CGRect(x: pad, y: 86, width: contentW, height: 28)
        
        versionNode.frame = CGRect(x: pad, y: 118, width: contentW, height: 22)
        
        let descY: CGFloat = 150
        let descMaxH: CGFloat = 80
        if let att = descriptionNode.attributedText {
            let descSize = att.boundingRect(with: CGSize(width: contentW, height: descMaxH), options: .usesLineFragmentOrigin, context: nil).size
            descriptionNode.frame = CGRect(x: pad, y: descY, width: contentW, height: min(descMaxH, ceil(descSize.height)))
        } else {
            descriptionNode.frame = CGRect(x: pad, y: descY, width: contentW, height: 22)
        }
        
        let buttonY: CGFloat = 240
        installButton.frame = CGRect(x: pad, y: buttonY, width: contentW, height: 50)
        
        let rowY: CGFloat = 306
        let switchW: CGFloat = 51
        let switchH: CGFloat = 31
        enableAfterLabel.frame = CGRect(x: pad, y: rowY, width: contentW - switchW - 12, height: 24)
        enableAfterContainer.frame = CGRect(x: w - pad - switchW, y: rowY, width: switchW, height: switchH)
        switchView?.frame = CGRect(origin: .zero, size: CGSize(width: switchW, height: switchH))
        
        let contentHeight: CGFloat = 360
        scrollNode.view.contentSize = CGSize(width: w, height: contentHeight)
    }
    
    override func layout() {
        super.layout()
        layoutContent()
    }
}

