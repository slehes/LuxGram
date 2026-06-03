import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import LegacyComponents
import ItemListUI
import PresentationDataUtils
import AppBundle

public class SliderPercentageItem: ListViewItem, ItemListItem {
    let theme: PresentationTheme
    let strings: PresentationStrings
    let value: Int32
    public let sectionId: ItemListSectionId
    let updated: (Int32) -> Void
    
    public init(theme: PresentationTheme, strings: PresentationStrings, value: Int32, sectionId: ItemListSectionId, updated: @escaping (Int32) -> Void) {
        self.theme = theme
        self.strings = strings
        self.value = value
        self.sectionId = sectionId
        self.updated = updated
    }
    
    public func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = SliderPercentageItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
            
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            
            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply() })
                })
            }
        }
    }
    
    public func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? SliderPercentageItemNode {
                let makeLayout = nodeValue.asyncLayout()
                
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
                    Queue.mainQueue().async {
                        completion(layout, { _ in
                            apply()
                        })
                    }
                }
            }
        }
    }
}

private func rescalePercentageValueToSlider(_ value: CGFloat) -> CGFloat {
    return max(0.0, min(1.0, value))
}

private func rescaleSliderValueToPercentageValue(_ value: CGFloat) -> CGFloat {
    return max(0.0, min(1.0, value))
}

class SliderPercentageItemNode: ListViewItemNode {
    private let backgroundNode: ASDisplayNode
    private let topStripeNode: ASDisplayNode
    private let bottomStripeNode: ASDisplayNode
    private let maskNode: ASImageNode
    
    private var sliderView: TGPhotoEditorSliderView?
    private let leftTextNode: ImmediateTextNode
    private let rightTextNode: ImmediateTextNode
    private let centerTextNode: ImmediateTextNode
    private let centerMeasureTextNode: ImmediateTextNode
    
    private let batteryImage: UIImage?
    private let batteryBackgroundNode: ASImageNode
    private let batteryForegroundNode: ASImageNode
    
    private var item: SliderPercentageItem?
    private var layoutParams: ListViewItemLayoutParams?
    
    private let activateArea: AccessibilityAreaNode
    
    init() {
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true
        
        self.topStripeNode = ASDisplayNode()
        self.topStripeNode.isLayerBacked = true
        
        self.bottomStripeNode = ASDisplayNode()
        self.bottomStripeNode.isLayerBacked = true
        
        self.maskNode = ASImageNode()
        
        self.leftTextNode = ImmediateTextNode()
        self.rightTextNode = ImmediateTextNode()
        self.centerTextNode = ImmediateTextNode()
        self.centerMeasureTextNode = ImmediateTextNode()
        
        self.batteryImage = nil //UIImage(bundleImageName: "Settings/UsageBatteryFrame")
        self.batteryBackgroundNode = ASImageNode()
        self.batteryForegroundNode = ASImageNode()
        
        self.activateArea = AccessibilityAreaNode()
        
        super.init(layerBacked: false)
        
        self.addSubnode(self.leftTextNode)
        self.addSubnode(self.rightTextNode)
        self.addSubnode(self.centerTextNode)
        self.addSubnode(self.batteryBackgroundNode)
        self.addSubnode(self.batteryForegroundNode)
        self.addSubnode(self.activateArea)
        
        self.activateArea.increment = { [weak self] in
            if let self {
                self.sliderView?.increase(by: 0.10)
            }
        }
        
        self.activateArea.decrement = { [weak self] in
            if let self {
                self.sliderView?.decrease(by: 0.10)
            }
        }
    }
    
