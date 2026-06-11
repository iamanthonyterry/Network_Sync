import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var pipeline = PipelineEngine.shared

    var body: some View {
        // Status
        if appState.isRunning {
            let active  = appState.activeTasks.filter { $0.phase != .done && $0.phase != .error }.count
            let done    = appState.activeTasks.filter { $0.phase == .done }.count
            Text("Running — \(done) done, \(active) active")
                .foregroundStyle(.secondary)
        } else {
            let last = appState.runHistory.first
            if let last {
                Text("Last run: \(last.finishedAt.formatted(.relative(presentation: .named)))")
                    .foregroundStyle(.secondary)
            } else {
                Text("No runs yet").foregroundStyle(.secondary)
            }
        }

        Divider()

        if appState.isRunning {
            Button(role: .destructive) {
                pipeline.stop()
            } label: {
                Label("Stop Pipeline", systemImage: "stop.fill")
            }
        } else {
            Button {
                Task { await pipeline.runAll() }
            } label: {
                Label("Start Sync & Transcode", systemImage: "play.fill")
            }
            .disabled(appState.hyperDecks.isEmpty)
        }

        Divider()

        // Schedule status
        let s = appState.scheduleSettings
        if s.isEnabled {
            Label("Scheduled at \(s.displayTime) daily", systemImage: "clock")
                .foregroundStyle(.secondary)
        }

        Divider()

        Button("Show App") {
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("Quit") {
            NSApp.terminate(nil)
        }
    }
}
