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

        // Storage cleanup before new run
        await runStorageCleanup()

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

    // MARK: - Retry failed tasks
    func retryFailed() async {
        let failed = appState.failedTasks
        guard !failed.isEmpty, !appState.isRunning else { return }
        appState.isRunning = true
        appState.log("↩ Retrying \(failed.count) failed file(s)...")

        let mounted = await mountSMBVolume(location: appState.syncLocation)
        guard mounted else {
            appState.log("❌ Could not mount SMB volume.")
            appState.isRunning = false
            return
        }

        // Group failed tasks by deck name
        let byDeck = Dictionary(grouping: failed, by: \.deckName)
        for (deckName, tasks) in byDeck {
            guard let deck = appState.hyperDecks.first(where: { $0.name == deckName }) else { continue }
            let deckDestDir = URL(fileURLWithPath: appState.syncLocation.recordsPath)
                .appendingPathComponent(deckName)
            var toConvert: [URL] = []

            for task in tasks {
                // Reset task state
                if let i = appState.activeTasks.firstIndex(where: { $0.id == task.id }) {
                    appState.activeTasks[i].phase           = .downloading
                    appState.activeTasks[i].syncProgress    = 0
                    appState.activeTasks[i].convertProgress = 0
                    appState.activeTasks[i].errorMessage    = nil
                }

                let destURL = deckDestDir.appendingPathComponent(task.fileName)
                try? FileManager.default.removeItem(at: destURL)

                let ok = await FTPService.downloadFile(
                    named: task.fileName, from: deck, to: destURL
                ) { [weak self] pct in self?.updateTask(id: task.id, syncProgress: pct) }

                if ok {
                    updateTask(id: task.id, phase: .converting, syncProgress: 1)
                    toConvert.append(destURL)
                } else {
                    updateTask(id: task.id, phase: .error, errorMessage: "Retry failed")
                    appState.currentRunErrors += 1
                }
            }

            if !toConvert.isEmpty {
                await convertInParallel(files: toConvert, deckDestDir: deckDestDir)
            }
        }

        appState.isRunning = false
        appState.log("↩ Retry complete")
    }

    // MARK: - Stop
    func stop() {
        appState.isRunning = false
        appState.log("⏹ Pipeline stopped by user")
        appState.commitRun()
    }

    // MARK: - Storage cleanup (retention policy)
    private func runStorageCleanup() async {
        let days = appState.conversionSettings.retentionDays
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        let base = URL(fileURLWithPath: appState.syncLocation.recordsPath)
        appState.log("🧹 Running \(days)-day retention cleanup...")

        let deletedCount = await Task.detached(priority: .background) {
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(
                at: base,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { return 0 }

            // Collect URLs first to avoid iterating NSEnumerator in async context
            let urls = enumerator.compactMap { $0 as? URL }

            var deleted = 0
            for url in urls {
                guard url.pathExtension.lowercased() == "mp4" ||
                      url.lastPathComponent.hasSuffix(".done") else { continue }
                if let mod = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   mod < cutoff {
                    try? fm.removeItem(at: url)
                    deleted += 1
                }
            }
            return deleted
        }.value

        appState.log("  🗑 Cleanup removed \(deletedCount) old file(s)")
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

        // Download all files for this deck sequentially
        var filesToConvert: [URL] = []

        for fileName in remoteFiles {
            guard appState.isRunning else { return }

            let destURL    = deckDestDir.appendingPathComponent(fileName)
            let receiptURL = deckDestDir.appendingPathComponent(fileName + ".done")
            let convertedURL = deckDestDir
                .appendingPathComponent("Converted")
                .appendingPathComponent((fileName as NSString).deletingPathExtension + ".mp4")

            if FileManager.default.fileExists(atPath: convertedURL.path) ||
               FileManager.default.fileExists(atPath: receiptURL.path) {
                appState.log("  ⏭ \(fileName) already processed")
                appState.currentRunSkipped += 1
                continue
            }

            // Download (with 1 retry on failure)
            let task = addTask(fileName: fileName, deckName: deck.name)
            updateTask(id: task.id, phase: .downloading, syncProgress: 0)
            appState.log("  ⬇ Downloading \(fileName)...")

            var downloaded = await FTPService.downloadFile(
                named: fileName, from: deck, to: destURL
            ) { [weak self] pct in self?.updateTask(id: task.id, syncProgress: pct) }

            if !downloaded {
                appState.log("  ↩ Retrying \(fileName)...")
                try? FileManager.default.removeItem(at: destURL)
                downloaded = await FTPService.downloadFile(
                    named: fileName, from: deck, to: destURL
                ) { [weak self] pct in self?.updateTask(id: task.id, syncProgress: pct) }
            }

            guard downloaded else {
                updateTask(id: task.id, phase: .error, errorMessage: "Download failed after retry")
                appState.log("  ❌ Download failed: \(fileName)")
                appState.currentRunErrors += 1
                continue
            }

            updateTask(id: task.id, phase: .converting, syncProgress: 1)
            appState.log("  ✅ Downloaded \(fileName)")
            filesToConvert.append(destURL)
        }

        // Convert with parallelism
        guard !filesToConvert.isEmpty, appState.isRunning else { return }
        await convertInParallel(files: filesToConvert, deckDestDir: deckDestDir)
    }

    // MARK: - Parallel conversion
    private func convertInParallel(files: [URL], deckDestDir: URL) async {
        let maxJobs = appState.conversionSettings.maxParallelConversions
        let convertedDir = deckDestDir.appendingPathComponent("Converted")
        try? FileManager.default.createDirectory(at: convertedDir, withIntermediateDirectories: true)

        // Chunk into batches of maxJobs
        let batches = stride(from: 0, to: files.count, by: maxJobs).map {
            Array(files[$0 ..< min($0 + maxJobs, files.count)])
        }

        for batch in batches {
            guard appState.isRunning else { return }

            await withTaskGroup(of: Void.self) { group in
                for inputURL in batch {
                    group.addTask {
                        let fileName  = inputURL.lastPathComponent
                        let outputURL = convertedDir.appendingPathComponent(
                            (fileName as NSString).deletingPathExtension + ".mp4"
                        )
                        let receiptURL = inputURL.deletingLastPathComponent()
                            .appendingPathComponent(fileName + ".done")

                        // Find matching task
                        let taskID = await MainActor.run {
                            self.appState.activeTasks.first { $0.fileName == fileName }?.id
                        }

                        await MainActor.run {
                            self.appState.log("  🎬 Converting \(fileName)...")
                        }

                        let ok = await ConversionService.convert(
                            input: inputURL,
                            output: outputURL,
                            settings: self.appState.conversionSettings
                        ) { pct in
                            if let id = taskID {
                                Task { @MainActor in
                                    self.updateTask(id: id, convertProgress: pct)
                                }
                            }
                        }

                        await MainActor.run {
                            if ok {
                                if let id = taskID {
                                    self.updateTask(id: id, phase: .done, convertProgress: 1)
                                }
                                self.appState.log("  ✅ Converted → \(outputURL.lastPathComponent)")
                                self.appState.currentRunConverted += 1
                                if self.appState.conversionSettings.deleteOriginalsAfterConvert {
                                    try? FileManager.default.removeItem(at: inputURL)
                                    FileManager.default.createFile(atPath: receiptURL.path, contents: nil)
                                }
                            } else {
                                if let id = taskID {
                                    self.updateTask(id: id, phase: .error, errorMessage: "Conversion failed")
                                }
                                self.appState.log("  ❌ Conversion failed: \(fileName)")
                                self.appState.currentRunErrors += 1
                            }
                        }
                    }
                }
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
