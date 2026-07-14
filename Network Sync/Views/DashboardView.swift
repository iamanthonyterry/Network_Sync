import SwiftUI

// MARK: - Dashboard Selection
// Identifies whichever device is currently selected in the left-hand list,
// so the right-hand pane knows which settings to show.
enum DashboardSelection: Hashable {
    case deck(UUID)
    case switcher(UUID)
    case cloudStore(UUID)
}

// MARK: - DashboardView
// Home base: shows every configured device (HyperDecks, ATEM Switchers,
// Cloud Stores) plus anything found on the network, all in one place.
// Two columns: the left lists every device with quick controls, and the
// right shows the settings and controls for whichever device is selected.

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var workflowEngine = WorkflowEngine.shared
    @StateObject private var discovery = DeviceDiscovery()
    @ObservedObject private var monitor = ConnectionMonitor.shared

    @State private var showingAddDeck = false
    @State private var showingAddSwitcher = false
    @State private var showingAddCloudStore = false
    @State private var selection: DashboardSelection?

    var activeCount: Int  { appState.activeTasks.filter { $0.phase == .downloading || $0.phase == .converting }.count }
    var doneCount: Int    { appState.activeTasks.filter { $0.phase == .done }.count }
    var errorCount: Int   { appState.activeTasks.filter { $0.phase == .error }.count }

    var totalDevices: Int  { appState.hyperDecks.count + appState.switchers.count + appState.cloudStores.count }

    private var hasDiscovered: Bool {
        !discovery.discoveredDecks.isEmpty || !discovery.discoveredSwitchers.isEmpty
            || !discovery.discoveredCloudStores.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if let error = appState.mountError {
                mountErrorBanner(error)
                Divider()
            }

            if totalDevices == 0 && !hasDiscovered {
                emptyState
            } else {
                HStack(spacing: 0) {
                    deviceList
                        .frame(width: 300)
                    Divider()
                    detailPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            Divider()
            actionBar
        }
        .sheet(isPresented: $showingAddDeck) { DeckEditSheet(deck: nil) }
        .sheet(isPresented: $showingAddSwitcher) { SwitcherEditSheet(switcher: nil) }
        .sheet(isPresented: $showingAddCloudStore) { CloudStoreEditSheet(store: nil) }
        .onAppear { monitor.start() }
    }

    // MARK: - Mount error banner
    private func mountErrorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sync stopped — couldn't reach storage").font(.subheadline).bold()
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let workflow = appState.lastRunWorkflow {
                Button {
                    Task { await workflowEngine.run(workflow) }
                } label: {
                    Label("Retry", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }
            Button {
                appState.mountError = nil
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.red.opacity(0.1))
    }

    // MARK: - Header
    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dashboard").font(.title2).bold()
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

                scanButton

                Menu {
                    Button("HyperDeck") { showingAddDeck = true }
                    Button("ATEM Switcher") { showingAddSwitcher = true }
                    Button("Cloud Store") { showingAddCloudStore = true }
                } label: {
                    Label("Add Device", systemImage: "plus")
                }.buttonStyle(.borderedProminent)
            }

            if let start = appState.runStartTime {
                ElapsedTimeView(startTime: start)
            }
        }
        .padding()
    }

    @ViewBuilder private var scanButton: some View {
        Button {
            if discovery.isScanning { discovery.stopScanning() }
            else { discovery.startScanning() }
        } label: {
            if discovery.isScanning {
                Label("Scanning…", systemImage: "antenna.radiowaves.left.and.right")
                    .symbolEffect(.pulse)
            } else {
                Label("Scan Network", systemImage: "antenna.radiowaves.left.and.right")
            }
        }
    }

    // MARK: - Left column: device list
    private var deviceList: some View {
        List(selection: $selection) {
            if !appState.hyperDecks.isEmpty {
                Section("HyperDecks") {
                    ForEach(appState.hyperDecks) { deck in
                        DeckListRow(deck: deck)
                            .tag(DashboardSelection.deck(deck.id))
                    }
                }
            }

            if !appState.switchers.isEmpty {
                Section("ATEM Switchers") {
                    ForEach(appState.switchers) { switcher in
                        SwitcherListRow(switcher: switcher)
                            .tag(DashboardSelection.switcher(switcher.id))
                    }
                }
            }

            if !appState.cloudStores.isEmpty {
                Section("Cloud Stores") {
                    ForEach(appState.cloudStores) { store in
                        CloudStoreListRow(store: store)
                            .tag(DashboardSelection.cloudStore(store.id))
                    }
                }
            }

            discoveredSection
        }
        .listStyle(.sidebar)
    }

    // MARK: - Right column: selected device's settings
    @ViewBuilder private var detailPane: some View {
        switch selection {
        case .deck(let id):
            if let deck = appState.hyperDecks.first(where: { $0.id == id }) {
                DeckDetailPane(deck: deck)
                    .id(deck.id)
            } else {
                emptyDetailState
            }
        case .switcher(let id):
            if let switcher = appState.switchers.first(where: { $0.id == id }) {
                SwitcherDetailPane(switcher: switcher)
                    .id(switcher.id)
            } else {
                emptyDetailState
            }
        case .cloudStore(let id):
            if let store = appState.cloudStores.first(where: { $0.id == id }) {
                CloudStoreDetailPane(store: store)
                    .id(store.id)
            } else {
                emptyDetailState
            }
        case .none:
            emptyDetailState
        }
    }

    private var emptyDetailState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Select a device")
                .font(.headline)
            Text("Choose a device on the left to view its settings and controls.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Discovered on network
    @ViewBuilder private var discoveredSection: some View {
        let newDecks = discovery.discoveredDecks.filter { d in
            !appState.hyperDecks.contains(where: { $0.ipAddress == d.ipAddress })
        }
        let newSwitchers = discovery.discoveredSwitchers.filter { s in
            !appState.switchers.contains(where: { $0.ipAddress == s.ipAddress })
        }
        let newStores = discovery.discoveredCloudStores.filter { s in
            !appState.cloudStores.contains(where: { $0.ipAddress == s.ipAddress })
        }

        if !newDecks.isEmpty || !newSwitchers.isEmpty || !newStores.isEmpty {
            Section("Discovered on Network") {
                ForEach(newDecks) { deck in
                    DiscoveredDeviceRow(name: deck.name, ip: deck.ipAddress, icon: "server.rack") {
                        appState.addDeck(deck)
                    }
                }
                ForEach(newSwitchers) { s in
                    DiscoveredDeviceRow(name: s.name, ip: s.ipAddress, icon: "switch.2") {
                        appState.addSwitcher(s)
                    }
                }
                ForEach(newStores) { s in
                    DiscoveredDeviceRow(name: s.name, ip: s.ipAddress, icon: "externaldrive.badge.wifi") {
                        appState.addCloudStore(s)
                    }
                }
            }
        }
    }

    // MARK: - Empty state
    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "network").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("No Devices Added").font(.title3).bold()
            Text("Scan the network or add a HyperDeck, ATEM Switcher, or Cloud Store.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Scan Network") { discovery.startScanning() }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding()
    }

    // MARK: - Action bar
    private var actionBar: some View {
        HStack(spacing: 16) {
            // Last run summary
            if let last = appState.workflowRunHistory.first, !appState.isRunning {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last run: \(last.workflowName) · \(last.finishedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("\(last.processed) processed · \(last.durationFormatted)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.leading)
            }

            Spacer()

            // Retry button — visible after a run with errors
            if !appState.isRunning && !appState.failedTasks.isEmpty {
                Button {
                    Task { await workflowEngine.retryFailed() }
                } label: {
                    Label("Retry \(appState.failedTasks.count) Failed", systemImage: "arrow.counterclockwise")
                        .padding(.horizontal, 16).padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }

            if appState.isRunning {
                Button(role: .destructive) {
                    workflowEngine.stop()
                } label: {
                    Label("Stop Workflow", systemImage: "stop.fill")
                        .padding(.horizontal, 28).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent).tint(.red)
            } else {
                runWorkflowMenu
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Run Workflow menu
    // The primary dashboard action: pick any user-defined workflow and run
    // it against its configured target devices. No workflow is baked in —
    // if none exist yet, this points the user to the Workflows tab instead.
    @ViewBuilder private var runWorkflowMenu: some View {
        let runnable = appState.workflows.filter { !$0.steps.isEmpty }

        if runnable.isEmpty {
            Label("No workflows yet — create one in Workflows", systemImage: "flowchart")
                .font(.subheadline).foregroundStyle(.secondary)
        } else {
            Menu {
                ForEach(runnable.sorted { $0.sortOrder < $1.sortOrder }) { workflow in
                    Button(workflow.name) {
                        Task { await workflowEngine.run(workflow) }
                    }
                }
            } label: {
                Label("Run Workflow", systemImage: "play.fill")
                    .padding(.horizontal, 28).padding(.vertical, 8)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .buttonStyle(.borderedProminent)
        }
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
