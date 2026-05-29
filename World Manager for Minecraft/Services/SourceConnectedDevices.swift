//
//  SourceConnectedDevices.swift
//  World Manager for Minecraft
//
//  Created by OpenAI Codex on 2026-05-28.
//

import Foundation

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

struct CachedConnectedDeviceDiscovery {
    let device: ConnectedDevice
    let containers: [DeviceAppContainer]
    let discoveryErrorDescription: String?
    let refreshedAt: Date
}

struct ConnectedDeviceRefreshContext {
    let existingSources: [MinecraftSource]
    let sourceFactory: ConnectedDeviceSourceFactory

    func knownSourceIDs(for device: ConnectedDevice) -> [URL] {
        existingSources.compactMap { source -> URL? in
            guard case .connectedDevice(let expectedDevice, _) = source.origin else {
                return nil
            }

            return expectedDevice.udid == device.udid ? source.id : nil
        }
    }

    func hasKnownSource(for device: ConnectedDevice) -> Bool {
        !knownSourceIDs(for: device).isEmpty
    }

    func matchingSourceID(
        for device: ConnectedDevice,
        containers: [DeviceAppContainer]
    ) -> URL? {
        for container in containers {
            let sourceID = sourceFactory.makeSourceIdentifier(
                device: device,
                container: container
            )
            if existingSources.contains(where: { $0.id == sourceID }) {
                return sourceID
            }
        }

        return nil
    }
}

enum ConnectedDeviceDiscoveryCachePolicy {
    private static let usbCacheTTL: TimeInterval = 60.0
    private static let networkCacheTTL: TimeInterval = 180.0

    static func cachedDiscovery(
        for device: ConnectedDevice,
        cache: [String: CachedConnectedDeviceDiscovery],
        isActivelyScanning: Bool,
        now: Date = Date()
    ) -> CachedConnectedDeviceDiscovery? {
        guard let cachedDiscovery = cache[device.udid] else {
            return nil
        }

        if isActivelyScanning {
            return cachedDiscovery
        }

        let age = now.timeIntervalSince(cachedDiscovery.refreshedAt)
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

    static func cacheDiscovery(
        for device: ConnectedDevice,
        containers: [DeviceAppContainer],
        discoveryErrorDescription: String?,
        now: Date = Date()
    ) -> CachedConnectedDeviceDiscovery {
        CachedConnectedDeviceDiscovery(
            device: device,
            containers: containers,
            discoveryErrorDescription: discoveryErrorDescription,
            refreshedAt: now
        )
    }

    private static func discoveryCacheTTL(for device: ConnectedDevice) -> TimeInterval {
        switch device.connection {
        case .usb:
            return usbCacheTTL
        case .network:
            return networkCacheTTL
        }
    }
}

enum ConnectedDeviceSourcePolicy {
    static func availability(for device: ConnectedDevice, hasMinecraftContainer: Bool) -> SourceAvailability {
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

    static func preferredDeviceName(
        currentName: String,
        fallbackDeviceName: String,
        fallbackDisplayName: String
    ) -> String {
        if let sanitizedCurrentName = sanitizedDeviceName(currentName) {
            return sanitizedCurrentName
        }

        if let sanitizedFallbackName = sanitizedDeviceName(fallbackDeviceName) {
            return sanitizedFallbackName
        }

        if let displayNamePrefix = fallbackDisplayName.components(separatedBy: " • ").first,
           let sanitizedDisplayName = sanitizedDeviceName(displayNamePrefix) {
            return sanitizedDisplayName
        }

        return "Unknown Device"
    }

    static func sanitizedDeviceName(_ candidate: String) -> String? {
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

    static func shouldRefreshSource(_ source: MinecraftSource) -> Bool {
        guard !source.isScanning else {
            return false
        }

        return hasRefreshDebt(source)
    }

    static func shouldRefreshSourceOnReconnect(_ source: MinecraftSource, now: Date = Date()) -> Bool {
        guard !source.isScanning else {
            return false
        }

        if hasRefreshDebt(source) {
            return true
        }

        guard let lastScanDate = source.lastScanDate else {
            return true
        }

        let reconnectGracePeriod: TimeInterval = 5 * 60
        if now.timeIntervalSince(lastScanDate) < reconnectGracePeriod {
            return false
        }

        return shouldRefreshSource(source)
    }

    static func hasRefreshDebt(_ source: MinecraftSource) -> Bool {
        guard source.origin.kind == .connectedDevice else {
            return false
        }

        guard !source.rawItems.isEmpty else {
            return true
        }

        let itemCount = source.rawItems.count
        return source.previewLoadedCount < itemCount || source.sizeLoadedCount < itemCount
    }
}
