import SwiftUI

/// Live printer dashboard: progress, temps, controls.
struct DashboardView: View {
    @EnvironmentObject private var monitor: PrintMonitor
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    connectionCard
                    progressCard
                    tempsCard
                    controlsCard
                }
                .padding()
            }
            .navigationTitle(settings.printerName.isEmpty ? "M5C" : settings.printerName)
            .refreshable { monitor.connect() }
        }
    }

    private var connectionCard: some View {
        HStack {
            Circle()
                .fill(color(for: monitor.connection))
                .frame(width: 10, height: 10)
            Text(connectionText)
                .font(.subheadline)
            Spacer()
            Button {
                monitor.connect()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
        .padding(.horizontal, 4)
    }

    private var progressCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: (monitor.status.progressPercent ?? 0) / 100)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: monitor.status.progressPercent)
                VStack {
                    Text(String(format: "%.0f%%", monitor.status.progressPercent ?? 0))
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                    Text(remainingText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: 260, maxHeight: 260)
            .aspectRatio(1, contentMode: .fit)

            if !monitor.status.fileName.isEmpty {
                Text(monitor.status.fileName)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(spacing: 8) {
                stateBadge
                if let layer = monitor.status.layer {
                    Text("Layer \(layer)\(monitor.status.totalLayers.map { " / \($0)" } ?? "")")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var tempsCard: some View {
        HStack(spacing: 12) {
            tempTile(
                icon: "flame.fill",
                tint: .orange,
                current: monitor.status.nozzleTemp,
                target: monitor.status.nozzleTarget,
                label: "Nozzle"
            )
            tempTile(
                icon: "rectangle.bottomthird.inset.filled",
                tint: .blue,
                current: monitor.status.bedTemp,
                target: monitor.status.bedTarget,
                label: "Bed"
            )
        }
    }

    private func tempTile(icon: String, tint: Color, current: Double?, target: Double?, label: String) -> some View {
        VStack(spacing: 4) {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundColor(tint)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(format: "%.0f°", current ?? 0))
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(target.map { String(format: "→ %.0f°", $0) } ?? "—")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var controlsCard: some View {
        VStack(spacing: 10) {
            Text("Print control")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                controlButton("pause.fill", "Pause", tint: .yellow) {
                    monitor.sendPrintControl(kind: .pause)
                }
                controlButton("play.fill", "Resume", tint: .green) {
                    monitor.sendPrintControl(kind: .resume)
                }
                controlButton("stop.fill", "Stop", tint: .red) {
                    monitor.sendPrintControl(kind: .stop)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func controlButton(_ icon: String, _ label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            .foregroundColor(tint)
        }
    }

    // MARK: - Helpers

    private var stateBadge: some View {
        Text(monitor.status.state.label)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(stateColor.opacity(0.18), in: Capsule())
            .foregroundColor(stateColor)
    }

    private var stateColor: Color {
        switch monitor.status.state {
        case .printing: return .green
        case .paused: return .orange
        case .error: return .red
        case .finished: return .blue
        default: return .gray
        }
    }

    private var remainingText: String {
        guard let seconds = monitor.status.remainingSeconds, seconds > 0 else { return "—" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .brief
        return formatter.string(from: TimeInterval(seconds)) ?? "—"
    }

    private var connectionText: String {
        switch monitor.connection {
        case .idle: return "Not connected"
        case .connecting: return "Connecting…"
        case .connected: return "Connected via AnkerMake cloud"
        case .disconnected(let reason): return reason.map { "Disconnected — \($0)" } ?? "Disconnected"
        }
    }

    private func color(for state: MQTTState) -> Color {
        switch state {
        case .connected: return .green
        case .connecting: return .orange
        default: return .red
        }
    }
}
