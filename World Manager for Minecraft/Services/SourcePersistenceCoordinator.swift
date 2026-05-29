//
//  SourcePersistenceCoordinator.swift
//  World Manager for Minecraft
//
//  Created by OpenAI Codex on 2026-05-29.
//

import Foundation

@MainActor
protocol SourcePersistenceHosting: AnyObject {
    var visibleSources: [MinecraftSource] { get }
    var isRestoringPersistedSources: Bool { get set }

    func source(withID sourceID: URL) -> MinecraftSource?
    func appendRestoredSource(_ source: MinecraftSource)
    func applyRestoredItems(_ items: [MinecraftContentItem], from record: PersistedSourceRecord)
    func sortSourcesByDisplayName()
    func refreshConnectedDevices() async
    func refreshLocalSources() async
    func queueAutomaticSync(for sourceID: URL, reason: String, debounce: TimeInterval?)
    func currentCollectionSnapshots(for sourceURL: URL) -> [CollectionSnapshot]
    func connectedDeviceDisplayName(for device: ConnectedDevice, container: DeviceAppContainer) -> String
}

enum SourcePersistenceCoordinator {
    static func restoreSources(
        on host: SourcePersistenceHosting,
        using persistenceStore: SourcePersistenceStore
    ) async {
        defer {
            host.isRestoringPersistedSources = false
        }

        let records: [PersistedSourceRecord]
        do {
            records = try await persistenceStore.loadSources()
        } catch {
            return
        }

        for record in records {
            let source = SourceRestoration.restoredSource(from: record) { device, container in
                host.connectedDeviceDisplayName(for: device, container: container)
            }

            host.appendRestoredSource(source)
        }

        for record in records where record.needsRepair {
            Task.detached(priority: .utility) {
                try? await persistenceStore.repair(record: record)
            }
        }

        host.sortSourcesByDisplayName()
        await Task.yield()

        for record in records {
            let restoredItems = await SourceRestoration.restoreCachedImages(in: record.rawItems)
            host.applyRestoredItems(restoredItems, from: record)
        }

        await host.refreshConnectedDevices()
        await host.refreshLocalSources()
        scheduleRestoredSourceRefreshes(records: records, on: host)
    }

    static func persistSourceIfAvailable(
        withID sourceID: URL,
        on host: SourcePersistenceHosting,
        using persistenceStore: SourcePersistenceStore
    ) {
        guard let source = host.source(withID: sourceID) else {
            return
        }

        let persistedSource = source
        Task {
            try? await persistenceStore.save(source: persistedSource)
        }
    }

    static func persistVisibleSourcesForShutdown(
        from sources: [MinecraftSource],
        using persistenceStore: SourcePersistenceStore
    ) async {
        for source in sources {
            try? await persistenceStore.save(source: source)
        }
    }

    static func deletePersistedSource(
        withID sourceID: URL,
        using persistenceStore: SourcePersistenceStore
    ) {
        Task {
            try? await persistenceStore.deleteSource(withID: sourceID)
        }
    }

    private static func scheduleRestoredSourceRefreshes(
        records: [PersistedSourceRecord],
        on host: SourcePersistenceHosting
    ) {
        let persistedRecordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.sourceID, $0) })

        for source in host.visibleSources {
            if let refreshReason = SourceRestoration.startupRefreshReason(
                for: source,
                persistedRecord: persistedRecordsByID[source.id],
                currentCollectionSnapshots: host.currentCollectionSnapshots(for:)
            ) {
                host.queueAutomaticSync(for: source.id, reason: refreshReason, debounce: nil)
            }
        }
    }
}
