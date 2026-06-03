
public extension Notification.Name {
    static let luxgramLiquidGlassDidChange = Notification.Name("com.luxgramapp.LiquidGlassDidChange")
}
// Applies frosted-glass (UIBlurEffect) to NavigationBar, TabBar, toolbars
// and injects a subtle glass overlay on all UIButton instances.
// Toggle via SGSimpleSettings.shared.liquidGlassEnabled.

import UIKit
#if canImport(SGSimpleSettings)
import SGSimpleSettings
#endif

// MARK: - Public API

public final class LiquidGlassStyle {

    public static let shared = LiquidGlassStyle()
    private init() {}

    // Whether glass is currently applied
    private var isApplied = false

    // Stored originals for rollback
    private var originalNavBarStyle: UIBarStyle = .default
    private var originalNavBarTrans: Bool = false

    public func apply() {
        guard !isApplied else { return }
        isApplied = true
        applyNavigationBar()
        applyTabBar()
        applyToolbar()
        applyBackgrounds()
    }

    public func remove() {
        guard isApplied else { return }
        isApplied = false
        removeNavigationBar()
        removeTabBar()
        removeToolbar()
        removeBackgrounds()
    }

    public func syncWithSettings() {
        #if canImport(SGSimpleSettings)
        if SGSimpleSettings.shared.liquidGlassEnabled {
            apply()
        } else {
            remove()
        }
        #endif
    }

    // MARK: - NavigationBar

    private func applyNavigationBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()

        let blur = UIBlurEffect(style: glassBlurStyle())
        let blurView = UIVisualEffectView(effect: blur)
        blurView.alpha = 0.88

        appearance.backgroundEffect = blur
        appearance.backgroundColor = glassColor()
        appearance.shadowColor = UIColor.white.withAlphaComponent(0.08)

        let buttonAppearance = UIBarButtonItemAppearance()
        buttonAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.buttonAppearance = buttonAppearance
        appearance.backButtonAppearance = buttonAppearance
        appearance.doneButtonAppearance = buttonAppearance

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = .white
    }

    private func removeNavigationBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = nil
    }

    // MARK: - TabBar

    private func applyTabBar() {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: glassBlurStyle())
        appearance.backgroundColor = glassColor()
        appearance.shadowColor = UIColor.white.withAlphaComponent(0.06)

        let itemAppearance = UITabBarItemAppearance()
        itemAppearance.selected.iconColor = .white
        itemAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.white]
        itemAppearance.normal.iconColor = UIColor.white.withAlphaComponent(0.55)
        itemAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.white.withAlphaComponent(0.55)]
        appearance.stackedLayoutAppearance = itemAppearance
        appearance.inlineLayoutAppearance = itemAppearance
        appearance.compactInlineLayoutAppearance = itemAppearance

        UITabBar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
        UITabBar.appearance().tintColor = .white
        UITabBar.appearance().unselectedItemTintColor = UIColor.white.withAlphaComponent(0.55)
    }

    private func removeTabBar() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
        UITabBar.appearance().tintColor = nil
        UITabBar.appearance().unselectedItemTintColor = nil
    }

    // MARK: - Toolbar

    private func applyToolbar() {
        let appearance = UIToolbarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: glassBlurStyle())
        appearance.backgroundColor = glassColor()
        UIToolbar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) {
            UIToolbar.appearance().scrollEdgeAppearance = appearance
        }
        UIToolbar.appearance().tintColor = .white
    }

    private func removeToolbar() {
        let appearance = UIToolbarAppearance()
        appearance.configureWithDefaultBackground()
        UIToolbar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) {
            UIToolbar.appearance().scrollEdgeAppearance = appearance
        }
        UIToolbar.appearance().tintColor = nil
    }

    // MARK: - Table / Collection backgrounds

    private func applyBackgrounds() {
        UITableView.appearance().backgroundColor = UIColor(white: 0, alpha: 0)
    }

    private func removeBackgrounds() {
        UITableView.appearance().backgroundColor = nil
    }

    // MARK: - Helpers

    private func glassBlurStyle() -> UIBlurEffect.Style {
        if #available(iOS 16.0, *) {
            return .systemUltraThinMaterial
        }
        return .systemThinMaterial
    }

    private func glassColor() -> UIColor {
        return UIColor(white: 1.0, alpha: 0.07)
    }
}

// MARK: - UIView extension: add glass layer to any view

public extension UIView {
    /// Wraps the view in a frosted-glass overlay. Call only when liquidGlass is enabled.
    @discardableResult
    func addLiquidGlassOverlay(cornerRadius: CGFloat = 14, alpha: CGFloat = 0.55) -> UIVisualEffectView {
        let blur = UIBlurEffect(style: .systemUltraThinMaterialLight)
        let fx = UIVisualEffectView(effect: blur)
        fx.alpha = alpha
        fx.layer.cornerRadius = cornerRadius
        fx.layer.masksToBounds = true
        fx.isUserInteractionEnabled = false
        fx.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        fx.frame = bounds
        insertSubview(fx, at: 0)
        return fx
    }
}