    override func didLoad() {
        super.didLoad()
        
        let sliderView = TGPhotoEditorSliderView()
        sliderView.enableEdgeTap = true
        sliderView.enablePanHandling = true
        sliderView.trackCornerRadius = 1.0
        sliderView.lineSize = 4.0
        sliderView.minimumValue = 0.0
        sliderView.startValue = 0.0
        sliderView.maximumValue = 1.0
        sliderView.disablesInteractiveTransitionGestureRecognizer = true
        sliderView.displayEdges = true
        if let item = self.item, let params = self.layoutParams {
            sliderView.value = rescalePercentageValueToSlider(CGFloat(item.value) / 100.0)
            sliderView.backgroundColor = item.theme.list.itemBlocksBackgroundColor
            sliderView.backColor = item.theme.list.itemSwitchColors.frameColor
            sliderView.trackColor = item.theme.list.itemAccentColor
            sliderView.knobImage = PresentationResourcesItemList.knobImage(item.theme)
            
            sliderView.frame = CGRect(origin: CGPoint(x: params.leftInset + 18.0, y: 36.0), size: CGSize(width: params.width - params.leftInset - params.rightInset - 18.0 * 2.0, height: 44.0))
        }
        self.view.addSubview(sliderView)
        sliderView.addTarget(self, action: #selector(self.sliderValueChanged), for: .valueChanged)
        self.sliderView = sliderView
    }
    
    func asyncLayout() -> (_ item: SliderPercentageItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        let currentItem = self.item
        
        return { item, params, neighbors in
            var themeUpdated = false
            if currentItem?.theme !== item.theme {
                themeUpdated = true
            }
            
            let contentSize: CGSize
            let insets: UIEdgeInsets
            let separatorHeight = UIScreenPixel
            
            contentSize = CGSize(width: params.width, height: 88.0)
            insets = itemListNeighborsGroupedInsets(neighbors, params)
            
            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: insets)
            let layoutSize = layout.size
            
            return (layout, { [weak self] in
                if let strongSelf = self {
                    strongSelf.item = item
                    strongSelf.layoutParams = params
                    
                    strongSelf.backgroundNode.backgroundColor = item.theme.list.itemBlocksBackgroundColor
                    strongSelf.topStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor
                    strongSelf.bottomStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor
                    
                    if strongSelf.backgroundNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.backgroundNode, at: 0)
                    }
                    if strongSelf.topStripeNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.topStripeNode, at: 1)
                    }
                    if strongSelf.bottomStripeNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.bottomStripeNode, at: 2)
                    }
                    if strongSelf.maskNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.maskNode, at: 3)
                    }
                    
                    let hasCorners = itemListHasRoundedBlockLayout(params)
                    var hasTopCorners = false
                    var hasBottomCorners = false
                    switch neighbors.top {
                    case .sameSection(false):
                        strongSelf.topStripeNode.isHidden = true
                    default:
                        hasTopCorners = true
                        strongSelf.topStripeNode.isHidden = hasCorners
                    }
                    let bottomStripeInset: CGFloat
                    let bottomStripeOffset: CGFloat
                    switch neighbors.bottom {
                        case .sameSection(false):
                            bottomStripeInset = params.leftInset + 16.0
                            bottomStripeOffset = -separatorHeight
                            strongSelf.bottomStripeNode.isHidden = false
                        default:
                            bottomStripeInset = 0.0
                            bottomStripeOffset = 0.0
                            hasBottomCorners = true
                            strongSelf.bottomStripeNode.isHidden = hasCorners
                    }
                    
                    strongSelf.maskNode.image = hasCorners ? PresentationResourcesItemList.cornersImage(item.theme, top: hasTopCorners, bottom: hasBottomCorners) : nil
                    
                    strongSelf.backgroundNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: contentSize.height + min(insets.top, separatorHeight) + min(insets.bottom, separatorHeight)))
                    strongSelf.maskNode.frame = strongSelf.backgroundNode.frame.insetBy(dx: params.leftInset, dy: 0.0)
                    strongSelf.topStripeNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: layoutSize.width, height: separatorHeight))
                    strongSelf.bottomStripeNode.frame = CGRect(origin: CGPoint(x: bottomStripeInset, y: contentSize.height + bottomStripeOffset), size: CGSize(width: layoutSize.width - bottomStripeInset, height: separatorHeight))
                    
                    strongSelf.leftTextNode.attributedText = NSAttributedString(string: "0%", font: Font.regular(13.0), textColor: item.theme.list.itemSecondaryTextColor)
                    strongSelf.rightTextNode.attributedText = NSAttributedString(string: "100%", font: Font.regular(13.0), textColor: item.theme.list.itemSecondaryTextColor)
                    
                    let centralText: String = "\(item.value)%"
                    let centralMeasureText: String = centralText
                    strongSelf.batteryBackgroundNode.isHidden = true
                    strongSelf.batteryForegroundNode.isHidden = strongSelf.batteryBackgroundNode.isHidden
                    strongSelf.centerTextNode.attributedText = NSAttributedString(string: centralText, font: Font.regular(16.0), textColor: item.theme.list.itemPrimaryTextColor)
                    strongSelf.centerMeasureTextNode.attributedText = NSAttributedString(string: centralMeasureText, font: Font.regular(16.0), textColor: item.theme.list.itemPrimaryTextColor)
                    
                    strongSelf.leftTextNode.isAccessibilityElement = true
                    strongSelf.leftTextNode.accessibilityLabel = "Minimum: \(Int32(rescaleSliderValueToPercentageValue(strongSelf.sliderView?.minimumValue ?? 0.0) * 100.0))%"
                    strongSelf.rightTextNode.isAccessibilityElement = true
                    strongSelf.rightTextNode.accessibilityLabel = "Maximum: \(Int32(rescaleSliderValueToPercentageValue(strongSelf.sliderView?.maximumValue ?? 1.0) * 100.0))%"
                    
                    let leftTextSize = strongSelf.leftTextNode.updateLayout(CGSize(width: 100.0, height: 100.0))
                    let rightTextSize = strongSelf.rightTextNode.updateLayout(CGSize(width: 100.0, height: 100.0))
                    let centerTextSize = strongSelf.centerTextNode.updateLayout(CGSize(width: 200.0, height: 100.0))
                    let centerMeasureTextSize = strongSelf.centerMeasureTextNode.updateLayout(CGSize(width: 200.0, height: 100.0))
                    
                    let sideInset: CGFloat = 18.0
                    
                    strongSelf.leftTextNode.frame = CGRect(origin: CGPoint(x: params.leftInset + sideInset, y: 15.0), size: leftTextSize)
                    strongSelf.rightTextNode.frame = CGRect(origin: CGPoint(x: params.width - params.leftInset - sideInset - rightTextSize.width, y: 15.0), size: rightTextSize)
                    
                    var centerFrame = CGRect(origin: CGPoint(x: floor((params.width - centerMeasureTextSize.width) / 2.0), y: 11.0), size: centerTextSize)
                    if !strongSelf.batteryBackgroundNode.isHidden {
                        centerFrame.origin.x -= 12.0
                    }
                    strongSelf.centerTextNode.frame = centerFrame
                    
                    if let frameImage = strongSelf.batteryImage {
                        strongSelf.batteryBackgroundNode.image = generateImage(frameImage.size, rotatedContext: { size, context in
                            UIGraphicsPushContext(context)
                            
                            context.clear(CGRect(origin: CGPoint(), size: size))
                            
                            if let image = generateTintedImage(image: frameImage, color: item.theme.list.itemPrimaryTextColor.withMultipliedAlpha(0.9)) {
                                image.draw(in: CGRect(origin: CGPoint(), size: size))
                                
                                let contentRect = CGRect(origin: CGPoint(x: 3.0, y: (size.height - 9.0) * 0.5), size: CGSize(width: 20.8, height: 9.0))
                                context.addPath(UIBezierPath(roundedRect: contentRect, cornerRadius: 2.0).cgPath)
                                context.clip()
                            }
                            
                            UIGraphicsPopContext()
                        })
                        strongSelf.batteryForegroundNode.image = generateImage(frameImage.size, rotatedContext: { size, context in
                            UIGraphicsPushContext(context)
                            
                            context.clear(CGRect(origin: CGPoint(), size: size))
                            
                            let contentRect = CGRect(origin: CGPoint(x: 3.0, y: (size.height - 9.0) * 0.5), size: CGSize(width: 20.8, height: 9.0))
                            context.addPath(UIBezierPath(roundedRect: contentRect, cornerRadius: 2.0).cgPath)
                            context.clip()
                            
                            context.setFillColor(UIColor.white.cgColor)
                            context.addPath(UIBezierPath(roundedRect: CGRect(origin: contentRect.origin, size: CGSize(width: contentRect.width * CGFloat(item.value) / 100.0, height: contentRect.height)), cornerRadius: 1.0).cgPath)
                            context.fillPath()
                            
                            UIGraphicsPopContext()
                        })
                        
                        let batteryColor: UIColor
                        if item.value <= 20 {
                            batteryColor = UIColor(rgb: 0xFF3B30)
                        } else {
                            batteryColor = item.theme.list.itemSwitchColors.positiveColor
                        }
                        
                        if strongSelf.batteryForegroundNode.layer.layerTintColor == nil {
                            strongSelf.batteryForegroundNode.layer.layerTintColor = batteryColor.cgColor
                        } else {
                            ContainedViewLayoutTransition.animated(duration: 0.2, curve: .easeInOut).updateTintColor(layer: strongSelf.batteryForegroundNode.layer, color: batteryColor)
                        }
                        
                        strongSelf.batteryBackgroundNode.frame = CGRect(origin: CGPoint(x: centerFrame.minX + centerMeasureTextSize.width + 4.0, y: floor(centerFrame.midY - frameImage.size.height * 0.5)), size: frameImage.size)
                        strongSelf.batteryForegroundNode.frame = strongSelf.batteryBackgroundNode.frame
                    }
                    
                    if let sliderView = strongSelf.sliderView {
                        if themeUpdated {
                            sliderView.backgroundColor = item.theme.list.itemBlocksBackgroundColor
                            sliderView.backColor = item.theme.list.itemSecondaryTextColor
                            sliderView.trackColor = item.theme.list.itemAccentColor.withAlphaComponent(0.45)
                            sliderView.knobImage = PresentationResourcesItemList.knobImage(item.theme)
                        }
                        
                        sliderView.frame = CGRect(origin: CGPoint(x: params.leftInset + 18.0, y: 36.0), size: CGSize(width: params.width - params.leftInset - params.rightInset - 18.0 * 2.0, height: 44.0))
                    }
                    
                    strongSelf.activateArea.accessibilityLabel = "Slider"
                    strongSelf.activateArea.accessibilityValue = centralMeasureText
                    strongSelf.activateArea.accessibilityTraits = .adjustable
                    strongSelf.activateArea.frame = CGRect(origin: CGPoint(x: params.leftInset, y: 0.0), size: CGSize(width: params.width - params.leftInset - params.rightInset, height: layout.contentSize.height))
                }
            })
        }
    }
    
    override func animateInsertion(_ currentTimestamp: Double, duration: Double, options: ListViewItemAnimationOptions) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.4)
    }
    
    override func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false)
    }
    
    @objc func sliderValueChanged() {
        guard let sliderView = self.sliderView else {
            return
        }
        self.item?.updated(Int32(rescaleSliderValueToPercentageValue(sliderView.value) * 100.0))
    }
}

