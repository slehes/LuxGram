import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import AppBundle

/// One row per plugin: icon, name, author, description; switch on the right (like Active sites).
final class ItemListPluginRowItem: ListViewItem, ItemListItem {
    let presentationData: ItemListPresentationData
    let plugin: PluginInfo
    let icon: UIImage?
    let sectionId: ItemListSectionId
    let toggle: (Bool) -> Void
    let action: (() -> Void)?
    
    init(presentationData: ItemListPresentationData, plugin: PluginInfo, icon: UIImage?, sectionId: ItemListSectionId, toggle: @escaping (Bool) -> Void, action: (() -> Void)? = nil) {
        self.presentationData = presentationData
        self.plugin = plugin
        self.icon = icon
        self.sectionId = sectionId
        self.toggle = toggle
        self.action = action
    }
    
    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = ItemListPluginRowItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            Queue.mainQueue().async {
                completion(node, { return (nil, { _ in apply(false) }) })
            }
        }
    }
    
    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? ItemListPluginRowItemNode {
                let makeLayout = nodeValue.asyncLayout()
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
                    Queue.mainQueue().async {
                        completion(layout, { _ in apply(animation.isAnimated) })
                    }
                }
            }
        }
    }
    
    var selectable: Bool { action != nil }
    func selected(listView: ListView) {
        listView.clearHighlightAnimated(true)
        action?()
    }
}

private let leftInsetNoIcon: CGFloat = 16.0
private let iconSize: CGFloat = 30.0
private let leftInsetWithIcon: CGFloat = 16.0 + iconSize + 13.0
private let switchWidth: CGFloat = 51.0
private let switchRightInset: CGFloat = 15.0

final class ItemListPluginRowItemNode: ListViewItemNode {
    private let backgroundNode: ASDisplayNode
    private let topStripeNode: ASDisplayNode
    private let bottomStripeNode: ASDisplayNode
    private let highlightedBackgroundNode: ASDisplayNode
    private let maskNode: ASImageNode
    
    private let iconNode: ASImageNode
    private let titleNode: TextNode
    private let authorNode: TextNode
    private let descriptionNode: TextNode
    private var switchNode: ASDisplayNode?
    private var switchView: UISwitch?
    
    private var layoutParams: (ItemListPluginRowItem, ListViewItemLayoutParams, ItemListNeighbors)?
    
    init() {
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true
        self.topStripeNode = ASDisplayNode()
        self.topStripeNode.isLayerBacked = true
        self.bottomStripeNode = ASDisplayNode()
        self.bottomStripeNode.isLayerBacked = true
        self.maskNode = ASImageNode()
        self.maskNode.isUserInteractionEnabled = false
        self.iconNode = ASImageNode()
        self.iconNode.contentMode = .scaleAspectFit
        self.iconNode.cornerRadius = 7.0
        self.iconNode.clipsToBounds = true
        self.iconNode.isLayerBacked = true
        self.titleNode = TextNode()
        self.titleNode.isUserInteractionEnabled = false
        self.titleNode.contentsScale = UIScreen.main.scale
        self.authorNode = TextNode()
        self.authorNode.isUserInteractionEnabled = false
        self.authorNode.contentsScale = UIScreen.main.scale
        self.descriptionNode = TextNode()
        self.descriptionNode.isUserInteractionEnabled = false
        self.descriptionNode.contentsScale = UIScreen.main.scale
        self.highlightedBackgroundNode = ASDisplayNode()
        self.highlightedBackgroundNode.isLayerBacked = true
        super.init(layerBacked: false, rotated: false, seeThrough: false)
        addSubnode(self.backgroundNode)
        addSubnode(self.topStripeNode)
        addSubnode(self.bottomStripeNode)
        addSubnode(self.maskNode)
        addSubnode(self.iconNode)
        addSubnode(self.titleNode)
        addSubnode(self.authorNode)
        addSubnode(self.descriptionNode)
    }
    
    func asyncLayout() -> (ItemListPluginRowItem, ListViewItemLayoutParams, ItemListNeighbors) -> (ListViewItemNodeLayout, (Bool) -> Void) {
        let makeTitle = TextNode.asyncLayout(self.titleNode)
        let makeAuthor = TextNode.asyncLayout(self.authorNode)
        let makeDescription = TextNode.asyncLayout(self.descriptionNode)
        return { item, params, neighbors in
            let titleFont = Font.medium(floor(item.presentationData.fontSize.itemListBaseFontSize * 16.0 / 17.0))
            let textFont = Font.regular(floor(item.presentationData.fontSize.itemListBaseFontSize * 14.0 / 17.0))
            let leftInset = leftInsetWithIcon + params.leftInset
            let rightInset = params.rightInset + switchWidth + switchRightInset
            let textWidth = params.width - leftInset - rightInset - 8.0
            
            let meta = item.plugin.metadata
            let titleAttr = NSAttributedString(string: meta.name, font: titleFont, textColor: item.presentationData.theme.list.itemPrimaryTextColor)
            let lang = item.presentationData.strings.baseLanguageCode
            let versionAuthor = (lang == "ru" ? "Версия " : "Version ") + "\(meta.version) · \(meta.author)"
            let authorAttr = NSAttributedString(string: versionAuthor, font: textFont, textColor: item.presentationData.theme.list.itemSecondaryTextColor)
            let descAttr = NSAttributedString(string: meta.description, font: textFont, textColor: item.presentationData.theme.list.itemPrimaryTextColor)
            
            let (titleLayout, titleApply) = makeTitle(TextNodeLayoutArguments(attributedString: titleAttr, backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: textWidth, height: .greatestFiniteMagnitude), alignment: .natural, cutout: nil, insets: .zero))
            let (authorLayout, authorApply) = makeAuthor(TextNodeLayoutArguments(attributedString: authorAttr, backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: textWidth, height: .greatestFiniteMagnitude), alignment: .natural, cutout: nil, insets: .zero))
            let (descLayout, descApply) = makeDescription(TextNodeLayoutArguments(attributedString: descAttr, backgroundColor: nil, maximumNumberOfLines: 2, truncationType: .end, constrainedSize: CGSize(width: textWidth, height: .greatestFiniteMagnitude), alignment: .natural, cutout: nil, insets: .zero))
            
