import Foundation
import Network
import Combine

// MARK: - HyperDeck Transport State

enum HyperDeckTransport: String {
    case recording  = "record"
    case stopped    = "stopped"
    case playing    = "play"
    case unknown    = "unknown"
}

// MARK: - HyperDeck Service
// Communicates with a HyperDeck over its Ethernet protocol (TCP port 9993).
// Commands follow the plain-text HyperDeck Ethernet Protocol spec.

@MainActor
final class HyperDeckService: ObservableObject {
    @Published var transport: HyperDeckTransport = .unknown
    @Published var isConnected = false
    @Published var isBusy = false
    @Published var lastError: String? = nil

    private let host: String
    private let port: UInt16 = 9993
    private var pollTask: Task<Void, Never>?

    init(host: String) {
        self.host = host
    }

    deinit {
        pollTask?.cancel()
    }

    // MARK: - Polling

    /// Starts polling the drive's transport state every 2 seconds so the UI
    /// reacts instantly whether recording is started from the app or manually.
    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fetchTransport()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Public Commands

    func record() async {
        await send(command: "record\n")
        await fetchTransport()
    }

    func stop() async {
        await send(command: "stop\n")
        await fetchTransport()
    }

    /// Formats the active slot. This is destructive — caller should confirm first.
    func formatDrive(filesystem: String = "HFS+") async {
        await send(command: "format filesystem: \(filesystem)\n")
    }

    /// Convenience: create a one-shot connection, format, and discard.
    static func formatDrive(deck: HyperDeck, filesystem: String = "HFS+") async throws {
        let service = HyperDeckService(host: deck.ipAddress)
        await service.formatDrive(filesystem: filesystem)
        if let error = service.lastError {
            throw NSError(domain: "HyperDeckService", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: error])
        }
    }

    func fetchTransport() async {
        let response = await sendAndReceive(command: "transport info\n")
        isConnected = !response.isEmpty
        transport = parseTransport(from: response)
    }

    /// Checks whether a disk/SSD is actually installed in the deck, using
    /// the "slot info" command. Returns nil if the check itself couldn't be
    /// completed (e.g. connection dropped) — that's different from "no media",
    /// so callers shouldn't treat nil the same as `false`.
    func checkMediaPresent() async -> Bool? {
        let response = await sendAndReceive(command: "slot info\n")
        guard !response.isEmpty else { return nil }
        return !response.lowercased().contains("status: empty")
    }

    /// One-shot convenience for a caller that just wants a quick check
    /// against an IP without holding onto a service instance.
    static func checkMediaPresent(host: String) async -> Bool? {
        await HyperDeckService(host: host).checkMediaPresent()
    }

    // MARK: - Private Networking

    /// Opens a fresh TCP connection, sends a command, and closes.
    private func send(command: String) async {
        isBusy = true
        lastError = nil
        defer { isBusy = false }

        guard let portObj = NWEndpoint.Port(rawValue: port) else { return }
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: portObj,
            using: .tcp
        )

        await withCheckedContinuation { continuation in
            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    let data = Data(command.utf8)
                    connection.send(content: data, completion: .contentProcessed { error in
                        connection.cancel()
                        if let error {
                            Task { @MainActor in self.lastError = error.localizedDescription }
                        }
                        continuation.resume()
                    })
                case .failed(let error):
                    Task { @MainActor in
                        self.lastError = error.localizedDescription
                        self.isConnected = false
                    }
                    continuation.resume()
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    /// Opens a TCP connection, sends a command, reads the response, and closes.
    private func sendAndReceive(command: String) async -> String {
        isBusy = true
        lastError = nil
        defer { isBusy = false }

        guard let portObj = NWEndpoint.Port(rawValue: port) else { return "" }
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: portObj,
            using: .tcp
        )

        return await withCheckedContinuation { continuation in
            nonisolated(unsafe) var resumed = false

            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    let data = Data(command.utf8)
                    connection.send(content: data, completion: .contentProcessed { error in
                        if let error {
                            Task { @MainActor in self.lastError = error.localizedDescription }
                            if !resumed { resumed = true; continuation.resume(returning: "") }
                            return
                        }
                        // Read response (up to 4 KB)
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                            connection.cancel()
                            let response = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                            if !resumed { resumed = true; continuation.resume(returning: response) }
                        }
                    })
                case .failed(let error):
                    Task { @MainActor in
                        self.lastError = error.localizedDescription
                        self.isConnected = false
                    }
                    if !resumed { resumed = true; continuation.resume(returning: "") }
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    // MARK: - Response Parsing

    private func parseTransport(from response: String) -> HyperDeckTransport {
        print("[HyperDeckService] transport info response:\n\(response)")
        for line in response.lowercased().components(separatedBy: "\n") {
            if line.contains("status:") {
                if line.contains("record")  { return .recording }
                if line.contains("stopped") || line.contains("preview") { return .stopped }
                if line.contains("play")    { return .playing }
            }
        }
        return .unknown
    }
}

