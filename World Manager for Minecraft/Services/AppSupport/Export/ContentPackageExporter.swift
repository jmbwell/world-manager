// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CryptoKit
import Foundation

enum ContentPackageExporter {
    enum ExportError: LocalizedError {
        case failedToCreateArchive(String)
        case failedToPrepareArchiveContents(String)

        var errorDescription: String? {
            switch self {
            case .failedToCreateArchive(let output):
                return output.isEmpty ? "Failed to create the archive file." : output
            case .failedToPrepareArchiveContents(let message):
                return message
            }
        }
    }

    nonisolated static func createArchiveFile(
        for item: MinecraftContentItem,
        source: MinecraftSource? = nil,
        destinationURL: URL? = nil
    ) async throws -> URL {
        let fileManager = FileManager.default
        let archiveURL: URL

        if let destinationURL {
            archiveURL = finalArchiveURL(for: item, destinationURL: destinationURL)
        } else {
            archiveURL = try shareArchiveURL(for: item, fileManager: fileManager)
        }

        if fileManager.fileExists(atPath: archiveURL.path) {
            try fileManager.removeItem(at: archiveURL)
        }

        try await createArchive(for: item, source: source, at: archiveURL)
        return archiveURL
    }

    nonisolated static func suggestedBaseFilename(for item: MinecraftContentItem) -> String {
        sanitizedFilename(item.displayName.isEmpty ? item.folderName : item.displayName)
    }

    nonisolated static func suggestedFilename(for item: MinecraftContentItem) -> String {
        "\(suggestedBaseFilename(for: item)).\(item.contentType.archiveExtension)"
    }

    nonisolated static func finalArchiveURL(for item: MinecraftContentItem, destinationURL: URL) -> URL {
        normalizedArchiveURL(for: item, destinationURL: destinationURL)
    }

