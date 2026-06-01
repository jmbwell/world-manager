// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

@MainActor
protocol SourceSyncRuntimeHosting: AnyObject {
    var isShuttingDown: Bool { get }

    func source(withID sourceID: URL) -> MinecraftSource?
    func updateSource(_ sourceID: URL, mutate: (inout MinecraftSource) -> Void)
    func cancelAutomaticSync(for sourceID: URL)
    func storeAutomaticSyncTask(_ task: Task<Void, Never>, for sourceID: URL)
    func startScan(for sourceID: URL, mode: SourceDiscoveryMode)
}

enum SourceSyncRuntime {
    static func queueAutomaticSync(
        for sourceID: URL,
        reason: String,
        debounce: TimeInterval?,
        defaultDebounce: TimeInterval,
        on host: SourceSyncRuntimeHosting
    ) {
        guard !host.isShuttingDown else {
            return
        }

        guard let source = host.source(withID: sourceID), source.availability == .available else {
            return
        }

        guard !source.isScanning else {
            return
        }

        let resolvedDebounce = debounce ?? defaultDebounce

        host.cancelAutomaticSync(for: sourceID)
        host.updateSource(sourceID) { source in
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
        let task = Task { [weak host] in
            do {
                try await Task.sleep(for: .seconds(resolvedDebounce))
            } catch {
                return
            }

            guard let host, !Task.isCancelled else {
                return
            }

            await MainActor.run {
                host.startScan(for: sourceID, mode: mode)
            }
        }

        host.storeAutomaticSyncTask(task, for: sourceID)
    }

    @discardableResult
    static func updateAvailability(
        for sourceID: URL,
        to newAvailability: SourceAvailability,
        on host: SourceSyncRuntimeHosting
    ) -> (previous: SourceAvailability, becameAvailable: Bool) {
        let previousAvailability = host.source(withID: sourceID)?.availability ?? .unknown
        let becameAvailable = previousAvailability != .available && newAvailability == .available

        host.updateSource(sourceID) { source in
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
                source.scanStatus = SourcePresentation.availabilityDisplayText(for: source)
                source.scanDiagnostic = SourcePresentation.cachedAvailabilityDetailText(for: source)
            }
        }

        return (previousAvailability, becameAvailable)
    }

    private static func isCachedAvailabilityDiagnostic(_ diagnostic: String?) -> Bool {
        guard let diagnostic else {
            return false
        }

        return diagnostic.localizedCaseInsensitiveContains("showing cached results")
    }
}
