import SwiftUI

struct ContentView: View {
    // Persistent or AppStorage values replacing the hardcoded script constants
    @AppStorage("cloudStoreIP") private var cloudStoreIP = "192.168.2.119"
    @AppStorage("maxParallelConversions") private var maxParallelConversions = 2
    
    @State private var isRunning = false
    @State private var currentStatus = "Idle"
    @State private var totalProgress: Double = 0.0

    var body: some View {
        NavigationSplitView {
            List {
                NavigationLink(destination: DashboardView(isRunning: $isRunning, status: $currentStatus, progress: $totalProgress)) {
                    Label("Dashboard", systemImage: "play.tv")
                }
                NavigationLink(destination: HyperDeckConfigView()) {
                    Label("HyperDecks", systemImage: "server.rack")
                }
                NavigationLink(destination: SettingsView()) {
                    Label("Settings & Email", systemImage: "gearshape")
                }
            }
            .listStyle(SidebarListStyle())
        } detail: {
            Text("Select an option from the sidebar")
        }
        .frame(minWidth: 800, minHeight: 500)
    }
}
