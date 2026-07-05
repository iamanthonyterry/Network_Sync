import SwiftUI

// MARK: - Device Source

enum DeviceSource: Identifiable, Hashable, Equatable {
    case hyperDeck(HyperDeck)
    case cloudStore(CloudStore)
    case switcher(BlackmagicSwitcher)

    var id: String {
        switch self {
        case .hyperDeck(let d):  return "deck-\(d.id)"
        case .cloudStore(let s): return "store-\(s.id)"
        case .switcher(let s):   return "switch-\(s.id)"
        }
    }

    var name: String {
        switch self {
        case .hyperDeck(let d):  return d.name
        case .cloudStore(let s): return s.name
        case .switcher(let s):   return s.name
        }
    }

    var ipAddress: String {
        switch self {
        case .hyperDeck(let d):  return d.ipAddress
        case .cloudStore(let s): return s.ipAddress
        case .switcher(let s):   return s.ipAddress
        }
    }

    var icon: String {
        switch self {
        case .hyperDeck:  return "server.rack"
        case .cloudStore: return "externaldrive.badge.wifi"
        case .switcher:   return "switch.2"
        }
    }

    var iconColor: Color {
        switch self {
        case .hyperDeck:  return .blue
        case .cloudStore: return .purple
        case .switcher:   return .orange
        }
    }

    var supportsFileBrowsing: Bool {
        switch self {
        case .hyperDeck, .cloudStore: return true
        case .switcher: return false
        }
    }

    static func == (lhs: DeviceSource, rhs: DeviceSource) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}


// MARK: - File Node

struct FileNode: Identifiable {
    let id: String
    let name: String
    let url: URL?           // local URL (Cloud Store); nil for FTP nodes
    let ftpPath: String?    // relative FTP path; nil for local nodes
    let isDirectory: Bool
    let size: Int64
    let modified: Date
    var children: [FileNode]?
    var isExpanded: Bool = false

    var sizeFormatted: String {
        isDirectory ? "" : ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var icon: String {
        if isDirectory { return "folder.fill" }
        let ext = (ftpPath ?? url?.lastPathComponent ?? name)
            .components(separatedBy: ".").last?.lowercased() ?? ""
        switch ext {
        case "mp4", "mov", "mxf", "m2ts": return "film.fill"
        case "mp3", "wav", "aac", "aif":  return "music.note"
        case "pdf":                        return "doc.fill"
        case "jpg", "jpeg", "png", "tiff": return "photo.fill"
        default:                           return "doc"
        }
    }

    var iconColor: Color {
        if isDirectory { return .blue }
        let ext = (ftpPath ?? url?.lastPathComponent ?? name)
            .components(separatedBy: ".").last?.lowercased() ?? ""
        switch ext {
        case "mp4", "mov", "mxf", "m2ts": return .purple
        case "mp3", "wav", "aac", "aif":  return .pink
        case "pdf":                        return .red
        case "jpg", "jpeg", "png", "tiff": return .green
        default:                           return .secondary
        }
    }
}


// MARK: - Main View

struct StorageBrowserView: View {
    @EnvironmentObject var appState: AppState

    @State private var selectedDevice: DeviceSource?
    @State private var rootNodes: [FileNode] = []
    @State private var isLoadingFiles = false
    @State private var loadError: String?
    @State private var selectedFile: FileNode?
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .name

    enum SortOrder: String, CaseIterable {
        case name = "Name", size = "Size", modified = "Modified"
    }

    private var allDevices: [DeviceSource] {
        appState.hyperDecks.map { .hyperDeck($0) }
        + appState.cloudStores.map { .cloudStore($0) }
        + appState.switchers.map { .switcher($0) }
    }

    var body: some View {
        HSplitView {
            devicesSidebar
                .frame(minWidth: 200, maxWidth: 240)
            filesBrowser
        }
    }

    // MARK: - Devices Sidebar

