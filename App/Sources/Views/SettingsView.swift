import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var monitor: PrintMonitor

    @State private var notificationAuth = "unknown"

    var body: some View {
        NavigationView {
            Form {
                Section("Printer") {
                    LabeledContent("Name", value: settings.printerName)
                    LabeledContent("Model", value: settings.printerModel)
                    LabeledContent("Serial", value: settings.printerSerial)
                    Button("Reconnect") { monitor.connect() }
                }

                Section {
                    Toggle("Automatic Live Activity", isOn: $settings.autoLiveActivity)
                    Button("Test Live Activity") {
                        LiveActivityService.shared.start(
                            printerName: settings.printerName,
                            fileName: "test.gcode",
                            status: PrinterStatus(state: .printing, progressPercent: 42, remainingSeconds: 900)
                        )
                    }
                } header: {
                    Text("Dynamic Island")
                } footer: {
                    Text("Shows progress in the Dynamic Island and on the Lock Screen. Long-press the island for details (temps, layer, remaining time).")
                }

                Section {
                    Toggle("Print started", isOn: $settings.notifyStarted)
                    Toggle("Print finished", isOn: $settings.notifyFinished)
                    Toggle("Paused / resumed", isOn: $settings.notifyPaused)
                    Toggle("Errors", isOn: $settings.notifyError)
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Status: \(notificationAuth)")
                }

                Section {
                    Picker("Envelope version", selection: $settings.outgoingVersion) {
                        Text("1 (M5C)").tag(UInt8(1))
                        Text("2 (M5)").tag(UInt8(2))
                    }
                    LabeledContent("Pause value", value: "\(settings.pauseValue)")
                    LabeledContent("Resume value", value: "\(settings.resumeValue)")
                    LabeledContent("Stop value", value: "\(settings.stopValue)")
                    Toggle("Speed: native 1006 command", isOn: $settings.speedUseNativeCommand)
                } header: {
                    Text("Advanced protocol")
                } footer: {
                    Text("If print control buttons have no effect, the 1008 value mapping may differ for your firmware — swap the numbers here and watch the Console for replies.")
                }

                Section("Account") {
                    LabeledContent("Email", value: settings.email)
                    LabeledContent("Region", value: settings.region.label)
                    Button("Sign out", role: .destructive) {
                        monitor.disconnect()
                        LiveActivityService.shared.end()
                        settings.signOut()
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear { refreshNotificationStatus() }
        }
    }
    private func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    notificationAuth = "authorized"
                case .denied:
                    notificationAuth = "denied — enable in iOS Settings"
                default:
                    notificationAuth = "not requested"
                }
            }
        }
    }
}

import UserNotifications
