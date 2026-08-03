// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

typealias PlatformProviderID = String

nonisolated enum MinecraftEdition: String, CaseIterable, Hashable, Sendable, Codable {
    case bedrock
    case java
}

nonisolated enum MinecraftContentKind: String, CaseIterable, Hashable, Sendable, Codable {
    case world
    case behaviorPack
    case resourcePack
    case dataPack
    case skinPack
    case worldTemplate
    case shaderPack
    case mod
}

nonisolated enum JavaContentType: String, CaseIterable, Hashable, Sendable, Codable {
    case world = "Java World"
    case resourcePack = "Java Resource Pack"
    case dataPack = "Java Data Pack"
    case shaderPack = "Java Shader Pack"
    case mod = "Java Mod"

    nonisolated var kind: MinecraftContentKind {
        switch self {
        case .world:
            return .world
        case .resourcePack:
            return .resourcePack
        case .dataPack:
            return .dataPack
        case .shaderPack:
            return .shaderPack
        case .mod:
            return .mod
        }
    }
}

nonisolated enum MinecraftContentType: String, CaseIterable, Hashable, Sendable, Codable {
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

    nonisolated var kind: MinecraftContentKind {
        switch self {
        case .world:
            return .world
        case .behaviorPack:
            return .behaviorPack
        case .resourcePack:
            return .resourcePack
        case .skinPack:
            return .skinPack
        case .worldTemplate:
            return .worldTemplate
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

nonisolated enum MinecraftPlatformContentType: Hashable, Sendable, Codable {
    case bedrock(MinecraftContentType)
    case java(JavaContentType)

    nonisolated var edition: MinecraftEdition {
        switch self {
        case .bedrock:
            return .bedrock
        case .java:
            return .java
        }
    }

    nonisolated var kind: MinecraftContentKind {
        switch self {
        case .bedrock(let contentType):
            return contentType.kind
        case .java(let contentType):
            return contentType.kind
        }
    }

    nonisolated var displayName: String {
        switch self {
        case .bedrock(let contentType):
            return contentType.rawValue
        case .java(let contentType):
            return contentType.rawValue
        }
    }
}

nonisolated struct ContentItemCapabilities: Hashable, Sendable, Codable {
    var canRevealNativeContent: Bool
    var canExportPortablePackage: Bool
    var canShare: Bool
    var portablePackageExtension: String?

    nonisolated static func bedrock(contentType: MinecraftContentType) -> ContentItemCapabilities {
        ContentItemCapabilities(
            canRevealNativeContent: true,
            canExportPortablePackage: true,
            canShare: true,
            portablePackageExtension: contentType.archiveExtension
        )
    }

    nonisolated static func java(contentType: JavaContentType) -> ContentItemCapabilities {
        let extensionName: String?
        switch contentType {
        case .world, .resourcePack, .dataPack, .shaderPack:
            extensionName = "zip"
        case .mod:
            extensionName = "jar"
        }

        return ContentItemCapabilities(
            canRevealNativeContent: true,
            canExportPortablePackage: true,
            canShare: true,
            portablePackageExtension: extensionName
        )
    }
}

nonisolated enum PackSource: String, Hashable, Sendable, Codable {
    case referencedByWorld
    case embeddedInWorld
    case foundInCollection
}

nonisolated struct ContentPackReference: Identifiable, Hashable, Sendable, Codable {
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

nonisolated struct WorldMetadata: Hashable, Sendable, Codable {
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

nonisolated struct PackMetadataDetails: Hashable, Sendable, Codable {
    var minimumEngineVersion: String?
}

nonisolated enum PlatformContentMetadata: Hashable, Sendable, Codable {
    case bedrock(BedrockContentMetadata)
    case java(JavaContentMetadata)
    case none
}

nonisolated struct BedrockContentMetadata: Hashable, Sendable, Codable {
    var world: WorldMetadata?
    var packUUID: String?
    var packVersion: String?
    var packDetails: PackMetadataDetails?
    var packReferences: [ContentPackReference]

    nonisolated init(
        world: WorldMetadata? = nil,
        packUUID: String? = nil,
        packVersion: String? = nil,
        packDetails: PackMetadataDetails? = nil,
        packReferences: [ContentPackReference] = []
    ) {
        self.world = world
        self.packUUID = packUUID?.lowercased()
        self.packVersion = packVersion
        self.packDetails = packDetails
        self.packReferences = packReferences
    }
}

nonisolated struct JavaContentMetadata: Hashable, Sendable, Codable {
    var world: JavaWorldMetadata?
    var pack: JavaPackMetadata?
    var mod: JavaModMetadata?
    var dataPacks: [JavaPackReference]

    nonisolated init(
        world: JavaWorldMetadata? = nil,
        pack: JavaPackMetadata? = nil,
        mod: JavaModMetadata? = nil,
        dataPacks: [JavaPackReference] = []
    ) {
        self.world = world
        self.pack = pack
        self.mod = mod
        self.dataPacks = dataPacks
    }
}

nonisolated struct JavaWorldMetadata: Hashable, Sendable, Codable {
    var dataVersion: String?
    var gameMode: String?
    var difficulty: String?
    var seed: String?
    var lastPlayedDate: Date?
}

nonisolated struct JavaPackMetadata: Hashable, Sendable, Codable {
    var packFormat: Int?
    var supportedFormats: String?
    var description: String?

    nonisolated init(
        packFormat: Int? = nil,
        supportedFormats: String? = nil,
        description: String? = nil
    ) {
        self.packFormat = packFormat
        self.supportedFormats = supportedFormats
        self.description = description
    }
}

nonisolated struct JavaModMetadata: Hashable, Sendable, Codable {
    var modID: String?
    var version: String?
    var description: String?
    var authors: [String]
    var license: String?
    var environment: String?
    var minecraftVersionRequirement: String?

    nonisolated init(
        modID: String? = nil,
        version: String? = nil,
        description: String? = nil,
        authors: [String] = [],
        license: String? = nil,
        environment: String? = nil,
        minecraftVersionRequirement: String? = nil
    ) {
        self.modID = modID
        self.version = version
        self.description = description
        self.authors = authors
        self.license = license
        self.environment = environment
        self.minecraftVersionRequirement = minecraftVersionRequirement
    }
}

nonisolated struct JavaPackReference: Identifiable, Hashable, Sendable, Codable {
    let id: String
    var name: String
    var pathHint: String?
}

nonisolated struct MinecraftContentItem: Identifiable, Hashable, Sendable, Codable {
    let id: URL
    let folderURL: URL
    let folderName: String
    let contentType: MinecraftContentType
    let sourceEdition: MinecraftEdition
    let contentKind: MinecraftContentKind
    let platformType: MinecraftPlatformContentType
    let collectionRootURL: URL
    var displayName: String
    var iconURL: URL?
    var hasKnownIcon: Bool
    var lastPlayedDate: Date?
    var modifiedDate: Date?
    var sizeBytes: Int64?
    var capabilities: ContentItemCapabilities
    var platformMetadata: PlatformContentMetadata
    var packUUID: String? {
        didSet { syncBedrockMetadataFromCompatibilityFields() }
    }
    var packVersion: String? {
        didSet { syncBedrockMetadataFromCompatibilityFields() }
    }
    var packMetadataDetails: PackMetadataDetails? {
        didSet { syncBedrockMetadataFromCompatibilityFields() }
    }
    var packReferences: [ContentPackReference] {
        didSet { syncBedrockMetadataFromCompatibilityFields() }
    }
    var worldMetadata: WorldMetadata? {
        didSet { syncBedrockMetadataFromCompatibilityFields() }
    }
    var metadataLoaded: Bool
    var previewLoaded: Bool
    var sizeLoaded: Bool

    nonisolated init(
        folderURL: URL,
        folderName: String,
        contentType: MinecraftContentType,
        sourceEdition: MinecraftEdition? = nil,
        contentKind: MinecraftContentKind? = nil,
        platformType: MinecraftPlatformContentType? = nil,
        collectionRootURL: URL,
        displayName: String? = nil,
        iconURL: URL? = nil,
        hasKnownIcon: Bool = false,
        lastPlayedDate: Date? = nil,
        modifiedDate: Date? = nil,
        sizeBytes: Int64? = nil,
        capabilities: ContentItemCapabilities? = nil,
        platformMetadata: PlatformContentMetadata? = nil,
        packUUID: String? = nil,
        packVersion: String? = nil,
        packMetadataDetails: PackMetadataDetails? = nil,
        packReferences: [ContentPackReference] = [],
        worldMetadata: WorldMetadata? = nil,
        metadataLoaded: Bool = false,
        previewLoaded: Bool = false,
        sizeLoaded: Bool = false
    ) {
        self.id = folderURL.standardizedFileURL
        self.folderURL = folderURL
        self.folderName = folderName
        self.contentType = contentType
        self.sourceEdition = sourceEdition ?? .bedrock
        self.contentKind = contentKind ?? contentType.kind
        self.platformType = platformType ?? .bedrock(contentType)
        self.collectionRootURL = collectionRootURL
        self.displayName = displayName ?? folderName
        self.iconURL = iconURL
        self.hasKnownIcon = hasKnownIcon
        self.lastPlayedDate = lastPlayedDate
        self.modifiedDate = modifiedDate
        self.sizeBytes = sizeBytes
        self.capabilities = capabilities ?? .bedrock(contentType: contentType)
        self.platformMetadata = platformMetadata ?? .bedrock(
            BedrockContentMetadata(
                world: worldMetadata,
                packUUID: packUUID,
                packVersion: packVersion,
                packDetails: packMetadataDetails,
                packReferences: packReferences
            )
        )
        self.packUUID = packUUID?.lowercased()
        self.packVersion = packVersion
        self.packMetadataDetails = packMetadataDetails
        self.packReferences = packReferences
        self.worldMetadata = worldMetadata
        self.metadataLoaded = metadataLoaded
        self.previewLoaded = previewLoaded
        self.sizeLoaded = sizeLoaded
    }

    nonisolated mutating private func syncBedrockMetadataFromCompatibilityFields() {
        guard sourceEdition == .bedrock else {
            return
        }

        platformMetadata = .bedrock(
            BedrockContentMetadata(
                world: worldMetadata,
                packUUID: packUUID,
                packVersion: packVersion,
                packDetails: packMetadataDetails,
                packReferences: packReferences
            )
        )
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
        if case .java(let metadata) = platformMetadata {
            values.append(metadata.world?.dataVersion ?? "")
            values.append(metadata.world?.gameMode ?? "")
            values.append(metadata.world?.difficulty ?? "")
            values.append(metadata.world?.seed ?? "")
            values.append(metadata.pack?.description ?? "")
            values.append(metadata.pack?.packFormat.map(String.init) ?? "")
            values.append(metadata.pack?.supportedFormats ?? "")
            values.append(metadata.mod?.modID ?? "")
            values.append(metadata.mod?.version ?? "")
            values.append(metadata.mod?.description ?? "")
            values.append(metadata.mod?.authors.joined(separator: " ") ?? "")
            values.append(metadata.mod?.license ?? "")
            values.append(metadata.mod?.environment ?? "")
            values.append(metadata.mod?.minecraftVersionRequirement ?? "")
            values.append(metadata.dataPacks.map(\.name).joined(separator: " "))
        }

        return values
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    nonisolated static func displaySort(_ lhs: MinecraftContentItem, _ rhs: MinecraftContentItem) -> Bool {
        if lhs.contentType != rhs.contentType {
            return lhs.contentType.rawValue.localizedStandardCompare(rhs.contentType.rawValue) == .orderedAscending
        }

        let displayNameOrder = lhs.displayName.localizedStandardCompare(rhs.displayName)
        if displayNameOrder != .orderedSame {
            return displayNameOrder == .orderedAscending
        }

        return lhs.folderName.localizedStandardCompare(rhs.folderName) == .orderedAscending
    }
}
