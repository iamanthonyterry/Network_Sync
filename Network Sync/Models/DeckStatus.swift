import Foundation

// MARK: - Deck Status
enum DeckStatus: String, Codable {
    case unknown, online, offline, syncing, transcoding
}

// MARK: - HyperDeck
struct HyperDeck: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var ipAddress: String
    var remotePath: String
    var username: String = ""
    var password: String = ""
    var sortOrder: Int = 0
}

// MARK: - Blackmagic Switcher (ATEM)
struct BlackmagicSwitcher: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var ipAddress: String
    var model: String = ""
    var sortOrder: Int = 0

    static let controlPort: UInt16 = 9910
}

// MARK: - Blackmagic Cloud Store
struct CloudStore: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var ipAddress: String
    var volumeName: String = ""
    var username: String = ""
    var password: String = ""
    var sortOrder: Int = 0
}

// MARK: - Sync Destination
struct SyncLocation: Codable {
    var ipAddress: String = ""
    var volumeName: String = ""
    var username: String = ""
    var password: String = ""
    var basePath: String = "ISO Records"

    /// Resolved at runtime by SMBService after mounting — NOT persisted.
    /// macOS may mount the share under a different name than `volumeName`
    /// (e.g. "LP-Service-Backup" → "LP Service Backup"). This holds the real path.
    var resolvedMountPath: String? = nil

    enum CodingKeys: String, CodingKey {
        case ipAddress, volumeName, username, password, basePath
    }

    /// Actual /Volumes path — uses resolved path when available.
    var mountPath: String { resolvedMountPath ?? "/Volumes/\(volumeName)" }
    var recordsPath: String { "\(mountPath)/\(basePath)" }
}

// MARK: - Conversion Settings
struct ConversionSettings: Codable {
    var preset: FFmpegPreset = .ultrafast
    var crf: Int = 23
    var audioBitrate: String = "128k"
    var deleteOriginalsAfterConvert: Bool = true
    var maxParallelConversions: Int = 2
    var retentionDays: Int = 30

    enum FFmpegPreset: String, Codable, CaseIterable {
        case ultrafast, superfast, veryfast, faster, fast, medium
        var displayName: String { rawValue.capitalized }
        var description: String {
            switch self {
            case .ultrafast: return "Fastest encode, largest file"
            case .superfast: return "Very fast, slightly smaller"
            case .veryfast:  return "Good balance for bulk jobs"
            case .faster:    return "Better compression"
            case .fast:      return "Near-optimal quality"
            case .medium:    return "Best compression, slowest"
            }
        }
    }
}

// MARK: - Per-file sync task (live, in-memory only)
struct SyncTask: Identifiable {
    var id = UUID()
    var fileName: String
    var deckName: String
    var phase: Phase = .queued
    var syncProgress: Double = 0
    var convertProgress: Double = 0
    var errorMessage: String? = nil

    enum Phase: String {
        case queued, downloading, converting, done, error
        var label: String { rawValue.capitalized }
    }

    var overallProgress: Double {
        switch phase {
        case .queued:      return 0
        case .downloading: return syncProgress * 0.5
        case .converting:  return 0.5 + convertProgress * 0.5
        case .done:        return 1.0
        case .error:       return 0
        }
    }
}

// MARK: - Completed run history (persisted)
struct PipelineRun: Identifiable, Codable, Hashable {
    var id = UUID()
    var startedAt: Date
    var finishedAt: Date
    var converted: Int
    var skipped: Int
    var errors: Int
    var decksProcessed: [String]
    var log: [String]

    var duration: TimeInterval { finishedAt.timeIntervalSince(startedAt) }

    var durationFormatted: String {
        let s = Int(duration)
        if s < 60 { return "\(s)s" }
        let m = s / 60; let r = s % 60
        return r == 0 ? "\(m)m" : "\(m)m \(r)s"
    }
}

// MARK: - Schedule Settings
struct ScheduleSettings: Codable {
    var isEnabled: Bool = false
    var hour: Int = 2
    var minute: Int = 0
    var repeatDaily: Bool = true

    var displayTime: String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        let ampm = hour < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", h, minute, ampm)
    }
}
