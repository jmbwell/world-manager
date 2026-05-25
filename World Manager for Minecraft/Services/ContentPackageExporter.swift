//
//  ContentPackageExporter.swift
//  World Manager for Minecraft
//
//  Created by John Burwell on 2026-05-25.
//

import Foundation

enum ContentPackageExporter {
    enum ExportError: LocalizedError {
        case failedToCreateArchive(String)

        var errorDescription: String? {
            switch self {
            case .failedToCreateArchive(let output):
                return output.isEmpty ? "Failed to create the archive file." : output
            }
        }
    }

    nonisolated static func exportItem(_ item: MinecraftContentItem, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        let archiveURL = normalizedArchiveURL(for: item, destinationURL: destinationURL)
        let temporaryArchiveURL = temporaryArchiveURL(for: item, fileManager: fileManager)

        defer {
            try? fileManager.removeItem(at: temporaryArchiveURL)
        }

        try createArchive(for: item, at: temporaryArchiveURL)

        if fileManager.fileExists(atPath: archiveURL.path) {
            try fileManager.removeItem(at: archiveURL)
        }

        try fileManager.moveItem(at: temporaryArchiveURL, to: archiveURL)
    }

    nonisolated static func prepareShareFile(for item: MinecraftContentItem) throws -> URL {
        let fileManager = FileManager.default
        let shareDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("MinecraftContentShares", isDirectory: true)

        try fileManager.createDirectory(at: shareDirectoryURL, withIntermediateDirectories: true)

        let archiveURL = uniqueArchiveURL(
            in: shareDirectoryURL,
            baseName: suggestedBaseFilename(for: item),
            pathExtension: item.contentType.archiveExtension,
            fileManager: fileManager
        )

        try createArchive(for: item, at: archiveURL)
        return archiveURL
    }

    nonisolated static func suggestedBaseFilename(for item: MinecraftContentItem) -> String {
        sanitizedFilename(item.displayName.isEmpty ? item.folderName : item.displayName)
    }

    nonisolated static func suggestedFilename(for item: MinecraftContentItem) -> String {
        "\(suggestedBaseFilename(for: item)).\(item.contentType.archiveExtension)"
    }

    nonisolated private static func createArchive(for item: MinecraftContentItem, at archiveURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.currentDirectoryURL = item.folderURL
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

    nonisolated private static func normalizedArchiveURL(for item: MinecraftContentItem, destinationURL: URL) -> URL {
        let normalizedDestinationURL = destinationURL.standardizedFileURL
        let requiredExtension = item.contentType.archiveExtension

        if normalizedDestinationURL.pathExtension.lowercased() == requiredExtension {
            return normalizedDestinationURL
        }

        return normalizedDestinationURL.appendingPathExtension(requiredExtension)
    }

    nonisolated private static func temporaryArchiveURL(for item: MinecraftContentItem, fileManager: FileManager) -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(item.contentType.archiveExtension)
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
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let components = value.components(separatedBy: invalidCharacters)
        let collapsed = components.joined(separator: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let normalizedWhitespace = collapsed.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )

        return normalizedWhitespace.isEmpty ? "Minecraft Content" : normalizedWhitespace
    }
}
