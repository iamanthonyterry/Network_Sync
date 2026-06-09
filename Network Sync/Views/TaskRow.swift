import SwiftUI

struct TaskRow: View {
    let task: SyncTask

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: phaseIcon)
                    .foregroundStyle(phaseColor)
                    .frame(width: 16)
                Text(task.fileName)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                Spacer()
                Text(task.phase.label)
                    .font(.caption2).bold()
                    .foregroundStyle(phaseColor)
            }

            if task.phase == .downloading || task.phase == .converting {
                VStack(spacing: 3) {
                    progressRow(label: "DL", value: task.syncProgress, color: .blue)
                    progressRow(label: "CV", value: task.convertProgress, color: .orange)
                }
            } else if task.phase == .done {
                ProgressView(value: 1.0)
                    .tint(.green)
            } else if task.phase == .error, let msg = task.errorMessage {
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func progressRow(label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            ProgressView(value: value)
                .tint(color)
        }
    }

    private var phaseIcon: String {
        switch task.phase {
        case .queued:      return "clock"
        case .downloading: return "arrow.down.circle"
        case .converting:  return "film.stack"
        case .done:        return "checkmark.circle.fill"
        case .error:       return "xmark.circle.fill"
        }
    }

    private var phaseColor: Color {
        switch task.phase {
        case .queued:      return .secondary
        case .downloading: return .blue
        case .converting:  return .orange
        case .done:        return .green
        case .error:       return .red
        }
    }
}
