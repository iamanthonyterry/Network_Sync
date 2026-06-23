import SwiftUI
import Network

struct SwitcherEditSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let existingSwitcher: BlackmagicSwitcher?

    @State private var name      = ""
    @State private var ipAddress = ""
    @State private var model     = ""
    @State private var pingStatus: DeckStatus = .unknown
    @State private var isTesting = false

    init(switcher: BlackmagicSwitcher?) {
        existingSwitcher = switcher
        _name      = State(initialValue: switcher?.name      ?? "")
        _ipAddress = State(initialValue: switcher?.ipAddress ?? "")
        _model     = State(initialValue: switcher?.model     ?? "")
    }

    var canSave: Bool { !name.isEmpty && !ipAddress.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(existingSwitcher == nil ? "Add ATEM Switcher" : "Edit ATEM Switcher")
                    .font(.title2).bold()
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(existingSwitcher == nil ? "Add" : "Save") { save() }
                    .buttonStyle(.borderedProminent).disabled(!canSave)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
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
        }
        .frame(width: 440)
    }

    private func save() {
        if var s = existingSwitcher {
            s.name = name; s.ipAddress = ipAddress; s.model = model
            appState.updateSwitcher(s)
        } else {
            appState.addSwitcher(BlackmagicSwitcher(name: name, ipAddress: ipAddress, model: model))
        }
        dismiss()
    }

    private func testConnection() {
        isTesting = true; pingStatus = .unknown
        Task {
            guard let port = NWEndpoint.Port(rawValue: BlackmagicSwitcher.controlPort) else {
                isTesting = false; return
            }
            let conn = NWConnection(host: NWEndpoint.Host(ipAddress), port: port, using: .tcp)
            conn.start(queue: .global())
            pingStatus = await resolveConnectionStatus(conn)
            isTesting = false
        }
    }
}
