import Foundation
import UIKit
import SwiftSignalKit
import SGConfig
import SGLogging
import SGRequests
import SGSimpleSettings

private func supportersRequest(
    _ request: URLRequest,
    baseURL: String
) -> Signal<(Data, URLResponse?), Error?> {
    let pins = SG_CONFIG.supportersPinnedCertHashes
    guard !pins.isEmpty, let host = URL(string: baseURL)?.host else {
        return requestsCustom(request: request)
    }
    return requestsCustomWithPinning(request: request, host: host, pinnedHashes: pins)
}

public enum SupportersAPIError: Error {
    case notConfigured
    case network
    case invalidResponse
    /// HTTP 429 — rate limit. Response body is plain JSON, not encrypted.
    case tooManyRequests
}

/// Single badge from server: id, display name, hex color, display mode, image URL.
public struct SupportersBadge: Equatable {
    public let id: String
    public let name: String
    public let colorHex: String
    public let displayMode: String
    public let imageURL: String?

    public init(id: String, name: String, colorHex: String, displayMode: String = "text", imageURL: String? = nil) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.displayMode = displayMode
        self.imageURL = imageURL
    }
}

/// Checks whether the given user ID is in the supporters list (encrypted request/response).
public func checkIsSupporter(
    userId: Int64,
    baseURL: String,
    aesKey: String,
    hmacKey: String? = nil
) -> Signal<Bool, SupportersAPIError> {
    return Signal { subscriber in
        let urlString = baseURL.hasSuffix("/") ? "\(baseURL)api/encrypted" : "\(baseURL)/api/encrypted"
        guard let url = URL(string: urlString) else {
            subscriber.putError(.notConfigured)
            return EmptyDisposable
        }
        let payload: [String: Any] = [
            "action": "check",
            "payload": ["userId": String(userId)]
        ]
        let body: String
        do {
            body = try SupportersCrypto.encrypt(payload, key: aesKey, hmacKey: hmacKey)
        } catch {
            subscriber.putError(.invalidResponse)
            return EmptyDisposable
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)
        let completed = Atomic<Bool>(value: false)
        let disposable = supportersRequest(request, baseURL: baseURL).start(
            next: { data, response in
                guard completed.swap(true) == false else { return }
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                if code == 429 {
                    subscriber.putError(.tooManyRequests)
                    return
                }
                guard let text = String(data: data, encoding: .utf8) else {
                    subscriber.putError(.invalidResponse)
                    return
                }
                do {
                    let decrypted = try SupportersCrypto.decrypt(text, key: aesKey, hmacKey: hmacKey)
                    let supported = (decrypted["supported"] as? Bool) ?? false
                    subscriber.putNext(supported)
                    subscriber.putCompletion()
                } catch {
                    subscriber.putError(.invalidResponse)
                }
            },
            error: { _ in
                guard completed.swap(true) == false else { return }
                subscriber.putError(.network)
            }
        )
        return ActionDisposable {
            if !completed.with({ $0 }) {
                disposable.dispose()
            }
        }
    }
}

/// Convenience: check using SG_CONFIG supporters URL and key if configured.
public func checkIsSupporterIfConfigured(userId: Int64) -> Signal<Bool, SupportersAPIError>? {
    guard let baseURL = SG_CONFIG.supportersApiUrl, !baseURL.isEmpty,
          let key = SG_CONFIG.supportersAesKey, !key.isEmpty else {
        return nil
    }
    return checkIsSupporter(userId: userId, baseURL: baseURL, aesKey: key, hmacKey: SG_CONFIG.supportersHmacKey)
}

private let kSupportersCacheAccount = "sg_supporters_cache"

private func loadCacheFile() -> [String: Any] {
    supportersSecureLoadJSON(account: kSupportersCacheAccount) ?? [:]
}

private func saveCacheFile(_ dict: [String: Any]) {
    _ = supportersSecureSaveJSON(dict, account: kSupportersCacheAccount)
}

