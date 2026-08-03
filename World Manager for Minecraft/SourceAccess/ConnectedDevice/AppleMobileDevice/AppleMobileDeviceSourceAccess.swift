// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

struct AppleMobileDeviceSourceAccess: ConnectedDeviceSourceAccessMethod {
    nonisolated let accessorIdentifier: SourceAccessorIdentifier = "connected-device.apple-mobile-device"

    nonisolated init() {}

    nonisolated func accessDescriptor(for source: MinecraftSource) -> SourceAccessDescriptor {
        _ = source
        return SourceAccessDescriptor(
            accessorIdentifier: accessorIdentifier,
            kind: .connectedDevice,
            refreshStrategy: .staged
        )
    }

    nonisolated func availability(for source: MinecraftSource) async -> SourceAvailability {
        guard case .connectedDevice(let expectedDevice, _) = source.origin else {
            return .unavailable
        }

        do {
            let devices = try await listConnectedDevices()
            guard let device = devices.first(where: { $0.udid == expectedDevice.udid }) else {
                return .disconnected
            }

            switch device.trustState {
            case .trusted:
                return .available
            case .locked, .untrusted:
                return .limited
            case .unavailable:
                return .disconnected
            }
        } catch {
            return .disconnected
        }
    }

    nonisolated func capabilities(for source: MinecraftSource) async -> SourceCapabilities {
        _ = source
        return .connectedDevice
    }

    nonisolated func listConnectedDevices() async throws -> [ConnectedDevice] {
        let devices = try await AppleMobileDeviceAccess.connectedDevices()
        return devices.compactMap { device in
            let connection: DeviceConnection
            switch device.connectionType.lowercased() {
            case "network", "wifi", "wi-fi":
                connection = .network
            default:
                connection = .usb
            }

            return ConnectedDevice(
                udid: device.deviceIdentifier,
                name: device.deviceName,
                productType: device.productType.isEmpty ? nil : device.productType,
                osVersion: device.productVersion.isEmpty ? nil : device.productVersion,
                connection: connection,
                trustState: device.trustState
            )
        }
    }

    nonisolated func listAccessibleContainers(for device: ConnectedDevice) async throws -> [DeviceAppContainer] {
        let applications = try await AppleMobileDeviceAccess.listApplications(deviceIdentifier: device.udid)

        return applications
            .filter { application in
                application.fileSharingEnabled
                    || application.supportsOpeningDocumentsInPlace
                    || application.bundleIdentifier == "com.mojang.minecraftpe"
            }
            .map { application in
                DeviceAppContainer(
                    deviceUDID: device.udid,
                    appID: application.bundleIdentifier,
                    appName: application.displayName,
                    accessMode: .documents,
                    minecraftFolderRelativePath: application.bundleIdentifier == "com.mojang.minecraftpe"
                        ? "Documents/games/com.mojang"
                        : nil
                )
            }
            .sorted { lhs, rhs in
                if lhs.appID == "com.mojang.minecraftpe" {
                    return true
                }
                if rhs.appID == "com.mojang.minecraftpe" {
                    return false
                }
                return lhs.appName.localizedStandardCompare(rhs.appName) == .orderedAscending
            }
    }

    nonisolated func discoverItems(
        for source: MinecraftSource,
        mode: SourceDiscoveryMode,
        onDiscovered: @escaping @Sendable (MinecraftContentItem) -> Void
    ) async throws {
        _ = mode
        guard case .connectedDevice(_, let container) = source.origin else {
            throw SourceAccessError.accessFailed(
                reason: "The selected source is not backed by a connected mobile device."
            )
        }

        let requestedSubpath = container.minecraftFolderRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !requestedSubpath.isEmpty else {
            throw SourceAccessError.accessFailed(
                reason: "A device-backed source requires a vend-relative Minecraft path."
            )
        }

        let summaries = try await AppleMobileDeviceAccess.minecraftLibrarySnapshot(
            deviceIdentifier: container.deviceUDID,
            bundleIdentifier: container.appID,
            relativePath: requestedSubpath
        )

        let metadataByPath = try await metadataByRelativePath(
            for: summaries,
            container: container,
            requestedSubpath: requestedSubpath
        )

        let items = summaries.compactMap { summary in
            makeItem(
                from: summary,
                metadata: metadataByPath[summary.relativePath],
                source: source
            )
        }

        for item in items {
            onDiscovered(item)
        }
    }

