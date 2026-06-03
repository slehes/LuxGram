import Foundation
import Compression

/// Result of installing a .deb: package name/version (if parsed) and list of installed .dylib filenames.
public struct DebInstallResult {
    public let packageName: String?
    public let packageVersion: String?
    public let installedDylibs: [String]
}

/// Extracts .dylib files from a .deb and installs them into TweakLoader's directory.
public enum DebExtractor {
    private static let arMagic = "!<arch>\n"
    private static let arMagicData = Data(arMagic.utf8)

    /// Install .deb: extract data archive, find all .dylib, copy to Tweaks directory.
    /// Supports data.tar.gz and data.tar.lzma. Returns installed dylib filenames or throws.
    public static func installDeb(from url: URL, tweaksDirectory: URL) throws -> DebInstallResult {
        let data = try Data(contentsOf: url)
        let (controlName, controlVersion) = parseControl(from: data)
        let dataTar = try extractDataTar(from: data)
        let (tempDir, dylibEntries) = try listDylibsInTar(data: dataTar)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: tweaksDirectory, withIntermediateDirectories: true)
        var installed: [String] = []
        for entry in dylibEntries {
            let name = (entry.path as NSString).lastPathComponent
            guard name.lowercased().hasSuffix(".dylib") else { continue }
            let dest = tweaksDirectory.appendingPathComponent(name)
            if fileManager.fileExists(atPath: dest.path) { try? fileManager.removeItem(at: dest) }
            try fileManager.copyItem(at: entry.url, to: dest)
            installed.append(name)
        }
        if installed.isEmpty {
            throw NSError(domain: "DebExtractor", code: 2, userInfo: [NSLocalizedDescriptionKey: "No .dylib files found in the .deb package"])
        }
        return DebInstallResult(packageName: controlName, packageVersion: controlVersion, installedDylibs: installed)
    }

    /// Parse ar archive and return raw content of member whose name starts with `prefix`.
    private static func readArMember(data: Data, namePrefix: String) -> Data? {
        guard data.count >= 8, data.prefix(8).elementsEqual(arMagicData) else { return nil }
        var offset = 8
        while offset + 60 <= data.count {
            let header = data.subdata(in: offset ..< offset + 60)
            guard let name = String(data: header.prefix(16), encoding: .ascii)?.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\0"))),
                  let sizeStr = String(data: header.subdata(in: 48 ..< 58), encoding: .ascii)?.trimmingCharacters(in: .whitespaces),
                  let size = Int(sizeStr, radix: 10), size >= 0 else {
                break
            }
            offset += 60
            if name == "/" || name.isEmpty { offset += size; if size % 2 != 0 { offset += 1 }; continue }
            if name.hasPrefix(namePrefix) {
                guard offset + size <= data.count else { return nil }
                return data.subdata(in: offset ..< offset + size)
            }
            offset += size
            if offset % 2 != 0 { offset += 1 }
        }
        return nil
    }

    /// Parse control.tar.gz to get Package and Version (optional).
    private static func parseControl(from debData: Data) -> (name: String?, version: String?) {
        guard let controlTar = readArMember(data: debData, namePrefix: "control.tar") else { return (nil, nil) }
        let decompressed: Data
        if controlTar.prefix(2) == Data([0x1f, 0x8b]) {
            guard let d = decompressGzip(controlTar) else { return (nil, nil) }
            decompressed = d
        } else {
            decompressed = controlTar
        }
        guard let controlFile = readFileFromTar(data: decompressed, nameSuffix: "control") else { return (nil, nil) }
        guard let str = String(data: controlFile, encoding: .utf8) else { return (nil, nil) }
        var name: String?
        var version: String?
        for line in str.components(separatedBy: .newlines) {
            if line.hasPrefix("Package:") { name = line.dropFirst(8).trimmingCharacters(in: .whitespaces) }
            if line.hasPrefix("Version:") { version = line.dropFirst(8).trimmingCharacters(in: .whitespaces) }
        }
        return (name, version)
    }

    /// Extract data.tar.* from .deb and decompress to raw tar.
    private static func extractDataTar(from debData: Data) throws -> Data {
        guard let dataMember = readArMember(data: debData, namePrefix: "data.tar") else {
            throw NSError(domain: "DebExtractor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid .deb: no data.tar found"])
        }
        if dataMember.prefix(2) == Data([0x1f, 0x8b]) {
            guard let d = decompressGzip(dataMember) else {
                throw NSError(domain: "DebExtractor", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to decompress data.tar.gz"])
            }
            return d
        }
        if dataMember.prefix(3).elementsEqual(Data([0x5d, 0x00, 0x00])) || dataMember.prefix(1) == Data([0x5d]) {
            guard let d = decompressLzma(dataMember) else {
                throw NSError(domain: "DebExtractor", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to decompress data.tar.lzma"])
            }
            return d
        }
        return dataMember
    }

    /// List .dylib entries in tar; extract each to a temp file and return (tempDir, entries). Caller must remove tempDir after copying.
    private static func listDylibsInTar(data: Data) throws -> (tempDir: URL, entries: [(path: String, url: URL)]) {
        var results: [(path: String, url: URL)] = []
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        var offset = 0
        while offset + 512 <= data.count {
            let header = data.subdata(in: offset ..< offset + 512)
            if header.prefix(257).allSatisfy({ $0 == 0 }) { break }
            guard let name = String(data: header.prefix(100), encoding: .ascii)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0")) else {
                offset += 512
                continue
            }
            let sizeStr = String(data: header.subdata(in: 124 ..< 136), encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "0"
            let size = Int(sizeStr, radix: 8) ?? 0
            offset += 512
            let contentStart = offset
            offset += (size + 511) / 512 * 512
            guard name.hasSuffix(".dylib"), size > 0, contentStart + size <= data.count else { continue }
            let content = data.subdata(in: contentStart ..< contentStart + size)
            let base = (name as NSString).lastPathComponent
            let tmpFile = tmpDir.appendingPathComponent(base)
            try content.write(to: tmpFile)
            results.append((name, tmpFile))
        }
        return (tmpDir, results)
    }

    /// Read first file from tar that has given name suffix (e.g. "control").
    private static func readFileFromTar(data: Data, nameSuffix: String) -> Data? {
        var offset = 0
        while offset + 512 <= data.count {
            let header = data.subdata(in: offset ..< offset + 512)
            if header.prefix(257).allSatisfy({ $0 == 0 }) { break }
            guard let name = String(data: header.prefix(100), encoding: .ascii)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0")),
                  name.hasSuffix(nameSuffix) else {
                let sizeStr = String(data: header.subdata(in: 124 ..< 136), encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "0"
                let size = Int(sizeStr, radix: 8) ?? 0
                offset += 512 + (size + 511) / 512 * 512
                continue
            }
            let sizeStr = String(data: header.subdata(in: 124 ..< 136), encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "0"
            let size = Int(sizeStr, radix: 8) ?? 0
            offset += 512
            guard offset + size <= data.count else { return nil }
            return data.subdata(in: offset ..< offset + size)
        }
        return nil
    }

    private static func decompressGzip(_ data: Data) -> Data? {
        return decompress(data, algorithm: COMPRESSION_ZLIB)
    }

    /// LZMA (e.g. data.tar.lzma).
    private static func decompressLzma(_ data: Data) -> Data? {
        return decompress(data, algorithm: COMPRESSION_LZMA)
    }

    private static func decompress(_ data: Data, algorithm: compression_algorithm) -> Data? {
        let destSize = 16 * 1024 * 1024
        let dest = UnsafeMutablePointer<UInt8>.allocate(capacity: destSize)
        defer { dest.deallocate() }
        let decoded = data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
            compression_decode_buffer(dest, destSize, src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, algorithm)
        }
        guard decoded > 0 else { return nil }
        return Data(bytes: dest, count: decoded)
    }
}
