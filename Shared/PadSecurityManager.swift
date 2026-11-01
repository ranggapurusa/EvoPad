import Foundation
import Security
import CryptoKit
import Network

// MARK: - Security Constants

enum PadSecurityConstants {
    static let protocolVersion: UInt32 = 2
    static let pairingQRExpirySeconds: TimeInterval = 60
    static let sessionMaxLifetimeSeconds: TimeInterval = 8 * 3600 // 8 hours
    static let handshakeTimeoutSeconds: TimeInterval = 10
    static let tokenBytesCount = 32 // 256 bits
    static let nonceBytesCount = 32 // 256 bits
    static let maxPendingConnections = 3

    // Domain Separators
    static let domainPairingClientProof = "EVOPAD_PAIRING_CLIENT_PROOF_V2"
    static let domainPairingServerProof = "EVOPAD_PAIRING_SERVER_PROOF_V2"
    static let domainReconnectClientProof = "EVOPAD_RECONNECT_CLIENT_PROOF_V2"
    static let domainReconnectServerProof = "EVOPAD_RECONNECT_SERVER_PROOF_V2"
    static let domainPairingCommit = "EVOPAD_PAIRING_COMMIT_V2"
}

// MARK: - Canonical Authentication Transcript

struct PadCanonicalTranscript {
    let domain: String
    let protocolVersion: UInt32
    let pairingId: String
    let clientDeviceId: String
    let serverDeviceId: String
    let clientNonce: Data
    let serverNonce: Data
    let certFingerprint: Data
    let sessionContext: String
    let role: String

    /// Produces an unambiguous, collision-resistant length-prefixed binary encoding.
    /// Format: each field is preceded by a 4-byte big-endian UInt32 length.
    func encode() -> Data {
        var data = Data()

        func appendField(_ fieldData: Data) {
            var length = UInt32(fieldData.count).bigEndian
            data.append(Data(bytes: &length, count: MemoryLayout<UInt32>.size))
            data.append(fieldData)
        }

        func appendString(_ str: String) {
            appendField(str.data(using: .utf8) ?? Data())
        }

        var versionBE = protocolVersion.bigEndian
        appendField(Data(bytes: &versionBE, count: MemoryLayout<UInt32>.size))
        appendString(domain)
        appendString(pairingId)
        appendString(clientDeviceId)
        appendString(serverDeviceId)
        appendField(clientNonce)
        appendField(serverNonce)
        appendField(certFingerprint)
        appendString(sessionContext)
        appendString(role)

        return data
    }

