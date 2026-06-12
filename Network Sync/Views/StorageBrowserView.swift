import SwiftUI
import Combine

struct StorageBrowserView: View {
    @EnvironmentObject var appState: AppState
    @State private var deckFolders: [DeckFolder] = []
    @State private var isLoading = false
    @State private var selectedDeck: DeckFolder?
    @State private var errorMessage: String?

    struct DeckFolder: Identifiable, Hashable {
        var id: String { name }
        var name: String
        var url: URL
        var convertedFiles: [StorageFile] = []
        var receiptFiles: Int = 0
        var totalSizeBytes: Int64 = 0

        var totalSizeFormatted: String {
            ByteCountFormatter.string(fromByteCount: totalSizeBytes, countStyle: .file)
        }

        func hash(into hasher: inout Hasher) { hasher.combine(name) }
        static func == (lhs: DeckFolder, rhs: DeckFolder) -> Bool { lhs.name == rhs.name }
    }

    struct StorageFile: Identifiable {
        var id: String { name }
        var name: String
        var sizeBytes: Int64
        var modifiedAt: Date

        var sizeFormatted: String {
            ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
        }
    }

    var body: some View {
        HSplitView {
            // Left: deck list
            VStack(spacing: 0) {
                HStack {
                    Text("Cloud Storage").font(.title2).bold()
                    Spacer()
                    Button(action: load) {
                        if isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(isLoading)
                }
                .padding()
                Divider()

                if let err = errorMessage {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 36)).foregroundStyle(.orange)
                        Text(err).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                        Button("Try Again") { load() }.buttonStyle(.borderedProminent)
                        Spacer()
                    }
                } else if deckFolders.isEmpty && !isLoading {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "externaldrive").font(.system(size: 40)).foregroundStyle(.secondary)
                        Text("Volume Not Mounted").font(.title3).bold()
                        Text("Mount the cloud store first via Settings → Test Mount, or start a sync.")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                        Button("Refresh") { load() }.buttonStyle(.borderedProminent)
                        Spacer()
                    }
                } else {
                    List(deckFolders, selection: $selectedDeck) { folder in
                        DeckFolderRow(folder: folder).tag(folder)
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 240, maxWidth: 300)
            .onAppear { load() }

            // Right: file detail
            if let folder = selectedDeck {
                DeckFolderDetailView(folder: folder)
            } else {
                VStack {
                    Spacer()
                    Text("Select a deck to browse its files")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }

    private func load() {
        isLoading = true
        errorMessage = nil
        let base = URL(fileURLWithPath: appState.syncLocation.recordsPath)

        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            guard fm.fileExists(atPath: base.path) else {
                DispatchQueue.main.async {
                    isLoading = false
                    deckFolders = []
                }
                return
            }

            do {
                let contents = try fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)
                let dirs = contents.filter { url in
                    var isDir: ObjCBool = false
                    fm.fileExists(atPath: url.path, isDirectory: &isDir)
                    return isDir.boolValue
                }.sorted { $0.lastPathComponent < $1.lastPathComponent }

                var folders: [DeckFolder] = []
                for dir in dirs {
                    var folder = DeckFolder(name: dir.lastPathComponent, url: dir)
                    let convertedDir = dir.appendingPathComponent("Converted")

                    // Scan converted files
                    if let files = try? fm.contentsOfDirectory(at: convertedDir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) {
                        folder.convertedFiles = files
                            .filter { $0.pathExtension.lowercased() == "mp4" }
                            .compactMap { url -> StorageFile? in
                                let res = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                                return StorageFile(
                                    name: url.lastPathComponent,
                                    sizeBytes: Int64(res?.fileSize ?? 0),
                                    modifiedAt: res?.contentModificationDate ?? Date()
                                )
                            }
                            .sorted { $0.modifiedAt > $1.modifiedAt }
                        folder.totalSizeBytes = folder.convertedFiles.reduce(0) { $0 + $1.sizeBytes }
                    }

                    // Count receipts
                    if let all = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                        folder.receiptFiles = all.filter { $0.lastPathComponent.hasSuffix(".done") }.count
                    }

                    folders.append(folder)
                }

                DispatchQueue.main.async {
                    deckFolders = folders
                    isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Deck Folder Row
struct DeckFolderRow: View {
    let folder: StorageBrowserView.DeckFolder

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(folder.name).font(.headline)
                Spacer()
                Text(folder.totalSizeFormatted)
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Label("\(folder.convertedFiles.count) MP4s", systemImage: "film")
                    .font(.caption).foregroundStyle(.secondary)
                if folder.receiptFiles > 0 {
                    Label("\(folder.receiptFiles) receipts", systemImage: "checkmark.seal")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Deck Folder Detail
struct DeckFolderDetailView: View {
    let folder: StorageBrowserView.DeckFolder

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name).font(.title2).bold()
                    Text("\(folder.convertedFiles.count) files · \(folder.totalSizeFormatted) total")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    NSWorkspace.shared.open(folder.url.appendingPathComponent("Converted"))
                } label: {
                    Label("Open in Finder", systemImage: "folder")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            Divider()

            if folder.convertedFiles.isEmpty {
                VStack {
                    Spacer()
                    Text("No converted files yet").foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                Table(folder.convertedFiles) {
                    TableColumn("File Name") { file in
                        HStack(spacing: 6) {
                            Image(systemName: "film.fill").foregroundStyle(.blue).font(.caption)
                            Text(file.name).font(.system(.body, design: .monospaced))
                        }
                    }
                    TableColumn("Size") { file in
                        Text(file.sizeFormatted).foregroundStyle(.secondary)
                    }
                    .width(80)
                    TableColumn("Modified") { file in
                        Text(file.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                    .width(160)
                }
            }
        }
    }
}
