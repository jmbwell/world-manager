//
//  World_Manager_for_MinecraftApp.swift
//  World Manager for Minecraft
//
//  Created by John Burwell on 2026-05-25.
//

import SwiftUI
import SwiftData

@main
struct World_Manager_for_MinecraftApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
