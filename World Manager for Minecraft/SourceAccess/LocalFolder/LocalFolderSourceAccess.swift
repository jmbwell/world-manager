//
//  LocalFolderSourceAccess.swift
//  World Manager for Minecraft
//
//  Created by OpenAI on 2026-05-26.
//

import Foundation

struct LocalFolderSourceAccess: SourceAccessMethod {
    nonisolated init() {}

    nonisolated func prepareScanRoot(for source: MinecraftSource) async throws -> PreparedScanRoot {
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

        return PreparedScanRoot(
            sourceID: source.id,
            rootURL: resolvedURL,
            mountPointURL: nil,
            cleanupBehavior: .none
        )
    }
}
