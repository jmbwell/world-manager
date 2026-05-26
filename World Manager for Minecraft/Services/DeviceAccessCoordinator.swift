//
//  DeviceAccessCoordinator.swift
//  World Manager for Minecraft
//
//  Created by OpenAI on 2026-05-26.
//

import Foundation

protocol SourceScanRootPreparing: Sendable {
    nonisolated func prepareScanRoot(for source: MinecraftSource) async throws -> PreparedScanRoot
}

protocol DeviceDiscoveryServing: Sendable {
    nonisolated func listConnectedDevices() async throws -> [ConnectedDevice]
    nonisolated func listAccessibleContainers(for device: ConnectedDevice) async throws -> [DeviceAppContainer]
}

protocol DeviceMountServing: Sendable {
    nonisolated func prepareScanRoot(
        for source: MinecraftSource,
        preferredSubpath: String?
    ) async throws -> PreparedScanRoot
}

struct LocalFolderScanRootPreparer: SourceScanRootPreparing {
    nonisolated init() {}

    nonisolated func prepareScanRoot(for source: MinecraftSource) async throws -> PreparedScanRoot {
        guard case .localFolder(let bookmarkData) = source.origin else {
            throw DeviceAccessError.mountFailed(
                reason: "No scan-root preparer is configured for this source type."
            )
        }

        let resolvedURL: URL
        if let bookmarkData {
            var isStale = false
            guard let bookmarkURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                throw DeviceAccessError.mountFailed(
                    reason: "The saved folder bookmark could not be resolved."
                )
            }

            resolvedURL = bookmarkURL.standardizedFileURL
        } else {
            resolvedURL = source.folderURL
        }

        return PreparedScanRoot(
            sourceID: source.id,
            rootURL: resolvedURL,
            cleanupBehavior: .none
        )
    }
}

enum DeviceAccessError: LocalizedError, Sendable {
    case toolingUnavailable
    case deviceUnavailable
    case deviceNotTrusted
    case appNotAccessible(appID: String)
    case minecraftFolderMissing(appID: String)
    case mountFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .toolingUnavailable:
            return "Required device-access tooling is unavailable."
        case .deviceUnavailable:
            return "The selected device is no longer available."
        case .deviceNotTrusted:
            return "The device must be unlocked and trusted before its files can be accessed."
        case .appNotAccessible(let appID):
            return "The app container for \(appID) is not accessible on this device."
        case .minecraftFolderMissing(let appID):
            return "Minecraft resources were not found in the accessible container for \(appID)."
        case .mountFailed(let reason):
            return reason
        }
    }
}
