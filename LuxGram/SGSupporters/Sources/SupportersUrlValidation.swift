import Foundation

/// URL validation for supporters API responses. Prevents injection (javascript:, file:, etc.) and SSRF.

private let allowedExternalSchemes = ["http", "https", "tg"]
private let blockedHosts: Set<String> = [
    "localhost", "127.0.0.1", "0.0.0.0",
    "169.254.169.254",  // cloud metadata
    "metadata.google.internal",
    "::1"
]

/// Returns true if URL is safe to open externally (badge buttons, miniAppUrl, beta links).
/// Only allows http, https, tg schemes. Blocks javascript:, file:, data:, etc.
public func isUrlSafeForExternalOpen(_ urlString: String) -> Bool {
    let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    guard let url = URL(string: trimmed) else { return false }
    guard let scheme = url.scheme?.lowercased() else { return false }
    guard allowedExternalSchemes.contains(scheme) else { return false }
    if let host = url.host?.lowercased(), blockedHosts.contains(host) {
        return false
    }
    return true
}

/// Returns true if URL is safe to fetch as badge image. Prevents SSRF.
/// Only allows http/https to same origin (supportersApiUrl) or explicitly allowed hosts.
public func isUrlSafeForBadgeImage(_ urlString: String, allowedBaseURL: String?) -> Bool {
    let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    if trimmed.hasPrefix("/") {
        guard let base = allowedBaseURL else { return false }
        let baseNorm = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard let baseUrl = URL(string: baseNorm), let host = baseUrl.host else { return false }
        return !blockedHosts.contains(host.lowercased())
    }
    guard let url = URL(string: trimmed),
          let scheme = url.scheme?.lowercased(),
          (scheme == "http" || scheme == "https"),
          let host = url.host?.lowercased() else {
        return false
    }
    guard !blockedHosts.contains(host) else { return false }
    if host == "127.0.0.1" || host.hasPrefix("192.168.") || host.hasPrefix("10.") || host.hasPrefix("172.") {
        return false
    }
    if let base = allowedBaseURL, let baseUrl = URL(string: base), let baseHost = baseUrl.host?.lowercased() {
        return host == baseHost || host.hasSuffix("." + baseHost)
    }
    return true
}
