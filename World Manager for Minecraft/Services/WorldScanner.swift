//
//  WorldScanner.swift
//  World Manager for Minecraft
//
//  Created by John Burwell on 2026-05-25.
//

import Combine
import Foundation

@MainActor
final class WorldScanner: ObservableObject {
    @Published var worlds: [MinecraftWorld] = []
    @Published var isScanning = false
    @Published var scanStatus = ""
    @Published var scanError: String?

    func scan(at parentFolderURL: URL) async {
        isScanning = true
        scanError = nil
        scanStatus = "Scanning worlds..."
        worlds = []

        do {
            let worlds = try await Task.detached(priority: .userInitiated) {
                try Self.scanWorlds(at: parentFolderURL)
            }.value

            self.worlds = worlds
            self.scanStatus = worlds.isEmpty ? "No worlds found." : "Found \(worlds.count) worlds."
        } catch {
            scanError = "Failed to scan folder: \(error.localizedDescription)"
            scanStatus = ""
        }

        isScanning = false
    }

    nonisolated private static func scanWorlds(at parentFolderURL: URL) throws -> [MinecraftWorld] {
        let fileManager = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey]
        let children = try fileManager.contentsOfDirectory(
            at: parentFolderURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )

        return try children.compactMap { childURL in
            let values = try childURL.resourceValues(forKeys: resourceKeys)
            guard values.isDirectory == true else {
                return nil
            }

            let isValidWorld = isLikelyWorldFolder(childURL, fileManager: fileManager)
            guard isValidWorld else {
                return nil
            }

            let folderName = childURL.lastPathComponent
            let displayName = readDisplayName(in: childURL, fallback: folderName)
            let iconURL = iconURL(in: childURL, fileManager: fileManager)
            let sizeBytes = folderSize(at: childURL, fileManager: fileManager)

            return MinecraftWorld(
                folderURL: childURL,
                folderName: folderName,
                displayName: displayName,
                iconURL: iconURL,
                modifiedDate: values.contentModificationDate,
                sizeBytes: sizeBytes,
                isValidWorld: true
            )
        }
        .sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    nonisolated private static func isLikelyWorldFolder(_ url: URL, fileManager: FileManager) -> Bool {
        let levelDatURL = url.appendingPathComponent("level.dat")
        let dbURL = url.appendingPathComponent("db", isDirectory: true)
        let levelNameURL = url.appendingPathComponent("levelname.txt")

        return fileManager.fileExists(atPath: levelDatURL.path)
            || fileManager.fileExists(atPath: dbURL.path)
            || fileManager.fileExists(atPath: levelNameURL.path)
    }

    nonisolated private static func readDisplayName(in worldURL: URL, fallback: String) -> String {
        let levelNameURL = worldURL.appendingPathComponent("levelname.txt")

        guard
            let name = try? String(contentsOf: levelNameURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !name.isEmpty
        else {
            return fallback
        }

        return name
    }

    nonisolated private static func iconURL(in worldURL: URL, fileManager: FileManager) -> URL? {
        let iconURL = worldURL.appendingPathComponent("world_icon.jpeg")
        return fileManager.fileExists(atPath: iconURL.path) ? iconURL : nil
    }

    nonisolated private static func folderSize(at folderURL: URL, fileManager: FileManager) -> Int64? {
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var totalSize: Int64 = 0

        for case let fileURL as URL in enumerator {
            guard
                let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                values.isRegularFile == true,
                let fileSize = values.fileSize
            else {
                continue
            }

            totalSize += Int64(fileSize)
        }

        return totalSize
    }
}