private let kDelaySecondsValues: [Int32] = [0, 12, 30, 45]

private func indexForDelaySeconds(_ value: Int32) -> Int {
    guard let idx = kDelaySecondsValues.firstIndex(of: value) else { return 0 }
    return idx
}

private func delaySecondsForIndex(_ index: Int) -> Int32 {
    let i = max(0, min(index, kDelaySecondsValues.count - 1))
    return kDelaySecondsValues[i]
}

public class SliderDelaySecondsItem: ListViewItem, ItemListItem {
    let theme: PresentationTheme
    let strings: PresentationStrings
    let value: Int32
    let leftLabel: String
    let rightLabel: String
    let centerLabels: [String]
    public let sectionId: ItemListSectionId
    let updated: (Int32) -> Void
    
    public init(theme: PresentationTheme, strings: PresentationStrings, value: Int32, leftLabel: String, rightLabel: String, centerLabels: [String], sectionId: ItemListSectionId, updated: @escaping (Int32) -> Void) {
        self.theme = theme
        self.strings = strings
        self.value = value
        self.leftLabel = leftLabel
        self.rightLabel = rightLabel
        self.centerLabels = centerLabels
        self.sectionId = sectionId
        self.updated = updated
    }
    
    public func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = SliderDelaySecondsItemNode()
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
            if let nodeValue = node() as? SliderDelaySecondsItemNode {
                let makeLayout = nodeValue.asyncLayout()
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
                    Queue.mainQueue().async {
                        completion(layout, { _ in apply() })
                    }
                }
            }
        }
    }
}

