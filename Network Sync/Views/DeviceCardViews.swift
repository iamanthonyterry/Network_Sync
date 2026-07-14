import SwiftUI
import Network

// MARK: - Status Badge

struct StatusBadge: View {
    let status: DeckStatus

    var body: some View {
        let color: Color = switch status {
            case .online: .green
            case .offline: .red
            case .unauthorized: .orange
            case .pathNotFound: .orange
            case .noMedia: .red
            case .syncing: .blue
            case .transcoding: .orange
            case .unknown: .gray
        }
        let label: String = switch status {
            case .online: "Online"
            case .offline: "Offline"
            case .unauthorized: "Login Failed"
            case .pathNotFound: "Wrong Path"
            case .noMedia: "No Drive"
            case .syncing: "Syncing"
            case .transcoding: "Converting"
            case .unknown: "Checking…"
        }

        Text(label)
            .font(.caption).bold()
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - ATEM Switcher Detail Pane
// The right-hand settings view for a selected switcher: editable fields,
// a connection test, and device actions (refresh / delete).

struct SwitcherDetailPane: View {
    let switcher: BlackmagicSwitcher
    @EnvironmentObject var appState: AppState
    @ObservedObject private var monitor = ConnectionMonitor.shared

    @State private var name: String
    @State private var ipAddress: String
    @State private var model: String
    @State private var pingStatus: DeckStatus = .unknown
    @State private var isTesting = false
    @State private var showDeleteConfirm = false

    init(switcher: BlackmagicSwitcher) {
        self.switcher = switcher
        _name      = State(initialValue: switcher.name)
        _ipAddress = State(initialValue: switcher.ipAddress)
        _model     = State(initialValue: switcher.model)
    }

    private var liveStatus: DeckStatus { monitor.status(for: switcher.ipAddress) }
    private var isDirty: Bool {
        name != switcher.name || ipAddress != switcher.ipAddress || model != switcher.model
    }
    private var canSave: Bool { !name.isEmpty && !ipAddress.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Form {
                Section("Device Info") {
                    LabeledContent("Name") {
                        TextField("e.g. Main ATEM", text: $name).textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("IP Address") {
                        TextField("192.168.x.x", text: $ipAddress).textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Model") {
                        TextField("e.g. ATEM Mini Pro", text: $model).textFieldStyle(.roundedBorder)
                    }
                }

                Section {
                    HStack {
                        Button(action: testConnection) {
                            if isTesting {
                                ProgressView().controlSize(.small)
                                Text("Testing…")
                            } else {
                                Label("Test Connection", systemImage: "network")
                            }
                        }.disabled(ipAddress.isEmpty || isTesting)
                        Spacer()
                        if pingStatus != .unknown {
                            Label(
                                pingStatus == .online ? "Connected" : "No Response",
                                systemImage: pingStatus == .online ? "checkmark.circle.fill" : "xmark.circle.fill"
                            )
                            .foregroundStyle(pingStatus == .online ? .green : .red)
                            .font(.subheadline)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            footer
        }
        .confirmationDialog(
            "Delete \(switcher.name)?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { appState.deleteSwitcher(id: switcher.id) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(switcher.name).font(.title3).bold()
                Text(switcher.ipAddress).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(status: liveStatus)
            Button {
                Task { await monitor.pingNow(switcher: switcher) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label("Delete Device", systemImage: "trash")
            }
            Spacer()
            Button("Save Changes") { save() }
                .buttonStyle(.borderedProminent)
                .disabled(!isDirty || !canSave)
        }
        .padding()
    }

    private func save() {
        var s = switcher
        s.name = name; s.ipAddress = ipAddress; s.model = model
        appState.updateSwitcher(s)
    }

    private func testConnection() {
        isTesting = true; pingStatus = .unknown
        Task {
            pingStatus = await ATEMProbe.ping(host: ipAddress)
            isTesting = false
        }
    }
}

// MARK: - Cloud Store Detail Pane
// The right-hand settings view for a selected cloud store: editable
// fields, a browse-for-volume shortcut, an SMB test/mount, and actions.

struct CloudStoreDetailPane: View {
    let store: CloudStore
    @EnvironmentObject var appState: AppState
    @ObservedObject private var monitor = ConnectionMonitor.shared

    @State private var name: String
    @State private var ipAddress: String
    @State private var volumeName: String
    @State private var username: String
    @State private var password: String
    @State private var pingStatus: DeckStatus = .unknown
    @State private var isTesting = false
    @State private var mountResult: String? = nil
    @State private var showVolumePicker = false
    @State private var showDeleteConfirm = false

    init(store: CloudStore) {
        self.store = store
        _name       = State(initialValue: store.name)
        _ipAddress  = State(initialValue: store.ipAddress)
        _volumeName = State(initialValue: store.volumeName)
        _username   = State(initialValue: store.username)
        _password   = State(initialValue: store.password)
    }

    private var liveStatus: DeckStatus { monitor.status(for: store.ipAddress) }
    private var isDirty: Bool {
        name != store.name || ipAddress != store.ipAddress || volumeName != store.volumeName
            || username != store.username || password != store.password
    }
    private var canSave: Bool { !name.isEmpty && !ipAddress.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Form {
                Section("Device Info") {
                    LabeledContent("Name") {
                        TextField("e.g. Cloud Store 1", text: $name).textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("IP Address") {
                        TextField("192.168.x.x", text: $ipAddress).textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Volume Name") {
                        HStack(spacing: 8) {
                            TextField("e.g. CloudStore", text: $volumeName)
                                .textFieldStyle(.roundedBorder)
                            Button {
                                showVolumePicker = true
                            } label: {
                                Label("Browse…", systemImage: "externaldrive")
                            }
                            .buttonStyle(.bordered)
                            .disabled(ipAddress.isEmpty)
                        }
                    }
                }
                Section("Credentials") {
                    LabeledContent("Username") {
                        TextField("Username", text: $username).textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Password") {
                        SecureField("Password", text: $password).textFieldStyle(.roundedBorder)
                    }
                }
                Section {
                    HStack {
                        Button(action: testConnection) {
                            if isTesting {
                                ProgressView().controlSize(.small)
                                Text("Testing…")
                            } else {
                                Label("Test & Mount", systemImage: "network")
                            }
                        }.disabled(ipAddress.isEmpty || isTesting)
                        Spacer()
                        if let result = mountResult {
                            Text(result)
                                .font(.subheadline)
                                .foregroundStyle(result.hasPrefix("✅") ? .green : .red)
                        } else if pingStatus != .unknown {
                            Label(
                                pingStatus == .online ? "Reachable" : "No Response",
                                systemImage: pingStatus == .online ? "checkmark.circle.fill" : "xmark.circle.fill"
                            )
                            .foregroundStyle(pingStatus == .online ? .green : .red)
                            .font(.subheadline)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            footer
        }
        .sheet(isPresented: $showVolumePicker) {
            CloudStoreVolumePickerSheet(ipAddress: ipAddress, username: username, password: password) { share in
                volumeName = share
            }
        }
        .confirmationDialog(
            "Delete \(store.name)?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { appState.deleteCloudStore(id: store.id) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(store.name).font(.title3).bold()
                Text(store.ipAddress).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(status: liveStatus)
            Button {
                Task { await monitor.pingNow(store: store) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label("Delete Device", systemImage: "trash")
            }
            Spacer()
            Button("Save Changes") { save() }
                .buttonStyle(.borderedProminent)
                .disabled(!isDirty || !canSave)
        }
        .padding()
    }

    private func save() {
        var s = store
        s.name = name; s.ipAddress = ipAddress
        s.volumeName = volumeName; s.username = username; s.password = password
        appState.updateCloudStore(s)
    }

    private func testConnection() {
        isTesting = true
        pingStatus = .unknown
        mountResult = nil

        Task {
            guard let port = NWEndpoint.Port(rawValue: UInt16(445)) else {
                isTesting = false; return
            }
            let conn = NWConnection(host: NWEndpoint.Host(ipAddress), port: port, using: .tcp)
            conn.start(queue: .global())
            pingStatus = await resolveConnectionStatus(conn)

            guard pingStatus == .online else {
                isTesting = false; return
            }

            do {
                let mountPath = try await SMBService.mountAndResolve(
                    ip: ipAddress, volume: volumeName,
                    username: username, password: password
                )
                mountResult = "✅ Mounted at \(mountPath)"
            } catch {
                mountResult = "❌ \(error.localizedDescription)"
            }
            isTesting = false
        }
    }
}

// MARK: - Discovered Device Row
// Shown in a lightweight list style rather than a card, since these are
// transient, one-tap-to-add entries rather than configured devices.

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

