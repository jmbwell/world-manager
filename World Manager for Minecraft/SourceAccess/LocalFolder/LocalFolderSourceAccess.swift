// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

struct LocalFolderSourceAccess: SourceAccessMethod {
    nonisolated let accessorIdentifier: SourceAccessorIdentifier = "local-folder"

    nonisolated init() {}

    nonisolated func accessDescriptor(for source: MinecraftSource) -> SourceAccessDescriptor {
        _ = source
        return SourceAccessDescriptor(
            accessorIdentifier: accessorIdentifier,
            kind: .localFolder,
            refreshStrategy: .eagerFullScan
        )
    }

    nonisolated func availability(for source: MinecraftSource) async -> SourceAvailability {
        let candidateURL: URL
        if case .localFolder(let bookmarkData) = source.origin,
           let bookmarkData {
            var isStale = false
            if let resolvedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                candidateURL = resolvedURL.standardizedFileURL
            } else {
                candidateURL = source.folderURL
            }
        } else {
            candidateURL = source.folderURL
        }

        return FileManager.default.fileExists(atPath: candidateURL.path) ? .available : .unavailable
    }

    nonisolated func capabilities(for source: MinecraftSource) async -> SourceCapabilities {
        _ = source
        return .localFolder
    }

    nonisolated func discoverItems(
        for source: MinecraftSource,
        mode: SourceDiscoveryMode,
        onDiscovered: @escaping @Sendable (MinecraftContentItem) -> Void
    ) async throws {
        guard case .localFolder(let bookmarkData) = source.origin else {
            throw SourceAccessError.accessFailed(
                reason: "No local-folder access method is configured for this source type."
            )
        }

        let resolvedURL: URL
        if let bookmarkData {
            var isStale = false
            guard let bookmarkURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                throw SourceAccessError.accessFailed(
                    reason: "The saved folder bookmark could not be resolved."
                )
            }

            resolvedURL = bookmarkURL.standardizedFileURL
        } else {
            resolvedURL = source.folderURL
        }

        let accessedSecurityScope = resolvedURL.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScope {
                resolvedURL.stopAccessingSecurityScopedResource()
            }
        }

        if case .reconcile = mode,
           let snapshot = source.snapshot {
            try discoverItemsByReconcilingCache(
                for: source,
                snapshot: snapshot,
                resolvedURL: resolvedURL,
                onDiscovered: onDiscovered
            )
            return
        }

        _ = try WorldScanner.discoverItems(in: resolvedURL, onDiscovered: onDiscovered)
    }

    nonisolated func enrich(_ item: MinecraftContentItem, for source: MinecraftSource) async -> MinecraftContentItem {
        _ = source
        return await WorldScanner.enrich(item: item)
    }

    nonisolated func loadSize(for item: MinecraftContentItem, in source: MinecraftSource) async -> MinecraftContentItem {
        _ = source
        return WorldScanner.loadSize(for: item)
    }

    nonisolated func listItemContents(for item: MinecraftContentItem, in source: MinecraftSource) async throws -> [DirectoryEntry] {
        _ = source
        let fileManager = FileManager.default
        let urls = try fileManager.contentsOfDirectory(
            at: item.folderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return urls
            .map { url in
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                return DirectoryEntry(name: url.lastPathComponent, isDirectory: isDirectory)
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory && !rhs.isDirectory
                }

                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    nonisolated func materializeItem(for item: MinecraftContentItem, in source: MinecraftSource) async throws -> URL {
        _ = source
        return item.folderURL
    }

    nonisolated func install(_ payload: InstallationPayload, in source: MinecraftSource) async throws -> InstalledContentItem {
        let sourceRootURL = try resolvedSourceRootURL(for: source)
        let accessedSecurityScope = sourceRootURL.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScope {
                sourceRootURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileManager = FileManager.default
        let contentRootURL = try resolvedContentRootURL(for: source, sourceRootURL: sourceRootURL)
        let collectionURL = contentRootURL.appendingPathComponent(
            payload.contentType.collectionFolderName,
            isDirectory: true
        )
        let stagingRootURL = contentRootURL
            .appendingPathComponent(".world-manager-staging", isDirectory: true)
        let stagedItemURL = stagingRootURL
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try fileManager.createDirectory(at: stagingRootURL, withIntermediateDirectories: true)
        do {
            try fileManager.copyItem(at: payload.preparedDirectoryURL, to: stagedItemURL)
            try fileManager.createDirectory(at: collectionURL, withIntermediateDirectories: true)
            let destinationURL = uniqueDestinationURL(
                in: collectionURL,
                preferredName: payload.suggestedFolderName,
                fileManager: fileManager
            )
            try fileManager.moveItem(at: stagedItemURL, to: destinationURL)
            return InstalledContentItem(
                contentType: payload.contentType,
                displayName: payload.displayName,
                destinationName: destinationURL.lastPathComponent
            )
        } catch {
            try? fileManager.removeItem(at: stagedItemURL)
            throw error
        }
    }

    nonisolated private func resolvedSourceRootURL(for source: MinecraftSource) throws -> URL {
        guard case .localFolder(let bookmarkData) = source.origin, let bookmarkData else {
            return source.folderURL
        }

        var isStale = false
        return try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ).standardizedFileURL
    }

    nonisolated private func resolvedContentRootURL(
        for source: MinecraftSource,
        sourceRootURL: URL
    ) throws -> URL {
        let observedRoots = Set(source.rawItems.map {
            $0.collectionRootURL.deletingLastPathComponent().standardizedFileURL
        })
        if let minimumDepth = observedRoots.map(\.pathComponents.count).min() {
            let shallowestRoots = observedRoots.filter { $0.pathComponents.count == minimumDepth }
            if shallowestRoots.count == 1, let observedRoot = shallowestRoots.first {
                return observedRoot
            }
            if shallowestRoots.count > 1 {
                throw SourceAccessError.accessFailed(
                    reason: "This source contains more than one Minecraft content root. Choose the specific com.mojang folder before importing."
                )
            }
        }

        return sourceRootURL
    }

    nonisolated private func uniqueDestinationURL(
        in collectionURL: URL,
        preferredName: String,
        fileManager: FileManager
    ) -> URL {
        var candidateURL = collectionURL.appendingPathComponent(preferredName, isDirectory: true)
        var suffix = 2
        while fileManager.fileExists(atPath: candidateURL.path) {
            candidateURL = collectionURL.appendingPathComponent("\(preferredName)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        return candidateURL
    }

    nonisolated private func discoverItemsByReconcilingCache(
        for source: MinecraftSource,
        snapshot: SourceSnapshot,
        resolvedURL: URL,
        onDiscovered: @escaping @Sendable (MinecraftContentItem) -> Void
    ) throws {
        let currentCollections = Dictionary(
            uniqueKeysWithValues: WorldScanner.collectionSnapshots(in: resolvedURL).map { ($0.folderName, $0) }
        )
        let previousCollections = Dictionary(
            uniqueKeysWithValues: snapshot.collectionSnapshots.map { ($0.folderName, $0) }
        )

        var changedCollectionNames = Set<String>()
        for type in MinecraftContentType.allCases {
            let collectionName = type.collectionFolderName
            let currentFingerprint = currentCollections[collectionName]?.fingerprint
            let previousFingerprint = previousCollections[collectionName]?.fingerprint
            if currentFingerprint != previousFingerprint {
                changedCollectionNames.insert(collectionName)
            }
        }

        let unchangedCollectionNames = Set(currentCollections.keys).subtracting(changedCollectionNames)
        var reconciledItems = source.rawItems.filter { item in
            guard let collectionName = topLevelCollectionName(for: item, sourceRootURL: resolvedURL) else {
                return false
            }

            return unchangedCollectionNames.contains(collectionName)
        }

        for type in MinecraftContentType.allCases {
            let collectionName = type.collectionFolderName
            guard changedCollectionNames.contains(collectionName) else {
                continue
            }

            let collectionURL = resolvedURL.appendingPathComponent(collectionName, isDirectory: true)
            let discoveredItems = try WorldScanner.discoverItems(
                inCollectionRootURL: collectionURL,
                contentType: type
            )
            reconciledItems.append(contentsOf: discoveredItems)
        }

        reconciledItems.sort(by: WorldScanner.sortItems)
        for item in reconciledItems {
            onDiscovered(item)
        }
    }

    nonisolated private func topLevelCollectionName(for item: MinecraftContentItem, sourceRootURL: URL) -> String? {
        let relativePath = item.folderURL.path.replacingOccurrences(of: sourceRootURL.path + "/", with: "")
        let components = relativePath.split(separator: "/")
        return components.first.map(String.init)
    }
}