/// Fetches badges and assignments (encrypted). Used to populate cache.
public func fetchBadges(baseURL: String, aesKey: String, hmacKey: String? = nil) -> Signal<(badges: [SupportersBadge], assignments: [String: [String]]), SupportersAPIError> {
    return Signal { subscriber in
        let urlString = baseURL.hasSuffix("/") ? "\(baseURL)api/encrypted" : "\(baseURL)/api/encrypted"
        guard let url = URL(string: urlString) else {
            subscriber.putError(.notConfigured)
            return EmptyDisposable
        }
        let payload: [String: Any] = ["action": "list_badges", "payload": [:] as [String: Any]]
        let body: String
        do {
            body = try SupportersCrypto.encrypt(payload, key: aesKey, hmacKey: hmacKey)
        } catch {
            subscriber.putError(.invalidResponse)
            return EmptyDisposable
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)
        SGLogger.shared.log("SGSupporters", "fetchBadges: POST \(urlString)")
        let completed = Atomic<Bool>(value: false)
        let disposable = supportersRequest(request, baseURL: baseURL).start(
            next: { data, response in
                guard completed.swap(true) == false else { return }
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                SGLogger.shared.log("SGSupporters", "fetchBadges: response status=\(code), bodyLen=\(data.count)")
                if code == 429 {
                    subscriber.putError(.tooManyRequests)
                    return
                }
                guard let text = String(data: data, encoding: .utf8) else {
                    SGLogger.shared.log("SGSupporters", "fetchBadges: body not UTF-8")
                    subscriber.putError(.invalidResponse)
                    return
                }
                do {
                    let decrypted = try SupportersCrypto.decrypt(text, key: aesKey, hmacKey: hmacKey)
                    let badgesRaw = decrypted["badges"] as? [[String: Any]] ?? []
                    let assignmentsRaw = decrypted["assignments"] as? [String: [String]] ?? [:]
                    let badges: [SupportersBadge] = badgesRaw.compactMap { b in
                        guard let id = b["id"] as? String else { return nil }
                        let name = b["name"] as? String ?? id
                        let colorHex = b["color"] as? String ?? "#34C759"
                        let displayMode = b["displayMode"] as? String ?? "text"
                        let imageURL = b["image"] as? String
                        return SupportersBadge(id: id, name: name, colorHex: colorHex, displayMode: displayMode, imageURL: imageURL)
                    }
                    SGLogger.shared.log("SGSupporters", "fetchBadges: decrypted ok — badges=\(badges.count)")
                    subscriber.putNext((badges: badges, assignments: assignmentsRaw))
                    subscriber.putCompletion()
                } catch {
                    SGLogger.shared.log("SGSupporters", "fetchBadges: decrypt failed — \(String(describing: error))")
                    subscriber.putError(.invalidResponse)
                }
            },
            error: { err in
                guard completed.swap(true) == false else { return }
                SGLogger.shared.log("SGSupporters", "fetchBadges: network error — \(String(describing: err))")
                subscriber.putError(.network)
            }
        )
        return ActionDisposable {
            if !completed.with({ $0 }) {
                disposable.dispose()
            }
        }
    }
}

func setCachedBadges(_ badges: [SupportersBadge]) {
    var cache = loadCacheFile()
    cache["badges"] = badges.map { b -> [String: Any] in
        var d: [String: Any] = ["id": b.id, "name": b.name, "color": b.colorHex, "displayMode": b.displayMode]
        if let img = b.imageURL { d["image"] = img }
        return d
    }
    saveCacheFile(cache)
}

func setCachedAssignments(_ assignments: [String: [String]]) {
    var cache = loadCacheFile()
    cache["assignments"] = assignments
    saveCacheFile(cache)
}

private func loadCachedBadges() -> [SupportersBadge] {
    let cache = loadCacheFile()
    guard let raw = cache["badges"] as? [[String: Any]] else { return [] }
    return raw.compactMap { b in
        guard let id = b["id"] as? String else { return nil }
        let name = b["name"] as? String ?? id
        let colorHex = b["color"] as? String ?? "#34C759"
        let displayMode = b["displayMode"] as? String ?? "text"
        let imageURL = b["image"] as? String
        return SupportersBadge(id: id, name: name, colorHex: colorHex, displayMode: displayMode, imageURL: imageURL)
    }
}

private func loadCachedAssignments() -> [String: [String]] {
    let cache = loadCacheFile()
    guard let raw = cache["assignments"] as? [String: [String]] else { return [:] }
    return raw
}

private let refreshStarted = Atomic<Bool>(value: false)

