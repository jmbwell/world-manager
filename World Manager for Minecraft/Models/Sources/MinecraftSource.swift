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
    var origin: MinecraftSourceOrigin
    var accessDescriptor: SourceAccessDescriptor
    var availability: SourceAvailability
    var bookmarkData: Data?
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
    var scanDiagnostic: String?
    var scanProgress: Double?
    var indexedItemCount: Int
    var indexedDetailCount: Int
    var previewLoadedCount: Int
    var sizeLoadedCount: Int
    var previewStageElapsed: TimeInterval?
    var previewStageDuration: TimeInterval?
    var sizeStageElapsed: TimeInterval?
    var sizeStageDuration: TimeInterval?
    var lastScanDate: Date?

    nonisolated init(
        sourceID: URL? = nil,
        folderURL: URL,
        bookmarkData: Data? = nil,
        origin: MinecraftSourceOrigin? = nil,
        accessDescriptor: SourceAccessDescriptor? = nil,
        availability: SourceAvailability = .unknown
    ) {
        let normalizedFolderURL = normalizedSourceURL(folderURL)
        let resolvedOrigin = origin ?? .localFolder(bookmarkData: bookmarkData)
        self.id = normalizedSourceURL(sourceID ?? normalizedFolderURL)
        self.folderURL = normalizedFolderURL
        self.origin = resolvedOrigin
        self.accessDescriptor = accessDescriptor ?? SourceAccessDescriptor(
            accessorIdentifier: resolvedOrigin.defaultAccessorIdentifier,
            kind: resolvedOrigin.kind,
            refreshStrategy: resolvedOrigin.defaultRefreshStrategy
        )
        self.availability = availability
        self.bookmarkData = bookmarkData
        self.displayName = normalizedFolderURL.lastPathComponent
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
        self.scanDiagnostic = nil
        self.scanProgress = nil
        self.indexedItemCount = 0
        self.indexedDetailCount = 0
        self.previewLoadedCount = 0
        self.sizeLoadedCount = 0
        self.previewStageElapsed = nil
        self.previewStageDuration = nil
        self.sizeStageElapsed = nil
        self.sizeStageDuration = nil
        self.lastScanDate = nil
    }

    var itemCount: Int {
        displayItems.count
    }

    var hasCachedContent: Bool {
        !displayItems.isEmpty || !rawItems.isEmpty || snapshot != nil
    }

    var isOfflineCached: Bool {
        availability != .available && hasCachedContent
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
            .sorted(by: MinecraftContentItem.displaySort)
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

    var sourceRecord: SourceRecord {
        SourceRecord(
            id: id,
            displayName: displayName,
            rootURL: folderURL,
            origin: origin,
            accessDescriptor: accessDescriptor,
            availability: availability,
            lastRefreshDate: lastScanDate
        )
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

nonisolated private func normalizedSourceURL(_ url: URL) -> URL {
    if url.isFileURL {
        return url.standardizedFileURL
    }

    return url.standardized
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
