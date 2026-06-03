import Foundation

public struct LuxGramUserStatus: Equatable {
    public let userId: String
    public let badges: [LuxGramBadge]
    public let subscription: LuxGramSubscription?
    public let trial: LuxGramTrial?
    public let donation: LuxGramDonation?
    public let access: LuxGramAccess
    public let luxgramPromo: LuxGramPromo?
    public let betaConfig: LuxGramBetaConfig?
    public let hasActiveSubscription: Bool
    public let hasActiveTrial: Bool
    public let trialAvailable: Bool

    public init(json: [String: Any]) {
        self.userId = json["userId"] as? String ?? ""
        self.badges = (json["badges"] as? [[String: Any]] ?? []).compactMap { LuxGramBadge(json: $0) }
        self.subscription = (json["subscription"] as? [String: Any]).flatMap { LuxGramSubscription(json: $0) }
        self.trial = (json["trial"] as? [String: Any]).flatMap { LuxGramTrial(json: $0) }
        self.donation = (json["donation"] as? [String: Any]).flatMap { LuxGramDonation(json: $0) }
        self.access = LuxGramAccess(json: json["access"] as? [String: Any] ?? [:])
        self.luxgramPromo = (json["luxgramPromo"] as? [String: Any]).flatMap { LuxGramPromo(json: $0) }
        self.betaConfig = (json["betaConfig"] as? [String: Any]).flatMap { LuxGramBetaConfig(json: $0) }
        self.hasActiveSubscription = json["hasActiveSubscription"] as? Bool ?? false
        self.hasActiveTrial = json["hasActiveTrial"] as? Bool ?? false
        self.trialAvailable = json["trialAvailable"] as? Bool ?? false
    }
}

public struct LuxGramBadge: Equatable {
    public let id: String
    public let name: String
    public let color: String
    public let displayMode: String   // "text" or "image"
    public let image: String?        // relative URL for image badges
    public let uiEnabled: Bool
    public let uiConfig: LuxGramBadgeUIConfig?

    public init?(json: [String: Any]) {
        guard let id = json["id"] as? String else { return nil }
        self.id = id
        self.name = json["name"] as? String ?? id
        self.color = json["color"] as? String ?? "#34C759"
        self.displayMode = json["displayMode"] as? String ?? "text"
        self.image = json["image"] as? String
        self.uiEnabled = json["uiEnabled"] as? Bool ?? false
        self.uiConfig = (json["uiConfig"] as? [String: Any]).flatMap { LuxGramBadgeUIConfig(json: $0) }
    }
}

public struct LuxGramBadgeUIConfig: Equatable {
    public let title: String
    public let description: String
    public let buttons: [LuxGramBadgeButton]

    public init?(json: [String: Any]) {
        self.title = json["title"] as? String ?? ""
        self.description = json["description"] as? String ?? ""
        self.buttons = (json["buttons"] as? [[String: Any]] ?? []).compactMap { LuxGramBadgeButton(json: $0) }
    }
}

public struct LuxGramBadgeButton: Equatable {
    public let label: String
    public let url: String

    public init?(json: [String: Any]) {
        guard let label = json["label"] as? String, let url = json["url"] as? String else { return nil }
        self.label = label
        self.url = url
    }
}

public struct LuxGramSubscription: Equatable {
    public let planId: String
    public let startedAt: String
    public let expiresAt: String
    public let active: Bool

    public init?(json: [String: Any]) {
        self.planId = json["planId"] as? String ?? ""
        self.startedAt = json["startedAt"] as? String ?? ""
        self.expiresAt = json["expiresAt"] as? String ?? ""
        self.active = json["active"] as? Bool ?? false
    }
}

public struct LuxGramTrial: Equatable {
    public let startedAt: String
    public let expiresAt: String
    public let active: Bool
    public let alreadyUsed: Bool

    public init?(json: [String: Any]) {
        self.startedAt = json["startedAt"] as? String ?? ""
        self.expiresAt = json["expiresAt"] as? String ?? ""
        self.active = json["active"] as? Bool ?? false
        self.alreadyUsed = json["alreadyUsed"] as? Bool ?? false
    }
}

public struct LuxGramDonation: Equatable {
    public let amount: Int
    public let lastDonatedAt: String
    public let betaAccess: Bool

    public init?(json: [String: Any]) {
        self.amount = json["amount"] as? Int ?? 0
        self.lastDonatedAt = json["lastDonatedAt"] as? String ?? ""
        self.betaAccess = json["betaAccess"] as? Bool ?? false
    }
}

public struct LuxGramAccess: Equatable {
    // Obfuscated storage: actual bits XOR'd with per-instance random salt.
    // Prevents trivial memory scanning for plain true/false values.
    private let _enc: UInt32
    private let _salt: UInt32
    /// HMAC access token (base64). Used by integrity layer to verify flags haven't been tampered.
    public let accessToken: String?

