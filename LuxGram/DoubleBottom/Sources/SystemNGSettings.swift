// From Nicegram NGData/Sources/NGSettings.swift - only SystemNGSettings for Double Bottom
import Foundation

public class SystemNGSettings {
    let UD = UserDefaults.standard

    public init() {}

    public var dbReset: Bool {
        get {
            return UD.bool(forKey: "ng_db_reset")
        }
        set {
            UD.set(newValue, forKey: "ng_db_reset")
        }
    }

    public var isDoubleBottomOn: Bool {
        get {
            return UD.bool(forKey: "isDoubleBottomOn")
        }
        set {
            UD.set(newValue, forKey: "isDoubleBottomOn")
        }
    }

    public var inDoubleBottom: Bool {
        get {
            return UD.bool(forKey: "inDoubleBottom")
        }
        set {
            UD.set(newValue, forKey: "inDoubleBottom")
        }
    }
}

public var VarSystemNGSettings = SystemNGSettings()
