import Foundation

/// Machine state as reported by the printer.
enum PrinterState: String {
    case idle
    case preparing
    case printing
    case paused
    case finished
    case stopped
    case error
    case unknown

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .preparing: return "Preparing"
        case .printing: return "Printing"
        case .paused: return "Paused"
        case .finished: return "Finished"
        case .stopped: return "Stopped"
        case .error: return "Error"
        case .unknown: return "Unknown"
        }
    }
}

/// Aggregated printer status, merged from the individual MQTT status messages
/// (`commandType` 1000–1055). Field names vary between firmware versions, so
/// parsing is deliberately tolerant (mirrors the community tooling).
struct PrinterStatus: Equatable {
    var state: PrinterState = .unknown
    var rawState: String = ""
    var progressPercent: Double?
    var remainingSeconds: Int?
    var fileName: String = ""
    var nozzleTemp: Double?
    var nozzleTarget: Double?
    var bedTemp: Double?
    var bedTarget: Double?
    var layer: Int?
    var totalLayers: Int?
    var reportedSpeed: Int?
    var lastUpdate: Date = Date()

    init() {}

    init(state: PrinterState, progressPercent: Double?, remainingSeconds: Int?) {
        self.state = state
        self.progressPercent = progressPercent
        self.remainingSeconds = remainingSeconds
    }

    /// True while the printer is actively producing something.
    var isActive: Bool {
        state == .printing || state == .preparing || state == .paused
    }
}

/// Parses one decrypted JSON object from the printer's notice stream.
enum StatusParser {

    /// commandType values from the protocol spec (mqtt.stf).
    enum CommandType {
        static let eventNotify = 1000      // 0x3e8
        static let printSchedule = 1001    // 0x3e9
        static let nozzleTemp = 1003       // 0x3eb
        static let hotbedTemp = 1004       // 0x3ec
        static let printSpeed = 1006       // 0x3ee
        static let printControl = 1008     // 0x3f0
        static let modelLayer = 1052       // 0x41c
        static let printMaxSpeed = 1055    // 0x41f
    }

    /// Applies a status dict to the given status, returning the mutated copy.
    static func apply(_ dict: [String: Any], to status: inout PrinterStatus) {
        guard let type = dict["commandType"] as? Int else { return }

        switch type {
        case CommandType.printSchedule:
            applySchedule(dict, to: &status)
        case CommandType.nozzleTemp:
            status.nozzleTemp = temp(dict, currentKey: "currentTemp")
            status.nozzleTarget = temp(dict, currentKey: "targetTemp")
        case CommandType.hotbedTemp:
            status.bedTemp = temp(dict, currentKey: "currentTemp")
            status.bedTarget = temp(dict, currentKey: "targetTemp")
        case CommandType.printSpeed:
            status.reportedSpeed = int(dict, keys: ["value", "speed"])
        case CommandType.modelLayer:
            if let l = int(dict, keys: ["currentLayer", "layer", "value"]) { status.layer = l }
            if let t = int(dict, keys: ["totalLayer", "total"]) { status.totalLayers = t }
        case CommandType.eventNotify:
            applyEvent(dict, to: &status)
        default:
            break
        }
        status.lastUpdate = Date()
    }

    private static func applySchedule(_ dict: [String: Any], to status: inout PrinterStatus) {
        if let p = double(dict, keys: ["progress"]) {
            // Firmware has been seen reporting 0–100 and 0–10000; normalize.
            var pct = p
            if pct > 100 { pct /= 100 }
            status.progressPercent = max(0, min(100, pct))
        }
        if let r = int(dict, keys: ["remaining", "remain", "remainTime", "remaining_time", "leftTime"]) {
            status.remainingSeconds = r
        }
        if let name = dict["filename"] as? String ?? dict["file_name"] as? String {
            status.fileName = name
        }
        if let raw = string(dict, keys: ["status", "state", "printStatus"]) {
            status.rawState = raw
            status.state = mapState(raw)
        }
    }

    private static func applyEvent(_ dict: [String: Any], to status: inout PrinterStatus) {
        let subType = dict["subType"] as? Int ?? -1
        let value = dict["value"] as? Int ?? -1

        // Filament runout: subType 2, value 6 (per community tooling).
        if subType == 2, value == 6 {
            status.state = .paused
            status.rawState = "filament_runout"
        }
    }

    private static func mapState(_ raw: String) -> PrinterState {
        let s = raw.lowercased()
        if s.contains("print") && s.contains("ing") { return .printing }
        if s.contains("pause") { return .paused }
        if s.contains("finish") || s.contains("complete") || s.contains("success") { return .finished }
        if s.contains("stop") || s.contains("cancel") { return .stopped }
        if s.contains("error") || s.contains("fail") { return .error }
        if s.contains("prepare") || s.contains("heat") || s.contains("level") { return .preparing }
        if s.contains("idle") { return .idle }
        return .unknown
    }

    // MARK: - Key-tolerant accessors

    private static func temp(_ dict: [String: Any], currentKey: String) -> Double? {
        guard let raw = double(dict, keys: [currentKey, "value"]) else { return nil }
        // Temps arrive in 1/100 °C units (e.g. 2400 → 24.0 °C).
        return raw > 500 ? raw / 100 : raw
    }

    private static func int(_ dict: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let v = dict[key] as? Int { return v }
            if let v = dict[key] as? Double { return Int(v) }
            if let v = dict[key] as? String, let v = Int(v) { return v }
        }
        return nil
    }

    private static func double(_ dict: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let v = dict[key] as? Double { return v }
            if let v = dict[key] as? Int { return Double(v) }
            if let v = dict[key] as? String, let v = Double(v) { return v }
        }
        return nil
    }

    private static func string(_ dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let v = dict[key] as? String { return v }
        }
        return nil
    }
}
