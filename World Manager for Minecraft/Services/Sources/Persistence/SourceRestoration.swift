//
//  SourceRestoration.swift
//  World Manager for Minecraft
//
//  Created by OpenAI Codex on 2026-05-28.
//

import Foundation

enum SourceRestoration {
    static func restoredSource(
        from record: PersistedSourceRecord,
        connectedDeviceDisplayName: (ConnectedDevice, DeviceAppContainer) -> String
    ) -> MinecraftSource {
        var source = MinecraftSource(
            sourceID: record.sourceID,
            folderURL: record.folderURL,
            bookmarkData: record.bookmarkData,
            origin: record.origin,
            accessDescriptor: record.accessDescriptor,
            availability: record.availability
        )

        if case .connectedDevice(let device, let container) = source.origin {
            var repairedDevice = device
            repairedDevice.name = ConnectedDeviceSourcePolicy.preferredDeviceName(
                currentName: device.name,
                fallbackDeviceName: "",
                fallbackDisplayName: record.displayName
            )
            source.origin = .connectedDevice(device: repairedDevice, container: container)

            let persistedDeviceName = record.displayName.components(separatedBy: " • ").first ?? record.displayName
            if ConnectedDeviceSourcePolicy.sanitizedDeviceName(persistedDeviceName) == nil {
                source.displayName = connectedDeviceDisplayName(repairedDevice, container)
            } else {
                source.displayName = record.displayName
            }
        } else {
            source.displayName = record.displayName
        }

        applyRestoredItemState(
            record.rawItems,
            lastScanDate: record.lastScanDate,
            snapshot: record.snapshot,
            to: &source
        )
        source.scanStatus = restoredStatus(for: source)
        return source
    }

    static func applyRestoredItemState(
        _ items: [MinecraftContentItem],
        lastScanDate: Date?,
        snapshot: SourceSnapshot?,
        to source: inout MinecraftSource
    ) {
        source.rawItems = items
        source.indexedItemCount = items.count
        source.indexedDetailCount = items.filter(\.metadataLoaded).count
        source.previewLoadedCount = items.filter(\.previewLoaded).count
        source.sizeLoadedCount = items.filter(\.sizeLoaded).count
        source.lastScanDate = lastScanDate
        source.snapshot = snapshot
    }

    static func restoreCachedImages(in items: [MinecraftContentItem]) async -> [MinecraftContentItem] {
        var restoredItems: [MinecraftContentItem] = []
        restoredItems.reserveCapacity(items.count)

        for var item in items {
            item.iconURL = await ImageCacheStore.shared.cachedImageURL(for: item.iconURL)
            item.packReferences = await restoreCachedImages(in: item.packReferences)
            restoredItems.append(item)
        }

        return restoredItems
    }

    static func restoreCachedImages(in references: [ContentPackReference]) async -> [ContentPackReference] {
        var restoredReferences: [ContentPackReference] = []
        restoredReferences.reserveCapacity(references.count)

        for reference in references {
            let cachedIconURL = await ImageCacheStore.shared.cachedImageURL(for: reference.iconURL)
            restoredReferences.append(
                ContentPackReference(
                    name: reference.name,
                    type: reference.type,
                    iconURL: cachedIconURL,
                    uuid: reference.uuid,
                    version: reference.version,
                    source: reference.source
                )
            )
        }

        return restoredReferences
    }

    static func startupRefreshReason(
        for source: MinecraftSource,
        persistedRecord: PersistedSourceRecord?,
        currentCollectionSnapshots: (URL) -> [CollectionSnapshot]
    ) -> String? {
        guard source.availability == .available else {
            return nil
        }

        switch source.origin.kind {
        case .localFolder:
            guard let persistedRecord else {
                return nil
            }

            if needsRescan(persistedRecord, currentCollectionSnapshots: currentCollectionSnapshots)
                || reconcileIsNeeded(source, currentCollectionSnapshots: currentCollectionSnapshots) {
                return defaultRefreshReason(for: source)
            }

            return nil
        case .connectedDevice:
            guard source.rawItems.isEmpty || source.lastScanDate == nil else {
                return nil
            }

            return defaultRefreshReason(for: source)
        }
    }

    static func needsReconcile(
        _ source: MinecraftSource,
        currentCollectionSnapshots: (URL) -> [CollectionSnapshot]
    ) -> Bool {
        reconcileIsNeeded(source, currentCollectionSnapshots: currentCollectionSnapshots)
    }

    private static func restoredStatus(for source: MinecraftSource) -> String {
        source.indexedItemCount == 0
            ? "No Minecraft items found."
            : "Loaded \(source.indexedDetailCount) items."
    }

    private static func defaultRefreshReason(for source: MinecraftSource) -> String {
        source.hasCachedContent
            ? "Refreshing cached library..."
            : "Scanning Minecraft library..."
    }

    private static func needsRescan(
        _ record: PersistedSourceRecord,
        currentCollectionSnapshots: (URL) -> [CollectionSnapshot]
    ) -> Bool {
        guard record.accessDescriptor.refreshStrategy == .eagerFullScan else {
            return record.rawItems.isEmpty
        }

        guard let snapshot = record.snapshot else {
            return true
        }

        let sourceURL = record.folderURL
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return true
        }

        return collectionsDiffer(
            currentCollectionSnapshots(sourceURL),
            persistedCollections: snapshot.collectionSnapshots
        )
    }

    private static func reconcileIsNeeded(
        _ source: MinecraftSource,
        currentCollectionSnapshots: (URL) -> [CollectionSnapshot]
    ) -> Bool {
        guard source.accessDescriptor.refreshStrategy == .eagerFullScan else {
            return source.rawItems.isEmpty
        }

        guard let snapshot = source.snapshot else {
            return true
        }

        let sourceURL = source.folderURL
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return false
        }

        return collectionsDiffer(
            currentCollectionSnapshots(sourceURL),
            persistedCollections: snapshot.collectionSnapshots
        )
    }

    private static func collectionsDiffer(
        _ currentCollections: [CollectionSnapshot],
        persistedCollections: [CollectionSnapshot]
    ) -> Bool {
        let currentCollectionsByName = Dictionary(
            uniqueKeysWithValues: currentCollections.map { ($0.folderName, $0) }
        )
        let persistedCollectionsByName = Dictionary(
            uniqueKeysWithValues: persistedCollections.map { ($0.folderName, $0) }
        )

        if currentCollectionsByName.count != persistedCollectionsByName.count {
            return true
        }

        for (folderName, persistedCollection) in persistedCollectionsByName {
            guard let currentCollection = currentCollectionsByName[folderName],
                  currentCollection.fingerprint == persistedCollection.fingerprint else {
                return true
            }
        }

        return false
    }
}