class SliderDelaySecondsItemNode: ListViewItemNode {
    private let backgroundNode: ASDisplayNode
    private let topStripeNode: ASDisplayNode
    private let bottomStripeNode: ASDisplayNode
    private let maskNode: ASImageNode
    private var sliderView: TGPhotoEditorSliderView?
    private let leftTextNode: ImmediateTextNode
    private let rightTextNode: ImmediateTextNode
    private let centerTextNode: ImmediateTextNode
    private let centerMeasureTextNode: ImmediateTextNode
    private var item: SliderDelaySecondsItem?
    private var layoutParams: ListViewItemLayoutParams?
    
    init() {
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true
        self.topStripeNode = ASDisplayNode()
        self.topStripeNode.isLayerBacked = true
        self.bottomStripeNode = ASDisplayNode()
        self.bottomStripeNode.isLayerBacked = true
        self.maskNode = ASImageNode()
        self.leftTextNode = ImmediateTextNode()
        self.rightTextNode = ImmediateTextNode()
        self.centerTextNode = ImmediateTextNode()
        self.centerMeasureTextNode = ImmediateTextNode()
        super.init(layerBacked: false)
        self.addSubnode(self.leftTextNode)
        self.addSubnode(self.rightTextNode)
        self.addSubnode(self.centerTextNode)
    }
    
