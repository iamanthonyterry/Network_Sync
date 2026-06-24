import Foundation
import Combine

/// Installs Homebrew and ffmpeg automatically — no Terminal required.
@MainActor
final class ToolInstaller: ObservableObject {

    static let shared = ToolInstaller()

    enum Phase: Equatable {
        case idle
        case installing(step: String)
        case done
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var log: [String] = []

    // MARK: - Public checks

    var ffmpegReady: Bool {
        ConversionService.ffmpegURL() != nil
    }

    var brewPath: String? {
        let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    // MARK: - Install entry point

    func installIfNeeded() {
        guard !ffmpegReady else { phase = .done; return }
        phase = .installing(step: "Starting…")
        log = []

        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.run()
        }
    }

    // MARK: - Installation pipeline

    private func run() async {
        // Step 1: ensure Homebrew exists
        if brewPath == nil {
            await setStep("Installing Homebrew…")
            let ok = await installHomebrew()
            guard ok else {
                await setFailed("Homebrew install failed. See log for details.")
                return
            }
        }

        // Step 2: install ffmpeg via brew
        await setStep("Installing ffmpeg via Homebrew…")
        let ok = await brewInstall("ffmpeg")
        if ok {
            await MainActor.run { self.phase = .done }
        } else {
            await setFailed("ffmpeg install failed. See log for details.")
        }
    }

    // MARK: - Homebrew installation

    private func installHomebrew() async -> Bool {
        // Download the official install script, then run it with /bin/bash
        await appendLog("Downloading Homebrew install script…")

        guard let scriptURL = URL(string: "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh") else {
            await appendLog("❌ Invalid Homebrew install script URL")
            return false
        }

        let scriptData: Data
        do {
            let (data, _) = try await URLSession.shared.data(from: scriptURL)
            scriptData = data
        } catch {
            await appendLog("❌ Could not download Homebrew install script: \(error.localizedDescription)")
            return false
        }

        guard let script = String(data: scriptData, encoding: .utf8) else {
            await appendLog("❌ Homebrew install script had unexpected encoding")
            return false
        }

        // Write to a temp file
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("brew_install.sh")
        do {
            try script.write(to: tmp, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
        } catch {
            await appendLog("❌ Could not write install script: \(error.localizedDescription)")
            return false
        }

        // NONINTERACTIVE=1 skips prompts
        return await runProcess(
            executable: "/bin/bash",
            arguments: [tmp.path],
            environment: ["NONINTERACTIVE": "1", "HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        )
    }

    // MARK: - brew install <package>

    private func brewInstall(_ package: String) async -> Bool {
        guard let brew = brewPath else {
            await appendLog("❌ brew not found after install")
            return false
        }
        return await runProcess(
            executable: brew,
            arguments: ["install", package],
            environment: ["HOME": NSHomeDirectory(), "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"]
        )
    }

    // MARK: - Generic subprocess runner

    private func runProcess(
        executable: String,
        arguments: [String],
        environment: [String: String]
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = environment
            process.standardOutput = pipe
            process.standardError = pipe   // merge so we capture everything

            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let text = String(data: handle.availableData, encoding: .utf8) ?? ""
                guard !text.isEmpty else { return }
                Task { @MainActor [weak self] in
                    self?.log.append(contentsOf: text
                        .components(separatedBy: .newlines)
                        .filter { !$0.isEmpty })
                }
            }

            process.terminationHandler = { p in
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: p.terminationStatus == 0)
            }

            do {
                try process.run()
            } catch {
                Task { @MainActor [weak self] in
                    self?.log.append("❌ Process error: \(error.localizedDescription)")
                }
                continuation.resume(returning: false)
            }
        }
    }

    // MARK: - Helpers

    private func setStep(_ step: String) async {
        await MainActor.run { self.phase = .installing(step: step) }
    }

    private func setFailed(_ message: String) async {
        await MainActor.run { self.phase = .failed(message) }
    }

    private func appendLog(_ line: String) async {
        await MainActor.run { self.log.append(line) }
    }
}
