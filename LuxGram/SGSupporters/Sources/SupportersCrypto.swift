import Foundation
import CryptoKit
import SGLogging

private let HMAC_SALT = "YOUR_HMAC_SALT"
private let TS_MAX_AGE_SEC = 300

/// AES-256-GCM + HMAC-SHA256 (anti-tampering, replay protection).
enum SupportersCrypto {
    private static let ivLength = 12
    private static let authTagLength = 16

    /// Normalize key to 32 bytes: base64 decode if 32 bytes, else SHA256 of string.
    static func normalizeKeyData(_ key: String) -> Data {
        if let decoded = Data(base64Encoded: key), decoded.count == 32 {
            return decoded
        }
        let hash = SHA256.hash(data: Data(Array(key.utf8)))
        let bytes = hash.withUnsafeBytes { Array($0) }
        return Data(bytes)
    }

    private static func normalizeKey(_ key: String) -> SymmetricKey {
        SymmetricKey(data: normalizeKeyData(key))
    }

    /// Derive HMAC key: HMAC-SHA256(master_key, "HMAC salt string").
    private static func deriveHmacKey(from masterKey: Data) -> SymmetricKey {
        let key = SymmetricKey(data: masterKey)
        let salt = Data(Array(HMAC_SALT.utf8))
        let authCode = HMAC<SHA256>.authenticationCode(for: salt, using: key)
        let bytes = authCode.withUnsafeBytes { Array($0) }
        return SymmetricKey(data: Data(bytes))
    }

    /// Resolve HMAC key: if explicit key provided (32-byte base64), use it; else derive from aesKey.
    private static func resolveHmacKey(aesKey: String, explicitHmacKey: String?) -> SymmetricKey {
        if let hmac = explicitHmacKey, !hmac.isEmpty,
           let decoded = Data(base64Encoded: hmac), decoded.count == 32 {
            return SymmetricKey(data: decoded)
        }
        return deriveHmacKey(from: normalizeKeyData(aesKey))
    }

    /// Canonical JSON: keys sorted alphabetically, optionally exclude "hmac" for signing.
    private static func canonicalJSON(_ obj: Any, excludeHmac: Bool = true) -> String {
        if let dict = obj as? [String: Any] {
            let filtered = excludeHmac ? dict.filter { $0.key != "hmac" } : dict
            let sorted = filtered.sorted { $0.key < $1.key }
            let parts = sorted.map { jsonEncodeString($0.key) + ":" + canonicalJSON($0.value) }
            return "{\(parts.joined(separator: ","))}"
        }
        if let arr = obj as? [Any] {
            return "[\(arr.map { canonicalJSON($0) }.joined(separator: ","))]"
        }
        return jsonEncodePrimitive(obj)
    }

