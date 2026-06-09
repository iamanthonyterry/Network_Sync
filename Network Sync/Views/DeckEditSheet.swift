import SwiftUI
import Network

struct DeckEditSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let existingDeck: HyperDeck?

    @State private var name       = ""
    @State private var ipAddress  = ""
    @State private var remotePath = "usb/Extreme Pro"
    @State private var username   = "lpproduction"
    @State private var password   = "7404"
    @State private var pingStatus: DeckStatus = .unknown
    @State private var isTesting  = false

    init(deck: HyperDeck?) {
        existingDeck = deck
        _name       = State(initialValue: deck?.name       ?? "")
        _ipAddress  = State(initialValue: deck?.ipAddress  ?? "")
        _remotePath = State(initialValue: deck?.remotePath ?? "usb/Extreme Pro")
        _username   = State(initialValue: deck?.username   ?? "lpproduction")
        _password   = State(initialValue: deck?.password   ?? "7404")
    }

    var canSave: Bool { !name.isEmpty && !ipAddress.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
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
                Section("Device Info") {
                    LabeledContent("Name") {
                        TextField("e.g. ISO 1", text: $name).textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("IP Address") {
                        TextField("192.168.2.138", text: $ipAddress).textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Remote Path") {
                        TextField("usb/Extreme Pro", text: $remotePath).textFieldStyle(.roundedBorder)
                    }
                }
                Section("Credentials") {
                    LabeledContent("Username") {
                        TextField("lpproduction", text: $username).textFieldStyle(.roundedBorder)
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
                                Text("Testing...")
                            } else {
                                Label("Test Connection", systemImage: "network")
                            }
                        }.disabled(ipAddress.isEmpty || isTesting)
                        Spacer()
                        if pingStatus != .unknown {
                            Label(
                                pingStatus == .online ? "Connected" : "No Response",
                                systemImage: pingStatus == .online ? "checkmark.circle.fill" : "xmark.circle.fill"
                            ).foregroundStyle(pingStatus == .online ? .green : .red)
                             .font(.subheadline)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 440)
    }

    private func save() {
        if var d = existingDeck {
            d.name = name; d.ipAddress = ipAddress
            d.remotePath = remotePath; d.username = username; d.password = password
            appState.updateDeck(d)
        } else {
            appState.addDeck(HyperDeck(name: name, ipAddress: ipAddress,
                                       remotePath: remotePath, username: username, password: password))
        }
        dismiss()
    }

    private func testConnection() {
        isTesting = true; pingStatus = .unknown
        let conn = NWConnection(host: NWEndpoint.Host(ipAddress), port: 21, using: .tcp)
        conn.stateUpdateHandler = { state in
            DispatchQueue.main.async {
                switch state {
                case .ready:  pingStatus = .online;  isTesting = false; conn.cancel()
                case .failed: pingStatus = .offline; isTesting = false; conn.cancel()
                default: break
                }
            }
        }
        conn.start(queue: .global())
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if isTesting { pingStatus = .offline; isTesting = false }
        }
    }
}
