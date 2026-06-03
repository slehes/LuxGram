//
// Плагины показывают тосты, алерты и отправляют сообщения через PluginHost.

import Foundation

/// Тип тоста для плагина (info / error / success).
public enum PluginBulletinType {
    case info
    case error
    case success
}

/// Host callbacks that the app sets so plugins can show UI and send messages.
public final class PluginHost {
    public static let shared = PluginHost()

    /// Показать тост (баннер внизу экрана).
    public var showBulletin: ((String, PluginBulletinType) -> Void)?

    /// Показать алерт (заголовок и сообщение).
    public var showAlert: ((String, String) -> Void)?

    /// Отправить текстовое или файловое сообщение (accountPeerId, peerId, text, replyToMessageId?, filePath?). filePath: локальный путь к файлу для отправки как документ; fileName задаётся отдельно через sendMessageWithFileName при необходимости.
    public var sendMessage: ((Int64, Int64, String, Int64?, String?) -> Void)?

    /// Временная директория для плагина (например для FileViewer: скачать/редактировать файлы). Поддиректория в Caches; создаётся при первом обращении.
    public func getPluginTempDirectory(pluginId: String) -> String {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Plugins", isDirectory: true)
            .appendingPathComponent(pluginId, isDirectory: true).path ?? NSTemporaryDirectory()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Выполнить блок на главной очереди.
    public var runOnMain: ((@escaping () -> Void) -> Void)?

    /// Выполнить блок в фоне.
    public var runOnBackground: ((@escaping () -> Void) -> Void)?

    // MARK: - Настройки плагина (get_setting / set_setting в Python)

    private let pluginSettingsPrefix = "sg_plugin_"

    /// Reads a plugin setting string (UserDefaults key: sg_plugin_{pluginId}_{key}).
    public func getPluginSetting(pluginId: String, key: String) -> String? {
        let k = "\(pluginSettingsPrefix)\(pluginId)_\(key)"
        return UserDefaults.standard.string(forKey: k)
    }

    /// Reads a plugin setting bool (stored as "1"/"0" or "true"/"false").
    public func getPluginSettingBool(pluginId: String, key: String, default: Bool) -> Bool {
        guard let s = getPluginSetting(pluginId: pluginId, key: key) else { return `default` }
        return s == "1" || s.lowercased() == "true"
    }

    /// Writes a plugin setting.
    public func setPluginSetting(pluginId: String, key: String, value: String) {
        UserDefaults.standard.set(value, forKey: "\(pluginSettingsPrefix)\(pluginId)_\(key)")
    }

    /// Writes a plugin setting bool.
    public func setPluginSettingBool(pluginId: String, key: String, value: Bool) {
        setPluginSetting(pluginId: pluginId, key: key, value: value ? "1" : "0")
    }

    private init() {
        runOnMain = { block in DispatchQueue.main.async(execute: block) }
        runOnBackground = { block in
            DispatchQueue.global(qos: .userInitiated).async(execute: block)
        }
    }
}
