import SwiftUI

@main
struct Network_SyncApp: App {
    @StateObject private var appState  = AppState.shared
    @StateObject private var scheduler = SchedulerService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    NotificationService.requestPermission()
                    scheduler.sync()
                    ConnectionMonitor.shared.start()
                }
                .onOpenURL { url in
                    GmailAuthService.shared.handleRedirect(url: url)
                }
                .onChange(of: appState.scheduleSettings.isEnabled) { scheduler.sync() }
                .onChange(of: appState.scheduleSettings.hour)      { scheduler.sync() }
                .onChange(of: appState.scheduleSettings.minute)    { scheduler.sync() }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    UpdateService.shared.checkForUpdates()
                }
                .disabled(!UpdateService.shared.canCheckForUpdates)
            }
            CommandGroup(after: .appInfo) {
                Button("Start Sync & Transcode") {
                    Task { await PipelineEngine.shared.runAll() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(appState.isRunning || (appState.hyperDecks.count + appState.switchers.count + appState.cloudStores.count == 0))

                if appState.isRunning {
                    Button("Stop Pipeline") {
                        PipelineEngine.shared.stop()
                    }
                    .keyboardShortcut(".", modifiers: .command)
                }
            }
        }

        MenuBarExtra("Network Sync", systemImage: menuBarIcon) {
            MenuBarView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuBarIcon: String {
        appState.isRunning
            ? "arrow.triangle.2.circlepath"
            : "externaldrive.connected.to.line.below"
    }
}