    override func didLoad() {
        super.didLoad()
        let sliderView = TGPhotoEditorSliderView()
        sliderView.enableEdgeTap = true
        sliderView.enablePanHandling = true
        sliderView.trackCornerRadius = 1.0
        sliderView.lineSize = 4.0
        sliderView.minimumValue = 0.0
        sliderView.maximumValue = CGFloat(kDelaySecondsValues.count - 1)
        sliderView.startValue = 0.0
        sliderView.displayEdges = true
        sliderView.disablesInteractiveTransitionGestureRecognizer = true
        sliderView.positionsCount = kDelaySecondsValues.count
        sliderView.disableSnapToPositions = false
        if let item = self.item, let params = self.layoutParams {
            sliderView.value = CGFloat(indexForDelaySeconds(item.value))
            sliderView.backgroundColor = item.theme.list.itemBlocksBackgroundColor
            sliderView.backColor = item.theme.list.itemSwitchColors.frameColor
            sliderView.trackColor = item.theme.list.itemAccentColor
            sliderView.knobImage = PresentationResourcesItemList.knobImage(item.theme)
            sliderView.frame = CGRect(origin: CGPoint(x: params.leftInset + 18.0, y: 36.0), size: CGSize(width: params.width - params.leftInset - params.rightInset - 18.0 * 2.0, height: 44.0))
        }
        self.view.addSubview(sliderView)
        sliderView.addTarget(self, action: #selector(self.sliderValueChanged), for: .valueChanged)
        self.sliderView = sliderView
    }
    
    func asyncLayout() -> (_ item: SliderDelaySecondsItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        let currentItem = self.item
        return { item, params, neighbors in
            var themeUpdated = false
            if currentItem?.theme !== item.theme { themeUpdated = true }
            let contentSize = CGSize(width: params.width, height: 88.0)
            let insets = itemListNeighborsGroupedInsets(neighbors, params)
            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: insets)
            let layoutSize = layout.size
            let separatorHeight = UIScreenPixel
            return (layout, { [weak self] in
                guard let strongSelf = self else { return }
                strongSelf.item = item
                strongSelf.layoutParams = params
                strongSelf.backgroundNode.backgroundColor = item.theme.list.itemBlocksBackgroundColor
                strongSelf.topStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor
                strongSelf.bottomStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor
                if strongSelf.backgroundNode.supernode == nil {
                    strongSelf.insertSubnode(strongSelf.backgroundNode, at: 0)
                    strongSelf.insertSubnode(strongSelf.topStripeNode, at: 1)
                    strongSelf.insertSubnode(strongSelf.bottomStripeNode, at: 2)
                    strongSelf.insertSubnode(strongSelf.maskNode, at: 3)
                }
                let hasCorners = itemListHasRoundedBlockLayout(params)
                var hasTopCorners = false
                var hasBottomCorners = false
                switch neighbors.top {
                case .sameSection(false): strongSelf.topStripeNode.isHidden = true
                default: hasTopCorners = true; strongSelf.topStripeNode.isHidden = hasCorners
                }
                let bottomStripeInset: CGFloat
                let bottomStripeOffset: CGFloat
                switch neighbors.bottom {
                case .sameSection(false):
                    bottomStripeInset = params.leftInset + 16.0
                    bottomStripeOffset = -separatorHeight
                    strongSelf.bottomStripeNode.isHidden = false
                default:
                    bottomStripeInset = 0.0
                    bottomStripeOffset = 0.0
                    hasBottomCorners = true
                    strongSelf.bottomStripeNode.isHidden = hasCorners
                }
                strongSelf.maskNode.image = hasCorners ? PresentationResourcesItemList.cornersImage(item.theme, top: hasTopCorners, bottom: hasBottomCorners) : nil
                strongSelf.backgroundNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: contentSize.height + min(insets.top, separatorHeight) + min(insets.bottom, separatorHeight)))
                strongSelf.maskNode.frame = strongSelf.backgroundNode.frame.insetBy(dx: params.leftInset, dy: 0.0)
                strongSelf.topStripeNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: layoutSize.width, height: separatorHeight))
                strongSelf.bottomStripeNode.frame = CGRect(origin: CGPoint(x: bottomStripeInset, y: contentSize.height + bottomStripeOffset), size: CGSize(width: layoutSize.width - bottomStripeInset, height: separatorHeight))
                strongSelf.leftTextNode.attributedText = NSAttributedString(string: item.leftLabel, font: Font.regular(13.0), textColor: item.theme.list.itemSecondaryTextColor)
                strongSelf.rightTextNode.attributedText = NSAttributedString(string: item.rightLabel, font: Font.regular(13.0), textColor: item.theme.list.itemSecondaryTextColor)
                let idx = indexForDelaySeconds(item.value)
                let centerLabel = idx < item.centerLabels.count ? item.centerLabels[idx] : item.centerLabels[0]
                strongSelf.centerTextNode.attributedText = NSAttributedString(string: centerLabel, font: Font.regular(16.0), textColor: item.theme.list.itemPrimaryTextColor)
                strongSelf.centerMeasureTextNode.attributedText = NSAttributedString(string: centerLabel, font: Font.regular(16.0), textColor: item.theme.list.itemPrimaryTextColor)
                let sideInset: CGFloat = 18.0
                let leftTextSize = strongSelf.leftTextNode.updateLayout(CGSize(width: 100.0, height: 100.0))
                let rightTextSize = strongSelf.rightTextNode.updateLayout(CGSize(width: 100.0, height: 100.0))
                let centerTextSize = strongSelf.centerTextNode.updateLayout(CGSize(width: 200.0, height: 100.0))
                let centerMeasureTextSize = strongSelf.centerMeasureTextNode.updateLayout(CGSize(width: 200.0, height: 100.0))
                strongSelf.leftTextNode.frame = CGRect(origin: CGPoint(x: params.leftInset + sideInset, y: 15.0), size: leftTextSize)
                strongSelf.rightTextNode.frame = CGRect(origin: CGPoint(x: params.width - params.leftInset - sideInset - rightTextSize.width, y: 15.0), size: rightTextSize)
                let centerFrame = CGRect(origin: CGPoint(x: floor((params.width - centerMeasureTextSize.width) / 2.0), y: 11.0), size: centerTextSize)
                strongSelf.centerTextNode.frame = centerFrame
                if let sliderView = strongSelf.sliderView {
                    if themeUpdated {
                        sliderView.backgroundColor = item.theme.list.itemBlocksBackgroundColor
                        sliderView.backColor = item.theme.list.itemSwitchColors.frameColor
                        sliderView.trackColor = item.theme.list.itemAccentColor
                        sliderView.knobImage = PresentationResourcesItemList.knobImage(item.theme)
                    }
                    sliderView.value = CGFloat(indexForDelaySeconds(item.value))
                    sliderView.frame = CGRect(origin: CGPoint(x: params.leftInset + 18.0, y: 36.0), size: CGSize(width: params.width - params.leftInset - params.rightInset - 18.0 * 2.0, height: 44.0))
                }
            })
        }
    }
    
    @objc private func sliderValueChanged() {
        guard let sliderView = self.sliderView, let item = self.item else { return }
        let idx = Int(round(sliderView.value))
        item.updated(delaySecondsForIndex(idx))
    }
}

