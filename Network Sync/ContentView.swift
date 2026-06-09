import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selection: NavItem? = .dashboard

    enum NavItem: String, Hashable, CaseIterable {
        case dashboard = "Dashboard"
        case devices   = "HyperDecks"
        case settings  = "Settings"

        var icon: String {
            switch self {
            case .dashboard: return "play.tv"
            case .devices:   return "server.rack"
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
        } detail: {
            switch selection {
            case .dashboard, .none: DashboardView()
            case .devices:          DevicesView()
            case .settings:         SettingsView()
            }
        }
    }
}
