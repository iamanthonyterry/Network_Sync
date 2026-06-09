import Foundation
import Combine

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: - Persisted State
    @Published var hyperDecks: [HyperDeck] = [] {
        didSet { save(hyperDecks, key: "hyperDecks") }
    }
    @Published var syncLocation: SyncLocation = SyncLocation() {
        didSet { save(syncLocation, key: "syncLocation") }
    }
    @Published var conversionSettings: ConversionSettings = ConversionSettings() {
        didSet { save(conversionSettings, key: "conversionSettings") }
    }

    // MARK: - Live Pipeline State
    @Published var isRunning = false
    @Published var activeTasks: [SyncTask] = []
    @Published var pipelineLog: [String] = []

    init() {
        hyperDecks         = load([HyperDeck].self,       key: "hyperDecks")         ?? Self.defaultDecks
        syncLocation       = load(SyncLocation.self,      key: "syncLocation")       ?? SyncLocation()
        conversionSettings = load(ConversionSettings.self, key: "conversionSettings") ?? ConversionSettings()
    }

    // MARK: - Deck CRUD
    func addDeck(_ deck: HyperDeck) {
        var d = deck; d.sortOrder = hyperDecks.count
        hyperDecks.append(d)
    }
    func updateDeck(_ deck: HyperDeck) {
        guard let i = hyperDecks.firstIndex(where: { $0.id == deck.id }) else { return }
        hyperDecks[i] = deck
    }
    func deleteDeck(id: UUID) { hyperDecks.removeAll { $0.id == id } }
    func moveDeck(from: IndexSet, to: Int) {
        hyperDecks.move(fromOffsets: from, toOffset: to)
        for i in hyperDecks.indices { hyperDecks[i].sortOrder = i }
    }

    // MARK: - Log
    func log(_ message: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        pipelineLog.append("[\(ts)] \(message)")
    }

    // MARK: - Persistence
    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: - Default seed data
    private static var defaultDecks: [HyperDeck] {
        [("ISO 1","192.168.2.138","usb/Extreme Pro"),
         ("ISO 2","192.168.2.139","usb/Extreme Pro"),
         ("ISO 3","192.168.2.140","usb/Extreme Pro"),
         ("ISO 4","192.168.2.141","usb/ISO_4"),
         ("ISO 5","192.168.2.142","usb/ISO_5"),
         ("ISO 6","192.168.2.129","usb/ISO 6"),
         ("ISO 7","192.168.2.128","usb/ISO 7"),
         ("ISO 8","192.168.2.127","usb/ISO 8"),
         ("ISO 9","192.168.2.126","usb/ISO 9"),
         ("ISO 10","192.168.2.125","usb/ISO 10")]
            .enumerated().map { i, t in
                HyperDeck(name: t.0, ipAddress: t.1, remotePath: t.2, sortOrder: i)
            }
    }
}
