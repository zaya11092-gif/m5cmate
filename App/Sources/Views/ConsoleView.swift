import SwiftUI

/// Raw MQTT log + ad-hoc GCode console — invaluable for validating commands
/// (e.g. testing speed encodings) against a real printer.
struct ConsoleView: View {
    @EnvironmentObject private var monitor: PrintMonitor
    @EnvironmentObject private var log: AppLog

    @State private var gcode = ""
    @State private var autoScroll = true

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                logList
                inputBar
            }
            .navigationTitle("Console")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        log.clear()
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(log.lines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(line.hasPrefix("[") && line.contains("→") ? .green : .primary)
                            .textSelection(.enabled)
                            .id(index)
                    }
                }
                .padding(8)
            }
            .background(Color(.systemBackground))
            .onChange(of: log.lines.count) { _ in
                guard autoScroll, !log.lines.isEmpty else { return }
                proxy.scrollTo(log.lines.count - 1, anchor: .bottom)
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("GCode, e.g. M220 S200", text: $gcode)
                .font(.system(size: 13, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .onSubmit(send)

            Button("Send", action: send)
                .disabled(gcode.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func send() {
        monitor.sendGCode(gcode)
        gcode = ""
    }
}
