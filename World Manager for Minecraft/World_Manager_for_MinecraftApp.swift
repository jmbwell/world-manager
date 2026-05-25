//
//  World_Manager_for_MinecraftApp.swift
//  World Manager for Minecraft
//
//  Created by John Burwell on 2026-05-25.
//

import SwiftUI

@main
struct World_Manager_for_MinecraftApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(Color("AccentColor"))
        }
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
    }
}
