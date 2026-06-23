import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var pipeline = PipelineEngine.shared

    var activeCount: Int  { appState.activeTasks.filter { $0.phase == .downloading || $0.phase == .converting }.count }
    var doneCount: Int    { appState.activeTasks.filter { $0.phase == .done }.count }
    var errorCount: Int   { appState.activeTasks.filter { $0.phase == .error }.count }

    var totalDevices: Int  { appState.hyperDecks.count + appState.switchers.count + appState.cloudStores.count }
    var hasDecks: Bool     { !appState.hyperDecks.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if totalDevices == 0 {
                emptyState
            } else {
                HSplitView {
                    deckGrid
                    if !appState.activeTasks.isEmpty {
                        taskPanel.frame(minWidth: 300, maxWidth: 380)
                    }
                }
            }

            Divider()
            actionBar
        }
    }

    // MARK: - Header
    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sync Dashboard").font(.title2).bold()
                Text("\(appState.hyperDecks.count) decks · \(appState.switchers.count) switchers · \(appState.cloudStores.count) cloud stores")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()

            if appState.isRunning {
                HStack(spacing: 10) {
                    statPill("\(activeCount) active", color: .blue)
                    statPill("\(doneCount) done", color: .green)
                    if errorCount > 0 { statPill("\(errorCount) errors", color: .red) }
                }
            } else {
                HStack(spacing: 6) {
                    Circle().fill(Color.gray.opacity(0.4)).frame(width: 9, height: 9)
                    Text("Idle").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }

    // MARK: - Deck Grid
    private var deckGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 270))], spacing: 16) {
                ForEach(appState.hyperDecks) { deck in
                    DeckCardView(deck: deck)
                }
            }
            .padding()
        }
    }

    // MARK: - Task panel
    private var taskPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Panel header with overall progress
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Active Tasks").font(.headline)
                    Spacer()
                    if !appState.isRunning && !appState.activeTasks.isEmpty {
                        Button("Clear") { appState.activeTasks.removeAll() }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                }
                if !appState.activeTasks.isEmpty {
                    let total = Double(appState.activeTasks.count)
                    let done  = Double(doneCount)
                    ProgressView(value: done, total: total).tint(.blue)
                    Text("\(doneCount) of \(appState.activeTasks.count) files complete")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()

            Divider()

            // Per-file task list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(appState.activeTasks) { task in
                        TaskRow(task: task)
                        Divider()
                    }
                }
            }

            Divider()

            // Log tail
            VStack(alignment: .leading, spacing: 0) {
                Text("Log").font(.caption).bold()
                    .foregroundStyle(.secondary).padding([.horizontal, .top], 8)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(appState.pipelineLog.enumerated()), id: \.offset) { i, line in
                                Text(line)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(i)
                            }
                        }
                        .padding(.horizontal, 8).padding(.bottom, 8)
                    }
                    .onChange(of: appState.pipelineLog.count) {
                        if let last = appState.pipelineLog.indices.last {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(height: 140)
            .background(Color(NSColor.textBackgroundColor))
        }
    }

    // MARK: - Empty state
    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "network").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("No Devices Configured").font(.title3).bold()
            Text("Add HyperDecks, ATEM Switchers, or Cloud Stores in the Devices tab.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    // MARK: - Action bar
    private var actionBar: some View {
        HStack(spacing: 16) {
            // Last run summary
            if let last = appState.runHistory.first, !appState.isRunning {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last run: \(last.finishedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("\(last.converted) converted · \(last.durationFormatted)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.leading)
            }

            Spacer()

            // Retry button — visible after a run with errors
            if !appState.isRunning && !appState.failedTasks.isEmpty {
                Button {
                    Task { await pipeline.retryFailed() }
                } label: {
                    Label("Retry \(appState.failedTasks.count) Failed", systemImage: "arrow.counterclockwise")
                        .padding(.horizontal, 16).padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }

            if appState.isRunning {
                Button(role: .destructive) {
                    pipeline.stop()
                } label: {
                    Label("Stop Pipeline", systemImage: "stop.fill")
                        .padding(.horizontal, 28).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent).tint(.red)
            } else {
                Button {
                    Task { await pipeline.runAll() }
                } label: {
                    Label("Start Sync & Transcode", systemImage: "play.fill")
                        .padding(.horizontal, 28).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasDecks)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Helpers
    private func statPill(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
