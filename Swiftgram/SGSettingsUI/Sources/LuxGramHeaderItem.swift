import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData
import ItemListUI
import AppBundle

public final class LuxGramHeaderItem: ItemListControllerHeaderItem {
    let theme: PresentationTheme
    let title: String
    let subtitle: String

    public init(theme: PresentationTheme, title: String, subtitle: String) {
        self.theme = theme
        self.title = title
        self.subtitle = subtitle
    }

    public func isEqual(to: ItemListControllerHeaderItem) -> Bool {
        if let item = to as? LuxGramHeaderItem {
            return theme === item.theme && title == item.title && subtitle == item.subtitle
        }
        return false
    }

    public func node(current: ItemListControllerHeaderItemNode?) -> ItemListControllerHeaderItemNode {
        if let current = current as? LuxGramHeaderItemNode {
            current.item = self
            return current
        }
        return LuxGramHeaderItemNode(item: self)
    }
}

private let titleFont = Font.bold(22.0)
private let subtitleFont = Font.regular(14.0)
private let iconSize: CGFloat = 64.0
private let iconCornerRadius: CGFloat = 14.0

final class LuxGramHeaderItemNode: ItemListControllerHeaderItemNode {
    private let backgroundNode: ASDisplayNode
    private let iconNode: ASImageNode
    private let titleNode: ImmediateTextNode
    private let subtitleNode: ImmediateTextNode
    private var validLayout: ContainerViewLayout?

    var item: LuxGramHeaderItem {
        didSet {
            updateItem()
            if let layout = validLayout {
                _ = updateLayout(layout: layout, transition: .immediate)
            }
        }
    }

    init(item: LuxGramHeaderItem) {
        self.item = item
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true
        self.iconNode = ASImageNode()
        self.iconNode.contentMode = .scaleAspectFit
        self.iconNode.cornerRadius = iconCornerRadius
        self.iconNode.clipsToBounds = true
        if let rawIcon = UIImage(bundleImageName: "LuxGramSettings") {
            self.iconNode.image = rawIcon
        }
        self.titleNode = ImmediateTextNode()
        self.titleNode.maximumNumberOfLines = 1
        self.subtitleNode = ImmediateTextNode()
        self.subtitleNode.maximumNumberOfLines = 2
        super.init()
        addSubnode(backgroundNode)
        addSubnode(iconNode)
        addSubnode(titleNode)
        addSubnode(subtitleNode)
        updateItem()
    }

    private func updateItem() {
        backgroundNode.backgroundColor = item.theme.list.blocksBackgroundColor
        titleNode.attributedText = NSAttributedString(string: item.title, font: titleFont, textColor: item.theme.list.itemPrimaryTextColor)
        subtitleNode.attributedText = NSAttributedString(string: item.subtitle, font: subtitleFont, textColor: item.theme.list.itemSecondaryTextColor)
    }

    override func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) -> CGFloat {
        validLayout = layout
        let width = layout.size.width - 32.0
        let spacing: CGFloat = 6.0
        let iconTitleSpacing: CGFloat = 10.0
        let bottomInset: CGFloat = 4.0
        let desiredHeaderHeight: CGFloat = 200.0
        let extraTopOffset: CGFloat = 36.0

        let titleSize = titleNode.updateLayout(CGSize(width: width, height: .greatestFiniteMagnitude))
        let subtitleSize = subtitleNode.updateLayout(CGSize(width: width, height: .greatestFiniteMagnitude))
        let subtitleHeight = min(subtitleSize.height, 36.0)
        let contentBlockHeight = iconSize + iconTitleSpacing + titleSize.height + spacing + subtitleHeight
        let topInset = extraTopOffset + max(12.0, (desiredHeaderHeight - extraTopOffset - contentBlockHeight - bottomInset) / 2.0)

        backgroundNode.frame = CGRect(origin: .zero, size: CGSize(width: layout.size.width, height: desiredHeaderHeight))
        iconNode.frame = CGRect(x: floor((layout.size.width - iconSize) / 2.0), y: topInset, width: iconSize, height: iconSize)
        let titleY = topInset + iconSize + iconTitleSpacing
        titleNode.frame = CGRect(x: floor((layout.size.width - titleSize.width) / 2.0), y: titleY, width: titleSize.width, height: titleSize.height)
        subtitleNode.frame = CGRect(x: floor((layout.size.width - subtitleSize.width) / 2.0), y: titleY + titleSize.height + spacing, width: subtitleSize.width, height: subtitleHeight)

        return desiredHeaderHeight
    }
}
