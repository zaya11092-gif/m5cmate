import Foundation
import Combine

/// Persisted app configuration (UserDefaults-backed).
final class AppSettings: ObservableObject {

    /// Shared instance — used by both the UI layer and PrintMonitor so that
    /// edits from Settings take effect immediately in the monitor.
    static let shared = AppSettings()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        region = AnkerRegion(rawValue: defaults.string(forKey: "region") ?? "us") ?? .us
        email = defaults.string(forKey: "email") ?? ""
        authToken = defaults.string(forKey: "authToken") ?? ""
        userID = defaults.string(forKey: "userID") ?? ""
        printerSerial = defaults.string(forKey: "printerSerial") ?? ""
        printerName = defaults.string(forKey: "printerName") ?? ""
        printerModel = defaults.string(forKey: "printerModel") ?? ""
        secretKeyHex = defaults.string(forKey: "secretKeyHex") ?? ""
        autoLiveActivity = defaults.object(forKey: "autoLiveActivity") as? Bool ?? true
        notifyStarted = defaults.object(forKey: "notifyStarted") as? Bool ?? true
        notifyFinished = defaults.object(forKey: "notifyFinished") as? Bool ?? true
        notifyPaused = defaults.object(forKey: "notifyPaused") as? Bool ?? true
        notifyError = defaults.object(forKey: "notifyError") as? Bool ?? true
        outgoingVersion = UInt8(defaults.object(forKey: "outgoingVersion") as? Int ?? 2)
        pauseValue = defaults.object(forKey: "pauseValue") as? Int ?? 0
        resumeValue = defaults.object(forKey: "resumeValue") as? Int ?? 1
        stopValue = defaults.object(forKey: "stopValue") as? Int ?? 2
        speedUseNativeCommand = defaults.object(forKey: "speedUseNativeCommand") as? Bool ?? false
    }

    // MARK: - Account / printer

    @Published var region: AnkerRegion { didSet { defaults.set(region.rawValue, forKey: "region") } }
    @Published var email: String { didSet { defaults.set(email, forKey: "email") } }
    @Published var authToken: String { didSet { defaults.set(authToken, forKey: "authToken") } }
    @Published var userID: String { didSet { defaults.set(userID, forKey: "userID") } }
    @Published var printerSerial: String { didSet { defaults.set(printerSerial, forKey: "printerSerial") } }
    @Published var printerName: String { didSet { defaults.set(printerName, forKey: "printerName") } }
    @Published var printerModel: String { didSet { defaults.set(printerModel, forKey: "printerModel") } }
    @Published var secretKeyHex: String { didSet { defaults.set(secretKeyHex, forKey: "secretKeyHex") } }

    // MARK: - Behaviour

    @Published var autoLiveActivity: Bool { didSet { defaults.set(autoLiveActivity, forKey: "autoLiveActivity") } }
    @Published var notifyStarted: Bool { didSet { defaults.set(notifyStarted, forKey: "notifyStarted") } }
    @Published var notifyFinished: Bool { didSet { defaults.set(notifyFinished, forKey: "notifyFinished") } }
    @Published var notifyPaused: Bool { didSet { defaults.set(notifyPaused, forKey: "notifyPaused") } }
    @Published var notifyError: Bool { didSet { defaults.set(notifyError, forKey: "notifyError") } }

    /// MQTT envelope version for outgoing packets: 1 = M5C-style, 2 = M5-style.
    @Published var outgoingVersion: UInt8 { didSet { defaults.set(Int(outgoingVersion), forKey: "outgoingVersion") } }

    /// `commandType 1008` control values (mapping not officially documented; adjustable).
    @Published var pauseValue: Int { didSet { defaults.set(pauseValue, forKey: "pauseValue") } }
    @Published var resumeValue: Int { didSet { defaults.set(resumeValue, forKey: "resumeValue") } }
    @Published var stopValue: Int { didSet { defaults.set(stopValue, forKey: "stopValue") } }

    /// Send speed as native commandType 1006 instead of the verified M220 GCode path.
    @Published var speedUseNativeCommand: Bool { didSet { defaults.set(speedUseNativeCommand, forKey: "speedUseNativeCommand") } }

    var isConfigured: Bool {
        !authToken.isEmpty && !printerSerial.isEmpty && !secretKeyHex.isEmpty
    }

    var account: AnkerAccount? {
        guard isConfigured else { return nil }
        return AnkerAccount(email: email, userID: userID, authToken: authToken, region: region)
    }

    var printer: AnkerPrinter? {
        guard isConfigured else { return nil }
        return AnkerPrinter(
            serial: printerSerial,
            name: printerName,
            model: printerModel,
            secretKeyHex: secretKeyHex
        )
    }

    func saveAccount(_ account: AnkerAccount) {
        email = account.email
        userID = account.userID
        authToken = account.authToken
        region = account.region
    }

    func savePrinter(_ printer: AnkerPrinter) {
        printerSerial = printer.serial
        printerName = printer.displayName
        printerModel = printer.model
        secretKeyHex = printer.secretKeyHex
    }

    func signOut() {
        authToken = ""
        userID = ""
        email = ""
        printerSerial = ""
        printerName = ""
        printerModel = ""
        secretKeyHex = ""
    }
}

/// Shared ring-buffer log shown in the Console tab.
final class AppLog: ObservableObject {
    @Published private(set) var lines: [String] = []
    private let lock = NSLock()
    private let capacity = 600

    func append(_ line: String) {
        let stamped = "[\(Self.timestamp())] \(line)"
        lock.lock()
        lines.append(stamped)
        if lines.count > capacity {
            lines.removeFirst(lines.count - capacity)
        }
        lock.unlock()
    }

    func clear() {
        lock.lock()
        lines.removeAll()
        lock.unlock()
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}
