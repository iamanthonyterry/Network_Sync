import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedRun: PipelineRun?

    var body: some View {
        HSplitView {
            // Run list
            VStack(spacing: 0) {
                HStack {
                    Text("Run History")
                        .font(.title2).bold()
                    Spacer()
                    if !appState.runHistory.isEmpty {
                        Button(role: .destructive) {
                            appState.runHistory.removeAll()
                            selectedRun = nil
                        } label: {
                            Label("Clear", systemImage: "trash")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                    }
                }
                .padding()
                Divider()

                if appState.runHistory.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 40)).foregroundStyle(.secondary)
                        Text("No Runs Yet").font(.title3).bold()
                        Text("Completed pipeline runs appear here.")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else {
                    List(appState.runHistory, selection: $selectedRun) { run in
                        RunRow(run: run)
                            .tag(run)
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 260, maxWidth: 320)

            // Run detail
            if let run = selectedRun {
                RunDetailView(run: run)
            } else {
                VStack {
                    Spacer()
                    Text("Select a run to view details")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Run Row
struct RunRow: View {
    let run: PipelineRun

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: run.errors == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(run.errors == 0 ? .green : .orange)
                Text(run.startedAt, style: .date)
                    .font(.headline)
                Spacer()
                Text(run.durationFormatted)
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                statChip("\(run.converted) converted", color: .green)
                if run.errors > 0 { statChip("\(run.errors) errors", color: .red) }
                if run.skipped > 0 { statChip("\(run.skipped) skipped", color: .secondary) }
            }
            Text(run.startedAt, style: .time)
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func statChip(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Run Detail
struct RunDetailView: View {
    let run: PipelineRun
    @State private var showLog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Header stats
                HStack(spacing: 16) {
                    statCard(value: "\(run.converted)", label: "Converted", color: .green)
                    statCard(value: "\(run.skipped)",   label: "Skipped",   color: .blue)
                    statCard(value: "\(run.errors)",    label: "Errors",    color: run.errors > 0 ? .red : .secondary)
                    statCard(value: run.durationFormatted, label: "Duration", color: .primary)
                }

                Divider()

                // Time info
                Group {
                    labelRow("Started",  run.startedAt.formatted(date: .abbreviated, time: .shortened))
                    labelRow("Finished", run.finishedAt.formatted(date: .abbreviated, time: .shortened))
                    labelRow("Decks",    run.decksProcessed.joined(separator: ", "))
                }

                Divider()

                // Log
                DisclosureGroup(isExpanded: $showLog) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(run.log, id: \.self) { line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 320)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } label: {
                    Label("Run Log (\(run.log.count) lines)", systemImage: "doc.text")
                        .font(.headline)
                }
            }
            .padding()
        }
    }

    private func statCard(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2).bold().foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(minWidth: 80)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func labelRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.subheadline).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
            Text(value).font(.subheadline)
        }
    }
}
