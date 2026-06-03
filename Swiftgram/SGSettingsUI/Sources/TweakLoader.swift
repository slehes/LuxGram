import Foundation
import SGSimpleSettings

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Directory where user-installed .dylib tweaks are stored. Tweaks are loaded on next app launch.
public enum TweakLoader {
    private static let tweaksSubdirectory = "Tweaks"

    /// URL to Application Support/Tweaks (call from main thread or after app container is available).
    public static var tweaksDirectoryURL: URL {
        let fileManager = FileManager.default
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory not available")
        }
        return support.appendingPathComponent(tweaksSubdirectory, isDirectory: true)
    }

    /// Ensure Tweaks directory exists; returns its URL.
    @discardableResult
    public static func ensureTweaksDirectory() -> URL {
        let url = tweaksDirectoryURL
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// List installed tweak filenames (.dylib) in the Tweaks directory.
    public static func installedTweakFilenames() -> [String] {
        let url = tweaksDirectoryURL
        guard let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        return contents
            .filter { $0.pathExtension.lowercased() == "dylib" }
            .map { $0.lastPathComponent }
            .sorted()
    }

    /// Copy a .dylib file into the Tweaks directory. Returns destination URL on success.
    public static func installTweak(from sourceURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let dir = ensureTweaksDirectory()
        let name = sourceURL.lastPathComponent
        guard name.lowercased().hasSuffix(".dylib") else {
            throw NSError(domain: "TweakLoader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not a .dylib file"])
        }
        let dest = dir.appendingPathComponent(name)
        if fileManager.fileExists(atPath: dest.path) {
            try fileManager.removeItem(at: dest)
        }
        try fileManager.copyItem(at: sourceURL, to: dest)
        return dest
    }

    /// Remove a tweak by filename (e.g. "TGExtra.dylib").
    public static func removeTweak(filename: String) throws {
        let url = tweaksDirectoryURL.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Load all .dylib files from the Tweaks directory. Call once at app startup when pluginSystemEnabled.
    /// On iOS, loading dylibs from a writable path may require jailbreak or special entitlements.
    public static func loadTweaks() {
        guard SGSimpleSettings.shared.pluginSystemEnabled else { return }
        let dir = tweaksDirectoryURL
        guard let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return
        }
        let dylibs = contents.filter { $0.pathExtension.lowercased() == "dylib" }
        for url in dylibs {
            loadTweak(at: url)
        }
    }

    private static func loadTweak(at url: URL) {
        let path = url.path
        #if canImport(Darwin)
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            if let err = dlerror() {
                NSLog("[TweakLoader] Failed to load %@: %s", path, err)
            }
            return
        }
        // Optional: call an init symbol if the tweak exports it (e.g. LuxGramTweakInit).
        if let initSymbol = dlsym(handle, "LuxGramTweakInit") {
            typealias InitFn = @convention(c) () -> Void
            let fn = unsafeBitCast(initSymbol, to: InitFn.self)
            fn()
        }
        // Keep handle alive (we don't dlclose; tweaks stay loaded for app lifetime).
        _ = handle
        #endif
    }
}
