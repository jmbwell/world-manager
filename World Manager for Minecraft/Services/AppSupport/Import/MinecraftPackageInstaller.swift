// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

nonisolated struct InstallationPayload: Sendable {
    let contentType: MinecraftContentType
    let preparedDirectoryURL: URL
    let displayName: String
    let packUUID: String?
    let packVersion: String?
    let suggestedFolderName: String
}

nonisolated struct InstallationPlan: Sendable {
    let payloads: [InstallationPayload]
    let stagingRootURL: URL

    func cleanup(fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: stagingRootURL)
    }
}

nonisolated struct InstalledContentItem: Sendable {
    let contentType: MinecraftContentType
    let displayName: String
    let destinationName: String
}

nonisolated struct SourceInstallationState: Hashable, Sendable {
    let completedCount: Int
    let totalCount: Int
    let status: String
}

enum MinecraftPackageInstaller {
    enum InstallError: LocalizedError {
        case emptyPackage
        case unsupportedAddonLayout
        case archiveTooLarge
        case tooManyEntries
        case symbolicLinksNotSupported
        case invalidPreparedContent
        case duplicatePack(name: String, version: String?)
        case duplicateArchivePath(String)
        case partialInstallation(completed: Int, total: Int, reason: String)

        var errorDescription: String? {
            switch self {
            case .emptyPackage:
                return "The Minecraft package does not contain any files."
            case .unsupportedAddonLayout:
                return "The .mcaddon package does not contain any supported Minecraft package files."
            case .archiveTooLarge:
                return "The expanded Minecraft package is too large to import safely."
            case .tooManyEntries:
                return "The Minecraft package contains too many files to import safely."
            case .symbolicLinksNotSupported:
                return "Minecraft packages containing symbolic links are not supported."
            case .invalidPreparedContent:
                return "The prepared content does not contain a valid Minecraft world, pack, or template."
            case .duplicatePack(let name, let version):
                if let version, !version.isEmpty {
                    return "\(name) version \(version) is already installed in this source."
                }
                return "\(name) is already installed in this source."
            case .duplicateArchivePath(let path):
                return "The Minecraft package contains more than one entry for \(path)."
            case .partialInstallation(let completed, let total, let reason):
                return "Installed \(completed) of \(total) items before the import stopped: \(reason)"
            }
        }
    }

    private static let maximumEntryCount = 100_000
    private static let maximumExpandedSize: UInt64 = 16 * 1_024 * 1_024 * 1_024

    nonisolated static func preparePackage(at packageURL: URL) throws -> InstallationPlan {
        let fileManager = FileManager.default
        let stagingRootURL = fileManager.temporaryDirectory
            .appendingPathComponent("MinecraftPackageInstallation", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: stagingRootURL, withIntermediateDirectories: true)

        do {
            let payloads = try preparePackage(
                at: packageURL.standardizedFileURL,
                inside: stagingRootURL,
                fileManager: fileManager
            )
            guard !payloads.isEmpty else {
                throw InstallError.emptyPackage
            }
            return InstallationPlan(payloads: payloads, stagingRootURL: stagingRootURL)
        } catch {
            try? fileManager.removeItem(at: stagingRootURL)
            throw error
        }
    }

