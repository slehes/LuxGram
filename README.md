<div align="center">

<img src="Icons/LuxGram 1024x1024.png" width="120" height="120" style="border-radius: 22px;" />

# LuxGram

**Next-level Telegram client for iOS**

[![Platform](https://img.shields.io/badge/platform-iOS%2016%2B-blue?style=flat-square&logo=apple)](https://apple.com/ios)
[![Swift](https://img.shields.io/badge/swift-5.9-orange?style=flat-square&logo=swift)](https://swift.org)
[![Telegram Base](https://img.shields.io/badge/Telegram-12.5-2CA5E0?style=flat-square&logo=telegram)](https://telegram.org)
[![License](https://img.shields.io/badge/license-GPL--2.0-green?style=flat-square)](LICENSE)
[![Build](https://img.shields.io/github/actions/workflow/status/LuxGram/LuxGram-iOS/build.yml?style=flat-square&label=IPA%20Build)](../../actions)

<br/>

<img src="AppBadges/LuxGram(Black).png" height="48" />
&nbsp;&nbsp;&nbsp;
<img src="AppBadges/LuxGram(Green).png" height="48" />

</div>

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| 👻 **Ghost Mode** | Hide online status — broadcasts offline every 5 sec |
| ⏱ **Ghost Delay** | Messages appear sent but server gets them after 12–45 sec |
| 🚫 **No Read Receipts** | Disable message & story read receipts, per-contact whitelist |
| 🚫 **No Ads** | Block all sponsored messages in channels |
| 💎 **Local Premium** | Unlock premium UI limits (folders, pins, emoji) locally |
| 🔒 **Chat Password** | Per-chat password protection |
| 🕳 **Double Bottom** | Hidden accounts behind a secret passcode |
| 💬 **Deleted Messages** | Auto-save deleted messages before they vanish |
| 🎨 **Font Replacement** | Replace Telegram's font app-wide (.ttf import) |
| 📍 **Fake Location** | Spoof GPS via CLLocationManager swizzling |
| 🔊 **Voice Morpher** | Change voice: Anonymous / Female / Male / Child / Robot |
| 📤 **Chat Export** | Export history to JSON, TXT or HTML |
| 🌊 **Liquid Glass** | iOS 26 frosted glass on all nav bars, tabs and toolbars |
| 🎭 **Fake Profile** | Show custom name/photo to yourself locally |
| 🔌 **Plugins** | Install & run custom JS plugins |
| ⭐ **Local Stars** | Custom Stars balance display |

---

## 📱 Badges

Pick your notification badge in **LuxGram → Settings → Badge**:

<div align="center">
<img src="AppBadges/LuxGram(Black).png" height="44" />&nbsp;&nbsp;&nbsp;<img src="AppBadges/LuxGram(Green).png" height="44" />
</div>

---

## 🛠 Build

### Requirements

| Tool | Version |
|------|---------|
| macOS | 14+ |
| Xcode | 16+ |
| JDK | 21 (system, set `JAVA_HOME`) |
| Python | 3.11+ |

### 1 — Clone

```bash
git clone --recursive https://github.com/LuxGram/LuxGram-iOS.git
cd LuxGram-iOS
```

### 2 — Configure signing

Edit `build-system/ipa-build-configuration.json`:

```json
{
  "bundle_id": "com.yourteam.LuxGram",
  "api_id": "35971841",
  "api_hash": "504a05393f81633f94c433502e9b09e6",
  "team_id": "YOUR_APPLE_TEAM_ID"
}
```

Place your provisioning profile:

```
build-system/real-codesigning/LuxGram.mobileprovision
```

### 3 — Build

```bash
# Production IPA
./scripts/buildprod.sh

# Custom build number
./scripts/buildprod.sh --buildNumber 100001

# Clean build
./scripts/buildprod.sh --clean

# Simulator (no device needed)
./scripts/buildsim.sh
```

IPA appears in `build/artifacts/`.

---

## ⚡ GitHub Actions (CI/CD)

Push to `main` → IPA built automatically.

**Add these Secrets** in repo **Settings → Secrets and variables → Actions**:

| Secret | How to get |
|--------|-----------|
| `CERTIFICATE_P12_BASE64` | `base64 -i YourCert.p12 \| pbcopy` |
| `CERTIFICATE_PASSWORD` | Password from Keychain |
| `PROVISIONING_PROFILE_BASE64` | `base64 -i LuxGram.mobileprovision \| pbcopy` |
| `APPLE_TEAM_ID` | Your 10-char Apple Team ID |

After push — go to **Actions** tab, download IPA from the build artifacts.

---

## 🗂 Structure

```
LuxGram-iOS/
├── LuxGram/            LuxGram-exclusive modules
│   ├── SGLocalPremium/ Local Premium emulation
│   ├── DoubleBottom/   Hidden accounts
│   ├── ChatPassword/   Per-chat passwords
│   ├── VoiceMorpher/   Voice presets
│   └── GLESettingsUI/  18 settings controllers
├── LuxGram/          Base LuxGram layer (~50 modules)
│   ├── SGSimpleSettings/ 150+ UserDefaults keys
│   └── SGSettingsUI/   Main settings UI
├── submodules/         Telegram iOS (patched)
├── AppBadges/          Selectable notification badges
└── Icons/              App icon assets
```

---

## 📬 Community

<div align="center">

[![Channel](https://img.shields.io/badge/Telegram-Channel-2CA5E0?style=for-the-badge&logo=telegram)](https://t.me/luxgramios)
[![Chat](https://img.shields.io/badge/Telegram-Chat-2CA5E0?style=for-the-badge&logo=telegram)](https://t.me/luxgramios_chat)

</div>

---

<div align="center">
<sub>Based on <a href="https://github.com/LuxGram/Telegram-iOS">LuxGram</a> · <a href="https://github.com/TelegramMessenger/Telegram-iOS">Telegram iOS</a> · GPL-2.0</sub>
</div>
