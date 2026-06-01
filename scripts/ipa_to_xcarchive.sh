#!/bin/zsh
# Конвертирует IPA в .xcarchive для загрузки через Xcode Organizer (Distribute App).
# Xcode Organizer показывает только archives — этот скрипт создаёт архив из IPA.
#
# Использование: ./scripts/ipa_to_xcarchive.sh [путь/к/LuxGram.ipa]

set -e
cd "$(dirname "$0")/.."

INPUT="${1:-}"
if [ -z "$INPUT" ]; then
  # Ищем IPA в типичных местах
  for p in "bazel-bin/Telegram/LuxGram.ipa" "bazel-bin/Telegram/LuxGram"*.ipa "build/artifacts/TestFlight/LuxGram.ipa" "$HOME/Downloads/LuxGram.ipa"; do
    if [ -f "$p" ]; then
      INPUT="$p"
      break
    fi
  done
fi
if [ -z "$INPUT" ] || [ ! -f "$INPUT" ]; then
  echo "Использование: $0 <путь/к/LuxGram.ipa>"
  echo "IPA не найден. Укажите путь или соберите: ./scripts/build_testflight_distribution.sh"
  exit 1
fi

WORK="/tmp/ipa_to_xcarchive_$$"
DIST_DIR="build/artifacts/TestFlight"
mkdir -p "$DIST_DIR"

echo "Создаю xcarchive из: $INPUT"
rm -rf "$WORK"
mkdir -p "$WORK"

# Распаковываем IPA
unzip -q "$INPUT" -d "$WORK/ipa"
APP_BUNDLE=$(ls -d "$WORK/ipa/Payload/"*.app 2>/dev/null | head -1)
if [ -z "$APP_BUNDLE" ] || [ ! -d "$APP_BUNDLE" ]; then
  echo "Ошибка: не найден .app в IPA"
  exit 1
fi
APP_NAME=$(basename "$APP_BUNDLE" .app)
ARCHIVE_DIR="$WORK/${APP_NAME}.xcarchive"
mkdir -p "$ARCHIVE_DIR/Products/Applications"

# Копируем .app в xcarchive
cp -R "$APP_BUNDLE" "$ARCHIVE_DIR/Products/Applications/"

# Читаем версию из Info.plist приложения
APP_PLIST="$ARCHIVE_DIR/Products/Applications/$APP_NAME.app/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PLIST" 2>/dev/null || echo "12.3")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PLIST" 2>/dev/null || echo "100001")

# Создаём Info.plist архива
cat > "$ARCHIVE_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>ApplicationProperties</key>
	<dict>
		<key>ApplicationPath</key>
		<string>Applications/$APP_NAME.app</string>
		<key>CFBundleIdentifier</key>
		<string>com.GLEProject.LuxGram</string>
		<key>CFBundleShortVersionString</key>
		<string>$VERSION</string>
		<key>CFBundleVersion</key>
		<string>$BUILD</string>
	</dict>
	<key>ArchiveVersion</key>
	<integer>1</integer>
	<key>CreationDate</key>
	<date>$(date -u +%Y-%m-%dT%H:%M:%SZ)</date>
	<key>Name</key>
	<string>$APP_NAME</string>
	<key>SchemeIdentifier</key>
	<string>com.GLEProject.LuxGram</string>
</dict>
</plist>
EOF

# SwiftSupport — копируем libswift*.dylib из Xcode toolchain
XCODE_DEV=$(xcode-select -p 2>/dev/null)
SWIFT_SUPPORT_DIR="$ARCHIVE_DIR/SwiftSupport/iphoneos"
mkdir -p "$SWIFT_SUPPORT_DIR"
SWIFT_COUNT=0
for dylib in "$ARCHIVE_DIR/Products/Applications/$APP_NAME.app/Frameworks"/libswift*.dylib; do
  [ -f "$dylib" ] || continue
  DYLIB_NAME=$(basename "$dylib")
  TOOLCHAIN_LIB=$(find "$XCODE_DEV/Toolchains" -path "*/iphoneos/$DYLIB_NAME" -not -path "*Simulator*" 2>/dev/null | head -1)
  if [ -f "$TOOLCHAIN_LIB" ]; then
    cp "$TOOLCHAIN_LIB" "$SWIFT_SUPPORT_DIR/"
    SWIFT_COUNT=$((SWIFT_COUNT + 1))
    echo "SwiftSupport: $DYLIB_NAME"
  fi
done
if [ "$SWIFT_COUNT" -eq 0 ]; then
  rm -rf "$ARCHIVE_DIR/SwiftSupport"
fi

# Копируем dSYMs если есть
DSYM_SRC="bazel-bin/Telegram"
if [ -d "$DSYM_SRC" ]; then
  mkdir -p "$ARCHIVE_DIR/dSYMs"
  for dsym in "$DSYM_SRC"/*.dSYM; do
    [ -d "$dsym" ] && cp -R "$dsym" "$ARCHIVE_DIR/dSYMs/" && echo "dSYM: $(basename "$dsym")"
  done
fi

# Копируем результат
ARCHIVE_DST="$DIST_DIR/${APP_NAME}_$(date +%Y%m%d_%H%M).xcarchive"
cp -R "$ARCHIVE_DIR" "$ARCHIVE_DST"

# Копируем в папку Xcode Archives — тогда архив появится в Organizer автоматически
XCODE_ARCHIVES="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)"
mkdir -p "$XCODE_ARCHIVES"
XCODE_ARCHIVE_PATH="$XCODE_ARCHIVES/${APP_NAME}_$(date +%H%M).xcarchive"
cp -R "$ARCHIVE_DIR" "$XCODE_ARCHIVE_PATH"
echo "Скопировано в Xcode Archives: $XCODE_ARCHIVE_PATH"

rm -rf "$WORK"

echo ""
echo "=== Готово ==="
echo "Archive: $ARCHIVE_DST"
echo ""
echo "Для загрузки в TestFlight:"
echo "  1. Xcode → Window → Organizer (⌥⇧⌘O)"
echo "  2. Архив уже в папке Xcode — должен отображаться в списке"
echo "  3. Если нет: двойной клик по .xcarchive в Finder"
echo "  4. Выберите архив → Distribute App → App Store Connect"
echo ""
echo "Или Transporter (IPA напрямую): откройте Transporter → перетащите IPA"
