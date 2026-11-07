import Foundation
import UserNotifications

/// Local notifications for print lifecycle events.
final class NotificationService {
    static let shared = NotificationService()

    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func post(id: String, title: String, body: String, playSound: Bool = true) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = playSound ? .default : nil
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Print events

    func printStarted(file: String, printer: String) {
        post(
            id: "print-started-\(printer)",
            title: "Print started",
            body: "“\(file)” has started on \(printer)."
        )
    }

    func printFinished(file: String, printer: String) {
        post(
            id: "print-finished-\(printer)",
            title: "✅ Print finished",
            body: "“\(file)” completed on \(printer)."
        )
    }

    func printPaused(file: String, reason: String?, printer: String) {
        post(
            id: "print-paused-\(printer)",
            title: "⏸ Print paused",
            body: "“\(file)” paused on \(printer)\(reason.map { " — \($0)" } ?? "")."
        )
    }

    func printResumed(file: String, printer: String) {
        post(
            id: "print-resumed-\(printer)",
            title: "▶️ Print resumed",
            body: "“\(file)” is running again on \(printer)."
        )
    }

    func printError(file: String, printer: String) {
        post(
            id: "print-error-\(printer)",
            title: "⚠️ Print problem",
            body: "The printer reported an error while printing “\(file)”. Open M5C Mate for details."
        )
    }

    func filamentRunout(printer: String) {
        post(
            id: "filament-\(printer)",
            title: "🧵 Filament runout",
            body: "\(printer) reports filament runout. Load new filament to resume."
        )
    }

    func connectionLost(printer: String) {
        post(
            id: "conn-lost-\(printer)",
            title: "Connection lost",
            body: "M5C Mate can no longer reach \(printer). Check your network.",
            playSound: false
        )
    }
}
