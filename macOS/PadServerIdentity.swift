import Foundation
import Security
import CryptoKit

/// Represents the persistent X.509 P-256 server identity stored in macOS Keychain.
final class PadServerIdentity {
    let secIdentity: SecIdentity
    let certificate: SecCertificate
    let privateKey: SecKey
    let certificateDER: Data
    let fingerprintHex: String

    static let keyTag = "id.evonex.evopad.server-identity.key.v1"
    static let certLabel = "EvoPad Server Certificate v1"
    static let identityLabel = "EvoPad Server Identity v1"

    init(
        secIdentity: SecIdentity,
        certificate: SecCertificate,
        privateKey: SecKey,
        certificateDER: Data,
        fingerprintHex: String
    ) {
        self.secIdentity = secIdentity
        self.certificate = certificate
        self.privateKey = privateKey
        self.certificateDER = certificateDER
        self.fingerprintHex = fingerprintHex
    }

    /// Loads the existing identity from Keychain, or generates a new one ONLY if genuinely absent.
    /// Fails closed on any Keychain error (does not silently rotate).
    static func loadOrCreate() throws -> PadServerIdentity {
        do {
            if let existing = try loadExistingIdentity() {
                return existing
            }
        } catch {
            // Fail closed: do not silently generate or rotate if Keychain is locked or error occurred
            PadLog.network("PadServerIdentity: failed loading identity from Keychain: \(error)")
            throw error
        }

        PadLog.network("PadServerIdentity: identity genuinely absent, generating new P-256 self-signed identity")
        return try generateAndPersist()
    }

    /// Queries macOS Keychain for existing SecIdentity matching the versioned label.
    private static func loadExistingIdentity() throws -> PadServerIdentity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrLabel as String: identityLabel
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess, let item else {
            let error = NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "SecItemCopyMatching failed with OSStatus \(status)"
            ])
            throw error
        }

        let secIdentity = item as! SecIdentity

        var certRef: SecCertificate?
        guard SecIdentityCopyCertificate(secIdentity, &certRef) == errSecSuccess, let certificate = certRef else {
            throw NSError(domain: "id.evonex.evopad.security", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to copy certificate from SecIdentity"
            ])
        }

        var keyRef: SecKey?
        guard SecIdentityCopyPrivateKey(secIdentity, &keyRef) == errSecSuccess, let privateKey = keyRef else {
            throw NSError(domain: "id.evonex.evopad.security", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "Failed to copy private key from SecIdentity"
            ])
        }

        // Verify certificate and private key match by signing and verifying a test nonce
        guard try verifyKeyMatchesCertificate(privateKey: privateKey, certificate: certificate) else {
            throw NSError(domain: "id.evonex.evopad.security", code: -3, userInfo: [
                NSLocalizedDescriptionKey: "SecIdentity certificate and private key mismatch"
            ])
        }

        let certDER = SecCertificateCopyData(certificate) as Data
        let fingerprint = SHA256.hash(data: certDER).map { String(format: "%02x", $0) }.joined()

        return PadServerIdentity(
            secIdentity: secIdentity,
            certificate: certificate,
            privateKey: privateKey,
            certificateDER: certDER,
            fingerprintHex: fingerprint
        )
    }

    /// Verifies that private key and certificate public key form a valid matching pair.
    static func verifyKeyMatchesCertificate(privateKey: SecKey, certificate: SecCertificate) throws -> Bool {
        guard let publicKey = SecCertificateCopyKey(certificate) else { return false }

        let testPayload = "EvoPad-Identity-Verification-\(UUID().uuidString)".data(using: .utf8)!
        var signError: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureMessageX962SHA256,
            testPayload as CFData,
            &signError
        ) as Data? else {
            if let err = signError?.takeRetainedValue() {
                throw err as Error
            }
            return false
        }

        var verifyError: Unmanaged<CFError>?
        let verified = SecKeyVerifySignature(
            publicKey,
            .ecdsaSignatureMessageX962SHA256,
            testPayload as CFData,
            signature as CFData,
            &verifyError
        )
        return verified
    }

    /// Generates a new P-256 key pair, builds a self-signed X.509 v3 certificate, and persists both in Keychain.
    private static func generateAndPersist() throws -> PadServerIdentity {
        // 1. Generate P-256 Key Pair
        let keyAttributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!,
                kSecAttrLabel as String: identityLabel
            ]
        ]

        var genError: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(keyAttributes as CFDictionary, &genError) else {
            let err = genError?.takeRetainedValue() ?? NSError(domain: "id.evonex.evopad.security", code: -4, userInfo: nil)
            throw err
        }

        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &genError) as Data? else {
            let err = genError?.takeRetainedValue() ?? NSError(domain: "id.evonex.evopad.security", code: -5, userInfo: nil)
            throw err
        }

        // 2. Generate self-signed X.509 v3 DER certificate
        let deviceName = Host.current().localizedName ?? "Mac"
        let commonName = "EvoPad (\(deviceName))"
        let certDER = try ASN1X509Generator.generateSelfSignedCertificate(
            commonName: commonName,
            publicKeyData: publicKeyData,
            privateKey: privateKey
        )

        guard let certificate = SecCertificateCreateWithData(nil, certDER as CFData) else {
            throw NSError(domain: "id.evonex.evopad.security", code: -6, userInfo: [
                NSLocalizedDescriptionKey: "Failed to create SecCertificate from generated DER"
            ])
        }

        // 3. Persist Certificate to Keychain with matching label
        let certAddQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecAttrLabel as String: identityLabel
        ]
        let addStatus = SecItemAdd(certAddQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus), userInfo: [
                NSLocalizedDescriptionKey: "Failed to persist certificate to Keychain: \(addStatus)"
            ])
        }

        // 4. Retrieve and verify the newly formed SecIdentity
        guard let identity = try loadExistingIdentity() else {
            throw NSError(domain: "id.evonex.evopad.security", code: -7, userInfo: [
                NSLocalizedDescriptionKey: "SecIdentity could not be retrieved from Keychain after persistence"
            ])
        }

        return identity
    }
}