    nonisolated func enrich(_ item: MinecraftContentItem, for source: MinecraftSource) async -> MinecraftContentItem {
        var enrichedItem = item
        guard case .connectedDevice = source.origin else {
            enrichedItem.metadataLoaded = true
            enrichedItem.previewLoaded = true
            return enrichedItem
        }

        enrichedItem.modifiedDate = nil
        enrichedItem.lastPlayedDate = enrichedItem.worldMetadata?.lastPlayedDate
        enrichedItem.metadataLoaded = true
        enrichedItem.previewLoaded = !enrichedItem.hasKnownIcon
        enrichedItem.sizeLoaded = false
        return enrichedItem
    }

    nonisolated func loadPreviewAssets(for item: MinecraftContentItem, in source: MinecraftSource) async -> MinecraftContentItem {
        var previewItem = item
        guard case .connectedDevice(_, let container) = source.origin else {
            previewItem.previewLoaded = true
            return previewItem
        }

        if previewItem.hasKnownIcon {
            previewItem.iconURL = await loadRemoteIcon(
                for: previewItem,
                source: source,
                container: container
            )
        }

        previewItem.previewLoaded = true
        return previewItem
    }

    nonisolated func loadPreviewAssets(for items: [MinecraftContentItem], in source: MinecraftSource) async -> [MinecraftContentItem] {
        guard case .connectedDevice(_, let container) = source.origin else {
            var previewItems: [MinecraftContentItem] = []
            previewItems.reserveCapacity(items.count)
            for item in items {
                previewItems.append(await loadPreviewAssets(for: item, in: source))
            }
            return previewItems
        }

        let summaries = items.compactMap { item -> AppleMobileMinecraftLibraryItemSummary? in
            guard item.hasKnownIcon, let relativePath = relativeItemPath(for: item, in: source) else {
                return nil
            }

            return AppleMobileMinecraftLibraryItemSummary(
                contentType: item.contentType.rawValue,
                collectionFolderName: item.collectionRootURL.lastPathComponent,
                relativePath: relativePath,
                folderName: item.folderName,
                displayName: item.displayName,
                hasIcon: true
            )
        }

        let iconsByRelativePath: [String: URL]
        if summaries.isEmpty {
            iconsByRelativePath = [:]
        } else if let iconSummaries = try? await AppleMobileDeviceAccess.minecraftIconBatch(
            deviceIdentifier: container.deviceUDID,
            bundleIdentifier: container.appID,
            relativePath: container.minecraftFolderRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            items: summaries
        ) {
            var resolvedIcons: [String: URL] = [:]
            resolvedIcons.reserveCapacity(iconSummaries.count)

            for iconSummary in iconSummaries {
                let pathExtension = NSString(string: iconSummary.iconFileName).pathExtension
                let cachedURL = await ImageCacheStore.shared.cachedImageURL(
                    forRemoteData: iconSummary.data,
                    cacheKey: "\(container.deviceUDID)::\(container.appID)::\(iconSummary.relativePath)::\(iconSummary.iconFileName)",
                    pathExtension: pathExtension
                )
                if let cachedURL {
                    resolvedIcons[iconSummary.relativePath] = cachedURL
                }
            }
            iconsByRelativePath = resolvedIcons
        } else {
            iconsByRelativePath = [:]
        }

        return items.map { item in
            var previewItem = item
            if let relativePath = relativeItemPath(for: item, in: source),
               let cachedURL = iconsByRelativePath[relativePath] {
                previewItem.iconURL = cachedURL
            }
            previewItem.previewLoaded = true
            return previewItem
        }
    }

