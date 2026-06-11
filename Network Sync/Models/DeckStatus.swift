import Foundation

// MARK: - Deck Status
enum DeckStatus: String, Codable {
    case unknown, online, offline, syncing, transcoding
}

// MARK: - HyperDeck
struct HyperDeck: Identifiable, Codable {
    var id = UUID()
    var name: String
    var ipAddress: String
    var remotePath: String
    var username: String = "lpproduction"
    var password: String = "7404"
    var sortOrder: Int = 0
}

// MARK: - Sync Destination
struct SyncLocation: Codable {
    var ipAddress: String = "192.168.2.119"
    var volumeName: String = "lp service backup"
    var username: String = "guest"
    var password: String = "7404"
    var basePath: String = "ISO Records"

    var mountPath: String { "/Volumes/\(volumeName)" }
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
struct PipelineRun: Identifiable, Codable {
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
    var hour: Int = 2       // 2 AM default
    var minute: Int = 0
    var repeatDaily: Bool = true

    var displayTime: String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        let ampm = hour < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", h, minute, ampm)
    }
}