// MARK: - Standalone X.509 v3 DER Generator (P-256 ECDSA, digitalSignature, serverAuth)

enum ASN1X509Generator {
    static func generateSelfSignedCertificate(
        commonName: String,
        publicKeyData: Data,
        privateKey: SecKey
    ) throws -> Data {
        // Serial Number: 16-byte random positive integer
        var serialBytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, serialBytes.count, &serialBytes)
        serialBytes[0] &= 0x7F // Ensure positive sign bit in two's complement
        let serial = derInteger(Data(serialBytes))

        // Version 3: [0] EXPLICIT INTEGER 2
        let version = derContextExplicit(0, derInteger(Data([0x02])))

        // Signature Algorithm Identifier: 1.2.840.10045.4.3.2 (ecdsaWithSHA256)
        let sigAlgOid = derOID([1, 2, 840, 10045, 4, 3, 2])
        let sigAlg = derSequence(sigAlgOid)

        // Issuer / Subject Name: CN = commonName
        let cnOid = derOID([2, 5, 4, 3])
        let cnVal = derUTF8String(commonName)
        let rdnSeq = derSequence(cnOid + cnVal)
        let rdnSet = derSet(rdnSeq)
        let name = derSequence(rdnSet)

        // Validity: notBefore (now - 1 hour), notAfter (now + 5 years)
        let now = Date()
        let notBeforeDate = now.addingTimeInterval(-3600)
        let notAfterDate = now.addingTimeInterval(5 * 365 * 24 * 3600)
        let validity = derSequence(derUTCTime(notBeforeDate) + derUTCTime(notAfterDate))

        // SubjectPublicKeyInfo (P-256 EC Public Key)
        let ecPublicOid = derOID([1, 2, 840, 10045, 2, 1])
        let prime256Oid = derOID([1, 2, 840, 10045, 3, 1, 7])
        let ecParams = derSequence(ecPublicOid + prime256Oid)
        let spkiBitString = derBitString(publicKeyData)
        let spki = derSequence(ecParams + spkiBitString)

