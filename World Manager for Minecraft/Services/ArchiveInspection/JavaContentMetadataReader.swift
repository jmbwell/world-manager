// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

nonisolated struct JavaArchiveMetadata: Hashable, Sendable {
    var displayName: String?
    var pack: JavaPackMetadata?
    var mod: JavaModMetadata?
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
            mod: nil,
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
            mod: modMetadata?.metadata,
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
            supportedFormats: supportedFormatsValue(from: packObject["supported_formats"]),
            description: textValue(from: packObject["description"])
        )
    }

    nonisolated private static func modMetadata(
        from archive: ZipArchiveReader
    ) -> (displayName: String?, iconPath: String?, metadata: JavaModMetadata)? {
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

    nonisolated private static func modTOMLMetadata(
        from archive: ZipArchiveReader
    ) -> (displayName: String?, iconPath: String?, metadata: JavaModMetadata)? {
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
            let dependenciesSection = firstTOMLSection(named: "[[dependencies.", in: text)
            let displayName = tomlStringValue(forKey: "displayName", in: firstModSection)
            let logoFile = tomlStringValue(forKey: "logoFile", in: firstModSection)
            let metadata = JavaModMetadata(
                modID: tomlStringValue(forKey: "modId", in: firstModSection),
                version: tomlStringValue(forKey: "version", in: firstModSection),
                description: tomlStringValue(forKey: "description", in: firstModSection),
                authors: stringListValue(from: tomlStringValue(forKey: "authors", in: firstModSection)),
                license: tomlStringValue(forKey: "license", in: text),
                environment: nil,
                minecraftVersionRequirement: minecraftDependencyRequirement(fromTOMLSection: dependenciesSection)
            )
            if displayName != nil || logoFile != nil || metadata.hasValues {
                return (displayName, logoFile, metadata)
            }
        }

        return nil
    }

    nonisolated private static func modJSONMetadata(
        from archive: ZipArchiveReader,
        entryName: String
    ) -> (displayName: String?, iconPath: String?, metadata: JavaModMetadata)? {
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

        let metadata = JavaModMetadata(
            modID: (jsonObject["id"] as? String)?.nilIfBlank,
            version: (jsonObject["version"] as? String)?.nilIfBlank,
            description: textValue(from: jsonObject["description"]),
            authors: authorsValue(from: jsonObject["authors"]),
            license: licenseValue(from: jsonObject["license"]),
            environment: (jsonObject["environment"] as? String)?.nilIfBlank,
            minecraftVersionRequirement: minecraftDependencyRequirement(fromJSON: jsonObject)
        )

        return (
            (jsonObject["name"] as? String)?.nilIfBlank,
            iconPath?.nilIfBlank,
            metadata
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

    nonisolated private static func minecraftDependencyRequirement(fromTOMLSection text: String) -> String? {
        guard tomlStringValue(forKey: "modId", in: text) == "minecraft" else {
            return nil
        }

        return tomlStringValue(forKey: "versionRange", in: text)
    }

    nonisolated private static func minecraftDependencyRequirement(fromJSON jsonObject: [String: Any]) -> String? {
        for key in ["depends", "dependencies", "breaks"] {
            guard let dependencies = jsonObject[key] as? [String: Any] else {
                continue
            }

            if let minecraft = dependencies["minecraft"] as? String {
                return minecraft.nilIfBlank
            }
            if let minecraft = dependencies["minecraft"] as? [String: Any] {
                return textValue(from: minecraft["version"])
            }
        }

        return nil
    }

    nonisolated private static func authorsValue(from value: Any?) -> [String] {
        if let author = value as? String {
            return stringListValue(from: author)
        }

        if let authors = value as? [String] {
            return authors.compactMap(\.nilIfBlank)
        }

        if let authors = value as? [[String: Any]] {
            return authors.compactMap { author in
                textValue(from: author["name"])
            }
        }

        return []
    }

    nonisolated private static func licenseValue(from value: Any?) -> String? {
        if let license = value as? String {
            return license.nilIfBlank
        }

        if let licenses = value as? [String] {
            let values = licenses.compactMap(\.nilIfBlank)
            return values.isEmpty ? nil : values.joined(separator: ", ")
        }

        return nil
    }

    nonisolated private static func stringListValue(from value: String?) -> [String] {
        guard let value else {
            return []
        }

        return value
            .split { character in
                character == "," || character == ";"
            }
            .map(String.init)
            .compactMap(\.nilIfBlank)
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

    nonisolated private static func supportedFormatsValue(from value: Any?) -> String? {
        if let format = value as? Int {
            return String(format)
        }

        if let formats = value as? [Int] {
            return formats.map(String.init).joined(separator: ", ").nilIfBlank
        }

        if let object = value as? [String: Any] {
            let minValue = object["min_inclusive"] as? Int
            let maxValue = object["max_inclusive"] as? Int
            switch (minValue, maxValue) {
            case (.some(let minValue), .some(let maxValue)):
                return "\(minValue)-\(maxValue)"
            case (.some(let minValue), .none):
                return "\(minValue)+"
            case (.none, .some(let maxValue)):
                return "Up to \(maxValue)"
            case (.none, .none):
                return nil
            }
        }

        return nil
    }
}

private extension JavaModMetadata {
    nonisolated var hasValues: Bool {
        modID != nil
            || version != nil
            || description != nil
            || !authors.isEmpty
            || license != nil
            || environment != nil
            || minecraftVersionRequirement != nil
    }
}

private extension String {
    nonisolated var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
