//
//  ConnectedDeviceMirrorCache.swift
//  World Manager for Minecraft
//
//  Created by OpenAI on 2026-05-26.
//

import Foundation

enum ConnectedDeviceMirrorCache {
    nonisolated static func rootURL(for sourceID: URL, fileManager: FileManager = .default) -> URL {
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)

        return applicationSupportURL
            .appendingPathComponent("World Manager for Minecraft", isDirectory: true)
            .appendingPathComponent("ConnectedDeviceCache", isDirectory: true)
            .appendingPathComponent(sanitizedComponent(for: sourceID), isDirectory: true)
    }

    nonisolated static func purgeRootURL(for sourceID: URL, fileManager: FileManager = .default) throws {
        let rootURL = rootURL(for: sourceID, fileManager: fileManager)
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return
        }

        try fileManager.removeItem(at: rootURL)
    }

    nonisolated private static func sanitizedComponent(for sourceID: URL) -> String {
        let rawValue = sourceID.absoluteString
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))

        let pieces = rawValue.unicodeScalars.map { scalar -> String in
            allowed.contains(scalar) ? String(scalar) : "_"
        }

        return String(pieces.joined().prefix(180))
    }
}
