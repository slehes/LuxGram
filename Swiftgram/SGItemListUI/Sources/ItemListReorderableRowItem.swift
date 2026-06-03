import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils

public final class ItemListReorderableRowItem: ListViewItem, ItemListItem {
    public let presentationData: ItemListPresentationData
    public let title: String
    public let iconName: String?
    public let sectionId: ItemListSectionId
    public let reorderId: AnyHashable

    public init(presentationData: ItemListPresentationData, title: String, iconName: String? = nil, sectionId: ItemListSectionId, reorderId: AnyHashable) {
        self.presentationData = presentationData
        self.title = title
        self.iconName = iconName
        self.sectionId = sectionId
        self.reorderId = reorderId
    }

    public func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = ItemListReorderableRowItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            Queue.mainQueue().async {
                completion(node, { return (nil, { _ in apply() }) })
            }
        }
    }

    public func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            guard let nodeValue = node() as? ItemListReorderableRowItemNode else { return }
            let makeLayout = nodeValue.asyncLayout()
            async {
                let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
                Queue.mainQueue().async {
                    completion(layout, { _ in apply() })
                }
            }
        }
    }

    public var selectable: Bool { false }
}

public final class ItemListReorderableRowItemNode: ListViewItemNode {
    private let backgroundNode: ASDisplayNode
    private let topStripeNode: ASDisplayNode
    private let bottomStripeNode: ASDisplayNode
    private let highlightedBackgroundNode: ASDisplayNode
    private let titleNode: TextNode
    private let iconNode: ASImageNode
    private var reorderControlNode: ItemListEditableReorderControlNode?

    private var item: ItemListReorderableRowItem?

    public init() {
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true
        self.topStripeNode = ASDisplayNode()
        self.topStripeNode.isLayerBacked = true
        self.bottomStripeNode = ASDisplayNode()
        self.bottomStripeNode.isLayerBacked = true
        self.highlightedBackgroundNode = ASDisplayNode()
        self.highlightedBackgroundNode.isLayerBacked = true
        self.titleNode = TextNode()
        self.titleNode.isUserInteractionEnabled = false
        self.iconNode = ASImageNode()
        self.iconNode.isLayerBacked = true
        self.iconNode.contentMode = .scaleAspectFit
        self.iconNode.isUserInteractionEnabled = false
        super.init(layerBacked: false)
        self.addSubnode(self.backgroundNode)
        self.addSubnode(self.topStripeNode)
        self.addSubnode(self.bottomStripeNode)
        self.addSubnode(self.iconNode)
        self.addSubnode(self.titleNode)
    }

    public func asyncLayout() -> (_ item: ItemListReorderableRowItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        let makeTitleLayout = TextNode.asyncLayout(self.titleNode)
        let reorderControlLayout = ItemListEditableReorderControlNode.asyncLayout(self.reorderControlNode)

        return { [weak self] item, params, neighbors in
            let iconSize: CGFloat = 22.0
            let iconGap: CGFloat = 12.0
            let baseLeftInset: CGFloat = 16.0 + params.leftInset
            let hasIcon = item.iconName != nil
            let leftInset: CGFloat = hasIcon ? baseLeftInset + iconSize + iconGap : baseLeftInset
            let reorderInset: CGFloat = 40.0
            let verticalInset: CGFloat = 13.0
            let (titleLayout, titleApply) = makeTitleLayout(TextNodeLayoutArguments(attributedString: NSAttributedString(string: item.title, font: Font.regular(17), textColor: item.presentationData.theme.list.itemPrimaryTextColor), backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: params.width - leftInset - reorderInset - params.rightInset - 16.0, height: CGFloat.greatestFiniteMagnitude), alignment: .natural, cutout: nil, insets: .zero))
            let (reorderWidth, reorderApplyClosure) = reorderControlLayout(item.presentationData.theme)
            let contentSize = CGSize(width: params.width, height: verticalInset * 2.0 + titleLayout.size.height)
            let insets = itemListNeighborsGroupedInsets(neighbors, params)
            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: insets)
            let layoutSize = layout.size
            let hasCorners = itemListHasRoundedBlockLayout(params)

            return (layout, {
                if let strongSelf = self {
                    strongSelf.item = item
                    let theme = item.presentationData.theme
                    strongSelf.backgroundNode.backgroundColor = theme.list.itemBlocksBackgroundColor
                    strongSelf.topStripeNode.backgroundColor = theme.list.itemBlocksSeparatorColor
                    strongSelf.bottomStripeNode.backgroundColor = theme.list.itemBlocksSeparatorColor
                    strongSelf.highlightedBackgroundNode.backgroundColor = theme.list.itemHighlightedBackgroundColor
                    let reorderNode = reorderApplyClosure(layoutSize.height, false, .immediate)
                    if strongSelf.reorderControlNode !== reorderNode {
                        strongSelf.reorderControlNode?.removeFromSupernode()
                        strongSelf.reorderControlNode = reorderNode
                        strongSelf.addSubnode(reorderNode)
                    }
                    reorderNode.frame = CGRect(origin: CGPoint(x: params.width - params.rightInset - reorderWidth, y: 0), size: CGSize(width: reorderWidth, height: layoutSize.height))
                    _ = titleApply()
                    strongSelf.titleNode.frame = CGRect(origin: CGPoint(x: leftInset, y: verticalInset), size: titleLayout.size)

                    // Icon
                    if let iconName = item.iconName {
                        let config = UIImage.SymbolConfiguration(pointSize: iconSize * 0.82, weight: .medium)
                        let img = UIImage(systemName: iconName, withConfiguration: config)?
                            .withTintColor(theme.list.itemAccentColor, renderingMode: .alwaysOriginal)
                        strongSelf.iconNode.image = img
                        let iconY = (layoutSize.height - iconSize) / 2.0
                        strongSelf.iconNode.frame = CGRect(x: baseLeftInset, y: iconY, width: iconSize, height: iconSize)
                        strongSelf.iconNode.isHidden = false
                    } else {
                        strongSelf.iconNode.isHidden = true
                    }

                    strongSelf.topStripeNode.isHidden = hasCorners
                    strongSelf.bottomStripeNode.isHidden = hasCorners
                    strongSelf.topStripeNode.frame = CGRect(origin: CGPoint(x: 0, y: 0), size: CGSize(width: layoutSize.width, height: UIScreenPixel))
                    strongSelf.bottomStripeNode.frame = CGRect(origin: CGPoint(x: 0, y: layoutSize.height - UIScreenPixel), size: CGSize(width: layoutSize.width, height: UIScreenPixel))
                    strongSelf.highlightedBackgroundNode.frame = CGRect(origin: .zero, size: layoutSize)
                }
            })
        }
    }

    override public func isReorderable(at point: CGPoint) -> Bool {
        if let reorderControlNode = self.reorderControlNode, reorderControlNode.frame.contains(point) {
            return true
        }
        return false
    }
}
