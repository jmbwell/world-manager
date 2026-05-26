//
//  SourceLibrary.swift
//  World Manager for Minecraft
//
//  Created by John Burwell on 2026-05-25.
//

import Combine
import Foundation

struct SidebarFooterState {
    enum Style {
        case idle
        case inProgress
        case failure
        case success
    }

    let style: Style
    let title: String
    let subtitle: String?
    let revealURL: URL?
}

@MainActor
final class SourceLibrary: ObservableObject {
    private static let enrichmentWorkerCount = 4
    private static let sizeWorkerCount = 2

    @Published var sources: [MinecraftSource] = []
    @Published private(set) var sidebarFooterState = SidebarFooterState(
        style: .idle,
        title: "",
        subtitle: nil,
        revealURL: nil
    )
    @Published private(set) var isRestoringPersistedSources = true

    private var scanTasks: [URL: Task<Void, Never>] = [:]
    private var footerResetTask: Task<Void, Never>?
    private let persistenceStore: SourcePersistenceStore

    init(persistenceStore: SourcePersistenceStore = .shared) {
        self.persistenceStore = persistenceStore

        Task { [weak self] in
            await self?.restorePersistedSources()
        }
    }

    func addSource(at url: URL) -> URL {
        let normalizedURL = url.standardizedFileURL

        if sources.contains(where: { $0.id == normalizedURL }) {
            startScan(for: normalizedURL)
            return normalizedURL
        }

        sources.append(MinecraftSource(folderURL: normalizedURL))
        sources.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        persistSourceIfAvailable(withID: normalizedURL)
        startScan(for: normalizedURL)
        return normalizedURL
    }

    func source(withID sourceID: URL) -> MinecraftSource? {
        sources.first(where: { $0.id == sourceID })
    }

    func rescanSource(withID sourceID: URL) {
        startScan(for: sourceID)
    }

    func removeSource(withID sourceID: URL) {
        scanTasks[sourceID]?.cancel()
        scanTasks[sourceID] = nil
        sources.removeAll { $0.id == sourceID }
        deletePersistedSource(withID: sourceID)
        refreshSidebarFooterState()
    }

    func setItemActionInProgress(_ description: String) {
        cancelFooterReset()
        sidebarFooterState = SidebarFooterState(
            style: .inProgress,
            title: description,
            subtitle: nil,
            revealURL: nil
        )
    }

    func setItemActionFailure(_ message: String) {
        sidebarFooterState = SidebarFooterState(
            style: .failure,
            title: "Action Failed",
            subtitle: message,
            revealURL: nil
        )
        scheduleFooterReset()
    }

    func setItemActionSuccess(title: String, subtitle: String, revealURL: URL?) {
        sidebarFooterState = SidebarFooterState(
            style: .success,
            title: title,
            subtitle: subtitle,
            revealURL: revealURL
        )
        scheduleFooterReset()
    }

    var activeScanSummary: String? {
        let scanningSources = sources.filter(\.isScanning)
        guard !scanningSources.isEmpty else {
            return nil
        }

        if scanningSources.count == 1, let source = scanningSources.first {
            return "\(source.displayName): \(source.scanStatus)"
        }

        return "Scanning \(scanningSources.count) sources..."
    }

    private func startScan(for sourceID: URL) {
        scanTasks[sourceID]?.cancel()

        let task = Task { [weak self] in
            guard let self else {
                return
            }

            await self.scanSource(withID: sourceID)
        }

        scanTasks[sourceID] = task
    }

