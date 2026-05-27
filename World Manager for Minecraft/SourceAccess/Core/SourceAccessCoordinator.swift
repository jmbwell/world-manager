//
//  SourceAccessCoordinator.swift
//  World Manager for Minecraft
//
//  Created by OpenAI on 2026-05-26.
//

import Foundation

protocol SourceAccessMethod: Sendable {
    nonisolated var accessorIdentifier: SourceAccessorIdentifier { get }
    nonisolated func accessDescriptor(for source: MinecraftSource) -> SourceAccessDescriptor
    nonisolated func availability(for source: MinecraftSource) async -> SourceAvailability
    nonisolated func discoverItems(
        for source: MinecraftSource,
        onDiscovered: @escaping @Sendable (MinecraftContentItem) -> Void
    ) async throws -> [MinecraftContentItem]
    nonisolated func enrich(_ item: MinecraftContentItem, for source: MinecraftSource) async -> MinecraftContentItem
    nonisolated func loadSize(for item: MinecraftContentItem, in source: MinecraftSource) async -> MinecraftContentItem
    nonisolated func listItemContents(for item: MinecraftContentItem, in source: MinecraftSource) async throws -> [DirectoryPreviewEntry]
    nonisolated func materializeItem(for item: MinecraftContentItem, in source: MinecraftSource) async throws -> URL
    nonisolated func purgeCachedArtifacts(for source: MinecraftSource) async
}

extension SourceAccessMethod {
    nonisolated var accessorIdentifier: SourceAccessorIdentifier {
        String(reflecting: Self.self)
    }

    nonisolated func accessDescriptor(for source: MinecraftSource) -> SourceAccessDescriptor {
        SourceAccessDescriptor(
            accessorIdentifier: accessorIdentifier,
            kind: source.origin.kind,
            capabilities: source.origin.defaultCapabilities,
            refreshStrategy: source.origin.defaultRefreshStrategy
        )
    }

    nonisolated func availability(for source: MinecraftSource) async -> SourceAvailability {
        _ = source
        return .unknown
    }

    nonisolated func discoverItems(
        for source: MinecraftSource,
        onDiscovered: @escaping @Sendable (MinecraftContentItem) -> Void
    ) async throws -> [MinecraftContentItem] {
        _ = source
        _ = onDiscovered
        return []
    }

    nonisolated func enrich(_ item: MinecraftContentItem, for source: MinecraftSource) async -> MinecraftContentItem {
        _ = source
        return item
    }

    nonisolated func loadSize(for item: MinecraftContentItem, in source: MinecraftSource) async -> MinecraftContentItem {
        _ = source
        return item
    }

    nonisolated func listItemContents(for item: MinecraftContentItem, in source: MinecraftSource) async throws -> [DirectoryPreviewEntry] {
        _ = source
        _ = item
        return []
    }

    nonisolated func materializeItem(for item: MinecraftContentItem, in source: MinecraftSource) async throws -> URL {
        _ = source
        return item.folderURL
    }

    nonisolated func purgeCachedArtifacts(for source: MinecraftSource) async {
        _ = source
    }
}

protocol ConnectedDeviceSourceAccessMethod: SourceAccessMethod {
    nonisolated func listConnectedDevices() async throws -> [ConnectedDevice]
    nonisolated func listAccessibleContainers(for device: ConnectedDevice) async throws -> [DeviceAppContainer]
}

struct SourceAccessCoordinator: SourceAccessMethod {
    private let accessMethodsByIdentifier: [SourceAccessorIdentifier: any SourceAccessMethod]

    nonisolated init(
        localFolderAccess: SourceAccessMethod = LocalFolderSourceAccess(),
        connectedDeviceAccess: ConnectedDeviceSourceAccessMethod
    ) {
        self.init(accessMethods: [localFolderAccess, connectedDeviceAccess])
    }

    nonisolated init(accessMethods: [any SourceAccessMethod]) {
        var accessMethodsByIdentifier: [SourceAccessorIdentifier: any SourceAccessMethod] = [:]
        for accessMethod in accessMethods {
            accessMethodsByIdentifier[accessMethod.accessorIdentifier] = accessMethod
        }
        self.accessMethodsByIdentifier = accessMethodsByIdentifier
    }

    nonisolated private func accessMethod(for source: MinecraftSource) -> (any SourceAccessMethod) {
        if let accessMethod = accessMethodsByIdentifier[source.accessDescriptor.accessorIdentifier] {
            return accessMethod
        }

        if let accessMethod = accessMethodsByIdentifier[source.origin.defaultAccessorIdentifier] {
            return accessMethod
        }

        if let accessMethod = accessMethodsByIdentifier[LocalFolderSourceAccess().accessorIdentifier] {
            return accessMethod
        }

        fatalError("No source access method is registered for \(source.accessDescriptor.accessorIdentifier).")
    }

    nonisolated func discoverItems(
        for source: MinecraftSource,
        onDiscovered: @escaping @Sendable (MinecraftContentItem) -> Void
    ) async throws -> [MinecraftContentItem] {
        return try await accessMethod(for: source).discoverItems(for: source, onDiscovered: onDiscovered)
    }

    nonisolated func accessDescriptor(for source: MinecraftSource) -> SourceAccessDescriptor {
        accessMethod(for: source).accessDescriptor(for: source)
    }

    nonisolated func availability(for source: MinecraftSource) async -> SourceAvailability {
        return await accessMethod(for: source).availability(for: source)
    }

    nonisolated func enrich(_ item: MinecraftContentItem, for source: MinecraftSource) async -> MinecraftContentItem {
        return await accessMethod(for: source).enrich(item, for: source)
    }

    nonisolated func loadSize(for item: MinecraftContentItem, in source: MinecraftSource) async -> MinecraftContentItem {
        return await accessMethod(for: source).loadSize(for: item, in: source)
    }

    nonisolated func listItemContents(for item: MinecraftContentItem, in source: MinecraftSource) async throws -> [DirectoryPreviewEntry] {
        return try await accessMethod(for: source).listItemContents(for: item, in: source)
    }

    nonisolated func materializeItem(for item: MinecraftContentItem, in source: MinecraftSource) async throws -> URL {
        return try await accessMethod(for: source).materializeItem(for: item, in: source)
    }

    nonisolated func purgeCachedArtifacts(for source: MinecraftSource) async {
        await accessMethod(for: source).purgeCachedArtifacts(for: source)
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
