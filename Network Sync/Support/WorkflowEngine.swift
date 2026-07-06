import Foundation
import Combine

/// Runs a user-defined `Workflow`: for each target device, executes the
/// workflow's steps in order, passing the current working set of local
/// files from one step to the next (sync produces files, convert/rename
/// transform them, format/cleanup act independently of them).
@MainActor
final class WorkflowEngine: ObservableObject {
    static let shared = WorkflowEngine()

    private let appState = AppState.shared

    /// Per-deck state threaded through a workflow's steps.
    private struct StepContext {
        let deck: HyperDeck
        let destDir: URL
        var files: [URL] = []
    }

    // MARK: - Run (all target devices)

    func run(_ workflow: Workflow) async {
        await start(workflow, decks: targetDecks(for: workflow))
    }

    // MARK: - Run (single device)
    // Runs the workflow's steps against exactly one device, regardless of
    // that workflow's own target list — used by the per-device "Run
    // Workflow" action on the Dashboard.

    func runDevice(_ workflow: Workflow, deck: HyperDeck) async {
        await start(workflow, decks: [deck])
    }

    // MARK: - Shared run loop

    private func start(_ workflow: Workflow, decks: [HyperDeck]) async {
        guard !appState.isRunning else { return }
        appState.isRunning = true
        appState.beginRun()
        appState.log("▶ Workflow started: \(workflow.name)")

        guard !decks.isEmpty else {
            appState.log("⚠️ No devices configured for this workflow")
            finishRun(workflow: workflow)
            return
        }

        if workflow.needsDestinationMount {
            appState.log("Mounting \(appState.syncLocation.volumeName)...")
            do {
                let resolvedPath = try await mountSMBVolume(location: appState.syncLocation)
                appState.syncLocation.resolvedMountPath = resolvedPath
                appState.log("✅ Mounted at \(resolvedPath)")
            } catch {
                appState.log("❌ \(error.localizedDescription)")
                appState.mountError = error.localizedDescription
                appState.currentRunErrors += 1
                appState.isRunning = false
                appState.commitRun()
                return
            }
        }

        for deck in decks {
            guard appState.isRunning else { break }
            if !appState.currentRunDecks.contains(deck.name) {
                appState.currentRunDecks.append(deck.name)
            }

            let destDir = URL(fileURLWithPath: appState.syncLocation.recordsPath)
                .appendingPathComponent(deck.name)
            try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

            var context = StepContext(deck: deck, destDir: destDir)
            appState.log("— \(deck.name) —")

            for step in workflow.steps {
                guard appState.isRunning else { break }
                await execute(step, context: &context)
            }
        }

        finishRun(workflow: workflow)
    }

    func stop() {
        appState.isRunning = false
        appState.log("⏹ Workflow stopped by user")
        appState.commitRun()
    }

    // MARK: - Step dispatch

    private func execute(_ step: WorkflowStep, context: inout StepContext) async {
        switch step.action {
        case .record(let stopAfterMinutes):
            await runRecord(context: &context, stopAfterMinutes: stopAfterMinutes)
        case .sync:
            await runSync(context: &context)
        case .convert(let preset, let deleteOriginal):
            await runConvert(context: &context, preset: preset, deleteOriginal: deleteOriginal)
        case .rename(let pattern):
            runRename(context: &context, pattern: pattern)
        case .format:
            await runFormat(context: &context)
        case .cleanup(let retentionDays):
            await runCleanup(context: &context, retentionDays: retentionDays)
        }
    }

    // MARK: - Sync step