    nonisolated private static func createArchive(
        for item: MinecraftContentItem,
        source: MinecraftSource?,
        at archiveURL: URL
    ) async throws {
        let fileManager = FileManager.default
        let stagingDirectoryURL = try await stagedArchiveContents(for: item, source: source, fileManager: fileManager)

        defer {
            try? fileManager.removeItem(at: stagingDirectoryURL)
        }

        if fileManager.fileExists(atPath: archiveURL.path) {
            try fileManager.removeItem(at: archiveURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.currentDirectoryURL = stagingDirectoryURL
        process.arguments = [
            "-c",
            "-k",
            "--norsrc",
            ".",
            archiveURL.path
        ]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw ExportError.failedToCreateArchive(output)
        }
    }

    nonisolated private static func stagedArchiveContents(
        for item: MinecraftContentItem,
        source: MinecraftSource?,
        fileManager: FileManager
    ) async throws -> URL {
        let stagingDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("MinecraftArchiveStaging", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try fileManager.createDirectory(at: stagingDirectoryURL, withIntermediateDirectories: true)

        do {
            if let source, case .connectedDevice(_, let container) = source.origin {
                try await materializeConnectedDeviceItem(
                    item,
                    source: source,
                    container: container,
                    into: stagingDirectoryURL
                )
            } else {
                let accessURL = try archiveAccessURL(for: item, source: source)
                let accessedSecurityScope = accessURL.startAccessingSecurityScopedResource()
                defer {
                    if accessedSecurityScope {
                        accessURL.stopAccessingSecurityScopedResource()
                    }
                }

                let contents = try fileManager.contentsOfDirectory(
                    at: item.folderURL,
                    includingPropertiesForKeys: nil,
                    options: [.skipsPackageDescendants]
                )

                for entryURL in contents {
                    let destinationURL = stagingDirectoryURL.appendingPathComponent(entryURL.lastPathComponent)
                    try fileManager.copyItem(at: entryURL, to: destinationURL)
                }
            }
        } catch {
            throw ExportError.failedToPrepareArchiveContents(
                "Could not prepare the item for archiving: \(error.localizedDescription)"
            )
        }

        return stagingDirectoryURL
    }

    nonisolated private static func materializeConnectedDeviceItem(
        _ item: MinecraftContentItem,
        source: MinecraftSource,
        container: DeviceAppContainer,
        into destinationURL: URL
    ) async throws {
        let rootPath = container.minecraftFolderRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rootPath.isEmpty else {
            throw ExportError.failedToPrepareArchiveContents("The connected-device source is missing its Minecraft path.")
        }

        let sourceRootPath = source.folderURL.path
        let itemPath = item.folderURL.path
        let relativeItemPath: String
        if itemPath.hasPrefix(sourceRootPath + "/") {
            relativeItemPath = String(itemPath.dropFirst(sourceRootPath.count + 1))
        } else {
            relativeItemPath = item.folderName
        }

        let remoteItemPath = relativeItemPath
            .split(separator: "/")
            .map(String.init)
            .reduce(rootPath) { partial, component in
                NSString(string: partial).appendingPathComponent(component)
            }

        try await AppleMobileDeviceAccess.mirrorSubtree(
            deviceIdentifier: container.deviceUDID,
            bundleIdentifier: container.appID,
            relativePath: remoteItemPath,
            destinationDirectoryURL: destinationURL
        )
    }

    nonisolated private static func shareArchiveDirectory(fileManager: FileManager) throws -> URL {
        let baseDirectoryURL = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let shareDirectoryURL = baseDirectoryURL
            .appendingPathComponent("MinecraftContentShares", isDirectory: true)

        try fileManager.createDirectory(at: shareDirectoryURL, withIntermediateDirectories: true)
        return shareDirectoryURL
    }

    nonisolated private static func shareArchiveURL(
        for item: MinecraftContentItem,
        fileManager: FileManager
    ) throws -> URL {
        let shareDirectoryURL = try shareArchiveDirectory(fileManager: fileManager)
        let itemDirectoryURL = shareDirectoryURL
            .appendingPathComponent(shareCacheKey(for: item), isDirectory: true)
        let requestDirectoryURL = itemDirectoryURL
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try fileManager.createDirectory(at: requestDirectoryURL, withIntermediateDirectories: true)

        cleanupShareArchives(in: itemDirectoryURL, keeping: requestDirectoryURL, fileManager: fileManager)

        return requestDirectoryURL
            .appendingPathComponent(suggestedBaseFilename(for: item))
            .appendingPathExtension(item.contentType.archiveExtension)
    }

    nonisolated private static func shareCacheKey(for item: MinecraftContentItem) -> String {
        let digest = SHA256.hash(data: Data(item.id.path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func cleanupShareArchives(
        in itemDirectoryURL: URL,
        keeping currentDirectoryURL: URL,
        fileManager: FileManager
    ) {
        guard let childDirectoryURLs = try? fileManager.contentsOfDirectory(
            at: itemDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let staleDirectories = childDirectoryURLs
            .filter { $0 != currentDirectoryURL }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return lhsDate > rhsDate
            }
            .dropFirst(2)

        for directoryURL in staleDirectories {
            try? fileManager.removeItem(at: directoryURL)
        }
    }

    nonisolated private static func archiveAccessURL(
        for item: MinecraftContentItem,
        source: MinecraftSource?
    ) throws -> URL {
        guard let source else {
            return item.folderURL
        }

        guard case .localFolder(let bookmarkData) = source.origin else {
            return source.folderURL
        }

        guard let bookmarkData else {
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

    nonisolated private static func normalizedArchiveURL(for item: MinecraftContentItem, destinationURL: URL) -> URL {
        let normalizedDestinationURL = destinationURL.standardizedFileURL
        let requiredExtension = item.contentType.archiveExtension

        if normalizedDestinationURL.pathExtension.lowercased() == requiredExtension {
            return normalizedDestinationURL
        }

        return normalizedDestinationURL.appendingPathExtension(requiredExtension)
    }

    nonisolated private static func uniqueArchiveURL(
        in directoryURL: URL,
        baseName: String,
        pathExtension: String,
        fileManager: FileManager
    ) -> URL {
        var candidateURL = directoryURL
            .appendingPathComponent(baseName)
            .appendingPathExtension(pathExtension)
        var suffix = 2

        while fileManager.fileExists(atPath: candidateURL.path) {
            candidateURL = directoryURL
                .appendingPathComponent("\(baseName) \(suffix)")
                .appendingPathExtension(pathExtension)
            suffix += 1
        }

        return candidateURL
    }

    nonisolated private static func sanitizedFilename(_ value: String) -> String {
        let transliterated = portableASCIIString(from: value)
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let components = transliterated.components(separatedBy: invalidCharacters)
        let collapsed = components.joined(separator: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_().,'&+"))
        let filteredScalars = collapsed.unicodeScalars.map { scalar in
            allowedCharacters.contains(scalar) ? Character(scalar) : " "
        }
        let filtered = String(filteredScalars)

        let normalizedWhitespace = filtered.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        let trimmedPunctuation = normalizedWhitespace.trimmingCharacters(in: CharacterSet(charactersIn: " .-_"))

        return trimmedPunctuation.isEmpty ? "Minecraft Item" : trimmedPunctuation
    }

    nonisolated private static func portableASCIIString(from value: String) -> String {
        let mutable = NSMutableString(string: value) as CFMutableString

        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)

        return mutable as String
    }
}
