import Foundation

// Wraps curl-based FTP operations using async/await.
// HyperDecks don't support Swift's URLSession FTP on modern macOS, so we shell out to curl.
struct FTPService {

    // MARK: - FTP Directory Entry

    struct FTPEntry: Hashable {
        let name: String
        let isDirectory: Bool
        let size: Int64
        let modified: Date
    }

    // MARK: - Login / permission probe

    /// Result of attempting to actually log in and list the remote path,
    /// as opposed to just checking that the port is open.
    enum AuthResult: Sendable {
        case authorized
        case unauthorized   // reachable, but login or permission denied
        case inconclusive   // couldn't tell (timeout, network error, etc.)
    }

    /// Confirms the deck's stored username/password can actually log in and
    /// list its configured remote path.
    static func probeAuth(on deck: HyperDeck) async -> AuthResult {
        let encoded = deck.remotePath
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? deck.remotePath
        let url = "ftp://\(deck.ipAddress)/\(encoded)/"

        let (_, exitCode) = await runProcessWithExitCode(
            executable: "/usr/bin/curl",
            args: ["--user", "\(deck.username):\(deck.password)",
                   "--connect-timeout", "5", "-s", "--list-only", url]
        )

        switch exitCode {
        case 0:      return .authorized
        case 9, 67:  return .unauthorized   // FTP access denied / login failed
        default:     return .inconclusive
        }
    }

    // MARK: - List all files in a remote directory

    static func listAllFiles(on deck: HyperDeck, path: String) async -> [FTPEntry] {
        let encoded = path
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let url = "ftp://\(deck.ipAddress)/\(encoded)/"

        let output = await runProcess(
            executable: "/usr/bin/curl",
            args: ["--user", "\(deck.username):\(deck.password)",
                   "--connect-timeout", "5", "-s", "--list-only", url]
        )
        return parseFTPListing(from: output, basePath: path, deck: deck)
    }

    // MARK: - List remote .mov files (legacy)
    static func listMovFiles(on deck: HyperDeck) async -> [String] {
        let encoded = deck.remotePath
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? deck.remotePath
        let url = "ftp://\(deck.ipAddress)/\(encoded)/"

        let output = await runProcess(
            executable: "/usr/bin/curl",
            args: ["--user", "\(deck.username):\(deck.password)",
                   "--connect-timeout", "5", "-s", url]
        )
        return parseMovFiles(from: output)
    }

    // MARK: - Download result
    // Carries a human-readable reason on failure so logs and the UI can
    // explain *why* a download failed, not just that it did.
    struct DownloadResult: Sendable {
        let success: Bool
        let failureReason: String?

        static let ok = DownloadResult(success: true, failureReason: nil)
        static func failed(_ reason: String) -> DownloadResult {
            DownloadResult(success: false, failureReason: reason)
        }
    }

    // MARK: - Download a single file with progress callback (0.0–1.0)
    static func downloadFile(
        named fileName: String,
        from deck: HyperDeck,
        to destinationURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async -> DownloadResult {
        let encoded = deck.remotePath
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? deck.remotePath
        let fileEncoded = fileName
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName
        let url = "ftp://\(deck.ipAddress)/\(encoded)/\(fileEncoded)"

        return await withCheckedContinuation { continuation in
            let process = Process()
            let stderrPipe = Pipe()
            nonisolated(unsafe) var stderrText = ""

            process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            process.arguments = [
                "--user", "\(deck.username):\(deck.password)",
                "--connect-timeout", "10",
                "--progress-bar",
                "-o", destinationURL.path,
                url
            ]
            process.standardOutput = Pipe()   // discard stdout
            process.standardError  = stderrPipe

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let text = String(data: handle.availableData, encoding: .utf8) ?? ""
                stderrText += text
                if let pct = parseCurlProgress(text) {
                    Task { @MainActor in progress(pct) }
                }
            }

            process.terminationHandler = { p in
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                if p.terminationStatus == 0 {
                    Task { @MainActor in progress(1.0) }
                    continuation.resume(returning: .ok)
                } else {
                    let reason = curlFailureReason(exitCode: p.terminationStatus, stderr: stderrText)
                    continuation.resume(returning: .failed(reason))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: .failed("Couldn't launch curl: \(error.localizedDescription)"))
            }
        }
    }

    /// Turns a curl exit code + raw stderr into a short, readable failure reason.
    /// See `man curl` exit code list for the full mapping.
    private static func curlFailureReason(exitCode: Int32, stderr: String) -> String {
        // --progress-bar writes carriage-return-separated "#" progress ticks to
        // stderr alongside real error text, so strip anything that's just
        // progress-bar noise and keep the actual message lines.
        let detailLines = stderr
            .components(separatedBy: CharacterSet(charactersIn: "\r\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                guard !line.isEmpty else { return false }
                return line.contains(where: { !"#% \t0123456789.".contains($0) })
            }
        let detail = detailLines.isEmpty ? nil : detailLines.joined(separator: "; ")

        let summary: String
        switch exitCode {
        case 7:  summary = "couldn't connect to deck"
        case 9:  summary = "FTP access denied (check remote path)"
        case 28: summary = "connection timed out"
        case 67: summary = "FTP login failed (check username/password)"
        case 78: summary = "remote file not found"
        default: summary = "curl exit \(exitCode)"
        }

        if let detail {
            return "\(summary) — \(detail)"
        }
        return summary
    }

    // MARK: - Generic process runner (non-blocking)
    private static func runProcess(executable: String, args: [String]) async -> String {
        await runProcessWithExitCode(executable: executable, args: args).output
    }

    /// Same as `runProcess`, but also surfaces the exit code so callers can
    /// distinguish "reachable" from "reachable but denied".
    private static func runProcessWithExitCode(
        executable: String, args: [String]
    ) async -> (output: String, exitCode: Int32) {
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            process.standardOutput = pipe
            process.standardError  = pipe

            process.terminationHandler = { p in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: (String(data: data, encoding: .utf8) ?? "", p.terminationStatus))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: ("", -1))
            }
        }
    }

    // MARK: - Helpers

    /// Parses a --list-only FTP response (one filename per line) into FTPEntry values.
    /// Uses a second curl call with -v to get size/date for each entry when available,
    /// but falls back to lightweight name-only parsing for speed.
    private static func parseFTPListing(from output: String, basePath: String, deck: HyperDeck) -> [FTPEntry] {
        output
            .replacingOccurrences(of: "\r", with: "")
            .components(separatedBy: "\n")
            .compactMap { line -> FTPEntry? in
                let name = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, name != ".", name != ".." else { return nil }
                let isDirectory = !name.contains(".")   // simple heuristic; HyperDeck dirs have no extension
                return FTPEntry(name: name, isDirectory: isDirectory, size: 0, modified: .distantPast)
            }
    }

    static func parseMovFiles(from output: String) -> [String] {
        output
            .replacingOccurrences(of: "\r", with: "")
            .components(separatedBy: "\n")
            .compactMap { line -> String? in
                let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard clean.lowercased().contains(".mov") else { return nil }
                let last = clean.components(separatedBy: " ").last ?? clean
                return last.lowercased().hasSuffix(".mov") ? last : nil
            }
    }

    private static func parseCurlProgress(_ text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*%"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text),
              let value = Double(text[range]) else { return nil }
        return min(value / 100.0, 1.0)
    }
}
