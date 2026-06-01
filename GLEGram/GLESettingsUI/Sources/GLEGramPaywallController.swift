import Foundation
import SwiftUI
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import SGSupporters
import SGSwiftUI
import LegacyUI

private let innerShadowWidth: CGFloat = 15.0
private let accentColorHex: String = "C0B0D8"

private struct LuxGramBackgroundView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(hex: "1A0A33"), location: 0.0),
                    .init(color: Color(hex: "3D1B6E"), location: 0.35),
                    .init(color: Color(hex: "2F1A57"), location: 0.7),
                    .init(color: Color(hex: "1A0A33"), location: 1.0),
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .edgesIgnoringSafeArea(.all)
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(hex: "4F298F").opacity(0.5), location: 0.0),
                    .init(color: Color.clear, location: 0.25),
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .edgesIgnoringSafeArea(.all)
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(hex: "604080").opacity(0.3), location: 0.0),
                    .init(color: Color.clear, location: 0.2),
                ]),
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .edgesIgnoringSafeArea(.all)
            .overlay(
                RoundedRectangle(cornerRadius: 0)
                    .stroke(Color.clear, lineWidth: 0)
                    .background(
                        ZStack {
                            innerShadow(x: -2, y: -2, blur: 6, color: Color(hex: "785B9E").opacity(0.6))
                            innerShadow(x: 2, y: 2, blur: 6, color: Color(hex: "4F298F").opacity(0.4))
                        }
                    )
            )
            .edgesIgnoringSafeArea(.all)
        }
    }

    func innerShadow(x: CGFloat, y: CGFloat, blur: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 0)
            .stroke(color, lineWidth: innerShadowWidth)
            .blur(radius: blur)
            .offset(x: x, y: y)
            .mask(RoundedRectangle(cornerRadius: 0).fill(LinearGradient(gradient: Gradient(colors: [Color.black, Color.clear]), startPoint: .top, endPoint: .bottom)))
    }
}

@available(iOS 13.0, *)
private struct LuxGramPaywallView: View {
    let promo: LuxGramPromo
    let trialAvailable: Bool
    let onTrial: () -> Void
    let onSubscribe: () -> Void
    let onBack: () -> Void

    @Environment(\.containerViewLayout) var containerViewLayout: ContainerViewLayout?
    @State private var buttonsSectionSize: CGSize = .zero

    var body: some View {
        ZStack {
            LuxGramBackgroundView()

            ZStack(alignment: .bottom) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        ZStack {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        gradient: Gradient(colors: [
                                            Color(hex: "4F298F").opacity(0.4),
                                            Color.clear
                                        ]),
                                        center: .center,
                                        startRadius: 20,
                                        endRadius: 60
                                    )
                                )
                                .frame(width: 120, height: 120)
                            Image("LuxGramSettings")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 88, height: 88)
                                .shadow(color: Color(hex: "785B9E").opacity(0.5), radius: 12, x: 0, y: 4)
                        }

                        VStack(spacing: 10) {
                            Text(promo.title)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                                .shadow(color: Color(hex: "1A0A33").opacity(0.5), radius: 2, x: 0, y: 1)

                            Text(promo.subtitle)
                                .font(.callout)
                                .foregroundColor(Color(hex: "D0C0E8"))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                                .lineSpacing(4)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(promo.features, id: \.self) { feature in
                                HStack(alignment: .top, spacing: 14) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Color(hex: accentColorHex))
                                        .font(.system(size: 22))
                                    Text(feature)
                                        .font(.subheadline)
                                        .foregroundColor(Color(hex: "E8E0F0"))
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color.white.opacity(0.08))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14)
                                                .stroke(Color(hex: "4F298F").opacity(0.3), lineWidth: 1)
                                        )
                                )
                            }
                        }
                        .padding(.horizontal)

                        Color.clear.frame(height: buttonsSectionSize.height + 24)
                    }
                    .padding(.vertical, 36)
                }
                .padding(.leading, max(innerShadowWidth + 8.0, sgLeftSafeAreaInset(containerViewLayout)))
                .padding(.trailing, max(innerShadowWidth + 8.0, sgRightSafeAreaInset(containerViewLayout)))

                VStack(spacing: 0) {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(hex: "1A0A33").opacity(0),
                                    Color(hex: "1A0A33").opacity(0.8)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: 20)
                    Divider()
                        .background(Color(hex: "4F298F").opacity(0.4))
                    VStack(spacing: 12) {
                        if trialAvailable {
                            Button(action: onTrial) {
                                Text(promo.trialButtonText)
                                    .fontWeight(.semibold)
                                    .font(.system(size: 17))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color(hex: "A78BDA"),
                                                Color(hex: "785B9E")
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .foregroundColor(.white)
                                    .cornerRadius(14)
                                    .shadow(color: Color(hex: "4F298F").opacity(0.5), radius: 8, x: 0, y: 4)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        Button(action: onSubscribe) {
                            Text(promo.subscribeButtonText)
                                .fontWeight(.semibold)
                                .font(.system(size: 17))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.white.opacity(0.12))
                                .cornerRadius(14)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color(hex: "C0B0D8").opacity(0.4), lineWidth: 1)
                                )
                                .foregroundColor(Color(hex: "E8E0F0"))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding([.horizontal, .top], 16)
                    .padding(.bottom, sgBottomSafeAreaInset(containerViewLayout) + 16)
                }
                .background(Color(hex: "1A0A33"))
                .shadow(color: Color(hex: "1A0A33").opacity(0.5), radius: 12, y: -4)
                .trackSize($buttonsSectionSize)
            }
        }
        .overlay(backButtonView)
        .colorScheme(.dark)
    }

    private var backButtonView: some View {
        VStack {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(hex: "E8E0F0"))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                Spacer()
            }
            .padding([.top, .leading], 16)
            Spacer()
        }
    }
}

