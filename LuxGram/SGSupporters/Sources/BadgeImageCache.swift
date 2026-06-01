import Foundation
import UIKit
import SGConfig
import SGLogging

private let badgeImageCacheDir: String = {
    let caches = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()
    let dir = caches + "/sg_badge_images"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return dir
}()

private var inMemoryCache: [String: UIImage] = [:]
private let cacheQueue = DispatchQueue(label: "sg.badge.image.cache", qos: .userInitiated)

/// Returns cached badge image synchronously (nil if not yet downloaded).
public func cachedBadgeImage(for url: String) -> UIImage? {
    let key = cacheKey(url)
    if let mem = inMemoryCache[key] { return mem }
    let path = badgeImageCacheDir + "/" + key + ".png"
    guard let data = FileManager.default.contents(atPath: path), let img = UIImage(data: data) else { return nil }
    inMemoryCache[key] = img
    return img
}

/// Downloads and caches badge images in the background. Call after check_user.
/// Only fetches URLs that pass isUrlSafeForBadgeImage (same-origin, no SSRF).
public func prefetchBadgeImages(urls: [String], allowedBaseURL: String? = nil) {
    let base = allowedBaseURL ?? SG_CONFIG.supportersApiUrl
    for urlString in urls {
        guard isUrlSafeForBadgeImage(urlString, allowedBaseURL: base) else {
            SGLogger.shared.log("SGSupporters", "BadgeImageCache: skipped unsafe URL")
            continue
        }
        let key = cacheKey(urlString)
        if inMemoryCache[key] != nil { continue }
        let path = badgeImageCacheDir + "/" + key + ".png"
        if FileManager.default.fileExists(atPath: path) {
            if let data = FileManager.default.contents(atPath: path), let img = UIImage(data: data) {
                inMemoryCache[key] = img
            }
            continue
        }
        guard let url = URL(string: urlString) else { continue }
        cacheQueue.async {
            guard let data = try? Data(contentsOf: url), let img = UIImage(data: data) else {
                SGLogger.shared.log("SGSupporters", "BadgeImageCache: failed to download \(urlString)")
                return
            }
            FileManager.default.createFile(atPath: path, contents: img.pngData())
            DispatchQueue.main.async {
                inMemoryCache[key] = img
                NotificationCenter.default.post(name: Notification.Name("SGBadgeImageDidCache"), object: nil)
            }
            SGLogger.shared.log("SGSupporters", "BadgeImageCache: cached \(urlString)")
        }
    }
}

private func cacheKey(_ url: String) -> String {
    let cleaned = url
        .replacingOccurrences(of: "https://", with: "")
        .replacingOccurrences(of: "http://", with: "")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: ".", with: "_")
    return String(cleaned.prefix(120))
}
