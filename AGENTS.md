# LuxGram AI Agent Instructions

LuxGram is an iOS Telegram client fork based on Telegram 12.5 and Swiftgram.

## Project Structure
- `LuxGram/`: Contains LuxGram-specific modules (e.g., `LuxSettingsUI`).
- `Telegram/`: Main Telegram source code.
- `submodules/`: External dependencies and shared modules.
- `build-system/`: Build scripts and Bazel configuration.

## Common Build Commands
The project uses a Python wrapper script `build-system/Make/Make.py`.

### Clean
```bash
python3 build-system/Make/Make.py clean
```

### Generate Xcode Project
```bash
python3 build-system/Make/Make.py generateProject --configurationPath build-system/ipa-build-configuration.json --xcodeManagedCodesigning
```

### Build (Simulator)
```bash
python3 build-system/Make/Make.py build --configurationPath build-system/ipa-build-configuration.json --xcodeManagedCodesigning --buildNumber 100 --configuration release_sim_arm64 --target LuxGram
```

### Bazel Query (Linux/CI)
```bash
python3 build-system/Make/Make.py --overrideXcodeVersion query --queryArgs "//Telegram:LuxGram"
```

## AI Agent Guidelines
- LuxGram-specific code in Telegram source is marked with `// MARK: - LuxGram` and `// MARK: - End LuxGram`.
- Always use `build-input/configuration-repository` for local build configuration.
- The repository requires `WORKSPACE`, `MODULE.bazel`, `BUILD`, and `variables.bzl` in the configuration directory.