public class SliderFontSizeMultiplierItem: ListViewItem, ItemListItem {
    let theme: PresentationTheme
    let strings: PresentationStrings
    let value: Int32
    public let sectionId: ItemListSectionId
    let updated: (Int32) -> Void
    
    public init(theme: PresentationTheme, strings: PresentationStrings, value: Int32, sectionId: ItemListSectionId, updated: @escaping (Int32) -> Void) {
        self.theme = theme
        self.strings = strings
        self.value = max(50, min(150, value))
        self.sectionId = sectionId
        self.updated = updated
    }
    
    public func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = SliderFontSizeMultiplierItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            Queue.mainQueue().async { completion(node, { return (nil, { _ in apply() }) }) }
        }
    }
    
    public func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? SliderFontSizeMultiplierItemNode {
                let makeLayout = nodeValue.asyncLayout()
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
                    Queue.mainQueue().async { completion(layout, { _ in apply() }) }
                }
            }
        }
    }
}

// 50, 55, 60, ..., 150 — 21 дискретных позиций, как у SliderDelaySecondsItem
private let kFontSizeMultiplierValues: [Int32] = (10...30).map { Int32($0 * 5) } // 50..150 step 5

private func indexForFontSizeMultiplier(_ value: Int32) -> Int {
    let v = max(50, min(150, value))
    return max(0, min(kFontSizeMultiplierValues.count - 1, Int((v - 50) / 5)))
}

