//
//  MinecraftSource.swift
//  World Manager for Minecraft
//
//  Created by John Burwell on 2026-05-25.
//

import Foundation

struct MinecraftSource: Identifiable, Hashable, Sendable {
    let id: URL
    let folderURL: URL
    var displayName: String
    var items: [MinecraftContentItem]
    var isScanning: Bool
    var scanStatus: String
    var scanError: String?

    init(folderURL: URL) {
        let normalizedURL = folderURL.standardizedFileURL
        self.id = normalizedURL
        self.folderURL = normalizedURL
        self.displayName = normalizedURL.lastPathComponent
        self.items = []
        self.isScanning = false
        self.scanStatus = ""
        self.scanError = nil
    }

    var itemCount: Int {
        items.count
    }
}
