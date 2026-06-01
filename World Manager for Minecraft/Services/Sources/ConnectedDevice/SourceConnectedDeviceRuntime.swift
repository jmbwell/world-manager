// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

@MainActor
protocol ConnectedDeviceRuntimeHosting: AnyObject {
    var sources: [MinecraftSource] { get }
    var connectedDevices: [ConnectedDeviceSidebarEntry] { get set }
    var lastMatchedConnectedSourceIDs: Set<URL> { get set }
    var cachedDeviceDiscoveryByUDID: [String: CachedConnectedDeviceDiscovery] { get set }
    var isShuttingDown: Bool { get }
    var hasActiveConnectedDeviceScan: Bool { get }

    func source(withID sourceID: URL) -> MinecraftSource?
    func updateSource(_ sourceID: URL, mutate: (inout MinecraftSource) -> Void)
    func updateAvailability(for sourceID: URL, to newAvailability: SourceAvailability) -> (previous: SourceAvailability, becameAvailable: Bool)
    func queueAutomaticSync(for sourceID: URL, reason: String, debounce: TimeInterval?)
    func persistSourceIfAvailable(withID sourceID: URL)
    func connectedDeviceDisplayName(for device: ConnectedDevice, container: DeviceAppContainer) -> String
    func accessDescriptor(for source: MinecraftSource) -> SourceAccessDescriptor
    func logConnectedDeviceRefreshStage(
        _ stage: String,
        elapsed: TimeInterval,
        device: ConnectedDevice,
        containerCount: Int,
        error: Error?
    )
}

enum ConnectedDeviceRuntime {
    static func runRefreshLoop(
        on host: ConnectedDeviceRuntimeHosting,
        refreshInterval: TimeInterval,
        refreshIntervalWhileScanning: TimeInterval,
        accessMethod: ConnectedDeviceSourceAccessMethod
    ) async {
        while !Task.isCancelled && !host.isShuttingDown {
            if host.hasActiveConnectedDeviceScan {
                do {
                    try await Task.sleep(for: .seconds(refreshIntervalWhileScanning))
                } catch {
                    return
                }
                continue
            }

            await refreshDevices(on: host, using: accessMethod)

            do {
                let nextInterval = host.hasActiveConnectedDeviceScan
                    ? refreshIntervalWhileScanning
                    : refreshInterval
                try await Task.sleep(for: .seconds(nextInterval))
            } catch {
                return
            }
        }
    }

