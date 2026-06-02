// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

nonisolated struct JavaArchiveMetadata: Hashable, Sendable {
    var displayName: String?
    var pack: JavaPackMetadata?
    var iconEntryPath: String?
}

enum JavaContentMetadataReader {
    nonisolated static func metadata(for item: MinecraftContentItem) -> JavaArchiveMetadata? {
        let values = try? item.folderURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        if values?.isDirectory == true {
            return directoryMetadata(for: item)
        }

        if values?.isRegularFile == true {
            return archiveMetadata(for: item.folderURL, contentKind: item.contentKind)
        }

        return nil
    }

    nonisolated static func cachedIconURL(for item: MinecraftContentItem, metadata: JavaArchiveMetadata?) async -> URL? {
        let values = try? item.folderURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        if values?.isDirectory == true {
            return await ImageCacheStore.shared.cachedImageURL(for: directoryIconURL(for: item))
        }

        guard
            values?.isRegularFile == true,
            let metadata,
            let iconEntryPath = metadata.iconEntryPath,
            let archive = try? ZipArchiveReader(url: item.folderURL),
            let entry = archive.entry(named: iconEntryPath),
            let data = try? archive.extract(entry)
        else {
            return nil
        }

        return await ImageCacheStore.shared.cachedImageURL(
            forRemoteData: data,
            cacheKey: "java-archive-icon:\(item.folderURL.standardizedFileURL.path):\(iconEntryPath)",
            pathExtension: URL(fileURLWithPath: iconEntryPath).pathExtension
        )
    }

    nonisolated private static func directoryMetadata(for item: MinecraftContentItem) -> JavaArchiveMetadata {
        let pack = packMetadata(from: item.folderURL.appendingPathComponent("pack.mcmeta"))
        let iconURL = directoryIconURL(for: item)

        return JavaArchiveMetadata(
            displayName: nil,
            pack: pack,
            iconEntryPath: iconURL?.lastPathComponent
        )
    }

    nonisolated private static func archiveMetadata(for archiveURL: URL, contentKind: MinecraftContentKind) -> JavaArchiveMetadata? {
        guard let archive = try? ZipArchiveReader(url: archiveURL) else {
            return nil
        }

        let pack = packMetadata(from: archive)
        let modMetadata = contentKind == .mod ? modMetadata(from: archive) : nil
        let iconEntryPath = iconEntryPath(
            in: archive,
            preferredPath: modMetadata?.iconPath,
            contentKind: contentKind
        )

        return JavaArchiveMetadata(
            displayName: modMetadata?.displayName,
            pack: pack,
            iconEntryPath: iconEntryPath
        )
    }