    private func scanSource(withID sourceID: URL) async {
        var workerTasks: [Task<Void, Never>] = []
        var sizeWorkerTasks: [Task<Void, Never>] = []
        defer {
            workerTasks.forEach { $0.cancel() }
            sizeWorkerTasks.forEach { $0.cancel() }
            scanTasks[sourceID] = nil
        }

        await WorldScanner.beginScanSession(for: sourceID)

        updateSource(sourceID) { source in
            source.isScanning = true
            source.scanError = nil
            source.scanStatus = "Scanning Minecraft library..."
            source.displayItems = []
            source.rawItems = []
            source.logicalPacks = []
            source.logicalWorlds = []
            source.packInstances = []
            source.worldPackRelationships = []
            source.snapshot = nil
            source.indexedItemCount = 0
            source.indexedDetailCount = 0
        }
        refreshSidebarFooterState()

        do {
            let index = SourceIndexActor(sourceID: sourceID, folderURL: sourceID)
            let enrichmentQueue = EnrichmentWorkQueue()
            let sizeQueue = EnrichmentWorkQueue()
            workerTasks = (0..<Self.enrichmentWorkerCount).map { _ in
                Task.detached(priority: .utility) { [weak self] in
                    guard let library = self else {
                        return
                    }

                    while let item = await enrichmentQueue.next() {
                        guard !Task.isCancelled else {
                            return
                        }

                        let enrichedItem = await WorldScanner.enrich(item: item)
                        if let snapshot = await index.applyEnrichedItem(enrichedItem) {
                            await MainActor.run {
                                library.applySnapshot(snapshot, to: sourceID)
                                library.refreshSidebarFooterState()
                            }
                        }
                        await sizeQueue.enqueue(enrichedItem)
                    }
                }
            }
            sizeWorkerTasks = (0..<Self.sizeWorkerCount).map { _ in
                Task.detached(priority: .utility) { [weak self] in
                    guard let library = self else {
                        return
                    }

                    while let item = await sizeQueue.next() {
                        guard !Task.isCancelled else {
                            return
                        }

                        let sizedItem = WorldScanner.loadSize(for: item)
                        if let snapshot = await index.applySizedItem(sizedItem) {
                            await MainActor.run {
                                library.applySnapshot(snapshot, to: sourceID)
                                library.refreshSidebarFooterState()
                            }
                        }
                    }
                }
            }
            let discoveryStream = AsyncThrowingStream<MinecraftContentItem, Error> { continuation in
                let discoveryTask = Task.detached(priority: .userInitiated) {
                    do {
                        _ = try WorldScanner.discoverItems(in: sourceID) { item in
                            continuation.yield(item)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }

                continuation.onTermination = { @Sendable _ in
                    discoveryTask.cancel()
                }
            }

            var discoveredCount = 0

            for try await item in discoveryStream {
                guard !Task.isCancelled else {
                    break
                }

                discoveredCount += 1
                if let snapshot = await index.addDiscoveredItem(
                    item,
                    discoveredCount: discoveredCount
                ) {
                    applySnapshot(snapshot, to: sourceID)
                }
                refreshSidebarFooterState()

                await enrichmentQueue.enqueue(item)
            }

            await enrichmentQueue.finish()

            for workerTask in workerTasks {
                await workerTask.value
            }

            if let snapshot = await index.markMetadataFinished() {
                applySnapshot(snapshot, to: sourceID)
            }
            refreshSidebarFooterState()

            await sizeQueue.finish()

            for sizeWorkerTask in sizeWorkerTasks {
                await sizeWorkerTask.value
            }

            if let snapshot = await index.finishScan() {
                applySnapshot(snapshot, to: sourceID)
            }
            updateSource(sourceID) { source in
                source.snapshot = buildSnapshot(for: source, packMetadataByItemID: [:])
            }
            persistSourceIfAvailable(withID: sourceID)
            refreshSidebarFooterState()
        } catch {
            guard !Task.isCancelled else {
                return
            }

            updateSource(sourceID) { source in
                source.scanError = "Failed to scan folder: \(error.localizedDescription)"
                source.scanStatus = ""
                source.isScanning = false
            }
            refreshSidebarFooterState()
        }
    }

    private func handleEnrichedItem(_ enrichedItem: MinecraftContentItem, for sourceID: URL) {
        var previousItem: MinecraftContentItem?

        updateSource(sourceID) { source in
            guard let index = source.rawItems.firstIndex(where: { $0.id == enrichedItem.id }) else {
                return
            }

            previousItem = source.rawItems[index]
            source.rawItems[index] = enrichedItem
            source.indexedDetailCount += 1

            if source.indexedDetailCount < source.indexedItemCount {
                source.scanStatus = "Loaded details for \(source.indexedDetailCount) of \(source.indexedItemCount) items..."
            }

            handleMetadataUpdate(
                for: enrichedItem,
                previousItem: previousItem,
                in: &source,
                sourceID: sourceID
            )
        }
        refreshSidebarFooterState()
    }

    private func handleSizedItem(_ sizedItem: MinecraftContentItem, for sourceID: URL) {
        updateSource(sourceID) { source in
            guard let index = source.rawItems.firstIndex(where: { $0.id == sizedItem.id }) else {
                return
            }

            source.rawItems[index].sizeBytes = sizedItem.sizeBytes
            source.rawItems[index].sizeLoaded = sizedItem.sizeLoaded

            if source.isScanning {
                source.scanStatus = "Calculating sizes for \(source.rawItems.filter(\.sizeLoaded).count) of \(source.indexedItemCount) items..."
            }
        }
        refreshSidebarFooterState()
    }

    private func rebuildNormalizedIndex(for sourceID: URL) {
        updateSource(sourceID) { source in
            let rawItems = source.rawItems.sorted(by: WorldScanner.sortItems)
            source.rawItems = rawItems
            let rawItemsByID = Dictionary(uniqueKeysWithValues: rawItems.map { ($0.id, $0) })

            let rawPacks = rawItems.filter {
                $0.contentType == .behaviorPack || $0.contentType == .resourcePack
            }
            let rawWorlds = rawItems.filter { $0.contentType == .world }

            let packMetadataByItemID = Dictionary(uniqueKeysWithValues: rawPacks.map { item in
                (item.id, packMetadata(for: item, sourceRootURL: source.folderURL))
            })

            var chosenRepresentativeByIdentity: [PackIdentity: MinecraftContentItem] = [:]
            var allPackItemsByIdentity: [PackIdentity: [MinecraftContentItem]] = [:]

            for item in rawPacks {
                let metadata = packMetadataByItemID[item.id] ?? packMetadata(for: item, sourceRootURL: source.folderURL)
                let identity = metadata.identity
                allPackItemsByIdentity[identity, default: []].append(item)

                guard let existing = chosenRepresentativeByIdentity[identity] else {
                    chosenRepresentativeByIdentity[identity] = item
                    continue
                }

                if shouldPreferPackItem(item, over: existing) {
                    chosenRepresentativeByIdentity[identity] = item
                }
            }

            let logicalPacks = allPackItemsByIdentity.keys.sorted {
                let lhs = chosenRepresentativeByIdentity[$0]?.displayName ?? ""
                let rhs = chosenRepresentativeByIdentity[$1]?.displayName ?? ""
                let nameOrder = lhs.localizedStandardCompare(rhs)
                if nameOrder != .orderedSame {
                    return nameOrder == .orderedAscending
                }

                return $0.id.localizedStandardCompare($1.id) == .orderedAscending
            }.compactMap { identity -> LogicalPack? in
                guard
                    let representativeItem = chosenRepresentativeByIdentity[identity],
                    let instances = allPackItemsByIdentity[identity]
                else {
                    return nil
                }

                let metadata = packMetadataByItemID[representativeItem.id]

                return LogicalPack(
                    id: identity,
                    contentType: identity.type,
                    displayName: representativeItem.displayName,
                    uuid: metadata?.uuid,
                    version: metadata?.version,
                    representativeItemID: representativeItem.id,
                    instanceItemIDs: instances.map(\.id).sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending },
                    isSuspicious: identity.isSuspicious
                )
            }

            var packInstances: [PackInstance] = []
            for logicalPack in logicalPacks {
                for itemID in logicalPack.instanceItemIDs {
                    guard let item = rawItemsByID[itemID] else {
                        continue
                    }

                    packInstances.append(
                        PackInstance(
                            id: item.id,
                            itemID: item.id,
                            sourceID: sourceID,
                            logicalPackID: logicalPack.id,
                            origin: packOrigin(for: item),
                            hostWorldItemID: hostWorldItemID(for: item, in: rawWorlds)
                        )
                    )
                }
            }

            let logicalPacksByID = Dictionary(uniqueKeysWithValues: logicalPacks.map { ($0.id, $0) })
            var worldRelationships: [WorldPackRelationship] = []
            var logicalWorlds: [LogicalWorld] = []

            for world in rawWorlds {
                var usedPackIDs = Set<PackIdentity>()
                var unresolvedReferences: [ContentPackReference] = []

                for reference in world.packReferences {
                    let referenceIdentity = PackIdentity(
                        type: reference.type,
                        uuid: reference.uuid,
                        version: reference.version,
                        fallbackName: reference.name,
                        fallbackLocationHint: world.folderName
                    )
                    let resolvedID = logicalPacksByID[referenceIdentity]?.id

                    if let resolvedID {
                        usedPackIDs.insert(resolvedID)
                    } else {
                        unresolvedReferences.append(reference)
                    }

                    worldRelationships.append(
                        WorldPackRelationship(
                            worldItemID: world.id,
                            logicalPackID: resolvedID,
                            reference: reference
                        )
                    )
                }

                logicalWorlds.append(
                    LogicalWorld(
                        id: world.id,
                        itemID: world.id,
                        usedPackIDs: usedPackIDs.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending },
                        unresolvedReferences: unresolvedReferences
                    )
                )
            }

            source.logicalPacks = logicalPacks
            source.logicalWorlds = logicalWorlds.sorted {
                guard
                    let lhs = source.rawItem(withID: $0.itemID),
                    let rhs = source.rawItem(withID: $1.itemID)
                else {
                    return $0.itemID.path.localizedStandardCompare($1.itemID.path) == .orderedAscending
                }

                return WorldScanner.sortItems(lhs, rhs)
            }
            source.packInstances = packInstances.sorted {
                $0.itemID.path.localizedStandardCompare($1.itemID.path) == .orderedAscending
            }
            source.worldPackRelationships = worldRelationships
            source.displayItems = buildDisplayItems(
                from: rawItems,
                logicalPacks: logicalPacks,
                rawItemsByID: rawItemsByID
            )
        }
    }