    private var devicesSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Devices").font(.title3).bold()
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if allDevices.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "network.slash")
                        .font(.system(size: 32)).foregroundStyle(.secondary)
                    Text("No Devices").foregroundStyle(.secondary).font(.callout)
                    Text("Add devices on the Devices page.")
                        .font(.caption).foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                    Spacer()
                }
            } else {
                List(allDevices, id: \.id, selection: $selectedDevice) { device in
                    DeviceSourceRow(device: device).tag(device)
                }
                .listStyle(.inset)
            }
        }
        .onChange(of: selectedDevice) { _, _ in loadFiles() }
    }


    // MARK: - Files Browser

    private var filesBrowser: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                if let device = selectedDevice {
                    Image(systemName: device.icon).foregroundStyle(device.iconColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(device.name).font(.title3).bold()
                        Text(device.ipAddress).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if device.supportsFileBrowsing {
                        HStack(spacing: 0) {
                            ForEach(SortOrder.allCases, id: \.self) { order in
                                SortOrderButton(order: order, selected: sortOrder == order) {
                                    sortOrder = order
                                }
                            }
                        }
                        Button(action: loadFiles) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .disabled(isLoadingFiles)
                    }
                } else {
                    Text("Select a device").font(.title3).foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // Search bar (only when browsable)
            if selectedDevice?.supportsFileBrowsing == true {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search files…", text: $searchText).textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
                Divider()
            }

            // Content
            filesContent
        }
    }

    @ViewBuilder
    private var filesContent: some View {
        if selectedDevice == nil {
            emptySelection
        } else if let device = selectedDevice, !device.supportsFileBrowsing {
            noFilesState(for: device)
        } else if isLoadingFiles {
            VStack { Spacer(); ProgressView("Loading files…"); Spacer() }
        } else if let error = loadError {
            errorState(message: error)
        } else if rootNodes.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "tray").font(.system(size: 36)).foregroundStyle(.secondary)
                Text("No files found").foregroundStyle(.secondary)
                Spacer()
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredNodes) { node in
                        FileNodeView(node: node, depth: 0, selectedFile: $selectedFile, onToggle: toggleNode)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }


    // MARK: - Empty / Error States

    private var emptySelection: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "externaldrive").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("Select a device to browse files").foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func noFilesState(for device: DeviceSource) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: device.icon).font(.system(size: 48)).foregroundStyle(.secondary)
            Text(device.name).font(.title3).bold()
            Text("This device type doesn't expose a file system.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle").font(.system(size: 40)).foregroundStyle(.red)
            Text("Could not load files").font(.headline)
            Text(message).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal)
            Button("Retry", action: loadFiles).buttonStyle(.bordered)
            Spacer()
        }
    }

    // MARK: - Computed / Filtering

    private var filteredNodes: [FileNode] {
        guard !searchText.isEmpty else { return sortedNodes(rootNodes) }
        return flatFilter(rootNodes, query: searchText.lowercased())
    }

    private func sortedNodes(_ nodes: [FileNode]) -> [FileNode] {
        nodes.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            switch sortOrder {
            case .name:     return a.name.localizedCompare(b.name) == .orderedAscending
            case .size:     return a.size > b.size
            case .modified: return a.modified > b.modified
            }
        }
    }

    private func flatFilter(_ nodes: [FileNode], query: String) -> [FileNode] {
        var result: [FileNode] = []
        for node in nodes {
            if node.name.lowercased().contains(query) { result.append(node) }
            if let children = node.children { result += flatFilter(children, query: query) }
        }
        return result
    }


    // MARK: - Load Files

    private func loadFiles() {
        guard let device = selectedDevice, device.supportsFileBrowsing else { return }
        isLoadingFiles = true
        loadError = nil
        rootNodes = []
        selectedFile = nil

        Task {
            do {
                let nodes = try await fetchNodes(for: device)
                await MainActor.run {
                    rootNodes = nodes
                    isLoadingFiles = false
                }
            } catch {
                await MainActor.run {
                    loadError = error.localizedDescription
                    isLoadingFiles = false
                }
            }
        }
    }

    private func fetchNodes(for device: DeviceSource) async throws -> [FileNode] {
        switch device {
        case .hyperDeck(let deck):
            return try await fetchFTPNodes(deck: deck, path: deck.remotePath)
        case .cloudStore(let store):
            let mountPath = try await SMBService.mountAndResolve(
                ip: store.ipAddress,
                volume: store.volumeName,
                username: store.username,
                password: store.password
            )
            return try fetchLocalNodes(at: URL(fileURLWithPath: mountPath))
        case .switcher:
            return []
        }
    }

    // MARK: - FTP (HyperDeck)

    private func fetchFTPNodes(deck: HyperDeck, path: String) async throws -> [FileNode] {
        let listing = await FTPService.listAllFiles(on: deck, path: path)
        return listing.map { entry in
            FileNode(
                id: "\(deck.id)-\(entry.name)",
                name: entry.name,
                url: nil,
                ftpPath: entry.name,
                isDirectory: entry.isDirectory,
                size: entry.size,
                modified: entry.modified,
                children: entry.isDirectory ? nil : []
            )
        }
    }

    // MARK: - Local / SMB (Cloud Store)

    private func fetchLocalNodes(at url: URL) throws -> [FileNode] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey]
        let contents = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: keys)
        return contents.compactMap { child -> FileNode? in
            let res = try? child.resourceValues(forKeys: Set(keys))
            guard !(res?.isHidden ?? false) else { return nil }
            let isDir = res?.isDirectory ?? false
            return FileNode(
                id: child.path,
                name: child.lastPathComponent,
                url: child,
                ftpPath: nil,
                isDirectory: isDir,
                size: Int64(res?.fileSize ?? 0),
                modified: res?.contentModificationDate ?? .distantPast,
                children: isDir ? nil : []
            )
        }
        .sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCompare(b.name) == .orderedAscending
        }
    }


    // MARK: - Toggle Node (expand/collapse directories)

    private func toggleNode(_ nodeID: String) {
        guard let device = selectedDevice else { return }
        toggleInTree(&rootNodes, id: nodeID, device: device)
    }

    @discardableResult
    private func toggleInTree(_ nodes: inout [FileNode], id: String, device: DeviceSource) -> Bool {
        for i in nodes.indices {
            if nodes[i].id == id {
                if nodes[i].isExpanded {
                    nodes[i].isExpanded = false
                } else {
                    if nodes[i].children == nil {
                        let node = nodes[i]
                        Task {
                            let children = await loadChildren(for: node, device: device)
                            await MainActor.run {
                                _ = toggleInTree(&rootNodes, id: id, device: device, setChildren: children)
                            }
                        }
                        return true
                    }
                    nodes[i].isExpanded = true
                }
                return true
            }
            if var children = nodes[i].children,
               toggleInTree(&children, id: id, device: device) {
                nodes[i].children = children
                return true
            }
        }
        return false
    }

    @discardableResult
    private func toggleInTree(_ nodes: inout [FileNode], id: String, device: DeviceSource, setChildren: [FileNode]) -> Bool {
        for i in nodes.indices {
            if nodes[i].id == id {
                nodes[i].children = setChildren
                nodes[i].isExpanded = true
                return true
            }
            if var children = nodes[i].children,
               toggleInTree(&children, id: id, device: device, setChildren: setChildren) {
                nodes[i].children = children
                return true
            }
        }
        return false
    }

    private func loadChildren(for node: FileNode, device: DeviceSource) async -> [FileNode] {
        switch device {
        case .hyperDeck(let deck):
            guard let path = node.ftpPath else { return [] }
            return (try? await fetchFTPNodes(deck: deck, path: path)) ?? []
        case .cloudStore:
            guard let url = node.url else { return [] }
            return (try? fetchLocalNodes(at: url)) ?? []
        case .switcher:
            return []
        }
    }
}


