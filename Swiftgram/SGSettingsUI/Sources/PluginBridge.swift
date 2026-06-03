//
// This module provides a bridge to run or query exteraGram-style .plugin files (Python).
// - Default: metadata and settings detection via regex (PluginMetadataParser), works on iOS/macOS.
// - Optional: when PythonKit (https://github.com/pvieito/PythonKit) is available, use
//   PythonPluginRuntime to execute plugin code in a sandbox and read metadata from Python.
//
// swift-bridge (https://github.com/chinedufn/swift-bridge) is for Rust↔Swift; for Swift↔Python
// we use PythonKit. This protocol allows swapping implementations (regex-only vs PythonKit).

import Foundation

/// Runtime used to parse or execute .plugin file content (exteraGram Python format).
public protocol PluginRuntime: Sendable {
    /// Parses plugin metadata (__name__, __id__, __description__, etc.) from file content.
    func parseMetadata(content: String) -> PluginMetadata?
    /// Returns true if the plugin defines create_settings or __settings__ = True.
    func hasCreateSettings(content: String) -> Bool
}

/// Default implementation using regex-based parsing (no Python required). Works on iOS and macOS.
public final class DefaultPluginRuntime: PluginRuntime, @unchecked Sendable {
    public static let shared = DefaultPluginRuntime()
    
    public init() {}
    
    public func parseMetadata(content: String) -> PluginMetadata? {
        PluginMetadataParser.parse(content: content)
    }
    
    public func hasCreateSettings(content: String) -> Bool {
        PluginMetadataParser.hasCreateSettings(content: content)
    }
}

/// Current runtime used by the app. Set to a PythonKit-based runtime when Python is available.
public var currentPluginRuntime: PluginRuntime = DefaultPluginRuntime.shared
