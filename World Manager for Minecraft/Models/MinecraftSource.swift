//
//  MinecraftSource.swift
//  World Manager for Minecraft
//
//  Created by John Burwell on 2026-05-25.
//

import Foundation

enum SourceScanPhase {
    case discovering
    case metadata
    case previews
    case sizing
    case completed
    case idle
}

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
            capabilities: resolvedOrigin.defaultCapabilities,
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

    var availabilityDisplayText: String {
        switch availability {
        case .available:
            return "Available"
        case .unknown:
            return "Checking availability"
        case .disconnected:
            return origin.kind == .connectedDevice ? "Device offline" : "Folder offline"
        case .limited:
            return origin.kind == .connectedDevice ? "Device access limited" : "Limited access"
        case .unavailable:
            return origin.kind == .connectedDevice ? "Device unavailable" : "Folder unavailable"
        }
    }

    var cachedAvailabilityDetailText: String? {
        guard isOfflineCached else {
            return nil
        }

        switch availability {
        case .disconnected:
            return origin.kind == .connectedDevice
                ? "Showing cached results until this device reconnects."
                : "Showing cached results until this folder becomes reachable again."
        case .limited:
            return origin.kind == .connectedDevice
                ? "Showing cached results until the device is unlocked and trusted."
                : "Showing cached results until full access is restored."
        case .unavailable, .unknown:
            return "Showing cached results while the source is unavailable."
        case .available:
            return nil
        }
    }

    var items: [MinecraftContentItem] {
        displayItems
    }

    var scanPhase: SourceScanPhase {
        guard isScanning else {
            if scanStatus.hasPrefix("Loaded ") || scanStatus == "No Minecraft items found." {
                return .completed
            }
            return .idle
        }

        if sizeLoadedCount > 0 {
            return .sizing
        }

        if previewLoadedCount > 0 {
            return .previews
        }

        if let scanProgress {
            if scanProgress >= 0.75 {
                return .sizing
            }
            if scanProgress >= 0.65 {
                return .previews
            }
            if scanProgress >= 0.1 {
                return .metadata
            }
        }

        if scanStatus.contains("Calculating sizes") {
            return .sizing
        }
        if scanStatus.contains("Loading previews") {
            return .previews
        }
        if scanStatus.contains("metadata") {
            return .metadata
        }

        return .discovering
    }

    var liveScanStatusTitle: String {
        guard isScanning else {
            return scanStatus
        }

        if indexedItemCount == 0 {
            return "Scanning Minecraft library..."
        }

        let discoveryIsComplete = (scanProgress ?? 0) >= 0.65

        if !discoveryIsComplete {
            return "Discovering items..."
        }

        if indexedItemCount > 0, previewLoadedCount >= indexedItemCount, sizeLoadedCount == 0 {
            return "Preparing size calculations..."
        }

        if scanStatus == "Preparing previews..." || scanStatus == "Preparing size calculations..." {
            return scanStatus
        }

        switch scanPhase {
        case .discovering, .metadata, .previews:
            return "Loading previews for \(previewLoadedCount) of \(indexedItemCount) items..."
        case .sizing:
            return "Calculating sizes for \(sizeLoadedCount) of \(indexedItemCount) items..."
        case .completed:
            return indexedItemCount == 0 ? "No Minecraft items found." : "Loaded \(indexedDetailCount) items."
        case .idle:
            return scanStatus
        }
    }

    var showsIndeterminateScanActivityIndicator: Bool {
        guard isScanning else {
            return false
        }

        let discoveryIsComplete = (scanProgress ?? 0) >= 0.65
        if !discoveryIsComplete {
            return true
        }

        if indexedItemCount > 0, previewLoadedCount >= indexedItemCount, sizeLoadedCount == 0 {
            return true
        }

        return scanStatus == "Preparing previews..." || scanStatus == "Preparing size calculations..."
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
