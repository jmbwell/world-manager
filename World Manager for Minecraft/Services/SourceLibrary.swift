//
//  SourceLibrary.swift
//  World Manager for Minecraft
//
//  Created by John Burwell on 2026-05-25.
//

import Combine
import Foundation
import OSLog

@MainActor
final class SourceLibrary: ObservableObject, SourceScanSessionHosting {
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

    @Published var sources: [MinecraftSource] = []
    @Published private(set) var connectedDevices: [ConnectedDeviceSidebarEntry] = []
    @Published private(set) var isRestoringPersistedSources = true

    private var scanTasks: [URL: Task<Void, Never>] = [:]
    private var automaticSyncTasks: [URL: Task<Void, Never>] = [:]
    private var connectedDeviceRefreshTask: Task<Void, Never>?
    private var localSourceRefreshTask: Task<Void, Never>?
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

            if SourceRestoration.needsReconcile(
                refreshedSource,
                currentCollectionSnapshots: currentCollectionSnapshots(for:)
            ) {
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
        let refreshContext = ConnectedDeviceRefreshContext(
            existingSources: sources,
            sourceFactory: connectedDeviceSourceFactory
        )
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
            let knownSourceIDs = refreshContext.knownSourceIDs(for: device)
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
            if let cachedDiscovery = ConnectedDeviceDiscoveryCachePolicy.cachedDiscovery(
                for: device,
                cache: cachedDeviceDiscoveryByUDID,
                isActivelyScanning: activeScanningDeviceUDIDs.contains(device.udid)
            ) {
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

            let matchedSourceID = refreshContext.matchingSourceID(for: device, containers: containers)

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
                && !refreshContext.hasKnownSource(for: device)
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

    private func cacheDeviceDiscovery(
        device: ConnectedDevice,
        containers: [DeviceAppContainer],
        discoveryErrorDescription: String?
    ) {
        cachedDeviceDiscoveryByUDID[device.udid] = ConnectedDeviceDiscoveryCachePolicy.cacheDiscovery(
            for: device,
            containers: containers,
            discoveryErrorDescription: discoveryErrorDescription
        )
    }

    private func refreshMatchedConnectedDeviceSource(
        sourceID: URL,
        device: ConnectedDevice,
        containers: [DeviceAppContainer]
    ) {
        let nextAvailability = ConnectedDeviceSourcePolicy.availability(
            for: device,
            hasMinecraftContainer: true
        )
        updateSource(sourceID) { source in
            guard case .connectedDevice(let previousDevice, let previousContainer) = source.origin else {
                return
            }

            let resolvedContainer = containers.first(where: {
                $0.appID == previousContainer.appID && $0.accessMode == previousContainer.accessMode
            }) ?? previousContainer

            var resolvedDevice = device
            resolvedDevice.name = ConnectedDeviceSourcePolicy.preferredDeviceName(
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
            if ConnectedDeviceSourcePolicy.shouldRefreshSourceOnReconnect(source) {
                queueAutomaticSync(
                    for: sourceID,
                    reason: source.hasCachedContent
                        ? "Device available. Refreshing cached library..."
                        : "Device available. Scanning Minecraft library..."
                )
            }
            return
        }

        if ConnectedDeviceSourcePolicy.shouldRefreshSource(source) {
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

    private func restorePersistedSources() async {
        defer {
            isRestoringPersistedSources = false
        }

        let records: [PersistedSourceRecord]
        do {
            records = try await persistenceStore.loadSources()
        } catch {
            return
        }

        for record in records {
            let source = SourceRestoration.restoredSource(from: record) { [connectedDeviceSourceFactory] device, container in
                connectedDeviceSourceFactory.displayName(for: device, container: container)
            }

            sources.append(source)
            rebuildNormalizedIndex(for: source.id)
        }

        for record in records where record.needsRepair {
            Task.detached(priority: .utility) { [persistenceStore] in
                try? await persistenceStore.repair(record: record)
            }
        }

        sources.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        await Task.yield()

        for record in records {
            let restoredItems = await SourceRestoration.restoreCachedImages(in: record.rawItems)
            updateSource(record.sourceID) { source in
                SourceRestoration.applyRestoredItemState(
                    restoredItems,
                    lastScanDate: record.lastScanDate,
                    snapshot: record.snapshot,
                    to: &source
                )
            }
            rebuildNormalizedIndex(for: record.sourceID)
        }

        await refreshConnectedDevices()
        await refreshLocalSources()
        scheduleRestoredSourceRefreshes(records: records)
    }

    private func scheduleRestoredSourceRefreshes(records: [PersistedSourceRecord]) {
        let persistedRecordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.sourceID, $0) })

        for source in sources {
            if let refreshReason = SourceRestoration.startupRefreshReason(
                for: source,
                persistedRecord: persistedRecordsByID[source.id],
                currentCollectionSnapshots: currentCollectionSnapshots(for:)
            ) {
                queueAutomaticSync(for: source.id, reason: refreshReason)
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

    func persistSourceIfAvailable(withID sourceID: URL) {
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
