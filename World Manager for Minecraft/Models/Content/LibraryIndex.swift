// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

nonisolated enum PackIdentitySource: String, Hashable, Sendable {
    case manifestUUID
    case fallback
}

nonisolated struct PackIdentity: Hashable, Sendable, Identifiable {
    let type: MinecraftContentType
    let uuid: String?
    let version: String?
    let fallbackName: String
    let fallbackLocationHint: String?
    let source: PackIdentitySource

    nonisolated var id: String {
        [
            type.rawValue,
            uuid ?? normalizedFallbackName,
            version ?? "",
            fallbackLocationHint ?? ""
        ].joined(separator: "::")
    }

    nonisolated var canonicalKey: String {
        if let uuid {
            return [
                type.rawValue,
                uuid,
                version ?? ""
            ].joined(separator: "::")
        }

        return [
            type.rawValue,
            normalizedFallbackName,
            version ?? "",
            fallbackLocationHint ?? ""
        ].joined(separator: "::")
    }

    nonisolated var isSuspicious: Bool {
        source == .fallback
    }

    nonisolated init(
        type: MinecraftContentType,
        uuid: String?,
        version: String?,
        fallbackName: String,
        fallbackLocationHint: String?
    ) {
        self.type = type
        self.uuid = uuid?.lowercased()
        self.version = version
        self.fallbackName = fallbackName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.fallbackLocationHint = fallbackLocationHint
        self.source = self.uuid == nil ? .fallback : .manifestUUID
    }

    private nonisolated var normalizedFallbackName: String {
        fallbackName.lowercased()
    }

    nonisolated static func == (lhs: PackIdentity, rhs: PackIdentity) -> Bool {
        guard lhs.type == rhs.type else {
            return false
        }

        if let lhsUUID = lhs.uuid, let rhsUUID = rhs.uuid {
            return lhsUUID == rhsUUID && lhs.version == rhs.version
        }

        return lhs.uuid == rhs.uuid
            && lhs.version == rhs.version
            && lhs.normalizedFallbackName == rhs.normalizedFallbackName
            && lhs.fallbackLocationHint == rhs.fallbackLocationHint
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(type)

        if let uuid {
            hasher.combine(uuid)
            hasher.combine(version)
            return
        }

        hasher.combine(uuid)
        hasher.combine(version)
        hasher.combine(normalizedFallbackName)
        hasher.combine(fallbackLocationHint)
    }
}

nonisolated struct PackInstance: Identifiable, Hashable, Sendable {
    let id: URL
    let itemID: URL
    let sourceID: URL
    let logicalPackID: PackIdentity
    let origin: PackSource
    let hostWorldItemID: URL?
}

nonisolated struct LogicalPack: Identifiable, Hashable, Sendable {
    let id: PackIdentity
    let contentType: MinecraftContentType
    let displayName: String
    let uuid: String?
    let version: String?
    let representativeItemID: URL
    let instanceItemIDs: [URL]
    let isSuspicious: Bool
}

nonisolated struct LogicalWorld: Identifiable, Hashable, Sendable {
    let id: URL
    let itemID: URL
    let usedPackIDs: [PackIdentity]
    let unresolvedReferences: [ContentPackReference]
}

nonisolated struct WorldPackRelationship: Identifiable, Hashable, Sendable {
    let worldItemID: URL
    let logicalPackID: PackIdentity?
    let reference: ContentPackReference

    var id: String {
        [
            worldItemID.path,
            logicalPackID?.id ?? "unresolved",
            reference.id
        ].joined(separator: "::")
    }
}

nonisolated struct ItemSnapshot: Identifiable, Hashable, Sendable, Codable {
    let id: URL
    let relativePath: String
    let modifiedDate: Date?
    let sizeBytes: Int64?
    let packUUID: String?
    let packVersion: String?
}

nonisolated struct CollectionSnapshot: Identifiable, Hashable, Sendable, Codable {
    let folderName: String
    let modifiedDate: Date?
    let childDirectoryCount: Int
    let fingerprint: String

    var id: String { folderName }
}

nonisolated struct SourceSnapshot: Hashable, Sendable, Codable {
    let sourceID: URL
    let rootModifiedDate: Date?
    let collectionSnapshots: [CollectionSnapshot]
    let itemSnapshots: [ItemSnapshot]
}
