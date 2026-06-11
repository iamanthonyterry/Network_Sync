import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selection: NavItem? = .dashboard

    enum NavItem: String, Hashable, CaseIterable {
        case dashboard = "Dashboard"
        case devices   = "HyperDecks"
        case history   = "History"
        case settings  = "Settings"

        var icon: String {
            switch self {
            case .dashboard: return "play.tv"
            case .devices:   return "server.rack"
            case .history:   return "clock.arrow.circlepath"
            case .settings:  return "gearshape"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(NavItem.allCases, id: \.self, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.icon)
            }
            .listStyle(.sidebar)
            .navigationTitle("Network Sync")

            // Schedule status badge at bottom of sidebar
            if appState.scheduleSettings.isEnabled {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text("Scheduled \(appState.scheduleSettings.displayTime)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        } detail: {
            switch selection {
            case .dashboard, .none: DashboardView()
            case .devices:          DevicesView()
            case .history:          HistoryView()
            case .settings:         SettingsView()
            }
        }
    }
}
