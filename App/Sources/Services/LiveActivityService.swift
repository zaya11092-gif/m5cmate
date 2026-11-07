import Foundation
import ActivityKit

/// Starts/updates/ends the print Live Activity (Dynamic Island + lock screen).
///
/// Updates happen in-process: the app keeps its MQTT connection alive while it
/// can, and a background refresh task keeps the activity ticking when possible.
final class LiveActivityService {
    static let shared = LiveActivityService()

    private var current: Activity<M5CPrintActivityAttributes>?

    var isRunning: Bool { current != nil }

    func start(printerName: String, fileName: String, status: PrinterStatus) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endAllStale()

        let attributes = M5CPrintActivityAttributes(printerName: printerName, fileName: fileName)
        let state = Self.contentState(from: status)

        do {
            current = try Activity.request(
                attributes: attributes,
                contentState: state
            )
        } catch {
            // Live Activities can fail (e.g. too many running); non-fatal.
        }
    }

    func update(status: PrinterStatus) {
        guard let activity = current else { return }
        let state = Self.contentState(from: status)
        Task {
            await activity.update(using: state)
        }
        // If the print ended, wrap the activity up after a short linger.
        if status.state == .finished || status.state == .stopped {
            end(delay: 5 * 60, finalState: state)
        } else if status.state == .idle {
            end(delay: 60, finalState: state)
        }
    }

    func end(delay: TimeInterval = 0, finalState: M5CPrintActivityAttributes.ContentState? = nil) {
        guard let activity = current else { return }
        current = nil
        let state = finalState ?? activity.contentState
        Task {
            if delay > 0 {
                await activity.end(using: state, dismissalPolicy: .after(Date().addingTimeInterval(delay)))
            } else {
                await activity.end(using: state, dismissalPolicy: .immediate)
            }
        }
    }

    /// Re-attaches to an activity started in a previous app run (e.g. after a crash).
    func reattachIfNeeded(printerName: String, fileName: String) {
        guard current == nil else { return }
        if let existing = Activity<M5CPrintActivityAttributes>.activities.first,
           existing.attributes.printerName == printerName {
            current = existing
        }
    }

    private func endAllStale() {
        for activity in Activity<M5CPrintActivityAttributes>.activities where activity.id != current?.id {
            let state = activity.contentState
            Task {
                await activity.end(using: state, dismissalPolicy: .immediate)
            }
        }
    }

    private static func contentState(from status: PrinterStatus) -> M5CPrintActivityAttributes.ContentState {
        M5CPrintActivityAttributes.ContentState(
            progress: status.progressPercent ?? 0,
            remainingSeconds: status.remainingSeconds,
            nozzleTemp: status.nozzleTemp ?? 0,
            bedTemp: status.bedTemp ?? 0,
            state: status.state.label,
            layer: status.layer,
            totalLayers: status.totalLayers
        )
    }
}