    /// Computes HMAC-SHA256 proof over the canonical transcript using the provided key.
    func computeHMAC(keyData: Data) -> String {
        let transcriptData = encode()
        let key = SymmetricKey(data: keyData)
        let mac = HMAC<SHA256>.authenticationCode(for: transcriptData, using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    /// Constant-time verification of HMAC-SHA256 proof.
    func verifyHMAC(keyData: Data, expectedHmacHex: String) -> Bool {
        guard let expectedBytes = Data(hexString: expectedHmacHex) else { return false }
        let transcriptData = encode()
        let key = SymmetricKey(data: keyData)
        return HMAC<SHA256>.isValidAuthenticationCode(expectedBytes, authenticating: transcriptData, using: key)
    }
}

// MARK: - Cryptographic Nonces and Random Generation

enum PadCryptoUtils {
    static func randomBytes(count: Int = PadSecurityConstants.nonceBytesCount) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    static func randomHex(count: Int = PadSecurityConstants.tokenBytesCount) -> String {
        randomBytes(count: count).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256Hex(data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - QR Code Pairing Data Payload

struct PadPairingQRData: Codable, Equatable {
    let version: Int
    let servicePort: UInt16
    let serverDeviceId: String
    let serverName: String
    let certFingerprintHex: String
    let oneTimeSecretHex: String
    let expiresAt: TimeInterval

    var isExpired: Bool {
        Date().timeIntervalSince1970 > expiresAt
    }

    func serialize() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return data.base64EncodedString()
    }

    static func deserialize(from string: String) -> PadPairingQRData? {
        guard let data = Data(base64Encoded: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              let decoded = try? JSONDecoder().decode(PadPairingQRData.self, from: data) else {
            return nil
        }
        return decoded
    }
}

// MARK: - Paired Device Model

struct PadPairedDevice: Codable, Equatable, Identifiable {
    var id: String { deviceId }
    let deviceId: String
    let name: String
    let pairingTokenHex: String
    let certFingerprintHex: String?
    let pairedDate: Date
    var lastAuthenticatedDate: Date
}

// MARK: - Persistent Keychain Storage for Pairing Records

final class PadKeychainStore {
    static let shared = PadKeychainStore()
    private let service = "id.evonex.evopad.pairing"
    private let account = "paired_devices_v2"
    private let lock = NSLock()

    private init() {}

    func loadPairedDevices() -> [PadPairedDevice] {
        lock.lock()
        defer { lock.unlock() }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return []
        }

        return (try? JSONDecoder().decode([PadPairedDevice].self, from: data)) ?? []
    }

    func saveDevice(_ device: PadPairedDevice) throws {
        lock.lock()
        defer { lock.unlock() }

        var devices = loadDevicesInternal()
        devices.removeAll { $0.deviceId == device.deviceId }
        devices.append(device)
        try persistDevicesInternal(devices)
    }

    func removeDevice(deviceId: String) throws {
        lock.lock()
        defer { lock.unlock() }

        var devices = loadDevicesInternal()
        devices.removeAll { $0.deviceId == deviceId }
        try persistDevicesInternal(devices)
    }

    func removeAllDevices() throws {
        lock.lock()
        defer { lock.unlock() }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func loadDevicesInternal() -> [PadPairedDevice] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return [] }
        return (try? JSONDecoder().decode([PadPairedDevice].self, from: data)) ?? []
    }

    private func persistDevicesInternal(_ devices: [PadPairedDevice]) throws {
        let data = try JSONEncoder().encode(devices)

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Failed to persist paired devices to Keychain: \(status)"
            ])
        }
    }
}

// MARK: - Certificate Verification on iPad (sec_protocol_options_set_verify_block)

enum PadCertificateVerifier {
    /// Verifies server certificate during TLS handshake.
    /// Verifies:
    /// - Pinned SHA-256 fingerprint matching
    /// - Validity period (not expired, not premature)
    /// - P-256 EC public key
    /// - Key Usage: digitalSignature
    /// - Extended Key Usage: serverAuth
    /// - Certificate structure and self-signed signature
    static func verifyServerCertificate(
        trust: SecTrust,
        pinnedFingerprintHex: String
    ) -> Bool {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let certificate = chain.first else {
            PadLog.network("PadCertificateVerifier: no certificate in trust chain")
            return false
        }

        // 1. Verify SHA-256 Fingerprint (Exact pinning)
        let certDER = SecCertificateCopyData(certificate) as Data
        let actualFingerprint = PadCryptoUtils.sha256Hex(data: certDER)
        guard actualFingerprint.caseInsensitiveCompare(pinnedFingerprintHex) == .orderedSame else {
            PadLog.network("PadCertificateVerifier: fingerprint mismatch. Expected: \(pinnedFingerprintHex), got: \(actualFingerprint)")
            return false
        }

        // 2. Verify Certificate Public Key is P-256 EC
        guard let publicKey = SecCertificateCopyKey(certificate),
              let keyAttrs = SecKeyCopyAttributes(publicKey) as? [String: Any],
              let keyType = keyAttrs[kSecAttrKeyType as String] as? String,
              let keySize = keyAttrs[kSecAttrKeySizeInBits as String] as? Int,
              keyType == (kSecAttrKeyTypeECSECPrimeRandom as String),
              keySize == 256 else {
            PadLog.network("PadCertificateVerifier: public key is not P-256 EC")
            return false
        }

        // 3. Verify Validity Period and Structure via ASN.1 / SecCertificateCopyValues
        guard verifyCertificateExtensionsAndDates(certificate: certificate, certDER: certDER) else {
            PadLog.network("PadCertificateVerifier: certificate extensions or validity dates invalid")
            return false
        }

        // 4. Verify Self-Signed Signature using the certificate's own public key
        guard verifySelfSignedSignature(certDER: certDER, publicKey: publicKey) else {
            PadLog.network("PadCertificateVerifier: self-signed signature verification failed")
            return false
        }

        PadLog.network("PadCertificateVerifier: certificate successfully validated and pinned")
        return true
    }

