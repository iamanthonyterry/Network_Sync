import Foundation
import Combine

// Watches the clock and fires the pipeline when the scheduled time arrives.
// Uses a 30-second polling interval — lightweight and reliable without needing
// a background daemon or LaunchAgent.
@MainActor
class SchedulerService: ObservableObject {
    static let shared = SchedulerService()

    private var timer: Timer?
    private var firedToday = false
    private var lastFiredDate: Date?

    private let appState  = AppState.shared
    private let pipeline  = PipelineEngine.shared

    // Call at app launch and whenever schedule settings change
    func sync() {
        timer?.invalidate()
        guard appState.scheduleSettings.isEnabled else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        timer?.tolerance = 10
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Tick
    private func tick() {
        let s = appState.scheduleSettings
        guard s.isEnabled, !appState.isRunning else { return }

        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        guard now.hour == s.hour, now.minute == s.minute else {
            // Reset daily fired flag when the minute window passes
            if let last = lastFiredDate,
               !Calendar.current.isDateInToday(last) {
                firedToday = false
            }
            return
        }

        // Avoid double-firing within the same minute
        guard !firedToday else { return }
        firedToday = true
        lastFiredDate = Date()

        appState.log("🕐 Scheduled run triggered at \(s.displayTime)")
        Task { await pipeline.runAll() }

        // If not repeating daily, turn off after firing
        if !s.repeatDaily {
            appState.scheduleSettings.isEnabled = false
            stop()
        }
    }
}
