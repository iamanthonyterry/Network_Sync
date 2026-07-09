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

            switch s.mode {
            case .daily:
                guard isDue(hour: s.hour, minute: s.minute) else {
                    if let last = workflowsFiredToday[workflow.id], !Calendar.current.isDateInToday(last) {
                        workflowsFiredToday.removeValue(forKey: workflow.id)
                    }
                    continue
                }
                guard isTodayActive(for: s) else { continue }
                guard workflowsFiredToday[workflow.id] == nil else { continue }
                workflowsFiredToday[workflow.id] = Date()

                appState.log("🕐 Scheduled workflow triggered: \(workflow.name)")
                Task { await workflowEngine.run(workflow) }

                if !s.repeatDaily, var updated = appState.workflows.first(where: { $0.id == workflow.id }) {
                    updated.schedule.isEnabled = false
                    appState.updateWorkflow(updated)
                }

            case .oneTime:
                guard isDue(date: s.oneTimeDate) else { continue }

                appState.log("🕐 Scheduled workflow triggered: \(workflow.name)")
                Task { await workflowEngine.run(workflow) }

                // One-time schedules always turn themselves off after firing.
                if var updated = appState.workflows.first(where: { $0.id == workflow.id }) {
                    updated.schedule.isEnabled = false
                    appState.updateWorkflow(updated)
                }
            }
        }
    }

    private func isDue(hour: Int, minute: Int) -> Bool {
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return now.hour == hour && now.minute == minute
    }

    /// Whether today's weekday is one of the days this recurring schedule
    /// is set to run on (an empty selection means every day).
    private func isTodayActive(for schedule: ScheduleSettings) -> Bool {
        guard let weekday = Weekday(rawValue: Calendar.current.component(.weekday, from: Date())) else {
            return true
        }
        return schedule.activeWeekdays.contains(weekday)
    }

    /// A one-time schedule is due once its target moment has arrived — since
    /// it disables itself immediately after firing, there's no need to guard
    /// against firing twice in the same minute.
    private func isDue(date target: Date) -> Bool {
        Date() >= target
    }
}
