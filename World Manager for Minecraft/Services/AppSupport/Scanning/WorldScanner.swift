// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

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

    nonisolated static func discoverItems(
        inCollectionRootURL collectionRootURL: URL,
        contentType: MinecraftContentType,
        onDiscovered: @Sendable (MinecraftContentItem) -> Void = { _ in }
    ) throws -> [MinecraftContentItem] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: collectionRootURL.path) else {
            return []
        }

        let childDirectories = try immediateChildDirectories(of: collectionRootURL, fileManager: fileManager)
        var discoveredItems: [MinecraftContentItem] = []
        var seenItemURLs = Set<URL>()

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
                collectionRootURL: collectionRootURL
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

        discoveredItems.sort(by: sortItems)
        return discoveredItems
    }

    nonisolated static func collectionSnapshots(in sourceRootURL: URL) -> [CollectionSnapshot] {
        let fileManager = FileManager.default
        return MinecraftContentType.allCases.compactMap { type in
            collectionSnapshot(
                for: sourceRootURL.appendingPathComponent(type.collectionFolderName, isDirectory: true),
                contentType: type,
                fileManager: fileManager
            )
        }
    }

    nonisolated static func enrich(item: MinecraftContentItem) async -> MinecraftContentItem {
        let fileManager = FileManager.default
        var enrichedItem = item

        enrichedItem.displayName = MinecraftContentMetadataReader.displayName(
            for: item.folderURL,
            contentType: item.contentType,
            fallbackName: item.folderName,
            fileManager: fileManager
        )
        let sourceIconURL = MinecraftContentMetadataReader.iconURL(
            for: item.folderURL,
            contentType: item.contentType,
            fileManager: fileManager
        )
        enrichedItem.iconURL = await ImageCacheStore.shared.cachedImageURL(for: sourceIconURL)
        enrichedItem.worldMetadata = item.contentType == .world
            ? MinecraftContentMetadataReader.worldMetadata(in: item.folderURL, fileManager: fileManager)
            : nil
        enrichedItem.lastPlayedDate = lastPlayedDate(for: item, fileManager: fileManager, worldMetadata: enrichedItem.worldMetadata)
        enrichedItem.modifiedDate = modifiedDate(for: item.folderURL)
        if let manifestMetadata = MinecraftContentMetadataReader.manifestMetadata(in: item.folderURL, fileManager: fileManager) {
            enrichedItem.packUUID = manifestMetadata.uuid
            enrichedItem.packVersion = manifestMetadata.version
            enrichedItem.packMetadataDetails = PackMetadataDetails(
                minimumEngineVersion: manifestMetadata.minimumEngineVersion
            )
            if !manifestMetadata.name.isEmpty {
                enrichedItem.displayName = manifestMetadata.name
            }
        }
        enrichedItem.packReferences = await packReferences(for: item, fileManager: fileManager)
        enrichedItem.metadataLoaded = true
        enrichedItem.previewLoaded = true
        enrichedItem.sizeLoaded = false

        return enrichedItem
    }

    nonisolated static func sortItems(_ lhs: MinecraftContentItem, _ rhs: MinecraftContentItem) -> Bool {
        MinecraftContentItem.displaySort(lhs, rhs)
    }

    nonisolated private static func contentType(forCollectionFolderName folderName: String) -> MinecraftContentType? {
        let normalizedFolderName = folderName.lowercased()

        return MinecraftContentType.allCases.first { type in
            type.collectionFolderName.lowercased() == normalizedFolderName
        }
    }

    nonisolated private static func collectionSnapshot(
        for collectionURL: URL,
        contentType: MinecraftContentType,
        fileManager: FileManager
    ) -> CollectionSnapshot? {
        guard fileManager.fileExists(atPath: collectionURL.path) else {
            return nil
        }

        let children = (try? fileManager.contentsOfDirectory(
            at: collectionURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let childDirectorySnapshots = children.compactMap { childURL -> (name: String, modifiedDate: Date?)? in
            guard (try? childURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }

            let modifiedDate = try? childURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            return (childURL.lastPathComponent, modifiedDate)
        }.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        let modifiedDate = try? collectionURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let childFingerprint = childDirectorySnapshots.map { child in
            [
                child.name,
                child.modifiedDate?.timeIntervalSince1970.formatted() ?? "nil"
            ].joined(separator: "@")
        }.joined(separator: "|")

        return CollectionSnapshot(
            folderName: contentType.collectionFolderName,
            modifiedDate: modifiedDate,
            childDirectoryCount: childDirectorySnapshots.count,
            fingerprint: [
                contentType.collectionFolderName,
                String(childDirectorySnapshots.count),
                modifiedDate?.timeIntervalSince1970.formatted() ?? "nil",
                childFingerprint
            ].joined(separator: "::")
        )
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

    nonisolated private static func lastPlayedDate(
        for item: MinecraftContentItem,
        fileManager: FileManager,
        worldMetadata: WorldMetadata?
    ) -> Date? {
        guard item.contentType == .world else {
            return nil
        }

        _ = fileManager
        return worldMetadata?.lastPlayedDate
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
            let version = MinecraftContentMetadataReader.versionString(from: entry["version"])
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
        guard let metadata = MinecraftContentMetadataReader.manifestMetadata(in: directoryURL, fileManager: fileManager) else {
            return nil
        }

        return ContentPackReference(
            name: metadata.name,
            type: type,
            iconURL: MinecraftContentMetadataReader.packIconURL(in: directoryURL, fileManager: fileManager),
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
