#!/bin/zsh
# Продакшн-сборка LuxGram (IPA, release_arm64)
#
# Использование:
#   ./scripts/buildprod.sh
#   ./scripts/buildprod.sh --buildNumber 100002
#   ./scripts/buildprod.sh --clean
#
# Требуется: build-system/ipa-build-configuration.json, build-system/real-codesigning

set -e
cd "$(dirname "$0")/.."

CACHE_DIR="${CACHE_DIR:-$HOME/telegram-bazel-cache}"
CONFIGURATION_PATH="build-system/ipa-build-configuration.json"
CODESIGNING_PATH="build-system/real-codesigning"
BUILD_NUMBER="${BUILD_NUMBER:-100005}"
CLEAN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --buildNumber)
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --clean)
      CLEAN=1
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [ "$CLEAN" = 1 ]; then
  echo "Cleaning build cache..."
  [ -x "./build-input/bazel-8.4.2-darwin-arm64" ] && ./build-input/bazel-8.4.2-darwin-arm64 clean || bazel clean
fi

echo "Building LuxGram (release_arm64, buildNumber=$BUILD_NUMBER)..."
mkdir -p build/artifacts
python3 build-system/Make/Make.py \
  --cacheDir="$CACHE_DIR" \
  build \
  --configurationPath="$CONFIGURATION_PATH" \
  --codesigningInformationPath="$CODESIGNING_PATH" \
  --buildNumber="$BUILD_NUMBER" \
  --target LuxGram \
  --configuration=release_arm64 \
  --outputBuildArtifactsPath="build/artifacts"

echo "Build complete. IPA: build/artifacts/LuxGram.ipa"
