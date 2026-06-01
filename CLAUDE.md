# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

LuxGram — a fork of LuxGram (which is a fork of Telegram iOS). Base version: Telegram 12.5, LuxGram 12.5. All LuxGram-specific code is marked with `// MARK: - LuxGram` and `// MARK: - End LuxGram` in Telegram source files.

## Build Commands

```bash
# Production IPA (release_arm64)
./scripts/buildprod.sh

# With custom build number
./scripts/buildprod.sh --buildNumber 100006

# Clean build
./scripts/buildprod.sh --clean

# Simulator build
./scripts/buildsim.sh
```

**Known issue:** Bazel 8.4.2 with embedded JDK 24 crashes on macOS 15.7.4+. The build system auto-applies `--server_javabase` pointing to system JDK 21 (configured in `build-system/Make/Make.py`).

**Build target:** `//Telegram:LuxGram` (alias `//Telegram:LuxGram` for backwards compatibility).

**Build configuration:** `build-system/ipa-build-configuration.json` + `build-system/real-codesigning/` for production signing.

## Architecture

### Three-layer structure

1. **Telegram base** (`submodules/`) — Original Telegram iOS code. LuxGram patches are injected with `// MARK: - LuxGram` markers and wrapped in `#if canImport(SGSimpleSettings)` guards.

2. **LuxGram layer** (`LuxGram/`) — ~50 modules: settings UI, localization, config, badges, logging, requests, API, etc. Core module: `SGSimpleSettings` (UserDefaults-backed settings with 150+ keys). Settings controller: `SGSettingsUI/Sources/SGSettingsController.swift`.

3. **LuxGram layer** (`LuxGram/`) — 10 modules with LuxGram-exclusive features:
   - `SGSupporters` — Encrypted badge/subscription API (AES-256 + HMAC-SHA256 + SSL pinning)
   - `SGDeletedMessages` — AyuGram-style saved deleted messages (namespace 1338)
   - `SGFakeLocation` — CLLocationManager swizzling
   - `SGChatExport` — HTML/JSON/TXT export
   - `SGLocalPremium` — Local Premium emulation
   - `DoubleBottom` — Hidden accounts with secret passcode
   - `ChatPassword` — Per-chat password protection
   - `VoiceMorpher` — Voice preset engine
   - `GLESettingsUI` — 18 controllers (paywall, plugins, fonts, fake profile, etc.)

### Key modified Telegram files

The heaviest LuxGram patches are in:
- `AppDelegate.swift` — App icons, SGConfig.isBetaBuild, supporters init, ghost delay, deeplinks
- `ChatController.swift` — Ghost mode delay, saved deleted hooks
- `AccountStateManagementUtils.swift` — Deleted message saving, edit history
- `PendingMessageManager.swift` — Ghost delay timer (GhostDelayedSendAttribute)
- `ManagedAccountPresence.swift` — Periodic offline timer for ghost mode
- `ManagedLocalInputActivities.swift` — Hide typing/recording/uploading statuses
- `DeleteMessages.swift` — SavedDeleted namespace handling
- `PeerInfoScreen.swift` — LuxGram settings tab, badges, export
- `Font.swift` (Display) — A-Font style font replacement with cache
- `MTTcpConnection.m` — Custom TLS ClientHello fingerprint

### Settings system

- `SGSimpleSettings` (`LuxGram/SGSimpleSettings/Sources/SimpleSettings.swift`) — All settings keys, defaults, UserDefault properties. LuxGram added 80+ keys (ghost mode, deleted messages, font replacement, fake profile, plugins, gated features, etc.)
- `SGUISettings` (`submodules/TelegramUIPreferences/Sources/LuxGram/SGUISettings.swift`) — Postbox-backed UI settings
- LuxGram settings controller: `LuxGram/SGSettingsUI/Sources/LuxGramSettingsController.swift`

### EnqueueMessage.forward

LuxGram added `asCopy: Bool` as 6th parameter to `EnqueueMessage.forward`. All `.forward` constructors need `asCopy:` and all destructuring patterns need 6 wildcards. When adding new `.forward` calls, always include `asCopy: false`.

### BUILD file conventions

LuxGram modules use `//LuxGram/ModuleName:ModuleName` paths. LuxGram modules use `//LuxGram/ModuleName:ModuleName`. When adding LuxGram deps to submodule BUILD files, add to the `deps` array (not `sgdeps` which is used for `srcs` in some modules like TelegramUI).

## Code Style

- **Naming**: PascalCase for types, camelCase for variables/methods
- **Imports**: Group and sort; use `#if canImport(SGSimpleSettings)` guards for LuxGram imports in Telegram source files
- **LuxGram markers**: Always wrap LuxGram code in `// MARK: - LuxGram` / `// MARK: - End LuxGram`
- **No tests** are used

## Localization

Strings in `LuxGram/SGStrings/Strings/` (110 language files, 386 strings). Use `i18n("KEY", lang)` for LuxGram-specific strings. Inline Russian/English with `lang == "ru" ? "..." : "..."` is acceptable for LuxGram-only UI.

## Config

`LuxGram/SGConfig/Sources/File.swift` — API URLs, supporters API keys, demo login config, `isBetaBuild` flag. Parsed from `BuildConfig.sgConfig` which comes from `variables.bzl` via the build system.
