import Foundation
import Combine
import SwiftUI

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
    @Published var scheduleSettings: ScheduleSettings = ScheduleSettings() {
        didSet { save(scheduleSettings, key: "scheduleSettings") }
    }
    @Published var runHistory: [PipelineRun] = [] {
        didSet { save(runHistory, key: "runHistory") }
    }

    // MARK: - Live Pipeline State
    @Published var isRunning = false
    @Published var activeTasks: [SyncTask] = []
    @Published var pipelineLog: [String] = []

    // Failed tasks eligible for retry
    var failedTasks: [SyncTask] { activeTasks.filter { $0.phase == .error } }

    // MARK: - Current run counters
    var currentRunConverted = 0
    var currentRunSkipped   = 0
    var currentRunErrors    = 0
    var currentRunDecks: [String] = []
    var currentRunStart: Date = Date()

    init() {
        hyperDecks         = load([HyperDeck].self,        key: "hyperDecks")         ?? []
        syncLocation       = load(SyncLocation.self,       key: "syncLocation")       ?? SyncLocation()
        conversionSettings = load(ConversionSettings.self, key: "conversionSettings") ?? ConversionSettings()
        scheduleSettings   = load(ScheduleSettings.self,   key: "scheduleSettings")   ?? ScheduleSettings()
        runHistory         = load([PipelineRun].self,      key: "runHistory")         ?? []
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

    // MARK: - Run lifecycle
    func beginRun() {
        currentRunConverted = 0
        currentRunSkipped   = 0
        currentRunErrors    = 0
        currentRunDecks     = []
        currentRunStart     = Date()
        activeTasks         = []
        pipelineLog         = []
    }

    func commitRun() {
        let run = PipelineRun(
            startedAt:       currentRunStart,
            finishedAt:      Date(),
            converted:       currentRunConverted,
            skipped:         currentRunSkipped,
            errors:          currentRunErrors,
            decksProcessed:  currentRunDecks,
            log:             pipelineLog
        )
        runHistory.insert(run, at: 0)
        // Keep at most 50 history entries
        if runHistory.count > 50 { runHistory = Array(runHistory.prefix(50)) }
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

}
