import SwiftUI
import Network

// MARK: - Shared ping helper (package-internal)
func resolveConnectionStatus(_ conn: NWConnection) async -> DeckStatus {
    await withCheckedContinuation { continuation in
        final class ResolveState: @unchecked Sendable { var resolved = false }
        let state = ResolveState()

        conn.stateUpdateHandler = { connectionState in
            guard !state.resolved else { return }
            switch connectionState {
            case .ready:
                state.resolved = true; conn.cancel()
                continuation.resume(returning: .online)
            case .failed:
                state.resolved = true; conn.cancel()
                continuation.resume(returning: .offline)
            default: break
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            guard !state.resolved else { return }
            state.resolved = true; conn.cancel()
            continuation.resume(returning: .offline)
        }
    }
}

struct DeckCardView: View {
    let deck: HyperDeck
    @EnvironmentObject var appState: AppState
    @StateObject private var pipeline = PipelineEngine.shared
    @ObservedObject private var monitor = ConnectionMonitor.shared

    @State private var files: [String] = []
    @State private var isShowingFiles = false
    @State private var isFetchingFiles = false

    // Live status from the shared monitor, which polls continuously and
    // auto-recovers as soon as the deck reconnects.
    private var pingStatus: DeckStatus { monitor.status(for: deck.ipAddress) }

    // Tasks belonging to this deck
    private var deckTasks: [SyncTask] {
        appState.activeTasks.filter { $0.deckName == deck.name }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(deck.name).font(.headline)
                    Text(deck.ipAddress).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                statusBadge(pingStatus)
            }

            Text(deck.remotePath)
                .font(.caption).italic().foregroundStyle(.secondary)

            // Per-deck task progress (visible while pipeline runs)
            if !deckTasks.isEmpty {
                Divider()
                VStack(spacing: 4) {
                    ForEach(deckTasks.prefix(4)) { task in
                        HStack(spacing: 6) {
                            Image(systemName: taskIcon(task.phase))
                                .font(.caption2)
                                .foregroundStyle(taskColor(task.phase))
                                .frame(width: 12)
                            Text(task.fileName)
                                .font(.system(size: 10, design: .monospaced))
                                .lineLimit(1)
                            Spacer()
                            ProgressView(value: task.overallProgress)
                                .frame(width: 60)
                        }
                    }
                }
            }

            Divider()

            // File list
            DisclosureGroup(isExpanded: $isShowingFiles) {
                if isFetchingFiles {
                    HStack {
                        ProgressView().controlSize(.mini)
                        Text("Reading drive...").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                } else if files.isEmpty {
                    Text(pingStatus == .unauthorized
                         ? "Login failed — check username/password."
                         : "No .mov files found.")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(files, id: \.self) { f in
                            HStack(spacing: 5) {
                                Image(systemName: "video.fill").font(.caption2).foregroundStyle(.blue)
                                Text(f).font(.system(.caption, design: .monospaced)).lineLimit(1)
                            }
                        }
                    }.padding(.vertical, 4)
                }
            } label: {
                Label("Files (\(files.count))", systemImage: "folder.badge.gearshape")
                    .font(.subheadline).bold()
            }

            Divider()

            // Actions
            HStack {
                Button {
                    Task { await monitor.pingNow(deck: deck); await fetchFiles() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }.buttonStyle(.borderless)

                Button(role: .destructive) {
                    appState.deleteDeck(id: deck.id)
                } label: {
                    Image(systemName: "trash")
                }.buttonStyle(.borderless)

                Spacer()

                Button {
                    Task { await pipeline.runDeck(deck) }
                } label: {
                    Label("Sync & Convert", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .disabled(pingStatus != .online || appState.isRunning)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .task { await fetchFiles() }
        .onChange(of: pingStatus) { _, newValue in
            if newValue == .online && files.isEmpty { Task { await fetchFiles() } }
        }
    }

    // MARK: - FTP file list
    private func fetchFiles() async {
        guard pingStatus == .online else { isFetchingFiles = false; return }
        isFetchingFiles = true
        files = await FTPService.listMovFiles(on: deck)
        isFetchingFiles = false
    }

    // MARK: - Helpers
    @ViewBuilder
    private func statusBadge(_ status: DeckStatus) -> some View {
        let (label, color): (String, Color) = {
            switch status {
            case .unknown:      return ("Checking", .gray)
            case .online:       return ("Online", .green)
            case .offline:      return ("Offline", .red)
            case .unauthorized: return ("Login Failed", .orange)
            case .syncing:      return ("Syncing", .blue)
            case .transcoding:  return ("Converting", .orange)
            }
        }()
        Text(label)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func taskIcon(_ phase: SyncTask.Phase) -> String {
        switch phase {
        case .queued: return "clock"
        case .downloading: return "arrow.down.circle"
        case .converting: return "film.stack"
        case .done: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        }
    }
    private func taskColor(_ phase: SyncTask.Phase) -> Color {
        switch phase {
        case .queued: return .secondary
        case .downloading: return .blue
        case .converting: return .orange
        case .done: return .green
        case .error: return .red
        }
    }
}