            let verticalInset: CGFloat = 4.0
            let rowHeight: CGFloat = verticalInset * 2 + 10 + titleLayout.size.height + 4 + authorLayout.size.height + 4 + descLayout.size.height
            let contentHeight = max(75.0, rowHeight)
            let insets = itemListNeighborsGroupedInsets(neighbors, params)
            let layout = ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: contentHeight), insets: insets)
            let layoutSize = layout.size
            let separatorHeight = UIScreenPixel
            
            return (layout, { [weak self] animated in
                guard let self = self else { return }
                self.layoutParams = (item, params, neighbors)
                let theme = item.presentationData.theme
                self.topStripeNode.backgroundColor = theme.list.itemBlocksSeparatorColor
                self.bottomStripeNode.backgroundColor = theme.list.itemBlocksSeparatorColor
                self.backgroundNode.backgroundColor = theme.list.itemBlocksBackgroundColor
                self.highlightedBackgroundNode.backgroundColor = theme.list.itemHighlightedBackgroundColor
                self.iconNode.image = item.icon
                let _ = titleApply()
                let _ = authorApply()
                let _ = descApply()
                
                if self.switchView == nil {
                    let sw = UISwitch()
                    sw.addTarget(self, action: #selector(self.switchChanged(_:)), for: .valueChanged)
                    self.switchView = sw
                    self.switchNode = ASDisplayNode(viewBlock: { sw })
                    self.addSubnode(self.switchNode!)
                }
                self.switchView?.isOn = item.plugin.enabled
                self.switchView?.isUserInteractionEnabled = true
                
                let hasCorners = itemListHasRoundedBlockLayout(params)
                var hasTopCorners = false
                var hasBottomCorners = false
                switch neighbors.top {
                case .sameSection(false): self.topStripeNode.isHidden = true
                default: hasTopCorners = true; self.topStripeNode.isHidden = hasCorners
                }
                let bottomStripeInset: CGFloat
                switch neighbors.bottom {
                case .sameSection(false): bottomStripeInset = leftInsetWithIcon + params.leftInset
                default: bottomStripeInset = 0; hasBottomCorners = true; self.bottomStripeNode.isHidden = hasCorners
                }
                self.maskNode.image = hasCorners ? PresentationResourcesItemList.cornersImage(theme, top: hasTopCorners, bottom: hasBottomCorners, glass: false) : nil
                
                self.backgroundNode.frame = CGRect(origin: CGPoint(x: 0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: contentHeight + min(insets.top, separatorHeight) + min(insets.bottom, separatorHeight)))
                self.maskNode.frame = self.backgroundNode.frame.insetBy(dx: params.leftInset, dy: 0)
                self.topStripeNode.frame = CGRect(x: 0, y: -min(insets.top, separatorHeight), width: layoutSize.width, height: separatorHeight)
                self.bottomStripeNode.frame = CGRect(x: bottomStripeInset, y: contentHeight, width: layoutSize.width - bottomStripeInset - params.rightInset, height: separatorHeight)
                
                self.iconNode.frame = CGRect(x: params.leftInset + 16, y: verticalInset + 10, width: iconSize, height: iconSize)
                let textX = params.leftInset + 16 + iconSize + 13
                self.titleNode.frame = CGRect(origin: CGPoint(x: textX, y: verticalInset + 10), size: titleLayout.size)
                self.authorNode.frame = CGRect(origin: CGPoint(x: textX, y: verticalInset + 10 + titleLayout.size.height + 4), size: authorLayout.size)
                self.descriptionNode.frame = CGRect(origin: CGPoint(x: textX, y: verticalInset + 10 + titleLayout.size.height + 4 + authorLayout.size.height + 4), size: descLayout.size)
                
                let switchSize = self.switchView?.bounds.size ?? CGSize(width: switchWidth, height: 31)
                self.switchNode?.frame = CGRect(x: params.width - params.rightInset - switchWidth - switchRightInset, y: floor((contentHeight - switchSize.height) / 2.0), width: switchWidth, height: switchSize.height)
                self.highlightedBackgroundNode.frame = self.backgroundNode.frame
            })
        }
    }
    
    @objc private func switchChanged(_ sender: UISwitch) {
        if let item = self.layoutParams?.0 {
            item.toggle(sender.isOn)
        }
    }
    
    override func setHighlighted(_ highlighted: Bool, at point: CGPoint, animated: Bool) {
        super.setHighlighted(highlighted, at: point, animated: animated)
        if highlighted {
            self.highlightedBackgroundNode.alpha = 1
            if self.highlightedBackgroundNode.supernode == nil {
                self.insertSubnode(self.highlightedBackgroundNode, aboveSubnode: self.backgroundNode)
            }
        } else {
            if animated {
                self.highlightedBackgroundNode.layer.animateAlpha(from: self.highlightedBackgroundNode.alpha, to: 0, duration: 0.25)
            }
            self.highlightedBackgroundNode.alpha = 0
        }
    }
}
