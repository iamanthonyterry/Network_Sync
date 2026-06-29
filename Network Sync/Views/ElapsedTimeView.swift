import SwiftUI
import Combine

/// Displays a live elapsed-time progress bar and label for an active pipeline run.
/// Uses a repeating timer that ticks every second while the run is active.
/// Pass `compact: true` for the slim menu-bar variant.
struct ElapsedTimeView: View {
    let startTime: Date
    var compact: Bool = false

    @State private var elapsed: TimeInterval = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // Animate an indeterminate-style shimmer over 60 s cycles
    private var progressValue: Double {
        // Oscillate 0→1 every 60 s so the bar always appears "moving"
        let cycle: Double = 60
        return (elapsed.truncatingRemainder(dividingBy: cycle)) / cycle
    }

    var body: some View {
        if compact {
            compactLayout
        } else {
            fullLayout
        }
    }

    // MARK: - Full (dashboard)
    private var fullLayout: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Running", systemImage: "clock")
                    .font(.caption).bold()
                    .foregroundStyle(.blue)
                Spacer()
                Text(elapsedString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progressValue)
                .tint(.blue)
                .animation(.linear(duration: 1), value: progressValue)
        }
        .onReceive(timer) { _ in elapsed = Date().timeIntervalSince(startTime) }
    }

    // MARK: - Compact (menu bar)
    private var compactLayout: some View {
        HStack(spacing: 8) {
            ProgressView(value: progressValue)
                .tint(.blue)
                .frame(width: 80)
                .animation(.linear(duration: 1), value: progressValue)
            Text(elapsedString)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .onReceive(timer) { _ in elapsed = Date().timeIntervalSince(startTime) }
    }

    // MARK: - Helpers
    private var elapsedString: String {
        let h = Int(elapsed) / 3600
        let m = Int(elapsed) % 3600 / 60
        let s = Int(elapsed) % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
