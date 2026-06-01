#!/bin/bash
# Deploy LuxGram IPA to iPhone via TrollStore over SSH
# Usage: ./deploy.sh [path/to/ipa]

set -e

DEVICE_IP="192.168.1.148"
DEVICE_USER="root"
DEVICE_PASS="1"
REMOTE_TMP="/var/mobile/deploy.ipa"

# IPA path: argument or default bazel output
IPA_PATH="${1:-bazel-bin/Telegram/LuxGram.ipa}"

if [ ! -f "$IPA_PATH" ]; then
    echo "❌ IPA not found: $IPA_PATH"
    exit 1
fi

echo "📦 IPA: $IPA_PATH ($(du -h "$IPA_PATH" | cut -f1))"

# Find trollstorehelper on device
echo "🔍 Finding trollstorehelper..."
TSH=$(sshpass -p "$DEVICE_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
    "$DEVICE_USER@$DEVICE_IP" \
    'find /private/var/containers/Bundle/Application -name trollstorehelper -type f 2>/dev/null | head -1')

if [ -z "$TSH" ]; then
    echo "❌ trollstorehelper not found on device"
    exit 1
fi
echo "✅ Found: $TSH"

# Upload IPA
echo "📤 Uploading to device..."
sshpass -p "$DEVICE_PASS" scp -o StrictHostKeyChecking=no \
    "$IPA_PATH" "$DEVICE_USER@$DEVICE_IP:$REMOTE_TMP"

# Install via TrollStore
echo "📲 Installing via TrollStore..."
sshpass -p "$DEVICE_PASS" ssh -o StrictHostKeyChecking=no \
    "$DEVICE_USER@$DEVICE_IP" \
    "'$TSH' install $REMOTE_TMP 2>&1; rm -f $REMOTE_TMP"

echo "✅ Done!"