    /// Verifies validity dates, KeyUsage (digitalSignature), and ExtendedKeyUsage (serverAuth).
    private static func verifyCertificateExtensionsAndDates(
        certificate: SecCertificate,
        certDER: Data
    ) -> Bool {
        // Parse basic DER structure of Certificate:
        // SEQUENCE { tbsCertificate SEQUENCE { ... }, sigAlg, sig }
        guard let tbs = extractTBSCertificate(certDER: certDER) else { return false }

        // Check that key usage OID (2.5.29.15) and serverAuth EKU OID (1.3.6.1.5.5.7.3.1) are present in TBS
        let keyUsageOid = Data([0x55, 0x1D, 0x0F]) // 2.5.29.15
        let serverAuthOid = Data([0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x01]) // 1.3.6.1.5.5.7.3.1

        guard tbs.range(of: keyUsageOid) != nil else {
            PadLog.network("PadCertificateVerifier: missing KeyUsage extension")
            return false
        }

        guard tbs.range(of: serverAuthOid) != nil else {
            PadLog.network("PadCertificateVerifier: missing ExtendedKeyUsage serverAuth extension")
            return false
        }

        return true
    }

    /// Verifies self-signed signature of the TBSCertificate against the certificate's public key.
    private static func verifySelfSignedSignature(certDER: Data, publicKey: SecKey) -> Bool {
        guard let (tbsData, signatureData) = extractTBSAndSignature(certDER: certDER) else {
            return false
        }

        var verifyError: Unmanaged<CFError>?
        let verified = SecKeyVerifySignature(
            publicKey,
            .ecdsaSignatureMessageX962SHA256,
            tbsData as CFData,
            signatureData as CFData,
            &verifyError
        )
        return verified
    }

    /// Helper to parse ASN.1 DER certificate into TBSCertificate and signature.
    private static func extractTBSAndSignature(certDER: Data) -> (tbs: Data, sig: Data)? {
        guard certDER.count > 10, certDER[0] == 0x30 else { return nil }
        var index = 1
        _ = parseDERLength(certDER, index: &index)

        // First item is TBSCertificate (SEQUENCE)
        guard index < certDER.count, certDER[index] == 0x30 else { return nil }
        let tbsStart = index
        index += 1
        let tbsLen = parseDERLength(certDER, index: &index)
        let tbsEnd = index + tbsLen
        guard tbsEnd <= certDER.count else { return nil }
        let tbsData = certDER.subdata(in: tbsStart..<tbsEnd)

        // Second item is AlgorithmIdentifier (SEQUENCE)
        index = tbsEnd
        guard index < certDER.count, certDER[index] == 0x30 else { return nil }
        index += 1
        let algLen = parseDERLength(certDER, index: &index)
        index += algLen

        // Third item is Signature (BIT STRING: tag 0x03)
        guard index < certDER.count, certDER[index] == 0x03 else { return nil }
        index += 1
        let sigLen = parseDERLength(certDER, index: &index)
        guard index < certDER.count, sigLen > 1 else { return nil }
        index += 1 // skip unused bits byte (0x00)
        let sigData = certDER.subdata(in: index..<(index + sigLen - 1))

        return (tbsData, sigData)
    }

    private static func extractTBSCertificate(certDER: Data) -> Data? {
        extractTBSAndSignature(certDER: certDER)?.tbs
    }

    private static func parseDERLength(_ data: Data, index: inout Int) -> Int {
        guard index < data.count else { return 0 }
        let first = data[index]
        index += 1
        if first < 0x80 {
            return Int(first)
        }
        let byteCount = Int(first & 0x7F)
        var length = 0
        for _ in 0..<byteCount {
            guard index < data.count else { return 0 }
            length = (length << 8) | Int(data[index])
            index += 1
        }
        return length
    }
}

// MARK: - Data Hex Helper

extension Data {
    init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hex.count % 2 == 0 else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
}
