//
//  SourceLibrary.swift
//  World Manager for Minecraft
//
//  Created by John Burwell on 2026-05-25.
//

import Combine
import Foundation

@MainActor
final class SourceLibrary: ObservableObject {
    @Published var sources: [MinecraftSource] = []

    private var scanTasks: [URL: Task<Void, Never>] = [:]

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
        }

        do {
            let discoveredItems = try await Task.detached(priority: .userInitiated) {
                try WorldScanner.discoverItems(in: sourceID)
            }.value

            guard !Task.isCancelled else {
                return
            }

            updateSource(sourceID) { source in
                source.items = discoveredItems
                source.scanStatus = discoveredItems.isEmpty
                    ? "No Minecraft content found."
                    : "Found \(discoveredItems.count) items. Loading details..."
            }

            var loadedCount = 0

            await withTaskGroup(of: MinecraftContentItem.self) { group in
                for item in discoveredItems {
                    group.addTask {
                        WorldScanner.enrich(item: item)
                    }
                }

                for await enrichedItem in group {
                    guard !Task.isCancelled else {
                        return
                    }

                    loadedCount += 1
                    updateSource(sourceID) { source in
                        guard let index = source.items.firstIndex(where: { $0.id == enrichedItem.id }) else {
                            return
                        }

                        source.items[index] = enrichedItem
                        source.items.sort(by: WorldScanner.sortItems)

                        if loadedCount == discoveredItems.count {
                            source.scanStatus = "Loaded \(loadedCount) items."
                            source.isScanning = false
                        } else {
                            source.scanStatus = "Loaded details for \(loadedCount) of \(discoveredItems.count) items..."
                        }
                    }
                }
            }

            if discoveredItems.isEmpty {
                updateSource(sourceID) { source in
                    source.isScanning = false
                }
            }
        } catch {
            guard !Task.isCancelled else {
                return
            }

            updateSource(sourceID) { source in
                source.scanError = "Failed to scan folder: \(error.localizedDescription)"
                source.scanStatus = ""
                source.isScanning = false
            }
        }

        scanTasks[sourceID] = nil
    }

    private func updateSource(_ sourceID: URL, mutate: (inout MinecraftSource) -> Void) {
        guard let index = sources.firstIndex(where: { $0.id == sourceID }) else {
            return
        }

        mutate(&sources[index])
    }
}
