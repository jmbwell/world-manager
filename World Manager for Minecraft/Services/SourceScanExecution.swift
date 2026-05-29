//
//  SourceScanExecution.swift
//  World Manager for Minecraft
//
//  Created by OpenAI Codex on 2026-05-29.
//

import Foundation

@MainActor
protocol SourceScanSessionHosting: AnyObject {
    func source(withID sourceID: URL) -> MinecraftSource?
    func updateSource(_ sourceID: URL, mutate: (inout MinecraftSource) -> Void)
    func applySnapshot(_ snapshot: SourceIndexSnapshot, to sourceID: URL)
    func persistSourceIfAvailable(withID sourceID: URL)
    func logScanStage(_ stage: String, elapsed: TimeInterval, context: String, itemCount: Int)
}

enum SourceScanExecutor {
    static func execute(
        sourceID: URL,
        mode: SourceDiscoveryMode,
        source: MinecraftSource,
        host: SourceScanSessionHosting,
        sourceAccessMethod: SourceAccessMethod,
        notificationService: ScanNotificationServicing,
        enrichmentWorkerCount: Int,
        sizeWorkerCount: Int,
        minimumVisibleScanDuration: TimeInterval
    ) async {
        var workerTasks: [Task<Void, Never>] = []
        var sizeWorkerTasks: [Task<Void, Never>] = []
        let scanStartTime = Date()
        defer {
            workerTasks.forEach { $0.cancel() }
            sizeWorkerTasks.forEach { $0.cancel() }
        }

        let previousSource = source
        let performanceContext = SourceScanPolicy.performanceContext(for: source)

        await host.updateSource(sourceID) { source in
            source.isScanning = true
            source.scanError = nil
            source.scanDiagnostic = nil
            source.scanStatus = SourceScanPolicy.initialStatus(for: source, mode: mode)
            source.scanProgress = nil
            source.indexedItemCount = 0
            source.indexedDetailCount = 0
            source.previewLoadedCount = 0
            source.sizeLoadedCount = 0
        }

        await host.updateSource(sourceID) { source in
            source.accessDescriptor = sourceAccessMethod.accessDescriptor(for: source)
        }
        let currentAvailability = await sourceAccessMethod.availability(for: source)
        await host.updateSource(sourceID) { source in
            source.availability = currentAvailability
        }

        let scanContextURL = source.folderURL
        await WorldScanner.beginScanSession(for: scanContextURL)
        defer {
            Task.detached(priority: .utility) {
                await WorldScanner.endScanSession(for: scanContextURL)
            }
        }

        await host.updateSource(sourceID) { source in
            source.availability = .available
            source.scanStatus = SourceScanPolicy.scanningLibraryStatus(for: source, mode: mode)
        }

        do {
            let index = SourceIndexActor(sourceID: sourceID, folderURL: scanContextURL)
            let enrichmentQueue = EnrichmentWorkQueue()
            let resolvedEnrichmentWorkerCount = source.origin.kind == .connectedDevice ? 1 : enrichmentWorkerCount
            let resolvedSizeWorkerCount = source.origin.kind == .connectedDevice ? 1 : sizeWorkerCount
            workerTasks = (0..<resolvedEnrichmentWorkerCount).map { _ in
                Task.detached(priority: .utility) {
                    while let item = await enrichmentQueue.next() {
                        guard !Task.isCancelled else {
                            return
                        }

                        let enrichedItem = await sourceAccessMethod.enrich(item, for: source)
                        if let snapshot = await index.applyEnrichedItem(enrichedItem) {
                            await host.applySnapshot(snapshot, to: sourceID)
                        }
                    }
                }
            }
            let discoveryStream = AsyncThrowingStream<MinecraftContentItem, Error> { continuation in
                let discoveryTask = Task.detached(priority: .userInitiated) {
                    do {
                        try await sourceAccessMethod.discoverItems(for: source, mode: mode) { item in
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

            let previousItemsByID = Dictionary(uniqueKeysWithValues: previousSource.rawItems.map { ($0.id, $0) })
            let previousSnapshotByItemID = Dictionary(
                uniqueKeysWithValues: (previousSource.snapshot?.itemSnapshots ?? []).map { ($0.id, $0) }
            )
            let shouldReconcileFromCache = mode == .reconcile && previousSource.hasCachedContent

            var discoveredCount = 0
            var discoveredCollectionNames = Set<String>()
            let discoveryStartTime = Date()

            for try await item in discoveryStream {
                guard !Task.isCancelled else {
                    break
                }

                discoveredCount += 1
                discoveredCollectionNames.insert(item.collectionRootURL.lastPathComponent)
                let itemForIndex: MinecraftContentItem
                if shouldReconcileFromCache,
                   let cachedItem = previousItemsByID[item.id],
                   SourceScanPolicy.shouldReuseCachedItem(
                    cachedItem,
                    forDiscoveredItem: item,
                    source: source,
                    previousSnapshot: previousSnapshotByItemID[item.id]
                   ) {
                    itemForIndex = cachedItem
                } else {
                    itemForIndex = item
                }

                if let snapshot = await index.addDiscoveredItem(
                    itemForIndex,
                    discoveredCount: discoveredCount
                ) {
                    await host.applySnapshot(snapshot, to: sourceID)
                }
                if itemForIndex.id == item.id, itemForIndex.metadataLoaded == false {
                    await enrichmentQueue.enqueue(item)
                }
            }

            if mode == .reconcile, source.origin.kind == .connectedDevice {
                let cachedItemsByCollection = Dictionary(grouping: previousSource.rawItems) { item in
                    item.collectionRootURL.lastPathComponent
                }

                for (collectionName, cachedItems) in cachedItemsByCollection {
                    guard !cachedItems.isEmpty else {
                        continue
                    }

                    guard !discoveredCollectionNames.contains(collectionName) else {
                        continue
                    }

                    for cachedItem in cachedItems {
                        discoveredCount += 1
                        if let snapshot = await index.addDiscoveredItem(
                            cachedItem,
                            discoveredCount: discoveredCount
                        ) {
                            await host.applySnapshot(snapshot, to: sourceID)
                        }
                    }
                }
            }

            await host.logScanStage(
                "Discovery",
                elapsed: Date().timeIntervalSince(discoveryStartTime),
                context: performanceContext,
                itemCount: discoveredCount
            )

            if let snapshot = await index.markDiscoveryFinished() {
                await host.applySnapshot(snapshot, to: sourceID)
            }
            await enrichmentQueue.finish()
            let enrichmentStartTime = Date()

            for workerTask in workerTasks {
                await workerTask.value
            }

            await host.logScanStage(
                "Enrichment",
                elapsed: Date().timeIntervalSince(enrichmentStartTime),
                context: performanceContext,
                itemCount: discoveredCount
            )

            if let snapshot = await index.markMetadataFinished() {
                await host.applySnapshot(snapshot, to: sourceID)
            }
            await host.persistSourceIfAvailable(withID: sourceID)

            let previewStageStartTime = Date()
            let previewSeedItems = await index.currentItems()
            let previewItems = await sourceAccessMethod.loadPreviewAssets(
                for: previewSeedItems.filter { !$0.previewLoaded },
                in: source
            )
            for previewItem in previewItems {
                if let snapshot = await index.applyPreviewItem(previewItem) {
                    await host.applySnapshot(snapshot, to: sourceID)
                }
            }

            await host.logScanStage(
                "Previews",
                elapsed: Date().timeIntervalSince(previewStageStartTime),
                context: performanceContext,
                itemCount: discoveredCount
            )

            if let snapshot = await index.markPreviewsFinished() {
                await host.applySnapshot(snapshot, to: sourceID)
            }
            await host.persistSourceIfAvailable(withID: sourceID)

            if source.origin.kind == .connectedDevice {
                try await finishConnectedDeviceScan(
                    sourceID: sourceID,
                    source: source,
                    host: host,
                    sourceAccessMethod: sourceAccessMethod,
                    notificationService: notificationService,
                    index: index,
                    discoveredCount: discoveredCount,
                    scanStartTime: scanStartTime,
                    scanContextURL: scanContextURL,
                    performanceContext: performanceContext,
                    minimumVisibleScanDuration: minimumVisibleScanDuration
                )
                return
            }

            let sizeQueue = EnrichmentWorkQueue()
            sizeWorkerTasks = (0..<resolvedSizeWorkerCount).map { _ in
                Task.detached(priority: .utility) {
                    while let item = await sizeQueue.next() {
                        guard !Task.isCancelled else {
                            return
                        }

                        let sizedItem = await sourceAccessMethod.loadSize(for: item, in: source)
                        if let snapshot = await index.applySizedItem(sizedItem) {
                            await host.applySnapshot(snapshot, to: sourceID)
                        }
                    }
                }
            }
            for item in await index.currentItems() where !item.sizeLoaded {
                await sizeQueue.enqueue(item)
            }
            await sizeQueue.finish()
            let sizeStageStartTime = Date()

            for sizeWorkerTask in sizeWorkerTasks {
                await sizeWorkerTask.value
            }

            await host.logScanStage(
                "Size",
                elapsed: Date().timeIntervalSince(sizeStageStartTime),
                context: performanceContext,
                itemCount: discoveredCount
            )

            try await finishScan(
                sourceID: sourceID,
                source: source,
                host: host,
                notificationService: notificationService,
                index: index,
                discoveredCount: discoveredCount,
                scanStartTime: scanStartTime,
                scanContextURL: scanContextURL,
                performanceContext: performanceContext,
                minimumVisibleScanDuration: minimumVisibleScanDuration
            )
        } catch {
            await host.updateSource(sourceID) { source in
                if SourceScanRecovery.shouldPreservePartialResults(currentSource: source, previousSource: previousSource) {
                    source.scanStatus = source.indexedItemCount == 0
                        ? previousSource.scanStatus
                        : "Loaded \(source.indexedDetailCount) items."
                    source.scanDiagnostic = Task.isCancelled
                        ? "Showing the most recent partial scan results."
                        : "Showing the most recent partial scan results after the scan stopped early."
                    if source.origin.kind == .localFolder, !source.rawItems.isEmpty {
                        source.snapshot = SourceScanPolicy.buildSnapshot(for: source, scanRootURL: scanContextURL)
                    }
                } else {
                    SourceScanRecovery.restoreIndexedState(from: previousSource, into: &source)
                }
                source.availability = Task.isCancelled
                    ? previousSource.availability
                    : SourceScanPolicy.availabilityStatus(for: error, defaultingTo: previousSource.availability)
                source.scanError = Task.isCancelled
                    ? previousSource.scanError
                    : SourceScanPolicy.friendlyError(for: error, source: source)
                source.scanDiagnostic = Task.isCancelled
                    ? source.scanDiagnostic
                    : (source.scanDiagnostic ?? error.localizedDescription)
                if source.scanStatus.isEmpty {
                    source.scanStatus = previousSource.scanStatus
                }
                source.scanProgress = nil
                source.isScanning = false
            }
            await host.persistSourceIfAvailable(withID: sourceID)
        }
    }

    private static func finishConnectedDeviceScan(
        sourceID: URL,
        source: MinecraftSource,
        host: SourceScanSessionHosting,
        sourceAccessMethod: SourceAccessMethod,
        notificationService: ScanNotificationServicing,
        index: SourceIndexActor,
        discoveredCount: Int,
        scanStartTime: Date,
        scanContextURL: URL,
        performanceContext: String,
        minimumVisibleScanDuration: TimeInterval
    ) async throws {
        let sizeStageStartTime = Date()
        let sizeSeedItems = await index.currentItems()
        let sizedItems = await sourceAccessMethod.loadSizeAssets(
            for: sizeSeedItems.filter { !$0.sizeLoaded },
            in: source
        )
        for sizedItem in sizedItems {
            if let snapshot = await index.applySizedItem(sizedItem) {
                await host.applySnapshot(snapshot, to: sourceID)
            }
        }

        await host.logScanStage(
            "Size",
            elapsed: Date().timeIntervalSince(sizeStageStartTime),
            context: performanceContext,
            itemCount: discoveredCount
        )

        try await finishScan(
            sourceID: sourceID,
            source: source,
            host: host,
            notificationService: notificationService,
            index: index,
            discoveredCount: discoveredCount,
            scanStartTime: scanStartTime,
            scanContextURL: scanContextURL,
            performanceContext: performanceContext,
            minimumVisibleScanDuration: minimumVisibleScanDuration
        )
    }

    private static func finishScan(
        sourceID: URL,
        source: MinecraftSource,
        host: SourceScanSessionHosting,
        notificationService: ScanNotificationServicing,
        index: SourceIndexActor,
        discoveredCount: Int,
        scanStartTime: Date,
        scanContextURL: URL,
        performanceContext: String,
        minimumVisibleScanDuration: TimeInterval
    ) async throws {
        let elapsedScanTime = Date().timeIntervalSince(scanStartTime)
        if elapsedScanTime < minimumVisibleScanDuration {
            try await Task.sleep(
                for: .seconds(minimumVisibleScanDuration - elapsedScanTime)
            )
        }

        if let snapshot = await index.finishScan() {
            await host.applySnapshot(snapshot, to: sourceID)
        }
        await host.updateSource(sourceID) { source in
            if source.origin.kind == .localFolder {
                source.snapshot = SourceScanPolicy.buildSnapshot(for: source, scanRootURL: scanContextURL)
            } else {
                source.snapshot = nil
            }
        }
        await host.persistSourceIfAvailable(withID: sourceID)
        await host.logScanStage(
            "Total",
            elapsed: Date().timeIntervalSince(scanStartTime),
            context: performanceContext,
            itemCount: discoveredCount
        )

        if let completedSource = await host.source(withID: sourceID) {
            await notificationService.notifyScanCompleted(
                for: completedSource,
                duration: Date().timeIntervalSince(scanStartTime)
            )
        }
        _ = source
    }
}

struct PackMetadata {
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

struct SourceIndexSnapshot {
    let displayItems: [MinecraftContentItem]
    let rawItems: [MinecraftContentItem]
    let logicalPacks: [LogicalPack]
    let logicalWorlds: [LogicalWorld]
    let packInstances: [PackInstance]
    let worldPackRelationships: [WorldPackRelationship]
    let indexedItemCount: Int
    let indexedDetailCount: Int
    let previewLoadedCount: Int
    let sizeLoadedCount: Int
    let scanStatus: String
    let scanProgress: Double?
    let isScanning: Bool
    let previewStageElapsed: TimeInterval?
    let previewStageDuration: TimeInterval?
    let sizeStageElapsed: TimeInterval?
    let sizeStageDuration: TimeInterval?
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
    private var previewLoadedCount = 0
    private var sizeLoadedCount = 0
    private var discoveryFinished = false
    private var metadataFinished = false
    private var previewsFinished = false
    private var sizesFinished = false
    private var previewStageStartedAt: Date?
    private var previewStageFinishedAt: Date?
    private var sizeStageStartedAt: Date?
    private var sizeStageFinishedAt: Date?
    private var lastPublishedAt: Date?

    init(sourceID: URL, folderURL: URL) {
        self.sourceID = sourceID
        self.folderURL = folderURL
    }

    func addDiscoveredItem(_ item: MinecraftContentItem, discoveredCount: Int) -> SourceIndexSnapshot? {
        orderedItemIDs.append(item.id)
        itemsByID[item.id] = item
        indexedItemCount = discoveredCount
        if item.metadataLoaded {
            indexedDetailCount += 1
        }
        if item.previewLoaded {
            previewLoadedCount += 1
        }
        if item.sizeLoaded {
            sizeLoadedCount += 1
        }
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

        let wasSizeLoaded = current.sizeLoaded
        current.sizeBytes = item.sizeBytes
        current.sizeLoaded = item.sizeLoaded
        itemsByID[item.id] = current
        if item.sizeLoaded, wasSizeLoaded != true {
            sizeLoadedCount += 1
        }
        return snapshotIfNeeded()
    }

    func applyPreviewItem(_ item: MinecraftContentItem) -> SourceIndexSnapshot? {
        let previous = itemsByID[item.id]
        itemsByID[item.id] = item
        if item.previewLoaded, previous?.previewLoaded != true {
            previewLoadedCount += 1
        }

        return snapshotIfNeeded()
    }

    func markDiscoveryFinished() -> SourceIndexSnapshot? {
        discoveryFinished = true
        return buildSnapshot(force: true)
    }

    func markMetadataFinished() -> SourceIndexSnapshot? {
        discoveryFinished = true
        metadataFinished = true
        previewStageStartedAt = previewStageStartedAt ?? Date()
        return buildSnapshot(force: true)
    }

    func markPreviewsFinished() -> SourceIndexSnapshot? {
        discoveryFinished = true
        metadataFinished = true
        previewsFinished = true
        let now = Date()
        previewStageStartedAt = previewStageStartedAt ?? now
        previewStageFinishedAt = previewStageFinishedAt ?? now
        sizeStageStartedAt = sizeStageStartedAt ?? now
        return buildSnapshot(force: true)
    }

    func finishScan() -> SourceIndexSnapshot? {
        discoveryFinished = true
        metadataFinished = true
        previewsFinished = true
        sizesFinished = true
        let now = Date()
        previewStageFinishedAt = previewStageFinishedAt ?? now
        sizeStageStartedAt = sizeStageStartedAt ?? now
        sizeStageFinishedAt = sizeStageFinishedAt ?? now
        return buildSnapshot(force: true)
    }

    func currentItems() -> [MinecraftContentItem] {
        orderedItemIDs.compactMap { itemsByID[$0] }
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
        let metadataFraction = progressFraction(completed: indexedDetailCount, total: indexedItemCount)
        let previewFraction = progressFraction(completed: previewLoadedCount, total: indexedItemCount)
        let sizeFraction = progressFraction(completed: sizeLoadedCount, total: indexedItemCount)
        let previewStageElapsed = previewStageStartedAt.map { now.timeIntervalSince($0) }
        let previewStageDuration = previewStageStartedAt.flatMap { startedAt in
            previewStageFinishedAt.map { $0.timeIntervalSince(startedAt) }
        }
        let sizeStageElapsed = sizeStageStartedAt.map { now.timeIntervalSince($0) }
        let sizeStageDuration = sizeStageStartedAt.flatMap { startedAt in
            sizeStageFinishedAt.map { $0.timeIntervalSince(startedAt) }
        }
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
                previewLoadedCount: previewLoadedCount,
                sizeLoadedCount: sizeLoadedCount,
                scanStatus: scanStatus,
                scanProgress: nil,
                isScanning: true,
                previewStageElapsed: previewStageElapsed,
                previewStageDuration: previewStageDuration,
                sizeStageElapsed: sizeStageElapsed,
                sizeStageDuration: sizeStageDuration,
                lastScanDate: nil
            )
        }

        if !metadataFinished {
            scanStatus = indexedItemCount == 0
                ? "No Minecraft items found."
                : "Loading metadata for \(indexedDetailCount) of \(indexedItemCount) items..."

            return SourceIndexSnapshot(
                displayItems: dedupedDisplayItems,
                rawItems: rawItems,
                logicalPacks: logicalPacks,
                logicalWorlds: [],
                packInstances: [],
                worldPackRelationships: [],
                indexedItemCount: indexedItemCount,
                indexedDetailCount: indexedDetailCount,
                previewLoadedCount: previewLoadedCount,
                sizeLoadedCount: sizeLoadedCount,
                scanStatus: scanStatus,
                scanProgress: progressAfterDiscovery(metadataFraction),
                isScanning: true,
                previewStageElapsed: previewStageElapsed,
                previewStageDuration: previewStageDuration,
                sizeStageElapsed: sizeStageElapsed,
                sizeStageDuration: sizeStageDuration,
                lastScanDate: nil
            )
        }

        if !previewsFinished {
            if indexedItemCount == 0 {
                scanStatus = "No Minecraft items found."
            } else if previewLoadedCount == 0 {
                scanStatus = "Preparing previews..."
            } else {
                scanStatus = "Loading previews for \(previewLoadedCount) of \(indexedItemCount) items..."
            }

            return SourceIndexSnapshot(
                displayItems: dedupedDisplayItems,
                rawItems: rawItems,
                logicalPacks: logicalPacks,
                logicalWorlds: [],
                packInstances: [],
                worldPackRelationships: [],
                indexedItemCount: indexedItemCount,
                indexedDetailCount: indexedDetailCount,
                previewLoadedCount: previewLoadedCount,
                sizeLoadedCount: sizeLoadedCount,
                scanStatus: scanStatus,
                scanProgress: progressAfterMetadata(previewFraction),
                isScanning: true,
                previewStageElapsed: previewStageElapsed,
                previewStageDuration: previewStageDuration,
                sizeStageElapsed: sizeStageElapsed,
                sizeStageDuration: sizeStageDuration,
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
            if indexedItemCount == 0 {
                scanStatus = "No Minecraft items found."
            } else if sizeLoadedCount == 0 {
                scanStatus = "Preparing size calculations..."
            } else {
                scanStatus = "Calculating sizes for \(sizeLoadedCount) of \(indexedItemCount) items..."
            }
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
            previewLoadedCount: previewLoadedCount,
            sizeLoadedCount: sizeLoadedCount,
            scanStatus: scanStatus,
            scanProgress: sizesFinished ? nil : progressAfterPreviews(sizeFraction),
            isScanning: !sizesFinished,
            previewStageElapsed: previewStageElapsed,
            previewStageDuration: previewStageDuration,
            sizeStageElapsed: sizeStageElapsed,
            sizeStageDuration: sizeStageDuration,
            lastScanDate: sizesFinished ? now : nil
        )
    }

    private func progressFraction(completed: Int, total: Int) -> Double {
        guard total > 0 else {
            return 1
        }

        return min(max(Double(completed) / Double(total), 0), 1)
    }

    private func progressAfterDiscovery(_ metadataFraction: Double) -> Double {
        0.1 + (metadataFraction * 0.55)
    }

    private func progressAfterMetadata(_ previewFraction: Double) -> Double {
        0.65 + (previewFraction * 0.1)
    }

    private func progressAfterPreviews(_ sizeFraction: Double) -> Double {
        0.75 + (sizeFraction * 0.25)
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

    private func refreshTrackedPackIdentity(
        for item: MinecraftContentItem,
        previousItem: MinecraftContentItem?
    ) {
        let metadata = PackMetadata(
            uuid: item.packUUID,
            version: item.packVersion,
            identity: PackIdentity(
                type: item.contentType,
                uuid: item.packUUID,
                version: item.packVersion,
                fallbackName: item.displayName,
                fallbackLocationHint: item.folderURL.path.replacingOccurrences(of: folderURL.path + "/", with: "")
            )
        )
        let newIdentityID = metadata.identity.canonicalKey

        packMetadataByItemID[item.id] = metadata
        packIdentityValueByID[newIdentityID] = metadata.identity

        if let previousIdentityID = packIdentityByItemID[item.id], previousIdentityID != newIdentityID {
            packItemIDsByIdentityID[previousIdentityID]?.remove(item.id)
            if packItemIDsByIdentityID[previousIdentityID]?.isEmpty == true {
                packItemIDsByIdentityID[previousIdentityID] = nil
                packRepresentativeItemIDByIdentityID[previousIdentityID] = nil
            } else if packRepresentativeItemIDByIdentityID[previousIdentityID] == item.id {
                packRepresentativeItemIDByIdentityID[previousIdentityID] = bestRepresentativeItemID(
                    within: packItemIDsByIdentityID[previousIdentityID] ?? [],
                    currentRepresentativeID: nil
                )
            }
        }

        packIdentityByItemID[item.id] = newIdentityID
        packItemIDsByIdentityID[newIdentityID, default: []].insert(item.id)
        packRepresentativeItemIDByIdentityID[newIdentityID] = bestRepresentativeItemID(
            within: packItemIDsByIdentityID[newIdentityID] ?? [],
            currentRepresentativeID: packRepresentativeItemIDByIdentityID[newIdentityID]
        )

        if previousItem == nil, packRepresentativeItemIDByIdentityID[newIdentityID] == nil {
            packRepresentativeItemIDByIdentityID[newIdentityID] = item.id
        }
    }

    private func bestRepresentativeItemID(
        within itemIDs: Set<URL>,
        currentRepresentativeID: URL?
    ) -> URL? {
        var chosenID = currentRepresentativeID

        for itemID in itemIDs {
            guard let candidate = itemsByID[itemID] else {
                continue
            }

            guard let existingID = chosenID, let existing = itemsByID[existingID] else {
                chosenID = itemID
                continue
            }

            if shouldPreferPackItem(candidate, over: existing) {
                chosenID = itemID
            }
        }

        return chosenID
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

        if (candidate.iconURL != nil) != (existing.iconURL != nil) {
            return candidate.iconURL != nil
        }

        if candidate.previewLoaded != existing.previewLoaded {
            return candidate.previewLoaded
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

    private func isLogicalPackType(_ contentType: MinecraftContentType) -> Bool {
        contentType == .behaviorPack || contentType == .resourcePack
    }
}
