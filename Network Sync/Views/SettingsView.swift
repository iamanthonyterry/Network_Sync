import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var scheduler = SchedulerService.shared
    @State private var mountResult: String?
    @State private var testingMount = false
    @State private var selectedStoreID: UUID? = nil   // nil = Custom
    @State private var shouldFormatDrive: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings").font(.title2).bold().padding(.horizontal)
                //cloudStoreSection
                conversionSection
                scheduleSection
                storageSection
                formatDriveSection
                emailSection
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
                LabeledContent("Delete Originals") {
                    Toggle("", isOn: $appState.conversionSettings.deleteOriginalsAfterConvert)
                        .labelsHidden()
                }
                LabeledContent("Engine") {
                    Text("AVFoundation (built-in, hardware-accelerated)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.columns)
        }.padding(.horizontal)
    }

    // MARK: - Schedule
    private var scheduleSection: some View {
        GroupBox(label: Label("Scheduled Sync", systemImage: "clock")) {
            Form {
                LabeledContent("Enable Schedule") {
                    Toggle("", isOn: $appState.scheduleSettings.isEnabled)
                        .labelsHidden()
                        .onChange(of: appState.scheduleSettings.isEnabled) { scheduler.sync() }
                }
                if appState.scheduleSettings.isEnabled {
                    LabeledContent("Run Time") {
                        HStack(spacing: 8) {
                            Stepper(value: $appState.scheduleSettings.hour, in: 0...23) {
                                Text(String(format: "%02d", appState.scheduleSettings.hour))
                                    .monospacedDigit().frame(width: 28)
                            }
                            .onChange(of: appState.scheduleSettings.hour) { scheduler.sync() }
                            Text(":")
                            Stepper(value: $appState.scheduleSettings.minute, in: 0...59, step: 5) {
                                Text(String(format: "%02d", appState.scheduleSettings.minute))
                                    .monospacedDigit().frame(width: 28)
                            }
                            .onChange(of: appState.scheduleSettings.minute) { scheduler.sync() }
                            Text(appState.scheduleSettings.displayTime)
                                .font(.caption).foregroundStyle(.secondary)
                                .padding(.leading, 4)
                        }
                    }
                    LabeledContent("Repeat") {
                        Toggle("Daily", isOn: $appState.scheduleSettings.repeatDaily)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Next run at \(appState.scheduleSettings.displayTime)\(appState.scheduleSettings.repeatDaily ? " every day" : " — once")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
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
            Toggle(isOn: $shouldFormatDrive) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Format drive after completion")
                        .font(.body)
                    Text("All data on the destination drive will be permanently erased.")
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
