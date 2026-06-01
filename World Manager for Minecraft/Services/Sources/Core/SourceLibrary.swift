// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation
import OSLog
import UniformTypeIdentifiers

@MainActor
final class SourceLibrary: ObservableObject, SourceScanSessionHosting, SourcePersistenceHosting, ConnectedDeviceRuntimeHosting, LocalSourceRuntimeHosting, SourceSyncRuntimeHosting {
    private static let enrichmentWorkerCount = 4
    private static let sizeWorkerCount = 2
    private static let minimumVisibleScanDuration: TimeInterval = 0.8
    private static let automaticSyncDebounce: TimeInterval = 0.75
    private static let localSourceRefreshInterval: TimeInterval = 4.0
    private static let connectedDeviceRefreshInterval: TimeInterval = 2.0
    private static let connectedDeviceRefreshIntervalWhileScanning: TimeInterval = 5.0
    private static let usbConnectedDeviceAutoRefreshInterval: TimeInterval = 45.0
    private static let networkConnectedDeviceAutoRefreshInterval: TimeInterval = 120.0
    private static let performanceLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "WorldManagerForMinecraft",
        category: "ConnectedDevicePerformance"
    )

    @Published var sources: [MinecraftSource] = [] {
        didSet {
            rebuildLookupIndexes()
        }
    }
    @Published var connectedDevices: [ConnectedDeviceSidebarEntry] = []
    @Published var isRestoringPersistedSources = true

    private var scanTasks: [URL: Task<Void, Never>] = [:]
    private var automaticSyncTasks: [URL: Task<Void, Never>] = [:]
    private var connectedDeviceRefreshTask: Task<Void, Never>?
    private var localSourceRefreshTask: Task<Void, Never>?
    private let persistenceStore: SourcePersistenceStore
    private let sourceAccessMethod: SourceAccessMethod
    private let connectedDeviceAccessMethod: ConnectedDeviceSourceAccessMethod?
    private let notificationService: ScanNotificationServicing
    private let itemActionService: ContentItemActionService
    private let connectedDeviceSourceFactory = ConnectedDeviceSourceFactory()
    private var sourceIndexByID: [URL: Int] = [:]
    private var sourceIDByItemID: [URL: URL] = [:]
    var lastMatchedConnectedSourceIDs: Set<URL> = []
    var cachedDeviceDiscoveryByUDID: [String: CachedConnectedDeviceDiscovery] = [:]
    var isShuttingDown = false

    init(
        persistenceStore: SourcePersistenceStore = .shared,
        sourceAccessMethod: SourceAccessMethod = LocalFolderSourceAccess(),
        connectedDeviceAccessMethod: ConnectedDeviceSourceAccessMethod? = nil,
        notificationService: ScanNotificationServicing? = nil,
        itemActionService: ContentItemActionService = ContentItemActionService()
    ) {
        self.persistenceStore = persistenceStore
        self.sourceAccessMethod = sourceAccessMethod
        self.connectedDeviceAccessMethod = connectedDeviceAccessMethod
        self.notificationService = notificationService ?? ScanNotificationService.shared
        self.itemActionService = itemActionService

        Task { [weak self] in
            guard let self else {
                return
            }
            await SourcePersistenceCoordinator.restoreSources(on: self, using: self.persistenceStore)
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
        automaticSyncTasks.values.forEach { $0.cancel() }
        scanTasks.values.forEach { $0.cancel() }
    }

    var visibleSources: [MinecraftSource] {
        sources
    }

    var sidebarSources: [MinecraftSource] {
        visibleSources
    }

    func sourceID(forItemID itemID: URL) -> URL? {
        sourceIDByItemID[itemID]
    }

    func containsItem(withID itemID: URL) -> Bool {
        sourceIDByItemID[itemID] != nil
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

        let sourcesToPersist = visibleSources
        shutdown()

        await SourcePersistenceCoordinator.persistVisibleSourcesForShutdown(
            from: sourcesToPersist,
            using: persistenceStore,
            timeout: timeout
        )
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
                source.capabilities = source.origin.defaultCapabilities
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
                existingSource.capabilities = source.capabilities
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
            resolvedSource.capabilities = resolvedSource.origin.defaultCapabilities
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
        guard let index = sourceIndexByID[sourceID], sources.indices.contains(index) else {
            return nil
        }

        return sources[index]
    }

    func rescanSource(withID sourceID: URL) {
        startScan(for: sourceID, mode: .fullScan)
    }

    func listContents(for item: MinecraftContentItem, in source: MinecraftSource) async throws -> [DirectoryEntry] {
        try await sourceAccessMethod.listItemContents(for: item, in: source)
    }

    func materializeItem(_ item: MinecraftContentItem, in source: MinecraftSource) async throws -> URL {
        try await sourceAccessMethod.materializeItem(for: item, in: source)
    }

    func externalRepresentation(
        for item: MinecraftContentItem,
        in source: MinecraftSource,
        preferredKind: ExternalRepresentationKind? = nil
    ) async throws -> ExternalRepresentation {
        let kind = resolvedExternalRepresentationKind(
            for: source,
            preferredKind: preferredKind
        )

        switch kind {
        case .nativeFolder:
            let url = try await sourceAccessMethod.materializeItem(for: item, in: source)
            return ExternalRepresentation(
                url: url,
                kind: .nativeFolder,
                suggestedFilename: itemActionService.suggestedFilename(for: item),
                contentType: .folder,
                isTemporary: source.origin.kind != .localFolder
            )
        case .portablePackage:
            let url = try await itemActionService.createArchiveFile(for: item, source: source)
            return ExternalRepresentation(
                url: url,
                kind: .portablePackage,
                suggestedFilename: itemActionService.suggestedArchiveFilename(for: item),
                contentType: itemActionService.archiveContentType(for: item),
                isTemporary: true
            )
        }
    }

    func removeSource(withID sourceID: URL) {
        let removedSource = source(withID: sourceID)
        scanTasks[sourceID]?.cancel()
        scanTasks[sourceID] = nil
        sources.removeAll { $0.id == sourceID }
        SourcePersistenceCoordinator.deletePersistedSource(withID: sourceID, using: persistenceStore)
        if let removedSource {
            purgeCachedArtifacts(for: removedSource)
        }
    }

    func startScan(for sourceID: URL, mode: SourceDiscoveryMode) {
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

    var hasActiveScan: Bool {
        sources.contains(where: \.isScanning)
    }

    var hasActiveConnectedDeviceScan: Bool {
        sources.contains { $0.isScanning && $0.origin.kind == .connectedDevice }
    }

    private func scanSource(withID sourceID: URL, mode: SourceDiscoveryMode) async {
        defer {
            scanTasks[sourceID] = nil
        }

        guard let source = source(withID: sourceID) else {
            return
        }
        await SourceScanExecutor.execute(
            sourceID: sourceID,
            mode: mode,
            source: source,
            host: self,
            sourceAccessMethod: sourceAccessMethod,
            notificationService: notificationService,
            enrichmentWorkerCount: Self.enrichmentWorkerCount,
            sizeWorkerCount: Self.sizeWorkerCount,
            minimumVisibleScanDuration: Self.minimumVisibleScanDuration
        )
    }

    func rebuildNormalizedIndex(for sourceID: URL) {
        updateSource(sourceID) { source in
            let index = SourceContentIndexer.buildIndex(for: source)
            source.rawItems = index.rawItems
            source.logicalPacks = index.logicalPacks
            source.logicalWorlds = index.logicalWorlds
            source.packInstances = index.packInstances
            source.worldPackRelationships = index.worldPackRelationships
            source.displayItems = index.displayItems
            source.displayItemCountsByType = index.displayItemCountsByType
        }
    }

    func logScanStage(
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

    func updateSource(_ sourceID: URL, mutate: (inout MinecraftSource) -> Void) {
        guard let index = sources.firstIndex(where: { $0.id == sourceID }) else {
            return
        }

        var source = sources[index]
        mutate(&source)
        sources[index] = source
    }

    func applySnapshot(_ snapshot: SourceIndexSnapshot, to sourceID: URL) {
        updateSource(sourceID) { source in
            source.displayItems = snapshot.displayItems
            source.displayItemCountsByType = snapshot.displayItemCountsByType
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

    private func resolvedExternalRepresentationKind(
        for source: MinecraftSource,
        preferredKind: ExternalRepresentationKind?
    ) -> ExternalRepresentationKind {
        switch preferredKind {
        case .some(.nativeFolder):
            if source.capabilities.canMaterializeItems {
                return .nativeFolder
            }
            return .portablePackage
        case .some(.portablePackage):
            return .portablePackage
        case .none:
            return .portablePackage
        }
    }

    private func runConnectedDeviceRefreshLoop() async {
        guard let connectedDeviceAccessMethod else {
            return
        }

        await ConnectedDeviceRuntime.runRefreshLoop(
            on: self,
            refreshInterval: Self.connectedDeviceRefreshInterval,
            refreshIntervalWhileScanning: Self.connectedDeviceRefreshIntervalWhileScanning,
            accessMethod: connectedDeviceAccessMethod
        )
    }

    private func runLocalSourceRefreshLoop() async {
        await LocalSourceRuntime.runRefreshLoop(
            on: self,
            refreshInterval: Self.localSourceRefreshInterval,
            accessMethod: sourceAccessMethod
        )
    }

    func refreshLocalSources() async {
        await LocalSourceRuntime.refreshSources(on: self, using: sourceAccessMethod)
    }

    func refreshConnectedDevices() async {
        guard let connectedDeviceAccessMethod else {
            return
        }

        await ConnectedDeviceRuntime.refreshDevices(on: self, using: connectedDeviceAccessMethod)
    }

    func currentCollectionSnapshots(for sourceURL: URL) -> [CollectionSnapshot] {
        WorldScanner.collectionSnapshots(in: sourceURL)
    }

    func connectedDeviceDisplayName(for device: ConnectedDevice, container: DeviceAppContainer) -> String {
        connectedDeviceSourceFactory.displayName(for: device, container: container)
    }

    func accessDescriptor(for source: MinecraftSource) -> SourceAccessDescriptor {
        sourceAccessMethod.accessDescriptor(for: source)
    }

    func logConnectedDeviceRefreshStage(
        _ stage: String,
        elapsed: TimeInterval,
        device: ConnectedDevice,
        containerCount: Int,
        error: Error?
    ) {
        logDeviceRefreshStage(
            stage,
            elapsed: elapsed,
            device: device,
            containerCount: containerCount,
            error: error
        )
    }

    func appendRestoredSource(_ source: MinecraftSource) {
        sources.append(source)
        rebuildNormalizedIndex(for: source.id)
    }

    func applyRestoredItems(_ items: [MinecraftContentItem], from record: PersistedSourceRecord) {
        updateSource(record.sourceID) { source in
            SourceRestoration.applyRestoredItemState(
                items,
                lastScanDate: record.lastScanDate,
                snapshot: record.snapshot,
                to: &source
            )
        }
        rebuildNormalizedIndex(for: record.sourceID)
    }

    func sortSourcesByDisplayName() {
        sources.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    func persistSourceIfAvailable(withID sourceID: URL) {
        SourcePersistenceCoordinator.persistSourceIfAvailable(
            withID: sourceID,
            on: self,
            using: persistenceStore
        )
    }

    func queueAutomaticSync(for sourceID: URL, reason: String, debounce: TimeInterval? = nil) {
        SourceSyncRuntime.queueAutomaticSync(
            for: sourceID,
            reason: reason,
            debounce: debounce,
            defaultDebounce: Self.automaticSyncDebounce,
            on: self
        )
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

    private func rebuildLookupIndexes() {
        sourceIndexByID = Dictionary(uniqueKeysWithValues: sources.enumerated().map { ($0.element.id, $0.offset) })

        var itemIndex: [URL: URL] = [:]
        for source in sources {
            for item in source.items {
                itemIndex[item.id] = source.id
            }
        }
        sourceIDByItemID = itemIndex
    }

    @discardableResult
    func updateAvailability(for sourceID: URL, to newAvailability: SourceAvailability) -> (previous: SourceAvailability, becameAvailable: Bool) {
        SourceSyncRuntime.updateAvailability(for: sourceID, to: newAvailability, on: self)
    }

    func cancelAutomaticSync(for sourceID: URL) {
        automaticSyncTasks[sourceID]?.cancel()
        automaticSyncTasks[sourceID] = nil
    }

    func storeAutomaticSyncTask(_ task: Task<Void, Never>, for sourceID: URL) {
        automaticSyncTasks[sourceID] = task
    }
}
