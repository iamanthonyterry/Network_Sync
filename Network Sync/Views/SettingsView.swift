import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var mountResult: String?
    @State private var testingMount = false
    @State private var selectedStoreID: UUID? = nil   // nil = Custom

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings").font(.title2).bold().padding(.horizontal)
                //cloudStoreSection
                conversionSection
                storageSection
                formatDriveSection
                emailSection
                RemoteControlSettingsView()
                //systemSection
                Spacer(minLength: 24)
            }
            .padding(.vertical)
        }
    }
    
    // MARK: - Conversion
    private var conversionSection: some View {
        GroupBox(label: Label("Conversion Settings", systemImage: "film.stack")) {
            Form {
                LabeledContent("Quality Preset") {
                    Picker("", selection: $appState.conversionSettings.preset) {
                        ForEach(ConversionSettings.FFmpegPreset.allCases, id: \.self) { p in
                            Text("\(p.displayName) — \(p.description)").tag(p)
                        }
                    }.frame(width: 320)
                }
                LabeledContent("Max Parallel Jobs") {
                    Stepper(
                        "\(appState.conversionSettings.maxParallelConversions)",
                        value: $appState.conversionSettings.maxParallelConversions,
                        in: 1...8
                    )
                }
                LabeledContent("Originals") {
                    Text("Deleted automatically after conversion")
                        .font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("Engine") {
                    Text("AVFoundation (built-in, hardware-accelerated)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.columns)
        }.padding(.horizontal)
    }

    // MARK: - Storage
    private var storageSection: some View {
        GroupBox(label: Label("Storage Management", systemImage: "clock.arrow.circlepath")) {
            Form {
                LabeledContent("Retain Converted Files") {
                    Stepper(
                        "\(appState.conversionSettings.retentionDays) days",
                        value: $appState.conversionSettings.retentionDays,
                        in: 1...365
                    )
                }
            }.formStyle(.columns)
        }.padding(.horizontal)
    }
    
    // MARK: - Email

    private var formatDriveSection: some View {
        GroupBox(label: Label("Post-Process Actions", systemImage: "externaldrive.badge.timemachine")) {
            Toggle(isOn: $appState.formatDriveAfterSync) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Erase device drive after sync completes")
                        .font(.body)
                    Text("Once files are safely synced, the device's own drive will be permanently erased. This cannot be undone.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .padding(.horizontal)
    }
    // MARK: - Email
    private var emailSection: some View {
        EmailNotificationsView()
    }

    // MARK: - Helpers
    private func testMount() {
        testingMount = true; mountResult = nil
        let path = appState.syncLocation.mountPath
        Task.detached(priority: .userInitiated) {
            let mounted = FileManager.default.fileExists(atPath: path)
            await MainActor.run {
                testingMount = false
                mountResult = mounted
                    ? "✅ Mounted at \(path)"
                    : "⚠️ Not mounted — will auto-mount on sync"
            }
        }
    }
}
