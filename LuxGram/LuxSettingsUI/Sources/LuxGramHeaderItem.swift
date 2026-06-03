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
    let lang: String
    let onAppearanceTap: (() -> Void)?
    let onPrivacyTap: (() -> Void)?
    let onOtherTap: (() -> Void)?

    public init(
        theme: PresentationTheme,
        title: String,
        subtitle: String,
        lang: String = "en",
        onAppearanceTap: (() -> Void)? = nil,
        onPrivacyTap: (() -> Void)? = nil,
        onOtherTap: (() -> Void)? = nil
    ) {
        self.theme = theme
        self.title = title
        self.subtitle = subtitle
        self.lang = lang
        self.onAppearanceTap = onAppearanceTap
        self.onPrivacyTap = onPrivacyTap
        self.onOtherTap = onOtherTap
    }

    public func isEqual(to: ItemListControllerHeaderItem) -> Bool {
        guard let item = to as? LuxGramHeaderItem else { return false }
        return theme === item.theme && title == item.title && subtitle == item.subtitle && lang == item.lang
    }

    public func node(current: ItemListControllerHeaderItemNode?) -> ItemListControllerHeaderItemNode {
        if let current = current as? LuxGramHeaderItemNode {
            current.item = self
            return current
        }
        return LuxGramHeaderItemNode(item: self)
    }
}

private final class NimbusGlassTabButton: UIControl {
    private let blurView: UIVisualEffectView
    private let tintOverlay: UIView
    private let iconView: UIImageView
    private let titleLabel: UILabel
    private let borderLayer: CALayer

    var onTap: (() -> Void)?

