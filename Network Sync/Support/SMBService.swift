import Foundation
import NetFS

enum SMBService {

    // MARK: - Primary API

    /// Mount an SMB share and return the actual /Volumes path where it landed.
    /// Uses NetFS (sandbox-safe) instead of osascript.
    static func mountAndResolve(
        ip: String,
        volume: String,
        username: String,
        password: String
    ) async -> String? {

        // 1. Already mounted at exact stored name?
        let exactPath = "/Volumes/\(volume)"
        if FileManager.default.fileExists(atPath: exactPath) {
            print("[SMBService] Already mounted at \(exactPath)")
            return exactPath
        }

        // 2. Already mounted under a different name for this IP?
        if let existing = resolveByIP(ip) {
            print("[SMBService] Found existing mount for \(ip): \(existing)")
            return existing
        }

        // 3. Snapshot /Volumes before mounting
        let before = Set(volumeNames())

        // 4. Mount via NetFS
        print("[SMBService] Mounting smb://\(ip)/\(volume) as \(username)…")
        let success = await runMount(ip: ip, volume: volume, username: username, password: password)

        let delay: Duration = success ? .milliseconds(1500) : .seconds(1)
        try? await Task.sleep(for: delay)

        // 5. New /Volumes entry?
        let after = Set(volumeNames())
        let newEntries = after.subtracting(before)
        print("[SMBService] New /Volumes entries: \(newEntries.sorted())")

        if let newVol = newEntries.first {
            let resolved = "/Volumes/\(newVol)"
            print("[SMBService] Resolved → \(resolved)")
            return resolved
        }

        // 6. Last resort: re-scan by IP
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

    /// Mount using NetFS — the sandbox-approved way to mount SMB shares.
    private static func runMount(
        ip: String, volume: String, username: String, password: String
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            guard let url = URL(string: "smb://\(ip)/\(volume)") else {
                continuation.resume(returning: false)
                return
            }

            let openOptions: NSMutableDictionary = [
                kNetFSUseGuestKey: false,
                kNetFSNoUserPreferencesKey: true   // suppress interactive auth dialogs
            ]
            let mountOptions: NSMutableDictionary = [
                kNetFSAllowLoopbackKey: false,
                kNetFSSoftMountKey: true
            ]

            var mountpoints: Unmanaged<CFArray>?

            let status = NetFSMountURLSync(
                url as CFURL,
                nil,
                username as CFString,
                password as CFString,
                openOptions,
                mountOptions,
                &mountpoints
            )

            if status == 0 {
                print("[SMBService] NetFS mount succeeded")
                continuation.resume(returning: true)
            } else {
                print("[SMBService] NetFS mount failed, status: \(status)")
                continuation.resume(returning: false)
            }
        }
    }

    /// Return the /Volumes path of any currently-mounted volume whose remount URL
    /// hostname matches `ip`.
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
