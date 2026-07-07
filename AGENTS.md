# LuxGram Agent Instructions

LuxGram is a Telegram client for iOS based on Telegram 12.5 and Swiftgram.

## Build System

The project uses Bazel with a Python wrapper script `build-system/Make/Make.py`.
For development and CI, we use `scripts/buildsim.sh` for simulator builds and `scripts/buildprod.sh` for production builds.

## Linux Compatibility

This environment is running on Linux. While full iOS builds require macOS and Xcode, basic workspace operations like `bazel query` can be performed on Linux if the build scripts are patched to handle the environment.

## Configuration

Build configuration is managed in `build-system/ipa-build-configuration.json`.
A local configuration repository is expected at `build-input/configuration-repository`.
