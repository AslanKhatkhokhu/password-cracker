import Foundation
import CryptoKit
import CommonCrypto

// MARK: - DOC / DOCX Cracker

/// Handles password verification for Microsoft Office documents.
///
/// - **DOCX (OOXML):** ZIP container → [Content_Types].xml or EncryptedPackage.
///   Uses ECMA-376 Agile/Standard encryption with SHA-512 + AES-256-CBC.
/// - **DOC (OLE2 Compound):** Binary format with RC4 or AES encryption.
///
/// Both formats store a password verifier that can be checked without
/// decrypting the full document.
enum DOCCracker {

    // MARK: - Public API

    /// Tries the given password against an encrypted Office document.
    static func tryPassword(_ password: String, fileURL: URL) -> Bool {
        let ext = fileURL.pathExtension.lowercased()
        if ext == "docx" || ext == "xlsx" || ext == "pptx" {
            return tryOOXML(password: password, fileURL: fileURL)
        } else {
            return tryOLE2(password: password, fileURL: fileURL)
        }
    }

    /// Validates that the file exists and appears to be an encrypted Office doc.
    static func validate(url: URL) -> Result<Void, CrackerError> {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure(.fileNotFound)
        }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return .failure(.invalidFile("Cannot read file"))
        }

        let ext = url.pathExtension.lowercased()
        if ext == "docx" || ext == "xlsx" || ext == "pptx" {
            // OOXML: should be a ZIP but if encrypted, starts with OLE2 magic
            if data.count >= 8 {
                let ole2Magic: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
                let header = [UInt8](data.prefix(8))
                if header == ole2Magic {
                    return .success(()) // OLE2-wrapped encrypted OOXML
                }
            }
            // Regular ZIP (not encrypted at the Office level)
            if data.prefix(2) == Data([0x50, 0x4B]) {
                return .failure(.notEncrypted)
            }
            return .failure(.invalidFile("Not a valid Office document"))
        } else {
            // OLE2 .doc — must verify it's actually encrypted
            if data.count >= 8 {
                let ole2Magic: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
                let header = [UInt8](data.prefix(8))
                guard header == ole2Magic else {
                    return .failure(.invalidFile("Not a valid OLE2 document"))
                }
                // Check for EncryptionInfo stream (means it's encrypted OOXML in OLE2)
                if extractOLE2Stream(named: "EncryptionInfo", from: data) != nil {
                    return .success(())
                }
                // Check WordDocument stream for encryption flag in FIB
                if let wordStream = extractOLE2Stream(named: "WordDocument", from: data) {
                    let bytes = [UInt8](wordStream)
                    if bytes.count > 11 {
                        let flags = readUInt16(bytes, offset: 10)
                        if (flags & 0x0100) != 0 {
                            return .success(()) // fEncrypted flag is set
                        }
                    }
                }
                return .failure(.notEncrypted)
            }
            return .failure(.invalidFile("Not a valid OLE2 document"))
        }
    }

    // MARK: - OOXML (docx/xlsx/pptx) Encrypted

    /// Encrypted OOXML files are OLE2 containers with an EncryptionInfo stream
    /// and an EncryptedPackage stream. We parse the encryption header and verify
    /// the password against the stored verifier.
    private static func tryOOXML(password: String, fileURL: URL) -> Bool {
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return false }
        guard let encInfo = extractOLE2Stream(named: "EncryptionInfo", from: data) else { return false }

        // Parse encryption info
        guard let params = parseEncryptionInfo(encInfo) else { return false }

        return verifyPassword(password, params: params)
    }

    // MARK: - OLE2 (legacy .doc)

    /// Legacy .doc uses RC4 or AES encryption stored in the OLE2 compound file.
    /// We look for the "1Table" or "0Table" stream which contains the FIB
    /// (File Information Block) with encryption details.
    private static func tryOLE2(password: String, fileURL: URL) -> Bool {
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return false }

        // Try parsing as encrypted OOXML first (some .doc files are actually OOXML)
        if let encInfo = extractOLE2Stream(named: "EncryptionInfo", from: data),
           let params = parseEncryptionInfo(encInfo) {
            return verifyPassword(password, params: params)
        }

        // Legacy Word Binary Format — look for encryption flag in FIB
        guard let wordStream = extractOLE2Stream(named: "WordDocument", from: data) else { return false }
        return verifyLegacyDoc(password: password, wordStream: wordStream)
    }

    // MARK: - OLE2 Container Parsing

    /// Minimal OLE2 compound binary file parser.
    /// Extracts a named stream from the directory entries.
    private static func extractOLE2Stream(named streamName: String, from data: Data) -> Data? {
        guard data.count > 512 else { return nil }
        let bytes = [UInt8](data)

        // Verify OLE2 magic
        let magic: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
        guard Array(bytes[0..<8]) == magic else { return nil }

        // Read header fields
        let sectorSize = 1 << Int(readUInt16(bytes, offset: 30))
        let firstDirSector = Int(readUInt32(bytes, offset: 48))

        // Read directory entries (each is 128 bytes)
        let dirOffset = 512 + firstDirSector * sectorSize
        guard dirOffset + 128 <= bytes.count else { return nil }

        // Scan directory entries for the target stream
        var offset = dirOffset
        while offset + 128 <= bytes.count {
            let nameLen = Int(readUInt16(bytes, offset: offset + 64))
            if nameLen > 0 && nameLen <= 64 {
                // Name is UTF-16LE
                let nameBytes = Array(bytes[offset..<(offset + min(nameLen, 64))])
                if let name = decodeUTF16LE(nameBytes), name == streamName {
                    let startSector = Int(readUInt32(bytes, offset: offset + 116))
                    let streamSize = Int(readUInt32(bytes, offset: offset + 120))

                    if streamSize > 0 && streamSize < data.count {
                        let streamOffset = 512 + startSector * sectorSize
                        if streamOffset + streamSize <= bytes.count {
                            return Data(bytes[streamOffset..<(streamOffset + streamSize)])
                        }
                    }
                }
            }
            offset += 128
            // Don't scan beyond a reasonable number of entries
            if offset - dirOffset > 128 * 256 { break }
        }

        return nil
    }

    // MARK: - Encryption Info Parsing

    struct EncryptionParams {
        var hashAlgorithm: String // "SHA512", "SHA256", "SHA1"
        var cipherAlgorithm: String // "AES256", "AES128"
        var salt: Data
        var verifierHashInput: Data
        var verifierHashValue: Data
        var keyBits: Int
        var spinCount: Int
        var blockSize: Int
    }

    private static func parseEncryptionInfo(_ data: Data) -> EncryptionParams? {
        let bytes = [UInt8](data)
        guard bytes.count >= 8 else { return nil }

        let vMajor = readUInt16(bytes, offset: 0)
        let vMinor = readUInt16(bytes, offset: 2)

        // Version 4.4 = Agile encryption (XML-based)
        if vMajor == 4 && vMinor == 4 {
            return parseAgileEncryption(bytes)
        }

        // Version 3.2 / 4.2 = Standard encryption
        if (vMajor == 3 || vMajor == 4) && vMinor == 2 {
            return parseStandardEncryption(bytes)
        }

        return nil
    }

    private static func parseAgileEncryption(_ bytes: [UInt8]) -> EncryptionParams? {
        // Skip 8-byte header to get to XML
        guard bytes.count > 8 else { return nil }
        let xmlData = Data(bytes[8...])
        guard let xmlString = String(data: xmlData, encoding: .utf8) else { return nil }

        // Parse key data from XML
        let spinCount = extractXMLAttr(xmlString, tag: "keyData", attr: "spinCount")
            ?? extractXMLAttr(xmlString, tag: "p:encryptedKey", attr: "spinCount")
            ?? "100000"
        let hashAlg = extractXMLAttr(xmlString, tag: "p:encryptedKey", attr: "hashAlgorithm") ?? "SHA512"
        let saltValue = extractXMLAttr(xmlString, tag: "p:encryptedKey", attr: "saltValue") ?? ""
        let encVerifierInput = extractXMLAttr(xmlString, tag: "p:encryptedKey", attr: "encryptedVerifierHashInput") ?? ""
        let encVerifierValue = extractXMLAttr(xmlString, tag: "p:encryptedKey", attr: "encryptedVerifierHashValue") ?? ""
        let keyBits = Int(extractXMLAttr(xmlString, tag: "p:encryptedKey", attr: "keyBits") ?? "256") ?? 256

        guard let salt = Data(base64Encoded: saltValue),
              let vInput = Data(base64Encoded: encVerifierInput),
              let vHash = Data(base64Encoded: encVerifierValue) else { return nil }

        return EncryptionParams(
            hashAlgorithm: hashAlg,
            cipherAlgorithm: keyBits >= 256 ? "AES256" : "AES128",
            salt: salt,
            verifierHashInput: vInput,
            verifierHashValue: vHash,
            keyBits: keyBits,
            spinCount: Int(spinCount) ?? 100000,
            blockSize: keyBits >= 256 ? 32 : 16
        )
    }

    private static func parseStandardEncryption(_ bytes: [UInt8]) -> EncryptionParams? {
        guard bytes.count >= 52 else { return nil }

        // Header at offset 4
        let headerSize = Int(readUInt32(bytes, offset: 8))
        let algID = readUInt32(bytes, offset: 12)
        let keySize = Int(readUInt32(bytes, offset: 20)) // bits

        // Salt starts after header
        let saltOffset = 8 + headerSize
        guard saltOffset + 16 <= bytes.count else { return nil }
        let salt = Data(bytes[saltOffset..<(saltOffset + 16)])

        // Encrypted verifier (16 bytes) + encrypted verifier hash (32 bytes)
        let vOffset = saltOffset + 16
        guard vOffset + 52 <= bytes.count else { return nil }
        let verifierInput = Data(bytes[vOffset..<(vOffset + 16)])
        let verifierHash = Data(bytes[(vOffset + 20)..<(vOffset + 52)])

        let hashAlg = algID == 0x00008004 ? "SHA1" : "SHA256"

        return EncryptionParams(
            hashAlgorithm: hashAlg,
            cipherAlgorithm: keySize >= 256 ? "AES256" : "AES128",
            salt: salt,
            verifierHashInput: verifierInput,
            verifierHashValue: verifierHash,
            keyBits: keySize,
            spinCount: 50000,
            blockSize: keySize >= 256 ? 32 : 16
        )
    }

    // MARK: - Password Verification

    private static func verifyPassword(_ password: String, params: EncryptionParams) -> Bool {
        // Convert password to UTF-16LE
        guard let passData = password.data(using: .utf16LittleEndian) else { return false }

        // Derive key: H0 = hash(salt + password)
        let hashData = params.salt + passData
        var hash = computeHash(hashData, algorithm: params.hashAlgorithm)

        // Iterate: Hi = hash(i + H(i-1))
        for i in 0..<params.spinCount {
            var iterData = Data()
            withUnsafeBytes(of: UInt32(i).littleEndian) { iterData.append(contentsOf: $0) }
            iterData.append(hash)
            hash = computeHash(iterData, algorithm: params.hashAlgorithm)
        }

        // Derive decryption key for verifier
        let verifierInputKey = deriveKey(hash, blockKey: Data([0xfe, 0xa7, 0xd2, 0x76, 0x3b, 0x4b, 0x9e, 0x79]),
                                          hashAlg: params.hashAlgorithm, keyBytes: params.blockSize)

        // Decrypt verifier hash input
        guard let decryptedInput = aesDecrypt(data: params.verifierHashInput, key: verifierInputKey) else { return false }

        // Derive key for verifier hash value
        let verifierHashKey = deriveKey(hash, blockKey: Data([0xd7, 0xaa, 0x0f, 0x1a, 0x27, 0x65, 0x99, 0x8b]),
                                         hashAlg: params.hashAlgorithm, keyBytes: params.blockSize)

        guard let decryptedHash = aesDecrypt(data: params.verifierHashValue, key: verifierHashKey) else { return false }

        // Hash the decrypted input and compare
        let computedHash = computeHash(decryptedInput, algorithm: params.hashAlgorithm)
        let hashLen = computedHash.count
        guard decryptedHash.count >= hashLen else { return false }

        return computedHash == decryptedHash.prefix(hashLen)
    }

    private static func deriveKey(_ hash: Data, blockKey: Data, hashAlg: String, keyBytes: Int) -> Data {
        let derived = computeHash(hash + blockKey, algorithm: hashAlg)
        if derived.count >= keyBytes {
            return derived.prefix(keyBytes)
        }
        // Pad with 0x36 if needed
        var padded = derived
        while padded.count < keyBytes { padded.append(0x36) }
        return padded.prefix(keyBytes)
    }

    // MARK: - Legacy DOC Verification

    private static func verifyLegacyDoc(password: String, wordStream: Data) -> Bool {
        guard wordStream.count >= 16 else { return false }
        let bytes = [UInt8](wordStream)

        // Read FIB base — check fEncrypted flag at offset 10, bit 0x100
        guard bytes.count > 11 else { return false }
        let flags = readUInt16(bytes, offset: 10)
        let isEncrypted = (flags & 0x0100) != 0
        guard isEncrypted else { return false }

        // Encryption type at offset in FIB table
        // For XOR obfuscation (simple), key and verifier at specific offsets
        let clsidOffset = Int(readUInt32(bytes, offset: 68))
        guard clsidOffset > 0, clsidOffset + 4 <= bytes.count else { return false }

        let encType = readUInt32(bytes, offset: clsidOffset)
        if encType == 1 {
            // RC4 encryption — uses standard CryptoAPI
            // Similar to OOXML standard encryption
            return false // Simplified — full RC4 implementation would go here
        }

        // XOR obfuscation (very old docs)
        if encType == 0 || clsidOffset == 0 {
            return verifyXORObfuscation(password: password, bytes: bytes)
        }

        return false
    }

    private static func verifyXORObfuscation(password: String, bytes: [UInt8]) -> Bool {
        // XOR obfuscation uses a simple 16-bit key derived from password
        guard bytes.count > 36 else { return false }
        let storedKey = readUInt16(bytes, offset: 34)
        _ = readUInt16(bytes, offset: 36)

        let passBytes = Array(password.utf8).map { UInt8($0) }
        guard !passBytes.isEmpty else { return false }

        // Compute XOR key
        var key: UInt16 = 0
        for b in passBytes {
            key = ((key >> 14) & 0x01) | ((key << 1) & 0x7FFF)
            key ^= UInt16(b)
        }
        key = ((key >> 14) & 0x01) | ((key << 1) & 0x7FFF)
        key ^= UInt16(passBytes.count)
        key ^= 0xCE4B

        return key == storedKey
    }

    // MARK: - Crypto Helpers

    private static func computeHash(_ data: Data, algorithm: String) -> Data {
        switch algorithm.uppercased() {
        case "SHA512", "SHA-512":
            return Data(SHA512.hash(data: data))
        case "SHA256", "SHA-256":
            return Data(SHA256.hash(data: data))
        case "SHA1", "SHA-1":
            return sha1(data)
        default:
            return Data(SHA256.hash(data: data))
        }
    }

    private static func sha1(_ data: Data) -> Data {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA1(buffer.baseAddress, CC_LONG(data.count), &digest)
        }
        return Data(digest)
    }

    private static func aesDecrypt(data: Data, key: Data) -> Data? {
        let keyLength: Int
        if key.count <= 16 { keyLength = kCCKeySizeAES128 }
        else if key.count <= 24 { keyLength = kCCKeySizeAES192 }
        else { keyLength = kCCKeySizeAES256 }

        let bufferSize = data.count + kCCBlockSizeAES128
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var decryptedSize = 0

        // ECB mode (no IV) for verifier decryption
        let status = key.withUnsafeBytes { keyPtr in
            data.withUnsafeBytes { dataPtr in
                CCCrypt(
                    CCOperation(kCCDecrypt),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCOptions(kCCOptionECBMode),
                    keyPtr.baseAddress, keyLength,
                    nil, // no IV for ECB
                    dataPtr.baseAddress, data.count,
                    &buffer, bufferSize,
                    &decryptedSize
                )
            }
        }

        guard status == kCCSuccess else { return nil }
        return Data(buffer.prefix(decryptedSize))
    }

    // MARK: - Binary Helpers

    private static func readUInt16(_ bytes: [UInt8], offset: Int) -> UInt16 {
        guard offset + 1 < bytes.count else { return 0 }
        return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt32(_ bytes: [UInt8], offset: Int) -> UInt32 {
        guard offset + 3 < bytes.count else { return 0 }
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func decodeUTF16LE(_ bytes: [UInt8]) -> String? {
        // Remove null terminator
        var cleaned = bytes
        while cleaned.count >= 2 && cleaned[cleaned.count - 1] == 0 && cleaned[cleaned.count - 2] == 0 {
            cleaned.removeLast(2)
        }
        return String(data: Data(cleaned), encoding: .utf16LittleEndian)
    }

    // MARK: - XML Attribute Helper

    private static func extractXMLAttr(_ xml: String, tag: String, attr: String) -> String? {
        // Find the tag
        guard let tagRange = xml.range(of: tag) else { return nil }
        let afterTag = xml[tagRange.upperBound...]

        // Find the attribute
        let pattern = attr + "=\""
        guard let attrStart = afterTag.range(of: pattern) else { return nil }
        let valueStart = afterTag[attrStart.upperBound...]
        guard let quoteEnd = valueStart.firstIndex(of: "\"") else { return nil }
        return String(valueStart[..<quoteEnd])
    }
}
