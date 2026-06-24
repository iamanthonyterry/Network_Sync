import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var scheduler = SchedulerService.shared
    @StateObject private var installer = ToolInstaller.shared
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
                LabeledContent("FFmpeg Preset") {
                    Picker("", selection: $appState.conversionSettings.preset) {
                        ForEach(ConversionSettings.FFmpegPreset.allCases, id: \.self) { p in
                            Text("\(p.displayName) — \(p.description)").tag(p)
                        }
                    }.frame(width: 280)
                }
                LabeledContent("CRF Quality") {
                    HStack {
                        Slider(value: Binding(
                            get: { Double(appState.conversionSettings.crf) },
                            set: { appState.conversionSettings.crf = Int($0) }
                        ), in: 0...51, step: 1).frame(width: 160)
                        Text("\(appState.conversionSettings.crf) (lower = better)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Audio Bitrate") {
                    Picker("", selection: $appState.conversionSettings.audioBitrate) {
                        ForEach(["96k","128k","192k","256k"], id: \.self) { Text($0).tag($0) }
                    }.frame(width: 100)
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
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    // Status icon
                    Group {
                        switch installer.phase {
                        case .done:
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        case .failed:
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        case .installing:
                            ProgressView().controlSize(.small)
                        case .idle:
                            Image(systemName: installer.ffmpegReady
                                  ? "checkmark.circle.fill"
                                  : "exclamationmark.triangle.fill")
                                .foregroundStyle(installer.ffmpegReady ? Color.green : Color.orange)
                        }
                    }

                    // Label
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ffmpeg").font(.subheadline)
                        switch installer.phase {
                        case .installing(let step):
                            Text(step).font(.caption).foregroundStyle(.secondary)
                        case .failed(let msg):
                            Text(msg).font(.caption).foregroundStyle(.red)
                        case .done:
                            Text("Installed and ready").font(.caption).foregroundStyle(.secondary)
                        case .idle:
                            Text(installer.ffmpegReady ? "Installed and ready" : "Not installed")
                                .font(.caption)
                                .foregroundStyle(installer.ffmpegReady ? Color.secondary : Color.orange)
                        }
                    }

                    Spacer()

                    // Action button
                    if !installer.ffmpegReady, installer.phase == .idle {
                        Button("Install Automatically") {
                            installer.installIfNeeded()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }

                // Live log during install
                if case .installing = installer.phase, !installer.log.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(installer.log.suffix(20), id: \.self) { line in
                                Text(line)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 100)
                    .padding(6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }

                // Error log
                if case .failed = installer.phase, !installer.log.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(installer.log.suffix(10), id: \.self) { line in
                                Text(line)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 80)
                    .padding(6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(4)
        }
        .padding(.horizontal)
        .onAppear {
            // Auto-check on view appear; auto-install if missing
            if !installer.ffmpegReady, installer.phase == .idle {
                installer.installIfNeeded()
            }
        }
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
