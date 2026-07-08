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
    @StateObject private var workflowEngine = WorkflowEngine.shared
    @ObservedObject private var monitor = ConnectionMonitor.shared

    @State private var files: [String] = []
    @State private var isShowingFiles = false
    @State private var isFetchingFiles = false
    @State private var isShowingEdit = false
    @State private var showFormatConfirm = false
    @StateObject private var hyperDeck: HyperDeckService

    // Live status from the shared monitor, which polls continuously and
    // auto-recovers as soon as the deck reconnects.
    private var pingStatus: DeckStatus { monitor.status(for: deck.ipAddress) }

    init(deck: HyperDeck) {
        self.deck = deck
        _hyperDeck = StateObject(wrappedValue: HyperDeckService(host: deck.ipAddress))
    }

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
                    Text(emptyFilesMessage)
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

            // Live transport controls — record/stop, plus a manual format
            if pingStatus == .online {
                Divider()
                HyperDeckControls(hyperDeck: hyperDeck, showFormatConfirm: $showFormatConfirm)
            }

            Divider()

            // Actions
            HStack {
                Button {
                    Task { await monitor.pingNow(deck: deck); await fetchFiles() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }.buttonStyle(.borderless)

                Button {
                    isShowingEdit = true
                } label: {
                    Image(systemName: "pencil")
                }.buttonStyle(.borderless)

                Button(role: .destructive) {
                    appState.deleteDeck(id: deck.id)
                } label: {
                    Image(systemName: "trash")
                }.buttonStyle(.borderless)

                Spacer()

                runWorkflowMenu
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
        .sheet(isPresented: $isShowingEdit) {
            DeckEditSheet(deck: deck)
        }
        .confirmationDialog(
            "Format Drive?",
            isPresented: $showFormatConfirm,
            titleVisibility: .visible
        ) {
            Button("Format", role: .destructive) {
                Task { await hyperDeck.formatDrive() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will erase all media on \(deck.name). This cannot be undone.")
        }
        .onAppear { hyperDeck.startPolling() }
        .onDisappear { hyperDeck.stopPolling() }
    }

    // MARK: - Run Workflow menu
    // Lets the user pick any configured workflow and run it against just
    // this device, regardless of that workflow's own target list.
    @ViewBuilder
    private var runWorkflowMenu: some View {
        if appState.workflows.isEmpty {
            Label("No Workflows", systemImage: "flowchart")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Menu {
                ForEach(appState.workflows.sorted { $0.sortOrder < $1.sortOrder }) { workflow in
                    Button(workflow.name) {
                        Task { await workflowEngine.runDevice(workflow, deck: deck) }
                    }
                    .disabled(workflow.steps.isEmpty)
                }
            } label: {
                Label("Run Workflow", systemImage: "flowchart")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .buttonStyle(.borderedProminent)
            .disabled(pingStatus != .online || appState.isRunning)
        }
    }

    // Explains *why* the file list is empty, matching whichever specific
    // failure the monitor detected — not just a generic fallback.
    private var emptyFilesMessage: String {
        switch pingStatus {
        case .unauthorized: return "Login failed — check username/password."
        case .pathNotFound: return "Remote folder not found — check the file location in settings."
        case .noMedia:      return "No drive detected in the deck."
        default:            return "No .mov files found."
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
            case .pathNotFound: return ("Wrong Path", .orange)
            case .noMedia:      return ("No Drive", .red)
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

// MARK: - HyperDeck Transport Controls
// Record/stop plus a manual format action, shown while the deck is online.

struct HyperDeckControls: View {
    @ObservedObject var hyperDeck: HyperDeckService
    @Binding var showFormatConfirm: Bool

    private var isRecording: Bool { hyperDeck.transport == .recording }

    var body: some View {
        HStack(spacing: 10) {
            if isRecording {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .symbolEffect(.pulse)
                Text("REC")
                    .font(.caption).bold()
                    .foregroundStyle(.red)
            }

            Button {
                Task {
                    if isRecording { await hyperDeck.stop() }
                    else { await hyperDeck.record() }
                }
            } label: {
                if isRecording {
                    Label("Stop", systemImage: "stop.circle.fill")
                } else {
                    Label("Record", systemImage: "record.circle")
                        .foregroundStyle(.red)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(hyperDeck.isBusy)
            .animation(.easeInOut(duration: 0.2), value: isRecording)

            Spacer()

            Button { showFormatConfirm = true } label: {
                Label("Format", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(hyperDeck.isBusy)

            if hyperDeck.isBusy {
                ProgressView().controlSize(.small)
            }
        }
    }
}