    static func refreshDevices(
        on host: ConnectedDeviceRuntimeHosting,
        using accessMethod: ConnectedDeviceSourceAccessMethod
    ) async {
        guard !host.isShuttingDown else {
            return
        }

        guard !host.hasActiveConnectedDeviceScan else {
            return
        }

        let devices: [ConnectedDevice]
        do {
            devices = try await accessMethod.listConnectedDevices()
        } catch {
            markAllConnectedDeviceSourcesDisconnected(on: host)
            host.connectedDevices = []
            host.lastMatchedConnectedSourceIDs = []
            return
        }

        var entries: [ConnectedDeviceSidebarEntry] = []
        var matchedSourceIDs = Set<URL>()
        let refreshContext = ConnectedDeviceRefreshContext(
            existingSources: host.sources,
            sourceFactory: ConnectedDeviceSourceFactory()
        )
        let activeScanningDeviceUDIDs = Set(
            host.sources.compactMap { source -> String? in
                guard source.isScanning, case .connectedDevice(let device, _) = source.origin else {
                    return nil
                }

                return device.udid
            }
        )
        let currentDeviceUDIDs = Set(devices.map(\.udid))
        host.cachedDeviceDiscoveryByUDID = host.cachedDeviceDiscoveryByUDID.filter { currentDeviceUDIDs.contains($0.key) }

        for device in devices {
            let knownSourceIDs = refreshContext.knownSourceIDs(for: device)
            if !knownSourceIDs.isEmpty {
                matchedSourceIDs.formUnion(knownSourceIDs)
                let cachedContainers = host.cachedDeviceDiscoveryByUDID[device.udid]?.containers ?? []
                for sourceID in knownSourceIDs {
                    refreshMatchedSource(
                        sourceID: sourceID,
                        device: device,
                        containers: cachedContainers,
                        on: host
                    )
                }

                continue
            }

            let containers: [DeviceAppContainer]
            let discoveryErrorDescription: String?
            if let cachedDiscovery = ConnectedDeviceDiscoveryCachePolicy.cachedDiscovery(
                for: device,
                cache: host.cachedDeviceDiscoveryByUDID,
                isActivelyScanning: activeScanningDeviceUDIDs.contains(device.udid)
            ) {
                containers = cachedDiscovery.containers
                discoveryErrorDescription = cachedDiscovery.discoveryErrorDescription
            } else {
                let containerDiscoveryStartTime = Date()

                do {
                    containers = try await accessMethod.listAccessibleContainers(for: device)
                    discoveryErrorDescription = nil
                    cacheDeviceDiscovery(
                        device: device,
                        containers: containers,
                        discoveryErrorDescription: nil,
                        on: host
                    )
                    host.logConnectedDeviceRefreshStage(
                        "Container discovery",
                        elapsed: Date().timeIntervalSince(containerDiscoveryStartTime),
                        device: device,
                        containerCount: containers.count,
                        error: nil
                    )
                } catch {
                    containers = []
                    discoveryErrorDescription = error.localizedDescription
                    cacheDeviceDiscovery(
                        device: device,
                        containers: [],
                        discoveryErrorDescription: error.localizedDescription,
                        on: host
                    )
                    host.logConnectedDeviceRefreshStage(
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
                refreshMatchedSource(
                    sourceID: matchedSourceID,
                    device: device,
                    containers: containers,
                    on: host
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

        markDisconnectedConnectedDeviceSources(excluding: matchedSourceIDs, on: host)

        host.connectedDevices = entries.sorted {
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

        host.lastMatchedConnectedSourceIDs = matchedSourceIDs
    }

    private static func cacheDeviceDiscovery(
        device: ConnectedDevice,
        containers: [DeviceAppContainer],
        discoveryErrorDescription: String?,
        on host: ConnectedDeviceRuntimeHosting
    ) {
        host.cachedDeviceDiscoveryByUDID[device.udid] = ConnectedDeviceDiscoveryCachePolicy.cacheDiscovery(
            for: device,
            containers: containers,
            discoveryErrorDescription: discoveryErrorDescription
        )
    }

    private static func refreshMatchedSource(
        sourceID: URL,
        device: ConnectedDevice,
        containers: [DeviceAppContainer],
        on host: ConnectedDeviceRuntimeHosting
    ) {
        let nextAvailability = ConnectedDeviceSourcePolicy.availability(
            for: device,
            hasMinecraftContainer: true
        )
        host.updateSource(sourceID) { source in
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
            source.displayName = host.connectedDeviceDisplayName(for: resolvedDevice, container: resolvedContainer)
            source.accessDescriptor = host.accessDescriptor(for: source)
        }
        let transition = host.updateAvailability(for: sourceID, to: nextAvailability)
        host.persistSourceIfAvailable(withID: sourceID)

        guard let source = host.source(withID: sourceID), source.availability == .available else {
            return
        }

        if transition.becameAvailable {
            if ConnectedDeviceSourcePolicy.shouldRefreshSourceOnReconnect(source) {
                host.queueAutomaticSync(
                    for: sourceID,
                    reason: source.hasCachedContent
                        ? "Device available. Refreshing cached library..."
                        : "Device available. Scanning Minecraft library...",
                    debounce: nil
                )
            }
            return
        }

        if ConnectedDeviceSourcePolicy.shouldRefreshSource(source) {
            host.queueAutomaticSync(for: sourceID, reason: "Refreshing device library...", debounce: nil)
        }
    }

    private static func markAllConnectedDeviceSourcesDisconnected(on host: ConnectedDeviceRuntimeHosting) {
        for source in host.sources where source.origin.kind == .connectedDevice {
            _ = host.updateAvailability(for: source.id, to: .disconnected)
        }
    }

    private static func markDisconnectedConnectedDeviceSources(
        excluding matchedSourceIDs: Set<URL>,
        on host: ConnectedDeviceRuntimeHosting
    ) {
        for source in host.sources where source.origin.kind == .connectedDevice && !matchedSourceIDs.contains(source.id) {
            _ = host.updateAvailability(for: source.id, to: .disconnected)
        }
    }
}
