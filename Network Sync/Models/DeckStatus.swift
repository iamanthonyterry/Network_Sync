//
//  DeckStatus.swift
//  Newtowk Sync
//
//  Created by Anthony Terry on 6/7/26.
//


import Foundation

enum DeckStatus {
    case unknown, online, offline, syncing, transcoding
}

struct HyperDeck: Identifiable, Codable {
    var id = UUID()
    var name: String
    var ipAddress: String
    var remotePath: String
    var username: String = "lpproduction"
    var password: String = "7404"
    
    // Add this line to hold the live file list (not saved permanently, fetched fresh)
    var discoveredFiles: [String]? = nil
}

struct SyncLocation: Identifiable, Codable {
    var id = UUID()
    var name: String
    var localPath: String // The /Volumes/ path on your Mac
    var securityBookmark: Data? // Keeps permissions persistent across app restarts
}