    private func handleDiscoveredItem(_ item: MinecraftContentItem, in source: inout MinecraftSource, sourceID: URL) {
        guard isLogicalPackType(item.contentType) else {
            return
        }

        let identity = packMetadata(for: item, sourceRootURL: source.folderURL).identity
        refreshLogicalPack(identity: identity, in: &source, sourceID: sourceID)
    }

    private func handleMetadataUpdate(
        for item: MinecraftContentItem,
        previousItem: MinecraftContentItem?,
        in source: inout MinecraftSource,
        sourceID: URL
    ) {
        if isLogicalPackType(item.contentType) {
            let newIdentity = packMetadata(for: item, sourceRootURL: source.folderURL).identity
            let previousIdentity = previousItem.map { packMetadata(for: $0, sourceRootURL: source.folderURL).identity }

            if let previousIdentity, previousIdentity != newIdentity {
                refreshLogicalPack(identity: previousIdentity, in: &source, sourceID: sourceID)
            }

            refreshLogicalPack(identity: newIdentity, in: &source, sourceID: sourceID)
            refreshWorldRelationships(in: &source, filteringTo: item.contentType)
            return
        }

        if item.contentType == .world {
            refreshWorldRelationship(for: item, in: &source)
        }
    }

    private func updateSource(_ sourceID: URL, mutate: (inout MinecraftSource) -> Void) {
        guard let index = sources.firstIndex(where: { $0.id == sourceID }) else {
            return
        }

        mutate(&sources[index])
    }

    private func applySnapshot(_ snapshot: SourceIndexSnapshot, to sourceID: URL) {
        updateSource(sourceID) { source in
            source.displayItems = snapshot.displayItems
            source.rawItems = snapshot.rawItems
            source.logicalPacks = snapshot.logicalPacks
            source.logicalWorlds = snapshot.logicalWorlds
            source.packInstances = snapshot.packInstances
            source.worldPackRelationships = snapshot.worldPackRelationships
            source.indexedItemCount = snapshot.indexedItemCount
            source.indexedDetailCount = snapshot.indexedDetailCount
            source.scanStatus = snapshot.scanStatus
            source.isScanning = snapshot.isScanning
            source.lastScanDate = snapshot.lastScanDate
        }
    }

    private func refreshLogicalPack(identity: PackIdentity, in source: inout MinecraftSource, sourceID: URL) {
        let matchingItems = source.rawItems.filter { item in
            guard isLogicalPackType(item.contentType) else {
                return false
            }

            return packMetadata(for: item, sourceRootURL: source.folderURL).identity == identity
        }

        source.logicalPacks.removeAll { $0.id == identity }
        source.packInstances.removeAll { $0.logicalPackID == identity }

        guard !matchingItems.isEmpty else {
            return
        }

        let representativeItem = matchingItems.reduce(matchingItems[0]) { current, candidate in
            shouldPreferPackItem(candidate, over: current) ? candidate : current
        }
        let representativeMetadata = packMetadata(for: representativeItem, sourceRootURL: source.folderURL)

        source.logicalPacks.append(
            LogicalPack(
                id: identity,
                contentType: identity.type,
                displayName: representativeItem.displayName,
                uuid: representativeMetadata.uuid,
                version: representativeMetadata.version,
                representativeItemID: representativeItem.id,
                instanceItemIDs: matchingItems.map(\.id).sorted {
                    $0.path.localizedStandardCompare($1.path) == .orderedAscending
                },
                isSuspicious: identity.isSuspicious
            )
        )
        source.logicalPacks.sort {
            let nameOrder = $0.displayName.localizedStandardCompare($1.displayName)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }

            return $0.id.id.localizedStandardCompare($1.id.id) == .orderedAscending
        }

