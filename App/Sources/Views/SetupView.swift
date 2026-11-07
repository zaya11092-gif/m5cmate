import SwiftUI

/// First-run onboarding: sign in with the AnkerMake account, pick a printer.
struct SetupView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var monitor: PrintMonitor

    @State private var password = ""
    @State private var printers: [AnkerPrinter] = []
    @State private var busy = false
    @State private var statusText = ""
    @State private var errorMessage = ""
    @State private var showAdvanced = false
    @State private var manualToken = ""

    var body: some View {
        NavigationView {
            Form {
                Section("AnkerMake account") {
                    Picker("Region", selection: $settings.region) {
                        ForEach(AnkerRegion.allCases) { region in
                            Text(region.label).tag(region)
                        }
                    }
                    TextField("Email", text: $settings.email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                    Button {
                        Task { await login() }
                    } label: {
                        if busy {
                            ProgressView()
                        } else {
                            Text("Sign in")
                        }
                    }
                    .disabled(busy || settings.email.isEmpty || password.isEmpty)
                }

                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.callout)
                    }
                }

                if !printers.isEmpty {
                    Section("Select printer") {
                        ForEach(printers) { printer in
                            Button {
                                settings.savePrinter(printer)
                                monitor.log.append("Printer selected: \(printer.displayName) (\(printer.model))")
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(printer.displayName)
                                        Text("\(printer.model) — \(printer.serial)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if settings.printerSerial == printer.serial {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    Toggle("Show manual setup", isOn: $showAdvanced.animation())
                    if showAdvanced {
                        TextField("Manual auth token (48 chars)", text: $manualToken)
                            .font(.caption.monospaced())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Use token") {
                            Task { await useManualToken() }
                        }
                        .disabled(manualToken.count != 48)
                    }
                } header: {
                    Text("Advanced")
                } footer: {
                    Text("Manual mode needs a token from `ankerctl` on your computer. "
                       + "The AES printer key is fetched automatically either way.")
                }
            }
            .navigationTitle("Set up M5C Mate")
        }
    }

    private func login() async {
        busy = true
        errorMessage = ""
        defer { busy = false }
        do {
            statusText = "Signing in…"
            let token = try await AnkerAPI().login(
                region: settings.region, email: settings.email, password: password
            )
            settings.authToken = token
            let profile = try await AnkerAPI().profile(region: settings.region, token: token)
            settings.userID = profile.userID
            if settings.email.isEmpty { settings.email = profile.email }

            statusText = "Fetching printers…"
            printers = try await AnkerAPI().printerList(region: settings.region, token: token)
            if printers.isEmpty {
                errorMessage = "No printers found on this account."
            }
            password = ""
        } catch {
            errorMessage = "Sign-in failed: \(error.localizedDescription)"
        }
    }

    private func useManualToken() async {
        busy = true
        errorMessage = ""
        defer { busy = false }
        do {
            settings.authToken = manualToken
            let profile = try await AnkerAPI().profile(region: settings.region, token: manualToken)
            settings.userID = profile.userID
            settings.email = profile.email
            printers = try await AnkerAPI().printerList(region: settings.region, token: manualToken)
            if printers.isEmpty {
                errorMessage = "No printers found for this token."
            }
        } catch {
            errorMessage = "Token check failed: \(error.localizedDescription)"
        }
    }
}
