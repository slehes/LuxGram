import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData
import ItemListUI

public final class LuxGramFooterItem: ItemListControllerFooterItem {
    let theme: PresentationTheme
    let title: String
    let linkTitle: String
    let action: () -> Void

    public init(theme: PresentationTheme, title: String, linkTitle: String, action: @escaping () -> Void) {
        self.theme = theme
        self.title = title
        self.linkTitle = linkTitle
        self.action = action
    }

    public func isEqual(to: ItemListControllerFooterItem) -> Bool {
        if let item = to as? LuxGramFooterItem {
            return self.theme === item.theme && self.title == item.title && self.linkTitle == item.linkTitle
        }
        return false
    }

    public func node(current: ItemListControllerFooterItemNode?) -> ItemListControllerFooterItemNode {
        if let current = current as? LuxGramFooterItemNode {
            current.item = self
            return current
        }
        return LuxGramFooterItemNode(item: self)
    }
}

final class LuxGramFooterItemNode: ItemListControllerFooterItemNode {
    private let backgroundNode: ASDisplayNode
    private let titleNode: ImmediateTextNode
    private let linkNode: ImmediateTextNode
    private var validLayout: ContainerViewLayout?

    var item: LuxGramFooterItem {
        didSet {
            updateItem()
            if let layout = validLayout {
                _ = updateLayout(layout: layout, transition: .immediate)
            }
        }
    }

    init(item: LuxGramFooterItem) {
        self.item = item
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.backgroundColor = item.theme.list.blocksBackgroundColor
        self.titleNode = ImmediateTextNode()
        self.titleNode.maximumNumberOfLines = 1
        self.linkNode = ImmediateTextNode()
        self.linkNode.maximumNumberOfLines = 1
        super.init()
        addSubnode(backgroundNode)
        addSubnode(titleNode)
        addSubnode(linkNode)
        updateItem()
    }

    private func updateItem() {
        backgroundNode.backgroundColor = item.theme.list.blocksBackgroundColor
        titleNode.attributedText = NSAttributedString(
            string: item.title,
            font: Font.regular(15.0),
            textColor: item.theme.list.freeTextColor
        )
        linkNode.attributedText = NSAttributedString(
            string: item.linkTitle,
            font: Font.medium(15.0),
            textColor: item.theme.list.itemAccentColor
        )
    }

    override func updateBackgroundAlpha(_ alpha: CGFloat, transition: ContainedViewLayoutTransition) {
        transition.updateAlpha(node: backgroundNode, alpha: alpha)
    }

    override func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) -> CGFloat {
        validLayout = layout
        let inset: CGFloat = 16.0
        let verticalInset: CGFloat = 20.0
        let spacing: CGFloat = 4.0

        let width = layout.size.width - layout.safeInsets.left - layout.safeInsets.right - inset * 2.0
        let titleSize = titleNode.updateLayout(CGSize(width: width, height: .greatestFiniteMagnitude))
        let linkSize = linkNode.updateLayout(CGSize(width: width, height: .greatestFiniteMagnitude))

        let contentHeight = titleSize.height + spacing + linkSize.height
        let panelHeight = contentHeight + verticalInset * 2.0

        let panelFrame = CGRect(
            x: 0,
            y: 0,
            width: layout.size.width,
            height: panelHeight
        )
        transition.updateFrame(node: backgroundNode, frame: panelFrame)
        transition.updateFrame(
            node: titleNode,
            frame: CGRect(
                x: layout.safeInsets.left + inset,
                y: verticalInset,
                width: titleSize.width,
                height: titleSize.height
            )
        )
        transition.updateFrame(
            node: linkNode,
            frame: CGRect(
                x: layout.safeInsets.left + inset,
                y: verticalInset + titleSize.height + spacing,
                width: linkSize.width,
                height: linkSize.height
            )
        )
        return panelHeight
    }

    override func didLoad() {
        super.didLoad()
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    @objc private func handleTap() {
        item.action()
    }
}
