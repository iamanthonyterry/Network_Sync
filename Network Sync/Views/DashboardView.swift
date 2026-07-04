import SwiftUI

// MARK: - DashboardView
// Home base: shows every configured device (HyperDecks, ATEM Switchers,
// Cloud Stores) plus anything found on the network, all in one place.
// Add, edit, and delete devices here; run a workflow against a single
// HyperDeck right from its card via "Run Workflow".

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var pipeline = PipelineEngine.shared
    @StateObject private var discovery = DeviceDiscovery()
    @ObservedObject private var monitor = ConnectionMonitor.shared

    @State private var showingAddDeck = false
    @State private var showingAddSwitcher = false
    @State private var showingAddCloudStore = false

    var activeCount: Int  { appState.activeTasks.filter { $0.phase == .downloading || $0.phase == .converting }.count }
    var doneCount: Int    { appState.activeTasks.filter { $0.phase == .done }.count }
    var errorCount: Int   { appState.activeTasks.filter { $0.phase == .error }.count }

    var totalDevices: Int  { appState.hyperDecks.count + appState.switchers.count + appState.cloudStores.count }
    var hasDecks: Bool     { !appState.hyperDecks.isEmpty }

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
                deviceGrid
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
            Button {
                Task { await pipeline.runAll() }
            } label: {
                Label("Retry", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
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

    // MARK: - Device Grid
    private var deviceGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !appState.hyperDecks.isEmpty {
                    sectionHeader("HyperDecks")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 270))], spacing: 16) {
                        ForEach(appState.hyperDecks) { deck in
                            DeckCardView(deck: deck)
                        }
                    }
                }

                if !appState.switchers.isEmpty {
                    sectionHeader("ATEM Switchers")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 270))], spacing: 16) {
                        ForEach(appState.switchers) { switcher in
                            SwitcherCardView(switcher: switcher)
                        }
                    }
                }

                if !appState.cloudStores.isEmpty {
                    sectionHeader("Cloud Stores")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 270))], spacing: 16) {
                        ForEach(appState.cloudStores) { store in
                            CloudStoreCardView(store: store)
                        }
                    }
                }

                discoveredSection
            }
            .padding()
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.headline).foregroundStyle(.secondary)
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
            sectionHeader("Discovered on Network")
            VStack(spacing: 8) {
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
