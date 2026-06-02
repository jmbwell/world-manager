// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

enum SourceDiscoveryMode: Sendable {
    case fullScan
    case reconcile
}

protocol SourceAccessMethod: Sendable {
    nonisolated var accessorIdentifier: SourceAccessorIdentifier { get }
    nonisolated func probeLocalFolder(_ url: URL) async -> SourceProbeResult?
    nonisolated func discoverSourceCandidates() -> AsyncThrowingStream<SourceCandidateEvent, Error>
    nonisolated func accessDescriptor(for source: MinecraftSource) -> SourceAccessDescriptor
    nonisolated func accessStatus(for source: MinecraftSource) async -> SourceAccessStatus
    nonisolated func availability(for source: MinecraftSource) async -> SourceAvailability
    nonisolated func capabilities(for source: MinecraftSource) async -> SourceCapabilities
    nonisolated func discoverItems(
        for source: MinecraftSource,
        mode: SourceDiscoveryMode,
        onDiscovered: @escaping @Sendable (MinecraftContentItem) -> Void
    ) async throws
    nonisolated func scanEvents(
        for source: MinecraftSource,
        mode: SourceDiscoveryMode
    ) -> AsyncThrowingStream<ProviderEvent, Error>
    nonisolated func enrich(_ item: MinecraftContentItem, for source: MinecraftSource) async -> MinecraftContentItem
    nonisolated func loadPreviewAssets(for item: MinecraftContentItem, in source: MinecraftSource) async -> MinecraftContentItem
    nonisolated func loadPreviewAssets(for items: [MinecraftContentItem], in source: MinecraftSource) async -> [MinecraftContentItem]
    nonisolated func loadSize(for item: MinecraftContentItem, in source: MinecraftSource) async -> MinecraftContentItem
    nonisolated func loadSizeAssets(for items: [MinecraftContentItem], in source: MinecraftSource) async -> [MinecraftContentItem]
    nonisolated func listItemContents(for item: MinecraftContentItem, in source: MinecraftSource) async throws -> [DirectoryEntry]
    nonisolated func materializeItem(for item: MinecraftContentItem, in source: MinecraftSource) async throws -> URL
    nonisolated func purgeCachedArtifacts(for source: MinecraftSource) async
}

extension SourceAccessMethod {
    nonisolated var accessorIdentifier: SourceAccessorIdentifier {
        String(reflecting: Self.self)
    }

    nonisolated func probeLocalFolder(_ url: URL) async -> SourceProbeResult? {
        _ = url
        return nil
    }

    nonisolated func discoverSourceCandidates() -> AsyncThrowingStream<SourceCandidateEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    nonisolated func accessDescriptor(for source: MinecraftSource) -> SourceAccessDescriptor {
        SourceAccessDescriptor(
            accessorIdentifier: accessorIdentifier,
            kind: source.origin.kind,
            refreshStrategy: source.origin.defaultRefreshStrategy
        )
    }

    nonisolated func availability(for source: MinecraftSource) async -> SourceAvailability {
        await accessStatus(for: source).availability
    }

    nonisolated func accessStatus(for source: MinecraftSource) async -> SourceAccessStatus {
        var status = source.origin.defaultAccessStatus(displayName: source.displayName)
        status.availability = .unknown
        return status
    }

    nonisolated func capabilities(for source: MinecraftSource) async -> SourceCapabilities {
        source.origin.defaultCapabilities
    }

    nonisolated func discoverItems(
        for source: MinecraftSource,
        mode: SourceDiscoveryMode,
        onDiscovered: @escaping @Sendable (MinecraftContentItem) -> Void
    ) async throws {
        _ = source
        _ = mode
        _ = onDiscovered
    }

    nonisolated func scanEvents(
        for source: MinecraftSource,
        mode: SourceDiscoveryMode
    ) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                let accessStatus = await accessStatus(for: source)
                continuation.yield(.accessStatusChanged(accessStatus))
                continuation.yield(
                    .stageUpdated(
                        WorkStage(
                            id: "discovery",
                            title: "Discovering content",
                            detail: nil,
                            state: .running,
                            progress: .indeterminate
                        )
                    )
                )

