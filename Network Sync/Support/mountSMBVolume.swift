import Foundation

// Mounts an SMB share using osascript (no root needed, same as Finder).
// Returns true if the volume is already mounted OR mounts successfully.
@discardableResult
func mountSMBVolume(location: SyncLocation) async -> Bool {
    let mountPath = location.mountPath

    // Already mounted?
    if FileManager.default.fileExists(atPath: mountPath) { return true }

    let script = """
    mount volume "smb://\(location.ipAddress)/\(location.volumeName)" \
    as user name "\(location.username)" with password "\(location.password)"
    """

    return await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            do {
                try process.run()
                process.waitUntilExit()
                // Give Finder a moment to mount
                Thread.sleep(forTimeInterval: 2)
                let mounted = FileManager.default.fileExists(atPath: mountPath)
                continuation.resume(returning: mounted)
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
}

func isSMBMounted(location: SyncLocation) -> Bool {
    FileManager.default.fileExists(atPath: location.mountPath)
}