/// Call when app becomes active or at launch to refresh badges cache. Uses SG_CONFIG if set.
public func refreshSupportersCacheIfConfigured() {
    guard let baseURL = SG_CONFIG.supportersApiUrl, !baseURL.isEmpty,
          let key = SG_CONFIG.supportersAesKey, !key.isEmpty else {
        SGLogger.shared.log("SGSupporters", "refreshSupportersCacheIfConfigured: skip — URL or key not set (url=\(SG_CONFIG.supportersApiUrl ?? "nil"), key=\(SG_CONFIG.supportersAesKey != nil ? "***" : "nil"))")
        return
    }
    if refreshStarted.swap(true) {
        SGLogger.shared.log("SGSupporters", "refreshSupportersCacheIfConfigured: refresh already in progress, skip")
        return
    }
    SGLogger.shared.log("SGSupporters", "refreshSupportersCacheIfConfigured: start fetch \(baseURL)")
    _ = fetchBadges(baseURL: baseURL, aesKey: key, hmacKey: SG_CONFIG.supportersHmacKey).start(next: { data in
        setCachedBadges(data.badges)
        setCachedAssignments(data.assignments)
        let uniqueUsers = Set(data.assignments.values.flatMap { $0 })
        SGLogger.shared.log("SGSupporters", "refreshSupportersCacheIfConfigured: ok — badges=\(data.badges.count), unique users=\(uniqueUsers.count)")
        // Prefetch image badges from list_badges result
        let imageURLs = data.badges.compactMap { badge -> String? in
            guard badge.displayMode == "image", let img = badge.imageURL else { return nil }
            if img.hasPrefix("http") {
                return isUrlSafeForBadgeImage(img, allowedBaseURL: baseURL) ? img : nil
            }
            guard img.hasPrefix("/") else { return nil }
            let baseNorm = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
            let full = baseNorm + img
            return isUrlSafeForBadgeImage(full, allowedBaseURL: baseURL) ? full : nil
        }
        if !imageURLs.isEmpty {
            prefetchBadgeImages(urls: imageURLs, allowedBaseURL: baseURL)
        }
    }, error: { err in
        _ = refreshStarted.swap(false)
        SGLogger.shared.log("SGSupporters", "refreshSupportersCacheIfConfigured: error — \(String(describing: err))")
    }, completed: {
        _ = refreshStarted.swap(false)
        SGLogger.shared.log("SGSupporters", "refreshSupportersCacheIfConfigured: completed")
    })
}

/// Full badge info for a user: name, color, display mode, image URL. Merges list_badges cache with check_user cache.
public func badges(forUserId userId: Int64) -> [(name: String, color: UIColor, displayMode: String, imageURL: String?)] {
    let userIdStr = String(userId)

    let baseURL = SG_CONFIG.supportersApiUrl
    if let status = loadCachedUserStatus(userId: userIdStr) {
        return status.badges.map { badge in
            let color = UIColor(hex: badge.color) ?? UIColor(red: 52/255, green: 199/255, blue: 89/255, alpha: 1)
            var fullImageURL: String? = nil
            if let img = badge.image {
                if img.hasPrefix("http") {
                    fullImageURL = isUrlSafeForBadgeImage(img, allowedBaseURL: baseURL) ? img : nil
                } else if let base = baseURL, img.hasPrefix("/") {
                    let baseNorm = base.hasSuffix("/") ? String(base.dropLast()) : base
                    let full = baseNorm + img
                    fullImageURL = isUrlSafeForBadgeImage(full, allowedBaseURL: base) ? full : nil
                }
            }
            return (name: badge.name, color: color, displayMode: badge.displayMode, imageURL: fullImageURL)
        }
    }

    let badgesList = loadCachedBadges()
    let assignments = loadCachedAssignments()
    var result: [(name: String, color: UIColor, displayMode: String, imageURL: String?)] = []
    for badge in badgesList {
        let userIds = assignments[badge.id] ?? []
        if userIds.contains(userIdStr) {
            let color = UIColor(hex: badge.colorHex) ?? UIColor(red: 52/255, green: 199/255, blue: 89/255, alpha: 1)
            var fullImageURL: String? = nil
            if let img = badge.imageURL {
                if img.hasPrefix("http") {
                    fullImageURL = isUrlSafeForBadgeImage(img, allowedBaseURL: baseURL) ? img : nil
                } else if let base = baseURL, img.hasPrefix("/") {
                    let baseNorm = base.hasSuffix("/") ? String(base.dropLast()) : base
                    let full = baseNorm + img
                    fullImageURL = isUrlSafeForBadgeImage(full, allowedBaseURL: base) ? full : nil
                }
            }
            result.append((name: badge.name, color: color, displayMode: badge.displayMode, imageURL: fullImageURL))
        }
    }
    if !result.isEmpty {
        SGLogger.shared.log("SGSupporters", "badges(userId=\(userIdStr)): \(result.map { $0.name }.joined(separator: ", "))")
    }
    return result
}

/// Legacy: true if user has at least one badge.
/// Integrity-gated: also verifies text segment checksum.
public func isSupporter(userId: Int64) -> Bool {
    guard SupportersIntegrity.textOK() else { return false }
    return !badges(forUserId: userId).isEmpty
}

private let kUserStatusCacheAccount = "sg_luxgram_user_status"
private let userStatusCacheLock = NSLock()

private let kVerifiedUserIds = "_verified"

private func loadAllCachedUserStatuses() -> [String: [String: Any]] {
    guard let j = supportersSecureLoadJSON(account: kUserStatusCacheAccount) else {
        return [:]
    }
    var result: [String: [String: Any]] = [:]
    for (key, value) in j {
        if key == "_multi" || key == kVerifiedUserIds { continue }
        if let statusDict = value as? [String: Any] {
            result[key] = statusDict
        }
    }
    return result
}

