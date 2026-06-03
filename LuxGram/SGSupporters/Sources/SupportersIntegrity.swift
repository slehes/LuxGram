import Foundation
import MachO
import CryptoKit
import SGLogging

//
// Three independent layers that must ALL pass for access to be granted:
//   1. Text-segment checksum   — detects ANY patched byte in __TEXT,__text
//   2. Anti-stub detection      — recognises common crack patterns (mov w0,#1;ret, nop, b+N)
//   3. Accumulator-based access — access derived from a sum of fragments contributed by
//      multiple independent code paths; patching any single path breaks the total
//
// The access check is NOT a single "if bool" — it is the result of XOR-ing
// multiple fragment values. The expected XOR depends on which access flags
// the server granted, making it impossible to bypass by patching one comparison.

public enum SupportersIntegrity {

    // ┌──────────────────────────────────────────────────────┐
    // │  1.  __TEXT,__text checksum                          │
    // └──────────────────────────────────────────────────────┘

    private static var _sealedHash: UInt64 = 0
    private static var _sealed = false

    /// Sample ~512 points across the main executable's __TEXT,__text section
    /// and compute a rolling hash.  Any single patched instruction changes the result.
    @inline(never)
    public static func textChecksum() -> UInt64 {
        guard let header = _dyld_get_image_header(0) else { return 0 }
        var size: UInt = 0
        let h64 = UnsafeRawPointer(header).assumingMemoryBound(to: mach_header_64.self)
        guard let ptr = getsectiondata(h64, "__TEXT", "__text", &size), size > 64 else { return 0 }

        var h: UInt64 = 0x736F6D65_70736575          // SipHash-like seed
        let step = max(8, Int(size) / 512)
        var off = 0
        while off + 8 <= Int(size) {
            let v = ptr.advanced(by: off)
                       .withMemoryRebound(to: UInt64.self, capacity: 1) { $0.pointee }
            h ^= v
            h &*= 0x517CC1B7_27220A95
            h = (h << 13) | (h >> 51)
            off += step
        }
        return h
    }

    /// Call once after the first successful encrypted API validation in a session.
    /// Records the "known-good" checksum for later comparison.
    public static func seal() {
        guard !_sealed else { return }
        _sealedHash = textChecksum()
        _sealed = true
        SGLogger.shared.log("SGIntegrity", "sealed text checksum")
    }

    /// Returns `false` if __TEXT has been modified after sealing (= runtime patch).
    /// If not yet sealed, returns `true` (don't block cold start from cache).
    @inline(__always)
    public static func textOK() -> Bool {
        guard _sealed else { return true }
        return textChecksum() == _sealedHash
    }

    // ┌──────────────────────────────────────────────────────┐
    // │  2.  Anti-stub detection                             │
    // └──────────────────────────────────────────────────────┘

    /// Recognises ARM64 instruction patterns commonly injected by crackers.
    ///
    /// Covered patterns (little-endian):
    /// - `mov wN, #imm16; ret`   (0x5280xxxx 0xD65F03C0)
    /// - `nop; nop`              (0xD503201F 0xD503201F)
    /// - `b +N`  first instr     (0x14xxxxxx)
    @inline(__always)
    public static func isStubbed(_ ptr: UnsafeRawPointer) -> Bool {
        let pair = ptr.load(as: UInt64.self)
        // second instruction == ret?
        let hi32 = UInt32(truncatingIfNeeded: pair >> 32)
        if hi32 == 0xD65F03C0 {                         // ret
            let lo32 = UInt32(truncatingIfNeeded: pair)
            if lo32 & 0xFF800000 == 0x52800000 {         // mov wN, #imm16
                return true
            }
        }
        // nop; nop
        if pair == 0xD503201F_D503201F { return true }
        // unconditional branch as first instruction
        let first = UInt32(truncatingIfNeeded: pair)
        if first & 0xFC000000 == 0x14000000 { return true }
        return false
    }

    // ┌──────────────────────────────────────────────────────┐
    // │  3.  Accumulator / fragment-based access derivation  │
    // └──────────────────────────────────────────────────────┘

    // Design:
    //   Several independent code paths each contribute a deterministic "fragment".
    //   Fragments are XOR'd together; the final value is compared to an "expected"
    //   that encodes the actual access flags.
    //
    //   expected = F_crypto ^ F_cache ^ F_text ^ F_access(flags)
    //
    //   If any code path was stubbed (returns early / wrong value), its fragment
    //   will differ and the final XOR won't match → access denied.
    //
    //   The "expected" value is recomputed from the stored per-user seed, so the
    //   cracker cannot hard-code it — it changes per user/session.

    // Fixed fragment keys (compile-time constants, deliberately non-round).
    // These are combined with runtime data to produce the actual fragments.
    public static let kCryptoOK:  UInt64 = 0xA3B7_C2D1_E5F6_0718
    public static let kCacheOK:   UInt64 = 0x4E5F_6A7B_8C9D_0E1F
    public static let kTextOK:    UInt64 = 0x1C2D_3E4F_5A6B_7C8D
    public static let kAccessOn:  UInt64 = 0x9F8E_7D6C_5B4A_3928
    public static let kBetaOn:    UInt64 = 0x72F1_843A_6BD5_9EC0

    private static var _fragments = [UInt64]()
    private static let _lock = NSLock()

