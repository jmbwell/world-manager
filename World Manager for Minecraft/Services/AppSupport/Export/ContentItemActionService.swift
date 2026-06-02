// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import UniformTypeIdentifiers

struct ContentItemActionService: Sendable {
    nonisolated init() {}

    nonisolated func suggestedFilename(for item: MinecraftContentItem) -> String {
        ContentPackageExporter.suggestedBaseFilename(for: item)
    }

    nonisolated func suggestedArchiveFilename(for item: MinecraftContentItem) -> String {
        ContentPackageExporter.suggestedFilename(for: item)
    }

    nonisolated func archiveContentType(for item: MinecraftContentItem) -> UTType {
        UTType(filenameExtension: item.capabilities.portablePackageExtension ?? item.contentType.archiveExtension) ?? .data
    }

    nonisolated func persistExternalRepresentation(
        _ representation: ExternalRepresentation,
        to destinationURL: URL
    ) throws -> URL {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        if representation.url.standardizedFileURL == destinationURL.standardizedFileURL {
            return destinationURL
        }

        if representation.isTemporary {
            try fileManager.moveItem(at: representation.url, to: destinationURL)
        } else {
            try fileManager.copyItem(at: representation.url, to: destinationURL)
        }

        return destinationURL
    }

    nonisolated func createArchiveFile(
        for item: MinecraftContentItem,
        source: MinecraftSource?,
        destinationURL: URL? = nil
    ) async throws -> URL {
        try await ContentPackageExporter.createArchiveFile(
            for: item,
            source: source,
            destinationURL: destinationURL
        )
    }
}
