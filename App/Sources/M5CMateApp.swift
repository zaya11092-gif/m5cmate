import SwiftUI

@main
struct M5CMateApp: App {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var monitor = PrintMonitor.shared

    init() {
        PrintMonitor.shared.registerBackgroundTasks()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(monitor)
                .environmentObject(PrintMonitor.shared.log)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var monitor: PrintMonitor

    var body: some View {
        if settings.isConfigured {
            MainTabView()
                .onAppear {
                    if !monitor.mqtt.isConnected {
                        monitor.connect()
                    }
                }
        } else {
            SetupView()
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Printer", systemImage: "printer") }
            SpeedView()
                .tabItem { Label("Speed", systemImage: "speedometer") }
            ConsoleView()
                .tabItem { Label("Console", systemImage: "terminal") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
