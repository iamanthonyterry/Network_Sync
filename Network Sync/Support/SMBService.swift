import Foundation

enum SMBService {

    // MARK: - Primary API

    /// Mount an SMB share and return the actual /Volumes path where it landed.
    /// macOS may mount the share under a different name than stored
    /// (e.g. "LP-Service-Backup" → "LP Service Backup"), so we resolve the
    /// real path by diffing /Volumes before/after and by querying the volume's
    /// remount URL rather than trusting the stored volume name.
    static func mountAndResolve(
        ip: String,
        volume: String,
        username: String,
        password: String
    ) async -> String? {

        // 1. Snapshot /Volumes before attempting anything
        let before = Set(volumeNames())

        // 2. Already mounted at the exact stored name?
        let exactPath = "/Volumes/\(volume)"
        if FileManager.default.fileExists(atPath: exactPath) {
            print("[SMBService] Already mounted at \(exactPath)")
            return exactPath
        }

        // 3. Already mounted under a different name for this IP?
        if let existing = resolveByIP(ip) {
            print("[SMBService] Found existing mount for \(ip): \(existing)")
            return existing
        }

        // 4. Attempt to mount via osascript
        print("[SMBService] Mounting smb://\(ip)/\(volume) as \(username)...")
        let success = await runMount(ip: ip, volume: volume, username: username, password: password)

        // Give macOS time to register the mount (or settle after a failed attempt)
        let delay: Duration = success ? .milliseconds(1500) : .seconds(1)
        try? await Task.sleep(for: delay)

        // 5. New entry in /Volumes? That's our mount.
        let after = Set(volumeNames())
        let newEntries = after.subtracting(before)
        print("[SMBService] New /Volumes entries: \(newEntries.sorted())")

        if let newVol = newEntries.first {
            let resolved = "/Volumes/\(newVol)"
            print("[SMBService] Resolved → \(resolved)")
            return resolved
        }

        // 6. Last resort: re-scan by IP (covers already-mounted edge cases)
        if let found = resolveByIP(ip) {
            print("[SMBService] Resolved via IP scan → \(found)")
            return found
        }

        print("[SMBService] ✗ Mount failed — /Volumes: \(volumeNames().joined(separator: ", "))")
        return nil
    }

    /// Convenience wrapper for a CloudStore.
    static func mount(store: CloudStore) async -> String? {
        await mountAndResolve(
            ip:       store.ipAddress,
            volume:   store.volumeName,
            username: store.username,
            password: store.password
        )
    }

    // MARK: - Private helpers

    private static func volumeNames() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: "/Volumes")) ?? []
    }

    private static func runMount(
        ip: String, volume: String, username: String, password: String
    ) async -> Bool {
        let script = """
            mount volume "smb://\(ip)/\(volume)" \
            as user name "\(username)" with password "\(password)"
            """

        return await withCheckedContinuation { continuation in
            let stderrPipe = Pipe()
            let process    = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments     = ["-e", script]
            process.standardError = stderrPipe

            process.terminationHandler = { proc in
                let stderr = String(
                    data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                print("[SMBService] osascript exit: \(proc.terminationStatus)")
                if !stderr.isEmpty { print("[SMBService] stderr: \(stderr)") }
                continuation.resume(returning: proc.terminationStatus == 0)
            }

            do {
                try process.run()
            } catch {
                print("[SMBService] Failed to launch osascript: \(error)")
                continuation.resume(returning: false)
            }
        }
    }

    /// Return the /Volumes path of any currently-mounted volume whose remount URL
    /// hostname matches `ip`. Handles macOS volume-name canonicalisation.
    private static func resolveByIP(_ ip: String) -> String? {
        for vol in volumeNames() {
            let url = URL(fileURLWithPath: "/Volumes/\(vol)")
            if let remount = try? url.resourceValues(forKeys: [.volumeURLForRemountingKey]).volumeURLForRemounting,
               remount.host == ip {
                return "/Volumes/\(vol)"
            }
        }
        return nil
    }
}
