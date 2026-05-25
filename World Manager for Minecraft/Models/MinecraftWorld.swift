//
//  MinecraftWorld.swift
//  World Manager for Minecraft
//
//  Created by John Burwell on 2026-05-25.
//

import Foundation

struct MinecraftWorld: Identifiable, Hashable {
    let id = UUID()
    let folderURL: URL
    let folderName: String
    let displayName: String
    let iconURL: URL?
    let modifiedDate: Date?
    let sizeBytes: Int64?
    let isValidWorld: Bool
}
