import SwiftUI

/// Feed-rate override control. Goes up to 200% — beyond what the official
/// app exposes. Implemented with the Marlin `M220` GCode command over the
/// verified MQTT gcode channel (with an optional native commandType-1006 path).
struct SpeedView: View {
    @EnvironmentObject private var monitor: PrintMonitor
    @EnvironmentObject private var settings: AppSettings

    @State private var speed: Double = 100
    @State private var lastSent: Int?
    @State private var sending = false

    private let presets = [50, 75, 100, 125, 150, 175, 200]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    gauge
                    presetsRow
                    applyButton
                    explanation
                }
                .padding()
            }
            .navigationTitle("Speed")
        }
    }

    private var gauge: some View {
        VStack(spacing: 8) {
            Text(String(format: "%.0f%%", speed))
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundColor(speedColor)
                .contentTransition(.numericText())

            Slider(value: $speed, in: 50...200, step: 5) {
                Text("Feed rate override")
            } minimumValueLabel: {
                Text("50%").font(.caption2)
            } maximumValueLabel: {
                Text("200%").font(.caption2.bold())
            }
            .tint(speedColor)

            if let reported = monitor.status.reportedSpeed {
                Text("Printer reports: \(reported) (raw print-speed value)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let sent = lastSent {
                Text("Last applied: \(sent)%")
                    .font(.caption.italic())
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var presetsRow: some View {
        HStack(spacing: 8) {
            ForEach(presets, id: \.self) { preset in
                Button {
                    speed = Double(preset)
                } label: {
                    Text("\(preset)%")
                        .font(.footnote.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Int(speed) == preset ? speedColor.opacity(0.25) : Color.secondary.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var applyButton: some View {
        Button {
            applySpeed()
        } label: {
            HStack {
                if sending {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "bolt.fill")
                    Text("Apply \(Int(speed))%")
                        .bold()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(speedColor, in: RoundedRectangle(cornerRadius: 12))
            .foregroundColor(.white)
        }
        .disabled(sending)
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("How this works", systemImage: "info.circle")
                .font(.headline)
            Text(settings.speedUseNativeCommand
                 ? "Sending the native `commandType 1006` print-speed command. Its payload semantics are not fully documented — watch the Console tab for the printer's reply."
                 : "Sends `M220 S<percent>` — the Marlin feed-rate override — through the verified MQTT gcode channel (commandType 1043). The printer firmware has the final say on limits.")
                .font(.callout)
                .foregroundColor(.secondary)

            if speed > 150 {
                Label(
                    "Above 150% you may see reduced print quality (ringing, under-extrusion) or firmware clamping. Printing faster than the filament can melt causes failed prints.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.callout)
                .foregroundColor(.orange)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var speedColor: Color {
        switch speed {
        case ..<90: return .blue
        case ..<150: return .green
        case ..<180: return .orange
        default: return .red
        }
    }

    private func applySpeed() {
        sending = true
        monitor.sendSpeed(percent: Int(speed))
        lastSent = Int(speed)
        // Give the printer a moment, then clear the spinner.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            sending = false
        }
    }
}