    init(systemIconName: String, title: String) {
        blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialLight))
        blurView.isUserInteractionEnabled = false

        tintOverlay = UIView()
        tintOverlay.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        tintOverlay.isUserInteractionEnabled = false

        iconView = UIImageView()
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .white
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        if let img = UIImage(systemName: systemIconName, withConfiguration: config) {
            iconView.image = img.withRenderingMode(.alwaysTemplate)
        }

        titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.95)
        titleLabel.font = UIFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.textAlignment = .center

        borderLayer = CALayer()
        borderLayer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
        borderLayer.borderWidth = 0.75

        super.init(frame: .zero)

        layer.cornerRadius = 16
        layer.masksToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 4)

        blurView.layer.cornerRadius = 16
        blurView.clipsToBounds = true
        tintOverlay.layer.cornerRadius = 16
        tintOverlay.clipsToBounds = true
        borderLayer.cornerRadius = 16

        addSubview(blurView)
        addSubview(tintOverlay)
        blurView.contentView.addSubview(iconView)
        blurView.contentView.addSubview(titleLabel)
        layer.addSublayer(borderLayer)

        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
        addTarget(self, action: #selector(touchDown), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(touchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func handleTap() { onTap?() }

    @objc private func touchDown() {
        UIView.animate(withDuration: 0.1, options: .allowUserInteraction) {
            self.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
            self.tintOverlay.backgroundColor = UIColor.white.withAlphaComponent(0.28)
        }
    }

    @objc private func touchUp() {
        UIView.animate(
            withDuration: 0.38,
            delay: 0,
            usingSpringWithDamping: 0.62,
            initialSpringVelocity: 0,
            options: .allowUserInteraction
        ) {
            self.transform = .identity
            self.tintOverlay.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        blurView.frame = bounds
        tintOverlay.frame = bounds
        borderLayer.frame = bounds

        let iconSize: CGFloat = 26
        let labelH: CGFloat = 14
        let spacing: CGFloat = 5
        let totalH = iconSize + spacing + labelH
        let topY = (bounds.height - totalH) / 2

        iconView.frame = CGRect(
            x: (bounds.width - iconSize) / 2, y: topY,
            width: iconSize, height: iconSize
        )
        titleLabel.frame = CGRect(
            x: 6, y: topY + iconSize + spacing,
            width: bounds.width - 12, height: labelH
        )
    }
}

private final class NimbusHeaderView: UIView {
    private let gradientLayer = CAGradientLayer()
    private let glowLayer = CALayer()
    private let logoBlurView: UIVisualEffectView
    private let logoImageView: UIImageView
    private let titleLabel: UILabel
    private let subtitleLabel: UILabel

    let appearanceButton: NimbusGlassTabButton
    let privacyButton: NimbusGlassTabButton
    let otherButton: NimbusGlassTabButton

    static var preferredHeight: CGFloat {
        // logoY=36, logoH=80, gap=14, titleH=32, gap=2, subH=20, gap=18, btnH=64, bottom=22
        return 36 + 80 + 14 + 32 + 2 + 20 + 18 + 64 + 22
    }

    init(lang: String) {
        let appL = lang == "ru" ? "Оформление" : "Appearance"
        let privL = lang == "ru" ? "Приватность" : "Privacy"
        let othL  = lang == "ru" ? "Прочее" : "Other"

        appearanceButton = NimbusGlassTabButton(systemIconName: "paintpalette.fill", title: appL)
        privacyButton    = NimbusGlassTabButton(systemIconName: "shield.lefthalf.filled", title: privL)
        otherButton      = NimbusGlassTabButton(systemIconName: "slider.horizontal.3", title: othL)

        logoBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialLight))
        logoImageView = UIImageView()
        titleLabel = UILabel()
        subtitleLabel = UILabel()

        super.init(frame: .zero)
        setup(lang: lang)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup(lang: String) {
        // Background gradient: deep violet → electric blue (LuxGram brand)
        gradientLayer.colors = [
            UIColor(red: 0.14, green: 0.05, blue: 0.38, alpha: 1.0).cgColor,
            UIColor(red: 0.05, green: 0.30, blue: 0.82, alpha: 1.0).cgColor,
            UIColor(red: 0.02, green: 0.62, blue: 0.88, alpha: 1.0).cgColor
        ]
        gradientLayer.locations = [0.0, 0.55, 1.0]
        gradientLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
        gradientLayer.endPoint   = CGPoint(x: 1.0, y: 1.0)
        layer.addSublayer(gradientLayer)

        // White glow halo behind logo
        glowLayer.backgroundColor = UIColor.white.withAlphaComponent(0.18).cgColor
        glowLayer.shadowColor   = UIColor.white.cgColor
        glowLayer.shadowOpacity = 0.65
        glowLayer.shadowRadius  = 22
        glowLayer.shadowOffset  = .zero
        layer.addSublayer(glowLayer)

        // Frosted pill behind logo
        logoBlurView.clipsToBounds = true

        // Logo
        logoImageView.contentMode = .scaleAspectFit
        logoImageView.clipsToBounds = true
        if let img = UIImage(bundleImageName: "LuxGramSettings") {
            logoImageView.image = img
        }

        // Title
        titleLabel.text = "LuxGram"
        titleLabel.textColor = .white
        titleLabel.font = UIFont.systemFont(ofSize: 28, weight: .heavy)
        titleLabel.textAlignment = .center

        // Subtitle
        let sub = lang == "ru"
            ? "Следующий уровень общения"
            : "Next-level messenger"
        subtitleLabel.text = sub
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        subtitleLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textAlignment = .center

        addSubview(logoBlurView)
        addSubview(logoImageView)
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(appearanceButton)
        addSubview(privacyButton)
        addSubview(otherButton)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds

        let logoSize: CGFloat = 80
        let glowSize: CGFloat = 110
        let logoX = (bounds.width - logoSize) / 2
        let logoY: CGFloat = 36

        glowLayer.frame = CGRect(
            x: (bounds.width - glowSize) / 2,
            y: logoY - (glowSize - logoSize) / 2,
            width: glowSize, height: glowSize
        )
        glowLayer.cornerRadius = glowSize / 2

        let blurPad: CGFloat = 5
        logoBlurView.frame = CGRect(
            x: logoX - blurPad,
            y: logoY - blurPad,
            width: logoSize + blurPad * 2,
            height: logoSize + blurPad * 2
        )
        logoBlurView.layer.cornerRadius = (logoSize + blurPad * 2) / 2

        logoImageView.frame = CGRect(x: logoX, y: logoY, width: logoSize, height: logoSize)
        logoImageView.layer.cornerRadius = logoSize * 0.22

        let titleY = logoY + logoSize + 14
        titleLabel.frame = CGRect(x: 16, y: titleY, width: bounds.width - 32, height: 32)

        let subY = titleY + 32 + 2
        subtitleLabel.frame = CGRect(x: 16, y: subY, width: bounds.width - 32, height: 20)

        let btnH: CGFloat  = 64
        let btnY: CGFloat  = subY + 20 + 18
        let totalW = bounds.width - 48
        let btnW   = (totalW - 24) / 3

        appearanceButton.frame = CGRect(x: 16,                     y: btnY, width: btnW, height: btnH)
        privacyButton.frame    = CGRect(x: 16 + btnW + 12,         y: btnY, width: btnW, height: btnH)
        otherButton.frame      = CGRect(x: 16 + (btnW + 12) * 2,   y: btnY, width: btnW, height: btnH)
    }
}

final class LuxGramHeaderItemNode: ItemListControllerHeaderItemNode {
    private var headerView: NimbusHeaderView?
    private var validLayout: ContainerViewLayout?

    var item: LuxGramHeaderItem {
        didSet {
            if let layout = validLayout {
                _ = updateLayout(layout: layout, transition: .immediate)
            }
        }
    }

    init(item: LuxGramHeaderItem) {
        self.item = item
        super.init()
        backgroundColor = .clear
    }

    override func didLoad() {
        super.didLoad()
        let hv = NimbusHeaderView(lang: item.lang)
        hv.appearanceButton.onTap = { [weak self] in self?.item.onAppearanceTap?() }
        hv.privacyButton.onTap    = { [weak self] in self?.item.onPrivacyTap?() }
        hv.otherButton.onTap      = { [weak self] in self?.item.onOtherTap?() }
        view.addSubview(hv)
        headerView = hv
    }

    override func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) -> CGFloat {
        validLayout = layout
        let h = NimbusHeaderView.preferredHeight
        headerView?.frame = CGRect(x: 0, y: 0, width: layout.size.width, height: h)
        return h
    }
}
