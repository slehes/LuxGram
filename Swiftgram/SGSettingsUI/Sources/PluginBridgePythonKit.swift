//
// Uses PythonKit (https://github.com/pvieito/PythonKit) when available.
// exteraGram plugins import Android/Java (base_plugin, org.telegram.messenger, etc.);
// on iOS/macOS those are unavailable, so we use regex parsing by default. When PythonKit
// is linked, you can implement full execution with builtins.exec(code, globals, locals)
// and stub modules (base_plugin, java, ui, ...) so the script runs and exposes __name__, etc.
//
// To enable PythonKit: add as SPM dependency or vendored; on iOS embed a Python framework.

import Foundation

#if canImport(PythonKit)
import PythonKit

/// Runtime that can use Python to parse/run plugin content when PythonKit is available.
/// Currently delegates to regex parser; replace with exec()-based implementation when
/// stubs for base_plugin/java/android are ready.
public final class PythonPluginRuntime: PluginRuntime, @unchecked Sendable {
    public static let shared = PythonPluginRuntime()
    
    private init() {}
    
    public func parseMetadata(content: String) -> PluginMetadata? {
        // Optional: use Python builtins.exec(content, globals, locals) with stubbed
        // base_plugin, java, ui, etc., then read __name__, __id__, ... from globals.
        // For now use regex so it works without a full Python stub environment.
        return PluginMetadataParser.parse(content: content)
    }
    
    public func hasCreateSettings(content: String) -> Bool {
        PluginMetadataParser.hasCreateSettings(content: content)
    }
}
#else
// When PythonKit is not linked, PythonPluginRuntime is not compiled; app uses DefaultPluginRuntime.
#endif
