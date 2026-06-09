import Foundation

// Wraps curl-based FTP operations using async/await.
// HyperDecks don't support Swift's URLSession FTP on modern macOS, so we shell out to curl.
struct FTPService {

    // MARK: - List remote .mov files
    static func listMovFiles(on deck: HyperDeck) async -> [String] {
        let encoded = deck.remotePath
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? deck.remotePath
        let url = "ftp://\(deck.ipAddress)/\(encoded)/"

        let output = await runCurl(args: [
            "--user", "\(deck.username):\(deck.password)",
            "--connect-timeout", "5",
            "-s", url
        ])

        return parseMovFiles(from: output)
    }

    // MARK: - Download a single file with progress callback
    // progress: 0.0 – 1.0
    static func downloadFile(
        named fileName: String,
        from deck: HyperDeck,
        to destinationURL: URL,
        progress: @escaping (Double) -> Void
    ) async -> Bool {
        let encoded = deck.remotePath
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? deck.remotePath
        let fileEncoded = fileName
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName
        let url = "ftp://\(deck.ipAddress)/\(encoded)/\(fileEncoded)"

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
                process.arguments = [
                    "--user", "\(deck.username):\(deck.password)",
                    "--connect-timeout", "10",
                    "--progress-bar",     // makes stderr emit clean % lines
                    "-o", destinationURL.path,
                    url
                ]
                process.standardOutput = stdoutPipe
                process.standardError  = stderrPipe

                // Parse curl's stderr progress: "##  3.2%  ..."
                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    let text = String(data: handle.availableData, encoding: .utf8) ?? ""
                    if let pct = parseCurlProgress(text) {
                        DispatchQueue.main.async { progress(pct) }
                    }
                }

                do {
                    try process.run()
                    process.waitUntilExit()
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    let success = process.terminationStatus == 0
                    if success { DispatchQueue.main.async { progress(1.0) } }
                    continuation.resume(returning: success)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    // MARK: - Helpers
    private static func runCurl(args: [String]) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
                process.arguments = args
                process.standardOutput = pipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }

    static func parseMovFiles(from output: String) -> [String] {
        output
            .replacingOccurrences(of: "\r", with: "")
            .components(separatedBy: "\n")
            .compactMap { line -> String? in
                let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard clean.lowercased().contains(".mov") else { return nil }
                // Handle both raw filename and Unix long-listing formats
                let last = clean.components(separatedBy: " ").last ?? clean
                return last.lowercased().hasSuffix(".mov") ? last : nil
            }
    }

    // curl --progress-bar outputs lines like: "## 45.2% ..."
    private static func parseCurlProgress(_ text: String) -> Double? {
        let pattern = #"(\d+(?:\.\d+)?)\s*%"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text),
              let value = Double(text[range]) else { return nil }
        return min(value / 100.0, 1.0)
    }
}
