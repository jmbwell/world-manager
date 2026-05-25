//
//  ContentView.swift
//  World Manager for Minecraft
//
//  Created by John Burwell on 2026-05-25.
//

import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var scanner = WorldScanner()
    @State private var folderURL: URL?
    @State private var selectedWorld: MinecraftWorld?

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 12) {
                Button("Choose Minecraft Worlds Folder...") {
                    pickFolder()
                }

                if let folderURL {
                    Text(folderURL.path)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else {
                    Text("No folder selected")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if scanner.isScanning {
                    ProgressView(scanner.scanStatus)
                } else if !scanner.scanStatus.isEmpty {
                    Text(scanner.scanStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let scanError = scanner.scanError {
                    Text(scanError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Folder")
        } content: {
            List(scanner.worlds, selection: $selectedWorld) { world in
                VStack(alignment: .leading, spacing: 4) {
                    Text(world.displayName)
                    Text(world.folderName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Worlds")
        } detail: {
            if let selectedWorld {
                VStack(alignment: .leading, spacing: 12) {
                    Text(selectedWorld.displayName)
                        .font(.title2)

                    Text(selectedWorld.folderName)
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    if let modifiedDate = selectedWorld.modifiedDate {
                        Text("Modified: \(modifiedDate.formatted(date: .abbreviated, time: .shortened))")
                    }

                    if let sizeBytes = selectedWorld.sizeBytes {
                        Text("Size: \(ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file))")
                    }

                    Spacer()
                }
                .padding()
            } else {
                Text("Select a world to see details")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Minecraft World Manager")
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.title = "Choose Minecraft Worlds Folder"

        guard panel.runModal() == .OK, let pickedURL = panel.url else {
            return
        }

        folderURL = pickedURL
        selectedWorld = nil

        Task {
            await scanner.scan(at: pickedURL)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
