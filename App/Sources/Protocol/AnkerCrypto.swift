import Foundation
import CommonCrypto
import CryptoKit

/// Crypto primitives used by the AnkerMake MQTT protocol.
///
/// - MQTT payloads: AES-256-CBC (PKCS7) with a fixed IV and a per-printer 32-byte key.
/// - Trailing 1-byte XOR checksum over the whole message (checksum byte included → XOR of all bytes == 0).
/// - Login: ECDH-P256 against Anker's static public key; shared secret X coordinate is the AES key.
enum AnkerCrypto {

    static let mqttIV = Data("3DPrintAnkerMake".utf8)

    // MARK: - XOR checksum

    static func xorChecksum(_ data: Data) -> UInt8 {
        data.reduce(UInt8(0)) { $0 ^ $1 }
    }

    /// Validates the trailing XOR-checksum byte and returns the payload without it.
    static func stripChecksum(_ payload: Data) throws -> Data {
        guard let last = payload.last else { throw AnkerProtocolError.emptyMessage }
        if xorChecksum(payload) != 0 {
            throw AnkerProtocolError.checksumMismatch
        }
        return payload.dropLast()
    }

    /// Appends the XOR-checksum byte to a message.
    static func appendChecksum(_ data: Data) -> Data {
        data + Data([xorChecksum(data)])
    }

    // MARK: - AES-256-CBC

    static func aesCBCEncrypt(_ input: Data, key: Data) throws -> Data {
        try aesCBC(input: input, key: key, encrypt: true)
    }

    static func aesCBCDecrypt(_ input: Data, key: Data) throws -> Data {
        try aesCBC(input: input, key: key, encrypt: false)
    }

    private static func aesCBC(input: Data, key: Data, encrypt: Bool) throws -> Data {
        guard key.count == kCCKeySizeAES256 else { throw AnkerProtocolError.invalidKeyLength(key.count) }
        guard input.count % kCCBlockSizeAES128 == 0, !input.isEmpty else {
            throw AnkerProtocolError.invalidCiphertextLength(input.count)
        }

        var output = Data(count: input.count + kCCBlockSizeAES128)
        var moved = 0

        let status = output.withUnsafeMutableBytes { outPtr -> CCCryptorStatus in
            input.withUnsafeBytes { inPtr -> CCCryptorStatus in
                key.withUnsafeBytes { keyPtr -> CCCryptorStatus in
                    mqttIV.withUnsafeBytes { ivPtr -> CCCryptorStatus in
                        CCCrypt(
                            encrypt ? CCOperation(kCCEncrypt) : CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress, key.count,
                            ivPtr.baseAddress,
                            inPtr.baseAddress, input.count,
                            outPtr.baseAddress, outPtr.count,
                            &moved
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else { throw AnkerCryptoError.ccCrypt(status) }
        output.removeSubrange(moved..<output.count)
        return output
    }

    // MARK: - ECDH login (v2/passport)

    /// Anker's static ECDH partner public key (secp256r1 / P-256).
    static let ankerPublicKeyX: [UInt8] = [
        0xC5, 0xC0, 0x0C, 0x4F, 0x8D, 0x11, 0x97, 0xCC, 0x7C, 0x31, 0x67, 0xC5, 0x2B, 0xF7, 0xAC, 0xB0,
        0x54, 0xD7, 0x22, 0xF0, 0xEF, 0x08, 0xDC, 0xD7, 0xE0, 0x88, 0x32, 0x36, 0xE0, 0xD7, 0x2A, 0x38,
    ]
    static let ankerPublicKeyY: [UInt8] = [
        0x68, 0xD9, 0x75, 0x0C, 0xB4, 0x7F, 0xA4, 0x61, 0x92, 0x48, 0xF3, 0xD8, 0x3F, 0x0F, 0x66, 0x26,
        0x71, 0xDA, 0xDC, 0x6E, 0x2D, 0x31, 0xC2, 0xF4, 0x1D, 0xB0, 0x16, 0x16, 0x51, 0xC7, 0xC0, 0x76,
    ]

    /// Performs the ECDH exchange and returns `(publicKeyHex, encryptedPasswordBase64)`.
    static func encryptLoginPassword(_ password: String) throws -> (publicKeyHex: String, encrypted: String) {
        var x963 = Data([0x04])
        x963.append(contentsOf: ankerPublicKeyX)
        x963.append(contentsOf: ankerPublicKeyY)
        let partner = try P256.KeyAgreement.PublicKey(x963Representation: x963)

        let ephemeral = P256.KeyAgreement.PrivateKey()
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: partner)
        let key = shared.withUnsafeBytes { Data($0) }   // 32-byte X coordinate
        guard key.count == 32 else { throw AnkerProtocolError.badSharedSecret }

        let iv = key.prefix(16)
        var sealed = Data()
        var ivData = Data(iv)

        let status = key.withUnsafeBytes { keyPtr -> CCCryptorStatus in
            ivData.withUnsafeMutableBytes { ivPtr -> CCCryptorStatus in
                Data(password.utf8).withUnsafeBytes { inPtr -> CCCryptorStatus in
                    var moved = 0
                    var out = Data(count: 64)
                    let st = out.withUnsafeMutableBytes { outPtr -> CCCryptorStatus in
                        CCCrypt(
                            CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress, key.count,
                            ivPtr.baseAddress,
                            inPtr.baseAddress, password.utf8.count,
                            outPtr.baseAddress, outPtr.count,
                            &moved
                        )
                    }
                    if st == kCCSuccess { out.removeSubrange(moved..<out.count); sealed = out }
                    return st
                }
            }
        }
        guard status == kCCSuccess else { throw AnkerCryptoError.ccCrypt(status) }

        let pubHex = ephemeral.publicKey.x963Representation.map { String(format: "%02x", $0) }.joined()
        return (pubHex, sealed.base64EncodedString())
    }
}

enum AnkerCryptoError: Error {
    case ccCrypt(CCCryptorStatus)
}

enum AnkerProtocolError: Error, LocalizedError {
    case emptyMessage
    case checksumMismatch
    case badMagic
    case unsupportedVersion(UInt8)
    case invalidKeyLength(Int)
    case invalidCiphertextLength(Int)
    case badSharedSecret
    case notJSON

    var errorDescription: String? {
        switch self {
        case .emptyMessage: return "Empty MQTT message"
        case .checksumMismatch: return "MQTT message XOR-checksum mismatch"
        case .badMagic: return "Bad MQTT message magic (expected 'MA')"
        case .unsupportedVersion(let v): return "Unsupported MQTT message format version \(v)"
        case .invalidKeyLength(let n): return "AES key must be 32 bytes, got \(n)"
        case .invalidCiphertextLength(let n): return "Ciphertext length \(n) is not a multiple of 16"
        case .badSharedSecret: return "ECDH shared secret has unexpected length"
        case .notJSON: return "Payload is not valid JSON"
        }
    }
}
