import SwiftUI

/// Small focused sheet for configuring a single workflow step.
/// Only shows fields relevant to that step's kind.
struct WorkflowStepConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var step: WorkflowStep

    // Local editable copies so Cancel doesn't mutate the caller's step.
    @State private var preset: ConversionSettings.FFmpegPreset = .fast
    @State private var deleteOriginal = true
    @State private var pattern = ""
    @State private var retentionDays = 30

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(step.kind.title, systemImage: step.kind.icon)
                    .font(.title3).bold()
                    .foregroundStyle(step.kind.color)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()

            Form {
                Text(step.kind.subtitle)
                    .font(.caption).foregroundStyle(.secondary)

                switch step.kind {
                case .sync:
                    Text("No configuration needed — downloads any files not already synced.")
                        .font(.callout).foregroundStyle(.secondary)

                case .convert:
                    convertFields

                case .rename:
                    renameFields

                case .format:
                    Label("This will permanently erase all files on the device.", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.red)

                case .cleanup:
                    cleanupFields
                }
            }
            .formStyle(.grouped)
            .padding(.top, 4)
        }
        .frame(width: 420)
        .onAppear(perform: load)
    }

    // MARK: - Field groups

    private var convertFields: some View {
        Group {
            LabeledContent("Quality Preset") {
                Picker("", selection: $preset) {
                    ForEach(ConversionSettings.FFmpegPreset.allCases, id: \.self) { p in
                        Text(p.displayName).tag(p)
                    }
                }.labelsHidden().frame(width: 200)
            }
            Toggle("Delete original after converting", isOn: $deleteOriginal)
        }
    }

    private var renameFields: some View {
        Group {
            LabeledContent("Pattern") {
                TextField("{device}_{date}_{index}", text: $pattern)
                    .textFieldStyle(.roundedBorder)
            }
            renamePreview
            VStack(alignment: .leading, spacing: 4) {
                Text("Available tokens").font(.caption).bold()
                ForEach(RenameToken.allCases, id: \.self) { token in
                    HStack {
                        Text(token.rawValue).font(.system(.caption, design: .monospaced))
                        Text(token.label).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Shows how the current pattern would rename a couple of example files,
    /// so the person can see the result before running the workflow.
    private var renamePreview: some View {
        let examples = [
            ("Clip0001.mov", 1),
            ("Clip0002.mov", 2)
        ]
        return VStack(alignment: .leading, spacing: 6) {
            Text("Preview").font(.caption).bold()
            ForEach(examples, id: \.0) { original, index in
                let newName = RenamePatternEngine.apply(
                    pattern: pattern.isEmpty ? "{name}" : pattern,
                    originalName: (original as NSString).deletingPathExtension,
                    deviceName: "Stage Camera",
                    index: index
                )
                HStack(spacing: 6) {
                    Text(original)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("\(newName).\((original as NSString).pathExtension)")
                        .font(.system(.caption, design: .monospaced))
                        .bold()
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var cleanupFields: some View {
        LabeledContent("Retention") {
            Stepper("\(retentionDays) day\(retentionDays == 1 ? "" : "s")", value: $retentionDays, in: 1...365)
        }
    }

    // MARK: - Load / Save

    private func load() {
        switch step.action {
        case .sync, .format:
            break
        case .convert(let p, let del):
            preset = p; deleteOriginal = del
        case .rename(let pat):
            pattern = pat
        case .cleanup(let days):
            retentionDays = days
        }
    }

    private func save() {
        switch step.kind {
        case .sync:    step.action = .sync
        case .convert: step.action = .convert(preset: preset, deleteOriginal: deleteOriginal)
        case .rename:  step.action = .rename(pattern: pattern.isEmpty ? "{name}" : pattern)
        case .format:  step.action = .format
        case .cleanup: step.action = .cleanup(retentionDays: retentionDays)
        }
        dismiss()
    }
}
