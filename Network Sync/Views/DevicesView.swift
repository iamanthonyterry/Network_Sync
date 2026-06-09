import SwiftUI
import Network

struct DevicesView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingAdd = false
    @State private var editingDeck: HyperDeck?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("HyperDecks").font(.title2).bold()
                Text("\(appState.hyperDecks.count) devices")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button { showingAdd = true } label: {
                    Label("Add Device", systemImage: "plus")
                }.buttonStyle(.borderedProminent)
            }
            .padding()
            Divider()

            if appState.hyperDecks.isEmpty {
                VStack(spacing: 14) {
                    Spacer()
                    Image(systemName: "server.rack").font(.system(size: 48)).foregroundStyle(.secondary)
                    Text("No HyperDecks Added").font(.title3).bold()
                    Text("Add your first HyperDeck to get started.").foregroundStyle(.secondary)
                    Button("Add HyperDeck") { showingAdd = true }.buttonStyle(.borderedProminent)
                    Spacer()
                }
            } else {
                List {
                    ForEach(appState.hyperDecks) { deck in
                        DeckRow(deck: deck)
                            .contentShape(Rectangle())
                            .onTapGesture { editingDeck = deck }
                    }
                    .onMove { appState.moveDeck(from: $0, to: $1) }
                    .onDelete { appState.deleteDeck(id: appState.hyperDecks[$0.first!].id) }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $showingAdd) { DeckEditSheet(deck: nil) }
        .sheet(item: $editingDeck) { DeckEditSheet(deck: $0) }
    }
}

// MARK: - Deck Row
struct DeckRow: View {
    let deck: HyperDeck
    @State private var status: DeckStatus = .unknown

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(statusColor).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(deck.name).font(.headline)
                HStack(spacing: 6) {
                    Text(deck.ipAddress)
                    Text("·")
                    Text(deck.remotePath)
                }.font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(status == .unknown ? "Checking..." : status == .online ? "Online" : "Offline")
                .font(.caption).bold()
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(statusColor.opacity(0.15))
                .foregroundStyle(statusColor)
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
        .onAppear { ping() }
    }

    private var statusColor: Color {
        switch status {
        case .unknown: return .gray
        case .online: return .green
        default: return .red
        }
    }

    private func ping() {
        let conn = NWConnection(host: NWEndpoint.Host(deck.ipAddress), port: 21, using: .tcp)
        conn.stateUpdateHandler = { s in
            DispatchQueue.main.async {
                switch s {
                case .ready:  status = .online;  conn.cancel()
                case .failed: status = .offline; conn.cancel()
                default: break
                }
            }
        }
        conn.start(queue: .global())
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if status == .unknown { status = .offline }
        }
    }
}
