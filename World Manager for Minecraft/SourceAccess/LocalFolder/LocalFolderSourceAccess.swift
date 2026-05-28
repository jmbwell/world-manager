//
//  LocalFolderSourceAccess.swift
//  World Manager for Minecraft
//
//  Created by OpenAI on 2026-05-26.
//

import Foundation

struct LocalFolderSourceAccess: SourceAccessMethod {
    nonisolated let accessorIdentifier: SourceAccessorIdentifier = "local-folder"

    nonisolated init() {}

    nonisolated func accessDescriptor(for source: MinecraftSource) -> SourceAccessDescriptor {
        _ = source
        return SourceAccessDescriptor(
            accessorIdentifier: accessorIdentifier,
            kind: .localFolder,
            capabilities: .localFolder,
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

    nonisolated func listItemContents(for item: MinecraftContentItem, in source: MinecraftSource) async throws -> [DirectoryPreviewEntry] {
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
                return DirectoryPreviewEntry(name: url.lastPathComponent, isDirectory: isDirectory)
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
