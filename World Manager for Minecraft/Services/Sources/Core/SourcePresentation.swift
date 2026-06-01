// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

enum SourceScanPhase {
    case discovering
    case metadata
    case previews
    case sizing
    case completed
    case idle
}

enum SourcePresentation {
    nonisolated static func availabilityDisplayText(for source: MinecraftSource) -> String {
        switch source.availability {
        case .available:
            return "Available"
        case .unknown:
            return "Checking availability"
        case .disconnected:
            return source.origin.kind == .connectedDevice ? "Device offline" : "Folder offline"
        case .limited:
            return source.origin.kind == .connectedDevice ? "Device access limited" : "Limited access"
        case .unavailable:
            return source.origin.kind == .connectedDevice ? "Device unavailable" : "Folder unavailable"
        }
    }

    nonisolated static func cachedAvailabilityDetailText(for source: MinecraftSource) -> String? {
        let hasCachedContent = !source.displayItems.isEmpty || !source.rawItems.isEmpty || source.snapshot != nil
        guard source.availability != .available && hasCachedContent else {
            return nil
        }

        switch source.availability {
        case .disconnected:
            return source.origin.kind == .connectedDevice
                ? "Showing cached results until this device reconnects."
                : "Showing cached results until this folder becomes reachable again."
        case .limited:
            return source.origin.kind == .connectedDevice
                ? "Showing cached results until the device is unlocked and trusted."
                : "Showing cached results until full access is restored."
        case .unavailable, .unknown:
            return "Showing cached results while the source is unavailable."
        case .available:
            return nil
        }
    }

    nonisolated static func scanPhase(for source: MinecraftSource) -> SourceScanPhase {
        guard source.isScanning else {
            if source.scanStatus.hasPrefix("Loaded ") || source.scanStatus == "No Minecraft items found." {
                return .completed
            }
            return .idle
        }

        if source.sizeLoadedCount > 0 {
            return .sizing
        }

        if source.previewLoadedCount > 0 {
            return .previews
        }

        if let scanProgress = source.scanProgress {
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

        if source.scanStatus.contains("Calculating sizes") {
            return .sizing
        }
        if source.scanStatus.contains("Loading previews") {
            return .previews
        }
        if source.scanStatus.contains("metadata") {
            return .metadata
        }

        return .discovering
    }

    nonisolated static func liveScanStatusTitle(for source: MinecraftSource) -> String {
        guard source.isScanning else {
            return source.scanStatus
        }

        if source.indexedItemCount == 0 {
            return "Scanning Minecraft library..."
        }

        let discoveryIsComplete = (source.scanProgress ?? 0) >= 0.65

        if !discoveryIsComplete {
            return "Discovering items..."
        }

        if source.indexedItemCount > 0,
           source.previewLoadedCount >= source.indexedItemCount,
           source.sizeLoadedCount == 0 {
            return "Preparing size calculations..."
        }

        if source.scanStatus == "Preparing previews..." || source.scanStatus == "Preparing size calculations..." {
            return source.scanStatus
        }

        switch scanPhase(for: source) {
        case .discovering, .metadata, .previews:
            return "Loading previews for \(source.previewLoadedCount) of \(source.indexedItemCount) items..."
        case .sizing:
            return "Calculating sizes for \(source.sizeLoadedCount) of \(source.indexedItemCount) items..."
        case .completed:
            return source.indexedItemCount == 0 ? "No Minecraft items found." : "Loaded \(source.indexedDetailCount) items."
        case .idle:
            return source.scanStatus
        }
    }

    nonisolated static func showsIndeterminateScanActivityIndicator(for source: MinecraftSource) -> Bool {
        guard source.isScanning else {
            return false
        }

        let discoveryIsComplete = (source.scanProgress ?? 0) >= 0.65
        if !discoveryIsComplete {
            return true
        }

        if source.indexedItemCount > 0,
           source.previewLoadedCount >= source.indexedItemCount,
           source.sizeLoadedCount == 0 {
            return true
        }

        return source.scanStatus == "Preparing previews..." || source.scanStatus == "Preparing size calculations..."
    }
}