private func fontSizeMultiplierForIndex(_ index: Int) -> Int32 {
    let i = max(0, min(index, kFontSizeMultiplierValues.count - 1))
    return kFontSizeMultiplierValues[i]
}

class SliderFontSizeMultiplierItemNode: ListViewItemNode {
    private let backgroundNode = ASDisplayNode()
    private let topStripeNode = ASDisplayNode()
    private let bottomStripeNode = ASDisplayNode()
    private let maskNode = ASImageNode()
    private var sliderView: TGPhotoEditorSliderView?
    private let leftTextNode = ImmediateTextNode()
    private let rightTextNode = ImmediateTextNode()
    private let centerTextNode = ImmediateTextNode()
    private var item: SliderFontSizeMultiplierItem?
    private var layoutParams: ListViewItemLayoutParams?
    
    init() {
        super.init(layerBacked: false)
        backgroundNode.isLayerBacked = true
        topStripeNode.isLayerBacked = true
        bottomStripeNode.isLayerBacked = true
        addSubnode(leftTextNode)
        addSubnode(rightTextNode)
        addSubnode(centerTextNode)
    }
    
    override func didLoad() {
        super.didLoad()
        let sliderView = TGPhotoEditorSliderView()
        sliderView.enableEdgeTap = true
        sliderView.enablePanHandling = true
        sliderView.trackCornerRadius = 1.0
        sliderView.lineSize = 4.0
        sliderView.minimumValue = 0.0
        sliderView.maximumValue = CGFloat(kFontSizeMultiplierValues.count - 1)
        sliderView.startValue = 0.0
        sliderView.displayEdges = true
        sliderView.disablesInteractiveTransitionGestureRecognizer = true
        sliderView.positionsCount = kFontSizeMultiplierValues.count
        sliderView.disableSnapToPositions = false
        sliderView.useLinesForPositions = true
        if let item = self.item, let params = self.layoutParams {
            sliderView.value = CGFloat(indexForFontSizeMultiplier(item.value))
            sliderView.backgroundColor = item.theme.list.itemBlocksBackgroundColor
            sliderView.backColor = item.theme.list.itemSwitchColors.frameColor
            sliderView.trackColor = item.theme.list.itemAccentColor
            sliderView.knobImage = PresentationResourcesItemList.knobImage(item.theme)
            sliderView.frame = CGRect(origin: CGPoint(x: params.leftInset + 18.0, y: 36.0), size: CGSize(width: params.width - params.leftInset - params.rightInset - 18.0 * 2.0, height: 44.0))
        }
        view.addSubview(sliderView)
        sliderView.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
        self.sliderView = sliderView
    }
    
