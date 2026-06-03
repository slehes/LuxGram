import Foundation

/// LuxGram / ghostgram-style: local voice morphing for outgoing voice messages (UserDefaults).
public final class VoiceMorpherManager {
    public static let shared = VoiceMorpherManager()

    public enum VoicePreset: Int, CaseIterable {
        case disabled = 0
        case anonymous = 1
        case female = 2
        case male = 3
        case child = 4
        case robot = 5

        public func title(langIsRu: Bool) -> String {
            switch self {
            case .disabled:
                return langIsRu ? "Выключено" : "Off"
            case .anonymous:
                return langIsRu ? "Аноним" : "Anonymous"
            case .female:
                return langIsRu ? "Женский" : "Female"
            case .male:
                return langIsRu ? "Мужской" : "Male"
            case .child:
                return langIsRu ? "Ребёнок" : "Child"
            case .robot:
                return langIsRu ? "Робот" : "Robot"
            }
        }

        public func subtitle(langIsRu: Bool) -> String {
            switch self {
            case .disabled:
                return langIsRu ? "Без изменений" : "Unchanged"
            case .anonymous:
                return langIsRu ? "Искажённый голос" : "Distorted voice"
            case .female:
                return langIsRu ? "Выше тон" : "Higher pitch"
            case .male:
                return langIsRu ? "Ниже тон" : "Lower pitch"
            case .child:
                return langIsRu ? "Детский тон" : "Child-like"
            case .robot:
                return langIsRu ? "Металлический эффект" : "Metallic effect"
            }
        }
    }

    private enum Keys {
        static let isEnabled = "VoiceMorpher.isEnabled"
        static let selectedPreset = "VoiceMorpher.selectedPreset"
    }

    private let defaults = UserDefaults.standard

    public var isEnabled: Bool {
        get { defaults.bool(forKey: Keys.isEnabled) }
        set {
            defaults.set(newValue, forKey: Keys.isEnabled)
            notifyChanged()
        }
    }

    public var selectedPresetId: Int {
        get { defaults.integer(forKey: Keys.selectedPreset) }
        set {
            defaults.set(newValue, forKey: Keys.selectedPreset)
            notifyChanged()
        }
    }

    public var selectedPreset: VoicePreset {
        VoicePreset(rawValue: selectedPresetId) ?? .disabled
    }

    public var effectivePreset: VoicePreset {
        guard isEnabled else { return .disabled }
        return selectedPreset
    }

    public static let settingsChangedNotification = Notification.Name("VoiceMorpherSettingsChanged")

    private func notifyChanged() {
        NotificationCenter.default.post(name: Self.settingsChangedNotification, object: nil)
    }

    private init() {}
}
