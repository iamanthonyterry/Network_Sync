import SwiftUI
import Network
import Combine

// MARK: - Status Cache
// Holds ping results in a stable @StateObject so device rows never
// flicker back to "Checking…" when the parent view re-renders.
@MainActor
final class DeviceStatusCache: ObservableObject {
    @Published private var cache: [String: DeckStatus] = [:]

    func status(for key: String) -> DeckStatus { cache[key] ?? .unknown }

    func ping(host: String, port: UInt16) async {
        // Skip if we already have a result — avoids redundant TCP probes.
        if let existing = cache[host], existing != .unknown { return }
        cache[host] = .unknown

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            cache[host] = .offline; return
        }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        conn.start(queue: .global())
        cache[host] = await resolveConnectionStatus(conn)
    }

    func refresh(host: String, port: UInt16) async {
        cache[host] = .unknown
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            cache[host] = .offline; return
        }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        conn.start(queue: .global())
        cache[host] = await resolveConnectionStatus(conn)
    }
}

// MARK: - DevicesView

struct DevicesView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var discovery = DeviceDiscovery()
    @StateObject private var statusCache = DeviceStatusCache()

    @State private var showingAddDeck = false
    @State private var showingAddSwitcher = false
    @State private var showingAddCloudStore = false
    @State private var editingDeck: HyperDeck?
    @State private var editingSwitcher: BlackmagicSwitcher?
    @State private var editingCloudStore: CloudStore?

    private var totalDevices: Int {
        appState.hyperDecks.count + appState.switchers.count + appState.cloudStores.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Devices").font(.title2).bold()
                Text("\(totalDevices) total")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                scanButton
                Menu {
                    Button("HyperDeck") { showingAddDeck = true }
                    Button("ATEM Switcher") { showingAddSwitcher = true }
                    Button("Cloud Store") { showingAddCloudStore = true }
                } label: {
                    Label("Add Device", systemImage: "plus")
                }.buttonStyle(.borderedProminent)
            }
            .padding()
            Divider()

            if totalDevices == 0 && discovery.discoveredDecks.isEmpty
                && discovery.discoveredSwitchers.isEmpty && discovery.discoveredCloudStores.isEmpty {
                emptyState
            } else {
                List {
                    hyperDeckSection
                    switcherSection
                    cloudStoreSection
                    discoveredSection
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $showingAddDeck) { DeckEditSheet(deck: nil) }
        .sheet(isPresented: $showingAddSwitcher) { SwitcherEditSheet(switcher: nil) }
        .sheet(isPresented: $showingAddCloudStore) { CloudStoreEditSheet(store: nil) }
        .sheet(item: $editingDeck) { DeckEditSheet(deck: $0) }
        .sheet(item: $editingSwitcher) { SwitcherEditSheet(switcher: $0) }
        .sheet(item: $editingCloudStore) { CloudStoreEditSheet(store: $0) }
        .task { await pingAllDevices() }
        .onChange(of: appState.hyperDecks)  { Task { await pingAllDevices() } }
        .onChange(of: appState.switchers)   { Task { await pingAllDevices() } }
        .onChange(of: appState.cloudStores) { Task { await pingAllDevices() } }
    }

    // MARK: - Ping All

    private func pingAllDevices() async {
        async let _ = withTaskGroup(of: Void.self) { group in
            for deck in appState.hyperDecks {
                group.addTask { await statusCache.ping(host: deck.ipAddress, port: 9993) }
            }
            for switcher in appState.switchers {
                group.addTask { await statusCache.ping(host: switcher.ipAddress, port: BlackmagicSwitcher.controlPort) }
            }
            for store in appState.cloudStores {
                group.addTask { await statusCache.ping(host: store.ipAddress, port: 445) }
            }
        }
    }

    // MARK: - Subviews

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

    @ViewBuilder private var hyperDeckSection: some View {
        if !appState.hyperDecks.isEmpty {
            Section("HyperDecks") {
                ForEach(appState.hyperDecks) { deck in
                    DeckRow(deck: deck, statusCache: statusCache)
                        .contextMenu { Button("Edit…") { editingDeck = deck } }
                }
                .onMove { appState.moveDeck(from: $0, to: $1) }
                .onDelete { offsets in
                    offsets.forEach { appState.deleteDeck(id: appState.hyperDecks[$0].id) }
                }
            }
        }
    }

    @ViewBuilder private var switcherSection: some View {
        if !appState.switchers.isEmpty {
            Section("ATEM Switchers") {
                ForEach(appState.switchers) { switcher in
                    SwitcherRow(switcher: switcher, statusCache: statusCache)
                        .contentShape(Rectangle())
                        .onTapGesture { editingSwitcher = switcher }
                }
                .onMove { appState.moveSwitcher(from: $0, to: $1) }
                .onDelete { offsets in
                    offsets.forEach { appState.deleteSwitcher(id: appState.switchers[$0].id) }
                }
            }
        }
    }

    @ViewBuilder private var cloudStoreSection: some View {
        if !appState.cloudStores.isEmpty {
            Section("Cloud Stores") {
                ForEach(appState.cloudStores) { store in
                    CloudStoreRow(store: store, statusCache: statusCache)
                        .contentShape(Rectangle())
                        .onTapGesture { editingCloudStore = store }
                }
                .onMove { appState.moveCloudStore(from: $0, to: $1) }
                .onDelete { offsets in
                    offsets.forEach { appState.deleteCloudStore(id: appState.cloudStores[$0].id) }
                }
            }
        }
    }

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

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "network").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("No Devices Added").font(.title3).bold()
            Text("Scan the network or add devices manually.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Scan Network") { discovery.startScanning() }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding()
    }
}

