import Foundation
import SwiftUI

// MARK: - Step Kind
// The catalog of step types users can drag into a workflow.
enum StepKind: String, Codable, CaseIterable, Identifiable {
    case sync, convert, rename, format, cleanup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sync:    return "Sync"
        case .convert: return "Convert"
        case .rename:  return "Rename"
        case .format:  return "Format Drive"
        case .cleanup: return "Cleanup"
        }
    }

    var subtitle: String {
        switch self {
        case .sync:    return "Download new files from the device"
        case .convert: return "Transcode files to MP4"
        case .rename:  return "Rename files using a pattern"
        case .format:  return "Erase the device's drive"
        case .cleanup: return "Delete files older than N days"
        }
    }

    var icon: String {
        switch self {
        case .sync:    return "arrow.down.circle"
        case .convert: return "film.stack"
        case .rename:  return "textformat"
        case .format:  return "externaldrive.badge.xmark"
        case .cleanup: return "trash"
        }
    }

    var color: Color {
        switch self {
        case .sync:    return .blue
        case .convert: return .orange
        case .rename:  return .purple
        case .format:  return .red
        case .cleanup: return .gray
        }
    }
}

// MARK: - Step Action
// Each case carries only the configuration that step needs.
enum StepAction: Codable, Hashable {
    case sync
    case convert(preset: ConversionSettings.FFmpegPreset, deleteOriginal: Bool)
    case rename(pattern: String)
    case format
    case cleanup(retentionDays: Int)

    var kind: StepKind {
        switch self {
        case .sync:     return .sync
        case .convert:  return .convert
        case .rename:   return .rename
        case .format:   return .format
        case .cleanup:  return .cleanup
        }
    }

    static func defaultAction(for kind: StepKind) -> StepAction {
        switch kind {
        case .sync:    return .sync
        case .convert: return .convert(preset: .fast, deleteOriginal: true)
        case .rename:  return .rename(pattern: "{device}_{date}_{index}")
        case .format:  return .format
        case .cleanup: return .cleanup(retentionDays: 30)
        }
    }

    /// One-line summary shown under the step title in the editor.
    var summary: String {
        switch self {
        case .sync:
            return "Downloads any new .mov files"
        case .convert(let preset, let deleteOriginal):
            return "\(preset.displayName) preset" + (deleteOriginal ? " · deletes original" : " · keeps original")
        case .rename(let pattern):
            return "Pattern: \(pattern)"
        case .format:
            return "Permanently erases all files on the device"
        case .cleanup(let days):
            return "Deletes files older than \(days) day\(days == 1 ? "" : "s")"
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
        steps.contains { $0.kind != .format }
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
        if s < 60 { return "\(s)s" }
        let m = s / 60; let r = s % 60
        return r == 0 ? "\(m)m" : "\(m)m \(r)s"
    }
}
