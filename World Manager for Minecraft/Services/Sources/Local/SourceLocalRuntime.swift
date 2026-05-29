//
//  SourceLocalRuntime.swift
//  World Manager for Minecraft
//
//  Created by OpenAI Codex on 2026-05-29.
//

import Foundation

@MainActor
protocol LocalSourceRuntimeHosting: AnyObject {
    var sources: [MinecraftSource] { get }
    var isShuttingDown: Bool { get }
    var hasActiveScan: Bool { get }

    func source(withID sourceID: URL) -> MinecraftSource?
    func updateAvailability(for sourceID: URL, to newAvailability: SourceAvailability) -> (previous: SourceAvailability, becameAvailable: Bool)
    func queueAutomaticSync(for sourceID: URL, reason: String, debounce: TimeInterval?)
    func currentCollectionSnapshots(for sourceURL: URL) -> [CollectionSnapshot]
}

enum LocalSourceRuntime {
    static func runRefreshLoop(
        on host: LocalSourceRuntimeHosting,
        refreshInterval: TimeInterval,
        accessMethod: SourceAccessMethod
    ) async {
        while !Task.isCancelled && !host.isShuttingDown {
            if host.hasActiveScan {
                do {
                    try await Task.sleep(for: .seconds(refreshInterval))
                } catch {
                    return
                }
                continue
            }

            await refreshSources(on: host, using: accessMethod)

            do {
                try await Task.sleep(for: .seconds(refreshInterval))
            } catch {
                return
            }
        }
    }

    static func refreshSources(
        on host: LocalSourceRuntimeHosting,
        using accessMethod: SourceAccessMethod
    ) async {
        guard !host.hasActiveScan else {
            return
        }

        let localSourceIDs = host.sources
            .filter { $0.origin.kind == .localFolder }
            .map(\.id)

        for sourceID in localSourceIDs {
            guard !Task.isCancelled, !host.isShuttingDown else {
                return
            }

            guard let currentSource = host.source(withID: sourceID) else {
                continue
            }

            let availability = await accessMethod.availability(for: currentSource)
            let transition = host.updateAvailability(for: sourceID, to: availability)

            guard let refreshedSource = host.source(withID: sourceID) else {
                continue
            }

            if transition.becameAvailable {
                host.queueAutomaticSync(
                    for: sourceID,
                    reason: refreshedSource.hasCachedContent
                        ? "Folder available. Refreshing cached library..."
                        : "Folder available. Scanning Minecraft library...",
                    debounce: nil
                )
                continue
            }

            guard refreshedSource.availability == .available, !refreshedSource.isScanning else {
                continue
            }

            if SourceRestoration.needsReconcile(
                refreshedSource,
                currentCollectionSnapshots: host.currentCollectionSnapshots(for:)
            ) {
                host.queueAutomaticSync(
                    for: sourceID,
                    reason: refreshedSource.hasCachedContent
                        ? "Detected changes. Refreshing cached library..."
                        : "Scanning Minecraft library...",
                    debounce: nil
                )
            }
        }
    }
}