private func loadVerifiedUserIds() -> Set<String> {
    guard let j = supportersSecureLoadJSON(account: kUserStatusCacheAccount) else {
        return []
    }
    if let arr = j[kVerifiedUserIds] as? [String], !arr.isEmpty {
        return Set(arr)
    }
    // Backward compat: no _verified yet — treat existing entries as verified
    var keys: Set<String> = []
    for (key, value) in j {
        if key != "_multi" && key != kVerifiedUserIds, value is [String: Any] {
            keys.insert(key)
        }
    }
    return keys
}

private func loadCachedUserStatus(userId: String? = nil) -> LuxGramUserStatus? {
    let all = loadAllCachedUserStatuses()
    if let userId = userId {
        guard let json = all[userId] else { return nil }
        return LuxGramUserStatus(json: json)
    }
    // Return first available status (backward compat)
    guard let first = all.values.first else { return nil }
    return LuxGramUserStatus(json: first)
}

private func saveCachedUserStatus(_ status: LuxGramUserStatus) {
    userStatusCacheLock.lock()
    defer { userStatusCacheLock.unlock() }
    var all: [String: [String: Any]] = [:]
    var verified: Set<String> = []
    if let j = supportersSecureLoadJSON(account: kUserStatusCacheAccount) {
        verified = Set((j[kVerifiedUserIds] as? [String]) ?? [])
        for (key, value) in j {
            if key == "_multi" || key == kVerifiedUserIds { continue }
            if let statusDict = value as? [String: Any] {
                all[key] = statusDict
            }
        }
    }
    all[status.userId] = status.toJSON()
    verified.insert(status.userId)
    var dict: [String: Any] = ["_multi": true, kVerifiedUserIds: Array(verified)]
    for (key, value) in all {
        dict[key] = value
    }
    _ = supportersSecureSaveJSON(dict, account: kUserStatusCacheAccount)
}

/// Cached LuxGram user status for a specific user ID (or first available).
public func cachedLuxGramUserStatus(userId: String? = nil) -> LuxGramUserStatus? {
    return loadCachedUserStatus(userId: userId)
}

/// Aggregate access across cached accounts. If validUserIds is set, only those accounts are considered.
/// Only entries from our check_user API (_verified) are trusted — prevents injection of fake IDs.
/// Access is verified through multiple independent integrity layers (token + text checksum + accumulator).
public func cachedAggregateAccess(validUserIds: Set<String>? = nil) -> LuxGramAccess {
    var all = loadAllCachedUserStatuses()
    let verified = loadVerifiedUserIds()
    all = all.filter { verified.contains($0.key) }
    if let ids = validUserIds {
        all = all.filter { ids.contains($0.key) }
    }
    var luxgramTab = false
    var betaBuilds = false
    var tokenVerified = false

    for (userId, json) in all {
        let status = LuxGramUserStatus(json: json)
        if status.access.luxgramTab { luxgramTab = true }
        if status.access.betaBuilds { betaBuilds = true }

        // Integrity layer: verify per-user access token
        if let tokenB64 = status.access.accessToken,
           let tokenData = Data(base64Encoded: tokenB64),
           let hmacB64 = SG_CONFIG.supportersHmacKey ?? SG_CONFIG.supportersAesKey {
            let keyData = SupportersCrypto.normalizeKeyData(hmacB64)
            if SupportersIntegrity.verifyAccessToken(
                tokenData,
                userId: userId,
                luxgramTab: status.access.luxgramTab,
                betaBuilds: status.access.betaBuilds,
                hmacKeyData: keyData
            ) {
                tokenVerified = true
            } else {
                // Token mismatch — flags were tampered in cache
                SGLogger.shared.log("SGIntegrity", "access token mismatch for userId=\(userId)")
                luxgramTab = false
                betaBuilds = false
            }
        }
    }

    // Integrity layer: text segment checksum
    if !SupportersIntegrity.textOK() {
        SGLogger.shared.log("SGIntegrity", "text segment modified — revoking access")
        luxgramTab = false
        betaBuilds = false
    }

    // Re-validate accumulator from cached state
    if tokenVerified {
        SupportersIntegrity.validate(
            cryptoSucceeded: tokenVerified,
            cacheDecrypted: !all.isEmpty,
            luxgramTab: luxgramTab,
            betaBuilds: betaBuilds
        )
    }

    return LuxGramAccess(json: ["luxgramTab": luxgramTab, "betaBuilds": betaBuilds])
}

