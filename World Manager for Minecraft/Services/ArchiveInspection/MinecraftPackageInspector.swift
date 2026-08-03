// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

enum MinecraftPackageInspector {
    struct InspectionResult: Sendable {
        let archiveURL: URL
        let extractedRootURL: URL
        let contentRootURL: URL
        let contentType: MinecraftContentType
        let displayName: String
        let iconURL: URL?
        let worldMetadata: WorldMetadata?
        let manifestMetadata: MinecraftManifestMetadata?
    }

    enum InspectionError: LocalizedError {
        case unsupportedFileType(String)
        case invalidArchiveLayout

        var errorDescription: String? {
            switch self {
            case .unsupportedFileType(let pathExtension):
                return "Unsupported Minecraft package type: .\(pathExtension)"
            case .invalidArchiveLayout:
                return "The Minecraft package did not contain a valid world or pack layout."
            }
        }
    }

    nonisolated static let supportedPathExtensions: Set<String> = [
        "mcaddon",
        "mcpack",
        "mctemplate",
        "mcworld"
    ]

    nonisolated static func inspectArchive(at archiveURL: URL) throws -> InspectionResult {
        let normalizedArchiveURL = archiveURL.standardizedFileURL
        let pathExtension = normalizedArchiveURL.pathExtension.lowercased()
        guard supportedPathExtensions.contains(pathExtension) else {
            throw InspectionError.unsupportedFileType(pathExtension)
        }

        let fileManager = FileManager.default
        let extractionDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("MinecraftPackageInspection", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try fileManager.createDirectory(at: extractionDirectoryURL, withIntermediateDirectories: true)

        do {
            let archive = try ZipArchiveReader(url: normalizedArchiveURL)
            let contentRootURL = try materializedContentRootURL(
                for: archive,
                archivePathExtension: pathExtension,
                in: extractionDirectoryURL,
                fileManager: fileManager
            )
            let contentType = try resolvedContentType(
                forArchivePathExtension: pathExtension,
                contentRootURL: contentRootURL,
                fileManager: fileManager
            )
            let displayName = MinecraftContentMetadataReader.displayName(
                for: contentRootURL,
                contentType: contentType,
                fallbackName: normalizedArchiveURL.deletingPathExtension().lastPathComponent,
                fileManager: fileManager
            )
            let worldMetadata: WorldMetadata? =
                contentType == .world ? MinecraftContentMetadataReader.worldMetadata(in: contentRootURL, fileManager: fileManager) : nil
            let manifestMetadata = MinecraftContentMetadataReader.manifestMetadata(in: contentRootURL, fileManager: fileManager)
            let iconURL = MinecraftContentMetadataReader.iconURL(
                for: contentRootURL,
                contentType: contentType,
                fileManager: fileManager
            )

            return InspectionResult(
                archiveURL: normalizedArchiveURL,
                extractedRootURL: extractionDirectoryURL,
                contentRootURL: contentRootURL,
                contentType: contentType,
                displayName: displayName,
                iconURL: iconURL,
                worldMetadata: worldMetadata,
                manifestMetadata: manifestMetadata
            )
        } catch {
            try? fileManager.removeItem(at: extractionDirectoryURL)
            throw error
        }
    }

    nonisolated static func cleanup(_ result: InspectionResult) {
        try? FileManager.default.removeItem(at: result.extractedRootURL)
    }

    nonisolated private static func resolvedContentType(
        forArchivePathExtension pathExtension: String,
        contentRootURL: URL,
        fileManager: FileManager
    ) throws -> MinecraftContentType {
        switch pathExtension {
        case "mcworld":
            return .world
        case "mctemplate":
            return .worldTemplate
        case "mcpack", "mcaddon":
            return MinecraftContentMetadataReader.inferredPackContentType(for: contentRootURL, fileManager: fileManager)
        default:
            throw InspectionError.unsupportedFileType(pathExtension)
        }
    }

    nonisolated private static func materializedContentRootURL(
        for archive: ZipArchiveReader,
        archivePathExtension: String,
        in extractionDirectoryURL: URL,
        fileManager: FileManager
    ) throws -> URL {
        let contentRootPath = try resolvedContentRootPath(
            in: archive.entries,
            archivePathExtension: archivePathExtension
        )
        let contentRootURL = extractionDirectoryURL.appendingPathComponent(contentRootPath, isDirectory: true)
        try fileManager.createDirectory(at: contentRootURL, withIntermediateDirectories: true)

        let requiredRelativePaths = requiredMetadataRelativePaths(
            in: archive.entries,
            contentRootPath: contentRootPath
        )

        for relativePath in requiredRelativePaths {
            let fullPath = contentRootPath.isEmpty ? relativePath : "\(contentRootPath)/\(relativePath)"
            guard let entry = archive.entry(named: fullPath) else {
                continue
            }

            let destinationURL = contentRootURL.appendingPathComponent(relativePath)
            try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try archive.extract(entry).write(to: destinationURL)
        }

        return contentRootURL
    }

    nonisolated static func resolvedContentRootPath(
        in entries: [ZipArchiveEntry],
        archivePathExtension: String
    ) throws -> String {
        let filePaths = entries
            .filter { !$0.isDirectory }
            .map(\.path)

        if containsContentMarkers(in: filePaths, prefix: "") {
            return ""
        }

        let rootCandidates = Set(
            filePaths.compactMap { path -> String? in
                guard let firstComponent = path.split(separator: "/").first else {
                    return nil
                }
                return String(firstComponent)
            }
        ).sorted()

        let matchingRoots = rootCandidates.filter { containsContentMarkers(in: filePaths, prefix: $0) }
        guard matchingRoots.count == 1 else {
            throw InspectionError.invalidArchiveLayout
        }

        let root = matchingRoots[0]
        if archivePathExtension == "mcaddon" {
            return root
        }

        return root
    }

    nonisolated static func containsContentMarkers(in filePaths: [String], prefix: String) -> Bool {
        let normalizedPrefix = prefix.isEmpty ? "" : prefix + "/"

        let worldMarkers = ["level.dat", "levelname.txt"]
        let packMarkers = ["manifest.json", "pack_icon.png", "pack_icon.jpeg", "pack_icon.jpg"]

        if worldMarkers.contains(where: { filePaths.contains(normalizedPrefix + $0) }) {
            return true
        }

        if filePaths.contains(normalizedPrefix + "db") || filePaths.contains(where: { $0.hasPrefix(normalizedPrefix + "db/") }) {
            return true
        }

        return packMarkers.contains(where: { filePaths.contains(normalizedPrefix + $0) })
    }

    nonisolated private static func requiredMetadataRelativePaths(
        in entries: [ZipArchiveEntry],
        contentRootPath: String
    ) -> [String] {
        let fullPrefix = contentRootPath.isEmpty ? "" : contentRootPath + "/"
        let candidateNames = [
            "manifest.json",
            "level.dat",
            "levelname.txt",
            "world_icon.jpeg",
            "world_icon.jpg",
            "world_icon.png",
            "pack_icon.png",
            "pack_icon.jpeg",
            "pack_icon.jpg"
        ]

        let availablePaths = Set(entries.filter { !$0.isDirectory }.map(\.path))
        return candidateNames.filter { availablePaths.contains(fullPrefix + $0) }
    }

    nonisolated private static func looksLikeMinecraftContentRoot(
        _ directoryURL: URL,
        fileManager: FileManager
    ) -> Bool {
        let worldMarkers = [
            "level.dat",
            "levelname.txt"
        ]
        let packMarkers = [
            "manifest.json",
            "pack_icon.png",
            "pack_icon.jpeg",
            "pack_icon.jpg"
        ]

        if worldMarkers.contains(where: { fileManager.fileExists(atPath: directoryURL.appendingPathComponent($0).path) }) {
            return true
        }

        if fileManager.fileExists(atPath: directoryURL.appendingPathComponent("db", isDirectory: true).path) {
            return true
        }

        if packMarkers.contains(where: { fileManager.fileExists(atPath: directoryURL.appendingPathComponent($0).path) }) {
            return true
        }

        return false
    }
}
