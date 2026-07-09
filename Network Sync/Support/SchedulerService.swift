import Foundation
import Combine

// Watches the clock and runs any workflow when its scheduled time arrives.
// Uses a 30-second polling interval — lightweight and reliable without
// needing a background daemon or LaunchAgent.
@MainActor
class SchedulerService: ObservableObject {
    static let shared = SchedulerService()

    private var timer: Timer?
    /// Tracks which workflows already fired today, keyed by workflow id.
    private var workflowsFiredToday: [UUID: Date] = [:]

    private let appState = AppState.shared
    private let workflowEngine = WorkflowEngine.shared

    // Call at app launch and whenever any workflow's schedule changes
    func sync() {
        timer?.invalidate()
        guard hasAnyScheduleEnabled else { return }
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

    private var hasAnyScheduleEnabled: Bool {
        appState.workflows.contains { $0.schedule.isEnabled }
    }

    // MARK: - Tick
    private func tick() {
        guard !appState.isRunning else { return }
        tickWorkflowSchedules()
    }

    // MARK: - Per-workflow schedules
    private func tickWorkflowSchedules() {
        for workflow in appState.workflows {
            let s = workflow.schedule
            guard s.isEnabled else { continue }
            guard !appState.isRunning else { return }   // only one run at a time

            guard isDue(hour: s.hour, minute: s.minute) else {
                if let last = workflowsFiredToday[workflow.id], !Calendar.current.isDateInToday(last) {
                    workflowsFiredToday.removeValue(forKey: workflow.id)
                }
                continue
            }
            guard workflowsFiredToday[workflow.id] == nil else { continue }
            workflowsFiredToday[workflow.id] = Date()

            appState.log("🕐 Scheduled workflow triggered: \(workflow.name)")
            Task { await workflowEngine.run(workflow) }

            if !s.repeatDaily, var updated = appState.workflows.first(where: { $0.id == workflow.id }) {
                updated.schedule.isEnabled = false
                appState.updateWorkflow(updated)
            }
        }
    }

    private func isDue(hour: Int, minute: Int) -> Bool {
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return now.hour == hour && now.minute == minute
    }
}