    func asyncLayout() -> (_ item: SliderFontSizeMultiplierItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        let currentItem = self.item
        return { item, params, neighbors in
            let themeUpdated = currentItem?.theme !== item.theme
            let contentSize = CGSize(width: params.width, height: 88.0)
            let insets = itemListNeighborsGroupedInsets(neighbors, params)
            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: insets)
            let layoutSize = layout.size
            let separatorHeight = UIScreenPixel
            return (layout, { [weak self] in
                guard let strongSelf = self else { return }
                strongSelf.item = item
                strongSelf.layoutParams = params
                strongSelf.backgroundNode.backgroundColor = item.theme.list.itemBlocksBackgroundColor
                strongSelf.topStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor
                strongSelf.bottomStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor
                if strongSelf.backgroundNode.supernode == nil {
                    strongSelf.insertSubnode(strongSelf.backgroundNode, at: 0)
                    strongSelf.insertSubnode(strongSelf.topStripeNode, at: 1)
                    strongSelf.insertSubnode(strongSelf.bottomStripeNode, at: 2)
                    strongSelf.insertSubnode(strongSelf.maskNode, at: 3)
                }
                let hasCorners = itemListHasRoundedBlockLayout(params)
                var hasTopCorners = false, hasBottomCorners = false
                switch neighbors.top {
                case .sameSection(false): strongSelf.topStripeNode.isHidden = true
                default: hasTopCorners = true; strongSelf.topStripeNode.isHidden = hasCorners
                }
                var bottomStripeInset: CGFloat = 0, bottomStripeOffset: CGFloat = 0
                switch neighbors.bottom {
                case .sameSection(false):
                    bottomStripeInset = params.leftInset + 16.0
                    bottomStripeOffset = -separatorHeight
                    strongSelf.bottomStripeNode.isHidden = false
                default:
                    hasBottomCorners = true
                    strongSelf.bottomStripeNode.isHidden = hasCorners
                }
                strongSelf.maskNode.image = hasCorners ? PresentationResourcesItemList.cornersImage(item.theme, top: hasTopCorners, bottom: hasBottomCorners) : nil
                strongSelf.backgroundNode.frame = CGRect(origin: CGPoint(x: 0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: contentSize.height + min(insets.top, separatorHeight) + min(insets.bottom, separatorHeight)))
                strongSelf.maskNode.frame = strongSelf.backgroundNode.frame.insetBy(dx: params.leftInset, dy: 0)
                strongSelf.topStripeNode.frame = CGRect(origin: CGPoint(x: 0, y: -min(insets.top, separatorHeight)), size: CGSize(width: layoutSize.width, height: separatorHeight))
                strongSelf.bottomStripeNode.frame = CGRect(origin: CGPoint(x: bottomStripeInset, y: contentSize.height + bottomStripeOffset), size: CGSize(width: layoutSize.width - bottomStripeInset, height: separatorHeight))
                strongSelf.leftTextNode.attributedText = NSAttributedString(string: "50%", font: Font.regular(13.0), textColor: item.theme.list.itemSecondaryTextColor)
                strongSelf.rightTextNode.attributedText = NSAttributedString(string: "150%", font: Font.regular(13.0), textColor: item.theme.list.itemSecondaryTextColor)
                let displayValue = fontSizeMultiplierForIndex(indexForFontSizeMultiplier(item.value))
                let centerLabel = "\(displayValue)%"
                strongSelf.centerTextNode.attributedText = NSAttributedString(string: centerLabel, font: Font.regular(16.0), textColor: item.theme.list.itemPrimaryTextColor)
                let sideInset: CGFloat = 18.0
                let leftSize = strongSelf.leftTextNode.updateLayout(CGSize(width: 100, height: 100))
                let rightSize = strongSelf.rightTextNode.updateLayout(CGSize(width: 100, height: 100))
                let centerSize = strongSelf.centerTextNode.updateLayout(CGSize(width: 200, height: 100))
                strongSelf.leftTextNode.frame = CGRect(origin: CGPoint(x: params.leftInset + sideInset, y: 15), size: leftSize)
                strongSelf.rightTextNode.frame = CGRect(origin: CGPoint(x: params.width - params.leftInset - sideInset - rightSize.width, y: 15), size: rightSize)
                strongSelf.centerTextNode.frame = CGRect(origin: CGPoint(x: floor((params.width - centerSize.width) / 2), y: 11), size: centerSize)
                if let sv = strongSelf.sliderView {
                    if themeUpdated {
                        sv.backgroundColor = item.theme.list.itemBlocksBackgroundColor
                        sv.backColor = item.theme.list.itemSwitchColors.frameColor
                        sv.trackColor = item.theme.list.itemAccentColor
                        sv.knobImage = PresentationResourcesItemList.knobImage(item.theme)
                    }
                    sv.value = CGFloat(indexForFontSizeMultiplier(item.value))
                    sv.frame = CGRect(origin: CGPoint(x: params.leftInset + 18, y: 36), size: CGSize(width: params.width - params.leftInset - params.rightInset - 18.0 * 2.0, height: 44))
                }
            })
        }
    }
    
    @objc private func sliderValueChanged() {
        guard let sliderView = self.sliderView, let item = self.item else { return }
        let idx = Int(round(sliderView.value))
        let v = fontSizeMultiplierForIndex(idx)
        // Обновляем подпись локально, без reload списка
        centerTextNode.attributedText = NSAttributedString(string: "\(v)%", font: Font.regular(16.0), textColor: item.theme.list.itemPrimaryTextColor)
        let centerSize = centerTextNode.updateLayout(CGSize(width: 200, height: 100))
        if let params = layoutParams {
            centerTextNode.frame = CGRect(origin: CGPoint(x: floor((params.width - centerSize.width) / 2), y: 11), size: centerSize)
        }
        item.updated(v)
    }
}