    /// Manual JSON string encoding to avoid JSONSerialization.data (crashes with NSData dataWithBytesNoCopy on iOS 16).
    private static func jsonEncodeString(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\u{0008}", with: "\\b")
            .replacingOccurrences(of: "\u{000C}", with: "\\f")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    /// Manual JSON primitive encoding to avoid JSONSerialization.data (crashes with NSData dataWithBytesNoCopy on iOS 16).
    private static func jsonEncodePrimitive(_ val: Any) -> String {
        switch val {
        case is NSNull:
            return "null"
        case let b as Bool:
            return b ? "true" : "false"
        case let i as Int:
            return String(i)
        case let i as Int8:
            return String(i)
        case let i as Int16:
            return String(i)
        case let i as Int32:
            return String(i)
        case let i as Int64:
            return String(i)
        case let i as UInt:
            return String(i)
        case let i as UInt8:
            return String(i)
        case let i as UInt16:
            return String(i)
        case let i as UInt32:
            return String(i)
        case let i as UInt64:
            return String(i)
        case let d as Double:
            return d.isFinite ? String(d) : "null"
        case let f as Float:
            return f.isFinite ? String(f) : "null"
        case let s as String:
            return jsonEncodeString(s)
        default:
            return "\"\""
        }
    }

    /// Compute HMAC-SHA256 of canonical JSON, base64 result.
    private static func computeHmac(_ obj: [String: Any], aesKey: String, explicitHmacKey: String?) -> String {
        let hmacKey = resolveHmacKey(aesKey: aesKey, explicitHmacKey: explicitHmacKey)
        let canonical = canonicalJSON(obj)
        let data = Data(Array(canonical.utf8))
        let authCode = HMAC<SHA256>.authenticationCode(for: data, using: hmacKey)
        let bytes = authCode.withUnsafeBytes { Array($0) }
        let result = Data(bytes).base64EncodedString()
        SGLogger.shared.log("SGSupporters.HMAC", "computeHmac: canonicalLen=\(canonical.count), resultLen=\(result.count), explicitKey=\(explicitHmacKey != nil)")
        return result
    }

    /// Add ts and hmac to payload before encryption.
    private static func signPayload(_ obj: inout [String: Any], aesKey: String, explicitHmacKey: String?) {
        obj["ts"] = Int(Date().timeIntervalSince1970)
        obj["hmac"] = computeHmac(obj, aesKey: aesKey, explicitHmacKey: explicitHmacKey)
        SGLogger.shared.log("SGSupporters.HMAC", "signPayload: ts=\(obj["ts"] ?? "?"), keys=\(obj.keys.sorted().joined(separator: ","))")
    }

    /// Constant-time HMAC comparison to prevent timing attacks.
    private static func secureCompare(_ a: String, _ b: String) -> Bool {
        guard let aData = Data(base64Encoded: a), let bData = Data(base64Encoded: b) else {
            return false
        }
        guard aData.count == bData.count else { return false }
        var result: UInt8 = 0
        for i in 0..<aData.count {
            result |= aData[i] ^ bData[i]
        }
        return result == 0
    }

    /// Verify ts (±5 min) and hmac. Throws if invalid.
    private static func verifySignedPayload(_ obj: [String: Any], aesKey: String, explicitHmacKey: String?) throws {
        guard let receivedHmac = obj["hmac"] as? String else {
            SGLogger.shared.log("SGSupporters.HMAC", "verifySignedPayload: missing hmac")
            throw SupportersCryptoError.invalidPayload
        }
        var copy = obj
        copy.removeValue(forKey: "hmac")
        let expected = computeHmac(copy, aesKey: aesKey, explicitHmacKey: explicitHmacKey)
        guard secureCompare(receivedHmac, expected) else {
            SGLogger.shared.log("SGSupporters.HMAC", "verifySignedPayload: HMAC mismatch (receivedLen=\(receivedHmac.count), expectedLen=\(expected.count))")
            throw SupportersCryptoError.invalidPayload
        }
        guard let ts = obj["ts"] as? Int else {
            SGLogger.shared.log("SGSupporters.HMAC", "verifySignedPayload: missing ts")
            throw SupportersCryptoError.invalidPayload
        }
        let now = Int(Date().timeIntervalSince1970)
        guard abs(now - ts) <= TS_MAX_AGE_SEC else {
            SGLogger.shared.log("SGSupporters.HMAC", "verifySignedPayload: ts expired (ts=\(ts), now=\(now), diff=\(abs(now - ts)))")
            throw SupportersCryptoError.invalidPayload
        }
        SGLogger.shared.log("SGSupporters.HMAC", "verifySignedPayload: ok ts=\(ts)")
    }

    /// Safe JSON encoding to Data, avoids JSONSerialization.data (crashes on iOS 16+).
    public static func jsonData(from obj: Any) -> Data {
        Data(Array(canonicalJSON(obj, excludeHmac: false).utf8))
    }

    /// Encrypt payload with ts + hmac. Server format: IV (12) + authTag (16) + ciphertext.
    /// Uses manual JSON encoding to avoid JSONSerialization.data (crashes with NSData dataWithBytesNoCopy on iOS 16+).
    static func encrypt(_ payload: [String: Any], key: String, hmacKey: String? = nil) throws -> String {
        var obj = payload
        signPayload(&obj, aesKey: key, explicitHmacKey: hmacKey)
        let keyMaterial = normalizeKey(key)
        let plaintext = Data(Array(canonicalJSON(obj, excludeHmac: false).utf8))
        let nonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(plaintext, using: keyMaterial, nonce: nonce)
        guard let combined = sealed.combined, combined.count >= ivLength + authTagLength else {
            throw SupportersCryptoError.sealFailed
        }
        let noncePart = Array(combined.prefix(ivLength))
        let tagPart = Array(combined.suffix(authTagLength))
        let cipherPart = Array(combined.dropFirst(ivLength).dropLast(authTagLength))
        let forServer = Data(noncePart) + Data(tagPart) + Data(cipherPart)
        return forServer.base64EncodedString()
    }

    /// Decrypt and verify ts + hmac. Throws if invalid or expired.
    static func decrypt(_ base64Payload: String, key: String, hmacKey: String? = nil) throws -> [String: Any] {
        guard let raw = Data(base64Encoded: base64Payload), raw.count > ivLength + authTagLength else {
            throw SupportersCryptoError.invalidPayload
        }
        let iv = Array(raw.prefix(ivLength))
        let tag = raw.subdata(in: ivLength..<(ivLength + authTagLength))
        let ciphertext = Array(raw.suffix(from: ivLength + authTagLength))
        let combinedForCryptoKit = Data(iv) + Data(ciphertext) + Data(tag)
        let keyMaterial = normalizeKey(key)
        let sealed = try AES.GCM.SealedBox(combined: combinedForCryptoKit)
        let decrypted = try AES.GCM.open(sealed, using: keyMaterial)
        let json = try JSONSerialization.jsonObject(with: decrypted) as? [String: Any]
        guard let json = json else { throw SupportersCryptoError.invalidPayload }
        try verifySignedPayload(json, aesKey: key, explicitHmacKey: hmacKey)
        return json
    }
}

enum SupportersCryptoError: Error {
    case sealFailed
    case invalidPayload
}
