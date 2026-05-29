//
//  SourceScanning.swift
//  World Manager for Minecraft
//
//  Created by OpenAI on 2026-05-28.
//

import Foundation

enum SourceScanPolicy {
    static func initialStatus(for source: MinecraftSource, mode: SourceDiscoveryMode) -> String {
        switch (source.origin, mode) {
        case (.localFolder, .fullScan):
            return "Preparing folder scan..."
        case (.localFolder, .reconcile):
            return "Preparing cached library refresh..."
        case (.connectedDevice, .fullScan):
            return "Connecting to device and discovering Minecraft items..."
        case (.connectedDevice, .reconcile):
            return "Connecting to device and refreshing cached library..."
        }
    }

    static func scanningLibraryStatus(for source: MinecraftSource, mode: SourceDiscoveryMode) -> String {
        switch (source.origin, mode) {
        case (.localFolder, .fullScan):
            return "Scanning Minecraft library..."
        case (.localFolder, .reconcile):
            return "Reconciling cached library..."
        case (.connectedDevice, .fullScan):
            return "Scanning Minecraft library on device..."
        case (.connectedDevice, .reconcile):
            return "Reconciling cached device library..."
        }
    }

    static func performanceContext(for source: MinecraftSource) -> String {
        switch source.origin {
        case .localFolder:
            return "source=\(source.displayName) kind=local"
        case .connectedDevice(let device, let container):
            let transport = device.connection == .usb ? "usb" : "network"
            return "source=\(source.displayName) kind=connected-device transport=\(transport) udid=\(device.udid) app=\(container.appID)"
        }
    }

    static func friendlyError(for error: Error, source: MinecraftSource) -> String {
        let description = error.localizedDescription

        guard source.origin.kind == .connectedDevice else {
            return "Failed to scan folder: \(description)"
        }

        if description.contains("AMDeviceCreateHouseArrestService returned -402653093")
            || description.contains("kAMDServiceLimitError") {
            return "Device is busy. Too many device access sessions were open, so the scan could not start."
        }

        if description.localizedCaseInsensitiveContains("InstallationLookupFailed") {
            return "The device refused access to the Minecraft app container."
        }

        if description.localizedCaseInsensitiveContains("not paired") {
            return "The device is not paired with this Mac."
        }

        if description.localizedCaseInsensitiveContains("no longer available") {
            return "The device disconnected during the scan."
        }

        return "Failed to scan device library."
    }

    static func availabilityStatus(
        for error: Error,
        defaultingTo currentAvailability: SourceAvailability
    ) -> SourceAvailability {
        if let accessError = error as? SourceAccessError {
            switch accessError {
            case .deviceUnavailable:
                return .disconnected
            case .deviceNotTrusted:
                return .limited
            case .appNotAccessible, .minecraftFolderMissing, .accessFailed:
                return .unavailable
            }
        }

        return currentAvailability
    }

    static func shouldReuseCachedItem(
        _ cachedItem: MinecraftContentItem,
        forDiscoveredItem discoveredItem: MinecraftContentItem,
        source: MinecraftSource,
        previousSnapshot: ItemSnapshot?
    ) -> Bool {
        guard cachedItem.contentType == discoveredItem.contentType else {
            return false
        }

        guard cachedItem.metadataLoaded, cachedItem.previewLoaded, cachedItem.sizeLoaded else {
            return false
        }

        switch source.origin.kind {
        case .localFolder:
            guard let previousSnapshot else {
                return false
            }

            let currentModifiedDate = try? discoveredItem.folderURL
                .resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            return previousSnapshot.modifiedDate == currentModifiedDate
        case .connectedDevice:
            return cachedItem.folderName == discoveredItem.folderName
                && cachedItem.displayName == discoveredItem.displayName
                && cachedItem.hasKnownIcon == discoveredItem.hasKnownIcon
                && cachedItem.packUUID == discoveredItem.packUUID
                && cachedItem.packVersion == discoveredItem.packVersion
                && cachedItem.packMetadataDetails == discoveredItem.packMetadataDetails
                && cachedItem.packReferences == discoveredItem.packReferences
        }
    }

    static func buildSnapshot(for source: MinecraftSource, scanRootURL: URL) -> SourceSnapshot {
        let collectionSnapshots = WorldScanner.collectionSnapshots(in: scanRootURL)

        let itemSnapshots = source.rawItems.map { item in
            ItemSnapshot(
                id: item.id,
                relativePath: item.folderURL.path.replacingOccurrences(of: scanRootURL.path + "/", with: ""),
                modifiedDate: item.modifiedDate,
                sizeBytes: item.sizeBytes,
                packUUID: nil,
                packVersion: nil
            )
        }.sorted { lhs, rhs in
            lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
        }

        let rootModifiedDate = try? scanRootURL
            .resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate

        return SourceSnapshot(
            sourceID: source.id,
            rootModifiedDate: rootModifiedDate,
            collectionSnapshots: collectionSnapshots,
            itemSnapshots: itemSnapshots
        )
    }
}

enum SourceScanRecovery {
    static func restoreIndexedState(from previousSource: MinecraftSource, into source: inout MinecraftSource) {
        source.displayItems = previousSource.displayItems
        source.rawItems = previousSource.rawItems
        source.logicalPacks = previousSource.logicalPacks
        source.logicalWorlds = previousSource.logicalWorlds
        source.packInstances = previousSource.packInstances
        source.worldPackRelationships = previousSource.worldPackRelationships
        source.snapshot = previousSource.snapshot
        source.indexedItemCount = previousSource.indexedItemCount
        source.indexedDetailCount = previousSource.indexedDetailCount
        source.previewLoadedCount = previousSource.previewLoadedCount
        source.sizeLoadedCount = previousSource.sizeLoadedCount
        source.scanProgress = previousSource.scanProgress
        source.lastScanDate = previousSource.lastScanDate
    }

    static func shouldPreservePartialResults(
        currentSource: MinecraftSource,
        previousSource: MinecraftSource
    ) -> Bool {
        if currentSource.rawItems.count > previousSource.rawItems.count {
            return true
        }

        if currentSource.indexedDetailCount > previousSource.indexedDetailCount {
            return true
        }

        if currentSource.previewLoadedCount > previousSource.previewLoadedCount {
            return true
        }

        if currentSource.sizeLoadedCount > previousSource.sizeLoadedCount {
            return true
        }

        return false
    }
}
