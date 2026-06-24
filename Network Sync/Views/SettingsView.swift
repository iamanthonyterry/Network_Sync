import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var scheduler = SchedulerService.shared
    @State private var mountResult: String?
    @State private var testingMount = false
    @State private var selectedStoreID: UUID? = nil   // nil = Custom

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings").font(.title2).bold().padding(.horizontal)
                cloudStoreSection
                conversionSection
                scheduleSection
                storageSection
                systemSection
                Spacer(minLength: 24)
            }
            .padding(.vertical)
        }
    }

    // MARK: - Sync Destination
    private var cloudStoreSection: some View {
        GroupBox(label: Label("Sync Destination (SMB)", systemImage: "externaldrive.connected.to.line.below")) {
            Form {
                if !appState.cloudStores.isEmpty {
                    LabeledContent("Device") {
                        Picker("", selection: $selectedStoreID) {
                            Text("Custom…").tag(Optional<UUID>.none)
                            Divider()
                            ForEach(appState.cloudStores) { store in
                                Text(store.name).tag(Optional(store.id))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                        .onChange(of: selectedStoreID) { _, id in
                            guard let id, let store = appState.cloudStores.first(where: { $0.id == id })
                            else { return }
                            appState.syncLocation.ipAddress  = store.ipAddress
                            appState.syncLocation.volumeName = store.volumeName
                            appState.syncLocation.username   = store.username
                            appState.syncLocation.password   = store.password
                            mountResult = nil
                        }
                    }
                }

                if selectedStoreID == nil {
                    LabeledContent("IP Address") {
                        TextField("192.168.2.119", text: $appState.syncLocation.ipAddress)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Volume Name") {
                        TextField("lp service backup", text: $appState.syncLocation.volumeName)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Base Folder") {
                        TextField("ISO Records", text: $appState.syncLocation.basePath)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Username") {
                        TextField("guest", text: $appState.syncLocation.username)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Password") {
                        SecureField("Password", text: $appState.syncLocation.password)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                HStack {
                    Button(action: testMount) {
                        if testingMount {
                            ProgressView().controlSize(.small)
                            Text("Testing...")
                        } else {
                            Label("Test Mount", systemImage: "externaldrive")
                        }
                    }.disabled(testingMount)
                    if let r = mountResult {
                        Text(r).font(.caption)
                            .foregroundStyle(r.hasPrefix("✅") ? Color.green : Color.orange)
                    }
                }
            }.formStyle(.columns)
        }.padding(.horizontal)
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

    // MARK: - System
    private var systemSection: some View {
        GroupBox(label: Label("System", systemImage: "cpu")) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Video Conversion").font(.subheadline)
                    Text("AVFoundation — built-in, hardware-accelerated, no installs required")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(4)
        }
        .padding(.horizontal)
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
