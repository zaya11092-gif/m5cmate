import Foundation

/// The AnkerMake MQTT envelope ("MA" framing).
///
/// Layout (M5-style, version 2, 64-byte header):
///   'MA' | size u16le | 05 | 01 | 02 | 05 | 'F' | pktType | num u16le | time u32le | guid[37] | pad[11] | AES-data
///
/// M5C firmware (version 1, 24-byte header) drops time/guid and shortens padding:
///   'MA' | size u16le | 05 | 01 | 01 | 05 | 'F' | pktType | num u16le | pad[12] | AES-data
///
/// `size` counts header + ciphertext + 1 (the trailing XOR-checksum byte).
/// The whole message (including the checksum byte) XORs to zero.
struct MqttEnvelope {

    /// Version byte at index 6: 1 = M5C (24-byte header), 2 = M5 (64-byte header).
    static let headerLength: [UInt8: Int] = [1: 24, 2: 64]

    /// Raw MQTT payload data (already decrypted), carrying JSON.
    let data: Data
    /// Version byte observed on the wire.
    let version: UInt8

    static func parse(raw: Data, key: Data) throws -> MqttEnvelope {
        let body = try AnkerCrypto.stripChecksum(raw)
        guard body.count > 8 else { throw AnkerProtocolError.badMagic }
        guard body[0] == 0x4D, body[1] == 0x41 else { throw AnkerProtocolError.badMagic }

        let version = body[6]
        guard let headerLen = headerLength[version] else {
            throw AnkerProtocolError.unsupportedVersion(version)
        }
        guard body.count > headerLen else { throw AnkerProtocolError.badMagic }

        let plaintext = try AnkerCrypto.aesCBCDecrypt(body.subdata(in: headerLen..<body.count), key: key)
        return MqttEnvelope(data: plaintext, version: version)
    }

    static func pack(json: Data, key: Data, version: UInt8, guid: String) throws -> Data {
        guard let headerLen = headerLength[version] else {
            throw AnkerProtocolError.unsupportedVersion(version)
        }
        let ciphertext = try AnkerCrypto.aesCBCEncrypt(json, key: key)

        let size = UInt16(headerLen + ciphertext.count + 1)
        var header = Data()
        header.append(0x4D)                  // 'M'
        header.append(0x41)                  // 'A'
        header.append(UInt8(size & 0xFF))    // size u16le
        header.append(UInt8(size >> 8))
        header.append(0x05)                  // m3
        header.append(0x01)                  // m4
        header.append(version)               // m5: 1 = M5C, 2 = M5
        header.append(0x05)                  // m6
        header.append(0x46)                  // 'F'
        header.append(0xC0)                  // packet type: Single
        header.append(0x00)                  // packet number u16le
        header.append(0x00)
        header.append(0x00)                  // time u32le (ignored)
        header.append(0x00)

        if version == 2 {
            // device_guid as 37-byte zero-padded string
            var guidData = Data(guid.utf8)
            if guidData.count > 37 { guidData = guidData.prefix(37) }
            header.append(guidData)
            header.append(Data(repeating: 0, count: 37 - guidData.count))
            header.append(Data(repeating: 0, count: 11))  // padding
        } else {
            // M5C: 12 bytes of padding, no time/guid
            header.append(Data(repeating: 0, count: 12))
        }

        precondition(header.count == headerLen, "header length mismatch: \(header.count) != \(headerLen)")
        return AnkerCrypto.appendChecksum(header + ciphertext)
    }
}
