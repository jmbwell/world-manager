//
//  ImageCacheStore.swift
//  World Manager for Minecraft
//
//  Created by OpenAI on 2026-05-26.
//

import CryptoKit
import Foundation

actor ImageCacheStore {
    static let shared = ImageCacheStore()

    private let fileManager: FileManager
    private let cacheDirectoryURL: URL
    private let cacheDirectoryPath: String

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches", isDirectory: true)
        let cacheDirectoryURL = cachesURL
            .appendingPathComponent("World Manager for Minecraft", isDirectory: true)
            .appendingPathComponent("ImageCache", isDirectory: true)

        self.cacheDirectoryURL = cacheDirectoryURL
        self.cacheDirectoryPath = cacheDirectoryURL.standardizedFileURL.path
    }

    func cachedImageURL(for sourceImageURL: URL?) -> URL? {
        guard let sourceImageURL else {
            return nil
        }

        let normalizedSourceURL = sourceImageURL.standardizedFileURL
        if isCachedImageURL(normalizedSourceURL) {
            return fileManager.fileExists(atPath: normalizedSourceURL.path) ? normalizedSourceURL : nil
        }

        guard fileManager.fileExists(atPath: normalizedSourceURL.path) else {
            return nil
        }

        guard
            let resourceValues = try? normalizedSourceURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
            let fileSize = resourceValues.fileSize
        else {
            return nil
        }

        let modifiedStamp = resourceValues.contentModificationDate?.timeIntervalSince1970 ?? 0
        let sourceKey = digest(for: normalizedSourceURL.path)
        let versionKey = digest(for: "\(normalizedSourceURL.path)|\(modifiedStamp)|\(fileSize)")
        let pathExtension = normalizedSourceURL.pathExtension.isEmpty ? "img" : normalizedSourceURL.pathExtension
        let cachedURL = cacheDirectoryURL
            .appendingPathComponent("\(sourceKey)-\(versionKey)", isDirectory: false)
            .appendingPathExtension(pathExtension)

        do {
            try fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)

            if fileManager.fileExists(atPath: cachedURL.path) {
                return cachedURL
            }

            purgeStaleVariants(forSourceKey: sourceKey, keeping: cachedURL)
            try fileManager.copyItem(at: normalizedSourceURL, to: cachedURL)
            return cachedURL
        } catch {
            return nil
        }
    }

    func isCachedImageURL(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(cacheDirectoryPath + "/")
    }

    private func purgeStaleVariants(forSourceKey sourceKey: String, keeping cachedURL: URL) {
        guard let cachedFiles = try? fileManager.contentsOfDirectory(
            at: cacheDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for url in cachedFiles where url.lastPathComponent.hasPrefix(sourceKey + "-") && url != cachedURL {
            try? fileManager.removeItem(at: url)
        }
    }

    private func digest(for value: String) -> String {
        let bytes = SHA256.hash(data: Data(value.utf8))
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
