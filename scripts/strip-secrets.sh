#!/bin/zsh
# Strip secrets before publishing to public repo
# Run ONLY on the 'main' branch

set -e
cd "$(dirname "$0")/.."

BRANCH=$(git branch --show-current)
if [ "$BRANCH" != "main" ]; then
    echo "ERROR: Run this only on 'main' branch (current: $BRANCH)"
    exit 1
fi

echo "Stripping secrets for public release..."

# 1. SGConfig — remove keys
cat > LuxGram/SGConfig/Sources/File.swift << 'SWIFT'
import Foundation
import BuildConfig

public struct SGConfig: Codable {
    public static let isBetaBuild: Bool = true
    public var apiUrl: String = "https://api.swiftgram.app"
    public var webappUrl: String = "https://my.swiftgram.app"
    public var botUsername: String = "LuxGramBot"
    public var publicKey: String?
    public var iaps: [String] = []
    public var supportersApiUrl: String? = nil
    public var supportersAesKey: String? = nil
    public var supportersHmacKey: String? = nil
    public var supportersPinnedCertHashes: [String] = []
    public var demoLoginBackendUrl: String? = nil
    public var demoLoginPhonePrefix: String? = nil
}

private func parseSGConfig(_ jsonString: String) -> SGConfig {
    let jsonData = Data(jsonString.utf8)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return (try? decoder.decode(SGConfig.self, from: jsonData)) ?? SGConfig()
}

private let baseAppBundleId = Bundle.main.bundleIdentifier!
private let buildConfig = BuildConfig(baseAppBundleId: baseAppBundleId)
public let SG_CONFIG: SGConfig = parseSGConfig(buildConfig.sgConfig)
public let SG_API_WEBAPP_URL_PARSED = URL(string: SG_CONFIG.webappUrl)!
SWIFT
echo "  Stripped: SGConfig"

# 1.5 SupportersCrypto — remove HMAC salt
sed -i '' 's/private let HMAC_SALT = .*/private let HMAC_SALT = "YOUR_HMAC_SALT"/' LuxGram/SGSupporters/Sources/SupportersCrypto.swift 2>/dev/null
echo "  Stripped: HMAC salt"

# 2. Build configs — replace with templates
for cfg in build-system/ipa-build-configuration.json build-system/glegram-appstore-configuration.json; do
    cat > "$cfg" << 'JSON'
{
	"bundle_id": "com.example.LuxGram",
	"api_id": "YOUR_API_ID",
	"api_hash": "YOUR_API_HASH",
	"team_id": "YOUR_TEAM_ID",
	"app_center_id": "0",
	"is_internal_build": "false",
	"is_appstore_build": "true",
	"appstore_id": "0",
	"app_specific_url_scheme": "tg",
	"premium_iap_product_id": "",
	"enable_siri": false,
	"enable_icloud": false,
	"sg_config": ""
}
JSON
done
echo "  Stripped: build configs"

# 3. Real codesigning — empty
rm -rf build-system/real-codesigning/certs/*.p12 build-system/real-codesigning/certs/*.cer 2>/dev/null
rm -rf build-system/real-codesigning/profiles/*.mobileprovision 2>/dev/null
mkdir -p build-system/real-codesigning/certs build-system/real-codesigning/profiles
echo "# Add your certificates here" > build-system/real-codesigning/certs/README.md
echo "# Add your provisioning profiles here" > build-system/real-codesigning/profiles/README.md
echo "  Stripped: codesigning"

# 4. Remove binaries
rm -f build-input/bazel-* scripts/Telegram 2>/dev/null
rm -rf build/ 2>/dev/null
echo "  Stripped: binaries"

echo ""
echo "Done. Run ./scripts/check-secrets.sh before committing."
