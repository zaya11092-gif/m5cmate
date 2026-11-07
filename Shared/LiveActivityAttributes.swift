import ActivityKit
import Foundation

/// Attributes shared between the app (which updates the activity) and the
/// widget extension (which renders it in the Dynamic Island / lock screen).
struct M5CPrintActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Print progress 0...100
        var progress: Double
        /// Estimated remaining time in seconds (nil when unknown)
        var remainingSeconds: Int?
        /// Nozzle temperature in degrees C
        var nozzleTemp: Double
        /// Heated-bed temperature in degrees C
        var bedTemp: Double
        /// Current machine state (printing, paused, finished, ...)
        var state: String
        /// Current layer, if known
        var layer: Int?
        var totalLayers: Int?
    }

    /// Human-readable printer name shown as the activity title
    var printerName: String
    /// G-code file currently printing
    var fileName: String
}
