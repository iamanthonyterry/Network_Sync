import Foundation
import Network
import Combine

/// Continuously polls every added device's reachability *and* login/
/// permission status, so status badges stay live and automatically recover
/// when a device drops, reconnects, or has its credentials fixed.
/// One instance for the whole app — start it once at launch.
@MainActor
final class ConnectionMonitor: ObservableObject {
    static let shared = ConnectionMonitor()

    @Published private(set) var statuses: [String: DeckStatus] = [:]

    private var monitorTask: Task<Void, Never>?
    private let pollInterval: Duration = .seconds(5)

    func status(for host: String) -> DeckStatus {
        statuses[host] ?? .unknown
    }

    /// Starts the continuous polling loop. Safe to call more than once.
    func start() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollAllDevices()
                try? await Task.sleep(for: self?.pollInterval ?? .seconds(5))
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    /// Forces an immediate re-check of a HyperDeck, including its login,
    /// e.g. from a manual "Refresh" button, without waiting for the next
    /// poll cycle.
    func pingNow(deck: HyperDeck) async {
        statuses[deck.ipAddress] = await Self.checkDeck(deck)
    }

    func pingNow(store: CloudStore) async {
        statuses[store.ipAddress] = await Self.checkCloudStore(store)
    }

    func pingNow(switcher: BlackmagicSwitcher) async {
        statuses[switcher.ipAddress] = await Self.ping(host: switcher.ipAddress, port: BlackmagicSwitcher.controlPort)
    }

    // MARK: - Polling

    private func pollAllDevices() async {
        let appState = AppState.shared
        let decks     = appState.hyperDecks
        let switchers = appState.switchers
        let stores    = appState.cloudStores

        guard !(decks.isEmpty && switchers.isEmpty && stores.isEmpty) else {
            if !statuses.isEmpty { statuses.removeAll() }
            return
        }

        await withTaskGroup(of: (String, DeckStatus).self) { group in
            for deck in decks {
                group.addTask { (deck.ipAddress, await Self.checkDeck(deck)) }
            }
            for switcher in switchers {
                group.addTask { (switcher.ipAddress, await Self.ping(host: switcher.ipAddress, port: BlackmagicSwitcher.controlPort)) }
            }
            for store in stores {
                group.addTask { (store.ipAddress, await Self.checkCloudStore(store)) }
            }
            for await (host, status) in group {
                statuses[host] = status
            }
        }

        // Drop entries for devices that were removed since the last poll.
        let liveHosts = Set(decks.map(\.ipAddress) + switchers.map(\.ipAddress) + stores.map(\.ipAddress))
        statuses = statuses.filter { liveHosts.contains($0.key) }
    }

    // MARK: - Per-device checks

    /// Reachability first, then — only if reachable — confirms the stored
    /// login can actually list the deck's remote path.
    private static func checkDeck(_ deck: HyperDeck) async -> DeckStatus {
        let reachable = await ping(host: deck.ipAddress, port: 9993)
        guard reachable == .online else { return reachable }

        if case .unauthorized = await FTPService.probeAuth(on: deck) {
            return .unauthorized
        }
        return .online
    }

    /// Reachability first, then — only if reachable — confirms the stored
    /// login can actually authenticate against the SMB share.
    private static func checkCloudStore(_ store: CloudStore) async -> DeckStatus {
        let reachable = await ping(host: store.ipAddress, port: 445)
        guard reachable == .online else { return reachable }

        let auth = await SMBService.probeAuth(
            ip: store.ipAddress, username: store.username, password: store.password
        )
        if case .unauthorized = auth { return .unauthorized }
        return .online
    }

    private static func ping(host: String, port: UInt16) async -> DeckStatus {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return .offline }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        conn.start(queue: .global())
        return await resolveConnectionStatus(conn)
    }
}
