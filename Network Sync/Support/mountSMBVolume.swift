//
//  mountSMBVolume.swift
//  Newtowk Sync
//
//  Created by Anthony Terry on 6/8/26.
//


import Foundation

func mountSMBVolume(ip: String, volume: String, user: String, pass: String) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/sbin/mount_smbfs")
    
    // Constructing URL format: //user:pass@ip/volume
    let credentialString = "//\(user):\(pass)@\(ip)/\(volume)"
    let mountPoint = "/Volumes/\(volume)"
    
    // Ensure mount folder exists locally if required, or let system automate
    process.arguments = [credentialString, mountPoint]
    
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        print("Mount failed: \(error)")
        return false
    }
}

func runFFmpeg(input: String, output: String) {
    let process = Process()
    // Point this to your bundled or system ffmpeg binary path
    process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
    
    process.arguments = [
        "-i", input,
        "-c:v", "libx264", "-preset", "ultrafast", "-crf", "23",
        "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart",
        "-threads", "0", "-y", output
    ]
    
    let errorPipe = Pipe()
    process.standardError = errorPipe // ffmpeg outputs progress telemetry to stderr
    
    do {
        try process.run()
        
        let fileHandle = errorPipe.fileHandleForReading
        fileHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if let outputString = String(data: data, encoding: .utf8) {
                // Parse standard ffmpeg strings like "time=00:02:15.45" to update SwiftUI
                parseFFmpegProgress(outputString)
            }
        }
        
        process.waitUntilExit()
    } catch {
        print("FFmpeg failed to execute: \(error)")
    }
}

func parseFFmpegProgress(_ log: String) {
    // Regex logic goes here to scan for "time=" or frames and update UI progress bindings
}
