import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var mountResult: String?
    @State private var testingMount = false
    @State private var ffmpegFound: Bool? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings").font(.title2).bold().padding(.horizontal)

                // Cloud Store
                GroupBox(label: Label("Cloud Store / SMB Destination", systemImage: "externaldrive.connected.to.line.below")) {
                    Form {
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
                        HStack {
                            Button(action: testMount) {
                                if testingMount {
                                    ProgressView().controlSize(.small); Text("Testing...")
                                } else {
                                    Label("Test Mount", systemImage: "externaldrive")
                                }
                            }.disabled(testingMount)
                            if let r = mountResult {
                                Text(r).font(.caption)
                                    .foregroundStyle(r.hasPrefix("✅") ? .green : .orange)
                            }
                        }
                    }.formStyle(.columns)
                }.padding(.horizontal)

                // Conversion
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
                            Stepper("\(appState.conversionSettings.maxParallelConversions)",
                                    value: $appState.conversionSettings.maxParallelConversions, in: 1...8)
                        }
                        LabeledContent("Delete Originals") {
                            Toggle("", isOn: $appState.conversionSettings.deleteOriginalsAfterConvert)
                                .labelsHidden()
                        }
                    }.formStyle(.columns)
                }.padding(.horizontal)

                // Storage
                GroupBox(label: Label("Storage Management", systemImage: "clock.arrow.circlepath")) {
                    Form {
                        LabeledContent("Retain Converted Files") {
                            Stepper("\(appState.conversionSettings.retentionDays) days",
                                    value: $appState.conversionSettings.retentionDays, in: 1...365)
                        }
                    }.formStyle(.columns)
                }.padding(.horizontal)

                // System
                GroupBox(label: Label("System", systemImage: "cpu")) {
                    HStack {
                        Text("ffmpeg").font(.subheadline)
                        Spacer()
                        if let found = ffmpegFound {
                            Label(found ? "Found" : "Not Found",
                                  systemImage: found ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(found ? .green : .red)
                                .font(.subheadline)
                        } else {
                            Button("Check") { checkFFmpeg() }
                        }
                    }
                    .padding(4)
                }.padding(.horizontal)

                Spacer(minLength: 24)
            }
            .padding(.vertical)
        }
    }

    private func testMount() {
        testingMount = true; mountResult = nil
        let path = appState.syncLocation.mountPath
        DispatchQueue.global().async {
            let mounted = FileManager.default.fileExists(atPath: path)
            DispatchQueue.main.async {
                testingMount = false
                mountResult = mounted ? "✅ Mounted at \(path)" : "⚠️ Not mounted — will auto-mount on sync"
            }
        }
    }

    private func checkFFmpeg() {
        let paths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
        ffmpegFound = paths.contains { FileManager.default.fileExists(atPath: $0) }
    }
}