    private func runSync(context: inout StepContext) async {
        let deck = context.deck
        appState.log("  📡 Scanning \(deck.name) (\(deck.ipAddress))...")

        let remoteFiles = await FTPService.listMovFiles(on: deck)
        guard !remoteFiles.isEmpty else {
            appState.log("  \(deck.name): no .mov files found")
            return
        }
        appState.log("  \(deck.name): \(remoteFiles.count) file(s) found")

        for fileName in remoteFiles {
            guard appState.isRunning else { return }

            let destURL = context.destDir.appendingPathComponent(fileName)
            let convertedURL = context.destDir
                .appendingPathComponent("Converted")
                .appendingPathComponent((fileName as NSString).deletingPathExtension + ".mp4")

            if FileManager.default.fileExists(atPath: convertedURL.path) {
                appState.log("  ⏭ \(fileName) already processed")
                appState.currentRunSkipped += 1
                continue
            }

            let task = addTask(fileName: fileName, deckName: deck.name)
            updateTask(id: task.id, phase: .downloading, syncProgress: 0)
            appState.log("  ⬇ Downloading \(fileName)...")

            var result = await FTPService.downloadFile(
                named: fileName, from: deck, to: destURL
            ) { [weak self] pct in Task { @MainActor in self?.updateTask(id: task.id, syncProgress: pct) } }

            if !result.success {
                appState.log("  ↩ Retrying \(fileName)... (\(result.failureReason ?? "unknown error"))")
                try? FileManager.default.removeItem(at: destURL)
                result = await FTPService.downloadFile(
                    named: fileName, from: deck, to: destURL
                ) { [weak self] pct in Task { @MainActor in self?.updateTask(id: task.id, syncProgress: pct) } }
            }

            guard result.success else {
                let reason = result.failureReason ?? "unknown error"
                updateTask(id: task.id, phase: .error, errorMessage: "Download failed after retry: \(reason)")
                appState.log("  ❌ Download failed: \(fileName) — \(reason)")
                appState.currentRunErrors += 1
                continue
            }

            updateTask(id: task.id, phase: .done, syncProgress: 1)
            appState.log("  ✅ Downloaded \(fileName)")
            context.files.append(destURL)
        }
    }

    // MARK: - Convert step

    private func runConvert(context: inout StepContext, preset: ConversionSettings.FFmpegPreset, deleteOriginal: Bool) async {
        guard !context.files.isEmpty else {
            appState.log("  ⏭ Convert: no files to convert")
            return
        }

        let settings: ConversionSettings = {
            var s = appState.conversionSettings
            s.preset = preset
            return s
        }()

        let convertedDir = context.destDir.appendingPathComponent("Converted")
        try? FileManager.default.createDirectory(at: convertedDir, withIntermediateDirectories: true)

        let maxJobs = appState.conversionSettings.maxParallelConversions
        let batches = stride(from: 0, to: context.files.count, by: maxJobs).map {
            Array(context.files[$0 ..< min($0 + maxJobs, context.files.count)])
        }

        var convertedFiles: [URL] = []

        for batch in batches {
            guard appState.isRunning else { break }

            let results: [(input: URL, output: URL, ok: Bool)] = await withTaskGroup(of: (URL, URL, Bool).self) { group in
                for inputURL in batch {
                    group.addTask {
                        let fileName  = inputURL.lastPathComponent
                        let outputURL = convertedDir.appendingPathComponent(
                            (fileName as NSString).deletingPathExtension + ".mp4"
                        )
                        let taskID = await MainActor.run {
                            self.appState.activeTasks.first { $0.fileName == fileName }?.id
                        }
                        await MainActor.run {
                            self.appState.log("  🎬 Converting \(fileName)...")
                            if let id = taskID { self.updateTask(id: id, phase: .converting, convertProgress: 0) }
                        }

                        let ok = await ConversionService.convert(
                            input: inputURL, output: outputURL, settings: settings
                        ) { pct in
                            if let id = taskID {
                                Task { @MainActor in self.updateTask(id: id, convertProgress: pct) }
                            }
                        }

                        await MainActor.run {
                            if ok, let id = taskID { self.updateTask(id: id, phase: .done, convertProgress: 1) }
                            if !ok, let id = taskID { self.updateTask(id: id, phase: .error, errorMessage: "Conversion failed") }
                        }
                        return (inputURL, outputURL, ok)
                    }
                }
                var collected: [(URL, URL, Bool)] = []
                for await result in group { collected.append(result) }
                return collected
            }

            for (input, output, ok) in results {
                if ok {
                    appState.log("  ✅ Converted → \(output.lastPathComponent)")
                    appState.currentRunConverted += 1
                    convertedFiles.append(output)
                    if deleteOriginal { try? FileManager.default.removeItem(at: input) }
                } else {
                    appState.log("  ❌ Conversion failed: \(input.lastPathComponent)")
                    appState.currentRunErrors += 1
                    if !deleteOriginal { convertedFiles.append(input) }
                }
            }
        }

        context.files = convertedFiles
    }

    // MARK: - Rename step

