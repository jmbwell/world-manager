//
//  ContentView.swift
//  World Manager for Minecraft
//
//  Created by John Burwell on 2026-05-25.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var library = SourceLibrary()
    @State private var selectedItemID: MinecraftContentItem.ID?
    @State private var selectedSidebarSelection: SidebarSelection?
    @State private var searchText = ""
    @State private var isDropTargeted = false
    @State private var isPerformingItemAction = false
    @State private var sortMode: ItemSortMode = .name

    private let directoryPreviewLimit = 12

    var body: some View {
        NavigationSplitView {
            SourcesSidebarView(
                sources: library.sources,
                selection: $selectedSidebarSelection,
                footerState: library.sidebarFooterState,
                addSourceAction: pickFolder,
                rescanSourceAction: { source in
                    library.rescanSource(withID: source.id)
                },
                removeSourceAction: { source in
                    removeSource(source.id)
                },
                revealFooterURLAction: revealURLInFinder(_:),
                filters: sidebarFilters(for:)
            )
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 380)
        } content: {
            ItemListColumnView(
                isEmpty: library.sources.isEmpty,
                isDropTargeted: $isDropTargeted,
                selectedItemID: $selectedItemID,
                searchText: $searchText,
                sortMode: $sortMode,
                title: collectionHeaderTitle,
                subtitle: collectionHeaderSubtitle,
                items: displayedItems,
                searchPrompt: searchPrompt,
                chooseFolderAction: pickFolder,
                dropAction: handleDroppedProviders(_:),
                refreshAction: rescanCurrentSource,
                itemContextMenu: itemContextMenu(for:)
            )
            .navigationSplitViewColumnWidth(min: 340, ideal: 400, max: 460)
        } detail: {
            ItemDetailColumnView(
                item: currentSelectedItem,
                source: currentSource,
                behaviorPacks: currentSelectedItem.map { logicalPackReferences(for: $0, type: .behaviorPack) } ?? [],
                resourcePacks: currentSelectedItem.map { logicalPackReferences(for: $0, type: .resourcePack) } ?? [],
                worldsUsingPack: currentSelectedItem.map(worldsUsingPack(for:)) ?? [],
                backingPackInstances: currentSelectedItem.map(backingPackInstances(for:)) ?? [],
                isSuspiciousPack: currentSelectedItem.map(isSuspiciousPack(_:)) ?? false,
                contents: currentSelectedItem.map(directoryPreviewEntries(for:)) ?? [],
                directoryPreviewLimit: directoryPreviewLimit,
                isEmpty: library.sources.isEmpty,
                isPerformingItemAction: isPerformingItemAction,
                exportTitle: currentSelectedItem.map(primaryActionTitle(for:)),
                exportAction: {
                    guard let item = currentSelectedItem else {
                        return
                    }

                    saveItem(item)
                },
                revealAction: {
                    guard let item = currentSelectedItem else {
                        return
                    }

                    revealInFinder(item)
                },
                shareAction: { anchorView in
                    guard let item = currentSelectedItem else {
                        return
                    }

                    shareItem(item, from: anchorView)
                }
            )
            .frame(minWidth: 450)
        }
        .overlay {
            if library.isRestoringPersistedSources {
                LaunchRestoreOverlayView()
            }
        }
        .disabled(library.isRestoringPersistedSources)
        .onChange(of: displayedItems.map(\.id)) { _, filteredIDs in
            guard let selectedItemID, !filteredIDs.contains(selectedItemID) else {
                return
            }

            self.selectedItemID = nil
        }
        .onChange(of: library.sources.map(\.id)) { _, sourceIDs in
            syncSelection(with: sourceIDs)
        }
    }

    private var scopedItems: [MinecraftContentItem] {
        guard let selectedSidebarSelection else {
            return []
        }

        switch selectedSidebarSelection {
        case .allContent(let sourceID):
            return library.source(withID: sourceID)?.items ?? []
        case .contentType(let sourceID, let contentType):
            return library.source(withID: sourceID)?.items.filter { $0.contentType == contentType } ?? []
        }
    }

    private var filteredItems: [MinecraftContentItem] {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearchText.isEmpty else {
            return scopedItems
        }

        return scopedItems.filter { item in
            item.searchText.localizedCaseInsensitiveContains(trimmedSearchText)
        }
    }

    private var displayedItems: [MinecraftContentItem] {
        filteredItems.sorted(by: sortComparator)
    }

    private var currentSource: MinecraftSource? {
        guard let sourceID = selectedSidebarSelection?.sourceID else {
            return library.sources.first
        }

        return library.source(withID: sourceID)
    }

    private var currentSelectedItem: MinecraftContentItem? {
        guard let selectedItemID else {
            return nil
        }

        return library.sources
            .flatMap(\.items)
            .first(where: { $0.id == selectedItemID })
    }

    private var sortComparator: (MinecraftContentItem, MinecraftContentItem) -> Bool {
        switch sortMode {
        case .name:
            return { lhs, rhs in
                lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
        case .modifiedDate:
            return { lhs, rhs in
                switch (lhs.displayDate, rhs.displayDate) {
                case let (lhsDate?, rhsDate?):
                    if lhsDate != rhsDate {
                        return lhsDate > rhsDate
                    }
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                case (nil, nil):
                    break
                }

                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
        case .size:
            return { lhs, rhs in
                switch (lhs.sizeBytes, rhs.sizeBytes) {
                case let (lhsSize?, rhsSize?):
                    if lhsSize != rhsSize {
                        return lhsSize > rhsSize
                    }
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                case (nil, nil):
                    break
                }

                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
        }
    }

    private var collectionHeaderTitle: String {
        if isSearching {
            return "Searching “\(searchScopeTitle)”"
        }

        guard let selectedSidebarSelection else {
            return "Library"
        }

        switch selectedSidebarSelection {
        case .allContent:
            return "All Items"
        case .contentType(_, let contentType):
            return sidebarTitle(for: contentType)
        }
    }

    private var collectionHeaderSubtitle: String {
        let totalCount = scopedItems.count
        let filteredCount = filteredItems.count
        let noun = collectionCountNoun

        if !isSearching {
            return "\(totalCount.formatted(.number)) \(noun)"
        }

        return "\(filteredCount.formatted(.number)) of \(totalCount.formatted(.number)) \(noun)"
    }

    private var searchScopeTitle: String {
        switch selectedSidebarSelection {
        case .some(.allContent):
            return "All"
        case .some(.contentType(_, let contentType)):
            return sidebarTitle(for: contentType)
        case .none:
            return "Library"
        }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var collectionCountNoun: String {
        guard let selectedSidebarSelection else {
            return "items"
        }

        switch selectedSidebarSelection {
        case .allContent:
            return scopedItems.count == 1 ? "item" : "items"
        case .contentType(_, let contentType):
            switch contentType {
            case .world:
                return scopedItems.count == 1 ? "world" : "worlds"
            case .behaviorPack, .resourcePack, .skinPack, .worldTemplate:
                return scopedItems.count == 1 ? "pack" : "packs"
            }
        }
    }

    private var searchPrompt: String {
        switch selectedSidebarSelection {
        case .some(.allContent):
            return "Search All Items"
        case .some(.contentType(_, let contentType)):
            return "Search \(sidebarTitle(for: contentType))"
        case .none:
            return "Search Library"
        }
    }

    private func sidebarFilters(for source: MinecraftSource) -> [SidebarFilter] {
        var filters = [
            SidebarFilter(
                title: "All Items",
                iconName: "square.grid.2x2",
                count: source.items.count,
                selection: .allContent(sourceID: source.id)
            )
        ]

        filters.append(
            contentsOf: MinecraftContentType.allCases.compactMap { contentType in
                let count = source.items.filter { $0.contentType == contentType }.count
                guard count > 0 else {
                    return nil
                }

                return SidebarFilter(
                    title: sidebarTitle(for: contentType),
                    iconName: sidebarIcon(for: contentType),
                    count: count,
                    selection: .contentType(sourceID: source.id, contentType: contentType)
                )
            }
        )

        return filters
    }

    private func sidebarTitle(for contentType: MinecraftContentType) -> String {
        switch contentType {
        case .world:
            return "Worlds"
        case .behaviorPack:
            return "Behavior Packs"
        case .resourcePack:
            return "Resource Packs"
        case .skinPack:
            return "Skin Packs"
        case .worldTemplate:
            return "World Templates"
        }
    }

    private func sidebarIcon(for contentType: MinecraftContentType) -> String {
        switch contentType {
        case .world:
            return "globe.europe.africa"
        case .behaviorPack:
            return "shippingbox"
        case .resourcePack:
            return "paintpalette"
        case .skinPack:
            return "person.crop.square"
        case .worldTemplate:
            return "doc.on.doc"
        }
    }

    @ViewBuilder
    private func itemContextMenu(for item: MinecraftContentItem) -> some View {
        Button("Share...") {
            shareItem(item, from: nil)
        }

        Button(exportMenuTitle(for: item)) {
            saveItem(item)
        }

        Divider()

        Button("Reveal in Finder") {
            revealInFinder(item)
        }
    }

    private func exportMenuTitle(for item: MinecraftContentItem) -> String {
        switch item.contentType {
        case .world:
            return "Create Minecraft World File..."
        case .behaviorPack, .resourcePack, .skinPack:
            return "Create Minecraft Pack File..."
        case .worldTemplate:
            return "Create Minecraft Template File..."
        }
    }

    private func primaryActionTitle(for item: MinecraftContentItem) -> String {
        switch item.contentType {
        case .world:
            return "Create Minecraft World File..."
        case .behaviorPack, .resourcePack, .skinPack:
            return "Create Minecraft Pack File..."
        case .worldTemplate:
            return "Create Minecraft Template File..."
        }
    }

    private func primaryActionSubtitle(for item: MinecraftContentItem) -> String {
        switch item.contentType {
        case .world:
            return "Creates a .mcworld file that can be opened on another device to import this world into Minecraft."
        case .behaviorPack, .resourcePack, .skinPack:
            return "Creates a .mcpack file that can be shared or opened on another device."
        case .worldTemplate:
            return "Creates a .mctemplate file that can be opened on another device."
        }
    }

    private func logicalPackReferences(for item: MinecraftContentItem, type: MinecraftContentType) -> [ContentPackReference] {
        guard
            item.contentType == .world,
            let source = currentSource
        else {
            return []
        }

        return source.resolvedPackReferences(for: item.id, type: type)
    }

    private func worldsUsingPack(for item: MinecraftContentItem) -> [MinecraftContentItem] {
        guard
            (item.contentType == .behaviorPack || item.contentType == .resourcePack),
            let source = currentSource,
            let logicalPack = source.logicalPack(forRepresentativeItemID: item.id)
        else {
            return []
        }

        return source.worldsUsingPack(logicalPack.id).sorted(by: sortComparator)
    }

    private func backingPackInstances(for item: MinecraftContentItem) -> [MinecraftContentItem] {
        guard
            (item.contentType == .behaviorPack || item.contentType == .resourcePack),
            let source = currentSource,
            let logicalPack = source.logicalPack(forRepresentativeItemID: item.id)
        else {
            return []
        }

        return source
            .packInstances(for: logicalPack.id)
            .compactMap { source.rawItem(withID: $0.itemID) }
            .sorted(by: WorldScanner.sortItems)
    }

    private func isSuspiciousPack(_ item: MinecraftContentItem) -> Bool {
        guard
            (item.contentType == .behaviorPack || item.contentType == .resourcePack),
            let source = currentSource,
            let logicalPack = source.logicalPack(forRepresentativeItemID: item.id)
        else {
            return false
        }

        return logicalPack.isSuspicious
    }

    private func directoryPreviewEntries(for item: MinecraftContentItem) -> [DirectoryPreviewEntry] {
        let fileManager = FileManager.default

        guard let urls = try? fileManager.contentsOfDirectory(
            at: item.folderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls
            .map { url in
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                return DirectoryPreviewEntry(name: url.lastPathComponent, isDirectory: isDirectory)
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory && !rhs.isDirectory
                }

                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            .prefix(directoryPreviewLimit)
            .map { $0 }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.title = "Add Minecraft Source Folders"

        guard panel.runModal() == .OK else {
            return
        }

        for url in panel.urls {
            let sourceID = library.addSource(at: url)
            selectSourceIfNeeded(sourceID)
        }
    }

    private func handleDroppedProviders(_ providers: [NSItemProvider]) -> Bool {
        let fileURLType = UTType.fileURL.identifier
        let supportedProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(fileURLType) }
        guard !supportedProviders.isEmpty else {
            return false
        }

        for provider in supportedProviders {
            provider.loadDataRepresentation(forTypeIdentifier: fileURLType) { data, _ in
                guard
                    let data,
                    let url = NSURL(absoluteURLWithDataRepresentation: data, relativeTo: nil) as URL?
                else {
                    return
                }

                Task { @MainActor in
                    let sourceID = library.addSource(at: url)
                    selectSourceIfNeeded(sourceID)
                }
            }
        }

        return true
    }

    private func selectSourceIfNeeded(_ sourceID: URL) {
        guard selectedSidebarSelection == nil else {
            return
        }

        selectedSidebarSelection = .allContent(sourceID: sourceID)
    }

    private func removeSource(_ sourceID: URL) {
        let fallbackSourceID = library.sources.first(where: { $0.id != sourceID })?.id
        library.removeSource(withID: sourceID)

        if selectedSidebarSelection?.sourceID == sourceID {
            selectedSidebarSelection = fallbackSourceID.map { .allContent(sourceID: $0) }
        }

        if let selectedItemID, currentSelectedItem?.id != selectedItemID {
            self.selectedItemID = nil
        }
    }

    private func syncSelection(with sourceIDs: [URL]) {
        if let selectedSidebarSelection, !sourceIDs.contains(selectedSidebarSelection.sourceID) {
            self.selectedSidebarSelection = sourceIDs.first.map { .allContent(sourceID: $0) }
        } else if self.selectedSidebarSelection == nil, let firstSourceID = sourceIDs.first {
            self.selectedSidebarSelection = .allContent(sourceID: firstSourceID)
        }

        if let selectedItemID {
            let itemStillExists = library.sources
                .flatMap(\.items)
                .contains(where: { $0.id == selectedItemID })

            if !itemStillExists {
                self.selectedItemID = nil
            }
        }
    }

    private func saveItem(_ item: MinecraftContentItem) {
        guard !isPerformingItemAction else {
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = primaryActionTitle(for: item)
        panel.message = primaryActionSubtitle(for: item)
        panel.nameFieldStringValue = ContentPackageExporter.suggestedBaseFilename(for: item)
        panel.allowedContentTypes = [archiveType(for: item)]

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }

        isPerformingItemAction = true
        library.setItemActionInProgress("Creating \(item.contentType.archiveExtension) file...")

        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try ContentPackageExporter.exportItem(item, to: destinationURL)
                }.value

                let finalURL = ContentPackageExporter.finalArchiveURL(for: item, destinationURL: destinationURL)

                await MainActor.run {
                    isPerformingItemAction = false
                    library.setItemActionSuccess(
                        title: "Created \(finalURL.lastPathComponent)",
                        subtitle: "Ready to move to another device",
                        revealURL: finalURL
                    )
                }
            } catch {
                await MainActor.run {
                    isPerformingItemAction = false
                    library.setItemActionFailure(error.localizedDescription)
                }
            }
        }
    }

    private func shareItem(_ item: MinecraftContentItem, from anchorView: NSView?) {
        guard !isPerformingItemAction else {
            return
        }

        isPerformingItemAction = true
        library.setItemActionInProgress("Preparing \(item.contentType.archiveExtension) file...")

        Task {
            do {
                let shareURL = try await Task.detached(priority: .userInitiated) {
                    try ContentPackageExporter.prepareShareFile(for: item)
                }.value

                await MainActor.run {
                    isPerformingItemAction = false

                    let presentationView = anchorView ?? NSApp.keyWindow?.contentView
                    guard let presentationView else {
                        library.setItemActionFailure("Could not present the share menu.")
                        return
                    }

                    library.setItemActionSuccess(
                        title: "Share ready",
                        subtitle: shareURL.lastPathComponent,
                        revealURL: shareURL
                    )

                    let picker = NSSharingServicePicker(items: [shareURL])
                    let targetRect = anchorView?.bounds ?? presentationView.bounds.insetBy(
                        dx: presentationView.bounds.width / 2,
                        dy: presentationView.bounds.height / 2
                    )
                    picker.show(relativeTo: targetRect, of: presentationView, preferredEdge: .minY)
                }
            } catch {
                await MainActor.run {
                    isPerformingItemAction = false
                    library.setItemActionFailure(error.localizedDescription)
                }
            }
        }
    }

    private func revealInFinder(_ item: MinecraftContentItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.folderURL])
    }

    private func rescanCurrentSource() {
        guard let sourceID = selectedSidebarSelection?.sourceID else {
            return
        }

        library.rescanSource(withID: sourceID)
    }

    private func revealURLInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func archiveType(for item: MinecraftContentItem) -> UTType {
        UTType(filenameExtension: item.contentType.archiveExtension) ?? .data
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
