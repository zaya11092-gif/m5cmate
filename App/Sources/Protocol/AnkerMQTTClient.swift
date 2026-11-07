import Foundation
import CocoaMQTT

enum MQTTState: Equatable {
    case idle
    case connecting
    case connected
    case disconnected(reason: String?)
}

/// Wrapper around CocoaMQTT implementing the AnkerMake MQTT dialect:
/// TLS to the cloud broker, envelope framing (AES + XOR checksum), and the
/// notice / command-reply topics.
final class AnkerMQTTClient: NSObject {

    /// Decoded JSON objects received from the printer (one per `commandType` entry).
    var onJSONObject: (([String: Any]) -> Void)?
    /// Human-readable log lines for the console UI.
    var onLog: ((String) -> Void)?
    var onStateChange: ((MQTTState) -> Void)?

    private var mqtt: CocoaMQTT?
    private var key = Data()
    private var serial = ""
    private var outgoingVersion: UInt8 = 2   // M5C firmware may want 1; configurable
    private let guid = UUID().uuidString.lowercased()

    private(set) var state: MQTTState = .idle {
        didSet { onStateChange?(state) }
    }

    var isConnected: Bool { state == .connected }

    // MARK: - Connection

    func connect(account: AnkerAccount, printer: AnkerPrinter, outgoingVersion: UInt8 = 2) {
        disconnect()
        self.key = Data(hexString: printer.secretKeyHex) ?? Data()
        self.serial = printer.serial
        self.outgoingVersion = outgoingVersion

        guard key.count == 32 else {
            state = .disconnected(reason: "Printer AES key invalid (must be 32 bytes)")
            return
        }

        let client = CocoaMQTT(
            clientID: "m5cmate-" + UUID().uuidString.prefix(8),
            host: account.region.mqttHost,
            port: 8789
        )
        client.username = account.mqttUsername
        client.password = account.mqttPassword
        client.enableSSL = true
        client.allowUntrustCACertificate = true
        client.keepAlive = 60
        client.autoReconnect = true
        client.autoReconnectTimeInterval = 3
        client.maxAutoReconnectTimeInterval = 60

        let delegate = Delegate(owner: self)
        client.delegate = delegate
        self.delegate = delegate   // keep alive alongside the client

        state = .connecting
        log("Connecting to \(account.region.mqttHost):8789 as \(account.mqttUsername) …")
        _ = client.connect(timeout: 15)
        mqtt = client
    }

    func disconnect() {
        mqtt?.disconnect()
        mqtt = nil
        delegate = nil
        if state != .idle { state = .idle }
    }

    // MARK: - Subscriptions / publishing

    private func subscribeAfterConnect() {
        guard let client = mqtt else { return }
        for topic in [
            "/phone/maker/\(serial)/notice",
            "/phone/maker/\(serial)/command/reply",
            "/phone/maker/\(serial)/query/reply",
        ] {
            client.subscribe(topic, qos: .qos0)
            log("Subscribed to \(topic)")
        }
        state = .connected
    }

    /// Publishes an encrypted envelope with a JSON command to the printer's command topic.
    func sendCommand(_ json: [String: Any], label: String) {
        guard let client = mqtt, isConnected else {
            log("✗ Not connected — dropped command: \(label)")
            return
        }
        do {
            let body = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
            let envelope = try MqttEnvelope.pack(json: body, key: key, version: outgoingVersion, guid: guid)
            let message = CocoaMQTTMessage(
                topic: "/device/maker/\(serial)/command",
                payload: [UInt8](envelope),
                qos: .qos1,
                retained: false
            )
            client.publish(message)
            if let pretty = String(data: body, encoding: .utf8) {
                log("→ \(label): \(pretty)")
            }
        } catch {
            log("✗ Failed to pack command \(label): \(error.localizedDescription)")
        }
    }

    // MARK: - High-level commands (verified wire formats)

    /// Run a raw GCode line on the printer — `commandType 1043` (M5C-verified format).
    func sendGCode(_ gcode: String) {
        let line = gcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        sendCommand([
            "commandType": 1043,
            "cmdData": line,
            "cmdLen": line.count,
        ], label: "gcode")
    }

    /// Print control (pause / resume / stop) — `commandType 1008`.
    /// `value` mapping is configurable because it is not fully documented.
    func sendPrintControl(value: Int, userName: String) {
        sendCommand([
            "commandType": 1008,
            "data": [
                "value": value,
                "userName": userName,
            ],
        ], label: "print-control")
    }

    /// Native print-speed command — `commandType 1006` (payload semantics unverified;
    /// the M220 GCode path is the reliable route for feed-rate override).
    func sendPrintSpeed(value: Int) {
        sendCommand([
            "commandType": 1006,
            "value": value,
        ], label: "print-speed")
    }

    /// Status query — `commandType 1027` (0x403 APP_QUERY_STATUS).
    func queryStatus() {
        sendCommand(["commandType": 1027], label: "query-status")
    }

    // MARK: - Receive path

    private func handlePayload(_ payload: [UInt8], topic: String) {
        let raw = Data(payload)
        guard !raw.isEmpty else { return }
        do {
            let envelope = try MqttEnvelope.parse(raw: raw, key: key)
            let obj = try JSONSerialization.jsonObject(with: envelope.data)
            let items: [Any]
            if let list = obj as? [Any] { items = list } else { items = [obj] }
            DispatchQueue.main.async {
                for item in items {
                    if let dict = item as? [String: Any] {
                        self.onJSONObject?(dict)
                    }
                }
                if let text = String(data: envelope.data, encoding: .utf8) {
                    self.log("← [\(topic)] \(text)")
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.log("✗ Failed to decode message on \(topic): \(error.localizedDescription)")
            }
        }
    }

    private func log(_ line: String) {
        DispatchQueue.main.async { self.onLog?(line) }
    }

    private weak var delegate: Delegate?

    /// CocoaMQTT delivers delegate callbacks on its socket queue.
    private final class Delegate: NSObject, CocoaMQTTDelegate {
        weak var owner: AnkerMQTTClient?

        init(owner: AnkerMQTTClient) { self.owner = owner }

        func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
            if ack == .accept {
                owner?.log("✓ Connected to MQTT broker")
                owner?.subscribeAfterConnect()
            } else {
                owner?.state = .disconnected(reason: "Broker refused connection: \(ack)")
                owner?.log("✗ Connection refused: \(ack)")
            }
        }

        func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
            owner?.handlePayload(message.payload, topic: message.topic)
        }

        func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {}

        func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {}

        func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {}

        func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {}

        func mqttDidPing(_ mqtt: CocoaMQTT) {}

        func mqttDidReceivePong(_ mqtt: CocoaMQTT) {}

        func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
            if owner?.state == .connected || owner?.state == .connecting {
                owner?.state = .disconnected(reason: err?.localizedDescription)
                owner?.log("✗ Disconnected: \(err?.localizedDescription ?? "no error")")
            }
        }
    }
}

extension Data {
    /// Hex-string → Data (tolerant of whitespace).
    init?(hexString: String) {
        let chars = hexString.lowercased().filter { $0.isHexDigit }
        guard chars.count % 2 == 0, chars.count >= 2 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(chars.count / 2)
        var index = chars.startIndex
        while index < chars.endIndex {
            let next = chars.index(index, offsetBy: 2)
            guard let byte = UInt8(chars[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
