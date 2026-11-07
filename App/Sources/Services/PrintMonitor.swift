import Foundation
import BackgroundTasks

/// Central monitor: owns the MQTT client, merges status messages, detects
/// lifecycle transitions and drives notifications + the Live Activity.
final class PrintMonitor: ObservableObject {

    static let shared = PrintMonitor()
    static let refreshTaskID = "com.m5cmate.app.refresh"

    @Published private(set) var status = PrinterStatus()
    @Published private(set) var connection: MQTTState = .idle
    @Published private(set) var lastConnectedPrinter: String = ""

    let mqtt = AnkerMQTTClient()
    let log = AppLog()
    private var settings: AppSettings { AppSettings.shared }

    private var lastState: PrinterState?
    private var lastActivityUpdate = Date.distantPast
    private var sawFirstStatus = false

    private init() {
        mqtt.onJSONObject = { [weak self] dict in
            self?.handle(dict)
        }
        mqtt.onLog = { [weak self] line in
            self?.log.append(line)
        }
        mqtt.onStateChange = { [weak self] state in
            DispatchQueue.main.async {
                self?.connection = state
                if case .connected = state {
                    self?.onConnected()
                }
                if case .disconnected = state {
                    self?.onDisconnected()
                }
            }
        }
    }

    // MARK: - Connection lifecycle

    func connect() {
        guard let account = settings.account, let printer = settings.printer else { return }
        lastConnectedPrinter = printer.displayName
        mqtt.connect(account: account, printer: printer, outgoingVersion: settings.outgoingVersion)
    }

    func disconnect() {
        mqtt.disconnect()
    }

    private func onConnected() {
        sawFirstStatus = false
        mqtt.queryStatus()
    }

    private func onDisconnected() {
        // Keep the Live Activity on screen; it shows the last known state until
        // the next successful refresh.
    }

    // MARK: - Status handling

    private func handle(_ dict: [String: Any]) {
        var updated = status
        StatusParser.apply(dict, to: &updated)

        let previous = lastState
        let isFirst = !sawFirstStatus
        status = updated
        lastState = updated.state
        sawFirstStatus = true

        detectTransitions(previous: previous, isFirstStatus: isFirst, status: updated)
        updateActivityThrottled(status: updated)
    }

    private func detectTransitions(previous: PrinterState?, isFirstStatus: Bool, status: PrinterStatus) {
        let file = status.fileName.isEmpty ? "Print" : status.fileName
        let printer = settings.printerName.isEmpty ? "printer" : settings.printerName

        // First status after (re)connect: reattach silently, no event spam.
        if isFirstStatus {
            if status.isActive && settings.autoLiveActivity {
                LiveActivityService.shared.reattachIfNeeded(printerName: printer, fileName: file)
                if !LiveActivityService.shared.isRunning {
                    LiveActivityService.shared.start(printerName: printer, fileName: file, status: status)
                }
            }
            return
        }

        if status.rawState == "filament_runout", previous != .paused {
            NotificationService.shared.filamentRunout(printer: printer)
        }

        switch (previous, status.state) {
        case (.printing, .paused), (.preparing, .paused):
            if settings.notifyPaused {
                NotificationService.shared.printPaused(
                    file: file,
                    reason: status.rawState == "filament_runout" ? "filament runout" : nil,
                    printer: printer
                )
            }
        case (.paused, .printing):
            if settings.notifyPaused {
                NotificationService.shared.printResumed(file: file, printer: printer)
            }
        case (_, .printing) where previous != .printing && previous != .preparing && previous != .paused:
            if settings.notifyStarted {
                NotificationService.shared.printStarted(file: file, printer: printer)
            }
            if settings.autoLiveActivity, !LiveActivityService.shared.isRunning {
                LiveActivityService.shared.start(printerName: printer, fileName: file, status: status)
            }
        case (_, .finished) where previous == .printing || previous == .paused || previous == .preparing:
            if settings.notifyFinished {
                NotificationService.shared.printFinished(file: file, printer: printer)
            }
        case (_, .stopped) where previous == .printing || previous == .paused:
            if settings.notifyFinished {
                NotificationService.shared.printFinished(file: file, printer: printer)
            }
        case (_, .error) where previous != .error:
            if settings.notifyError {
                NotificationService.shared.printError(file: file, printer: printer)
            }
        default:
            break
        }
    }

    private func updateActivityThrottled(status: PrinterStatus) {
        guard LiveActivityService.shared.isRunning else { return }
        guard Date().timeIntervalSince(lastActivityUpdate) > 0.8 else { return }
        lastActivityUpdate = Date()
        LiveActivityService.shared.update(status: status)
    }

    // MARK: - Commands (thin wrappers used by the UI)

    func sendGCode(_ line: String) { mqtt.sendGCode(line) }
    func sendPrintControl(kind: PrintControlKind) {
        let value: Int
        switch kind {
        case .pause: value = settings.pauseValue
        case .resume: value = settings.resumeValue
        case .stop: value = settings.stopValue
        }
        mqtt.sendPrintControl(value: value, userName: settings.email)
    }
    func sendSpeed(percent: Int) {
        if settings.speedUseNativeCommand {
            mqtt.sendPrintSpeed(value: percent * 100)  // 1/100 units, mirroring temps
        } else {
            mqtt.sendGCode("M220 S\(percent)")
        }
    }

    // MARK: - Background refresh

    /// Must be called before the app finishes launching.
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskID,
            using: nil
        ) { [weak self] task in
            guard let self else { task.setTaskCompleted(success: false); return }
            self.handleRefresh(task: task as? BGAppRefreshTask)
        }
    }

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            log.append("Background refresh scheduling failed: \(error.localizedDescription)")
        }
    }

    private func handleRefresh(task: BGAppRefreshTask?) {
        scheduleBackgroundRefresh()
        guard let account = settings.account, let printer = settings.printer else {
            task?.setTaskCompleted(success: true)
            return
        }

        // Brief reconnect to catch up on state, then yield the runtime back.
        // The regular onStateChange wiring already queries status on connect.
        var finished = false
        connect()

        // Give the broker a bounded window to deliver fresh status.
        DispatchQueue.global().asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, !finished else { return }
            finished = true
            if LiveActivityService.shared.isRunning && !self.status.isActive {
                LiveActivityService.shared.end()
            }
            self.mqtt.disconnect()
            task?.setTaskCompleted(success: true)
        }

        task?.expirationHandler = { [weak self] in
            finished = true
            self?.mqtt.disconnect()
            task?.setTaskCompleted(success: false)
        }
    }
}

enum PrintControlKind {
    case pause
    case resume
    case stop
}
