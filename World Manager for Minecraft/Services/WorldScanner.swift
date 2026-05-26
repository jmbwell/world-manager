//
//  WorldScanner.swift
//  World Manager for Minecraft
//
//  Created by John Burwell on 2026-05-25.
//

import Foundation

enum WorldScanner {
    nonisolated static func loadSize(for item: MinecraftContentItem) -> MinecraftContentItem {
        let fileManager = FileManager.default
        var sizedItem = item
        sizedItem.sizeBytes = folderSize(at: item.folderURL, fileManager: fileManager)
        sizedItem.sizeLoaded = true
        return sizedItem
    }

    nonisolated static func beginScanSession(for sourceRootURL: URL) async {
        await packReferenceIndexStore.reset(for: sourceRootURL)
    }

    nonisolated static func endScanSession(for sourceRootURL: URL) async {
        await packReferenceIndexStore.reset(for: sourceRootURL)
    }

    nonisolated static func discoverItems(
        in searchRootURL: URL,
        onDiscovered: @Sendable (MinecraftContentItem) -> Void = { _ in }
    ) throws -> [MinecraftContentItem] {
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
                    let item = MinecraftContentItem(
                        folderURL: childDirectory,
                        folderName: childDirectory.lastPathComponent,
                        contentType: contentType,
                        collectionRootURL: directoryURL
                    )
                    seenItemURLs.insert(itemURL)
                    discoveredItems.append(item)
                    onDiscovered(item)

                    if contentType == .world {
                        let embeddedPackItems = discoverEmbeddedPackItems(
                            in: childDirectory,
                            fileManager: fileManager,
                            seenItemURLs: &seenItemURLs
                        )
                        discoveredItems.append(contentsOf: embeddedPackItems)
                        embeddedPackItems.forEach(onDiscovered)
                    }
                }
            }
        }

        discoveredItems.sort(by: sortItems)
        return discoveredItems
    }

    nonisolated static func enrich(item: MinecraftContentItem) async -> MinecraftContentItem {
        let fileManager = FileManager.default
        var enrichedItem = item

        enrichedItem.displayName = displayName(for: item, fileManager: fileManager)
        enrichedItem.iconURL = iconURL(for: item, fileManager: fileManager)
        enrichedItem.lastPlayedDate = lastPlayedDate(for: item, fileManager: fileManager)
        enrichedItem.modifiedDate = modifiedDate(for: item.folderURL)
        if let manifestMetadata = manifestMetadata(in: item.folderURL, fileManager: fileManager) {
            enrichedItem.packUUID = manifestMetadata.uuid
            enrichedItem.packVersion = manifestMetadata.version
            if !manifestMetadata.name.isEmpty {
                enrichedItem.displayName = manifestMetadata.name
            }
        }
        enrichedItem.packReferences = await packReferences(for: item, fileManager: fileManager)
        enrichedItem.metadataLoaded = true
        enrichedItem.sizeLoaded = false

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

    nonisolated fileprivate static func immediateChildDirectories(of directoryURL: URL, fileManager: FileManager) throws -> [URL] {
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

    nonisolated private static func discoverEmbeddedPackItems(
        in worldDirectoryURL: URL,
        fileManager: FileManager,
        seenItemURLs: inout Set<URL>
    ) -> [MinecraftContentItem] {
        let embeddedCollections: [(MinecraftContentType, URL)] = [
            (.behaviorPack, worldDirectoryURL.appendingPathComponent("behavior_packs", isDirectory: true)),
            (.resourcePack, worldDirectoryURL.appendingPathComponent("resource_packs", isDirectory: true))
        ]

        var embeddedItems: [MinecraftContentItem] = []

        for (contentType, collectionURL) in embeddedCollections {
            guard
                fileManager.fileExists(atPath: collectionURL.path),
                let childDirectories = try? immediateChildDirectories(of: collectionURL, fileManager: fileManager)
            else {
                continue
            }

            for childDirectory in childDirectories {
                let itemURL = childDirectory.standardizedFileURL
                guard !seenItemURLs.contains(itemURL) else {
                    continue
                }

                guard isCandidateItem(at: childDirectory, type: contentType, fileManager: fileManager) else {
                    continue
                }

                let item = MinecraftContentItem(
                    folderURL: childDirectory,
                    folderName: childDirectory.lastPathComponent,
                    contentType: contentType,
                    collectionRootURL: collectionURL
                )
                seenItemURLs.insert(itemURL)
                embeddedItems.append(item)
            }
        }

        return embeddedItems
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
        manifestMetadata(in: directoryURL, fileManager: fileManager)?.name
    }

    nonisolated private static func packIconURL(in directoryURL: URL, fileManager: FileManager) -> URL? {
        let candidateNames = ["pack_icon.png", "pack_icon.jpeg", "pack_icon.jpg"]

        for candidateName in candidateNames {
            let candidateURL = directoryURL.appendingPathComponent(candidateName)
            if fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return nil
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

    nonisolated private static func lastPlayedDate(for item: MinecraftContentItem, fileManager: FileManager) -> Date? {
        guard item.contentType == .world else {
            return nil
        }

        // Bedrock's level.dat requires format-specific parsing to distinguish a true
        // last-played timestamp from general save metadata. Until that is implemented
        // reliably, prefer surfacing the filesystem modified date only.
        _ = fileManager
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

    nonisolated private static func packReferences(for item: MinecraftContentItem, fileManager: FileManager) async -> [ContentPackReference] {
        switch item.contentType {
        case .world:
            var references = await referencedWorldPacks(for: item, fileManager: fileManager)
            references.append(contentsOf: embeddedWorldPacks(for: item, fileManager: fileManager))
            return uniquePackReferences(references)
        case .behaviorPack, .resourcePack, .skinPack, .worldTemplate:
            return []
        }
    }

    nonisolated private static func referencedWorldPacks(for item: MinecraftContentItem, fileManager: FileManager) async -> [ContentPackReference] {
        let behaviorReferences = await packReferences(
            fromWorldReferenceFileNamed: "world_behavior_packs.json",
            type: .behaviorPack,
            worldFolderURL: item.folderURL,
            fileManager: fileManager
        )
        let resourceReferences = await packReferences(
            fromWorldReferenceFileNamed: "world_resource_packs.json",
            type: .resourcePack,
            worldFolderURL: item.folderURL,
            fileManager: fileManager
        )

        return behaviorReferences + resourceReferences
    }

    nonisolated private static func embeddedWorldPacks(for item: MinecraftContentItem, fileManager: FileManager) -> [ContentPackReference] {
        var references: [ContentPackReference] = []

        references.append(
            contentsOf: embeddedPackReferences(
                in: item.folderURL.appendingPathComponent("behavior_packs", isDirectory: true),
                type: .behaviorPack,
                fileManager: fileManager
            )
        )
        references.append(
            contentsOf: embeddedPackReferences(
                in: item.folderURL.appendingPathComponent("resource_packs", isDirectory: true),
                type: .resourcePack,
                fileManager: fileManager
            )
        )

        return references
    }

    nonisolated private static func packReferences(
        fromWorldReferenceFileNamed filename: String,
        type: MinecraftContentType,
        worldFolderURL: URL,
        fileManager: FileManager
    ) async -> [ContentPackReference] {
        let fileURL = worldFolderURL.appendingPathComponent(filename)
        guard
            fileManager.fileExists(atPath: fileURL.path),
            let data = try? Data(contentsOf: fileURL),
            let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return []
        }

        var references: [ContentPackReference] = []

        for entry in jsonObject {
            let uuid = (entry["pack_id"] as? String)?.lowercased()
            let version = versionString(from: entry["version"])
            let resolvedPack: ContentPackReference?
            if let uuid {
                resolvedPack = await resolvedPackReference(
                    uuid: uuid,
                    type: type,
                    worldCollectionRootURL: worldFolderURL.deletingLastPathComponent()
                )
            } else {
                resolvedPack = nil
            }
            let fallbackName = resolvedPack?.name ?? uuid ?? "Referenced Pack"
            references.append(
                ContentPackReference(
                    name: fallbackName,
                    type: type,
                    iconURL: resolvedPack?.iconURL,
                    uuid: uuid,
                    version: resolvedPack?.version ?? version,
                    source: .referencedByWorld
                )
            )
        }

        return references
    }

    nonisolated private static func embeddedPackReferences(
        in directoryURL: URL,
        type: MinecraftContentType,
        fileManager: FileManager
    ) -> [ContentPackReference] {
        guard
            fileManager.fileExists(atPath: directoryURL.path),
            let childDirectories = try? immediateChildDirectories(of: directoryURL, fileManager: fileManager)
        else {
            return []
        }

        return childDirectories.compactMap { childDirectory in
            packReference(
                fromPackFolder: childDirectory,
                type: type,
                source: .embeddedInWorld,
                fileManager: fileManager
            )
        }
    }

    nonisolated fileprivate static func packReference(
        fromPackFolder directoryURL: URL,
        type: MinecraftContentType,
        source: PackSource,
        fileManager: FileManager
    ) -> ContentPackReference? {
        guard let metadata = manifestMetadata(in: directoryURL, fileManager: fileManager) else {
            return nil
        }

        return ContentPackReference(
            name: metadata.name,
            type: type,
            iconURL: packIconURL(in: directoryURL, fileManager: fileManager),
            uuid: metadata.uuid,
            version: metadata.version,
            source: source
        )
    }

    nonisolated private static func resolvedPackReference(
        uuid: String,
        type: MinecraftContentType,
        worldCollectionRootURL: URL
    ) async -> ContentPackReference? {
        let siblingCollectionURL = worldCollectionRootURL
            .deletingLastPathComponent()
            .appendingPathComponent(type.collectionFolderName, isDirectory: true)

        return await packReferenceIndexStore.reference(
            forUUID: uuid,
            type: type,
            in: siblingCollectionURL
        )
    }

    nonisolated private static func versionString(from value: Any?) -> String? {
        if let versionString = value as? String, !versionString.isEmpty {
            return versionString
        }

        if let versionArray = value as? [Any] {
            let components = versionArray.compactMap { component -> String? in
                if let intComponent = component as? Int {
                    return String(intComponent)
                }
                if let stringComponent = component as? String {
                    return stringComponent
                }
                return nil
            }

            return components.isEmpty ? nil : components.joined(separator: ".")
        }

        return nil
    }

    nonisolated private static func manifestMetadata(in directoryURL: URL, fileManager: FileManager) -> ManifestMetadata? {
        let manifestURL = directoryURL.appendingPathComponent("manifest.json")
        guard
            fileManager.fileExists(atPath: manifestURL.path),
            let data = try? Data(contentsOf: manifestURL),
            let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let header = jsonObject["header"] as? [String: Any]
        else {
            return nil
        }

        let name = ((header["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : $0
        } ?? directoryURL.lastPathComponent

        return ManifestMetadata(
            name: name,
            uuid: (header["uuid"] as? String)?.lowercased(),
            version: versionString(from: header["version"])
        )
    }

    nonisolated private static func uniquePackReferences(_ references: [ContentPackReference]) -> [ContentPackReference] {
        var seen = Set<String>()
        var uniqueReferences: [ContentPackReference] = []

        for reference in references {
            let dedupeKey = [reference.type.rawValue, reference.uuid ?? reference.name, reference.version ?? ""]
                .joined(separator: "::")
            guard seen.insert(dedupeKey).inserted else {
                continue
            }

            uniqueReferences.append(reference)
        }

        return uniqueReferences.sorted { lhs, rhs in
            if lhs.type != rhs.type {
                return lhs.type.rawValue.localizedStandardCompare(rhs.type.rawValue) == .orderedAscending
            }

            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

private struct ManifestMetadata {
    let name: String
    let uuid: String?
    let version: String?
}

private actor PackReferenceIndexStore {
    private var referencesByCollectionURL: [URL: [String: ContentPackReference]] = [:]

    func reset(for sourceRootURL: URL) {
        let sourceRootPath = sourceRootURL.standardizedFileURL.path
        referencesByCollectionURL = referencesByCollectionURL.filter { collectionURL, _ in
            !collectionURL.standardizedFileURL.path.hasPrefix(sourceRootPath + "/")
        }
    }

    func reference(forUUID uuid: String, type: MinecraftContentType, in collectionURL: URL) -> ContentPackReference? {
        let normalizedCollectionURL = collectionURL.standardizedFileURL

        if let cachedReferences = referencesByCollectionURL[normalizedCollectionURL] {
            return cachedReferences[uuid]
        }

        let fileManager = FileManager.default
        guard
            fileManager.fileExists(atPath: normalizedCollectionURL.path),
            let childDirectories = try? WorldScanner.immediateChildDirectories(
                of: normalizedCollectionURL,
                fileManager: fileManager
            )
        else {
            referencesByCollectionURL[normalizedCollectionURL] = [:]
            return nil
        }

        var referencesByUUID: [String: ContentPackReference] = [:]
        for childDirectory in childDirectories {
            guard
                let reference = WorldScanner.packReference(
                    fromPackFolder: childDirectory,
                    type: type,
                    source: .foundInCollection,
                    fileManager: fileManager
                ),
                let referenceUUID = reference.uuid
            else {
                continue
            }

            referencesByUUID[referenceUUID] = reference
        }

        referencesByCollectionURL[normalizedCollectionURL] = referencesByUUID
        return referencesByUUID[uuid]
    }
}

private let packReferenceIndexStore = PackReferenceIndexStore()
