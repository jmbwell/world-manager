// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI

@main
struct World_Manager_for_MinecraftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Task {
            await ScanNotificationService.shared.requestAuthorizationIfNeeded()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(Color("AccentColor"))
                .background(WindowChromeConfigurator())
        }
        .defaultSize(width: 1520, height: 980)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppTerminationCoordinator.shared.beginTermination(for: sender)
    }
}

@MainActor
final class AppTerminationCoordinator {
    static let shared = AppTerminationCoordinator()

    private weak var library: SourceLibrary?
    private var isTerminationInProgress = false

    func register(library: SourceLibrary) {
        self.library = library
    }

    func beginTermination(for application: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminationInProgress else {
            return .terminateLater
        }

        isTerminationInProgress = true

        Task { @MainActor [weak self] in
            if let library = self?.library {
                await library.shutdownGracefully(timeout: 2.0)
            }
            application.reply(toApplicationShouldTerminate: true)
        }

        return .terminateLater
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