        let rawWorlds = source.rawItems.filter { $0.contentType == .world }
        source.packInstances.append(
            contentsOf: matchingItems.map { item in
                PackInstance(
                    id: item.id,
                    itemID: item.id,
                    sourceID: sourceID,
                    logicalPackID: identity,
                    origin: packOrigin(for: item),
                    hostWorldItemID: hostWorldItemID(for: item, in: rawWorlds)
                )
            }
        )
        source.packInstances.sort {
            $0.itemID.path.localizedStandardCompare($1.itemID.path) == .orderedAscending
        }
    }

    private func refreshWorldRelationships(in source: inout MinecraftSource, filteringTo type: MinecraftContentType? = nil) {
        let worlds = source.rawItems.filter { $0.contentType == .world }
        for world in worlds {
            guard type == nil || world.packReferences.contains(where: { $0.type == type }) else {
                continue
            }

            refreshWorldRelationship(for: world, in: &source)
        }
    }

    private func refreshWorldRelationship(for world: MinecraftContentItem, in source: inout MinecraftSource) {
        source.worldPackRelationships.removeAll { $0.worldItemID == world.id }
        source.logicalWorlds.removeAll { $0.itemID == world.id }

        let logicalPacksByID = Dictionary(uniqueKeysWithValues: source.logicalPacks.map { ($0.id, $0) })
        var usedPackIDs = Set<PackIdentity>()
        var unresolvedReferences: [ContentPackReference] = []
        var relationships: [WorldPackRelationship] = []

        for reference in world.packReferences {
            let referenceIdentity = PackIdentity(
                type: reference.type,
                uuid: reference.uuid,
                version: reference.version,
                fallbackName: reference.name,
                fallbackLocationHint: world.folderName
            )
            let resolvedID = logicalPacksByID[referenceIdentity]?.id

            if let resolvedID {
                usedPackIDs.insert(resolvedID)
            } else {
                unresolvedReferences.append(reference)
            }

            relationships.append(
                WorldPackRelationship(
                    worldItemID: world.id,
                    logicalPackID: resolvedID,
                    reference: reference
                )
            )
        }

        source.worldPackRelationships.append(contentsOf: relationships)
        source.logicalWorlds.append(
            LogicalWorld(
                id: world.id,
                itemID: world.id,
                usedPackIDs: usedPackIDs.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending },
                unresolvedReferences: unresolvedReferences
            )
        )
        let rawItemsByID = Dictionary(uniqueKeysWithValues: source.rawItems.map { ($0.id, $0) })
        source.logicalWorlds.sort {
            guard
                let lhs = rawItemsByID[$0.itemID],
                let rhs = rawItemsByID[$1.itemID]
            else {
                return $0.itemID.path.localizedStandardCompare($1.itemID.path) == .orderedAscending
            }

            return WorldScanner.sortItems(lhs, rhs)
        }
    }

    private func restorePersistedSources() async {
        defer {
            isRestoringPersistedSources = false
            refreshSidebarFooterState()
        }

        let records: [PersistedSourceRecord]
        do {
            records = try await persistenceStore.loadSources()
        } catch {
            return
        }

        for record in records {
            var source = MinecraftSource(folderURL: record.folderURL)
            source.displayName = record.displayName
            source.rawItems = await restoreCachedImages(in: record.rawItems)
            source.indexedItemCount = record.rawItems.count
            source.indexedDetailCount = source.rawItems.filter(\.metadataLoaded).count
            source.lastScanDate = record.lastScanDate
            source.snapshot = record.snapshot

            sources.append(source)
            rebuildNormalizedIndex(for: source.id)

            updateSource(source.id) { source in
                source.displayItems = source.displayItems.sorted(by: WorldScanner.sortItems)
                source.scanStatus = source.indexedItemCount == 0
                    ? "No Minecraft items found."
                    : "Loaded \(source.indexedDetailCount) items."
            }
        }

        sources.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }

        for record in records {
            if sourceNeedsRescan(record) {
                startScan(for: record.folderURL)
            }
        }
    }

    private func restoreCachedImages(in items: [MinecraftContentItem]) async -> [MinecraftContentItem] {
        var restoredItems: [MinecraftContentItem] = []
        restoredItems.reserveCapacity(items.count)

        for var item in items {
            item.iconURL = await ImageCacheStore.shared.cachedImageURL(for: item.iconURL)
            item.packReferences = await restoreCachedImages(in: item.packReferences)
            restoredItems.append(item)
        }

        return restoredItems
    }

    private func restoreCachedImages(in references: [ContentPackReference]) async -> [ContentPackReference] {
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

    private func sourceNeedsRescan(_ record: PersistedSourceRecord) -> Bool {
        guard let snapshot = record.snapshot else {
            return true
        }

        let fileManager = FileManager.default
        let sourceURL = record.folderURL

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            return true
        }

        let currentCollections = Dictionary(uniqueKeysWithValues: currentCollectionSnapshots(for: sourceURL).map { ($0.folderName, $0) })
        let persistedCollections = Dictionary(uniqueKeysWithValues: snapshot.collectionSnapshots.map { ($0.folderName, $0) })

        if currentCollections.count != persistedCollections.count {
            return true
        }

        for (folderName, persistedCollection) in persistedCollections {
            guard let currentCollection = currentCollections[folderName], currentCollection == persistedCollection else {
                return true
            }
        }

        for itemSnapshot in snapshot.itemSnapshots {
            let itemURL = sourceURL.appendingPathComponent(itemSnapshot.relativePath, isDirectory: true)
            guard fileManager.fileExists(atPath: itemURL.path) else {
                return true
            }

            let modifiedDate = try? itemURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if modifiedDate != itemSnapshot.modifiedDate {
                return true
            }
        }

        return false
    }

    private func currentCollectionSnapshots(for sourceURL: URL) -> [CollectionSnapshot] {
        let fileManager = FileManager.default

        return MinecraftContentType.allCases.compactMap { type -> CollectionSnapshot? in
            let collectionURL = sourceURL.appendingPathComponent(type.collectionFolderName, isDirectory: true)
            guard fileManager.fileExists(atPath: collectionURL.path) else {
                return nil
            }

            let children = (try? fileManager.contentsOfDirectory(
                at: collectionURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            let childDirectoryCount = children.filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }.count
            let modifiedDate = try? collectionURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

            return CollectionSnapshot(
                folderName: type.collectionFolderName,
                modifiedDate: modifiedDate,
                childDirectoryCount: childDirectoryCount,
                fingerprint: [
                    type.collectionFolderName,
                    String(childDirectoryCount),
                    modifiedDate?.timeIntervalSince1970.formatted() ?? "nil"
                ].joined(separator: "::")
            )
        }
    }

    private func buildDisplayItems(
        from rawItems: [MinecraftContentItem],
        logicalPacks: [LogicalPack],
        rawItemsByID: [URL: MinecraftContentItem]
    ) -> [MinecraftContentItem] {
        var normalizedItemIDs = Set<URL>()
        var normalizedItems: [MinecraftContentItem] = []

        for item in rawItems where item.contentType == .world {
            guard normalizedItemIDs.insert(item.id).inserted else {
                continue
            }

            normalizedItems.append(item)
        }

        for logicalPack in logicalPacks {
            guard
                let item = rawItemsByID[logicalPack.representativeItemID],
                normalizedItemIDs.insert(item.id).inserted
            else {
                continue
            }

            normalizedItems.append(item)
        }

        for item in rawItems where item.contentType == .skinPack || item.contentType == .worldTemplate {
            guard normalizedItemIDs.insert(item.id).inserted else {
                continue
            }

            normalizedItems.append(item)
        }

        return normalizedItems
    }

    private func persistSourceIfAvailable(withID sourceID: URL) {
        guard let source = source(withID: sourceID) else {
            return
        }

        let persistedSource = source
        Task {
            try? await persistenceStore.save(source: persistedSource)
        }
    }

    private func deletePersistedSource(withID sourceID: URL) {
        let normalizedSourceID = sourceID.standardizedFileURL
        Task {
            try? await persistenceStore.deleteSource(withID: normalizedSourceID)
        }
    }

    private func isLogicalPackType(_ contentType: MinecraftContentType) -> Bool {
        contentType == .behaviorPack || contentType == .resourcePack
    }

    private func refreshSidebarFooterState() {
        if isRestoringPersistedSources {
            cancelFooterReset()
            sidebarFooterState = SidebarFooterState(
                style: .inProgress,
                title: "Restoring library...",
                subtitle: "Loading saved sources and cached metadata",
                revealURL: nil
            )
            return
        }

        let scanningSources = sources.filter(\.isScanning)
        if let source = scanningSources.first {
            cancelFooterReset()
            let subtitle: String
            if source.indexedItemCount > 0 {
                subtitle = "\(source.indexedDetailCount) of \(source.indexedItemCount) indexed"
            } else {
                subtitle = "Searching \(source.displayName)"
            }

            sidebarFooterState = SidebarFooterState(
                style: .inProgress,
                title: "Scanning...",
                subtitle: subtitle,
                revealURL: nil
            )
            return
        }

        if let source = sources.first(where: { $0.scanError != nil }) {
            sidebarFooterState = SidebarFooterState(
                style: .failure,
                title: "Scan failed",
                subtitle: source.scanError,
                revealURL: nil
            )
            scheduleFooterReset()
            return
        }
        cancelFooterReset()
        sidebarFooterState = SidebarFooterState(style: .idle, title: "", subtitle: nil, revealURL: nil)
    }

    private func cancelFooterReset() {
        footerResetTask?.cancel()
        footerResetTask = nil
    }

    private func scheduleFooterReset(after seconds: Double = 5) {
        cancelFooterReset()
        footerResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled else {
                return
            }

            self.refreshSidebarFooterState()
        }
    }

    private func buildSnapshot(
        for source: MinecraftSource,
        packMetadataByItemID: [URL: PackMetadata]
    ) -> SourceSnapshot {
        let collectionSnapshots = MinecraftContentType.allCases.compactMap { type -> CollectionSnapshot? in
            let collectionURL = source.folderURL.appendingPathComponent(type.collectionFolderName, isDirectory: true)
            guard FileManager.default.fileExists(atPath: collectionURL.path) else {
                return nil
            }

            let children = (try? FileManager.default.contentsOfDirectory(
                at: collectionURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            let childDirectoryCount = children.filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }.count
            let modifiedDate = try? collectionURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

            return CollectionSnapshot(
                folderName: type.collectionFolderName,
                modifiedDate: modifiedDate,
                childDirectoryCount: childDirectoryCount,
                fingerprint: [
                    type.collectionFolderName,
                    String(childDirectoryCount),
                    modifiedDate?.timeIntervalSince1970.formatted() ?? "nil"
                ].joined(separator: "::")
            )
        }

        let itemSnapshots = source.rawItems.map { item in
            let relativePath = item.folderURL.path.replacingOccurrences(of: source.folderURL.path + "/", with: "")
            let metadata = packMetadataByItemID[item.id]
            return ItemSnapshot(
                id: item.id,
                relativePath: relativePath,
                modifiedDate: item.modifiedDate,
                sizeBytes: item.sizeBytes,
                packUUID: metadata?.uuid,
                packVersion: metadata?.version
            )
        }.sorted { (lhs: ItemSnapshot, rhs: ItemSnapshot) in
            lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
        }

        let rootModifiedDate = try? source.folderURL
            .resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate

        return SourceSnapshot(
            sourceID: source.id,
            rootModifiedDate: rootModifiedDate,
            collectionSnapshots: collectionSnapshots,
            itemSnapshots: itemSnapshots
        )
    }

    private func shouldPreferPackItem(_ candidate: MinecraftContentItem, over existing: MinecraftContentItem) -> Bool {
        let candidateEmbedded = isEmbeddedWorldPack(candidate)
        let existingEmbedded = isEmbeddedWorldPack(existing)

        if candidateEmbedded != existingEmbedded {
            return !candidateEmbedded
        }

        if candidate.metadataLoaded != existing.metadataLoaded {
            return candidate.metadataLoaded
        }

        if candidate.modifiedDate != existing.modifiedDate {
            return (candidate.modifiedDate ?? .distantPast) > (existing.modifiedDate ?? .distantPast)
        }

        return candidate.folderURL.path.localizedStandardCompare(existing.folderURL.path) == .orderedAscending
    }

    private func packOrigin(for item: MinecraftContentItem) -> PackSource {
        isEmbeddedWorldPack(item) ? .embeddedInWorld : .foundInCollection
    }

    private func isEmbeddedWorldPack(_ item: MinecraftContentItem) -> Bool {
        item.folderURL.pathComponents.contains(MinecraftContentType.world.collectionFolderName)
    }

    private func hostWorldItemID(for packItem: MinecraftContentItem, in rawWorlds: [MinecraftContentItem]) -> URL? {
        rawWorlds.first(where: { world in
            packItem.folderURL.path.hasPrefix(world.folderURL.path + "/")
        })?.id
    }

    private func packMetadata(for item: MinecraftContentItem, sourceRootURL: URL) -> PackMetadata {
        let uuid = item.packUUID
        let version = item.packVersion

        return PackMetadata(
            uuid: uuid,
            version: version,
            identity: PackIdentity(
                type: item.contentType,
                uuid: uuid,
                version: version,
                fallbackName: item.displayName,
                fallbackLocationHint: relativePathHint(for: item, sourceRootURL: sourceRootURL)
            )
        )
    }

    private func relativePathHint(for item: MinecraftContentItem, sourceRootURL: URL) -> String {
        item.folderURL.path.replacingOccurrences(of: sourceRootURL.path + "/", with: "")
    }

}

