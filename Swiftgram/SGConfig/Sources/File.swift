import Foundation
import BuildConfig

public struct SGConfig: Codable {
    public static let isBetaBuild: Bool = true
    public var apiUrl: String = "https://api.swiftgram.app"
    public var webappUrl: String = "https://my.swiftgram.app"
    public var botUsername: String = "LuxGramBot"
    public var publicKey: String?
    public var iaps: [String] = []
    public var supportersApiUrl: String? = nil
    public var supportersAesKey: String? = nil
    public var supportersHmacKey: String? = nil
    public var supportersPinnedCertHashes: [String] = []
    public var demoLoginBackendUrl: String? = nil
    public var demoLoginPhonePrefix: String? = nil
}

private func parseSGConfig(_ jsonString: String) -> SGConfig {
    let jsonData = Data(jsonString.utf8)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return (try? decoder.decode(SGConfig.self, from: jsonData)) ?? SGConfig()
}

private let baseAppBundleId = Bundle.main.bundleIdentifier!
private let buildConfig = BuildConfig(baseAppBundleId: baseAppBundleId)
public let SG_CONFIG: SGConfig = parseSGConfig(buildConfig.sgConfig)
public let SG_API_WEBAPP_URL_PARSED = URL(string: SG_CONFIG.webappUrl)!
