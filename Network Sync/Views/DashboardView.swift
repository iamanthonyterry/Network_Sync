import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var pipeline = PipelineEngine.shared

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if appState.hyperDecks.isEmpty {
                emptyState
            } else {
                HSplitView {
                    deckGrid
                    if appState.isRunning || !appState.activeTasks.isEmpty {
                        taskPanel
                            .frame(minWidth: 280, maxWidth: 360)
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
                Text("Sync Dashboard")
                    .font(.title2).bold()
                Text("\(appState.hyperDecks.count) decks · \(appState.syncLocation.volumeName)")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.isRunning ? Color.green : Color.gray.opacity(0.4))
                    .frame(width: 9, height: 9)
                Text(appState.isRunning ? "Running" : "Idle")
                    .font(.subheadline).foregroundStyle(.secondary)
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

    // MARK: - Right-side task panel
    private var taskPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Active Tasks")
                .font(.headline)
                .padding()
            Divider()
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
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(appState.pipelineLog.suffix(30), id: \.self) { line in
                        Text(line)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(8)
            }
            .frame(height: 120)
            .background(Color(NSColor.textBackgroundColor))
        }
    }

    // MARK: - Empty state
    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "server.rack")
                .font(.system(size: 48)).foregroundStyle(.secondary)
            Text("No HyperDecks Configured").font(.title3).bold()
            Text("Add your devices in the HyperDecks tab.")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Action bar
    private var actionBar: some View {
        HStack {
            Spacer()
            if appState.isRunning {
                Button(role: .destructive) {
                    pipeline.stop()
                } label: {
                    Label("Stop Pipeline", systemImage: "stop.fill")
                        .padding(.horizontal, 32).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent).tint(.red)
            } else {
                Button {
                    Task { await pipeline.runAll() }
                } label: {
                    Label("Start Sync & Transcode", systemImage: "play.fill")
                        .padding(.horizontal, 32).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.hyperDecks.isEmpty)
            }
            Spacer()
        }
        .padding()
    }
}