    nonisolated static func prepareDirectory(
        at directoryURL: URL,
        contentType: MinecraftContentType
    ) throws -> InstallationPlan {
        let fileManager = FileManager.default
        let stagingRootURL = fileManager.temporaryDirectory
            .appendingPathComponent("MinecraftDirectoryInstallation", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let payloadDirectoryURL = stagingRootURL.appendingPathComponent("payload", isDirectory: true)

        do {
            try validateDirectoryTree(at: directoryURL, fileManager: fileManager)
            try fileManager.createDirectory(at: stagingRootURL, withIntermediateDirectories: true)
            try fileManager.copyItem(at: directoryURL, to: payloadDirectoryURL)
            let payload = try makePayload(
                contentRootURL: payloadDirectoryURL,
                contentType: contentType,
                fallbackName: directoryURL.lastPathComponent,
                fileManager: fileManager
            )
            return InstallationPlan(payloads: [payload], stagingRootURL: stagingRootURL)
        } catch {
            try? fileManager.removeItem(at: stagingRootURL)
            throw error
        }
    }

    private nonisolated static func preparePackage(
        at packageURL: URL,
        inside stagingRootURL: URL,
        fileManager: FileManager
    ) throws -> [InstallationPayload] {
        let pathExtension = packageURL.pathExtension.lowercased()
        guard MinecraftPackageInspector.supportedPathExtensions.contains(pathExtension) else {
            throw MinecraftPackageInspector.InspectionError.unsupportedFileType(pathExtension)
        }

        let archive = try ZipArchiveReader(url: packageURL)
        try validate(entries: archive.entries)

        if pathExtension == "mcaddon" {
            return try prepareAddon(
                archive: archive,
                packageURL: packageURL,
                stagingRootURL: stagingRootURL,
                fileManager: fileManager
            )
        }

        let contentRootPath = try MinecraftPackageInspector.resolvedContentRootPath(
            in: archive.entries,
            archivePathExtension: pathExtension
        )
        let payloadDirectoryURL = stagingRootURL
            .appendingPathComponent("payload-\(UUID().uuidString)", isDirectory: true)
        try extract(
            archive: archive,
            contentRootPath: contentRootPath,
            to: payloadDirectoryURL,
            fileManager: fileManager
        )

        let contentType: MinecraftContentType
        switch pathExtension {
        case "mcworld":
            contentType = .world
        case "mctemplate":
            contentType = .worldTemplate
        case "mcpack":
            contentType = MinecraftContentMetadataReader.inferredPackContentType(
                for: payloadDirectoryURL,
                fileManager: fileManager
            )
        default:
            throw MinecraftPackageInspector.InspectionError.unsupportedFileType(pathExtension)
        }

        return [
            try makePayload(
                contentRootURL: payloadDirectoryURL,
                contentType: contentType,
                fallbackName: packageURL.deletingPathExtension().lastPathComponent,
                fileManager: fileManager
            )
        ]
    }

    private nonisolated static func prepareAddon(
        archive: ZipArchiveReader,
        packageURL: URL,
        stagingRootURL: URL,
        fileManager: FileManager
    ) throws -> [InstallationPayload] {
        let nestedEntries = archive.entries.filter { entry in
            guard !entry.isDirectory else {
                return false
            }
            return ["mcpack", "mcworld", "mctemplate"].contains(
                URL(fileURLWithPath: entry.path).pathExtension.lowercased()
            )
        }

        guard !nestedEntries.isEmpty else {
            throw InstallError.unsupportedAddonLayout
        }

        var payloads: [InstallationPayload] = []
        for nestedEntry in nestedEntries {
            let nestedPackageURL = stagingRootURL
                .appendingPathComponent("nested-\(UUID().uuidString)")
                .appendingPathExtension(URL(fileURLWithPath: nestedEntry.path).pathExtension)
            try archive.extract(nestedEntry).write(to: nestedPackageURL, options: .atomic)
            payloads.append(
                contentsOf: try preparePackage(
                    at: nestedPackageURL,
                    inside: stagingRootURL,
                    fileManager: fileManager
                )
            )
            try? fileManager.removeItem(at: nestedPackageURL)
        }

        _ = packageURL
        return payloads
    }

    private nonisolated static func validate(entries: [ZipArchiveEntry]) throws {
        guard !entries.isEmpty else {
            throw InstallError.emptyPackage
        }
        guard entries.count <= maximumEntryCount else {
            throw InstallError.tooManyEntries
        }
        guard !entries.contains(where: \.isSymbolicLink) else {
            throw InstallError.symbolicLinksNotSupported
        }
        var paths = Set<String>()
        for entry in entries where !entry.isDirectory {
            guard paths.insert(entry.path).inserted else {
                throw InstallError.duplicateArchivePath(entry.path)
            }
        }

        let expandedSize = entries.reduce(UInt64(0)) { partial, entry in
            partial + UInt64(entry.uncompressedSize)
        }
        guard expandedSize <= maximumExpandedSize else {
            throw InstallError.archiveTooLarge
        }
    }

    private nonisolated static func extract(
        archive: ZipArchiveReader,
        contentRootPath: String,
        to destinationRootURL: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(at: destinationRootURL, withIntermediateDirectories: true)
        let prefix = contentRootPath.isEmpty ? "" : contentRootPath + "/"

        for entry in archive.entries {
            guard entry.path.hasPrefix(prefix) else {
                continue
            }
            let relativePath = String(entry.path.dropFirst(prefix.count))
            guard !relativePath.isEmpty else {
                continue
            }

            let destinationURL = destinationRootURL.appendingPathComponent(relativePath)
            if entry.isDirectory {
                try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                continue
            }

            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try archive.extract(entry).write(to: destinationURL, options: .atomic)
        }
    }

    private nonisolated static func makePayload(
        contentRootURL: URL,
        contentType: MinecraftContentType,
        fallbackName: String,
        fileManager: FileManager
    ) throws -> InstallationPayload {
        guard isValidContent(at: contentRootURL, type: contentType, fileManager: fileManager) else {
            throw InstallError.invalidPreparedContent
        }

        let manifest = MinecraftContentMetadataReader.manifestMetadata(
            in: contentRootURL,
            fileManager: fileManager
        )
        let displayName = MinecraftContentMetadataReader.displayName(
            for: contentRootURL,
            contentType: contentType,
            fallbackName: fallbackName,
            fileManager: fileManager
        )
        let preferredFolderName = manifest?.uuid ?? fallbackName

        return InstallationPayload(
            contentType: contentType,
            preparedDirectoryURL: contentRootURL,
            displayName: displayName,
            packUUID: manifest?.uuid,
            packVersion: manifest?.version,
            suggestedFolderName: sanitizedFolderName(preferredFolderName)
        )
    }

    private nonisolated static func isValidContent(
        at directoryURL: URL,
        type: MinecraftContentType,
        fileManager: FileManager
    ) -> Bool {
        switch type {
        case .world:
            return fileManager.fileExists(atPath: directoryURL.appendingPathComponent("level.dat").path)
                || fileManager.fileExists(atPath: directoryURL.appendingPathComponent("db", isDirectory: true).path)
        case .behaviorPack, .resourcePack, .skinPack, .worldTemplate:
            return fileManager.fileExists(atPath: directoryURL.appendingPathComponent("manifest.json").path)
        }
    }

    private nonisolated static func sanitizedFolderName(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let components = value.components(separatedBy: invalidCharacters)
        let sanitized = components.joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? UUID().uuidString : String(sanitized.prefix(80))
    }

    private nonisolated static func validateDirectoryTree(
        at directoryURL: URL,
        fileManager: FileManager
    ) throws {
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: []
        ) else {
            throw InstallError.invalidPreparedContent
        }

        var entryCount = 0
        for case let entryURL as URL in enumerator {
            entryCount += 1
            guard entryCount <= maximumEntryCount else {
                throw InstallError.tooManyEntries
            }
            if (try entryURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw InstallError.symbolicLinksNotSupported
            }
        }
    }
}
