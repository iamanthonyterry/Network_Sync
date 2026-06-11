import Foundation
import Combine

@MainActor
class PipelineEngine: ObservableObject {
    static let shared = PipelineEngine()

    private let appState = AppState.shared

    // MARK: - Run All
    func runAll() async {
        guard !appState.isRunning else { return }
        appState.isRunning = true
        appState.beginRun()
        appState.log("▶ Pipeline started")

        appState.log("Mounting \(appState.syncLocation.volumeName)...")
        let mounted = await mountSMBVolume(location: appState.syncLocation)
        guard mounted else {
            appState.log("❌ Could not mount SMB volume. Aborting.")
            appState.isRunning = false
            return
        }
        appState.log("✅ Mounted at \(appState.syncLocation.mountPath)")

        for deck in appState.hyperDecks {
            guard appState.isRunning else { break }
            await syncAndConvert(deck: deck)
        }

        finishRun()
    }

    // MARK: - Run Single Deck
    func runDeck(_ deck: HyperDeck) async {
        guard !appState.isRunning else { return }
        appState.isRunning = true
        appState.beginRun()
        appState.log("▶ Single-deck run: \(deck.name)")

        let mounted = await mountSMBVolume(location: appState.syncLocation)
        guard mounted else {
            appState.log("❌ Could not mount SMB volume.")
            appState.isRunning = false
            return
        }

        await syncAndConvert(deck: deck)
        finishRun()
    }

    // MARK: - SMB Mount
    private func mountSMBVolume(location: SyncLocation) async -> Bool {
        if FileManager.default.fileExists(atPath: location.mountPath) { return true }
        let script = "mount volume \"smb://\(location.ipAddress)/\(location.volumeName)\" as user name \"\(location.username)\" with password \"\(location.password)\""
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                do {
                    try process.run()
                    process.waitUntilExit()
                    Thread.sleep(forTimeInterval: 2)
                    continuation.resume(returning: FileManager.default.fileExists(atPath: location.mountPath))
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    // MARK: - Stop
    func stop() {
        appState.isRunning = false
        appState.log("⏹ Pipeline stopped by user")
        appState.commitRun()
    }

    // MARK: - Core interleaved logic
    private func syncAndConvert(deck: HyperDeck) async {
        appState.log("📡 Scanning \(deck.name) (\(deck.ipAddress))...")
        if !appState.currentRunDecks.contains(deck.name) {
            appState.currentRunDecks.append(deck.name)
        }

        let remoteFiles = await FTPService.listMovFiles(on: deck)
        guard !remoteFiles.isEmpty else {
            appState.log("  \(deck.name): no .mov files found")
            return
        }
        appState.log("  \(deck.name): \(remoteFiles.count) file(s) found")

        let deckDestDir = URL(fileURLWithPath: appState.syncLocation.recordsPath)
            .appendingPathComponent(deck.name)
        try? FileManager.default.createDirectory(at: deckDestDir, withIntermediateDirectories: true)

        for fileName in remoteFiles {
            guard appState.isRunning else { return }

            let destURL    = deckDestDir.appendingPathComponent(fileName)
            let receiptURL = deckDestDir.appendingPathComponent(fileName + ".done")

            if FileManager.default.fileExists(atPath: destURL.path) ||
               FileManager.default.fileExists(atPath: receiptURL.path) {
                appState.log("  ⏭ \(fileName) already processed")
                appState.currentRunSkipped += 1
                continue
            }

            // Download
            let task = addTask(fileName: fileName, deckName: deck.name)
            updateTask(id: task.id, phase: .downloading, syncProgress: 0)
            appState.log("  ⬇ Downloading \(fileName)...")

            let downloaded = await FTPService.downloadFile(
                named: fileName, from: deck, to: destURL
            ) { pct in self.updateTask(id: task.id, syncProgress: pct) }

            guard downloaded else {
                updateTask(id: task.id, phase: .error, errorMessage: "Download failed")
                appState.log("  ❌ Download failed: \(fileName)")
                appState.currentRunErrors += 1
                continue
            }
            updateTask(id: task.id, phase: .converting, syncProgress: 1)
            appState.log("  ✅ Downloaded \(fileName)")

            // Convert
            guard appState.isRunning else { return }
            let convertedDir = deckDestDir.appendingPathComponent("Converted")
            let outputURL = convertedDir.appendingPathComponent(
                (fileName as NSString).deletingPathExtension + ".mp4"
            )
            appState.log("  🎬 Converting \(fileName)...")

            let converted = await ConversionService.convert(
                input: destURL, output: outputURL,
                settings: appState.conversionSettings
            ) { pct in self.updateTask(id: task.id, convertProgress: pct) }

            if converted {
                updateTask(id: task.id, phase: .done, convertProgress: 1)
                appState.log("  ✅ Converted → \(outputURL.lastPathComponent)")
                appState.currentRunConverted += 1
                if appState.conversionSettings.deleteOriginalsAfterConvert {
                    try? FileManager.default.removeItem(at: destURL)
                    FileManager.default.createFile(atPath: receiptURL.path, contents: nil)
                }
            } else {
                updateTask(id: task.id, phase: .error, errorMessage: "Conversion failed")
                appState.log("  ❌ Conversion failed: \(fileName)")
                appState.currentRunErrors += 1
            }
        }
    }

    // MARK: - Finish
    private func finishRun() {
        appState.isRunning = false
        let c = appState.currentRunConverted
        let e = appState.currentRunErrors
        appState.log("✅ Done — \(c) converted, \(e) errors")
        appState.commitRun()
        NotificationService.sendCompletion(converted: c, errors: e)
    }

    // MARK: - Task helpers
    @discardableResult
    private func addTask(fileName: String, deckName: String) -> SyncTask {
        let t = SyncTask(fileName: fileName, deckName: deckName)
        appState.activeTasks.append(t)
        return t
    }

    private func updateTask(
        id: UUID,
        phase: SyncTask.Phase? = nil,
        syncProgress: Double? = nil,
        convertProgress: Double? = nil,
        errorMessage: String? = nil
    ) {
        guard let i = appState.activeTasks.firstIndex(where: { $0.id == id }) else { return }
        if let v = phase           { appState.activeTasks[i].phase           = v }
        if let v = syncProgress    { appState.activeTasks[i].syncProgress    = v }
        if let v = convertProgress { appState.activeTasks[i].convertProgress = v }
        if let v = errorMessage    { appState.activeTasks[i].errorMessage    = v }
    }
}