// MARK: - HyperDeck Row

struct DeckRow: View {
    let deck: HyperDeck
    let statusCache: DeviceStatusCache
    @StateObject private var hyperDeck: HyperDeckService
    @State private var showFormatConfirm = false

    init(deck: HyperDeck, statusCache: DeviceStatusCache) {
        self.deck = deck
        self.statusCache = statusCache
        _hyperDeck = StateObject(wrappedValue: HyperDeckService(host: deck.ipAddress))
    }

    private var status: DeckStatus { statusCache.status(for: deck.ipAddress) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DeviceRow(
                name: deck.name,
                detail: "\(deck.ipAddress) · \(deck.remotePath)",
                icon: "server.rack",
                status: status
            )

            if status == .online {
                HyperDeckControls(
                    hyperDeck: hyperDeck,
                    showFormatConfirm: $showFormatConfirm
                )
                .padding(.leading, 40)
            }
        }
        .padding(.vertical, 4)
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
    }
}

// MARK: - HyperDeck Controls

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
        .onAppear { hyperDeck.startPolling() }
        .onDisappear { hyperDeck.stopPolling() }
    }
}

// MARK: - Switcher Row

struct SwitcherRow: View {
    let switcher: BlackmagicSwitcher
    let statusCache: DeviceStatusCache

    var body: some View {
        DeviceRow(
            name: switcher.name,
            detail: "\(switcher.ipAddress)\(switcher.model.isEmpty ? "" : " · \(switcher.model)")",
            icon: "switch.2",
            status: statusCache.status(for: switcher.ipAddress)
        )
    }
}

// MARK: - Cloud Store Row

struct CloudStoreRow: View {
    let store: CloudStore
    let statusCache: DeviceStatusCache

    var body: some View {
        DeviceRow(
            name: store.name,
            detail: "\(store.ipAddress)\(store.volumeName.isEmpty ? "" : " · \(store.volumeName)")",
            icon: "externaldrive.badge.wifi",
            status: statusCache.status(for: store.ipAddress)
        )
    }
}

// resolveConnectionStatus(_:) is defined in DeckCardView.swift

// MARK: - Shared Device Row

struct DeviceRow: View {
    let name: String
    let detail: String
    let icon: String
    let status: DeckStatus

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(status: status)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: DeckStatus

    var body: some View {
        let color: Color = switch status {
            case .online: .green
            case .offline: .red
            default: .gray
        }
        let label: String = switch status {
            case .online: "Online"
            case .offline: "Offline"
            default: "Checking…"
        }

        Text(label)
            .font(.caption).bold()
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Discovered Device Row

struct DiscoveredDeviceRow: View {
    let name: String
    let ip: String
    let icon: String
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3).foregroundStyle(.secondary).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline)
                Text(ip).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Add") { onAdd() }.buttonStyle(.bordered).controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}
