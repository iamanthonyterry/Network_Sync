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

    /// How long a single attempt is allowed to sit waiting for a connection
    /// before we give up on it. Without this, a dropped/unreachable deck can
    /// leave the NWConnection parked in `.waiting` indefinitely (it doesn't
    /// always transition to `.failed` on its own) — which left `isBusy`
    /// stuck `true` forever and made the Record/Stop/Format buttons look
    /// frozen.
    private static let commandTimeout: Duration = .seconds(4)

    /// A single dropped packet or momentary Wi-Fi blip shouldn't surface as
    /// a hard failure to the person clicking the button — retry a couple
    /// times with a short pause before actually reporting an error.
    private static let maxAttempts = 3
    private static let retryDelay: Duration = .seconds(1)

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
    ///
    /// The HyperDeck Ethernet protocol treats `format` as a two-step handshake:
    /// the initial command only returns a `format token`, and nothing on the
    /// deck actually gets erased until that token is echoed back via
    /// `format confirm:`. Sending just the first command (as this used to do)
    /// leaves the deck waiting for a confirmation that never comes, so the
    /// button looked like it did nothing.
    func formatDrive(filesystem: String = "HFS+") async {
        isBusy = true
        defer { isBusy = false }

        // Both handshake steps run through the raw (non-isBusy-toggling)
        // path so the button/spinner stay steady for the whole operation
        // instead of flickering off between the two commands.
        let readyResponse = await performWithRetry(command: "format filesystem: \(filesystem)\n", readResponse: true) ?? ""
        guard let token = formatToken(from: readyResponse) else {
            if lastError == nil {
                lastError = "Format failed — deck didn't return a confirmation token"
            }
            return
        }
        _ = await performWithRetry(command: "format confirm: \(token)\n", readResponse: true)
    }

    /// Pulls the `format token: <value>` line out of the deck's
    /// "216 format ready" response so it can be echoed back to confirm.
    private func formatToken(from response: String) -> String? {
        for line in response.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("format token:") {
                return trimmed.split(separator: ":", maxSplits: 1).last?
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
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

    /// Polled every 2 seconds in the background, so this deliberately does
    /// NOT toggle `isBusy` — doing so previously made the Record/Format
    /// buttons and their spinner flicker on and off every poll cycle even
    /// when nobody had pressed anything.
    func fetchTransport() async {
        let response = await performWithRetry(command: "transport info\n", readResponse: true) ?? ""
        isConnected = !response.isEmpty
        transport = parseTransport(from: response)
    }

    /// Checks whether a disk/SSD is actually installed in the deck, using
    /// the "slot info" command. Returns nil if the check itself couldn't be
    /// completed (e.g. connection dropped) — that's different from "no media",
    /// so callers shouldn't treat nil the same as `false`. Status check only,
    /// so it doesn't toggle `isBusy` either.
    func checkMediaPresent() async -> Bool? {
        let response = await performWithRetry(command: "slot info\n", readResponse: true) ?? ""
        guard !response.isEmpty else { return nil }
        return !response.lowercased().contains("status: empty")
    }

    /// One-shot convenience for a caller that just wants a quick check
    /// against an IP without holding onto a service instance.
    static func checkMediaPresent(host: String) async -> Bool? {
        await HyperDeckService(host: host).checkMediaPresent()
    }

    // MARK: - Private Networking

    /// Sends a command, retrying a couple of times if a single attempt
    /// times out or the connection drops, before finally reporting failure.
    /// Toggles `isBusy` for the duration — use this for user-initiated
    /// actions (record/stop), not for background status polling.
    private func send(command: String) async {
        isBusy = true
        defer { isBusy = false }
        _ = await performWithRetry(command: command, readResponse: false)
    }

    /// Runs a command with retry logic, without touching `isBusy`. Shared by
    /// the `isBusy`-toggling wrappers above and by callers (background
    /// polling, multi-step handshakes like format) that manage busy/loading
    /// state themselves so it doesn't flicker between steps.
    private func performWithRetry(command: String, readResponse: Bool) async -> String? {
        for attempt in 1...Self.maxAttempts {
            lastError = nil
            if let response = await attemptSendAndReceive(command: command, readResponse: readResponse) {
                isConnected = true
                return response
            }
            if attempt < Self.maxAttempts {
                try? await Task.sleep(for: Self.retryDelay)
            }
        }
        isConnected = false
        return nil
    }

    /// A single connect → send → (optionally) read attempt. Returns nil on
    /// any failure (connection error or timeout) so the caller can decide
    /// whether to retry; returns the response text (empty string if
    /// `readResponse` is false) on success.
    private func attemptSendAndReceive(command: String, readResponse: Bool) async -> String? {
        guard let portObj = NWEndpoint.Port(rawValue: port) else { return nil }
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: portObj,
            using: .tcp
        )

        return await withCheckedContinuation { continuation in
            nonisolated(unsafe) var resumed = false
            let resumeOnce: @Sendable (String?) -> Void = { value in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: value)
            }

            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    let data = Data(command.utf8)
                    connection.send(content: data, completion: .contentProcessed { error in
                        if let error {
                            connection.cancel()
                            Task { @MainActor in self.lastError = error.localizedDescription }
                            resumeOnce(nil)
                            return
                        }
                        guard readResponse else {
                            connection.cancel()
                            resumeOnce("")
                            return
                        }
                        // Read response (up to 4 KB)
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                            connection.cancel()
                            let response = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                            resumeOnce(response)
                        }
                    })
                case .failed(let error):
                    connection.cancel()
                    Task { @MainActor in self.lastError = error.localizedDescription }
                    resumeOnce(nil)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))

            Task {
                try? await Task.sleep(for: Self.commandTimeout)
                guard !resumed else { return }
                connection.cancel()
                await MainActor.run { self.lastError = "Timed out — device didn't respond" }
                resumeOnce(nil)
            }
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