/// Returns true if ANY cached account has an active subscription.
/// Integrity-gated: also verifies text segment checksum.
public func hasAnyCachedSubscription() -> Bool {
    guard SupportersIntegrity.textOK() else { return false }
    let all = loadAllCachedUserStatuses()
    return all.values.contains { json in
        LuxGramUserStatus(json: json).hasActiveSubscription
    }
}

/// Returns true if ANY cached account has an active trial.
/// Integrity-gated: also verifies text segment checksum.
public func hasAnyCachedTrial() -> Bool {
    guard SupportersIntegrity.textOK() else { return false }
    let all = loadAllCachedUserStatuses()
    return all.values.contains { json in
        LuxGramUserStatus(json: json).hasActiveTrial
    }
}

/// Returns the first betaConfig found across cached accounts that has betaBuilds access.
/// Integrity-gated: returns nil if text segment has been modified.
public func cachedAggregateBetaConfig(validUserIds: Set<String>? = nil) -> LuxGramBetaConfig? {
    guard SupportersIntegrity.textOK() else { return nil }
    var all = loadAllCachedUserStatuses()
    let verified = loadVerifiedUserIds()
    all = all.filter { verified.contains($0.key) }
    if let ids = validUserIds {
        all = all.filter { ids.contains($0.key) }
    }
    for (_, json) in all {
        let status = LuxGramUserStatus(json: json)
        if status.access.betaBuilds, let config = status.betaConfig {
            return config
        }
    }
    return nil
}

/// Returns the first promo found across cached accounts (for paywall display).
public func cachedAggregatePromo() -> (promo: LuxGramPromo, trialAvailable: Bool)? {
    let all = loadAllCachedUserStatuses()
    for (_, json) in all {
        let status = LuxGramUserStatus(json: json)
        if let promo = status.luxgramPromo {
            return (promo: promo, trialAvailable: status.trialAvailable)
        }
    }
    return nil
}

/// Full user status: badges, subscription, trial, access, promo, beta config.
public func checkUser(
    userId: Int64,
    baseURL: String,
    aesKey: String,
    hmacKey: String? = nil
) -> Signal<LuxGramUserStatus, SupportersAPIError> {
    return encryptedAPICall(
        action: "check_user",
        payload: ["userId": String(userId)],
        baseURL: baseURL,
        aesKey: aesKey,
        hmacKey: hmacKey
    ) |> map { json in
        // Generate integrity access token and inject into JSON before parsing
        var enrichedJSON = json
        let userId = json["userId"] as? String ?? String(userId)
        let accessJSON = json["access"] as? [String: Any] ?? [:]
        let tab = accessJSON["luxgramTab"] as? Bool ?? false
        let beta = accessJSON["betaBuilds"] as? Bool ?? false
        if let hmacB64 = SG_CONFIG.supportersHmacKey ?? SG_CONFIG.supportersAesKey {
            let keyData = SupportersCrypto.normalizeKeyData(hmacB64)
            let token = SupportersIntegrity.computeAccessToken(
                userId: userId, luxgramTab: tab, betaBuilds: beta, hmacKeyData: keyData
            )
            var accessWithToken = accessJSON
            accessWithToken["_accessToken"] = token.base64EncodedString()
            enrichedJSON["access"] = accessWithToken
        }

        let status = LuxGramUserStatus(json: enrichedJSON)
        saveCachedUserStatus(status)

        // Integrity: validate all layers after successful check_user
        SupportersIntegrity.validate(
            cryptoSucceeded: true,
            cacheDecrypted: true,
            luxgramTab: tab,
            betaBuilds: beta
        )

        // Parse gated features from check_user response (if server embeds them).
        // Write to SGSimpleSettings on main queue to avoid threading issues.
        if let gatedArray = json["gatedFeatures"] as? [[String: Any]] {
            let features = gatedArray.compactMap { f -> (key: String, deeplinkPath: String)? in
                guard let key = f["key"] as? String,
                      let path = f["deeplinkPath"] as? String else { return nil }
                return (key: key, deeplinkPath: path)
            }
            DispatchQueue.main.async {
                SGSimpleSettings.shared.updateGatedFeatures(features)
            }
            SGLogger.shared.log("SGSupporters", "check_user: parsed \(features.count) gatedFeatures")
        }
        if let unlockedArray = json["unlockedFeatures"] as? [String] {
            DispatchQueue.main.async {
                var current = SGSimpleSettings.shared.unlockedFeatureKeys
                for k in unlockedArray {
                    if !current.contains(k) { current.append(k) }
                }
                SGSimpleSettings.shared.unlockedFeatureKeys = current
            }
            SGLogger.shared.log("SGSupporters", "check_user: parsed \(unlockedArray.count) unlockedFeatures")
        }

        return status
    }
}

