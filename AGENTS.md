# LuxGram AI Agent Instructions

LuxGram is an iOS Telegram client fork based on Telegram 12.5 and Swiftgram.

## Project Structure
- `Telegram/`: Core Telegram application code.
- `LuxGram/`: LuxGram-specific UI and features (mostly in `LuxSettingsUI`).
- `Swiftgram/`: Swiftgram-specific components.
- `build-system/`: Build scripts and Bazel configuration.

## Build System
The project uses Bazel for builds. A Python wrapper `build-system/Make/Make.py` is used to manage the build environment and dependencies.

### Common Commands
- Build for simulator: `python3 build-system/Make/Make.py build --configuration debug_sim_arm64 --buildNumber 10000 --configurationPath build-system/ipa-build-configuration.json --disableProvisioningProfiles`

## Coding Standards
- LuxGram-specific changes should be marked with `// MARK: - LuxGram` and `// MARK: - End LuxGram`.
- Avoid modifying core Telegram logic unless necessary for LuxGram features.