private struct PackMetadata {
    let uuid: String?
    let version: String?
    let identity: PackIdentity
}

private actor EnrichmentWorkQueue {
    private var pendingItems: [MinecraftContentItem] = []
    private var isFinished = false
    private var waitingContinuations: [CheckedContinuation<MinecraftContentItem?, Never>] = []

    func enqueue(_ item: MinecraftContentItem) {
        if let continuation = waitingContinuations.first {
            waitingContinuations.removeFirst()
            continuation.resume(returning: item)
            return
        }

        pendingItems.append(item)
    }

    func next() async -> MinecraftContentItem? {
        if !pendingItems.isEmpty {
            return pendingItems.removeFirst()
        }

        if isFinished {
            return nil
        }

        return await withCheckedContinuation { continuation in
            waitingContinuations.append(continuation)
        }
    }

    func finish() {
        isFinished = true

        for continuation in waitingContinuations {
            continuation.resume(returning: nil)
        }

        waitingContinuations.removeAll()
    }
}

private struct SourceIndexSnapshot {
    let displayItems: [MinecraftContentItem]
    let rawItems: [MinecraftContentItem]
    let logicalPacks: [LogicalPack]
    let logicalWorlds: [LogicalWorld]
    let packInstances: [PackInstance]
    let worldPackRelationships: [WorldPackRelationship]
    let indexedItemCount: Int
    let indexedDetailCount: Int
    let scanStatus: String
    let isScanning: Bool
    let lastScanDate: Date?
}

