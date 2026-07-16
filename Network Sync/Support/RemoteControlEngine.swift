import Foundation

// MARK: - Remote Control Engine
// Owns the OSC and MIDI listeners, applies persisted settings to them, and
// matches incoming messages against the user's mappings to drive HyperDeck
// actions. A singleton (like WorkflowEngine) since there's only ever one
// live set of listeners for the app.

@MainActor
final class RemoteControlEngine: ObservableObject {
    static let shared = RemoteControlEngine()

    let osc = OSCListenerService()
    let midi = MIDIListenerService()

    private let appState = AppState.shared

    private init() {
        osc.onMessage = { [weak self] message, _ in
            self?.handle(osc: message)
        }
        midi.onMessage = { [weak self] message, _ in
            self?.handle(midi: message)
        }
    }

    /// Starts/stops each listener to match the persisted settings. Call
    /// this on launch and again whenever the user changes a setting.
    func applySettings() {
        let settings = appState.remoteControlSettings

        if settings.oscEnabled {
            osc.start(port: settings.oscPort)
        } else {
            osc.stop()
        }

        if settings.midiEnabled {
            midi.start(sourceFilter: settings.midiSourceNames)
        } else {
            midi.stop()
        }
    }

    // MARK: - Matching

    private func handle(osc message: OSCMessage) {
        let matches = appState.remoteMappings.filter { mapping in
            guard mapping.isEnabled, case .osc(let address) = mapping.trigger else { return false }
            return address == message.address
        }
        matches.forEach(execute)
    }

    private func handle(midi message: MIDIMessage) {
        let matches = appState.remoteMappings.filter { mapping in
            guard mapping.isEnabled,
                  case .midi(let kind, let channel, let number) = mapping.trigger else { return false }
            return kind == message.kind && channel == message.channel && number == message.number
        }
        matches.forEach(execute)
    }

    // MARK: - Execution

    private func execute(_ mapping: RemoteMapping) {
        guard let deck = appState.hyperDecks.first(where: { $0.id == mapping.deckID }) else {
            appState.log("⚠️ Remote control \"\(mapping.name)\" targets a device that no longer exists")
            return
        }
        appState.log("🎛 Remote control: \"\(mapping.name)\" → \(mapping.action.title) on \(deck.name)")

        Task {
            switch mapping.action {
            case .record:
                await HyperDeckService(host: deck.ipAddress).record()
            case .stop:
                await HyperDeckService(host: deck.ipAddress).stop()
            case .format:
                do {
                    try await HyperDeckService.formatDrive(deck: deck)
                } catch {
                    appState.log("❌ Remote control format failed: \(error.localizedDescription)")
                }
            }
        }
    }
}
