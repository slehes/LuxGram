#!/bin/zsh
# Сборка LuxGram для симулятора
#
# Использование:
#   ./scripts/buildsim.sh                 # сборка для симулятора
#   ./scripts/buildsim.sh --device       # сборка для устройства
#   ./scripts/buildsim.sh --clean         # чистая сборка (если изменения не применяются)
#   ./scripts/buildsim.sh --buildNumber 10004
#   ./scripts/buildsim.sh --version 12.4

set -e
cd "$(dirname "$0")/.."

BAZEL="${BAZEL:-}"
[ -z "$BAZEL" ] && [ -x "./build-input/bazel-8.4.2-darwin-arm64" ] && BAZEL="./build-input/bazel-8.4.2-darwin-arm64"
BAZEL="${BAZEL:-bazel}"

BUILD_NUMBER="${BUILD_NUMBER:-10003}"
TELEGRAM_VERSION="${TELEGRAM_VERSION:-12.3}"
CPU="ios_sim_arm64"
CLEAN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --device)
      CPU="ios_arm64"
      shift
      ;;
    --clean)
      CLEAN=1
      shift
      ;;
    --buildNumber)
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --version)
      TELEGRAM_VERSION="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [ "$CLEAN" = 1 ]; then
  echo "Cleaning build cache..."
  "$BAZEL" clean
fi

echo "Building LuxGram for simulator (cpu=$CPU, buildNumber=$BUILD_NUMBER, version=$TELEGRAM_VERSION)..."
"$BAZEL" build //Telegram:LuxGram \
  --cpu="$CPU" \
  --define=buildNumber="$BUILD_NUMBER" \
  --define=telegramVersion="$TELEGRAM_VERSION" \
  --//Telegram:disableProvisioningProfiles=True \
  --verbose_failures

echo "Build complete."
