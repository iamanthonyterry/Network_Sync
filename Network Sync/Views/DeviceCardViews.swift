import SwiftUI

// MARK: - Status Badge

struct StatusBadge: View {
    let status: DeckStatus

    var body: some View {
        let color: Color = switch status {
            case .online: .green
            case .offline: .red
            case .unauthorized: .orange
            default: .gray
        }
        let label: String = switch status {
            case .online: "Online"
            case .offline: "Offline"
            case .unauthorized: "Login Failed"
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

// MARK: - ATEM Switcher Card

struct SwitcherCardView: View {
    let switcher: BlackmagicSwitcher
    @EnvironmentObject var appState: AppState
    @ObservedObject private var monitor = ConnectionMonitor.shared
    @State private var isShowingEdit = false

    private var status: DeckStatus { monitor.status(for: switcher.ipAddress) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(switcher.name).font(.headline)
                    Text(switcher.ipAddress).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(status: status)
            }

            if !switcher.model.isEmpty {
                Text(switcher.model).font(.caption).italic().foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button {
                    Task { await monitor.pingNow(switcher: switcher) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }.buttonStyle(.borderless)

                Button {
                    isShowingEdit = true
                } label: {
                    Image(systemName: "pencil")
                }.buttonStyle(.borderless)

                Button(role: .destructive) {
                    appState.deleteSwitcher(id: switcher.id)
                } label: {
                    Image(systemName: "trash")
                }.buttonStyle(.borderless)

                Spacer()
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .sheet(isPresented: $isShowingEdit) {
            SwitcherEditSheet(switcher: switcher)
        }
    }
}

// MARK: - Cloud Store Card

struct CloudStoreCardView: View {
    let store: CloudStore
    @EnvironmentObject var appState: AppState
    @ObservedObject private var monitor = ConnectionMonitor.shared
    @State private var isShowingEdit = false

    private var status: DeckStatus { monitor.status(for: store.ipAddress) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.name).font(.headline)
                    Text(store.ipAddress).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(status: status)
            }

            if !store.volumeName.isEmpty {
                Text(store.volumeName).font(.caption).italic().foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button {
                    Task { await monitor.pingNow(store: store) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }.buttonStyle(.borderless)

                Button {
                    isShowingEdit = true
                } label: {
                    Image(systemName: "pencil")
                }.buttonStyle(.borderless)

                Button(role: .destructive) {
                    appState.deleteCloudStore(id: store.id)
                } label: {
                    Image(systemName: "trash")
                }.buttonStyle(.borderless)

                Spacer()
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .sheet(isPresented: $isShowingEdit) {
            CloudStoreEditSheet(store: store)
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
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
