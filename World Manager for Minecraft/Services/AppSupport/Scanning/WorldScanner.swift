// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

typealias WorldScanner = BedrockContentScanner

enum BedrockContentScanner {
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

    nonisolated static func probeLocalFolder(_ url: URL, providerID: PlatformProviderID) -> SourceProbeResult? {
        let fileManager = FileManager.default
        let normalizedURL = url.standardizedFileURL
        var detectedKinds = Set<MinecraftContentKind>()
        var score = 0

        let collectionKinds: [(String, MinecraftContentKind)] = [
            ("minecraftWorlds", .world),
            ("behavior_packs", .behaviorPack),
            ("resource_packs", .resourcePack),
            ("skin_packs", .skinPack),
            ("world_templates", .worldTemplate)
        ]

        for (folderName, kind) in collectionKinds {
            if fileManager.fileExists(atPath: normalizedURL.appendingPathComponent(folderName, isDirectory: true).path) {
                detectedKinds.insert(kind)
                score += 25
            }
        }

        if fileManager.fileExists(atPath: normalizedURL.appendingPathComponent("db", isDirectory: true).path)
            || fileManager.fileExists(atPath: normalizedURL.appendingPathComponent("levelname.txt").path) {
            detectedKinds.insert(.world)
            score += 35
        }

        guard score > 0 else {
            return nil
        }

        let confidence: SourceProbeConfidence = score >= 50 ? .strong : .medium
        return SourceProbeResult(
            providerID: providerID,
            edition: .bedrock,
            confidence: confidence,
            sourceRootURL: normalizedURL,
            displayName: normalizedURL.lastPathComponent,
            detectedKinds: detectedKinds,
            warnings: []
        )
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
        enrichedItem.modifiedDate = WorldScanner.modifiedDate(for: item.folderURL)
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

    nonisolated fileprivate static func modifiedDate(for directoryURL: URL) -> Date? {
        try? directoryURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    nonisolated fileprivate static func folderSize(at folderURL: URL, fileManager: FileManager) -> Int64? {
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

enum JavaContentScanner {
    nonisolated static func probeLocalFolder(_ url: URL, providerID: PlatformProviderID) -> SourceProbeResult? {
        let fileManager = FileManager.default
        let candidates = localFolderProbeCandidates(for: url.standardizedFileURL, fileManager: fileManager)
        let scoredCandidates = candidates.compactMap { candidate -> (url: URL, score: Int, kinds: Set<MinecraftContentKind>)? in
            let score = javaProbeScore(for: candidate, fileManager: fileManager)
            guard score.value > 0 else {
                return nil
            }

            return (candidate, score.value, score.kinds)
        }

        guard let best = scoredCandidates.max(by: { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score < rhs.score
            }

            return lhs.url.path.count > rhs.url.path.count
        }) else {
            return nil
        }

        let confidence: SourceProbeConfidence
        if best.score >= 70 {
            confidence = .exact
        } else if best.score >= 45 {
            confidence = .strong
        } else {
            confidence = .medium
        }

        let warnings = best.url.standardizedFileURL == url.standardizedFileURL ? [] : [
            "Using nested Java instance folder: \(best.url.lastPathComponent)"
        ]

        return SourceProbeResult(
            providerID: providerID,
            edition: .java,
            confidence: confidence,
            sourceRootURL: best.url.standardizedFileURL,
            displayName: best.url.lastPathComponent,
            detectedKinds: best.kinds,
            warnings: warnings
        )
    }

    nonisolated static func discoverSourceCandidates(
        providerID: PlatformProviderID,
        searchRoots: [URL]? = nil,
        fileManager: FileManager = .default
    ) -> [SourceCandidate] {
        let roots = uniqueStandardizedURLs(searchRoots ?? defaultCandidateSearchRoots(fileManager: fileManager))
            .map(\.standardizedFileURL)
            .filter { fileManager.fileExists(atPath: $0.path) }

        var candidatesByID: [String: SourceCandidate] = [:]
        for root in roots {
            let candidateFolders = boundedCandidateFolders(from: root, maxDepth: 4, maxFolderCount: 600, fileManager: fileManager)
            var candidatesForRoot: [SourceCandidate] = []
            for folderURL in candidateFolders {
                guard let probe = probeLocalFolder(folderURL, providerID: providerID) else {
                    continue
                }

                let candidate = SourceCandidate(
                    providerID: probe.providerID,
                    edition: probe.edition,
                    sourceRootURL: probe.sourceRootURL,
                    displayName: probe.displayName,
                    confidence: probe.confidence,
                    reason: "Found Java markers near \(root.lastPathComponent)",
                    detectedKinds: probe.detectedKinds
                )

                candidatesForRoot.append(candidate)
            }

            for candidate in collapsedCandidates(
                candidatesForRoot,
                under: root,
                providerID: providerID
            ) {
                if let existingCandidate = candidatesByID[candidate.id],
                   existingCandidate.confidence >= candidate.confidence {
                    continue
                }

                candidatesByID[candidate.id] = candidate
            }
        }

        return candidatesByID.values.sorted {
            if $0.confidence != $1.confidence {
                return $0.confidence > $1.confidence
            }

            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    nonisolated static func discoverItems(
        in searchRootURL: URL,
        onDiscovered: @Sendable (MinecraftContentItem) -> Void = { _ in }
    ) throws -> [MinecraftContentItem] {
        let fileManager = FileManager.default
        var discoveredItems: [MinecraftContentItem] = []

        for scanRootURL in contentScanRoots(for: searchRootURL, fileManager: fileManager) {
            let savesRootURL = existingDirectory(
                named: "saves",
                in: scanRootURL,
                fileManager: fileManager
            ) ?? scanRootURL
            let worldItems = try discoverWorlds(in: savesRootURL, fileManager: fileManager)
            discoveredItems.append(contentsOf: worldItems)

            if let resourcePacksURL = existingDirectory(named: "resourcepacks", in: scanRootURL, fileManager: fileManager) {
                let resourcePackItems = try discoverResourcePacks(in: resourcePacksURL, fileManager: fileManager)
                discoveredItems.append(contentsOf: resourcePackItems)
            }

            if let dataPacksURL = existingDirectory(named: "datapacks", in: scanRootURL, fileManager: fileManager) {
                discoveredItems.append(contentsOf: try discoverJavaPackages(
                    in: dataPacksURL,
                    contentKind: .dataPack,
                    platformType: .dataPack,
                    packageExtension: "zip",
                    fileManager: fileManager
                ))
            }

            if let shaderPacksURL = existingDirectory(named: "shaderpacks", in: scanRootURL, fileManager: fileManager) {
                discoveredItems.append(contentsOf: try discoverJavaPackages(
                    in: shaderPacksURL,
                    contentKind: .shaderPack,
                    platformType: .shaderPack,
                    packageExtension: "zip",
                    fileManager: fileManager
                ))
            }

            if let modsURL = existingDirectory(named: "mods", in: scanRootURL, fileManager: fileManager) {
                discoveredItems.append(contentsOf: try discoverJavaPackages(
                    in: modsURL,
                    contentKind: .mod,
                    platformType: .mod,
                    packageExtension: "jar",
                    fileManager: fileManager
                ))
            }
        }

        discoveredItems.sort(by: WorldScanner.sortItems)
        discoveredItems.forEach(onDiscovered)
        return discoveredItems
    }

    nonisolated static func enrich(item: MinecraftContentItem) async -> MinecraftContentItem {
        var enrichedItem = item
        let metadata = JavaContentMetadataReader.metadata(for: item)
        enrichedItem.displayName = metadata?.displayName ?? displayName(for: item)
        enrichedItem.iconURL = await JavaContentMetadataReader.cachedIconURL(for: item, metadata: metadata)
        if metadata?.pack != nil || metadata?.mod != nil {
            enrichedItem.platformMetadata = .java(JavaContentMetadata(
                pack: metadata?.pack,
                mod: metadata?.mod
            ))
        }
        enrichedItem.hasKnownIcon = enrichedItem.iconURL != nil
        enrichedItem.modifiedDate = WorldScanner.modifiedDate(for: item.folderURL)
        enrichedItem.metadataLoaded = true
        enrichedItem.previewLoaded = true
        enrichedItem.sizeLoaded = false
        return enrichedItem
    }

    nonisolated static func loadSize(for item: MinecraftContentItem) -> MinecraftContentItem {
        var sizedItem = item
        sizedItem.sizeBytes = contentSize(at: item.folderURL, fileManager: .default)
        sizedItem.sizeLoaded = true
        return sizedItem
    }

    nonisolated static func collectionSnapshots(in sourceRootURL: URL) -> [CollectionSnapshot] {
        let fileManager = FileManager.default
        var snapshots: [CollectionSnapshot] = []
        for scanRootURL in contentScanRoots(for: sourceRootURL, fileManager: fileManager) {
            let candidateRoots = [
                existingDirectory(named: "saves", in: scanRootURL, fileManager: fileManager),
                existingDirectory(named: "resourcepacks", in: scanRootURL, fileManager: fileManager),
                existingDirectory(named: "datapacks", in: scanRootURL, fileManager: fileManager),
                existingDirectory(named: "shaderpacks", in: scanRootURL, fileManager: fileManager),
                existingDirectory(named: "mods", in: scanRootURL, fileManager: fileManager)
            ]

            for collectionURL in candidateRoots {
                guard let collectionURL else {
                    continue
                }

                if let snapshot = collectionSnapshot(
                    for: collectionURL,
                    sourceRootURL: sourceRootURL,
                    fileManager: fileManager
                ) {
                    snapshots.append(snapshot)
                }
            }
        }

        return snapshots
    }

    nonisolated private static func discoverWorlds(in savesRootURL: URL, fileManager: FileManager) throws -> [MinecraftContentItem] {
        let worldDirectories = try WorldScanner.immediateChildDirectories(of: savesRootURL, fileManager: fileManager)
        return worldDirectories.compactMap { worldURL in
            guard fileManager.fileExists(atPath: worldURL.appendingPathComponent("level.dat").path) else {
                return nil
            }

            return MinecraftContentItem(
                folderURL: worldURL,
                folderName: worldURL.lastPathComponent,
                contentType: .world,
                sourceEdition: .java,
                contentKind: .world,
                platformType: .java(.world),
                collectionRootURL: savesRootURL,
                capabilities: .java(contentType: .world),
                platformMetadata: .java(JavaContentMetadata())
            )
        }
    }

    nonisolated private static func discoverResourcePacks(in resourcePacksURL: URL, fileManager: FileManager) throws -> [MinecraftContentItem] {
        try discoverJavaPackages(
            in: resourcePacksURL,
            contentKind: .resourcePack,
            platformType: .resourcePack,
            packageExtension: "zip",
            fileManager: fileManager,
            folderMarker: "pack.mcmeta"
        )
    }

    nonisolated private static func discoverJavaPackages(
        in collectionURL: URL,
        contentKind: MinecraftContentKind,
        platformType: JavaContentType,
        packageExtension: String,
        fileManager: FileManager,
        folderMarker: String? = nil
    ) throws -> [MinecraftContentItem] {
        let children = try fileManager.contentsOfDirectory(
            at: collectionURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        return children.compactMap { childURL in
            let values = try? childURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            let isDirectory = values?.isDirectory == true
            let isRegularFile = values?.isRegularFile == true

            if isDirectory {
                if let folderMarker,
                   !fileManager.fileExists(atPath: childURL.appendingPathComponent(folderMarker).path) {
                    return nil
                }
            } else if isRegularFile {
                guard childURL.pathExtension.localizedCaseInsensitiveCompare(packageExtension) == .orderedSame else {
                    return nil
                }
            } else {
                return nil
            }

            return javaContentItem(
                url: childURL,
                contentKind: contentKind,
                platformType: platformType,
                collectionRootURL: collectionURL
            )
        }
    }

    nonisolated private static func existingDirectory(named name: String, in rootURL: URL, fileManager: FileManager) -> URL? {
        let directoryURL = rootURL.appendingPathComponent(name, isDirectory: true)
        guard (try? directoryURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            return nil
        }

        return directoryURL
    }

    nonisolated private static func javaContentItem(
        url: URL,
        contentKind: MinecraftContentKind,
        platformType: JavaContentType,
        collectionRootURL: URL
    ) -> MinecraftContentItem {
        MinecraftContentItem(
            folderURL: url,
            folderName: url.lastPathComponent,
            contentType: contentKind == .world ? .world : .resourcePack,
            sourceEdition: .java,
            contentKind: contentKind,
            platformType: .java(platformType),
            collectionRootURL: collectionRootURL,
            displayName: url.deletingPathExtension().lastPathComponent,
            capabilities: .java(contentType: platformType),
            platformMetadata: .java(JavaContentMetadata())
        )
    }

    nonisolated private static func contentSize(at url: URL, fileManager: FileManager) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        if values?.isDirectory == true {
            return WorldScanner.folderSize(at: url, fileManager: fileManager)
        }

        return values?.fileSize.map(Int64.init)
    }

    nonisolated private static func localFolderProbeCandidates(for url: URL, fileManager: FileManager) -> [URL] {
        var candidates = [url]
        let children = (try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )) ?? []
        candidates.append(contentsOf: children.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        })
        return candidates
    }

    nonisolated private static func collapsedCandidates(
        _ candidates: [SourceCandidate],
        under root: URL,
        providerID: PlatformProviderID
    ) -> [SourceCandidate] {
        let uniqueCandidates = Dictionary(grouping: candidates, by: { sourceIdentityKey(for: $0.sourceRootURL) }).compactMap { _, groupedCandidates in
            groupedCandidates.max { lhs, rhs in
                lhs.confidence < rhs.confidence
            }
        }

        guard uniqueCandidates.count > 1 else {
            return uniqueCandidates
        }

        let detectedKinds = uniqueCandidates.reduce(into: Set<MinecraftContentKind>()) { result, candidate in
            result.formUnion(candidate.detectedKinds)
        }
        let confidence = uniqueCandidates.map(\.confidence).max() ?? .medium
        let standardizedRoot = root.standardizedFileURL

        return [
            SourceCandidate(
                providerID: providerID,
                edition: .java,
                sourceRootURL: standardizedRoot,
                displayName: standardizedRoot.lastPathComponent,
                confidence: confidence,
                reason: "Found multiple Java sources under \(standardizedRoot.lastPathComponent)",
                detectedKinds: detectedKinds
            )
        ]
    }

    nonisolated private static func javaProbeScore(for url: URL, fileManager: FileManager) -> (value: Int, kinds: Set<MinecraftContentKind>) {
        var score = 0
        var kinds = Set<MinecraftContentKind>()

        if existingDirectory(named: "saves", in: url, fileManager: fileManager) != nil {
            kinds.insert(.world)
            score += 25
        }
        if existingDirectory(named: "resourcepacks", in: url, fileManager: fileManager) != nil {
            kinds.insert(.resourcePack)
            score += 20
        }
        if existingDirectory(named: "datapacks", in: url, fileManager: fileManager) != nil {
            kinds.insert(.dataPack)
            score += 15
        }
        if existingDirectory(named: "shaderpacks", in: url, fileManager: fileManager) != nil {
            kinds.insert(.shaderPack)
            score += 15
        }
        if existingDirectory(named: "mods", in: url, fileManager: fileManager) != nil {
            kinds.insert(.mod)
            score += 20
        }
        if fileManager.fileExists(atPath: url.appendingPathComponent("options.txt").path)
            || fileManager.fileExists(atPath: url.appendingPathComponent("launcher_profiles.json").path)
            || fileManager.fileExists(atPath: url.appendingPathComponent(".curseclient").path) {
            score += 15
        }
        if fileManager.fileExists(atPath: url.appendingPathComponent("region", isDirectory: true).path)
            && fileManager.fileExists(atPath: url.appendingPathComponent("level.dat").path) {
            kinds.insert(.world)
            score += 35
        }

        return (score, kinds)
    }

    nonisolated private static func defaultCandidateSearchRoots(fileManager: FileManager) -> [URL] {
        let homeURL = fileManager.homeDirectoryForCurrentUser
        let applicationSupportURL = homeURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        let documentsURL = homeURL.appendingPathComponent("Documents", isDirectory: true)

        return [
            applicationSupportURL.appendingPathComponent("minecraft", isDirectory: true),
            documentsURL.appendingPathComponent("curseforge/minecraft", isDirectory: true),
            documentsURL.appendingPathComponent("CurseForge/Minecraft", isDirectory: true),
            applicationSupportURL.appendingPathComponent("PrismLauncher/instances", isDirectory: true),
            applicationSupportURL.appendingPathComponent("MultiMC/instances", isDirectory: true),
            applicationSupportURL.appendingPathComponent("PolyMC/instances", isDirectory: true),
            applicationSupportURL.appendingPathComponent("com.modrinth.theseus/profiles", isDirectory: true),
            applicationSupportURL.appendingPathComponent("ATLauncher/instances", isDirectory: true),
            applicationSupportURL.appendingPathComponent("gdlauncher_next/instances", isDirectory: true),
            applicationSupportURL.appendingPathComponent("GDLauncher_next/instances", isDirectory: true)
        ]
    }

    nonisolated private static func boundedCandidateFolders(
        from rootURL: URL,
        maxDepth: Int,
        maxFolderCount: Int,
        fileManager: FileManager
    ) -> [URL] {
        var folders: [URL] = []
        var queue: [(url: URL, depth: Int)] = [(rootURL, 0)]
        var seen = Set<String>()

        while !queue.isEmpty && folders.count < maxFolderCount {
            let current = queue.removeFirst()
            let normalizedURL = current.url.standardizedFileURL
            guard seen.insert(sourceIdentityKey(for: normalizedURL)).inserted else {
                continue
            }

            folders.append(normalizedURL)
            guard current.depth < maxDepth else {
                continue
            }

            let children = (try? fileManager.contentsOfDirectory(
                at: normalizedURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            )) ?? []

            let childDirectories = children
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .sorted { lhs, rhs in
                    lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
                }

            queue.append(contentsOf: childDirectories.map { ($0, current.depth + 1) })
        }

        return folders
    }

    nonisolated private static func contentScanRoots(for sourceRootURL: URL, fileManager: FileManager) -> [URL] {
        let standardizedRoot = sourceRootURL.standardizedFileURL
        if javaProbeScore(for: standardizedRoot, fileManager: fileManager).value > 0 {
            return [standardizedRoot]
        }

        let discoveredRoots = boundedCandidateFolders(
            from: standardizedRoot,
            maxDepth: 4,
            maxFolderCount: 600,
            fileManager: fileManager
        ).filter { candidateURL in
            candidateURL != standardizedRoot
                && javaProbeScore(for: candidateURL, fileManager: fileManager).value > 0
        }

        return uniqueStandardizedURLs(discoveredRoots).sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    nonisolated private static func uniqueStandardizedURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        result.reserveCapacity(urls.count)

        for url in urls {
            let standardizedURL = url.standardizedFileURL
            guard seen.insert(sourceIdentityKey(for: standardizedURL)).inserted else {
                continue
            }

            result.append(standardizedURL)
        }

        return result
    }

    nonisolated private static func collectionSnapshot(
        for collectionURL: URL,
        sourceRootURL: URL,
        fileManager: FileManager
    ) -> CollectionSnapshot? {
        guard fileManager.fileExists(atPath: collectionURL.path) else {
            return nil
        }

        let children = (try? fileManager.contentsOfDirectory(
            at: collectionURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let childSnapshots = children.compactMap { childURL -> (name: String, modifiedDate: Date?, size: Int?)? in
            let values = try? childURL.resourceValues(forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .contentModificationDateKey,
                .fileSizeKey
            ])
            guard values?.isDirectory == true || values?.isRegularFile == true else {
                return nil
            }

            return (childURL.lastPathComponent, values?.contentModificationDate, values?.fileSize)
        }.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        let modifiedDate = try? collectionURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let childFingerprint = childSnapshots.map { child in
            [
                child.name,
                child.modifiedDate?.timeIntervalSince1970.formatted() ?? "nil",
                child.size.map(String.init) ?? "nil"
            ].joined(separator: "@")
        }.joined(separator: "|")

        let folderName = relativePath(from: sourceRootURL.standardizedFileURL, to: collectionURL.standardizedFileURL)
            ?? collectionURL.lastPathComponent

        return CollectionSnapshot(
            folderName: folderName,
            modifiedDate: modifiedDate,
            childDirectoryCount: childSnapshots.count,
            fingerprint: [
                folderName,
                String(childSnapshots.count),
                modifiedDate?.timeIntervalSince1970.formatted() ?? "nil",
                childFingerprint
            ].joined(separator: "::")
        )
    }

    nonisolated private static func relativePath(from rootURL: URL, to childURL: URL) -> String? {
        let rootPath = rootURL.standardizedFileURL.path
        let childPath = childURL.standardizedFileURL.path
        guard childPath.hasPrefix(rootPath + "/") else {
            return nil
        }

        return String(childPath.dropFirst(rootPath.count + 1))
    }

    nonisolated private static func displayName(for item: MinecraftContentItem) -> String {
        guard item.contentKind == .world else {
            return item.folderName
        }

        let levelNameURL = item.folderURL.appendingPathComponent("levelname.txt")
        guard
            let value = try? String(contentsOf: levelNameURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return item.folderName
        }

        return value
    }
}

private let packReferenceIndexStore = PackReferenceIndexStore()
