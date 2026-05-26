//
//  SourceAccessCoordinator.swift
//  World Manager for Minecraft
//
//  Created by OpenAI on 2026-05-26.
//

import Foundation

protocol SourceAccessMethod: Sendable {
    nonisolated func prepareScanRoot(for source: MinecraftSource) async throws -> PreparedScanRoot
    nonisolated func releaseScanRoot(_ preparedScanRoot: PreparedScanRoot) async
}

extension SourceAccessMethod {
    nonisolated func releaseScanRoot(_ preparedScanRoot: PreparedScanRoot) async {
        _ = preparedScanRoot
    }
}

protocol ConnectedDeviceSourceAccessMethod: SourceAccessMethod {
    nonisolated func listConnectedDevices() async throws -> [ConnectedDevice]
    nonisolated func listAccessibleContainers(for device: ConnectedDevice) async throws -> [DeviceAppContainer]
}

struct SourceAccessCoordinator: SourceAccessMethod {
    private let localFolderAccess: SourceAccessMethod
    private let connectedDeviceAccess: ConnectedDeviceSourceAccessMethod

    nonisolated init(
        localFolderAccess: SourceAccessMethod = LocalFolderSourceAccess(),
        connectedDeviceAccess: ConnectedDeviceSourceAccessMethod
    ) {
        self.localFolderAccess = localFolderAccess
        self.connectedDeviceAccess = connectedDeviceAccess
    }

    nonisolated func prepareScanRoot(for source: MinecraftSource) async throws -> PreparedScanRoot {
        switch source.origin {
        case .localFolder:
            return try await localFolderAccess.prepareScanRoot(for: source)
        case .connectedDevice:
            return try await connectedDeviceAccess.prepareScanRoot(for: source)
        }
    }

    nonisolated func releaseScanRoot(_ preparedScanRoot: PreparedScanRoot) async {
        await localFolderAccess.releaseScanRoot(preparedScanRoot)
        await connectedDeviceAccess.releaseScanRoot(preparedScanRoot)
    }
}

enum SourceAccessError: LocalizedError, Sendable {
    case deviceUnavailable
    case deviceNotTrusted
    case appNotAccessible(appID: String)
    case minecraftFolderMissing(appID: String)
    case accessFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable:
            return "The selected device is no longer available."
        case .deviceNotTrusted:
            return "The device must be unlocked and trusted before its files can be accessed."
        case .appNotAccessible(let appID):
            return "The app container for \(appID) is not accessible on this device."
        case .minecraftFolderMissing(let appID):
            return "Minecraft resources were not found in the accessible container for \(appID)."
        case .accessFailed(let reason):
            return reason
        }
    }
}
