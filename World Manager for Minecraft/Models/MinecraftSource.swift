//
//  MinecraftSource.swift
//  World Manager for Minecraft
//
//  Created by John Burwell on 2026-05-25.
//

import Foundation

struct MinecraftSource: Identifiable, Hashable, Sendable {
    let id: URL
    let folderURL: URL
    var displayName: String
    var displayItems: [MinecraftContentItem]
    var rawItems: [MinecraftContentItem]
    var logicalPacks: [LogicalPack]
    var logicalWorlds: [LogicalWorld]
    var packInstances: [PackInstance]
    var worldPackRelationships: [WorldPackRelationship]
    var snapshot: SourceSnapshot?
    var isScanning: Bool
    var scanStatus: String
    var scanError: String?
    var indexedItemCount: Int
    var indexedDetailCount: Int
    var lastScanDate: Date?

    init(folderURL: URL) {
        let normalizedURL = folderURL.standardizedFileURL
        self.id = normalizedURL
        self.folderURL = normalizedURL
        self.displayName = normalizedURL.lastPathComponent
        self.displayItems = []
        self.rawItems = []
        self.logicalPacks = []
        self.logicalWorlds = []
        self.packInstances = []
        self.worldPackRelationships = []
        self.snapshot = nil
        self.isScanning = false
        self.scanStatus = ""
        self.scanError = nil
        self.indexedItemCount = 0
        self.indexedDetailCount = 0
        self.lastScanDate = nil
    }

    var itemCount: Int {
        displayItems.count
    }

    var items: [MinecraftContentItem] {
        displayItems
    }

    func rawItem(withID itemID: URL) -> MinecraftContentItem? {
        rawItems.first(where: { $0.id == itemID })
    }

    func logicalPack(forRepresentativeItemID itemID: URL) -> LogicalPack? {
        logicalPacks.first(where: { $0.representativeItemID == itemID })
    }

    func logicalWorld(forItemID itemID: URL) -> LogicalWorld? {
        logicalWorlds.first(where: { $0.itemID == itemID })
    }

    func packInstances(for logicalPackID: PackIdentity) -> [PackInstance] {
        packInstances.filter { $0.logicalPackID == logicalPackID }
    }

    func worldsUsingPack(_ logicalPackID: PackIdentity) -> [MinecraftContentItem] {
        worldPackRelationships
            .filter { $0.logicalPackID == logicalPackID }
            .compactMap { rawItem(withID: $0.worldItemID) }
            .uniqued(by: \.id)
            .sorted(by: WorldScanner.sortItems)
    }

    func resolvedPackReferences(for worldItemID: URL, type: MinecraftContentType) -> [ContentPackReference] {
        worldPackRelationships
            .filter { $0.worldItemID == worldItemID && $0.reference.type == type }
            .compactMap { relationship in
                if let logicalPackID = relationship.logicalPackID,
                   let logicalPack = logicalPacks.first(where: { $0.id == logicalPackID }),
                   let representativeItem = rawItem(withID: logicalPack.representativeItemID) {
                    return ContentPackReference(
                        name: logicalPack.displayName,
                        type: logicalPack.contentType,
                        iconURL: representativeItem.iconURL,
                        uuid: logicalPack.uuid,
                        version: logicalPack.version,
                        source: relationship.reference.source
                    )
                }

                return relationship.reference
            }
            .uniqued(by: \.id)
    }

    private func shouldIncludeAsStandalone(_ item: MinecraftContentItem) -> Bool {
        switch item.contentType {
        case .world, .behaviorPack, .resourcePack:
            return false
        case .skinPack, .worldTemplate:
            return true
        }
    }
}

private extension Array {
    func uniqued<Key: Hashable>(by keyPath: KeyPath<Element, Key>) -> [Element] {
        var seen = Set<Key>()
        var result: [Element] = []

        for element in self {
            let key = element[keyPath: keyPath]
            guard seen.insert(key).inserted else {
                continue
            }

            result.append(element)
        }

        return result
    }
}
