import Foundation
import SwiftUI
import SGSwiftUI
import SGStrings
import SGSimpleSettings
import LegacyUI
import Display
import TelegramPresentationData
import AccountContext

struct AppBadge: Identifiable, Hashable {
    let id: UUID = .init()
    let displayName: String
    let assetName: String
}

func getAvailableAppBadges() -> [AppBadge] {
    var appBadges: [AppBadge] = [
        .init(displayName: "LuxGram Black", assetName: "LuxGramBlackAppBadge"),
        .init(displayName: "LuxGram Green", assetName: "LuxGramGreenAppBadge"),
        // Colour variants
        .init(displayName: "Dark Purple",   assetName: "SkyAppBadge"),
        .init(displayName: "Dark",          assetName: "NightAppBadge"),
        .init(displayName: "Red",           assetName: "TitaniumAppBadge"),
        .init(displayName: "Pink",          assetName: "ProAppBadge"),
        .init(displayName: "Green",         assetName: "DayAppBadge"),
        .init(displayName: "Purple",        assetName: "SparklingAppBadge"),
    ]

    if SGSimpleSettings.shared.duckyAppIconAvailable {
        appBadges.append(.init(displayName: "Duck", assetName: "DuckyAppBadge"))
    }

    return appBadges
}
    
@available(iOS 14.0, *)
struct AppBadgeSettingsView: View {
    weak var wrapperController: LegacyController?
    let context: AccountContext
    
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.lang) var lang: String
    
    @State var selectedBadge: AppBadge
    let availableAppBadges: [AppBadge] = getAvailableAppBadges()

    private enum Layout {
        static let cardCorner: CGFloat = 12
        static let imageHeight: CGFloat = 56
        static let columnSpacing: CGFloat = 16
        static let horizontalPadding: CGFloat = 20
    }

    private var columns: [SwiftUI.GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Layout.columnSpacing), count: 2)
    }
    
    init(wrapperController: LegacyController?, context: AccountContext) {
        self.wrapperController = wrapperController
        self.context = context

        // Pick saved badge (or default to Dark Purple).
        let saved = SGSimpleSettings.shared.customAppBadge
        let initial = self.availableAppBadges.first(where: { $0.assetName == saved }) ?? self.availableAppBadges.first!
        self._selectedBadge = State(initialValue: initial)

        // Apply the badge immediately (so default isn't "Classic" until user taps).
        let sharedContext = context.sharedContext
        if sharedContext.immediateSGStatus.status > 1 {
            let image = UIImage(bundleImageName: initial.assetName) ?? UIImage(bundleImageName: "SkyAppBadge") ?? UIImage(bundleImageName: "Components/AppBadge")
            DispatchQueue.main.async {
                sharedContext.mainWindow?.badgeView.image = image
            }
        }
    }
    
    private func onSelectBadge(_ badge: AppBadge) {
        self.selectedBadge = badge
        // Persist selection
        SGSimpleSettings.shared.customAppBadge = badge.assetName
        SGSimpleSettings.shared.synchronizeShared()

        let image = UIImage(bundleImageName: selectedBadge.assetName) ?? UIImage(bundleImageName: "SkyAppBadge") ?? UIImage(bundleImageName: "Components/AppBadge")
        let sharedContext = self.context.sharedContext
        if sharedContext.immediateSGStatus.status > 1 {
            DispatchQueue.main.async {
                // Update badge view
                sharedContext.mainWindow?.badgeView.image = image
            }
        }
    }
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .center, spacing: Layout.columnSpacing) {
                ForEach(availableAppBadges) { badge in
                    Button {
                        onSelectBadge(badge)
                    } label: {
                        VStack(spacing: 8) {
                            Image(badge.assetName)
                                .resizable()
                                .scaledToFit()
                                .frame(height: Layout.imageHeight)
                                .accessibilityHidden(true)

                            Text(badge.displayName)
                                .font(.footnote)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(colorScheme == .dark ? .secondarySystemBackground : .systemBackground))
                        .cornerRadius(Layout.cardCorner)
                        .overlay(
                            RoundedRectangle(cornerRadius: Layout.cardCorner)
                                .stroke(selectedBadge == badge ? Color.accentColor : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Layout.horizontalPadding)
            .padding(.vertical, 24)

        }
        .background(Color(colorScheme == .light ? .secondarySystemBackground : .systemBackground).ignoresSafeArea())
    }
    
}

@available(iOS 14.0, *)
public func sgAppBadgeSettingsController(context: AccountContext, presentationData: PresentationData? = nil) -> ViewController {
    let theme = presentationData?.theme ?? (UITraitCollection.current.userInterfaceStyle == .dark ? defaultDarkColorPresentationTheme : defaultPresentationTheme)
    let strings = presentationData?.strings ?? defaultPresentationStrings

    let legacyController = LegacySwiftUIController(
        presentation: .navigation,
        theme: theme,
        strings: strings
    )

    legacyController.statusBar.statusBarStyle = theme.rootController
        .statusBarStyle.style
    legacyController.title = "AppBadge.Title".i18n(strings.baseLanguageCode)
    
    let swiftUIView = SGSwiftUIView<AppBadgeSettingsView>(
        legacyController: legacyController,
        manageSafeArea: true,
        content: {
            AppBadgeSettingsView(wrapperController: legacyController, context: context)
        }
    )
    let controller = UIHostingController(rootView: swiftUIView, ignoreSafeArea: true)
    legacyController.bind(controller: controller)

    return legacyController
}