public func gleGramPaywallController(context: AccountContext, promo: LuxGramPromo, trialAvailable: Bool) -> ViewController {
    if #available(iOS 13.0, *) {
        let theme = defaultDarkColorPresentationTheme
        let strings = context.sharedContext.currentPresentationData.with { $0 }.strings

        let legacyController = LegacySwiftUIController(
            presentation: .navigation,
            theme: theme,
            strings: strings
        )
        legacyController.statusBar.statusBarStyle = .White
        legacyController.displayNavigationBar = false
        legacyController.title = ""

        var weakLegacy: LegacySwiftUIController?
        weakLegacy = legacyController

        let swiftUIView = SGSwiftUIView<LuxGramPaywallView>(
            legacyController: legacyController,
            content: {
                LuxGramPaywallView(
                    promo: promo,
                    trialAvailable: trialAvailable,
                    onTrial: { [weak context] in
                        guard let context else { return }
                        let userId = context.account.peerId.id._internalGetInt64Value()
                        guard let signal = startTrialIfConfigured(userId: userId) else { return }
                        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                        let lang = presentationData.strings.baseLanguageCode
                        _ = (signal |> deliverOnMainQueue).start(next: { trial in
                            if let trial = trial, trial.alreadyUsed {
                                let text = lang == "ru" ? "Пробный период уже был использован" : "Trial has already been used"
                                weakLegacy?.present(standardTextAlertController(theme: AlertControllerTheme(presentationData: presentationData), title: nil, text: text, actions: [
                                    TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
                                ]), in: .window(.root))
                            } else if let trial = trial, trial.active {
                                refreshLuxGramStatusIfConfigured(userId: userId)
                                let text = lang == "ru" ? "Пробный период активирован!" : "Trial activated!"
                                weakLegacy?.present(standardTextAlertController(theme: AlertControllerTheme(presentationData: presentationData), title: nil, text: text, actions: [
                                    TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {
                                        weakLegacy?.navigationController?.popViewController(animated: true)
                                    })
                                ]), in: .window(.root))
                            }
                        }, error: { err in
                            let text: String
                            if case .tooManyRequests = err {
                                text = lang == "ru" ? "Слишком много запросов. Подождите минуту." : "Too many requests. Wait a minute."
                            } else {
                                text = lang == "ru" ? "Ошибка сети. Попробуйте позже." : "Network error. Try again later."
                            }
                            weakLegacy?.present(standardTextAlertController(theme: AlertControllerTheme(presentationData: presentationData), title: nil, text: text, actions: [
                                TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
                            ]), in: .window(.root))
                        })
                    },
                    onSubscribe: { [weak context] in
                        guard let context, let urlString = promo.miniAppUrl, isUrlSafeForExternalOpen(urlString) else { return }
                        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                        context.sharedContext.openExternalUrl(context: context, urlContext: .generic, url: urlString, forceExternal: false, presentationData: presentationData, navigationController: weakLegacy?.navigationController as? NavigationController, dismissInput: {})
                    },
                    onBack: { weakLegacy?.navigationController?.popViewController(animated: true) }
                )
            }
        )
        let hostingController = UIHostingController(rootView: swiftUIView, ignoreSafeArea: true)
        legacyController.bind(controller: hostingController)

        return legacyController
    } else {
        return LuxGramPaywallFallbackController(context: context, promo: promo, trialAvailable: trialAvailable)
    }
}

private final class LuxGramPaywallFallbackController: ViewController {
    private let context: AccountContext
    private let promo: LuxGramPromo
    private let trialAvailable: Bool

