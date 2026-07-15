import SwiftUI

/// Displays a live elapsed-time progress bar and label for an active pipeline run.
/// Driven by `TimelineView` so it ticks on its own internal schedule —
/// independent of how often the parent view happens to re-render (which,
/// during an active sync, can be many times a second from progress callbacks).
/// Pass `compact: true` for the slim menu-bar variant.
struct ElapsedTimeView: View {
    let startTime: Date
    var compact: Bool = false

    var body: some View {
        TimelineView(.periodic(from: startTime, by: 1)) { context in
            let elapsed = context.date.timeIntervalSince(startTime)
            if compact {
                compactLayout(elapsed: elapsed)
            } else {
                fullLayout(elapsed: elapsed)
            }
        }
    }

    // MARK: - Full (dashboard)
    private func fullLayout(elapsed: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Running", systemImage: "clock")
                    .font(.caption).bold()
                    .foregroundStyle(.blue)
                Spacer()
                Text(elapsedString(elapsed))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progressValue(elapsed))
                .tint(.blue)
                .animation(.linear(duration: 1), value: elapsed)
        }
    }

    // MARK: - Compact (menu bar)
    private func compactLayout(elapsed: TimeInterval) -> some View {
        HStack(spacing: 8) {
            ProgressView(value: progressValue(elapsed))
                .tint(.blue)
                .frame(width: 80)
                .animation(.linear(duration: 1), value: elapsed)
            Text(elapsedString(elapsed))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    // Animate an indeterminate-style shimmer over 60 s cycles so the bar
    // always appears "moving" even though there's no real percent-complete
    // for an open-ended run.
    private func progressValue(_ elapsed: TimeInterval) -> Double {
        let cycle: Double = 60
        return elapsed.truncatingRemainder(dividingBy: cycle) / cycle
    }

    private func elapsedString(_ elapsed: TimeInterval) -> String {
        let h = Int(elapsed) / 3600
        let m = Int(elapsed) % 3600 / 60
        let s = Int(elapsed) % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
