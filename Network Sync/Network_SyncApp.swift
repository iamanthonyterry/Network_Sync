//
//  Newtowk_SyncApp.swift
//  Newtowk Sync
//
//  Created by Anthony Terry on 6/7/26.
//

import SwiftUI
import CoreData

@main
struct Newtowk_SyncApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
