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
                .background(WindowChromeConfigurator())
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}

private struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()

        DispatchQueue.main.async {
            configureWindow(for: view)
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(for: nsView)
        }
    }

    private func configureWindow(for view: NSView) {
        guard let window = view.window else {
            return
        }

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
    }
}
