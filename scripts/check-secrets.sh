#!/bin/zsh
# Verify no secrets remain before pushing to public repo

set -e
cd "$(dirname "$0")/.."

FOUND=0

echo "Checking for secrets..."

# AES/HMAC keys
if grep -rq "V1wmSaHPBtfwGR7jHozwSkRVQrUVtvUMkb\|QpU3hDanhmp67LDTzL2tjzDuG4qIsCIFn3LMY" . --include="*.swift" --include="*.json" 2>/dev/null; then
    echo "FAIL: AES/HMAC keys found!"
    FOUND=1
fi

# LuxGram API credentials
if grep -rq "31339208\|b7917b274453f075e114f2fef86230d2" . --include="*.swift" --include="*.json" --include="*.bzl" 2>/dev/null; then
    echo "FAIL: LuxGram API credentials found!"
    FOUND=1
fi

# Team ID
if grep -rq "F8A8NWPL78" . --include="*.swift" --include="*.json" --include="*.bzl" 2>/dev/null; then
    echo "FAIL: LuxGram Team ID found!"
    FOUND=1
fi

# HMAC salt
if grep -rq "glegram-hmac-v1" . --include="*.swift" 2>/dev/null; then
    echo "FAIL: HMAC salt found!"
    FOUND=1
fi

# SSL pinning hashes
if grep -rq "brDmHiqwkhgPrFDmkcD2IsDUdKLZlyGjGkn0SOGNKFI" . --include="*.swift" --include="*.json" 2>/dev/null; then
# HMAC salt
if grep -rq "glegram-hmac-v1" . --include="*.swift" 2>/dev/null; then
    echo "FAIL: HMAC salt found!"
    FOUND=1
fi

    echo "FAIL: SSL pinning hashes found!"
    FOUND=1
fi

# glegram.site in code (not comments)
if grep -rn "glegram.site" . --include="*.swift" --include="*.json" 2>/dev/null | grep -v "//\|/\*\|e\.g\.\|example" | grep -q .; then
    echo "FAIL: glegram.site domain in code (not comment)!"
    FOUND=1
fi

# Real provisioning profiles
if find build-system/real-codesigning -name "*.mobileprovision" -o -name "*.p12" 2>/dev/null | grep -q .; then
    echo "FAIL: Real provisioning profiles found!"
    FOUND=1
fi

if [ "$FOUND" -eq 0 ]; then
    echo "ALL CLEAR — safe to push to public repo."
else
    echo ""
    echo "BLOCKED — fix the issues above before pushing!"
    exit 1
fi