    public var luxgramTab: Bool {
        return (_enc ^ _salt) & 0x1 != 0
    }

    public var betaBuilds: Bool {
        return (_enc ^ _salt) & 0x2 != 0
    }

    public init(json: [String: Any]) {
        let tab = json["luxgramTab"] as? Bool ?? false
        let beta = json["betaBuilds"] as? Bool ?? false
        let bits: UInt32 = (tab ? 1 : 0) | (beta ? 2 : 0)
        let salt = UInt32.random(in: 1...UInt32.max)
        self._enc = bits ^ salt
        self._salt = salt
        self.accessToken = json["_accessToken"] as? String
    }

    public static func == (lhs: LuxGramAccess, rhs: LuxGramAccess) -> Bool {
        return lhs.luxgramTab == rhs.luxgramTab && lhs.betaBuilds == rhs.betaBuilds
    }
}

public struct LuxGramPromo: Equatable {
    public let title: String
    public let subtitle: String
    public let features: [String]
    public let trialButtonText: String
    public let subscribeButtonText: String
    public let miniAppUrl: String?

    public init?(json: [String: Any]) {
        self.title = json["title"] as? String ?? ""
        self.subtitle = json["subtitle"] as? String ?? ""
        self.features = json["features"] as? [String] ?? []
        self.trialButtonText = json["trialButtonText"] as? String ?? ""
        self.subscribeButtonText = json["subscribeButtonText"] as? String ?? ""
        self.miniAppUrl = json["miniAppUrl"] as? String
    }
}

public struct LuxGramBetaConfig: Equatable {
    public let channelId: String?
    public let channelUrl: String?
    public let buildUrl: String?

    public init?(json: [String: Any]) {
        self.channelId = json["channelId"] as? String
        self.channelUrl = json["channelUrl"] as? String
        self.buildUrl = json["buildUrl"] as? String
    }
}

// MARK: - JSON serialization for cache

extension LuxGramUserStatus {
    public func toJSON() -> [String: Any] {
        var dict: [String: Any] = [
            "userId": userId,
            "badges": badges.map { $0.toJSON() },
            "hasActiveSubscription": hasActiveSubscription,
            "hasActiveTrial": hasActiveTrial,
            "trialAvailable": trialAvailable,
            "access": access.toJSON()
        ]
        if let s = subscription { dict["subscription"] = s.toJSON() }
        if let t = trial { dict["trial"] = t.toJSON() }
        if let d = donation { dict["donation"] = d.toJSON() }
        if let p = luxgramPromo { dict["luxgramPromo"] = p.toJSON() }
        if let b = betaConfig { dict["betaConfig"] = b.toJSON() }
        return dict
    }
}

extension LuxGramBadge {
    func toJSON() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id, "name": name, "color": color,
            "displayMode": displayMode, "uiEnabled": uiEnabled
        ]
        if let img = image { dict["image"] = img }
        if let ui = uiConfig { dict["uiConfig"] = ui.toJSON() }
        return dict
    }
}

extension LuxGramBadgeUIConfig {
    func toJSON() -> [String: Any] {
        return [
            "title": title,
            "description": description,
            "buttons": buttons.map { ["label": $0.label, "url": $0.url] }
        ]
    }
}

extension LuxGramSubscription {
    func toJSON() -> [String: Any] {
        return ["planId": planId, "startedAt": startedAt, "expiresAt": expiresAt, "active": active]
    }
}

extension LuxGramTrial {
    func toJSON() -> [String: Any] {
        return ["startedAt": startedAt, "expiresAt": expiresAt, "active": active, "alreadyUsed": alreadyUsed]
    }
}

extension LuxGramDonation {
    func toJSON() -> [String: Any] {
        return ["amount": amount, "lastDonatedAt": lastDonatedAt, "betaAccess": betaAccess]
    }
}

extension LuxGramAccess {
    func toJSON() -> [String: Any] {
        var d: [String: Any] = ["luxgramTab": luxgramTab, "betaBuilds": betaBuilds]
        if let t = accessToken { d["_accessToken"] = t }
        return d
    }
}

extension LuxGramPromo {
    func toJSON() -> [String: Any] {
        var dict: [String: Any] = [
            "title": title, "subtitle": subtitle, "features": features,
            "trialButtonText": trialButtonText, "subscribeButtonText": subscribeButtonText
        ]
        if let url = miniAppUrl { dict["miniAppUrl"] = url }
        return dict
    }
}

extension LuxGramBetaConfig {
    func toJSON() -> [String: Any] {
        var dict: [String: Any] = [:]
        if let v = channelId { dict["channelId"] = v }
        if let v = channelUrl { dict["channelUrl"] = v }
        if let v = buildUrl { dict["buildUrl"] = v }
        return dict
    }
}
