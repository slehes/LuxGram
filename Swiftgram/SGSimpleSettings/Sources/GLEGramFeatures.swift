import Foundation

/// Global feature flags for LuxGram (Swiftgram).
public enum LuxGramFeatures {
    /// Master toggle for JS plugins: without it, PluginRunner and chat hooks are disabled (less overhead and hangs).
    public static let pluginsEnabled = true
}