    init(context: AccountContext, promo: LuxGramPromo, trialAvailable: Bool) {
        self.context = context
        self.promo = promo
        self.trialAvailable = trialAvailable
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: context.sharedContext.currentPresentationData.with { $0 }))
        self.title = "LuxGram"
    }

    required init(coder: NSCoder) { fatalError() }

    override public func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = UIColor(red: 26/255, green: 10/255, blue: 51/255, alpha: 1)
    }

    private var scrollView: UIScrollView?
    private var contentLoaded = false

    override public func viewDidLoad() {
        super.viewDidLoad()
        let sv = UIScrollView()
        sv.alwaysBounceVertical = true
        view.addSubview(sv)
        scrollView = sv
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        guard let sv = scrollView else { return }

        if !contentLoaded {
            contentLoaded = true
            let sideInset: CGFloat = 24
            let maxW = layout.size.width - sideInset * 2
            var y: CGFloat = 40

            let titleLabel = UILabel()
            titleLabel.text = promo.title
            titleLabel.font = Font.bold(28)
            titleLabel.textColor = .white
            titleLabel.textAlignment = .center
            titleLabel.numberOfLines = 0
            titleLabel.frame = CGRect(x: sideInset, y: y, width: maxW, height: 60)
            sv.addSubview(titleLabel)
            y += 70

            let subLabel = UILabel()
            subLabel.text = promo.subtitle
            subLabel.font = Font.regular(16)
            subLabel.textColor = UIColor(red: 232/255, green: 224/255, blue: 240/255, alpha: 1)
            subLabel.textAlignment = .center
            subLabel.numberOfLines = 0
            let subSize = subLabel.sizeThatFits(CGSize(width: maxW, height: 200))
            subLabel.frame = CGRect(x: sideInset, y: y, width: maxW, height: subSize.height)
            sv.addSubview(subLabel)
            y += subSize.height + 24

            for f in promo.features {
                let l = UILabel()
                l.text = "✓  \(f)"
                l.font = Font.regular(17)
                l.textColor = .white
                l.numberOfLines = 0
                let sz = l.sizeThatFits(CGSize(width: maxW - 16, height: 100))
                l.frame = CGRect(x: sideInset + 8, y: y, width: maxW - 16, height: sz.height)
                sv.addSubview(l)
                y += sz.height + 12
            }
            y += 24

            if trialAvailable {
                let btn = UIButton(type: .system)
                btn.setTitle(promo.trialButtonText, for: .normal)
                btn.titleLabel?.font = Font.semibold(17)
                btn.setTitleColor(.white, for: .normal)
                btn.backgroundColor = UIColor(red: 120/255, green: 91/255, blue: 158/255, alpha: 1)
                btn.layer.cornerRadius = 12
                btn.frame = CGRect(x: sideInset, y: y, width: maxW, height: 50)
                btn.addTarget(self, action: #selector(trialTap), for: .touchUpInside)
                sv.addSubview(btn)
                y += 62
            }

            let subBtn = UIButton(type: .system)
            subBtn.setTitle(promo.subscribeButtonText, for: .normal)
            subBtn.titleLabel?.font = Font.semibold(17)
            subBtn.setTitleColor(.white, for: .normal)
            subBtn.backgroundColor = UIColor(white: 1, alpha: 0.12)
            subBtn.layer.cornerRadius = 12
            subBtn.frame = CGRect(x: sideInset, y: y, width: maxW, height: 50)
            subBtn.addTarget(self, action: #selector(subscribeTap), for: .touchUpInside)
            sv.addSubview(subBtn)
            y += 70

            sv.contentSize = CGSize(width: layout.size.width, height: y)
        }

        let topInset = layout.safeInsets.top
        sv.frame = CGRect(x: 0, y: topInset, width: layout.size.width, height: layout.size.height - topInset)
    }

    @objc private func trialTap() {
        let userId = context.account.peerId.id._internalGetInt64Value()
        guard let signal = startTrialIfConfigured(userId: userId) else { return }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let lang = presentationData.strings.baseLanguageCode
        _ = (signal |> deliverOnMainQueue).start(next: { [weak self] trial in
            guard let self else { return }
            if let trial = trial, trial.alreadyUsed {
                let text = lang == "ru" ? "Пробный период уже был использован" : "Trial has already been used"
                self.present(standardTextAlertController(theme: AlertControllerTheme(presentationData: presentationData), title: nil, text: text, actions: [
                    TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
                ]), in: .window(.root))
            } else if let trial = trial, trial.active {
                refreshLuxGramStatusIfConfigured(userId: userId)
                let text = lang == "ru" ? "Пробный период активирован!" : "Trial activated!"
                self.present(standardTextAlertController(theme: AlertControllerTheme(presentationData: presentationData), title: nil, text: text, actions: [
                    TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: { [weak self] in
                        self?.navigationController?.popViewController(animated: true)
                    })
                ]), in: .window(.root))
            }
        }, error: { [weak self] err in
            guard let self else { return }
            let text: String
            if case .tooManyRequests = err {
                text = lang == "ru" ? "Слишком много запросов. Подождите минуту." : "Too many requests. Wait a minute."
            } else {
                text = lang == "ru" ? "Ошибка сети. Попробуйте позже." : "Network error. Try again later."
            }
            self.present(standardTextAlertController(theme: AlertControllerTheme(presentationData: presentationData), title: nil, text: text, actions: [
                TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
            ]), in: .window(.root))
        })
    }

    @objc private func subscribeTap() {
        guard let urlString = promo.miniAppUrl, isUrlSafeForExternalOpen(urlString) else { return }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        context.sharedContext.openExternalUrl(context: context, urlContext: .generic, url: urlString, forceExternal: false, presentationData: presentationData, navigationController: navigationController as? NavigationController, dismissInput: {})
    }
}
