//
//  WorldScanner.swift
//  World Manager for Minecraft
//
//  Created by John Burwell on 2026-05-25.
//

import Foundation

enum WorldScanner {
    nonisolated static func discoverItems(in searchRootURL: URL) throws -> [MinecraftContentItem] {
        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey]

        guard let enumerator = fileManager.enumerator(
            at: searchRootURL,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var discoveredItems: [MinecraftContentItem] = []
        var seenItemURLs = Set<URL>()

        for case let directoryURL as URL in enumerator {
            guard (try? directoryURL.resourceValues(forKeys: Set(resourceKeys)).isDirectory) == true else {
                continue
            }

            guard let contentType = contentType(forCollectionFolderName: directoryURL.lastPathComponent) else {
                continue
            }

            let childDirectories = try immediateChildDirectories(of: directoryURL, fileManager: fileManager)
            for childDirectory in childDirectories {
                let itemURL = childDirectory.standardizedFileURL
                guard !seenItemURLs.contains(itemURL) else {
                    continue
                }

                if isCandidateItem(at: childDirectory, type: contentType, fileManager: fileManager) {
                    seenItemURLs.insert(itemURL)
                    discoveredItems.append(
                        MinecraftContentItem(
                            folderURL: childDirectory,
                            folderName: childDirectory.lastPathComponent,
                            contentType: contentType,
                            collectionRootURL: directoryURL
                        )
                    )
                }
            }
        }

        discoveredItems.sort(by: sortItems)
        return discoveredItems
    }

    nonisolated static func enrich(item: MinecraftContentItem) -> MinecraftContentItem {
        let fileManager = FileManager.default
        var enrichedItem = item

        enrichedItem.displayName = displayName(for: item, fileManager: fileManager)
        enrichedItem.iconURL = iconURL(for: item, fileManager: fileManager)
        enrichedItem.modifiedDate = modifiedDate(for: item.folderURL)
        enrichedItem.sizeBytes = folderSize(at: item.folderURL, fileManager: fileManager)
        enrichedItem.metadataLoaded = true

        return enrichedItem
    }

    nonisolated static func sortItems(_ lhs: MinecraftContentItem, _ rhs: MinecraftContentItem) -> Bool {
        if lhs.contentType != rhs.contentType {
            return lhs.contentType.rawValue.localizedStandardCompare(rhs.contentType.rawValue) == .orderedAscending
        }

        let displayNameOrder = lhs.displayName.localizedStandardCompare(rhs.displayName)
        if displayNameOrder != .orderedSame {
            return displayNameOrder == .orderedAscending
        }

        return lhs.folderName.localizedStandardCompare(rhs.folderName) == .orderedAscending
    }

    nonisolated private static func contentType(forCollectionFolderName folderName: String) -> MinecraftContentType? {
        let normalizedFolderName = folderName.lowercased()

        return MinecraftContentType.allCases.first { type in
            type.collectionFolderName.lowercased() == normalizedFolderName
        }
    }

    nonisolated private static func immediateChildDirectories(of directoryURL: URL, fileManager: FileManager) throws -> [URL] {
        let children = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return children.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    nonisolated private static func isCandidateItem(at directoryURL: URL, type: MinecraftContentType, fileManager: FileManager) -> Bool {
        switch type {
        case .world:
            return fileManager.fileExists(atPath: directoryURL.appendingPathComponent("level.dat").path)
                || fileManager.fileExists(atPath: directoryURL.appendingPathComponent("db", isDirectory: true).path)
                || fileManager.fileExists(atPath: directoryURL.appendingPathComponent("levelname.txt").path)
        case .behaviorPack, .resourcePack, .skinPack, .worldTemplate:
            return fileManager.fileExists(atPath: directoryURL.appendingPathComponent("manifest.json").path)
                || fileManager.fileExists(atPath: directoryURL.appendingPathComponent("pack_icon.png").path)
                || fileManager.fileExists(atPath: directoryURL.appendingPathComponent("pack_icon.jpeg").path)
                || fileManager.fileExists(atPath: directoryURL.appendingPathComponent("pack_icon.jpg").path)
        }
    }

    nonisolated private static func displayName(for item: MinecraftContentItem, fileManager: FileManager) -> String {
        switch item.contentType {
        case .world:
            let levelNameURL = item.folderURL.appendingPathComponent("levelname.txt")
            guard
                let name = try? String(contentsOf: levelNameURL, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !name.isEmpty
            else {
                return item.folderName
            }

            return name
        case .behaviorPack, .resourcePack, .skinPack, .worldTemplate:
            if let manifestName = manifestName(in: item.folderURL, fileManager: fileManager) {
                return manifestName
            }

            return item.folderName
        }
    }

    nonisolated private static func manifestName(in directoryURL: URL, fileManager: FileManager) -> String? {
        let manifestURL = directoryURL.appendingPathComponent("manifest.json")
        guard
            fileManager.fileExists(atPath: manifestURL.path),
            let data = try? Data(contentsOf: manifestURL),
            let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let header = jsonObject["header"] as? [String: Any],
            let name = (header["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !name.isEmpty
        else {
            return nil
        }

        return name
    }

    nonisolated private static func iconURL(for item: MinecraftContentItem, fileManager: FileManager) -> URL? {
        let candidateNames: [String]

        switch item.contentType {
        case .world:
            candidateNames = ["world_icon.jpeg", "world_icon.jpg", "world_icon.png"]
        case .behaviorPack, .resourcePack, .skinPack, .worldTemplate:
            candidateNames = ["pack_icon.png", "pack_icon.jpeg", "pack_icon.jpg"]
        }

        for candidateName in candidateNames {
            let candidateURL = item.folderURL.appendingPathComponent(candidateName)
            if fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return nil
    }

    nonisolated private static func modifiedDate(for directoryURL: URL) -> Date? {
        try? directoryURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
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