    nonisolated private static func directoryIconURL(for item: MinecraftContentItem) -> URL? {
        let candidateNames: [String]
        switch item.contentKind {
        case .mod:
            candidateNames = ["icon.png", "logo.png", "mod_logo.png", "catalogue_icon.png", "pack.png"]
        case .resourcePack, .dataPack, .shaderPack:
            candidateNames = ["pack.png", "icon.png", "logo.png"]
        case .world, .behaviorPack, .skinPack, .worldTemplate:
            candidateNames = ["icon.png", "pack.png"]
        }

        for candidateName in candidateNames {
            let candidateURL = item.folderURL.appendingPathComponent(candidateName)
            if FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return nil
    }

    nonisolated private static func packMetadata(from metadataURL: URL) -> JavaPackMetadata? {
        guard let data = try? Data(contentsOf: metadataURL) else {
            return nil
        }

        return packMetadata(from: data)
    }

    nonisolated private static func packMetadata(from archive: ZipArchiveReader) -> JavaPackMetadata? {
        guard
            let entry = archive.entry(named: "pack.mcmeta"),
            let data = try? archive.extract(entry)
        else {
            return nil
        }

        return packMetadata(from: data)
    }

    nonisolated private static func packMetadata(from data: Data) -> JavaPackMetadata? {
        guard
            let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let packObject = jsonObject["pack"] as? [String: Any]
        else {
            return nil
        }

        return JavaPackMetadata(
            packFormat: packObject["pack_format"] as? Int,
            description: textValue(from: packObject["description"])
        )
    }

    nonisolated private static func modMetadata(from archive: ZipArchiveReader) -> (displayName: String?, iconPath: String?)? {
        if let tomlMetadata = modTOMLMetadata(from: archive) {
            return tomlMetadata
        }

        if let jsonMetadata = modJSONMetadata(from: archive, entryName: "fabric.mod.json") {
            return jsonMetadata
        }

        if let jsonMetadata = modJSONMetadata(from: archive, entryName: "quilt.mod.json") {
            return jsonMetadata
        }

        return nil
    }

    nonisolated private static func modTOMLMetadata(from archive: ZipArchiveReader) -> (displayName: String?, iconPath: String?)? {
        let entryNames = ["META-INF/neoforge.mods.toml", "META-INF/mods.toml"]
        for entryName in entryNames {
            guard
                let entry = archive.entry(named: entryName),
                let data = try? archive.extract(entry),
                let text = String(data: data, encoding: .utf8)
            else {
                continue
            }

            let firstModSection = firstTOMLSection(named: "[[mods]]", in: text)
            let displayName = tomlStringValue(forKey: "displayName", in: firstModSection)
            let logoFile = tomlStringValue(forKey: "logoFile", in: firstModSection)
            if displayName != nil || logoFile != nil {
                return (displayName, logoFile)
            }
        }

        return nil
    }

    nonisolated private static func modJSONMetadata(
        from archive: ZipArchiveReader,
        entryName: String
    ) -> (displayName: String?, iconPath: String?)? {
        guard
            let entry = archive.entry(named: entryName),
            let data = try? archive.extract(entry),
            let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let iconPath: String?
        if let iconString = jsonObject["icon"] as? String {
            iconPath = iconString
        } else if let icons = jsonObject["icon"] as? [String: String] {
            iconPath = icons.sorted { lhs, rhs in lhs.key.localizedStandardCompare(rhs.key) == .orderedDescending }.first?.value
        } else {
            iconPath = nil
        }

        return (
            (jsonObject["name"] as? String)?.nilIfBlank,
            iconPath?.nilIfBlank
        )
    }

    nonisolated private static func firstTOMLSection(named sectionName: String, in text: String) -> String {
        guard let sectionRange = text.range(of: sectionName) else {
            return text
        }

        let sectionText = text[sectionRange.upperBound...]
        if let nextSectionRange = sectionText.range(of: "\n[") {
            return String(sectionText[..<nextSectionRange.lowerBound])
        }

        return String(sectionText)
    }

    nonisolated private static func tomlStringValue(forKey key: String, in text: String) -> String? {
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix(key) else {
                continue
            }

            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                continue
            }

            return parts[1]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                .nilIfBlank
        }

        return nil
    }

    nonisolated private static func iconEntryPath(
        in archive: ZipArchiveReader,
        preferredPath: String?,
        contentKind: MinecraftContentKind
    ) -> String? {
        let candidateNames: [String]
        switch contentKind {
        case .mod:
            candidateNames = [preferredPath, "icon.png", "logo.png", "mod_logo.png", "catalogue_icon.png", "pack.png"].compactMap(\.self)
        case .resourcePack, .dataPack, .shaderPack:
            candidateNames = [preferredPath, "pack.png", "icon.png", "logo.png"].compactMap(\.self)
        case .world, .behaviorPack, .skinPack, .worldTemplate:
            candidateNames = [preferredPath, "icon.png", "pack.png"].compactMap(\.self)
        }

        for candidateName in candidateNames {
            if let entry = archive.entry(named: candidateName), !entry.isDirectory {
                return entry.path
            }
        }

        return archive.entries
            .filter { !$0.isDirectory && $0.path.localizedCaseInsensitiveContains("icon") && $0.path.hasSuffix(".png") }
            .sorted { lhs, rhs in lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending }
            .first?
            .path
    }

    nonisolated private static func textValue(from value: Any?) -> String? {
        if let text = value as? String {
            return text.nilIfBlank
        }

        if let object = value as? [String: Any] {
            if let text = object["text"] as? String {
                return text.nilIfBlank
            }
            if let translate = object["translate"] as? String {
                return translate.nilIfBlank
            }
        }

        return nil
    }
}

private extension String {
    nonisolated var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
