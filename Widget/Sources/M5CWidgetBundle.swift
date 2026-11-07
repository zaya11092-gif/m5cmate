import WidgetKit
import SwiftUI
import ActivityKit

@main
struct M5CWidgetBundle: WidgetBundle {
    var body: some Widget {
        M5CPrintActivityWidget()
    }
}

/// Live Activity for an ongoing print.
///
/// The Dynamic Island presents:
/// - compact: file/progress on the left, remaining time on the right
/// - minimal: a small progress ring
/// - expanded (long-press / tap-and-hold): full detail — progress bar,
///   remaining time, nozzle/bed temps and layer position.
struct M5CPrintActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: M5CPrintActivityAttributes.self) { context in
            // Lock Screen / notification presentation
            LockScreenPrintView(context: context)
                .padding(15)
                .activityBackgroundTint(Color(red: 0.09, green: 0.09, blue: 0.12))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(context.state.state, systemImage: "printer.dotmatrix.fill")
                            .font(.caption2.bold())
                            .foregroundColor(.green)
                        Text(context.attributes.fileName)
                            .font(.caption)
                            .lineLimit(2)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(String(format: "%.0f%%", context.state.progress))
                            .font(.title3.bold())
                            .contentTransition(.numericText())
                        Text(remaining(context.state.remainingSeconds))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        ProgressView(value: context.state.progress, total: 100)
                            .progressViewStyle(.linear)
                            .tint(progressTint(context.state.progress))
                        HStack {
                            Label(String(format: "%.0f°", context.state.nozzleTemp),
                                  systemImage: "flame.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Spacer()
                            Label(String(format: "%.0f°", context.state.bedTemp),
                                  systemImage: "rectangle.bottomthird.inset.filled")
                                .font(.caption2)
                                .foregroundColor(.blue)
                            Spacer()
                            if let layer = context.state.layer {
                                Text("L \(layer)\(context.state.totalLayers.map { "/\($0)" } ?? "")")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "printer.dotmatrix.fill")
                    .foregroundColor(.green)
                    .imageScale(.small)
            } compactTrailing: {
                Text(String(format: "%.0f%%", context.state.progress))
                    .font(.caption2.bold())
                    .contentTransition(.numericText())
                    .frame(maxWidth: 34)
            } minimal: {
                Gauge(
                    value: context.state.progress,
                    in: 0...100
                ) {
                    Image(systemName: "printer.dotmatrix")
                }
                .gaugeStyle(.accessoryCircular)
                .tint(progressTint(context.state.progress))
            }
            .keylineTint(.green)
        }
    }

    private func remaining(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "—" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: TimeInterval(seconds)) ?? "—"
    }

    private func progressTint(_ progress: Double) -> Color {
        switch progress {
        case ..<50: return .blue
        case ..<90: return .green
        default: return .mint
        }
    }
}

/// Full-width card on the Lock Screen.
private struct LockScreenPrintView: View {
    let context: ActivityViewContext<M5CPrintActivityAttributes>

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label(context.attributes.printerName, systemImage: "printer.dotmatrix.fill")
                    .font(.headline)
                Spacer()
                Text(context.state.state)
                    .font(.subheadline.bold())
                    .foregroundColor(.green)
            }

            Text(context.attributes.fileName)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)

            ProgressView(value: context.state.progress, total: 100)
                .tint(progressTint(context.state.progress))

            HStack {
                Text(String(format: "%.0f%%", context.state.progress))
                    .font(.title3.bold())
                    .contentTransition(.numericText())
                Spacer()
                Text(context.state.remainingSeconds.map { remaining($0) } ?? "")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Label(String(format: "%.0f°", context.state.nozzleTemp), systemImage: "flame.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                Label(String(format: "%.0f°", context.state.bedTemp), systemImage: "rectangle.bottomthird.inset.filled")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
    }

    private func remaining(_ seconds: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: TimeInterval(seconds)) ?? "—"
    }

    private func progressTint(_ progress: Double) -> Color {
        switch progress {
        case ..<50: return .blue
        case ..<90: return .green
        default: return .mint
        }
    }
}