        // Extensions [3] EXPLICIT:
        // 1. Key Usage (2.5.29.15, critical=true): digitalSignature (0x80)
        let kuOid = derOID([2, 5, 29, 15])
        let kuCritical = derBoolean(true)
        let kuBits = derBitString(Data([0x80]), unusedBits: 7)
        let kuOctet = derOctetString(kuBits)
        let kuExt = derSequence(kuOid + kuCritical + kuOctet)

        // 2. Extended Key Usage (2.5.29.37): serverAuth (1.3.6.1.5.5.7.3.1)
        let ekuOid = derOID([2, 5, 29, 37])
        let serverAuthOid = derOID([1, 3, 6, 1, 5, 5, 7, 3, 1])
        let ekuSeq = derSequence(serverAuthOid)
        let ekuOctet = derOctetString(ekuSeq)
        let ekuExt = derSequence(ekuOid + ekuOctet)

        // 3. Basic Constraints (2.5.29.19, critical=true): CA = false
        let bcOid = derOID([2, 5, 29, 19])
        let bcCritical = derBoolean(true)
        let bcSeq = derSequence(Data())
        let bcOctet = derOctetString(bcSeq)
        let bcExt = derSequence(bcOid + bcCritical + bcOctet)

        let extensions = derContextExplicit(3, derSequence(kuExt + ekuExt + bcExt))

        // TBSCertificate SEQUENCE
        let tbsCertificate = derSequence(
            version +
            serial +
            sigAlg +
            name +       // issuer
            validity +
            name +       // subject
            spki +
            extensions
        )

        // Sign TBSCertificate with P-256 private key
        var signError: Unmanaged<CFError>?
        guard let signatureData = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureMessageX962SHA256,
            tbsCertificate as CFData,
            &signError
        ) as Data? else {
            let err = signError?.takeRetainedValue() ?? NSError(domain: "id.evonex.evopad.security", code: -10, userInfo: nil)
            throw err
        }

        let signatureBitString = derBitString(signatureData, unusedBits: 0)

        // Final X.509 Certificate
        return derSequence(tbsCertificate + sigAlg + signatureBitString)
    }

    // MARK: - DER Primitives

    private static func derLength(_ length: Int) -> Data {
        if length < 128 {
            return Data([UInt8(length)])
        }
        var temp = length
        var bytes = [UInt8]()
        while temp > 0 {
            bytes.insert(UInt8(temp & 0xFF), at: 0)
            temp >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }

    static func derTL(_ tag: UInt8, _ content: Data) -> Data {
        var result = Data([tag])
        result.append(derLength(content.count))
        result.append(content)
        return result
    }

    static func derSequence(_ content: Data) -> Data {
        derTL(0x30, content)
    }

    static func derSet(_ content: Data) -> Data {
        derTL(0x31, content)
    }

    static func derInteger(_ content: Data) -> Data {
        if let first = content.first, first >= 0x80 {
            return derTL(0x02, Data([0x00]) + content)
        }
        return derTL(0x02, content)
    }

    static func derBitString(_ content: Data, unusedBits: UInt8 = 0) -> Data {
        derTL(0x03, Data([unusedBits]) + content)
    }

    static func derOctetString(_ content: Data) -> Data {
        derTL(0x04, content)
    }

    static func derBoolean(_ value: Bool) -> Data {
        derTL(0x01, Data([value ? 0xFF : 0x00]))
    }

    static func derUTF8String(_ string: String) -> Data {
        derTL(0x0C, string.data(using: .utf8) ?? Data())
    }

    static func derUTCTime(_ date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let dateString = formatter.string(from: date)
        return derTL(0x17, dateString.data(using: .ascii) ?? Data())
    }

    static func derContextExplicit(_ tag: UInt8, _ content: Data) -> Data {
        derTL(0xA0 | tag, content)
    }

    static func derOID(_ components: [UInt]) -> Data {
        guard components.count >= 2 else { return Data() }
        var result = Data()
        result.append(UInt8(components[0] * 40 + components[1]))

        for component in components.dropFirst(2) {
            var val = component
            var bytes = [UInt8]()
            bytes.append(UInt8(val & 0x7F))
            val >>= 7
            while val > 0 {
                bytes.insert(UInt8((val & 0x7F) | 0x80), at: 0)
                val >>= 7
            }
            result.append(contentsOf: bytes)
        }
        return derTL(0x06, result)
    }
}
