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

    static let keyTag = "id.evonex.evopad.server-identity.key.v2"
    static let certLabel = "EvoPad Server Certificate v2"
    static let identityLabel = "EvoPad Server Identity v2"

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

        PadLog.network("PadServerIdentity: identity genuinely absent, generating new P-256 self-signed identity v2")
        return try generateAndPersist()
    }

    /// Queries macOS Keychain for existing SecIdentity matching the versioned label.
    private static func loadExistingIdentity() throws -> PadServerIdentity? {
        let certQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var certItems: CFTypeRef?
        let certStatus = SecItemCopyMatching(certQuery as CFDictionary, &certItems)

        guard certStatus == errSecSuccess, let certList = certItems as? [SecCertificate] else {
            PadLog.network("PadServerIdentity: no certificates found in Keychain")
            return nil
        }

        for certificate in certList {
            let summary = SecCertificateCopySubjectSummary(certificate) as String? ?? ""
            guard summary.starts(with: "EvoPad v2") else { continue }

            guard let publicKey = SecCertificateCopyKey(certificate),
                  let attrs = SecKeyCopyAttributes(publicKey) as? [String: Any],
                  let keySize = attrs[kSecAttrKeySizeInBits as String] as? Int,
                  keySize == 256 else {
                continue
            }

            var identityRef: SecIdentity?
            let identityStatus = SecIdentityCreateWithCertificate(nil, certificate, &identityRef)
            guard identityStatus == errSecSuccess, let identity = identityRef else {
                continue
            }

            var keyRef: SecKey?
            guard SecIdentityCopyPrivateKey(identity, &keyRef) == errSecSuccess, let privateKey = keyRef else {
                continue
            }

            // Verify certificate and private key match by signing and verifying a test nonce
            guard (try? verifyKeyMatchesCertificate(privateKey: privateKey, certificate: certificate)) == true else {
                continue
            }

            let certDER = SecCertificateCopyData(certificate) as Data
            let fingerprint = SHA256.hash(data: certDER).map { String(format: "%02x", $0) }.joined()

            return PadServerIdentity(
                secIdentity: identity,
                certificate: certificate,
                privateKey: privateKey,
                certificateDER: certDER,
                fingerprintHex: fingerprint
            )
        }

        PadLog.network("PadServerIdentity: no matching EvoPad v2 certificate found")
        return nil
    }

    // MARK: - Internal ECDSA Signing & Verification Helpers

    /// Creates an ECDSA signature over data, checking supported algorithms in priority order:
    /// 1. .ecdsaSignatureDigestX962SHA256 (pre-computed 32-byte SHA-256 digest)
    /// 2. .ecdsaSignatureDigestX962 (pre-computed 32-byte SHA-256 digest)
    /// 3. .ecdsaSignatureMessageX962SHA256 (original message, hashed internally)
    static func createECDSASignature(privateKey: SecKey, data: Data) throws -> (signature: Data, algorithm: SecKeyAlgorithm) {
        let digest = Data(SHA256.hash(data: data))

        if let attrs = SecKeyCopyAttributes(privateKey) as? [String: Any] {
            print("DEBUG [createECDSASignature] PrivateKey attributes: \(attrs)")
        }

        let candidateAlgorithms: [(SecKeyAlgorithm, Data, String)] = [
            (.ecdsaSignatureDigestX962SHA256, digest, "ecdsaSignatureDigestX962SHA256"),
            (.ecdsaSignatureDigestX962, digest, "ecdsaSignatureDigestX962"),
            (.ecdsaSignatureMessageX962SHA256, data, "ecdsaSignatureMessageX962SHA256")
        ]

        var lastError: Error?
        for (algorithm, payload, name) in candidateAlgorithms {
            let isSupported = SecKeyIsAlgorithmSupported(privateKey, .sign, algorithm)
            print("DEBUG [createECDSASignature] SecKeyIsAlgorithmSupported(\(name)): \(isSupported)")

            var signError: Unmanaged<CFError>?
            if let signature = SecKeyCreateSignature(
                privateKey,
                algorithm,
                payload as CFData,
                &signError
            ) as Data? {
                print("DEBUG [createECDSASignature] SecKeyCreateSignature SUCCESS with \(name)!")
                return (signature, algorithm)
            } else if let err = signError?.takeRetainedValue() {
                print("DEBUG [createECDSASignature] SecKeyCreateSignature FAILED with \(name): \(err)")
                lastError = err as Error
            }
        }

        let failureError = lastError ?? NSError(domain: "id.evonex.evopad.security", code: -10, userInfo: [
            NSLocalizedDescriptionKey: "No supported ECDSA signing algorithm found for private key"
        ])
        PadLog.network("PadServerIdentity: all ECDSA signing candidates failed: \(failureError)")
        throw failureError
    }

    /// Verifies an ECDSA signature over data using public key, trying preferred algorithm first then falling back.
    static func verifyECDSASignature(publicKey: SecKey, data: Data, signature: Data, preferredAlgorithm: SecKeyAlgorithm? = nil) -> Bool {
        let digest = Data(SHA256.hash(data: data))

        var candidateAlgorithms: [(SecKeyAlgorithm, Data, String)] = []
        if let preferred = preferredAlgorithm {
            let payload = (preferred == .ecdsaSignatureMessageX962SHA256) ? data : digest
            let name = (preferred == .ecdsaSignatureMessageX962SHA256) ? "preferred:ecdsaSignatureMessageX962SHA256" : "preferred:digest"
            candidateAlgorithms.append((preferred, payload, name))
        }

        candidateAlgorithms.append((.ecdsaSignatureDigestX962SHA256, digest, "ecdsaSignatureDigestX962SHA256"))
        candidateAlgorithms.append((.ecdsaSignatureDigestX962, digest, "ecdsaSignatureDigestX962"))
        candidateAlgorithms.append((.ecdsaSignatureMessageX962SHA256, data, "ecdsaSignatureMessageX962SHA256"))

        for (algorithm, payload, name) in candidateAlgorithms {
            if SecKeyIsAlgorithmSupported(publicKey, .verify, algorithm) {
                var verifyError: Unmanaged<CFError>?
                let valid = SecKeyVerifySignature(
                    publicKey,
                    algorithm,
                    payload as CFData,
                    signature as CFData,
                    &verifyError
                )
                if valid {
                    PadLog.network("PadServerIdentity: signature verified successfully using algorithm \(name)")
                    return true
                } else if let err = verifyError?.takeRetainedValue() {
                    PadLog.network("PadServerIdentity: SecKeyVerifySignature with \(name) failed: \(err)")
                }
            } else {
                PadLog.network("PadServerIdentity: algorithm \(name) not supported for verification by public key")
            }
        }

        PadLog.network("PadServerIdentity: signature verification failed across all candidate algorithms")
        return false
    }

    /// Verifies that private key and certificate public key form a valid matching pair.
    static func verifyKeyMatchesCertificate(privateKey: SecKey, certificate: SecCertificate) throws -> Bool {
        guard let publicKey = SecCertificateCopyKey(certificate) else {
            PadLog.network("PadServerIdentity: failed to extract public key from certificate")
            return false
        }

        let testPayload = "EvoPad-Identity-Verification-\(UUID().uuidString)".data(using: .utf8)!
        let (signature, algorithm) = try createECDSASignature(privateKey: privateKey, data: testPayload)
        let verified = verifyECDSASignature(
            publicKey: publicKey,
            data: testPayload,
            signature: signature,
            preferredAlgorithm: algorithm
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
                kSecAttrLabel as String: identityLabel,
                kSecAttrCanSign as String: true
            ]
        ]

        var genError: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(keyAttributes as CFDictionary, &genError) else {
            if let err = genError?.takeRetainedValue() {
                throw err as Error
            }
            throw NSError(domain: "id.evonex.evopad.security", code: -4, userInfo: [
                NSLocalizedDescriptionKey: "SecKeyCreateRandomKey failed to create private key"
            ])
        }

        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &genError) as Data? else {
            if let err = genError?.takeRetainedValue() {
                throw err as Error
            }
            throw NSError(domain: "id.evonex.evopad.security", code: -5, userInfo: [
                NSLocalizedDescriptionKey: "SecKeyCopyExternalRepresentation failed to extract public key"
            ])
        }

        // 2. Generate self-signed X.509 v3 DER certificate
        let deviceName = Host.current().localizedName ?? "Mac"
        let commonName = "EvoPad v2 (\(deviceName))"
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
        print("DEBUG [generateAndPersist] SecItemAdd cert addStatus: \(addStatus)")
        guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus), userInfo: [
                NSLocalizedDescriptionKey: "Failed to persist certificate to Keychain: \(addStatus)"
            ])
        }

        // 4. Form and verify the newly formed SecIdentity
        var identityRef: SecIdentity?
        let identityStatus = SecIdentityCreateWithCertificate(nil, certificate, &identityRef)
        guard identityStatus == errSecSuccess, let secIdentity = identityRef else {
            throw NSError(domain: "id.evonex.evopad.security", code: -7, userInfo: [
                NSLocalizedDescriptionKey: "SecIdentityCreateWithCertificate failed with status \(identityStatus)"
            ])
        }

        guard try verifyKeyMatchesCertificate(privateKey: privateKey, certificate: certificate) else {
            throw NSError(domain: "id.evonex.evopad.security", code: -8, userInfo: [
                NSLocalizedDescriptionKey: "SecIdentity certificate and private key mismatch after generation"
            ])
        }

        let fingerprint = SHA256.hash(data: certDER).map { String(format: "%02x", $0) }.joined()

        return PadServerIdentity(
            secIdentity: secIdentity,
            certificate: certificate,
            privateKey: privateKey,
            certificateDER: certDER,
            fingerprintHex: fingerprint
        )
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
        let (signatureData, _) = try PadServerIdentity.createECDSASignature(
            privateKey: privateKey,
            data: tbsCertificate
        )

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
