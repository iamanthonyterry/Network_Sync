import SwiftUI
import Network

struct DevicesView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var discovery = DeviceDiscovery()

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
                    DeckRow(deck: deck)
                        .contextMenu {
                            Button("Edit…") { editingDeck = deck }
                        }
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
                    SwitcherRow(switcher: switcher)
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
                    CloudStoreRow(store: store)
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
    @State private var status: DeckStatus = .unknown
    @StateObject private var hyperDeck: HyperDeckService
    @State private var showFormatConfirm = false

    init(deck: HyperDeck) {
        self.deck = deck
        _hyperDeck = StateObject(wrappedValue: HyperDeckService(host: deck.ipAddress))
    }

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
        .task { await ping(host: deck.ipAddress, port: 9993) }
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

    private func ping(host: String, port: UInt16) async {
        guard let port = NWEndpoint.Port(rawValue: port) else { return }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        conn.start(queue: .global())
        status = await resolveConnectionStatus(conn)
    }
}

// MARK: - HyperDeck Controls

struct HyperDeckControls: View {
    @ObservedObject var hyperDeck: HyperDeckService
    @Binding var showFormatConfirm: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Record
            Button {
                Task { await hyperDeck.record() }
            } label: {
                Label("Record", systemImage: "record.circle")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(hyperDeck.isBusy || hyperDeck.transport == .recording)

            // Stop
            Button {
                Task { await hyperDeck.stop() }
            } label: {
                Label("Stop", systemImage: "stop.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(hyperDeck.isBusy || hyperDeck.transport == .stopped)

            Spacer()

            // Format (destructive, separated)
            Button {
                showFormatConfirm = true
            } label: {
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
        .task { await hyperDeck.fetchTransport() }
    }
}

// MARK: - Switcher Row

struct SwitcherRow: View {
    let switcher: BlackmagicSwitcher
    @State private var status: DeckStatus = .unknown

    var body: some View {
        DeviceRow(
            name: switcher.name,
            detail: "\(switcher.ipAddress)\(switcher.model.isEmpty ? "" : " · \(switcher.model)")",
            icon: "switch.2",
            status: status
        )
        .task { await ping() }
    }

    private func ping() async {
        guard let port = NWEndpoint.Port(rawValue: BlackmagicSwitcher.controlPort) else { return }
        let conn = NWConnection(host: NWEndpoint.Host(switcher.ipAddress), port: port, using: .tcp)
        conn.start(queue: .global())
        status = await resolveConnectionStatus(conn)
    }
}

// MARK: - Cloud Store Row

struct CloudStoreRow: View {
    let store: CloudStore
    @State private var status: DeckStatus = .unknown

    var body: some View {
        DeviceRow(
            name: store.name,
            detail: "\(store.ipAddress)\(store.volumeName.isEmpty ? "" : " · \(store.volumeName)")",
            icon: "externaldrive.badge.wifi",
            status: status
        )
        .task { await ping() }
    }

    private func ping() async {
        // Cloud Store serves via SMB port 445
        guard let port = NWEndpoint.Port(rawValue: UInt16(445)) else { return }
        let conn = NWConnection(host: NWEndpoint.Host(store.ipAddress), port: port, using: .tcp)
        conn.start(queue: .global())
        status = await resolveConnectionStatus(conn)
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
