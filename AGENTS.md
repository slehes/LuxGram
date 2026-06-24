# LuxGram AI Agent Instructions

LuxGram is an iOS Telegram client fork based on Telegram 12.5 and Swiftgram.

## Project Structure
- `Telegram/`: Main application code.
- `LuxGram/`: LuxGram-specific modules and UI.
- `Swiftgram/`: Swiftgram-specific modules.
- `build-system/Make/Make.py`: Python wrapper for Bazel build system.
- `scripts/`: Build and utility scripts.

## Build Commands
To run a Bazel query (useful for environment verification):
```bash
python3 build-system/Make/Make.py --overrideXcodeVersion query --queryArgs "query //Telegram:LuxGram"
```

To build for simulator (requires macOS):
```bash
./scripts/buildsim.sh
```
