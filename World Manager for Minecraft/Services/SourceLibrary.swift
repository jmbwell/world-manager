//
//  SourceLibrary.swift
//  World Manager for Minecraft
//
//  Created by John Burwell on 2026-05-25.
//

import Combine
import Foundation
import OSLog

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
    let detail: String?
    let revealURL: URL?
}

struct ConnectedDeviceSidebarEntry: Identifiable, Hashable {
    let device: ConnectedDevice
    let containers: [DeviceAppContainer]
    let matchedSourceID: URL?
    let discoveryErrorDescription: String?

    var id: String { device.id }

    var minecraftContainer: DeviceAppContainer? {
        containers.first(where: { $0.appID == "com.mojang.minecraftpe" })
            ?? containers.first(where: { $0.minecraftFolderRelativePath != nil })
    }

    var hasMinecraftContainer: Bool {
        minecraftContainer != nil
    }
}

private struct CachedConnectedDeviceDiscovery {
    let device: ConnectedDevice
    let containers: [DeviceAppContainer]
    let discoveryErrorDescription: String?
    let refreshedAt: Date
}

@MainActor
final class SourceLibrary: ObservableObject {
    private static let enrichmentWorkerCount = 4
    private static let sizeWorkerCount = 2
    private static let minimumVisibleScanDuration: TimeInterval = 0.8
    private static let automaticSyncDebounce: TimeInterval = 0.75
    private static let localSourceRefreshInterval: TimeInterval = 4.0
    private static let connectedDeviceRefreshInterval: TimeInterval = 2.0
    private static let connectedDeviceRefreshIntervalWhileScanning: TimeInterval = 5.0
    private static let footerRefreshDebounce: TimeInterval = 0.15
    private static let usbConnectedDeviceAutoRefreshInterval: TimeInterval = 45.0
    private static let networkConnectedDeviceAutoRefreshInterval: TimeInterval = 120.0
    private static let usbConnectedDeviceDiscoveryCacheTTL: TimeInterval = 60.0
    private static let networkConnectedDeviceDiscoveryCacheTTL: TimeInterval = 180.0
    private static let performanceLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "WorldManagerForMinecraft",
        category: "ConnectedDevicePerformance"
    )

    @Published var sources: [MinecraftSource] = []
    @Published private(set) var connectedDevices: [ConnectedDeviceSidebarEntry] = []
    @Published private(set) var sidebarFooterState = SidebarFooterState(
        style: .idle,
        title: "",
        subtitle: nil,
        detail: nil,
        revealURL: nil
    )
    @Published private(set) var isRestoringPersistedSources = true

    private var scanTasks: [URL: Task<Void, Never>] = [:]
    private var automaticSyncTasks: [URL: Task<Void, Never>] = [:]
    private var connectedDeviceRefreshTask: Task<Void, Never>?
    private var localSourceRefreshTask: Task<Void, Never>?
    private var footerResetTask: Task<Void, Never>?
    private var footerRefreshTask: Task<Void, Never>?
    private let persistenceStore: SourcePersistenceStore
    private let sourceAccessMethod: SourceAccessMethod
    private let connectedDeviceAccessMethod: ConnectedDeviceSourceAccessMethod?
    private let notificationService: ScanNotificationServicing
    private let connectedDeviceSourceFactory = ConnectedDeviceSourceFactory()
    private var lastMatchedConnectedSourceIDs: Set<URL> = []
    private var cachedDeviceDiscoveryByUDID: [String: CachedConnectedDeviceDiscovery] = [:]
    private var isShuttingDown = false

    init(
        persistenceStore: SourcePersistenceStore = .shared,
        sourceAccessMethod: SourceAccessMethod = LocalFolderSourceAccess(),
        connectedDeviceAccessMethod: ConnectedDeviceSourceAccessMethod? = nil,
        notificationService: ScanNotificationServicing? = nil
    ) {
        self.persistenceStore = persistenceStore
        self.sourceAccessMethod = sourceAccessMethod
        self.connectedDeviceAccessMethod = connectedDeviceAccessMethod
        self.notificationService = notificationService ?? ScanNotificationService.shared

        Task { [weak self] in
            await self?.restorePersistedSources()
        }

        localSourceRefreshTask = Task { [weak self] in
            await self?.runLocalSourceRefreshLoop()
        }

        if connectedDeviceAccessMethod != nil {
            connectedDeviceRefreshTask = Task { [weak self] in
                await self?.runConnectedDeviceRefreshLoop()
            }
        }
    }

    deinit {
        connectedDeviceRefreshTask?.cancel()
        localSourceRefreshTask?.cancel()
        footerResetTask?.cancel()
        footerRefreshTask?.cancel()
        automaticSyncTasks.values.forEach { $0.cancel() }
        scanTasks.values.forEach { $0.cancel() }
    }

    var visibleSources: [MinecraftSource] {
        sources
    }

    var sidebarSources: [MinecraftSource] {
        visibleSources
    }

    func shutdown() {
        guard !isShuttingDown else {
            return
        }

        isShuttingDown = true
        connectedDeviceRefreshTask?.cancel()
        connectedDeviceRefreshTask = nil
        localSourceRefreshTask?.cancel()
        localSourceRefreshTask = nil
        footerResetTask?.cancel()
        footerResetTask = nil
        footerRefreshTask?.cancel()
        footerRefreshTask = nil

        for task in automaticSyncTasks.values {
            task.cancel()
        }
        automaticSyncTasks.removeAll()

        for task in scanTasks.values {
            task.cancel()
        }
        scanTasks.removeAll()
    }

    func shutdownGracefully(timeout: TimeInterval = 1.0) async {
        guard !isShuttingDown else {
            return
        }

        await persistVisibleSourcesForShutdown()
        shutdown()
        try? await Task.sleep(for: .seconds(timeout))
    }

    func addSource(at url: URL) -> URL {
        let normalizedURL = url.standardizedFileURL
        let bookmarkData = securityScopedBookmarkData(for: normalizedURL)

        if sources.contains(where: { $0.id == normalizedURL }) {
            updateSource(normalizedURL) { source in
                if source.bookmarkData == nil {
                    source.bookmarkData = bookmarkData
                }
                source.accessDescriptor = sourceAccessMethod.accessDescriptor(for: source)
            }
            startScan(for: normalizedURL, mode: .fullScan)
            return normalizedURL
        }

        let source = MinecraftSource(
            folderURL: normalizedURL,
            bookmarkData: bookmarkData,
            accessDescriptor: SourceAccessDescriptor(
                accessorIdentifier: LocalFolderSourceAccess().accessorIdentifier,
                kind: .localFolder,
                capabilities: .localFolder,
                refreshStrategy: .eagerFullScan
            )
        )
        return addSource(source, shouldPersist: true, shouldScan: true)
    }

    @discardableResult
    func addSource(_ source: MinecraftSource, shouldPersist: Bool = false, shouldScan: Bool = true) -> URL {
        if sources.contains(where: { $0.id == source.id }) {
            updateSource(source.id) { existingSource in
                existingSource.origin = source.origin
                existingSource.accessDescriptor = source.accessDescriptor
                existingSource.availability = source.availability
                if existingSource.bookmarkData == nil {
                    existingSource.bookmarkData = source.bookmarkData
                }
                if existingSource.displayName.isEmpty {
                    existingSource.displayName = source.displayName
                }
            }
        } else {
            var resolvedSource = source
            resolvedSource.accessDescriptor = sourceAccessMethod.accessDescriptor(for: resolvedSource)
            sources.append(resolvedSource)
            sources.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        }

        if shouldPersist {
            persistSourceIfAvailable(withID: source.id)
        }
        if shouldScan {
            startScan(for: source.id, mode: .fullScan)
        }

        return source.id
    }

    func source(withID sourceID: URL) -> MinecraftSource? {
        sources.first(where: { $0.id == sourceID })
    }

    func rescanSource(withID sourceID: URL) {
        startScan(for: sourceID, mode: .fullScan)
    }

    func listContents(for item: MinecraftContentItem, in source: MinecraftSource) async throws -> [DirectoryPreviewEntry] {
        try await sourceAccessMethod.listItemContents(for: item, in: source)
    }

    func materializeItem(_ item: MinecraftContentItem, in source: MinecraftSource) async throws -> URL {
        try await sourceAccessMethod.materializeItem(for: item, in: source)
    }

    func removeSource(withID sourceID: URL) {
        let removedSource = source(withID: sourceID)
        scanTasks[sourceID]?.cancel()
        scanTasks[sourceID] = nil
        sources.removeAll { $0.id == sourceID }
        deletePersistedSource(withID: sourceID)
        if let removedSource {
            purgeCachedArtifacts(for: removedSource)
        }
        refreshSidebarFooterState()
    }

    func setItemActionInProgress(_ description: String) {
        cancelFooterReset()
        sidebarFooterState = SidebarFooterState(
            style: .inProgress,
            title: description,
            subtitle: nil,
            detail: nil,
            revealURL: nil
        )
    }

    func setItemActionFailure(_ message: String) {
        sidebarFooterState = SidebarFooterState(
            style: .failure,
            title: "Action Failed",
            subtitle: message,
            detail: nil,
            revealURL: nil
        )
        scheduleFooterReset()
    }

    func setItemActionSuccess(title: String, subtitle: String, revealURL: URL?) {
        sidebarFooterState = SidebarFooterState(
            style: .success,
            title: title,
            subtitle: subtitle,
            detail: nil,
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

    private func startScan(for sourceID: URL, mode: SourceDiscoveryMode) {
        guard !isShuttingDown else {
            return
        }

        automaticSyncTasks[sourceID]?.cancel()
        automaticSyncTasks[sourceID] = nil
        scanTasks[sourceID]?.cancel()

        let task = Task { [weak self] in
            guard let self else {
                return
            }

            await self.scanSource(withID: sourceID, mode: mode)
        }

        scanTasks[sourceID] = task
    }

    private var hasActiveScan: Bool {
        sources.contains(where: \.isScanning)
    }

    private var hasActiveConnectedDeviceScan: Bool {
        sources.contains { $0.isScanning && $0.origin.kind == .connectedDevice }
    }

    private func scanSource(withID sourceID: URL, mode: SourceDiscoveryMode) async {
        var workerTasks: [Task<Void, Never>] = []
        var sizeWorkerTasks: [Task<Void, Never>] = []
        let scanStartTime = Date()
        defer {
            workerTasks.forEach { $0.cancel() }
            sizeWorkerTasks.forEach { $0.cancel() }
            scanTasks[sourceID] = nil
        }

        guard let source = source(withID: sourceID) else {
            return
        }
        let previousSource = source
        let performanceContext = performanceContext(for: source)

        updateSource(sourceID) { source in
            source.isScanning = true
            source.scanError = nil
            source.scanDiagnostic = nil
            source.scanStatus = initialScanStatus(for: source, mode: mode)
            source.scanProgress = nil
            source.indexedItemCount = 0
            source.indexedDetailCount = 0
            source.previewLoadedCount = 0
            source.sizeLoadedCount = 0
        }
        refreshSidebarFooterState()

        updateSource(sourceID) { source in
            source.accessDescriptor = sourceAccessMethod.accessDescriptor(for: source)
        }
        let currentAvailability = await sourceAccessMethod.availability(for: source)
        updateSource(sourceID) { source in
            source.availability = currentAvailability
        }

        let scanContextURL = source.folderURL
        await WorldScanner.beginScanSession(for: scanContextURL)
        defer {
            Task.detached(priority: .utility) {
                await WorldScanner.endScanSession(for: scanContextURL)
            }
        }

        updateSource(sourceID) { source in
            source.availability = .available
            source.scanStatus = scanningLibraryStatus(for: source, mode: mode)
        }
        refreshSidebarFooterState()

        do {
            let index = SourceIndexActor(sourceID: sourceID, folderURL: scanContextURL)
            let enrichmentQueue = EnrichmentWorkQueue()
            let enrichmentWorkerCount = source.origin.kind == .connectedDevice ? 1 : Self.enrichmentWorkerCount
            let sizeWorkerCount = source.origin.kind == .connectedDevice ? 1 : Self.sizeWorkerCount
            workerTasks = (0..<enrichmentWorkerCount).map { _ in
                Task.detached(priority: .utility) { [weak self] in
                    guard let library = self else {
                        return
                    }

                    while let item = await enrichmentQueue.next() {
                        guard !Task.isCancelled else {
                            return
                        }

                        let enrichedItem = await library.sourceAccessMethod.enrich(item, for: source)
                        if let snapshot = await index.applyEnrichedItem(enrichedItem) {
                            await MainActor.run {
                                library.applySnapshot(snapshot, to: sourceID)
                                library.scheduleSidebarFooterRefresh()
                            }
                        }
                    }
                }
            }
            let discoveryStream = AsyncThrowingStream<MinecraftContentItem, Error> { continuation in
                let accessMethod = sourceAccessMethod
                let discoveryTask = Task.detached(priority: .userInitiated) {
                    do {
                        _ = try await accessMethod.discoverItems(for: source, mode: mode) { item in
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
                   shouldReuseCachedItem(
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
                    applySnapshot(snapshot, to: sourceID)
                }
                scheduleSidebarFooterRefresh()

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
                            applySnapshot(snapshot, to: sourceID)
                        }
                    }
                }
            }

            logScanStage(
                "Discovery",
                elapsed: Date().timeIntervalSince(discoveryStartTime),
                context: performanceContext,
                itemCount: discoveredCount
            )

            if let snapshot = await index.markDiscoveryFinished() {
                applySnapshot(snapshot, to: sourceID)
            }
            refreshSidebarFooterState()

            await enrichmentQueue.finish()
            let enrichmentStartTime = Date()

            for workerTask in workerTasks {
                await workerTask.value
            }

            logScanStage(
                "Enrichment",
                elapsed: Date().timeIntervalSince(enrichmentStartTime),
                context: performanceContext,
                itemCount: discoveredCount
            )

            if let snapshot = await index.markMetadataFinished() {
                applySnapshot(snapshot, to: sourceID)
            }
            persistSourceIfAvailable(withID: sourceID)
            refreshSidebarFooterState()

            let previewStageStartTime = Date()
            let previewSeedItems = await index.currentItems()
            let previewItems = await sourceAccessMethod.loadPreviewAssets(
                for: previewSeedItems.filter { !$0.previewLoaded },
                in: source
            )
            for previewItem in previewItems {
                if let snapshot = await index.applyPreviewItem(previewItem) {
                    applySnapshot(snapshot, to: sourceID)
                    scheduleSidebarFooterRefresh()
                }
            }

            logScanStage(
                "Previews",
                elapsed: Date().timeIntervalSince(previewStageStartTime),
                context: performanceContext,
                itemCount: discoveredCount
            )

            if let snapshot = await index.markPreviewsFinished() {
                applySnapshot(snapshot, to: sourceID)
            }
            persistSourceIfAvailable(withID: sourceID)
            refreshSidebarFooterState()

            if source.origin.kind == .connectedDevice {
                let sizeStageStartTime = Date()
                let sizeSeedItems = await index.currentItems()
                let sizedItems = await sourceAccessMethod.loadSizeAssets(
                    for: sizeSeedItems.filter { !$0.sizeLoaded },
                    in: source
                )
                for sizedItem in sizedItems {
                    if let snapshot = await index.applySizedItem(sizedItem) {
                        applySnapshot(snapshot, to: sourceID)
                        scheduleSidebarFooterRefresh()
                    }
                }

                logScanStage(
                    "Size",
                    elapsed: Date().timeIntervalSince(sizeStageStartTime),
                    context: performanceContext,
                    itemCount: discoveredCount
                )

                let elapsedScanTime = Date().timeIntervalSince(scanStartTime)
                if elapsedScanTime < Self.minimumVisibleScanDuration {
                    try? await Task.sleep(
                        for: .seconds(Self.minimumVisibleScanDuration - elapsedScanTime)
                    )
                }

                if let snapshot = await index.finishScan() {
                    applySnapshot(snapshot, to: sourceID)
                }
                updateSource(sourceID) { source in
                    if source.origin.kind == .localFolder {
                        source.snapshot = buildSnapshot(for: source, scanRootURL: scanContextURL, packMetadataByItemID: [:])
                    } else {
                        source.snapshot = nil
                    }
                }
                persistSourceIfAvailable(withID: sourceID)
                refreshSidebarFooterState()
                logScanStage(
                    "Total",
                    elapsed: Date().timeIntervalSince(scanStartTime),
                    context: performanceContext,
                    itemCount: discoveredCount
                )

                if let completedSource = self.source(withID: sourceID) {
                    await notificationService.notifyScanCompleted(
                        for: completedSource,
                        duration: Date().timeIntervalSince(scanStartTime)
                    )
                }
                return
            }

            let sizeQueue = EnrichmentWorkQueue()
            sizeWorkerTasks = (0..<sizeWorkerCount).map { _ in
                Task.detached(priority: .utility) { [weak self] in
                    guard let library = self else {
                        return
                    }

                    while let item = await sizeQueue.next() {
                        guard !Task.isCancelled else {
                            return
                        }

                        let sizedItem = await library.sourceAccessMethod.loadSize(for: item, in: source)
                        if let snapshot = await index.applySizedItem(sizedItem) {
                            await MainActor.run {
                                library.applySnapshot(snapshot, to: sourceID)
                                library.scheduleSidebarFooterRefresh()
                            }
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

            logScanStage(
                "Size",
                elapsed: Date().timeIntervalSince(sizeStageStartTime),
                context: performanceContext,
                itemCount: discoveredCount
            )

            let elapsedScanTime = Date().timeIntervalSince(scanStartTime)
            if elapsedScanTime < Self.minimumVisibleScanDuration {
                try? await Task.sleep(
                    for: .seconds(Self.minimumVisibleScanDuration - elapsedScanTime)
                )
            }

            if let snapshot = await index.finishScan() {
                applySnapshot(snapshot, to: sourceID)
            }
            updateSource(sourceID) { source in
                if source.origin.kind == .localFolder {
                    source.snapshot = buildSnapshot(for: source, scanRootURL: scanContextURL, packMetadataByItemID: [:])
                } else {
                    source.snapshot = nil
                }
            }
            persistSourceIfAvailable(withID: sourceID)
            refreshSidebarFooterState()
            logScanStage(
                "Total",
                elapsed: Date().timeIntervalSince(scanStartTime),
                context: performanceContext,
                itemCount: discoveredCount
            )

            if let completedSource = self.source(withID: sourceID) {
                await notificationService.notifyScanCompleted(
                    for: completedSource,
                    duration: Date().timeIntervalSince(scanStartTime)
                )
            }
        } catch {
            updateSource(sourceID) { source in
                if shouldPreservePartialScanContent(currentSource: source, previousSource: previousSource) {
                    source.scanStatus = source.indexedItemCount == 0
                        ? previousSource.scanStatus
                        : "Loaded \(source.indexedDetailCount) items."
                    source.scanDiagnostic = Task.isCancelled
                        ? "Showing the most recent partial scan results."
                        : "Showing the most recent partial scan results after the scan stopped early."
                    if source.origin.kind == .localFolder, !source.rawItems.isEmpty {
                        source.snapshot = buildSnapshot(
                            for: source,
                            scanRootURL: scanContextURL,
                            packMetadataByItemID: [:]
                        )
                    }
                } else {
                    restoreScannedContent(from: previousSource, into: &source)
                }
                source.availability = Task.isCancelled
                    ? previousSource.availability
                    : availabilityStatus(for: error, defaultingTo: previousSource.availability)
                source.scanError = Task.isCancelled
                    ? previousSource.scanError
                    : friendlyScanError(for: error, source: source)
                source.scanDiagnostic = Task.isCancelled
                    ? source.scanDiagnostic
                    : (source.scanDiagnostic ?? error.localizedDescription)
                if source.scanStatus.isEmpty {
                    source.scanStatus = previousSource.scanStatus
                }
                source.scanProgress = nil
                source.isScanning = false
            }
            persistSourceIfAvailable(withID: sourceID)
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

    private func restoreScannedContent(from previousSource: MinecraftSource, into source: inout MinecraftSource) {
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

    private func shouldPreservePartialScanContent(
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

    private func performanceContext(for source: MinecraftSource) -> String {
        switch source.origin {
        case .localFolder:
            return "source=\(source.displayName) kind=local"
        case .connectedDevice(let device, let container):
            let transport = device.connection == .usb ? "usb" : "network"
            return "source=\(source.displayName) kind=connected-device transport=\(transport) udid=\(device.udid) app=\(container.appID)"
        }
    }

    private func logScanStage(
        _ stage: String,
        elapsed: TimeInterval,
        context: String,
        itemCount: Int
    ) {
        Self.performanceLogger.log(
            "\(stage, privacy: .public) \(context, privacy: .public) elapsed=\(elapsed, format: .fixed(precision: 3))s items=\(itemCount)"
        )
    }

    private func logDeviceRefreshStage(
        _ stage: String,
        elapsed: TimeInterval,
        device: ConnectedDevice,
        containerCount: Int,
        error: Error? = nil
    ) {
        let transport = device.connection == .usb ? "usb" : "network"
        let errorDescription = error?.localizedDescription ?? ""
        Self.performanceLogger.log(
            "\(stage, privacy: .public) device=\(device.name, privacy: .public) transport=\(transport, privacy: .public) udid=\(device.udid, privacy: .public) elapsed=\(elapsed, format: .fixed(precision: 3))s containers=\(containerCount) error=\(errorDescription, privacy: .public)"
        )
    }

    private func friendlyScanError(for error: Error, source: MinecraftSource) -> String {
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

        var source = sources[index]
        mutate(&source)
        sources[index] = source
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
            source.previewLoadedCount = snapshot.previewLoadedCount
            source.sizeLoadedCount = snapshot.sizeLoadedCount
            source.scanStatus = snapshot.scanStatus
            source.scanProgress = snapshot.scanProgress
            source.isScanning = snapshot.isScanning
            source.previewStageElapsed = snapshot.previewStageElapsed
            source.previewStageDuration = snapshot.previewStageDuration
            source.sizeStageElapsed = snapshot.sizeStageElapsed
            source.sizeStageDuration = snapshot.sizeStageDuration
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

    private func runConnectedDeviceRefreshLoop() async {
        while !Task.isCancelled && !isShuttingDown {
            if hasActiveConnectedDeviceScan {
                do {
                    try await Task.sleep(for: .seconds(Self.connectedDeviceRefreshIntervalWhileScanning))
                } catch {
                    return
                }
                continue
            }

            await refreshConnectedDevices()

            do {
                let refreshInterval = sources.contains {
                    $0.isScanning && $0.origin.kind == .connectedDevice
                }
                    ? Self.connectedDeviceRefreshIntervalWhileScanning
                    : Self.connectedDeviceRefreshInterval
                try await Task.sleep(for: .seconds(refreshInterval))
            } catch {
                return
            }
        }
    }

    private func runLocalSourceRefreshLoop() async {
        while !Task.isCancelled && !isShuttingDown {
            if hasActiveScan {
                do {
                    try await Task.sleep(for: .seconds(Self.localSourceRefreshInterval))
                } catch {
                    return
                }
                continue
            }

            await refreshLocalSources()

            do {
                try await Task.sleep(for: .seconds(Self.localSourceRefreshInterval))
            } catch {
                return
            }
        }
    }

    private func refreshLocalSources() async {
        guard !hasActiveScan else {
            return
        }

        let localSourceIDs = sources
            .filter { $0.origin.kind == .localFolder }
            .map(\.id)

        for sourceID in localSourceIDs {
            guard !Task.isCancelled, !isShuttingDown else {
                return
            }

            guard let currentSource = source(withID: sourceID) else {
                continue
            }

            let availability = await sourceAccessMethod.availability(for: currentSource)
            let transition = updateAvailability(for: sourceID, to: availability)

            guard let refreshedSource = source(withID: sourceID) else {
                continue
            }

            if transition.becameAvailable {
                queueAutomaticSync(
                    for: sourceID,
                    reason: refreshedSource.hasCachedContent
                        ? "Folder available. Refreshing cached library..."
                        : "Folder available. Scanning Minecraft library..."
                )
                continue
            }

            guard refreshedSource.availability == SourceAvailability.available, !refreshedSource.isScanning else {
                continue
            }

            if sourceNeedsReconcile(refreshedSource) {
                queueAutomaticSync(
                    for: sourceID,
                    reason: refreshedSource.hasCachedContent
                        ? "Detected changes. Refreshing cached library..."
                        : "Scanning Minecraft library..."
                )
            }
        }
    }

    private func refreshConnectedDevices() async {
        guard !isShuttingDown else {
            return
        }

        guard !hasActiveConnectedDeviceScan else {
            return
        }

        guard let connectedDeviceAccessMethod else {
            return
        }

        let devices: [ConnectedDevice]
        do {
            devices = try await connectedDeviceAccessMethod.listConnectedDevices()
        } catch {
            markAllConnectedDeviceSourcesDisconnected()
            connectedDevices = []
            lastMatchedConnectedSourceIDs = []
            return
        }

        var entries: [ConnectedDeviceSidebarEntry] = []
        var matchedSourceIDs = Set<URL>()
        let activeScanningDeviceUDIDs = Set(
            sources.compactMap { source -> String? in
                guard source.isScanning, case .connectedDevice(let device, _) = source.origin else {
                    return nil
                }

                return device.udid
            }
        )
        let currentDeviceUDIDs = Set(devices.map(\.udid))
        cachedDeviceDiscoveryByUDID = cachedDeviceDiscoveryByUDID.filter { currentDeviceUDIDs.contains($0.key) }

        for device in devices {
            let knownSourceIDs = knownConnectedDeviceSourceIDs(for: device)
            if !knownSourceIDs.isEmpty {
                matchedSourceIDs.formUnion(knownSourceIDs)
                let cachedContainers = cachedDeviceDiscoveryByUDID[device.udid]?.containers ?? []
                for sourceID in knownSourceIDs {
                    refreshMatchedConnectedDeviceSource(
                        sourceID: sourceID,
                        device: device,
                        containers: cachedContainers
                    )
                }

                continue
            }

            let containers: [DeviceAppContainer]
            let discoveryErrorDescription: String?
            if let cachedDiscovery = cachedDiscovery(for: device, isActivelyScanning: activeScanningDeviceUDIDs.contains(device.udid)) {
                containers = cachedDiscovery.containers
                discoveryErrorDescription = cachedDiscovery.discoveryErrorDescription
            } else {
                let containerDiscoveryStartTime = Date()

                do {
                    containers = try await connectedDeviceAccessMethod.listAccessibleContainers(for: device)
                    discoveryErrorDescription = nil
                    cacheDeviceDiscovery(
                        device: device,
                        containers: containers,
                        discoveryErrorDescription: nil
                    )
                    logDeviceRefreshStage(
                        "Container discovery",
                        elapsed: Date().timeIntervalSince(containerDiscoveryStartTime),
                        device: device,
                        containerCount: containers.count
                    )
                } catch {
                    containers = []
                    discoveryErrorDescription = error.localizedDescription
                    cacheDeviceDiscovery(
                        device: device,
                        containers: [],
                        discoveryErrorDescription: error.localizedDescription
                    )
                    logDeviceRefreshStage(
                        "Container discovery failed",
                        elapsed: Date().timeIntervalSince(containerDiscoveryStartTime),
                        device: device,
                        containerCount: 0,
                        error: error
                    )
                }
            }

            let matchedSourceID = matchingConnectedDeviceSourceID(
                device: device,
                containers: containers
            )

            if let matchedSourceID {
                matchedSourceIDs.insert(matchedSourceID)
                refreshMatchedConnectedDeviceSource(
                    sourceID: matchedSourceID,
                    device: device,
                    containers: containers
                )
            }

            let shouldDisplayEntry =
                matchedSourceID == nil
                && !hasKnownConnectedDeviceSource(for: device)
                && (!containers.isEmpty || device.trustState != .trusted)

            if shouldDisplayEntry {
                entries.append(
                    ConnectedDeviceSidebarEntry(
                        device: device,
                        containers: containers,
                        matchedSourceID: matchedSourceID,
                        discoveryErrorDescription: discoveryErrorDescription
                    )
                )
            }
        }

        markDisconnectedConnectedDeviceSources(excluding: matchedSourceIDs)

        connectedDevices = entries.sorted {
            let lhsKnown = $0.matchedSourceID != nil
            let rhsKnown = $1.matchedSourceID != nil
            if lhsKnown != rhsKnown {
                return lhsKnown && !rhsKnown
            }

            let lhsMinecraft = $0.hasMinecraftContainer
            let rhsMinecraft = $1.hasMinecraftContainer
            if lhsMinecraft != rhsMinecraft {
                return lhsMinecraft && !rhsMinecraft
            }

            return $0.device.name.localizedStandardCompare($1.device.name) == .orderedAscending
        }

        lastMatchedConnectedSourceIDs = matchedSourceIDs
    }

    private func cachedDiscovery(for device: ConnectedDevice, isActivelyScanning: Bool) -> CachedConnectedDeviceDiscovery? {
        guard let cachedDiscovery = cachedDeviceDiscoveryByUDID[device.udid] else {
            return nil
        }

        if isActivelyScanning {
            return cachedDiscovery
        }

        let age = Date().timeIntervalSince(cachedDiscovery.refreshedAt)
        guard age <= discoveryCacheTTL(for: device) else {
            return nil
        }

        guard cachedDiscovery.device.connection == device.connection,
              cachedDiscovery.device.trustState == device.trustState,
              cachedDiscovery.device.name == device.name else {
            return nil
        }

        return cachedDiscovery
    }

    private func discoveryCacheTTL(for device: ConnectedDevice) -> TimeInterval {
        switch device.connection {
        case .usb:
            return Self.usbConnectedDeviceDiscoveryCacheTTL
        case .network:
            return Self.networkConnectedDeviceDiscoveryCacheTTL
        }
    }

    private func cacheDeviceDiscovery(
        device: ConnectedDevice,
        containers: [DeviceAppContainer],
        discoveryErrorDescription: String?
    ) {
        cachedDeviceDiscoveryByUDID[device.udid] = CachedConnectedDeviceDiscovery(
            device: device,
            containers: containers,
            discoveryErrorDescription: discoveryErrorDescription,
            refreshedAt: Date()
        )
    }

    private func matchingConnectedDeviceSourceID(
        device: ConnectedDevice,
        containers: [DeviceAppContainer]
    ) -> URL? {
        for container in containers {
            let sourceID = connectedDeviceSourceFactory.makeSourceIdentifier(
                device: device,
                container: container
            )
            if sources.contains(where: { $0.id == sourceID }) {
                return sourceID
            }
        }

        return nil
    }

    private func knownConnectedDeviceSourceIDs(for device: ConnectedDevice) -> [URL] {
        sources.compactMap { source -> URL? in
            guard case .connectedDevice(let expectedDevice, _) = source.origin else {
                return nil
            }

            return expectedDevice.udid == device.udid ? source.id : nil
        }
    }

    private func hasKnownConnectedDeviceSource(for device: ConnectedDevice) -> Bool {
        !knownConnectedDeviceSourceIDs(for: device).isEmpty
    }

    private func refreshMatchedConnectedDeviceSource(
        sourceID: URL,
        device: ConnectedDevice,
        containers: [DeviceAppContainer]
    ) {
        let nextAvailability = availability(for: device, hasMinecraftContainer: true)
        updateSource(sourceID) { source in
            guard case .connectedDevice(let previousDevice, let previousContainer) = source.origin else {
                return
            }

            let resolvedContainer = containers.first(where: {
                $0.appID == previousContainer.appID && $0.accessMode == previousContainer.accessMode
            }) ?? previousContainer

            var resolvedDevice = device
            resolvedDevice.name = preferredConnectedDeviceName(
                currentName: device.name,
                fallbackDeviceName: previousDevice.name,
                fallbackDisplayName: source.displayName
            )
            source.origin = .connectedDevice(device: resolvedDevice, container: resolvedContainer)
            source.displayName = connectedDeviceSourceFactory.displayName(
                for: resolvedDevice,
                container: resolvedContainer
            )
            source.accessDescriptor = sourceAccessMethod.accessDescriptor(for: source)
        }
        let transition = updateAvailability(for: sourceID, to: nextAvailability)
        persistSourceIfAvailable(withID: sourceID)

        guard let source = source(withID: sourceID), source.availability == .available else {
            return
        }

        if transition.becameAvailable {
            if shouldRefreshConnectedDeviceOnReconnect(source, device: device) {
                queueAutomaticSync(
                    for: sourceID,
                    reason: source.hasCachedContent
                        ? "Device available. Refreshing cached library..."
                        : "Device available. Scanning Minecraft library..."
                )
            }
            return
        }

        if shouldRefreshConnectedDeviceSource(source, device: device) {
            queueAutomaticSync(for: sourceID, reason: "Refreshing device library...")
        }
    }

    private func markAllConnectedDeviceSourcesDisconnected() {
        for source in sources where source.origin.kind == .connectedDevice {
            _ = updateAvailability(for: source.id, to: .disconnected)
        }
    }

    private func markDisconnectedConnectedDeviceSources(excluding matchedSourceIDs: Set<URL>) {
        for source in sources where source.origin.kind == .connectedDevice && !matchedSourceIDs.contains(source.id) {
            _ = updateAvailability(for: source.id, to: .disconnected)
        }
    }

    private func availability(for device: ConnectedDevice, hasMinecraftContainer: Bool) -> SourceAvailability {
        guard hasMinecraftContainer else {
            return .unavailable
        }

        switch device.trustState {
        case .trusted:
            return .available
        case .locked, .untrusted:
            return .limited
        case .unavailable:
            return .disconnected
        }
    }

    private func preferredConnectedDeviceName(
        currentName: String,
        fallbackDeviceName: String,
        fallbackDisplayName: String
    ) -> String {
        if let sanitizedCurrentName = sanitizedConnectedDeviceName(currentName) {
            return sanitizedCurrentName
        }

        if let sanitizedFallbackName = sanitizedConnectedDeviceName(fallbackDeviceName) {
            return sanitizedFallbackName
        }

        if let displayNamePrefix = fallbackDisplayName.components(separatedBy: " • ").first,
           let sanitizedDisplayName = sanitizedConnectedDeviceName(displayNamePrefix) {
            return sanitizedDisplayName
        }

        return "Unknown Device"
    }

    private func sanitizedConnectedDeviceName(_ candidate: String) -> String? {
        let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCandidate.isEmpty else {
            return nil
        }

        let normalizedCandidate = trimmedCandidate.lowercased()
        guard normalizedCandidate != "unknown device",
              normalizedCandidate != "unknown device..." else {
            return nil
        }

        return trimmedCandidate
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
                repairedDevice.name = preferredConnectedDeviceName(
                    currentName: device.name,
                    fallbackDeviceName: "",
                    fallbackDisplayName: record.displayName
                )
                source.origin = .connectedDevice(device: repairedDevice, container: container)
                let persistedDeviceName = record.displayName.components(separatedBy: " • ").first ?? record.displayName
                if sanitizedConnectedDeviceName(persistedDeviceName) == nil {
                    source.displayName = connectedDeviceSourceFactory.displayName(
                        for: repairedDevice,
                        container: container
                    )
                } else {
                    source.displayName = record.displayName
                }
            } else {
                source.displayName = record.displayName
            }
            source.rawItems = record.rawItems
            source.indexedItemCount = record.rawItems.count
            source.indexedDetailCount = record.rawItems.filter(\.metadataLoaded).count
            source.previewLoadedCount = record.rawItems.filter(\.previewLoaded).count
            source.sizeLoadedCount = record.rawItems.filter(\.sizeLoaded).count
            source.lastScanDate = record.lastScanDate
            source.snapshot = record.snapshot
            source.scanStatus = source.indexedItemCount == 0
                ? "No Minecraft items found."
                : "Loaded \(source.indexedDetailCount) items."

            sources.append(source)
            rebuildNormalizedIndex(for: source.id)
        }

        for record in records where record.needsRepair {
            Task.detached(priority: .utility) { [persistenceStore] in
                try? await persistenceStore.repair(record: record)
            }
        }

        sources.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        refreshSidebarFooterState()
        await Task.yield()

        for record in records {
            let restoredItems = await restoreCachedImages(in: record.rawItems)
            updateSource(record.sourceID) { source in
                source.rawItems = restoredItems
                source.indexedItemCount = restoredItems.count
                source.indexedDetailCount = restoredItems.filter(\.metadataLoaded).count
                source.previewLoadedCount = restoredItems.filter(\.previewLoaded).count
                source.sizeLoadedCount = restoredItems.filter(\.sizeLoaded).count
                source.lastScanDate = record.lastScanDate
                source.snapshot = record.snapshot
            }
            rebuildNormalizedIndex(for: record.sourceID)
        }

        await refreshConnectedDevices()
        await refreshLocalSources()
        scheduleRestoredSourceRefreshes(records: records)
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

        let currentCollections = Dictionary(uniqueKeysWithValues: currentCollectionSnapshots(for: sourceURL).map { ($0.folderName, $0) })
        let persistedCollections = Dictionary(uniqueKeysWithValues: snapshot.collectionSnapshots.map { ($0.folderName, $0) })

        if currentCollections.count != persistedCollections.count {
            return true
        }

        for (folderName, persistedCollection) in persistedCollections {
            guard let currentCollection = currentCollections[folderName],
                  currentCollection.fingerprint == persistedCollection.fingerprint else {
                return true
            }
        }

        return false
    }

    private func sourceNeedsReconcile(_ source: MinecraftSource) -> Bool {
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

        let currentCollections = Dictionary(uniqueKeysWithValues: currentCollectionSnapshots(for: sourceURL).map { ($0.folderName, $0) })
        let persistedCollections = Dictionary(uniqueKeysWithValues: snapshot.collectionSnapshots.map { ($0.folderName, $0) })

        if currentCollections.count != persistedCollections.count {
            return true
        }

        for (folderName, persistedCollection) in persistedCollections {
            guard let currentCollection = currentCollections[folderName],
                  currentCollection.fingerprint == persistedCollection.fingerprint else {
                return true
            }
        }

        return false
    }

    private func scheduleRestoredSourceRefreshes(records: [PersistedSourceRecord]) {
        let persistedRecordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.sourceID, $0) })

        for source in sources {
            guard source.availability == .available else {
                continue
            }

            switch source.origin.kind {
            case .localFolder:
                if let record = persistedRecordsByID[source.id], sourceNeedsRescan(record) || sourceNeedsReconcile(source) {
                    queueAutomaticSync(
                        for: source.id,
                        reason: source.hasCachedContent
                            ? "Refreshing cached library..."
                            : "Scanning Minecraft library..."
                    )
                }
            case .connectedDevice:
                if source.rawItems.isEmpty || source.lastScanDate == nil {
                    queueAutomaticSync(
                        for: source.id,
                        reason: source.hasCachedContent
                            ? "Refreshing cached library..."
                            : "Scanning Minecraft library..."
                    )
                }
            }
        }
    }

    private func currentCollectionSnapshots(for sourceURL: URL) -> [CollectionSnapshot] {
        WorldScanner.collectionSnapshots(in: sourceURL)
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

    private func persistVisibleSourcesForShutdown() async {
        let persistedSources = sources
        for source in persistedSources {
            try? await persistenceStore.save(source: source)
        }
    }

    private func deletePersistedSource(withID sourceID: URL) {
        Task {
            try? await persistenceStore.deleteSource(withID: sourceID)
        }
    }

    private func queueAutomaticSync(for sourceID: URL, reason: String, debounce: TimeInterval? = nil) {
        guard !isShuttingDown else {
            return
        }

        guard let source = source(withID: sourceID), source.availability == .available else {
            return
        }

        if source.isScanning {
            return
        }

        let resolvedDebounce = debounce ?? Self.automaticSyncDebounce

        automaticSyncTasks[sourceID]?.cancel()
        updateSource(sourceID) { source in
            guard !source.isScanning else {
                return
            }

            source.scanError = nil
            if isCachedAvailabilityDiagnostic(source.scanDiagnostic) {
                source.scanDiagnostic = nil
            }
            source.scanStatus = reason
            source.scanProgress = nil
        }

            let mode: SourceDiscoveryMode = source.hasCachedContent ? .reconcile : .fullScan

        let task = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(resolvedDebounce))
            } catch {
                return
            }

            guard let self, !Task.isCancelled else {
                return
            }

            await MainActor.run {
                self.startScan(for: sourceID, mode: mode)
            }
        }

        automaticSyncTasks[sourceID] = task
    }

    private func purgeCachedArtifacts(for source: MinecraftSource) {
        Task.detached(priority: .utility) { [sourceAccessMethod] in
            await sourceAccessMethod.purgeCachedArtifacts(for: source)
        }
    }

    private func securityScopedBookmarkData(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func isLogicalPackType(_ contentType: MinecraftContentType) -> Bool {
        contentType == .behaviorPack || contentType == .resourcePack
    }

    private func refreshSidebarFooterState() {
        footerRefreshTask?.cancel()
        footerRefreshTask = nil

        if isRestoringPersistedSources {
            cancelFooterReset()
            sidebarFooterState = SidebarFooterState(
                style: .inProgress,
                title: "Restoring library...",
                subtitle: "Loading saved sources and cached metadata",
                detail: nil,
                revealURL: nil
            )
            return
        }

        let scanningSources = sources.filter(\.isScanning)
        if let source = scanningSources.first {
            cancelFooterReset()
            let title = source.liveScanStatusTitle.isEmpty
                ? "Scanning Minecraft library..."
                : source.liveScanStatusTitle
            let subtitle: String
            let detail: String?
            if source.indexedItemCount > 0 {
                subtitle = source.displayName
                switch source.scanPhase {
                case .discovering:
                    detail = "\(source.indexedItemCount) items found"
                case .metadata:
                    detail = "\(source.indexedDetailCount) of \(source.indexedItemCount) indexed"
                case .previews:
                    detail = "\(source.previewLoadedCount) of \(source.indexedItemCount) previews loaded"
                case .sizing:
                    detail = "\(source.sizeLoadedCount) of \(source.indexedItemCount) sizes calculated"
                case .completed, .idle:
                    detail = "\(source.indexedDetailCount) of \(source.indexedItemCount) indexed"
                }
            } else {
                subtitle = "Searching \(source.displayName)"
                detail = nil
            }

            sidebarFooterState = SidebarFooterState(
                style: .inProgress,
                title: title,
                subtitle: subtitle,
                detail: detail,
                revealURL: nil
            )
            return
        }

        if let source = sources.first(where: { $0.scanError != nil }) {
            sidebarFooterState = SidebarFooterState(
                style: .failure,
                title: "Scan failed",
                subtitle: source.scanError,
                detail: nil,
                revealURL: nil
            )
            scheduleFooterReset()
            return
        }
        cancelFooterReset()
        sidebarFooterState = SidebarFooterState(style: .idle, title: "", subtitle: nil, detail: nil, revealURL: nil)
    }

    private func scheduleSidebarFooterRefresh() {
        guard !isRestoringPersistedSources else {
            refreshSidebarFooterState()
            return
        }

        footerRefreshTask?.cancel()
        footerRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.footerRefreshDebounce))
            guard let self, !Task.isCancelled else {
                return
            }

            self.refreshSidebarFooterState()
        }
    }

    @discardableResult
    private func updateAvailability(for sourceID: URL, to newAvailability: SourceAvailability) -> (previous: SourceAvailability, becameAvailable: Bool) {
        let previousAvailability = source(withID: sourceID)?.availability ?? .unknown
        let becameAvailable = previousAvailability != .available && newAvailability == .available

        updateSource(sourceID) { source in
            source.availability = newAvailability

            guard !source.isScanning else {
                return
            }

            if newAvailability == .available {
                source.scanError = nil
                if isCachedAvailabilityDiagnostic(source.scanDiagnostic) {
                    source.scanDiagnostic = nil
                }
                if becameAvailable || source.scanStatus.isEmpty {
                    source.scanStatus = source.indexedItemCount == 0
                        ? "No Minecraft items found."
                        : "Loaded \(source.indexedDetailCount) items."
                }
            } else {
                source.scanError = nil
                source.scanProgress = nil
                source.scanStatus = source.availabilityDisplayText
                source.scanDiagnostic = source.cachedAvailabilityDetailText
            }
        }

        return (previousAvailability, becameAvailable)
    }

    private func isCachedAvailabilityDiagnostic(_ diagnostic: String?) -> Bool {
        guard let diagnostic else {
            return false
        }

        return diagnostic.localizedCaseInsensitiveContains("showing cached results")
    }

    private func shouldRefreshConnectedDeviceSource(_ source: MinecraftSource, device: ConnectedDevice) -> Bool {
        guard !source.isScanning else {
            return false
        }

        if connectedDeviceSourceHasRefreshDebt(source) {
            return true
        }
        _ = device
        return false
    }

    private func shouldRefreshConnectedDeviceOnReconnect(_ source: MinecraftSource, device: ConnectedDevice) -> Bool {
        guard !source.isScanning else {
            return false
        }

        if connectedDeviceSourceHasRefreshDebt(source) {
            return true
        }

        guard let lastScanDate = source.lastScanDate else {
            return true
        }

        let reconnectGracePeriod: TimeInterval = 5 * 60
        if Date().timeIntervalSince(lastScanDate) < reconnectGracePeriod {
            return false
        }

        return shouldRefreshConnectedDeviceSource(source, device: device)
    }

    private func connectedDeviceSourceHasRefreshDebt(_ source: MinecraftSource) -> Bool {
        guard source.origin.kind == .connectedDevice else {
            return false
        }

        guard !source.rawItems.isEmpty else {
            return true
        }

        let itemCount = source.rawItems.count
        return source.previewLoadedCount < itemCount || source.sizeLoadedCount < itemCount
    }

    private func cancelFooterReset() {
        footerResetTask?.cancel()
        footerResetTask = nil
    }

    private func initialScanStatus(for source: MinecraftSource, mode: SourceDiscoveryMode) -> String {
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

    private func scanningLibraryStatus(for source: MinecraftSource, mode: SourceDiscoveryMode) -> String {
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

    private func shouldReuseCachedItem(
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
        scanRootURL: URL,
        packMetadataByItemID: [URL: PackMetadata]
    ) -> SourceSnapshot {
        let collectionSnapshots = WorldScanner.collectionSnapshots(in: scanRootURL)

        let itemSnapshots = source.rawItems.map { item in
            let relativePath = item.folderURL.path.replacingOccurrences(of: scanRootURL.path + "/", with: "")
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

    private func availabilityStatus(for error: Error, defaultingTo currentAvailability: SourceAvailability) -> SourceAvailability {
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