// MARK: - File Node Row

struct FileNodeView: View {
    let node: FileNode
    let depth: Int
    @Binding var selectedFile: FileNode?
    let onToggle: (String) -> Void

    private var isSelected: Bool { selectedFile?.id == node.id }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                // Indent
                if depth > 0 {
                    Rectangle().fill(Color.clear).frame(width: CGFloat(depth) * 16)
                }

                // Expand chevron or spacer
                if node.isDirectory {
                    Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                } else {
                    Spacer().frame(width: 12)
                }

                // Icon + name
                Image(systemName: node.icon)
                    .foregroundStyle(node.iconColor)
                    .frame(width: 18)

                Text(node.name)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                // Size (files only)
                if !node.sizeFormatted.isEmpty {
                    Text(node.sizeFormatted)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture {
                if node.isDirectory {
                    onToggle(node.id)
                } else {
                    selectedFile = node
                }
            }

            Divider().padding(.leading, CGFloat(depth) * 16 + 38)
        }

        // Children
        if node.isExpanded, let children = node.children {
            ForEach(children) { child in
                FileNodeView(node: child, depth: depth + 1, selectedFile: $selectedFile, onToggle: onToggle)
            }
        }
    }
}

// MARK: - Sort Order Button

private struct SortOrderButton: View {
    let order: StorageBrowserView.SortOrder
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(order.rawValue, action: action)
            .buttonStyle(.borderless)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(selected ? Color.accentColor.opacity(0.15) : Color.clear)
            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - Device Source Row

struct DeviceSourceRow: View {
    let device: DeviceSource

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.icon)
                .font(.system(size: 18))
                .foregroundStyle(device.iconColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).font(.system(.body, weight: .medium))
                Text(device.ipAddress)
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            if !device.supportsFileBrowsing {
                Image(systemName: "nosign")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }
}

