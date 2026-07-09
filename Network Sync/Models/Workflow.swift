import Foundation
import SwiftUI

// MARK: - Step Kind
// The catalog of step types users can drag into a workflow.
enum StepKind: String, Codable, CaseIterable, Identifiable {
    case record, sync, convert, rename, format, cleanup, notify

    var id: String { rawValue }

    var title: String {
        switch self {
        case .record:  return "Record"
        case .sync:    return "Sync"
        case .convert: return "Convert"
        case .rename:  return "Rename"
        case .format:  return "Format Drive"
        case .cleanup: return "Cleanup"
        case .notify:  return "Notification"
        }
    }

    var subtitle: String {
        switch self {
        case .record:  return "Start recording on the device"
        case .sync:    return "Download new files from the device"
        case .convert: return "Transcode files to MP4"
        case .rename:  return "Rename files using a pattern"
        case .format:  return "Permanently erase the device's drive"
        case .cleanup: return "Delete files older than N days in the destination folder"
        case .notify:  return "Send an email"
        }
    }

    var icon: String {
        switch self {
        case .record:  return "record.circle"
        case .sync:    return "arrow.down.circle"
        case .convert: return "film.stack"
        case .rename:  return "textformat"
        case .format:  return "externaldrive.badge.xmark"
        case .cleanup: return "trash"
        case .notify:  return "envelope"
        }
    }

    var color: Color {
        switch self {
        case .record:  return .red
        case .sync:    return .blue
        case .convert: return .orange
        case .rename:  return .purple
        case .format:  return .red
        case .cleanup: return .gray
        case .notify:  return .teal
        }
    }
}

// MARK: - Step Action
// Each case carries only the configuration that step needs.
enum StepAction: Codable, Hashable {
    case record(stopAfterMinutes: Int?)
    case sync
    case convert(preset: ConversionSettings.FFmpegPreset, deleteOriginal: Bool)
    case rename(pattern: String)
    case format
    case cleanup(retentionDays: Int)
    case notify(header: String, message: String, recipients: [NotificationRecipient])

    var kind: StepKind {
        switch self {
        case .record:   return .record
        case .sync:     return .sync
        case .convert:  return .convert
        case .rename:   return .rename
        case .format:   return .format
        case .cleanup:  return .cleanup
        case .notify:   return .notify
        }
    }

    static func defaultAction(for kind: StepKind) -> StepAction {
        switch kind {
        case .record:  return .record(stopAfterMinutes: nil)
        case .sync:    return .sync
        case .convert: return .convert(preset: .fast, deleteOriginal: true)
        case .rename:  return .rename(pattern: "{device}_{date}_{index}")
        case .format:  return .format
        case .cleanup: return .cleanup(retentionDays: 30)
        case .notify:  return .notify(header: "Workflow update", message: "", recipients: [])
        }
    }

    /// One-line summary shown under the step title in the editor.
    var summary: String {
        switch self {
        case .record(let stopAfterMinutes):
            if let minutes = stopAfterMinutes {
                return "Records, then stops after \(minutes) minute\(minutes == 1 ? "" : "s")"
            }
            return "Starts recording and continues to the next step"
        case .sync:
            return "Downloads any new .mov files"
        case .convert(let preset, let deleteOriginal):
            return "\(preset.displayName) preset" + (deleteOriginal ? " · deletes original" : " · keeps original")
        case .rename(let pattern):
            return "Pattern: \(pattern)"
        case .format:
            return "Erases the device's drive — cannot be undone"
        case .cleanup(let days):
            return "Deletes files older than \(days) day\(days == 1 ? "" : "s") in the destination folder"
        case .notify(let header, _, let recipients):
            let who = recipients.isEmpty ? "no recipients set" : "\(recipients.count) recipient\(recipients.count == 1 ? "" : "s")"
            return "\"\(header)\" → \(who)"
        }
    }
}

// MARK: - Rename Tokens
// Supported tokens for the rename step's pattern field.
enum RenameToken: String, CaseIterable {
    case name   = "{name}"
    case device = "{device}"
    case date   = "{date}"
    case time   = "{time}"
    case index  = "{index}"

    var label: String {
        switch self {
        case .name:   return "Original name"
        case .device: return "Device name"
        case .date:   return "Date (yyyyMMdd)"
        case .time:   return "Time (HHmmss)"
        case .index:  return "File number"
        }
    }
}

// MARK: - Rename Pattern Engine
// Single source of truth for turning a pattern + file info into a final
// name — used by both the live preview in the editor and the real run.
enum RenamePatternEngine {
    static func apply(
        pattern: String,
        originalName: String,
        deviceName: String,
        index: Int,
        date: Date = Date()
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let dateString = formatter.string(from: date)
        formatter.dateFormat = "HHmmss"
        let timeString = formatter.string(from: date)

        let result = pattern
            .replacingOccurrences(of: RenameToken.name.rawValue, with: originalName)
            .replacingOccurrences(of: RenameToken.device.rawValue, with: deviceName)
            .replacingOccurrences(of: RenameToken.date.rawValue, with: dateString)
            .replacingOccurrences(of: RenameToken.time.rawValue, with: timeString)
            .replacingOccurrences(of: RenameToken.index.rawValue, with: String(format: "%03d", index))

        return result.isEmpty ? originalName : result
    }
}

// MARK: - Workflow Step
struct WorkflowStep: Identifiable, Codable, Hashable {
    var id = UUID()
    var action: StepAction
    var kind: StepKind { action.kind }
}

// MARK: - Workflow
struct Workflow: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var steps: [WorkflowStep] = []
    /// Which HyperDecks this workflow runs against. Empty = all configured decks.
    var targetDeckIDs: [UUID] = []
    var schedule: ScheduleSettings = ScheduleSettings()
    var sortOrder: Int = 0

    var stepsSummary: String {
        steps.isEmpty ? "No steps yet" : steps.map(\.kind.title).joined(separator: "  →  ")
    }

    /// True if any step needs the shared sync destination mounted.
    var needsDestinationMount: Bool {
        steps.contains { $0.kind != .format && $0.kind != .record && $0.kind != .notify }
    }
}

// MARK: - Workflow Run History (persisted)
struct WorkflowRun: Identifiable, Codable, Hashable {
    var id = UUID()
    var workflowName: String
    var startedAt: Date
    var finishedAt: Date
    var processed: Int
    var errors: Int
    var decksProcessed: [String]
    var log: [String]

    var duration: TimeInterval { finishedAt.timeIntervalSince(startedAt) }
    var durationFormatted: String {
        let s = Int(duration)
        let h = s / 3600
        let m = (s % 3600) / 60
        let r = s % 60
        return String(format: "%d:%02d:%02d", h, m, r)
    }
}