/// Convenience: check_user using SG_CONFIG.
public func checkUserIfConfigured(userId: Int64) -> Signal<LuxGramUserStatus, SupportersAPIError>? {
    guard let baseURL = SG_CONFIG.supportersApiUrl, !baseURL.isEmpty,
          let key = SG_CONFIG.supportersAesKey, !key.isEmpty else {
        return nil
    }
    return checkUser(userId: userId, baseURL: baseURL, aesKey: key, hmacKey: SG_CONFIG.supportersHmacKey)
}

/// Start 7-day trial (one-time per Telegram ID).
public func startTrial(
    userId: Int64,
    baseURL: String,
    aesKey: String,
    hmacKey: String? = nil
) -> Signal<LuxGramTrial?, SupportersAPIError> {
    return encryptedAPICall(
        action: "start_trial",
        payload: ["userId": String(userId)],
        baseURL: baseURL,
        aesKey: aesKey,
        hmacKey: hmacKey
    ) |> map { json in
        (json["trial"] as? [String: Any]).flatMap { LuxGramTrial(json: $0) }
    }
}

/// Convenience: start_trial using SG_CONFIG.
public func startTrialIfConfigured(userId: Int64) -> Signal<LuxGramTrial?, SupportersAPIError>? {
    guard let baseURL = SG_CONFIG.supportersApiUrl, !baseURL.isEmpty,
          let key = SG_CONFIG.supportersAesKey, !key.isEmpty else {
        return nil
    }
    return startTrial(userId: userId, baseURL: baseURL, aesKey: key, hmacKey: SG_CONFIG.supportersHmacKey)
}

/// On app launch: call check_user and refresh badges cache.
public func refreshLuxGramStatusIfConfigured(userId: Int64) {
    guard let signal = checkUserIfConfigured(userId: userId) else { return }
    SGLogger.shared.log("SGSupporters", "refreshLuxGramStatus: starting check_user for \(userId)")
    _ = signal.start(next: { status in
        SGLogger.shared.log("SGSupporters", "refreshLuxGramStatus: ok — access.luxgramTab=\(status.access.luxgramTab), badges=\(status.badges.count), sub=\(status.hasActiveSubscription), trial=\(status.hasActiveTrial)")
        let baseURL = SG_CONFIG.supportersApiUrl
        let imageURLs = status.badges.compactMap { badge -> String? in
            guard badge.displayMode == "image", let img = badge.image else { return nil }
            if img.hasPrefix("http") {
                return isUrlSafeForBadgeImage(img, allowedBaseURL: baseURL) ? img : nil
            }
            guard let base = baseURL, img.hasPrefix("/") else { return nil }
            let baseNorm = base.hasSuffix("/") ? String(base.dropLast()) : base
            let full = baseNorm + img
            return isUrlSafeForBadgeImage(full, allowedBaseURL: base) ? full : nil
        }
        if !imageURLs.isEmpty {
            prefetchBadgeImages(urls: imageURLs, allowedBaseURL: baseURL)
        }
    }, error: { err in
        let msg: String
        if case .tooManyRequests = err { msg = "429 Too Many Requests" }
        else { msg = String(describing: err) }
        SGLogger.shared.log("SGSupporters", "refreshLuxGramStatus: error — \(msg)")
    })
}

/// Prune cache to only keep statuses for accounts that exist in the app.
public func pruneCachedUserStatuses(keepingUserIds: Set<String>) {
    userStatusCacheLock.lock()
    defer { userStatusCacheLock.unlock() }
    guard let j = supportersSecureLoadJSON(account: kUserStatusCacheAccount) else { return }
    var all: [String: [String: Any]] = [:]
    var verified = Set<String>((j[kVerifiedUserIds] as? [String]) ?? [])
    for (key, value) in j {
        if key == "_multi" || key == kVerifiedUserIds { continue }
        if let statusDict = value as? [String: Any] {
            all[key] = statusDict
        }
    }
    let before = all.count
    all = all.filter { keepingUserIds.contains($0.key) }
    verified = verified.intersection(keepingUserIds)
    if all.count != before {
        var dict: [String: Any] = ["_multi": true, kVerifiedUserIds: Array(verified)]
        for (key, value) in all {
            dict[key] = value
        }
        _ = supportersSecureSaveJSON(dict, account: kUserStatusCacheAccount)
        SGLogger.shared.log("SGSupporters", "pruneCachedUserStatuses: removed \(before - all.count) stale entries")
    }
}

