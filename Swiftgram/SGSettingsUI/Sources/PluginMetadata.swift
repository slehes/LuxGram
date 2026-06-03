import Foundation

/// Metadata parsed from a .plugin file (exteraGram plugin format).
public struct PluginMetadata: Codable, Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let version: String
    public let author: String
    /// Icon reference e.g. "ApplicationEmoji/141" or "glePlugins/1".
    public let iconRef: String?
    public let minVersion: String?
    /// If true, plugin modifies profile display (Fake Profile–style). App reads settings and applies via userDisplayRunner.
    public let hasUserDisplay: Bool

    public init(id: String, name: String, description: String, version: String, author: String, iconRef: String? = nil, minVersion: String? = nil, hasUserDisplay: Bool = false) {
        self.id = id
        self.name = name
        self.description = description
        self.version = version
        self.author = author
        self.iconRef = iconRef
        self.minVersion = minVersion
        self.hasUserDisplay = hasUserDisplay
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decode(String.self, forKey: .description)
        version = try c.decode(String.self, forKey: .version)
        author = try c.decode(String.self, forKey: .author)
        iconRef = try c.decodeIfPresent(String.self, forKey: .iconRef)
        minVersion = try c.decodeIfPresent(String.self, forKey: .minVersion)
        hasUserDisplay = try c.decodeIfPresent(Bool.self, forKey: .hasUserDisplay) ?? false
    }
}

/// Installed plugin info (stored in settings).
public struct PluginInfo: Codable, Equatable {
    public var metadata: PluginMetadata
    public var path: String
    public var enabled: Bool
    public var hasSettings: Bool
    
    public init(metadata: PluginMetadata, path: String, enabled: Bool, hasSettings: Bool) {
        self.metadata = metadata
        self.path = path
        self.enabled = enabled
        self.hasSettings = hasSettings
    }
}

/// Parses exteraGram-style metadata from .plugin file content (Python script with __name__, __description__, etc.).
public enum PluginMetadataParser {
    private static let namePattern = #"__name__\s*=\s*["']([^"']+)["']"#
    private static let descriptionPattern = #"__description__\s*=\s*["']([^"']+)["']"#
    private static let versionPattern = #"__version__\s*=\s*["']([^"']+)["']"#
    private static let authorPattern = #"__author__\s*=\s*["']([^"']+)["']"#
    private static let idPattern = #"__id__\s*=\s*["']([^"']+)["']"#
    private static let iconPattern = #"__icon__\s*=\s*["']([^"']+)["']"#
    private static let minVersionPattern = #"__min_version__\s*=\s*["']([^"']+)["']"#
    private static let createSettingsPattern = #"def\s+create_settings\s*\("#
    /// Some plugins set __settings__ = True (e.g. panic_passcode_pro).
    private static let settingsFlagPattern = #"__settings__\s*=\s*True"#
    /// Plugins that modify profile display (Fake Profile–style) set __user_display__ = True.
    private static let userDisplayPattern = #"__user_display__\s*=\s*True"#

    public static func parse(content: String) -> PluginMetadata? {
        guard let name = firstMatch(in: content, pattern: namePattern),
              let id = firstMatch(in: content, pattern: idPattern) else {
            return nil
        }
        let description = firstMatch(in: content, pattern: descriptionPattern) ?? ""
        let version = firstMatch(in: content, pattern: versionPattern) ?? "1.0"
        let author = firstMatch(in: content, pattern: authorPattern) ?? ""
        let iconRef = firstMatch(in: content, pattern: iconPattern)
        let minVersion = firstMatch(in: content, pattern: minVersionPattern)
        let hasUserDisplay = content.range(of: userDisplayPattern, options: .regularExpression) != nil
        return PluginMetadata(id: id, name: name, description: description, version: version, author: author, iconRef: iconRef, minVersion: minVersion, hasUserDisplay: hasUserDisplay)
    }
    
    public static func hasCreateSettings(content: String) -> Bool {
        content.range(of: createSettingsPattern, options: .regularExpression) != nil
            || content.range(of: settingsFlagPattern, options: .regularExpression) != nil
    }
    
    private static func firstMatch(in string: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
              let range = Range(match.range(at: 1), in: string) else {
            return nil
        }
        return String(string[range])
    }
}