    nonisolated func loadSize(for item: MinecraftContentItem, in source: MinecraftSource) async -> MinecraftContentItem {
        var sizedItem = item
        guard case .connectedDevice(_, let container) = source.origin else {
            sizedItem.sizeLoaded = true
            return sizedItem
        }

        if let remoteItemPath = remoteItemPath(for: item, in: source),
           let metrics = try? await AppleMobileDeviceAccess.pathMetrics(
                deviceIdentifier: container.deviceUDID,
                bundleIdentifier: container.appID,
                relativePath: remoteItemPath
           ) {
            sizedItem.sizeBytes = metrics.sizeBytes
            if sizedItem.modifiedDate == nil {
                sizedItem.modifiedDate = metrics.modifiedDate
            }
        }

        sizedItem.sizeLoaded = true
        return sizedItem
    }

    nonisolated func loadSizeAssets(for items: [MinecraftContentItem], in source: MinecraftSource) async -> [MinecraftContentItem] {
        guard case .connectedDevice(_, let container) = source.origin else {
            var sizedItems: [MinecraftContentItem] = []
            sizedItems.reserveCapacity(items.count)
            for item in items {
                sizedItems.append(await loadSize(for: item, in: source))
            }
            return sizedItems
        }

        let relativePathsByItemID = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            remoteItemPath(for: item, in: source).map { (item.id, $0) }
        })

        let metricsByRelativePath: [String: AppleMobileDevicePathMetrics]
        if relativePathsByItemID.isEmpty {
            metricsByRelativePath = [:]
        } else if let metricSummaries = try? await AppleMobileDeviceAccess.pathMetricsBatch(
            deviceIdentifier: container.deviceUDID,
            bundleIdentifier: container.appID,
            relativePaths: Array(relativePathsByItemID.values)
        ) {
            metricsByRelativePath = Dictionary(
                uniqueKeysWithValues: metricSummaries.map { ($0.relativePath, $0.metrics) }
            )
        } else {
            metricsByRelativePath = [:]
        }

        return items.map { item in
            var sizedItem = item
            if let relativePath = relativePathsByItemID[item.id],
               let metrics = metricsByRelativePath[relativePath] {
                sizedItem.sizeBytes = metrics.sizeBytes
                if sizedItem.modifiedDate == nil {
                    sizedItem.modifiedDate = metrics.modifiedDate
                }
            }
            sizedItem.sizeLoaded = true
            return sizedItem
        }
    }

    nonisolated func listItemContents(for item: MinecraftContentItem, in source: MinecraftSource) async throws -> [DirectoryEntry] {
        guard case .connectedDevice(_, let container) = source.origin else {
            return []
        }

        guard let remoteFolderPath = remoteItemPath(for: item, in: source) else {
            return []
        }

        let entries = try await AppleMobileDeviceAccess.listDirectory(
            deviceIdentifier: container.deviceUDID,
            bundleIdentifier: container.appID,
            relativePath: remoteFolderPath
        )

        return entries
            .map { entry in
                let isDirectory = !NSString(string: entry).pathExtension.isEmpty ? false : true
                return DirectoryEntry(name: entry, isDirectory: isDirectory)
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory && !rhs.isDirectory
                }

                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    nonisolated func materializeItem(for item: MinecraftContentItem, in source: MinecraftSource) async throws -> URL {
        guard case .connectedDevice(_, let container) = source.origin else {
            return item.folderURL
        }

        guard let remoteItemPath = remoteItemPath(for: item, in: source) else {
            throw SourceAccessError.accessFailed(reason: "Could not resolve the device path for this item.")
        }

        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WMMConnectedDeviceReveal", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        do {
            try await AppleMobileDeviceAccess.mirrorSubtree(
                deviceIdentifier: container.deviceUDID,
                bundleIdentifier: container.appID,
                relativePath: remoteItemPath,
                destinationDirectoryURL: destinationURL
            )
            return destinationURL
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
    }

    nonisolated func install(_ payload: InstallationPayload, in source: MinecraftSource) async throws -> InstalledContentItem {
        guard case .connectedDevice(_, let container) = source.origin else {
            throw SourceAccessError.accessFailed(reason: "The selected source is not a connected device.")
        }
        let minecraftRoot = container.minecraftFolderRelativePath?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !minecraftRoot.isEmpty else {
            throw SourceAccessError.accessFailed(reason: "The connected device is missing its Minecraft content path.")
        }

        let destinationName = try await AppleMobileDeviceAccess.installDirectory(
            deviceIdentifier: container.deviceUDID,
            bundleIdentifier: container.appID,
            minecraftRootRelativePath: minecraftRoot,
            collectionFolderName: payload.contentType.collectionFolderName,
            preferredDestinationName: payload.suggestedFolderName,
            sourceDirectoryURL: payload.preparedDirectoryURL
        )
        return InstalledContentItem(
            contentType: payload.contentType,
            displayName: payload.displayName,
            destinationName: destinationName
        )
    }

    nonisolated func purgeCachedArtifacts(for source: MinecraftSource) async {
        guard source.origin.kind == .connectedDevice else {
            return
        }

        try? ConnectedDeviceMirrorCache.purgeRootURL(for: source.id)
    }

    nonisolated private func makeItem(
        from summary: AppleMobileMinecraftLibraryItemSummary,
        metadata: AppleMobileMinecraftItemMetadataSummary?,
        source: MinecraftSource
    ) -> MinecraftContentItem? {
        let contentType: MinecraftContentType
        switch summary.contentType {
        case MinecraftContentType.world.rawValue:
            contentType = .world
        case MinecraftContentType.behaviorPack.rawValue:
            contentType = .behaviorPack
        case MinecraftContentType.resourcePack.rawValue:
            contentType = .resourcePack
        case MinecraftContentType.skinPack.rawValue:
            contentType = .skinPack
        case MinecraftContentType.worldTemplate.rawValue:
            contentType = .worldTemplate
        default:
            return nil
        }

        let collectionRootURL = source.folderURL.appendingPathComponent(summary.collectionFolderName, isDirectory: true)
        let folderURL = source.folderURL.appendingPathComponent(summary.relativePath, isDirectory: true)
        let displayName = metadata?.displayName ?? summary.displayName
        let packMetadataDetails: PackMetadataDetails?
        if let minimumEngineVersion = metadata?.minimumEngineVersion {
            packMetadataDetails = PackMetadataDetails(minimumEngineVersion: minimumEngineVersion)
        } else {
            packMetadataDetails = nil
        }

        return MinecraftContentItem(
            folderURL: folderURL,
            folderName: summary.folderName,
            contentType: contentType,
            collectionRootURL: collectionRootURL,
            displayName: displayName,
            iconURL: nil,
            hasKnownIcon: summary.hasIcon,
            packUUID: metadata?.packUUID,
            packVersion: metadata?.packVersion,
            packMetadataDetails: packMetadataDetails,
            packReferences: packReferences(from: metadata?.packReferences ?? []),
            metadataLoaded: false,
            previewLoaded: !summary.hasIcon,
            sizeLoaded: false
        )
    }

    nonisolated private func metadataByRelativePath(
        for summaries: [AppleMobileMinecraftLibraryItemSummary],
        container: DeviceAppContainer,
        requestedSubpath: String
    ) async throws -> [String: AppleMobileMinecraftItemMetadataSummary] {
        guard !summaries.isEmpty else {
            return [:]
        }

        let metadata = try await AppleMobileDeviceAccess.minecraftMetadataBatch(
            deviceIdentifier: container.deviceUDID,
            bundleIdentifier: container.appID,
            relativePath: requestedSubpath,
            items: summaries
        )

        return Dictionary(uniqueKeysWithValues: metadata.map { ($0.relativePath, $0) })
    }

    nonisolated private func packReferences(
        from summaries: [AppleMobilePackReferenceSummary]
    ) -> [ContentPackReference] {
        let references = summaries.compactMap { summary -> ContentPackReference? in
            let contentType: MinecraftContentType
            switch summary.contentType {
            case MinecraftContentType.behaviorPack.rawValue:
                contentType = .behaviorPack
            case MinecraftContentType.resourcePack.rawValue:
                contentType = .resourcePack
            case MinecraftContentType.skinPack.rawValue:
                contentType = .skinPack
            case MinecraftContentType.worldTemplate.rawValue:
                contentType = .worldTemplate
            default:
                return nil
            }

            let source: PackSource
            switch summary.source {
            case PackSource.embeddedInWorld.rawValue:
                source = .embeddedInWorld
            case PackSource.foundInCollection.rawValue:
                source = .foundInCollection
            default:
                source = .referencedByWorld
            }

            return ContentPackReference(
                name: summary.name,
                type: contentType,
                iconURL: nil,
                uuid: summary.uuid,
                version: summary.version,
                source: source
            )
        }

        return uniquePackReferences(references)
    }

    nonisolated private func remoteItemPath(
        for item: MinecraftContentItem,
        in source: MinecraftSource,
        appending childPath: String? = nil
    ) -> String? {
        guard case .connectedDevice(_, let container) = source.origin else {
            return nil
        }

        let rootPath = container.minecraftFolderRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rootPath.isEmpty else {
            return nil
        }

        let relativeItemPath = relativeItemPath(for: item, in: source) ?? ""
        guard !relativeItemPath.isEmpty else {
            return nil
        }

        let basePath = appendPathComponents(
            rootPath,
            components: relativeItemPath.split(separator: "/").map(String.init)
        )

        if let childPath, !childPath.isEmpty {
            return NSString(string: basePath).appendingPathComponent(childPath)
        }

        return basePath
    }

    nonisolated private func relativeItemPath(for item: MinecraftContentItem, in source: MinecraftSource) -> String? {
        let relativeItemPath = item.folderURL.path.replacingOccurrences(of: source.folderURL.path + "/", with: "")
        return relativeItemPath.isEmpty ? nil : relativeItemPath
    }

    nonisolated private func loadRemoteIcon(
        for item: MinecraftContentItem,
        source: MinecraftSource,
        container: DeviceAppContainer
    ) async -> URL? {
        let candidateNames: [String]
        switch item.contentType {
        case .world:
            candidateNames = ["world_icon.jpeg", "world_icon.jpg", "world_icon.png"]
        case .behaviorPack, .resourcePack, .skinPack, .worldTemplate:
            candidateNames = ["pack_icon.png", "pack_icon.jpeg", "pack_icon.jpg"]
        }

        for candidateName in candidateNames {
            guard let remotePath = remoteItemPath(for: item, in: source, appending: candidateName) else {
                continue
            }
            guard let data = try? await AppleMobileDeviceAccess.fileData(
                deviceIdentifier: container.deviceUDID,
                bundleIdentifier: container.appID,
                relativePath: remotePath
            ) else {
                continue
            }

            let pathExtension = NSString(string: candidateName).pathExtension
            return await ImageCacheStore.shared.cachedImageURL(
                forRemoteData: data,
                cacheKey: "\(container.deviceUDID)::\(container.appID)::\(remotePath)",
                pathExtension: pathExtension
            )
        }

        return nil
    }

    nonisolated private func appendPathComponents(_ root: String, components: [String]) -> String {
        components.reduce(root) { partial, component in
            NSString(string: partial).appendingPathComponent(component)
        }
    }

    nonisolated private func loadWorldPackReferences(
        for item: MinecraftContentItem,
        source: MinecraftSource,
        container: DeviceAppContainer
    ) async -> [ContentPackReference] {
        var references: [ContentPackReference] = []

        if let behaviorRefPath = remoteItemPath(for: item, in: source, appending: "world_behavior_packs.json"),
           let behaviorData = try? await AppleMobileDeviceAccess.fileData(
                deviceIdentifier: container.deviceUDID,
                bundleIdentifier: container.appID,
                relativePath: behaviorRefPath
           ) {
            references.append(contentsOf: parsePackReferences(from: behaviorData, type: .behaviorPack))
        }

        if let resourceRefPath = remoteItemPath(for: item, in: source, appending: "world_resource_packs.json"),
           let resourceData = try? await AppleMobileDeviceAccess.fileData(
                deviceIdentifier: container.deviceUDID,
                bundleIdentifier: container.appID,
                relativePath: resourceRefPath
           ) {
            references.append(contentsOf: parsePackReferences(from: resourceData, type: .resourcePack))
        }

        references.append(contentsOf: await loadEmbeddedPackReferences(
            for: item,
            source: source,
            container: container,
            folderName: "behavior_packs",
            type: .behaviorPack
        ))
        references.append(contentsOf: await loadEmbeddedPackReferences(
            for: item,
            source: source,
            container: container,
            folderName: "resource_packs",
            type: .resourcePack
        ))

        return uniquePackReferences(references)
    }

    nonisolated private func loadEmbeddedPackReferences(
        for item: MinecraftContentItem,
        source: MinecraftSource,
        container: DeviceAppContainer,
        folderName: String,
        type: MinecraftContentType
    ) async -> [ContentPackReference] {
        guard let remoteFolderPath = remoteItemPath(for: item, in: source, appending: folderName) else {
            return []
        }

        guard let childFolders = try? await AppleMobileDeviceAccess.listDirectory(
            deviceIdentifier: container.deviceUDID,
            bundleIdentifier: container.appID,
            relativePath: remoteFolderPath
        ) else {
            return []
        }

        var references: [ContentPackReference] = []
        for childFolder in childFolders {
            let childFolderPath = NSString(string: remoteFolderPath).appendingPathComponent(childFolder)
            let manifestPath = NSString(string: childFolderPath).appendingPathComponent("manifest.json")
            guard let manifestData = try? await AppleMobileDeviceAccess.fileData(
                deviceIdentifier: container.deviceUDID,
                bundleIdentifier: container.appID,
                relativePath: manifestPath
            ) else {
                continue
            }

            guard let metadata = parseManifestMetadata(from: manifestData, fallbackName: childFolder) else {
                continue
            }

            references.append(
                ContentPackReference(
                    name: metadata.name,
                    type: type,
                    iconURL: nil,
                    uuid: metadata.uuid,
                    version: metadata.version,
                    source: .embeddedInWorld
                )
            )
        }

        return references
    }

    nonisolated private func parsePackReferences(
        from data: Data,
        type: MinecraftContentType
    ) -> [ContentPackReference] {
        guard let jsonObject = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return []
        }

        return jsonObject.map { entry in
            let uuid = (entry["pack_id"] as? String)?.lowercased()
            let version = versionString(from: entry["version"])
            return ContentPackReference(
                name: uuid ?? "Referenced Pack",
                type: type,
                iconURL: nil,
                uuid: uuid,
                version: version,
                source: .referencedByWorld
            )
        }
    }

    nonisolated private func parseManifestMetadata(
        from data: Data,
        fallbackName: String
    ) -> (name: String, uuid: String?, version: String?, minimumEngineVersion: String?)? {
        guard
            let jsonObject = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let header = jsonObject["header"] as? [String: Any]
        else {
            return nil
        }

        let name = ((header["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : $0
        } ?? fallbackName

        return (
            name: name,
            uuid: (header["uuid"] as? String)?.lowercased(),
            version: versionString(from: header["version"]),
            minimumEngineVersion: versionString(from: header["min_engine_version"])
        )
    }

    nonisolated private func versionString(from value: Any?) -> String? {
        if let versionString = value as? String, !versionString.isEmpty {
            return versionString
        }

        if let versionArray = value as? [Any] {
            let components = versionArray.compactMap { component -> String? in
                if let intComponent = component as? Int {
                    return String(intComponent)
                }
                if let stringComponent = component as? String {
                    return stringComponent
                }
                return nil
            }

            return components.isEmpty ? nil : components.joined(separator: ".")
        }

        return nil
    }

    nonisolated private func uniquePackReferences(_ references: [ContentPackReference]) -> [ContentPackReference] {
        var seen = Set<String>()
        var uniqueReferences: [ContentPackReference] = []

        for reference in references {
            let dedupeKey = [reference.type.rawValue, reference.uuid ?? reference.name, reference.version ?? ""]
                .joined(separator: "::")
            guard seen.insert(dedupeKey).inserted else {
                continue
            }
            uniqueReferences.append(reference)
        }

        return uniqueReferences.sorted { lhs, rhs in
            if lhs.type != rhs.type {
                return lhs.type.rawValue.localizedStandardCompare(rhs.type.rawValue) == .orderedAscending
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