/// Fetches check_user for all userIds in parallel. Completes when all finish (success or error).
/// Use before checking cachedAggregateAccess when current account has no beta.
public func fetchAllUserStatusesIfConfigured(userIds: [Int64]) -> Signal<Never, NoError> {
    return Signal { subscriber in
        let total = userIds.count
        if total == 0 {
            subscriber.putCompletion()
            return EmptyDisposable
        }
        let completed = Atomic<Int>(value: 0)
        let disposable = DisposableSet()
        for userId in userIds {
            guard let s = checkUserIfConfigured(userId: userId) else {
                if completed.modify({ $0 + 1 }) == total { subscriber.putCompletion() }
                continue
            }
            let d = s.start(error: { _ in
                if completed.modify({ $0 + 1 }) == total { subscriber.putCompletion() }
            }, completed: {
                if completed.modify({ $0 + 1 }) == total { subscriber.putCompletion() }
            })
            disposable.add(d)
        }
        return disposable
    }
}

/// Check all accounts at once (multi-account access support). Prunes cache to match app accounts.
public func refreshLuxGramStatusForAllAccounts(userIds: [Int64]) {
    SGLogger.shared.log("SGSupporters", "refreshLuxGramStatusForAllAccounts: \(userIds.count) accounts")
    let validUserIds = Set(userIds.map { String($0) })
    pruneCachedUserStatuses(keepingUserIds: validUserIds)
    for userId in userIds {
        refreshLuxGramStatusIfConfigured(userId: userId)
    }
}

private func encryptedAPICall(
    action: String,
    payload: [String: Any],
    baseURL: String,
    aesKey: String,
    hmacKey: String? = nil
) -> Signal<[String: Any], SupportersAPIError> {
    return Signal { subscriber in
        let urlString = baseURL.hasSuffix("/") ? "\(baseURL)api/encrypted" : "\(baseURL)/api/encrypted"
        guard let url = URL(string: urlString) else {
            subscriber.putError(.notConfigured)
            return EmptyDisposable
        }
        let requestPayload: [String: Any] = ["action": action, "payload": payload]
        let body: String
        do {
            body = try SupportersCrypto.encrypt(requestPayload, key: aesKey, hmacKey: hmacKey)
        } catch {
            subscriber.putError(.invalidResponse)
            return EmptyDisposable
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)
        SGLogger.shared.log("SGSupporters", "\(action): POST \(urlString)")
        let completed = Atomic<Bool>(value: false)
        let disposable = supportersRequest(request, baseURL: baseURL).start(
            next: { data, response in
                guard completed.swap(true) == false else { return }
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                SGLogger.shared.log("SGSupporters", "\(action): status=\(code)")
                if code == 429 {
                    subscriber.putError(.tooManyRequests)
                    return
                }
                guard let text = String(data: data, encoding: .utf8) else {
                    subscriber.putError(.invalidResponse)
                    return
                }
                do {
                    let decrypted = try SupportersCrypto.decrypt(text, key: aesKey, hmacKey: hmacKey)
                    if let ok = decrypted["ok"] as? Bool, !ok {
                        let errMsg = decrypted["error"] as? String ?? "Unknown error"
                        SGLogger.shared.log("SGSupporters", "\(action): server error — \(errMsg)")
                        subscriber.putError(.invalidResponse)
                        return
                    }
                    // Integrity: seal text checksum on first successful crypto verification
                    SupportersIntegrity.seal()
                    subscriber.putNext(decrypted)
                    subscriber.putCompletion()
                } catch {
                    SGLogger.shared.log("SGSupporters", "\(action): decrypt failed — \(String(describing: error))")
                    subscriber.putError(.invalidResponse)
                }
            },
            error: { err in
                guard completed.swap(true) == false else { return }
                SGLogger.shared.log("SGSupporters", "\(action): network error — \(String(describing: err))")
                subscriber.putError(.network)
            }
        )
        return ActionDisposable {
            if !completed.with({ $0 }) {
                disposable.dispose()
            }
        }
    }
}

/// Fetch list of gated features from server (encrypted).
public func fetchGatedFeatures(
    baseURL: String,
    aesKey: String,
    hmacKey: String? = nil
) -> Signal<[(key: String, deeplinkPath: String)], SupportersAPIError> {
    return encryptedAPICall(
        action: "gated_features",
        payload: [:],
        baseURL: baseURL,
        aesKey: aesKey,
        hmacKey: hmacKey
    ) |> map { json in
        guard let features = json["gatedFeatures"] as? [[String: Any]] else { return [] }
        return features.compactMap { f in
            guard let key = f["key"] as? String,
                  let path = f["deeplinkPath"] as? String else { return nil }
            return (key: key, deeplinkPath: path)
        }
    }
}

/// Fetch unlocked features for a specific user (encrypted).
public func fetchUnlockedFeatures(
    userId: Int64,
    baseURL: String,
    aesKey: String,
    hmacKey: String? = nil
) -> Signal<[String], SupportersAPIError> {
    return encryptedAPICall(
        action: "unlocked_features",
        payload: ["userId": String(userId)],
        baseURL: baseURL,
        aesKey: aesKey,
        hmacKey: hmacKey
    ) |> map { json in
        return json["unlockedKeys"] as? [String] ?? []
    }
}