private actor SourceIndexActor {
    private let sourceID: URL
    private let folderURL: URL
    private let publishInterval: TimeInterval = 0.12

    private var orderedItemIDs: [URL] = []
    private var itemsByID: [URL: MinecraftContentItem] = [:]
    private var packMetadataByItemID: [URL: PackMetadata] = [:]
    private var packIdentityByItemID: [URL: String] = [:]
    private var packIdentityValueByID: [String: PackIdentity] = [:]
    private var packItemIDsByIdentityID: [String: Set<URL>] = [:]
    private var packRepresentativeItemIDByIdentityID: [String: URL] = [:]
    private var indexedItemCount = 0
    private var indexedDetailCount = 0
    private var discoveryFinished = false
    private var metadataFinished = false
    private var sizesFinished = false
    private var lastPublishedAt: Date?

    init(sourceID: URL, folderURL: URL) {
        self.sourceID = sourceID
        self.folderURL = folderURL
    }

    func addDiscoveredItem(_ item: MinecraftContentItem, discoveredCount: Int) -> SourceIndexSnapshot? {
        orderedItemIDs.append(item.id)
        itemsByID[item.id] = item
        indexedItemCount = discoveredCount
        return snapshotIfNeeded()
    }

    func applyEnrichedItem(_ item: MinecraftContentItem) -> SourceIndexSnapshot? {
        let previous = itemsByID[item.id]
        itemsByID[item.id] = item
        if item.metadataLoaded, previous?.metadataLoaded != true {
            indexedDetailCount += 1
        }

        if isLogicalPackType(item.contentType) {
            refreshTrackedPackIdentity(for: item, previousItem: previous)
        }

        return snapshotIfNeeded()
    }

    func applySizedItem(_ item: MinecraftContentItem) -> SourceIndexSnapshot? {
        guard var current = itemsByID[item.id] else {
            return nil
        }

        current.sizeBytes = item.sizeBytes
        current.sizeLoaded = item.sizeLoaded
        itemsByID[item.id] = current
        return snapshotIfNeeded()
    }

    func markDiscoveryFinished() -> SourceIndexSnapshot? {
        discoveryFinished = true
        return buildSnapshot(force: true)
    }

    func markMetadataFinished() -> SourceIndexSnapshot? {
        discoveryFinished = true
        metadataFinished = true
        return buildSnapshot(force: true)
    }

    func finishScan() -> SourceIndexSnapshot? {
        discoveryFinished = true
        metadataFinished = true
        sizesFinished = true
        return buildSnapshot(force: true)
    }

    private func snapshotIfNeeded() -> SourceIndexSnapshot? {
        buildSnapshot(force: false)
    }

    private func buildSnapshot(force: Bool) -> SourceIndexSnapshot? {
        let now = Date()
        if !force, let lastPublishedAt, now.timeIntervalSince(lastPublishedAt) < publishInterval {
            return nil
        }

        lastPublishedAt = now

        let rawItems = orderedItemIDs.compactMap { itemsByID[$0] }
        let rawItemsByID = Dictionary(uniqueKeysWithValues: rawItems.map { ($0.id, $0) })
        let logicalPacks = buildLogicalPacks(rawItemsByID: rawItemsByID)
        let dedupedDisplayItems = buildDisplayItems(
            from: rawItems,
            logicalPacks: logicalPacks,
            rawItemsByID: rawItemsByID
        )
        let scanStatus: String

        if !discoveryFinished {
            scanStatus = indexedItemCount == 0
                ? "Scanning Minecraft library..."
                : "Found \(indexedItemCount) items. Loading metadata..."

            return SourceIndexSnapshot(
                displayItems: dedupedDisplayItems,
                rawItems: rawItems,
                logicalPacks: logicalPacks,
                logicalWorlds: [],
                packInstances: [],
                worldPackRelationships: [],
                indexedItemCount: indexedItemCount,
                indexedDetailCount: indexedDetailCount,
                scanStatus: scanStatus,
                isScanning: true,
                lastScanDate: nil
            )
        }

        if !metadataFinished {
            scanStatus = indexedItemCount == 0
                ? "No Minecraft items found."
                : "Deduplicating packs..."

            return SourceIndexSnapshot(
                displayItems: dedupedDisplayItems,
                rawItems: rawItems,
                logicalPacks: logicalPacks,
                logicalWorlds: [],
                packInstances: [],
                worldPackRelationships: [],
                indexedItemCount: indexedItemCount,
                indexedDetailCount: indexedDetailCount,
                scanStatus: scanStatus,
                isScanning: true,
                lastScanDate: nil
            )
        }

        let rawWorlds = rawItems.filter { $0.contentType == .world }
        var packInstances: [PackInstance] = []
        for logicalPack in logicalPacks {
            for itemID in logicalPack.instanceItemIDs {
                guard let item = rawItemsByID[itemID] else {
                    continue
                }

                packInstances.append(
                    PackInstance(
                        id: item.id,
                        itemID: item.id,
                        sourceID: sourceID,
                        logicalPackID: logicalPack.id,
                        origin: isEmbeddedWorldPack(item) ? .embeddedInWorld : .foundInCollection,
                        hostWorldItemID: hostWorldItemID(for: item, in: rawWorlds)
                    )
                )
            }
        }

        let logicalPacksByID = Dictionary(uniqueKeysWithValues: logicalPacks.map { ($0.id.canonicalKey, $0) })
        var worldRelationships: [WorldPackRelationship] = []
        var logicalWorlds: [LogicalWorld] = []

        for world in rawWorlds {
            var usedPackIDsByID: [String: PackIdentity] = [:]
            var unresolvedReferences: [ContentPackReference] = []

            for reference in world.packReferences {
                let referenceIdentity = PackIdentity(
                    type: reference.type,
                    uuid: reference.uuid,
                    version: reference.version,
                    fallbackName: reference.name,
                    fallbackLocationHint: world.folderName
                )
                let resolvedID = logicalPacksByID[referenceIdentity.canonicalKey]?.id

                if let resolvedID {
                    usedPackIDsByID[resolvedID.id] = resolvedID
                } else {
                    unresolvedReferences.append(reference)
                }

                worldRelationships.append(
                    WorldPackRelationship(
                        worldItemID: world.id,
                        logicalPackID: resolvedID,
                        reference: reference
                    )
                )
            }

            logicalWorlds.append(
                LogicalWorld(
                    id: world.id,
                    itemID: world.id,
                    usedPackIDs: usedPackIDsByID.values.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending },
                    unresolvedReferences: unresolvedReferences
                )
            )
        }

        logicalWorlds.sort {
            guard
                let lhs = rawItemsByID[$0.itemID],
                let rhs = rawItemsByID[$1.itemID]
            else {
                return $0.itemID.path.localizedStandardCompare($1.itemID.path) == .orderedAscending
            }

            return WorldScanner.sortItems(lhs, rhs)
        }

        if !sizesFinished {
            scanStatus = indexedItemCount == 0
                ? "No Minecraft items found."
                : "Resolving pack relationships..."
        } else {
            scanStatus = indexedItemCount == 0
                ? "No Minecraft items found."
                : "Loaded \(indexedDetailCount) items."
        }

        return SourceIndexSnapshot(
            displayItems: dedupedDisplayItems,
            rawItems: rawItems,
            logicalPacks: logicalPacks,
            logicalWorlds: logicalWorlds,
            packInstances: packInstances.sorted {
                $0.itemID.path.localizedStandardCompare($1.itemID.path) == .orderedAscending
            },
            worldPackRelationships: worldRelationships,
            indexedItemCount: indexedItemCount,
            indexedDetailCount: indexedDetailCount,
            scanStatus: scanStatus,
            isScanning: !sizesFinished,
            lastScanDate: sizesFinished ? now : nil
        )
    }

    private func buildDisplayItems(
        from rawItems: [MinecraftContentItem],
        logicalPacks: [LogicalPack],
        rawItemsByID: [URL: MinecraftContentItem]
    ) -> [MinecraftContentItem] {
        var normalizedItemIDs = Set<URL>()
        var normalizedItems: [MinecraftContentItem] = []

        for item in rawItems where item.contentType == .world {
            guard normalizedItemIDs.insert(item.id).inserted else {
                continue
            }

            normalizedItems.append(item)
        }

        for logicalPack in logicalPacks {
            guard
                let item = rawItemsByID[logicalPack.representativeItemID],
                normalizedItemIDs.insert(item.id).inserted
            else {
                continue
            }

            normalizedItems.append(item)
        }

        for item in rawItems where item.contentType == .skinPack || item.contentType == .worldTemplate {
            guard normalizedItemIDs.insert(item.id).inserted else {
                continue
            }

            normalizedItems.append(item)
        }

        return normalizedItems
    }

    private func buildRawDisplayItems(from rawItems: [MinecraftContentItem]) -> [MinecraftContentItem] {
        rawItems.sorted(by: WorldScanner.sortItems)
    }

    private func buildLogicalPacks(rawItemsByID: [URL: MinecraftContentItem]) -> [LogicalPack] {
        packItemIDsByIdentityID.keys.sorted {
            let lhs = packRepresentativeItemIDByIdentityID[$0].flatMap { rawItemsByID[$0]?.displayName } ?? ""
            let rhs = packRepresentativeItemIDByIdentityID[$1].flatMap { rawItemsByID[$0]?.displayName } ?? ""
            let nameOrder = lhs.localizedStandardCompare(rhs)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }

            return $0.localizedStandardCompare($1) == .orderedAscending
        }.compactMap { identityID in
            guard
                let identity = packIdentityValueByID[identityID],
                let representativeItemID = packRepresentativeItemIDByIdentityID[identityID],
                let representativeItem = rawItemsByID[representativeItemID],
                let instanceItemIDs = packItemIDsByIdentityID[identityID]
            else {
                return nil
            }

            let metadata = packMetadataByItemID[representativeItemID]

            return LogicalPack(
                id: identity,
                contentType: identity.type,
                displayName: representativeItem.displayName,
                uuid: metadata?.uuid,
                version: metadata?.version,
                representativeItemID: representativeItemID,
                instanceItemIDs: instanceItemIDs.sorted {
                    $0.path.localizedStandardCompare($1.path) == .orderedAscending
                },
                isSuspicious: identity.isSuspicious
            )
        }
    }

    private func packMetadata(for item: MinecraftContentItem) -> PackMetadata {
        let uuid = item.packUUID
        let version = item.packVersion

        return PackMetadata(
            uuid: uuid,
            version: version,
            identity: PackIdentity(
                type: item.contentType,
                uuid: uuid,
                version: version,
                fallbackName: item.displayName,
                fallbackLocationHint: relativePathHint(for: item)
            )
        )
    }

    private func relativePathHint(for item: MinecraftContentItem) -> String {
        item.folderURL.path.replacingOccurrences(of: folderURL.path + "/", with: "")
    }

    private func shouldPreferPackItem(_ candidate: MinecraftContentItem, over existing: MinecraftContentItem) -> Bool {
        let candidateEmbedded = isEmbeddedWorldPack(candidate)
        let existingEmbedded = isEmbeddedWorldPack(existing)

        if candidateEmbedded != existingEmbedded {
            return !candidateEmbedded
        }

        if candidate.metadataLoaded != existing.metadataLoaded {
            return candidate.metadataLoaded
        }

        if candidate.modifiedDate != existing.modifiedDate {
            return (candidate.modifiedDate ?? .distantPast) > (existing.modifiedDate ?? .distantPast)
        }

        return candidate.folderURL.path.localizedStandardCompare(existing.folderURL.path) == .orderedAscending
    }

    private func isEmbeddedWorldPack(_ item: MinecraftContentItem) -> Bool {
        item.folderURL.pathComponents.contains(MinecraftContentType.world.collectionFolderName)
    }

    private func hostWorldItemID(for packItem: MinecraftContentItem, in rawWorlds: [MinecraftContentItem]) -> URL? {
        rawWorlds.first(where: { world in
            packItem.folderURL.path.hasPrefix(world.folderURL.path + "/")
        })?.id
    }

    private func refreshTrackedPackIdentity(for item: MinecraftContentItem, previousItem: MinecraftContentItem?) {
        let previousIdentityID = packIdentityByItemID[item.id]
        let newMetadata = packMetadata(for: item)
        let newIdentity = newMetadata.identity
        let newIdentityID = newIdentity.canonicalKey

        packMetadataByItemID[item.id] = newMetadata
        packIdentityByItemID[item.id] = newIdentityID
        packIdentityValueByID[newIdentityID] = newIdentity

        if let previousIdentityID, previousIdentityID != newIdentityID {
            removePackItem(itemID: item.id, fromIdentityID: previousIdentityID)
        }

        packItemIDsByIdentityID[newIdentityID, default: []].insert(item.id)
        refreshRepresentative(forIdentityID: newIdentityID)

        if let previousItem, previousIdentityID == newIdentityID {
            guard
                let representativeItemID = packRepresentativeItemIDByIdentityID[newIdentityID],
                let currentRepresentative = itemsByID[representativeItemID]
            else {
                return
            }

            if shouldPreferPackItem(item, over: currentRepresentative) || representativeItemID == item.id {
                refreshRepresentative(forIdentityID: newIdentityID)
            } else if representativeItemID == previousItem.id {
                refreshRepresentative(forIdentityID: newIdentityID)
            }
        }
    }

    private func removePackItem(itemID: URL, fromIdentityID identityID: String) {
        guard var itemIDs = packItemIDsByIdentityID[identityID] else {
            return
        }

        itemIDs.remove(itemID)
        if itemIDs.isEmpty {
            packItemIDsByIdentityID[identityID] = nil
            packRepresentativeItemIDByIdentityID[identityID] = nil
            packIdentityValueByID[identityID] = nil
        } else {
            packItemIDsByIdentityID[identityID] = itemIDs
            if packRepresentativeItemIDByIdentityID[identityID] == itemID {
                refreshRepresentative(forIdentityID: identityID)
            }
        }
    }

    private func refreshRepresentative(forIdentityID identityID: String) {
        guard let itemIDs = packItemIDsByIdentityID[identityID] else {
            packRepresentativeItemIDByIdentityID[identityID] = nil
            return
        }

        let candidateIDs = itemIDs.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }

        guard
            let firstID = candidateIDs.first,
            let firstItem = itemsByID[firstID]
        else {
            packRepresentativeItemIDByIdentityID[identityID] = nil
            return
        }

        let representative = candidateIDs.dropFirst().compactMap { itemsByID[$0] }.reduce(firstItem) { current, candidate in
            shouldPreferPackItem(candidate, over: current) ? candidate : current
        }

        packRepresentativeItemIDByIdentityID[identityID] = representative.id
    }

    private func isLogicalPackType(_ contentType: MinecraftContentType) -> Bool {
        contentType == .behaviorPack || contentType == .resourcePack
    }
}
