import SwiftUI

@main
struct Network_SyncApp: App {
    @StateObject private var appState   = AppState.shared
    @StateObject private var scheduler  = SchedulerService.shared

    var body: some Scene {
        // Main window
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    NotificationService.requestPermission()
                    scheduler.sync()
                }
                .onChange(of: appState.scheduleSettings.isEnabled) { scheduler.sync() }
                .onChange(of: appState.scheduleSettings.hour)      { scheduler.sync() }
                .onChange(of: appState.scheduleSettings.minute)    { scheduler.sync() }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1100, height: 700)

        // Menu bar extra — always visible even when main window is closed
        MenuBarExtra("Network Sync", systemImage: menuBarIcon) {
            MenuBarView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuBarIcon: String {
        appState.isRunning ? "arrow.triangle.2.circlepath" : "externaldrive.connected.to.line.below"
    }
}