    private func runRename(context: inout StepContext, pattern: String) {
        guard !context.files.isEmpty else {
            appState.log("  ⏭ Rename: no files to rename")
            return
        }

        var renamed: [URL] = []

        for (index, url) in context.files.enumerated() {
            let ext = url.pathExtension
            let originalName = (url.lastPathComponent as NSString).deletingPathExtension

            let newName = RenamePatternEngine.apply(
                pattern: pattern,
                originalName: originalName,
                deviceName: context.deck.name,
                index: index + 1
            )
            let newURL = url.deletingLastPathComponent().appendingPathComponent("\(newName).\(ext)")

            do {
                if FileManager.default.fileExists(atPath: newURL.path) {
                    try FileManager.default.removeItem(at: newURL)
                }
                try FileManager.default.moveItem(at: url, to: newURL)
                appState.log("  ✏️ Renamed → \(newURL.lastPathComponent)")
                renamed.append(newURL)
            } catch {
                appState.log("  ❌ Rename failed for \(url.lastPathComponent): \(error.localizedDescription)")
                appState.currentRunErrors += 1
                renamed.append(url)
            }
        }

        context.files = renamed
    }

    // MARK: - Record step

    private func runRecord(context: inout StepContext, stopAfterMinutes: Int?) async {
        let deck = context.deck
        appState.log("  ⏺ Starting recording on \(deck.name)...")

        let service = HyperDeckService(host: deck.ipAddress)
        await service.record()
        if let error = service.lastError {
            appState.log("  ❌ \(deck.name) failed to start recording: \(error)")
            appState.currentRunErrors += 1
            return
        }
        appState.log("  ✅ \(deck.name) is recording")

        guard let minutes = stopAfterMinutes else { return }

        appState.log("  ⏳ Will stop \(deck.name) after \(minutes) minute\(minutes == 1 ? "" : "s")...")
        try? await Task.sleep(for: .seconds(minutes * 60))
        guard appState.isRunning else { return }

        await service.stop()
        if let error = service.lastError {
            appState.log("  ❌ \(deck.name) failed to stop recording: \(error)")
            appState.currentRunErrors += 1
        } else {
            appState.log("  ⏹ \(deck.name) stopped recording")
        }
    }

    // MARK: - Format step

    private func runFormat(context: inout StepContext) async {
        appState.log("  🗑 Formatting \(context.deck.name) (\(context.deck.ipAddress))...")
        do {
            try await HyperDeckService.formatDrive(deck: context.deck)
            appState.log("  ✅ \(context.deck.name) formatted successfully")
        } catch {
            appState.log("  ❌ \(context.deck.name) format failed: \(error.localizedDescription)")
            appState.currentRunErrors += 1
        }
    }

    // MARK: - Cleanup step

    private func runCleanup(context: inout StepContext, retentionDays: Int) async {
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86400)
        let base = context.destDir
        appState.log("  🧹 Cleaning files older than \(retentionDays) day(s)...")

        let deletedCount = await Task.detached(priority: .background) {
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(
                at: base,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { return 0 }

            var deleted = 0
            let urls = enumerator.compactMap { $0 as? URL }
            for url in urls {
                guard !url.hasDirectoryPath else { continue }
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

    // MARK: - Finish

    private func finishRun(workflow: Workflow) {
        appState.syncLocation.resolvedMountPath = nil
        appState.isRunning = false
        let c = appState.currentRunConverted
        let e = appState.currentRunErrors
        appState.log("✅ Workflow finished — \(c) processed, \(e) errors")

        let run = WorkflowRun(
            workflowName:   workflow.name,
            startedAt:      appState.currentRunStart,
            finishedAt:     Date(),
            processed:      c,
            errors:         e,
            decksProcessed: appState.currentRunDecks,
            log:            appState.pipelineLog
        )
        appState.workflowRunHistory.insert(run, at: 0)
        if appState.workflowRunHistory.count > 50 {
            appState.workflowRunHistory = Array(appState.workflowRunHistory.prefix(50))
        }

        appState.commitRun()
        NotificationService.sendCompletion(converted: c, errors: e)
        Task { await EmailNotificationService.sendSyncComplete(converted: c, errors: e) }
    }

    // MARK: - Helpers

    private func targetDecks(for workflow: Workflow) -> [HyperDeck] {
        guard !workflow.targetDeckIDs.isEmpty else { return appState.hyperDecks }
        return appState.hyperDecks.filter { workflow.targetDeckIDs.contains($0.id) }
    }

    private func mountSMBVolume(location: SyncLocation) async throws -> String {
        try await SMBService.mountAndResolve(
            ip:       location.ipAddress,
            volume:   location.volumeName,
            username: location.username,
            password: location.password
        )
    }

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
