import SwiftUI
import Network

struct DeckEditSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let existingDeck: HyperDeck?

    @State private var name            = ""
    @State private var ipAddress       = ""
    @State private var remotePath      = ""
    @State private var username        = ""
    @State private var password        = ""
    @State private var cloudStoreID: UUID? = nil   // nil = global destination
    @State private var cloudStorePath  = ""
    @State private var showFolderPicker = false
    @State private var pingStatus: DeckStatus = .unknown
    @State private var isTesting       = false

    init(deck: HyperDeck?) {
        existingDeck = deck
        _name           = State(initialValue: deck?.name           ?? "")
        _ipAddress      = State(initialValue: deck?.ipAddress      ?? "")
        _remotePath     = State(initialValue: deck?.remotePath     ?? "")
        _username       = State(initialValue: deck?.username       ?? "")
        _password       = State(initialValue: deck?.password       ?? "")
        _cloudStoreID   = State(initialValue: deck?.cloudStoreID)
        _cloudStorePath = State(initialValue: deck?.cloudStorePath ?? "")
    }

    var canSave: Bool { !name.isEmpty && !ipAddress.isEmpty }

    private var selectedStore: CloudStore? {
        guard let id = cloudStoreID else { return nil }
        return appState.cloudStores.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Header
            HStack {
                Text(existingDeck == nil ? "Add HyperDeck" : "Edit HyperDeck")
                    .font(.title2).bold()
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(existingDeck == nil ? "Add" : "Save") { save() }
                    .buttonStyle(.borderedProminent).disabled(!canSave)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()

            Form {
                // MARK: Device Info
                Section("Device Info") {
                    LabeledContent("Name") {
                        TextField("e.g. ISO 1", text: $name).textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("IP Address") {
                        TextField("192.168.x.x", text: $ipAddress).textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Remote Path") {
                        TextField("usb/DriveName", text: $remotePath).textFieldStyle(.roundedBorder)
                    }
                }

                // MARK: Credentials
                Section("Credentials") {
                    LabeledContent("Username") {
                        TextField("Username", text: $username).textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Password") {
                        SecureField("Password", text: $password).textFieldStyle(.roundedBorder)
                    }
                }

                // MARK: Sync Destination
                Section("Sync Destination") {
                    LabeledContent("Cloud Store") {
                        Picker("", selection: $cloudStoreID) {
                            Text("Global Default").tag(Optional<UUID>.none)
                            if !appState.cloudStores.isEmpty {
                                Divider()
                                ForEach(appState.cloudStores) { store in
                                    Text(store.name).tag(Optional(store.id))
                                }
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                        .onChange(of: cloudStoreID) {
                            // Clear the path when the store changes
                            cloudStorePath = ""
                        }
                    }

                    // Folder row — only shown when a specific store is chosen
                    if let store = selectedStore {
                        LabeledContent("Folder") {
                            HStack(spacing: 8) {
                                // Path display / placeholder
                                Group {
                                    if cloudStorePath.isEmpty {
                                        Text("Volume root")
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text(cloudStorePath)
                                            .lineLimit(1)
                                            .truncationMode(.head)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .font(.callout)

                                // Clear button
                                if !cloudStorePath.isEmpty {
                                    Button {
                                        cloudStorePath = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }

                                // Browse button
                                Button {
                                    showFolderPicker = true
                                } label: {
                                    Label("Browse…", systemImage: "folder")
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        // Preview label
                        let folder = cloudStorePath.isEmpty ? "/" : "/\(cloudStorePath)"
                        Label("→ \(store.name)\(folder)",
                              systemImage: "externaldrive.connected.to.line.below")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Uses the global sync destination from Settings.",
                              systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: Test Connection
                Section {
                    HStack {
                        Button(action: testConnection) {
                            if isTesting {
                                ProgressView().controlSize(.small)
                                Text("Testing...")
                            } else {
                                Label("Test Connection", systemImage: "network")
                            }
                        }.disabled(ipAddress.isEmpty || isTesting)
                        Spacer()
                        if pingStatus != .unknown {
                            Label(
                                pingStatus == .online ? "Connected" : "No Response",
                                systemImage: pingStatus == .online
                                    ? "checkmark.circle.fill" : "xmark.circle.fill"
                            )
                            .foregroundStyle(pingStatus == .online ? .green : .red)
                            .font(.subheadline)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 480)
        .sheet(isPresented: $showFolderPicker) {
            if let store = selectedStore {
                FolderPickerSheet(store: store) { path in
                    cloudStorePath = path
                }
                .environmentObject(appState)
            }
        }
    }

    // MARK: - Save
    private func save() {
        if var d = existingDeck {
            d.name = name; d.ipAddress = ipAddress
            d.remotePath = remotePath; d.username = username; d.password = password
            d.cloudStoreID = cloudStoreID; d.cloudStorePath = cloudStorePath
            appState.updateDeck(d)
        } else {
            appState.addDeck(HyperDeck(
                name: name, ipAddress: ipAddress, remotePath: remotePath,
                username: username, password: password,
                cloudStoreID: cloudStoreID, cloudStorePath: cloudStorePath
            ))
        }
        dismiss()
    }

    // MARK: - Test
    private func testConnection() {
        isTesting = true; pingStatus = .unknown
        Task {
            guard let port = NWEndpoint.Port(rawValue: UInt16(21)) else {
                isTesting = false; return
            }
            let conn = NWConnection(host: NWEndpoint.Host(ipAddress), port: port, using: .tcp)
            conn.start(queue: .global())
            pingStatus = await resolveConnectionStatus(conn)
            isTesting = false
        }
    }
}
