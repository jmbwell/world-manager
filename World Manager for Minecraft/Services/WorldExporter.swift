//
//  WorldExporter.swift
//  World Manager for Minecraft
//
//  Created by John Burwell on 2026-05-25.
//

import Foundation

enum WorldExporter {
    enum ExportError: LocalizedError {
        case unsupportedContentType
        case failedToCreateArchive(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedContentType:
                return "Only Minecraft worlds can be exported as .mcworld files."
            case .failedToCreateArchive(let output):
                return output.isEmpty ? "Failed to create the .mcworld archive." : output
            }
        }
    }

    nonisolated static func exportWorld(_ item: MinecraftContentItem, to destinationURL: URL) throws {
        guard item.contentType == .world else {
            throw ExportError.unsupportedContentType
        }

        let fileManager = FileManager.default
        let normalizedDestinationURL = destinationURL.standardizedFileURL
        let archiveURL = normalizedDestinationURL.pathExtension.lowercased() == "mcworld"
            ? normalizedDestinationURL
            : normalizedDestinationURL.appendingPathExtension("mcworld")

        let temporaryArchiveURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mcworld")

        defer {
            try? fileManager.removeItem(at: temporaryArchiveURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.currentDirectoryURL = item.folderURL
        process.arguments = [
            "-c",
            "-k",
            "--norsrc",
            ".",
            temporaryArchiveURL.path
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

        if fileManager.fileExists(atPath: archiveURL.path) {
            try fileManager.removeItem(at: archiveURL)
        }

        try fileManager.moveItem(at: temporaryArchiveURL, to: archiveURL)
    }

    nonisolated static func suggestedFilename(for item: MinecraftContentItem) -> String {
        let baseName = sanitizedFilename(item.displayName.isEmpty ? item.folderName : item.displayName)
        return "\(baseName).mcworld"
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

        return normalizedWhitespace.isEmpty ? "Minecraft World" : normalizedWhitespace
    }
}
