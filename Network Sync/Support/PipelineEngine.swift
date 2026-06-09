import Foundation

// Orchestrates the full sync + convert pipeline across all decks.
// Mirrors the Python script's interleaved pattern: sync deck → convert deck → next deck.
@MainActor
class PipelineEngine: ObservableObject {
    static let shared = PipelineEngine()

    private let appState = AppState.shared

    // MARK: - Run full pipeline
    func runAll() async {
        guard !appState.isRunning else { return }
        appState.isRunning = true
        appState.activeTasks = []
        appState.pipelineLog = []
        appState.log("Pipeline started")

        // 1. Mount SMB volume
        appState.log("Mounting \(appState.syncLocation.volumeName)...")
        let mounted = await mountSMBVolume(location: appState.syncLocation)
        guard mounted else {
            appState.log("❌ Could not mount SMB volume. Aborting.")
            appState.isRunning = false
            return
        }
        appState.log("✅ Volume mounted at \(appState.syncLocation.mountPath)")

        // 2. For each deck: sync then convert (interleaved, sequential per deck)
        for deck in appState.hyperDecks {
            await syncAndConvert(deck: deck)
        }

        appState.log("✅ Pipeline complete")
        appState.isRunning = false
    }

    // MARK: - Run single deck
    func runDeck(_ deck: HyperDeck) async {
        guard !appState.isRunning else { return }
        appState.isRunning = true
        appState.log("Starting single-deck run for \(deck.name)")

        let mounted = await mountSMBVolume(location: appState.syncLocation)
        guard mounted else {
            appState.log("❌ Could not mount SMB volume.")
            appState.isRunning = false
            return
        }

        await syncAndConvert(deck: deck)
        appState.isRunning = false
    }

    // MARK: - Stop
    func stop() {
        appState.isRunning = false
        appState.log("Pipeline stopped by user")
    }

    // MARK: - Core interleaved logic
    private func syncAndConvert(deck: HyperDeck) async {
        appState.log("📡 Scanning \(deck.name) (\(deck.ipAddress))...")

        let remoteFiles = await FTPService.listMovFiles(on: deck)
        guard !remoteFiles.isEmpty else {
            appState.log("  \(deck.name): no .mov files found")
            return
        }
        appState.log("  \(deck.name): \(remoteFiles.count) file(s) found")

        let deckDestDir = URL(fileURLWithPath: appState.syncLocation.recordsPath)
            .appendingPathComponent(deck.name)
        try? FileManager.default.createDirectory(at: deckDestDir, withIntermediateDirectories: true)

        // Phase A: Download all files for this deck
        for fileName in remoteFiles {
            guard appState.isRunning else { return }

            let destURL = deckDestDir.appendingPathComponent(fileName)
            let receiptURL = deckDestDir.appendingPathComponent(fileName + ".done")

            // Skip if already downloaded or converted
            if FileManager.default.fileExists(atPath: destURL.path) ||
               FileManager.default.fileExists(atPath: receiptURL.path) {
                appState.log("  ⏭️ \(fileName) already present, skipping download")
                continue
            }

            let task = addTask(fileName: fileName, deckName: deck.name)
            updateTask(id: task.id, phase: .downloading, syncProgress: 0)
            appState.log("  ⬇️ Downloading \(fileName)...")

            let ok = await FTPService.downloadFile(named: fileName, from: deck, to: destURL) { pct in
                self.updateTask(id: task.id, syncProgress: pct)
            }

            if ok {
                updateTask(id: task.id, phase: .converting, syncProgress: 1)
                appState.log("  ✅ Downloaded \(fileName)")
            } else {
                updateTask(id: task.id, phase: .error, errorMessage: "Download failed")
                appState.log("  ❌ Download failed: \(fileName)")
                continue
            }

            // Phase B: Convert immediately after each download
            guard appState.isRunning else { return }
            let convertedDir = deckDestDir.appendingPathComponent("Converted")
            let outputURL = convertedDir.appendingPathComponent(
                (fileName as NSString).deletingPathExtension + ".mp4"
            )

            appState.log("  🎬 Converting \(fileName)...")
            let converted = await ConversionService.convert(
                input: destURL,
                output: outputURL,
                settings: appState.conversionSettings
            ) { pct in
                self.updateTask(id: task.id, convertProgress: pct)
            }

            if converted {
                updateTask(id: task.id, phase: .done, convertProgress: 1)
                appState.log("  ✅ Converted → \(outputURL.lastPathComponent)")

                if appState.conversionSettings.deleteOriginalsAfterConvert {
                    try? FileManager.default.removeItem(at: destURL)
                    FileManager.default.createFile(atPath: receiptURL.path, contents: nil)
                }
            } else {
                updateTask(id: task.id, phase: .error, errorMessage: "Conversion failed")
                appState.log("  ❌ Conversion failed: \(fileName)")
            }
        }
    }

    // MARK: - Task helpers
    @discardableResult
    private func addTask(fileName: String, deckName: String) -> SyncTask {
        let task = SyncTask(fileName: fileName, deckName: deckName)
        appState.activeTasks.append(task)
        return task
    }

    private func updateTask(
        id: UUID,
        phase: SyncTask.Phase? = nil,
        syncProgress: Double? = nil,
        convertProgress: Double? = nil,
        errorMessage: String? = nil
    ) {
        guard let i = appState.activeTasks.firstIndex(where: { $0.id == id }) else { return }
        if let p = phase           { appState.activeTasks[i].phase           = p }
        if let s = syncProgress    { appState.activeTasks[i].syncProgress    = s }
        if let c = convertProgress { appState.activeTasks[i].convertProgress = c }
        if let e = errorMessage    { appState.activeTasks[i].errorMessage    = e }
    }
}
