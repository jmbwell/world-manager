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
    @Published var sources: [MinecraftSource] = []
    @Published private(set) var sidebarFooterState = SidebarFooterState(
        style: .idle,
        title: "",
        subtitle: nil,
        revealURL: nil
    )

    private var scanTasks: [URL: Task<Void, Never>] = [:]
    private var footerResetTask: Task<Void, Never>?

    func addSource(at url: URL) -> URL {
        let normalizedURL = url.standardizedFileURL

        if sources.contains(where: { $0.id == normalizedURL }) {
            startScan(for: normalizedURL)
            return normalizedURL
        }

        sources.append(MinecraftSource(folderURL: normalizedURL))
        sources.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
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
        updateSource(sourceID) { source in
            source.isScanning = true
            source.scanError = nil
            source.scanStatus = "Searching for Minecraft content..."
            source.items = []
            source.indexedItemCount = 0
            source.indexedDetailCount = 0
        }
        refreshSidebarFooterState()

        do {
            let enrichmentTracker = PendingEnrichmentTracker()
            let applyEnrichedItem: @MainActor (MinecraftContentItem) -> Void = { [weak self] enrichedItem in
                self?.handleEnrichedItem(enrichedItem, for: sourceID)
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
                updateSource(sourceID) { source in
                    source.items.append(item)
                    source.indexedItemCount = discoveredCount
                    source.scanStatus = "Found \(discoveredCount) items. Loading details..."
                }
                refreshSidebarFooterState()

                await enrichmentTracker.beginEnrichment()
                let tracker = enrichmentTracker

                Task.detached(priority: .utility) {
                    let enrichedItem = WorldScanner.enrich(item: item)
                    await applyEnrichedItem(enrichedItem)
                    await tracker.finishEnrichment()
                }
            }

            await enrichmentTracker.markDiscoveryFinished()
            await enrichmentTracker.waitForCompletion()

            updateSource(sourceID) { source in
                source.items.sort(by: WorldScanner.sortItems)
                source.scanStatus = source.indexedItemCount == 0
                    ? "No Minecraft content found."
                    : "Loaded \(source.indexedDetailCount) items."
                source.isScanning = false
                source.lastScanDate = Date()
            }
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

        scanTasks[sourceID] = nil
    }

    private func handleEnrichedItem(_ enrichedItem: MinecraftContentItem, for sourceID: URL) {
        updateSource(sourceID) { source in
            guard let index = source.items.firstIndex(where: { $0.id == enrichedItem.id }) else {
                return
            }

            source.items[index] = enrichedItem
            source.indexedDetailCount += 1

            if source.indexedDetailCount < source.indexedItemCount {
                source.scanStatus = "Loaded details for \(source.indexedDetailCount) of \(source.indexedItemCount) items..."
            }
        }
        refreshSidebarFooterState()
    }

    private func updateSource(_ sourceID: URL, mutate: (inout MinecraftSource) -> Void) {
        guard let index = sources.firstIndex(where: { $0.id == sourceID }) else {
            return
        }

        mutate(&sources[index])
    }

    private func refreshSidebarFooterState() {
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
}

private actor PendingEnrichmentTracker {
    private var pendingCount = 0
    private var discoveryFinished = false
    private var continuation: CheckedContinuation<Void, Never>?

    func beginEnrichment() {
        pendingCount += 1
    }

    func finishEnrichment() {
        pendingCount -= 1
        resumeIfNeeded()
    }

    func markDiscoveryFinished() {
        discoveryFinished = true
        resumeIfNeeded()
    }

    func waitForCompletion() async {
        guard !(discoveryFinished && pendingCount == 0) else {
            return
        }

        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    private func resumeIfNeeded() {
        guard discoveryFinished, pendingCount == 0 else {
            return
        }

        continuation?.resume()
        continuation = nil
    }
}
