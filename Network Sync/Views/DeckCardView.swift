//
//  DeckCardView.swift
//  Newtowk Sync
//
//  Created by Anthony Terry on 6/7/26.
//


import SwiftUI
import Network

struct DeckCardView: View {
    var deck: HyperDeck
    var destination: SyncLocation?
    var onDelete: () -> Void
    
    @State private var currentStatus: DeckStatus = .unknown
    @State private var files: [String] = []
    @State private var isShowingFiles = false
    @State private var isFetchingFiles = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(deck.name)
                        .font(.headline)
                    Text(deck.ipAddress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                statusIndicator(for: currentStatus)
            }
            
            Text("Source: \(deck.remotePath)")
                .font(.caption)
                .italic()
            
            Divider()
            
            // Live File List Dropdown Section
            if currentStatus == .online || !files.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    DisclosureGroup(
                        isExpanded: $isShowingFiles,
                        content: {
                            if isFetchingFiles {
                                HStack {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Reading drive directory...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                            } else if files.isEmpty {
                                Text("No .mov files found on this drive.")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .padding(.vertical, 4)
                            } else {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(files, id: \.self) { fileName in
                                        HStack {
                                            Image(systemName: "video.fill")
                                                .font(.caption)
                                                .foregroundColor(.blue)
                                            Text(fileName)
                                                .font(.system(.caption, design: .monospaced))
                                                .lineLimit(1)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        },
                        label: {
                            HStack {
                                Image(systemName: "folder.badge.gearshape")
                                Text("Drive Files (\(files.count))")
                                    .font(.subheadline).bold()
                            }
                        }
                    )
                }
                .padding(.vertical, 2)
                Divider()
            }
            
            HStack {
                Button(action: {
                    checkDeckConnection()
                    fetchRemoteFiles()
                }) {
                    Text("Refresh")
                    Image(systemName: "arrow.clockwise")
                    //Label("Refresh", systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                
                Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 4)
                
                Spacer()
                
                Button(action: startInterleavedProcess) {
                    Text("Sync & Transcode")
                    Image(systemName: "arrow.triangle.2.circlepath")
                   // Label("Sync & Transcode", systemName: "arrow.triangle.2.circlepath")
                }
                .disabled(destination == nil || currentStatus == .offline)
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
        .onAppear {
            checkDeckConnection()
            fetchRemoteFiles()
        }
    }
    
    func checkDeckConnection() {
        let host = NWEndpoint.Host(deck.ipAddress)
        let port = NWEndpoint.Port(integerLiteral: 21)
        let connection = NWConnection(host: host, port: port, using: .tcp)
        
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                currentStatus = .online
                connection.cancel()
            case .failed:
                currentStatus = .offline
            default:
                break
            }
        }
        connection.start(queue: .global())
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if currentStatus == .unknown { currentStatus = .offline }
        }
    }
    
    // MARK: - Native FTP Directory Fetcher
    func fetchRemoteFiles() {
        guard currentStatus != .offline else { return }
        isFetchingFiles = true
        
        // Run this in the background so the UI never stutters
        DispatchQueue.global(qos: .background).async {
            let process = Process()
            let pipe = Pipe()
            
            // Target the native macOS curl binary
            process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            
            // Properly URL-encode spaces in paths (e.g., "usb/Extreme Pro" becomes "usb/Extreme%20Pro")
            let encodedPath = deck.remotePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? deck.remotePath
            
            // Build the direct ftp URL string
            let ftpURL = "ftp://\(deck.ipAddress)/\(encodedPath)/"
            
            // Pass arguments to curl: use credentials, force passive mode (-L), and set a 3-second timeout
            process.arguments = [
                "--user", "\(deck.username):\(deck.password)",
                "--connect-timeout", "3",
                "-s", // Silent mode (suppress curl's progress meter)
                ftpURL
            ]
            
            process.standardOutput = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let outputString = String(data: data, encoding: .utf8) {
                    // Send the raw text to our updated string parser
                    self.parseFTPList(outputString)
                } else {
                    DispatchQueue.main.async { self.isFetchingFiles = false }
                }
            } catch {
                print("❌ Failed to execute background curl process: \(error)")
                DispatchQueue.main.async { self.isFetchingFiles = false }
            }
        }
    }

    func parseFTPList(_ response: String) {
        DispatchQueue.main.async {
            // Clean out carriage returns and split by line breaks
            let normalizedResponse = response.replacingOccurrences(of: "\r", with: "")
            let lines = normalizedResponse.components(separatedBy: "\n")
            
            var discoveredMovs: [String] = []
            
            for line in lines {
                let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleanLine.isEmpty { continue }
                
                // Curl will return either raw file lines or standard UNIX directory listings.
                // This condition handles both safely!
                if cleanLine.lowercased().contains(".mov") {
                    if let lastSegment = cleanLine.components(separatedBy: " ").last,
                       lastSegment.lowercased().hasSuffix(".mov") {
                        discoveredMovs.append(lastSegment)
                    } else if cleanLine.lowercased().hasSuffix(".mov") {
                        discoveredMovs.append(cleanLine)
                    }
                }
            }
            
            self.files = discoveredMovs
            self.isFetchingFiles = false
        }
    }
    
    func startInterleavedProcess() {
        guard let target = destination else { return }
        currentStatus = .syncing
    }
    
    @ViewBuilder
    func statusIndicator(for status: DeckStatus) -> some View {
        let payload: (text: String, color: Color) = {
            switch status {
            case .unknown: return ("Unknown", .gray)
            case .online: return ("Online", .green)
            case .offline: return ("Offline", .red)
            case .syncing: return ("Syncing", .blue)
            case .transcoding: return ("Rendering", .orange)
            }
        }()
        
        Text(payload.text)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(payload.color.opacity(0.2))
            .foregroundColor(payload.color)
            .cornerRadius(20)
    }
}