                do {
                    try await discoverItems(for: source, mode: mode) { item in
                        continuation.yield(.discovered(item))
                    }
                    continuation.yield(
                        .stageUpdated(
                            WorkStage(
                                id: "discovery",
                                title: "Discovering content",
                                detail: nil,
                                state: .succeeded,
                                progress: .indeterminate
                            )
                        )
                    )
                    continuation.finish()
                } catch {
                    continuation.yield(
                        .stageUpdated(
                            WorkStage(
                                id: "discovery",
                                title: "Discovering content",
                                detail: error.localizedDescription,
                                state: .failed,
                                progress: .indeterminate
                            )
                        )
                    )
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    nonisolated func enrich(_ item: MinecraftContentItem, for source: MinecraftSource) async -> MinecraftContentItem {
        _ = source
        return item
    }

    nonisolated func loadPreviewAssets(for item: MinecraftContentItem, in source: MinecraftSource) async -> MinecraftContentItem {
        _ = source
        return item
    }

    nonisolated func loadPreviewAssets(for items: [MinecraftContentItem], in source: MinecraftSource) async -> [MinecraftContentItem] {
        var previewItems: [MinecraftContentItem] = []
        previewItems.reserveCapacity(items.count)

        for item in items {
            previewItems.append(await loadPreviewAssets(for: item, in: source))
        }

        return previewItems
    }

    nonisolated func loadSize(for item: MinecraftContentItem, in source: MinecraftSource) async -> MinecraftContentItem {
        _ = source
        return item
    }

    nonisolated func loadSizeAssets(for items: [MinecraftContentItem], in source: MinecraftSource) async -> [MinecraftContentItem] {
        var sizedItems: [MinecraftContentItem] = []
        sizedItems.reserveCapacity(items.count)

        for item in items {
            sizedItems.append(await loadSize(for: item, in: source))
        }

        return sizedItems
    }

    nonisolated func listItemContents(for item: MinecraftContentItem, in source: MinecraftSource) async throws -> [DirectoryEntry] {
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
        javaLocalFolderAccess: SourceAccessMethod = JavaLocalFolderSourceAccess(),
        connectedDeviceAccess: ConnectedDeviceSourceAccessMethod
    ) {
        self.init(accessMethods: [localFolderAccess, javaLocalFolderAccess, connectedDeviceAccess])
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

    nonisolated func probeLocalFolder(_ url: URL) async -> SourceProbeResult? {
        var bestProbe: SourceProbeResult?

        for accessMethod in accessMethodsByIdentifier.values {
            guard let probe = await accessMethod.probeLocalFolder(url) else {
                continue
            }

            guard probe.confidence > .none else {
                continue
            }

            if let currentBest = bestProbe {
                if probe.confidence > currentBest.confidence {
                    bestProbe = probe
                }
            } else {
                bestProbe = probe
            }
        }

        return bestProbe
    }

    nonisolated func discoverSourceCandidates() -> AsyncThrowingStream<SourceCandidateEvent, Error> {
        AsyncThrowingStream { continuation in
            let accessMethods = Array(accessMethodsByIdentifier.values)
            let task = Task.detached(priority: .userInitiated) {
                await withTaskGroup(of: Void.self) { group in
                    for accessMethod in accessMethods {
                        group.addTask {
                            do {
                                for try await event in accessMethod.discoverSourceCandidates() {
                                    continuation.yield(event)
                                }
                            } catch {
                                continuation.yield(
                                    .warning(
                                        ProviderWarning(
                                            id: "\(accessMethod.accessorIdentifier)-candidate-discovery-failed",
                                            message: "Source discovery failed",
                                            detail: error.localizedDescription
                                        )
                                    )
                                )
                            }
                        }
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    nonisolated func discoverItems(
        for source: MinecraftSource,
        mode: SourceDiscoveryMode,
        onDiscovered: @escaping @Sendable (MinecraftContentItem) -> Void
    ) async throws {
        try await accessMethod(for: source).discoverItems(
            for: source,
            mode: mode,
            onDiscovered: onDiscovered
        )
    }

    nonisolated func scanEvents(
        for source: MinecraftSource,
        mode: SourceDiscoveryMode
    ) -> AsyncThrowingStream<ProviderEvent, Error> {
        accessMethod(for: source).scanEvents(for: source, mode: mode)
    }

    nonisolated func accessDescriptor(for source: MinecraftSource) -> SourceAccessDescriptor {
        accessMethod(for: source).accessDescriptor(for: source)
    }

    nonisolated func availability(for source: MinecraftSource) async -> SourceAvailability {
        return await accessMethod(for: source).availability(for: source)
    }

    nonisolated func accessStatus(for source: MinecraftSource) async -> SourceAccessStatus {
        return await accessMethod(for: source).accessStatus(for: source)
    }

    nonisolated func capabilities(for source: MinecraftSource) async -> SourceCapabilities {
        return await accessMethod(for: source).capabilities(for: source)
    }

    nonisolated func enrich(_ item: MinecraftContentItem, for source: MinecraftSource) async -> MinecraftContentItem {
        return await accessMethod(for: source).enrich(item, for: source)
    }

    nonisolated func loadPreviewAssets(for item: MinecraftContentItem, in source: MinecraftSource) async -> MinecraftContentItem {
        return await accessMethod(for: source).loadPreviewAssets(for: item, in: source)
    }

    nonisolated func loadPreviewAssets(for items: [MinecraftContentItem], in source: MinecraftSource) async -> [MinecraftContentItem] {
        return await accessMethod(for: source).loadPreviewAssets(for: items, in: source)
    }

    nonisolated func loadSize(for item: MinecraftContentItem, in source: MinecraftSource) async -> MinecraftContentItem {
        return await accessMethod(for: source).loadSize(for: item, in: source)
    }

    nonisolated func loadSizeAssets(for items: [MinecraftContentItem], in source: MinecraftSource) async -> [MinecraftContentItem] {
        return await accessMethod(for: source).loadSizeAssets(for: items, in: source)
    }

    nonisolated func listItemContents(for item: MinecraftContentItem, in source: MinecraftSource) async throws -> [DirectoryEntry] {
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
