// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

struct MinecraftManifestMetadata: Sendable, Hashable {
    let name: String
    let uuid: String?
    let version: String?
    let minimumEngineVersion: String?
}

typealias MinecraftContentMetadataReader = BedrockContentMetadataReader

enum BedrockContentMetadataReader {
    nonisolated static func displayName(
        for directoryURL: URL,
        contentType: MinecraftContentType,
        fallbackName: String,
        fileManager: FileManager = .default
    ) -> String {
        switch contentType {
        case .world:
            let levelNameURL = directoryURL.appendingPathComponent("levelname.txt")
            guard
                let name = try? String(contentsOf: levelNameURL, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !name.isEmpty
            else {
                return fallbackName
            }

            return name
        case .behaviorPack, .resourcePack, .skinPack, .worldTemplate:
            if let manifestName = manifestMetadata(in: directoryURL, fileManager: fileManager)?.name {
                return manifestName
            }

            return fallbackName
        }
    }

    nonisolated static func iconURL(
        for directoryURL: URL,
        contentType: MinecraftContentType,
        fileManager: FileManager = .default
    ) -> URL? {
        let candidateNames: [String]

        switch contentType {
        case .world:
            candidateNames = ["world_icon.jpeg", "world_icon.jpg", "world_icon.png"]
        case .behaviorPack, .resourcePack, .skinPack, .worldTemplate:
            candidateNames = ["pack_icon.png", "pack_icon.jpeg", "pack_icon.jpg"]
        }

        for candidateName in candidateNames {
            let candidateURL = directoryURL.appendingPathComponent(candidateName)
            if fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return nil
    }

    nonisolated static func packIconURL(
        in directoryURL: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let candidateNames = ["pack_icon.png", "pack_icon.jpeg", "pack_icon.jpg"]

        for candidateName in candidateNames {
            let candidateURL = directoryURL.appendingPathComponent(candidateName)
            if fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return nil
    }

    nonisolated static func worldMetadata(
        in directoryURL: URL,
        fileManager: FileManager = .default
    ) -> WorldMetadata? {
        let levelDatURL = directoryURL.appendingPathComponent("level.dat")
        guard fileManager.fileExists(atPath: levelDatURL.path) else {
            return nil
        }

        return BedrockLevelMetadataDecoder.decode(fromLevelDatAt: levelDatURL)
    }

    nonisolated static func manifestMetadata(
        in directoryURL: URL,
        fileManager: FileManager = .default
    ) -> MinecraftManifestMetadata? {
        let manifestURL = directoryURL.appendingPathComponent("manifest.json")
        guard
            fileManager.fileExists(atPath: manifestURL.path),
            let data = try? Data(contentsOf: manifestURL),
            let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let header = jsonObject["header"] as? [String: Any]
        else {
            return nil
        }

        let name = ((header["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : $0
        } ?? directoryURL.lastPathComponent

        return MinecraftManifestMetadata(
            name: name,
            uuid: (header["uuid"] as? String)?.lowercased(),
            version: versionString(from: header["version"]),
            minimumEngineVersion: versionString(from: header["min_engine_version"])
        )
    }

    nonisolated static func versionString(from value: Any?) -> String? {
        if let versionString = value as? String, !versionString.isEmpty {
            return versionString
        }

        if let versionArray = value as? [Any] {
            let components = versionArray.compactMap { component -> String? in
                if let intComponent = component as? Int {
                    return String(intComponent)
                }
                if let stringComponent = component as? String {
                    return stringComponent
                }
                return nil
            }

            return components.isEmpty ? nil : components.joined(separator: ".")
        }

        return nil
    }

    nonisolated static func inferredPackContentType(
        for directoryURL: URL,
        fileManager: FileManager = .default
    ) -> MinecraftContentType {
        let manifestURL = directoryURL.appendingPathComponent("manifest.json")
        guard
            fileManager.fileExists(atPath: manifestURL.path),
            let data = try? Data(contentsOf: manifestURL),
            let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return .behaviorPack
        }

        if let modules = jsonObject["modules"] as? [[String: Any]] {
            let normalizedTypes = modules.compactMap { ($0["type"] as? String)?.lowercased() }
            if normalizedTypes.contains("resources") || normalizedTypes.contains("client_data") {
                return .resourcePack
            }
            if normalizedTypes.contains("skin_pack") {
                return .skinPack
            }
            if normalizedTypes.contains("data") || normalizedTypes.contains("script") || normalizedTypes.contains("javascript") {
                return .behaviorPack
            }
        }

        if let metadata = jsonObject["metadata"] as? [String: Any],
           let productType = (metadata["product_type"] as? String)?.lowercased() {
            if productType.contains("skin") {
                return .skinPack
            }
            if productType.contains("resource") {
                return .resourcePack
            }
        }

        return .behaviorPack
    }
}
