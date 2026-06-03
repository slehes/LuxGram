import Foundation

public enum DoubleBottomViewingSecretStore {
    private static let key = "DoubleBottomViewingWithSecretPasscode"

    public static func isViewingWithSecretPasscode() -> Bool {
        return UserDefaults.standard.bool(forKey: key)
    }

    public static func setViewingWithSecretPasscode(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
