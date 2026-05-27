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
        onDiscovered: @escaping @Sendable (MinecraftContentItem) -> Void
    ) async throws -> [MinecraftContentItem] {
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

        return try WorldScanner.discoverItems(in: resolvedURL, onDiscovered: onDiscovered)
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
}