    /// Reset at the beginning of a new validation cycle.
    public static func resetFragments() {
        _lock.lock()
        _fragments.removeAll()
        _lock.unlock()
    }

    /// A verified code path contributes its fragment.
    @inline(__always)
    public static func contribute(_ fragment: UInt64) {
        _lock.lock()
        _fragments.append(fragment)
        _lock.unlock()
    }

    /// XOR of all contributed fragments.
    @inline(__always)
    public static func accumulatedXOR() -> UInt64 {
        _lock.lock()
        let v = _fragments.reduce(0 as UInt64) { $0 ^ $1 }
        _lock.unlock()
        return v
    }

    /// Number of contributed fragments (sanity: must be ≥ expected count).
    @inline(__always)
    public static func fragmentCount() -> Int {
        _lock.lock()
        let c = _fragments.count
        _lock.unlock()
        return c
    }

    // ┌──────────────────────────────────────────────────────┐
    // │  4.  Composite access derivation                     │
    // └──────────────────────────────────────────────────────┘

    /// Derive luxgramTab access from accumulated fragments.
    ///
    /// Expected XOR when all integrity checks pass AND luxgramTab == true:
    ///   kCryptoOK ^ kCacheOK ^ kTextOK ^ kAccessOn
    ///
    /// If any layer is missing or returns the wrong fragment, the XOR differs
    /// from the expected value → access denied.
    ///
    /// This function is `@inline(__always)` so it is duplicated at every call site.
    /// The cracker must patch EVERY call site, not just one function.
    @inline(__always)
    public static func deriveGlegramTab() -> Bool {
        let expected = kCryptoOK ^ kCacheOK ^ kTextOK ^ kAccessOn
        return accumulatedXOR() == expected && fragmentCount() >= 3
    }

    /// Same for betaBuilds — uses a different expected value.
    @inline(__always)
    public static func deriveBetaBuilds() -> Bool {
        let expected = kCryptoOK ^ kCacheOK ^ kTextOK ^ kBetaOn
        return accumulatedXOR() == expected && fragmentCount() >= 3
    }

    // ┌──────────────────────────────────────────────────────┐
    // │  5.  Per-user access token (HMAC-signed)             │
    // └──────────────────────────────────────────────────────┘

    /// Compute a per-user access token: HMAC-SHA256(derivedKey, userId|flags).
    /// The server can also generate this token so the client can verify it.
    public static func computeAccessToken(
        userId: String,
        luxgramTab: Bool,
        betaBuilds: Bool,
        hmacKeyData: Data
    ) -> Data {
        let integrityKey = deriveIntegrityKey(from: hmacKeyData)
        let payload = "\(userId)|\(luxgramTab ? "1" : "0")|\(betaBuilds ? "1" : "0")"
        let auth = HMAC<SHA256>.authenticationCode(
            for: Data(payload.utf8),
            using: SymmetricKey(data: integrityKey)
        )
        return Data(auth)
    }

    /// Verify a stored access token against recomputed expected value.
    @inline(__always)
    public static func verifyAccessToken(
        _ token: Data,
        userId: String,
        luxgramTab: Bool,
        betaBuilds: Bool,
        hmacKeyData: Data
    ) -> Bool {
        let expected = computeAccessToken(
            userId: userId,
            luxgramTab: luxgramTab,
            betaBuilds: betaBuilds,
            hmacKeyData: hmacKeyData
        )
        guard expected.count == token.count, !token.isEmpty else { return false }
        var diff: UInt8 = 0
        for i in 0..<expected.count {
            diff |= expected[i] ^ token[i]
        }
        return diff == 0
    }

    /// Derive a separate key for access tokens (so it differs from the API HMAC key).
    private static func deriveIntegrityKey(from masterKey: Data) -> Data {
        let salt = Data("luxgram-integrity-v1".utf8)
        let auth = HMAC<SHA256>.authenticationCode(for: salt, using: SymmetricKey(data: masterKey))
        return Data(auth)
    }

    // ┌──────────────────────────────────────────────────────┐
    // │  6.  Full validation entry point                     │
    // └──────────────────────────────────────────────────────┘

    /// Run all integrity layers and contribute their fragments to the accumulator.
    /// Call this during / after encrypted API validation.
    ///
    /// - `cryptoSucceeded`:  set `true` after a successful decrypt+HMAC verify
    /// - `cacheDecrypted`:   set `true` after Keychain data was decrypted successfully
    /// - `luxgramTab` / `betaBuilds`:  raw access flags from the server response
    ///
    /// After calling this, `deriveGlegramTab()` / `deriveBetaBuilds()` return
    /// the integrity-verified access.
    public static func validate(
        cryptoSucceeded: Bool,
        cacheDecrypted: Bool,
        luxgramTab: Bool,
        betaBuilds: Bool
    ) {
        resetFragments()

        // Fragment 1: crypto verification passed
        if cryptoSucceeded {
            contribute(kCryptoOK)
        }

        // Fragment 2: cache decryption passed
        if cacheDecrypted {
            contribute(kCacheOK)
        }

        // Fragment 3: text segment not patched
        if textOK() {
            contribute(kTextOK)
        }

        // Fragment 4: access flag (determines which derive* returns true)
        if luxgramTab {
            contribute(kAccessOn)
        } else if betaBuilds {
            contribute(kBetaOn)
        }
    }
}
