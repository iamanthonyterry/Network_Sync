import Foundation

struct ConversionService {

    // Convert a single MOV to MP4.
    // progress: 0.0 – 1.0, derived from ffmpeg's time= output vs total duration.
    static func convert(
        input: URL,
        output: URL,
        settings: ConversionSettings,
        progress: @escaping (Double) -> Void
    ) async -> Bool {
        // Ensure output directory exists
        try? FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let duration = await probeDuration(of: input)

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stderrPipe = Pipe()

                process.executableURL = ffmpegURL()
                process.arguments = [
                    "-i", input.path,
                    "-c:v", "libx264",
                    "-preset", settings.preset.rawValue,
                    "-crf", "\(settings.crf)",
                    "-c:a", "aac",
                    "-b:a", settings.audioBitrate,
                    "-movflags", "+faststart",
                    "-threads", "0",
                    "-y",
                    output.path
                ]
                process.standardError = stderrPipe

                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    let text = String(data: handle.availableData, encoding: .utf8) ?? ""
                    if duration > 0, let elapsed = parseFFmpegTime(text) {
                        let pct = min(elapsed / duration, 1.0)
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

    // MARK: - Probe total duration via ffprobe
    private static func probeDuration(of url: URL) async -> Double {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = ffprobeURL()
                process.arguments = [
                    "-v", "quiet",
                    "-print_format", "compact=print_section=0:nokey=1:escape=csv",
                    "-show_entries", "format=duration",
                    url.path
                ]
                process.standardOutput = pipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    continuation.resume(returning: Double(out.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0)
                } catch {
                    continuation.resume(returning: 0)
                }
            }
        }
    }

    // MARK: - Parse "time=HH:MM:SS.ss" from ffmpeg stderr
    static func parseFFmpegTime(_ text: String) -> Double? {
        let pattern = #"time=(\d{2}):(\d{2}):(\d{2})\.(\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func g(_ i: Int) -> Double {
            guard let r = Range(match.range(at: i), in: text) else { return 0 }
            return Double(text[r]) ?? 0
        }
        return g(1) * 3600 + g(2) * 60 + g(3) + g(4) / 100
    }

    // MARK: - ffmpeg / ffprobe paths (Homebrew ARM or Intel)
    static func ffmpegURL() -> URL {
        let paths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
        return paths.compactMap { FileManager.default.fileExists(atPath: $0) ? URL(fileURLWithPath: $0) : nil }.first
            ?? URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
    }
    static func ffprobeURL() -> URL {
        let paths = ["/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe"]
        return paths.compactMap { FileManager.default.fileExists(atPath: $0) ? URL(fileURLWithPath: $0) : nil }.first
            ?? URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe")
    }
}
