//
//  MinecraftContentItem.swift
//  World Manager for Minecraft
//
//  Created by John Burwell on 2026-05-25.
//

import Foundation

enum MinecraftContentType: String, CaseIterable, Hashable, Sendable, Codable {
    case world = "World"
    case behaviorPack = "Behavior Pack"
    case resourcePack = "Resource Pack"
    case skinPack = "Skin Pack"
    case worldTemplate = "World Template"

    nonisolated var collectionFolderName: String {
        switch self {
        case .world:
            return "minecraftWorlds"
        case .behaviorPack:
            return "behavior_packs"
        case .resourcePack:
            return "resource_packs"
        case .skinPack:
            return "skin_packs"
        case .worldTemplate:
            return "world_templates"
        }
    }

    nonisolated var archiveExtension: String {
        switch self {
        case .world:
            return "mcworld"
        case .behaviorPack, .resourcePack, .skinPack:
            return "mcpack"
        case .worldTemplate:
            return "mctemplate"
        }
    }

    nonisolated var exportTitle: String {
        switch self {
        case .world:
            return "Minecraft World"
        case .behaviorPack:
            return "Behavior Pack"
        case .resourcePack:
            return "Resource Pack"
        case .skinPack:
            return "Skin Pack"
        case .worldTemplate:
            return "World Template"
        }
    }
}

enum PackSource: String, Hashable, Sendable, Codable {
    case referencedByWorld
    case embeddedInWorld
    case foundInCollection
}

struct ContentPackReference: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let name: String
    let type: MinecraftContentType
    let iconURL: URL?
    let uuid: String?
    let version: String?
    let source: PackSource

    nonisolated init(
        name: String,
        type: MinecraftContentType,
        iconURL: URL? = nil,
        uuid: String? = nil,
        version: String? = nil,
        source: PackSource
    ) {
        self.type = type
        self.iconURL = iconURL
        self.uuid = uuid?.lowercased()
        self.version = version
        self.source = source
        self.name = name
        self.id = [
            type.rawValue,
            self.uuid ?? name,
            version ?? source.rawValue
        ].joined(separator: "::")
    }
}

struct WorldMetadata: Hashable, Sendable, Codable {
    var gameMode: String?
    var difficulty: String?
    var seed: String?
    var lastPlayedDate: Date?
    var lastOpenedWithVersion: String?
    var inventoryVersion: String?
    var cheatsEnabled: Bool?
    var commandsEnabled: Bool?
    var educationFeaturesEnabled: Bool?
    var coordinatesShown: Bool?
    var keepInventory: Bool?
    var mobGriefingEnabled: Bool?
    var daylightCycleEnabled: Bool?
    var weatherCycleEnabled: Bool?
    var spawn: String?
    var storageVersion: String?
    var networkVersion: String?
}

struct PackMetadataDetails: Hashable, Sendable, Codable {
    var minimumEngineVersion: String?
}

struct MinecraftContentItem: Identifiable, Hashable, Sendable, Codable {
    let id: URL
    let folderURL: URL
    let folderName: String
    let contentType: MinecraftContentType
    let collectionRootURL: URL
    var displayName: String
    var iconURL: URL?
    var lastPlayedDate: Date?
    var modifiedDate: Date?
    var sizeBytes: Int64?
    var packUUID: String?
    var packVersion: String?
    var packMetadataDetails: PackMetadataDetails?
    var packReferences: [ContentPackReference]
    var worldMetadata: WorldMetadata?
    var metadataLoaded: Bool
    var sizeLoaded: Bool

    nonisolated init(
        folderURL: URL,
        folderName: String,
        contentType: MinecraftContentType,
        collectionRootURL: URL,
        displayName: String? = nil,
        iconURL: URL? = nil,
        lastPlayedDate: Date? = nil,
        modifiedDate: Date? = nil,
        sizeBytes: Int64? = nil,
        packUUID: String? = nil,
        packVersion: String? = nil,
        packMetadataDetails: PackMetadataDetails? = nil,
        packReferences: [ContentPackReference] = [],
        worldMetadata: WorldMetadata? = nil,
        metadataLoaded: Bool = false,
        sizeLoaded: Bool = false
    ) {
        self.id = folderURL.standardizedFileURL
        self.folderURL = folderURL
        self.folderName = folderName
        self.contentType = contentType
        self.collectionRootURL = collectionRootURL
        self.displayName = displayName ?? folderName
        self.iconURL = iconURL
        self.lastPlayedDate = lastPlayedDate
        self.modifiedDate = modifiedDate
        self.sizeBytes = sizeBytes
        self.packUUID = packUUID?.lowercased()
        self.packVersion = packVersion
        self.packMetadataDetails = packMetadataDetails
        self.packReferences = packReferences
        self.worldMetadata = worldMetadata
        self.metadataLoaded = metadataLoaded
        self.sizeLoaded = sizeLoaded
    }

    nonisolated var folderID: String {
        folderName
    }

    nonisolated var displayDate: Date? {
        lastPlayedDate ?? modifiedDate
    }

    nonisolated var displayDateLabel: String {
        lastPlayedDate == nil ? "Modified" : "Last Played"
    }

    nonisolated var searchText: String {
        var values: [String] = [
            displayName,
            folderName,
            folderURL.path,
            contentType.rawValue
        ]
        values.append(worldMetadata?.gameMode ?? "")
        values.append(worldMetadata?.difficulty ?? "")
        values.append(worldMetadata?.seed ?? "")
        values.append(worldMetadata?.lastOpenedWithVersion ?? "")
        values.append(packMetadataDetails?.minimumEngineVersion ?? "")
        values.append(packReferences.map(\.name).joined(separator: " "))
        values.append(packReferences.compactMap(\.uuid).joined(separator: " "))

        return values
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    nonisolated static func == (lhs: MinecraftContentItem, rhs: MinecraftContentItem) -> Bool {
        lhs.id == rhs.id
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