/// Unlock a feature via deeplink path (encrypted).
/// Returns array of unlocked keys (single key for individual paths, multiple for group paths like "unlock-all", "ghost-mode").
public func unlockFeature(
    userId: Int64,
    deeplinkPath: String,
    baseURL: String,
    aesKey: String,
    hmacKey: String? = nil
) -> Signal<[String], SupportersAPIError> {
    return encryptedAPICall(
        action: "unlock_feature",
        payload: ["userId": String(userId), "deeplinkPath": deeplinkPath],
        baseURL: baseURL,
        aesKey: aesKey,
        hmacKey: hmacKey
    ) |> map { json in
        // Group unlock: server returns "unlockedKeys": ["key1", "key2", ...]
        if let keys = json["unlockedKeys"] as? [String] {
            return keys
        }
        // Single unlock: server returns "key": "singleKey"
        if let key = json["key"] as? String {
            return [key]
        }
        return []
    }
}

/// Convenience: fetch gated features using SG_CONFIG.
public func fetchGatedFeaturesIfConfigured() -> Signal<[(key: String, deeplinkPath: String)], SupportersAPIError>? {
    guard let baseURL = SG_CONFIG.supportersApiUrl, !baseURL.isEmpty,
          let key = SG_CONFIG.supportersAesKey, !key.isEmpty else {
        return nil
    }
    return fetchGatedFeatures(baseURL: baseURL, aesKey: key, hmacKey: SG_CONFIG.supportersHmacKey)
}

/// Convenience: fetch unlocked features using SG_CONFIG.
public func fetchUnlockedFeaturesIfConfigured(userId: Int64) -> Signal<[String], SupportersAPIError>? {
    guard let baseURL = SG_CONFIG.supportersApiUrl, !baseURL.isEmpty,
          let key = SG_CONFIG.supportersAesKey, !key.isEmpty else {
        return nil
    }
    return fetchUnlockedFeatures(userId: userId, baseURL: baseURL, aesKey: key, hmacKey: SG_CONFIG.supportersHmacKey)
}

/// Convenience: unlock feature using SG_CONFIG.
public func unlockFeatureIfConfigured(userId: Int64, deeplinkPath: String) -> Signal<[String], SupportersAPIError>? {
    guard let baseURL = SG_CONFIG.supportersApiUrl, !baseURL.isEmpty,
          let key = SG_CONFIG.supportersAesKey, !key.isEmpty else {
        return nil
    }
    return unlockFeature(userId: userId, deeplinkPath: deeplinkPath, baseURL: baseURL, aesKey: key, hmacKey: SG_CONFIG.supportersHmacKey)
}

/// Refresh gated features cache: fetch gated list + unlocked list, save to SimpleSettings.
public func refreshGatedFeaturesCache(userId: Int64) {
    guard let gatedSignal = fetchGatedFeaturesIfConfigured() else { return }
    SGLogger.shared.log("SGSupporters", "refreshGatedFeatures: starting")
    _ = gatedSignal.start(next: { features in
        DispatchQueue.main.async {
            SGSimpleSettings.shared.updateGatedFeatures(features)
        }
        SGLogger.shared.log("SGSupporters", "refreshGatedFeatures: \(features.count) gated features cached")

        // Now fetch unlocked for this user
        guard let unlockedSignal = fetchUnlockedFeaturesIfConfigured(userId: userId) else { return }
        _ = unlockedSignal.start(next: { keys in
            DispatchQueue.main.async {
                var current = SGSimpleSettings.shared.unlockedFeatureKeys
                for k in keys {
                    if !current.contains(k) { current.append(k) }
                }
                SGSimpleSettings.shared.unlockedFeatureKeys = current
            }
            SGLogger.shared.log("SGSupporters", "refreshGatedFeatures: \(keys.count) unlocked features synced")
        }, error: { err in
            SGLogger.shared.log("SGSupporters", "refreshGatedFeatures: unlocked fetch error — \(err)")
        })
    }, error: { err in
        SGLogger.shared.log("SGSupporters", "refreshGatedFeatures: gated fetch error — \(err)")
    })
}

private extension UIColor {
    convenience init?(hex: String) {
        var hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if hex.hasPrefix("#") { hex = String(hex.dropFirst()) }
        if hex.count == 6 {
            hex += "FF"
        } else if hex.count != 8 {
            return nil
        }
        guard let value = UInt32(hex, radix: 16) else { return nil }
        let r = CGFloat((value >> 24) & 0xFF) / 255
        let g = CGFloat((value >> 16) & 0xFF) / 255
        let b = CGFloat((value >> 8) & 0xFF) / 255
        let a = CGFloat(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
