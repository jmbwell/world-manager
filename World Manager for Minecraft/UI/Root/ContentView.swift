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
    @StateObject private var library: SourceLibrary
    @State private var selectedItemID: MinecraftContentItem.ID?
    @State private var selectedSidebarSelection: SidebarSelection?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var searchText = ""
    @State private var isDropTargeted = false
    @State private var isPerformingItemAction = false
    @State private var isShowingDeviceSourceSheet = false
    @State private var sortMode: ItemSortMode = .name
    @State private var directoryPreviewContents: [DirectoryEntry] = []

    private let connectedDeviceAccess: AppleMobileDeviceSourceAccess
    private let deviceSourceFactory: ConnectedDeviceSourceFactory
    private let directoryPreviewLimit = 12

    init() {
        let connectedDeviceAccess = AppleMobileDeviceSourceAccess()
        self.connectedDeviceAccess = connectedDeviceAccess
        self.deviceSourceFactory = ConnectedDeviceSourceFactory()
        _library = StateObject(
            wrappedValue: SourceLibrary(
                sourceAccessMethod: SourceAccessCoordinator(
                    connectedDeviceAccess: connectedDeviceAccess
                ),
                connectedDeviceAccessMethod: connectedDeviceAccess
            )
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SourcesSidebarView(
                sources: library.sidebarSources,
                connectedDevices: library.connectedDevices,
                selection: $selectedSidebarSelection,
                addSourceAction: pickFolder,
                addDeviceSourceAction: { isShowingDeviceSourceSheet = true },
                addConnectedDeviceAction: addConnectedDeviceSource(from:),
                rescanSourceAction: { source in
                    selectedSidebarSelection = .source(sourceID: source.id)
                    selectedItemID = nil
                    library.rescanSource(withID: source.id)
                },
                removeSourceAction: { source in
                    removeSource(source.id)
                },
                filters: sidebarFilters(for:)
            )
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 380)
        } content: {
            ItemListColumnView(
                isEmpty: library.visibleSources.isEmpty && library.connectedDevices.isEmpty,
                isDropTargeted: $isDropTargeted,
                selectedItemID: $selectedItemID,
                searchText: $searchText,
                sortMode: $sortMode,
                showsHeader: shouldShowItemListHeader,
                sourceName: currentSourceDisplayName,
                showsSourceName: !isSidebarVisible,
                title: collectionHeaderTitle,
                subtitle: collectionHeaderSubtitle,
                showsSubtitle: isSearching,
                isRefreshing: currentSource?.isScanning == true,
                items: displayedItems,
                searchPrompt: searchPrompt,
                chooseFolderAction: pickFolder,
                dropAction: handleDroppedProviders(_:),
                itemContextMenu: itemContextMenu(for:)
            )
            .navigationSplitViewColumnWidth(min: 340, ideal: 400, max: 460)
        } detail: {
            ItemDetailColumnView(
                item: currentSelectedItem,
                source: currentSource,
                showsSourceDetails: currentSelectedItem == nil && isSourceOverviewSelection,
                behaviorPacks: currentSelectedItem.map { logicalPackReferences(for: $0, type: .behaviorPack) } ?? [],
                resourcePacks: currentSelectedItem.map { logicalPackReferences(for: $0, type: .resourcePack) } ?? [],
                worldsUsingPack: currentSelectedItem.map(worldsUsingPack(for:)) ?? [],
                backingPackInstances: currentSelectedItem.map(backingPackInstances(for:)) ?? [],
                isSuspiciousPack: currentSelectedItem.map(isSuspiciousPack(_:)) ?? false,
                contents: directoryPreviewContents,
                directoryPreviewLimit: directoryPreviewLimit,
                isEmpty: library.visibleSources.isEmpty && library.connectedDevices.isEmpty,
                isPerformingItemAction: isPerformingItemAction,
                areFileActionsEnabled: areCurrentItemFileActionsEnabled,
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
            if library.isRestoringPersistedSources && library.visibleSources.isEmpty && library.connectedDevices.isEmpty {
                LaunchRestoreOverlayView()
            }
        }
        .sheet(isPresented: $isShowingDeviceSourceSheet) {
            ConnectedDeviceSourcePickerView(
                deviceDiscoveryService: connectedDeviceAccess,
                sourceFactory: deviceSourceFactory,
                onAddSource: { source in
                    let sourceID = library.addSource(source, shouldPersist: true, shouldScan: true)
                    selectedSidebarSelection = .source(sourceID: sourceID)
                    selectedItemID = nil
                    isShowingDeviceSourceSheet = false
                }
            )
        }
        .task {
            AppTerminationCoordinator.shared.register(library: library)
        }
        .disabled(library.isRestoringPersistedSources && library.visibleSources.isEmpty && library.connectedDevices.isEmpty)
        .onChange(of: displayedItems.map(\.id)) { _, filteredIDs in
            guard let selectedItemID, !filteredIDs.contains(selectedItemID) else {
                return
            }

            self.selectedItemID = nil
        }
        .onChange(of: selectedSidebarSelection) { _, selection in
            guard let selection else {
                return
            }

            if case .source = selection {
                selectedItemID = nil
            }
        }
        .onChange(of: library.sources.map(\.id)) { _, _ in
            syncSelection(with: library.visibleSources.map(\.id))
        }
        .onChange(of: library.connectedDevices.map { "\($0.id)::\($0.matchedSourceID?.absoluteString ?? "nil")" }) { _, _ in
            syncSelection(with: library.visibleSources.map(\.id))
        }
        .task(id: currentSelectedItem?.id) {
            await refreshDirectoryPreviewContents()
        }
    }

    private var scopedItems: [MinecraftContentItem] {
        guard let selectedSidebarSelection else {
            return []
        }

        switch selectedSidebarSelection {
        case .source(let sourceID), .allContent(let sourceID):
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
            return library.visibleSources.first
        }

        return library.source(withID: sourceID)
    }

    private var currentSelectedItem: MinecraftContentItem? {
        guard let selectedItemID else {
            return nil
        }

        return library.visibleSources
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
        case .source, .allContent:
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

    private var currentSourceDisplayName: String {
        currentSource?.displayName ?? "Library"
    }

    private var currentCollectionStatus: String? {
        guard let currentSource else {
            return nil
        }

        if currentSource.isScanning {
            return currentSource.scanStatus
        }

        if let scanError = currentSource.scanError, !scanError.isEmpty {
            return scanError
        }

        if !currentSource.scanStatus.isEmpty {
            return currentSource.scanStatus
        }

        if let lastScanDate = currentSource.lastScanDate {
            return "Last scanned \(lastScanDate.formatted(date: .abbreviated, time: .shortened))"
        }

        return nil
    }

    private var areCurrentItemFileActionsEnabled: Bool {
        guard currentSelectedItem != nil else {
            return false
        }

        return currentSource?.availability == .available
    }

    private var searchScopeTitle: String {
        switch selectedSidebarSelection {
        case .some(.source(let sourceID)):
            return library.source(withID: sourceID)?.displayName ?? "Library"
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

    private var isSidebarVisible: Bool {
        columnVisibility == .all
    }

    private var shouldShowItemListHeader: Bool {
        isSearching || !isSidebarVisible
    }

    private var collectionCountNoun: String {
        guard let selectedSidebarSelection else {
            return "items"
        }

        switch selectedSidebarSelection {
        case .source, .allContent:
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
        case .some(.source(let sourceID)):
            let sourceName = library.source(withID: sourceID)?.displayName ?? "Library"
            return "Search \(sourceName)"
        case .some(.allContent):
            return "Search All Items"
        case .some(.contentType(_, let contentType)):
            return "Search \(sidebarTitle(for: contentType))"
        case .none:
            return "Search Library"
        }
    }

    private func sidebarFilters(for source: MinecraftSource) -> [SidebarFilter] {
        MinecraftContentType.allCases.compactMap { contentType in
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
    }

    private var isSourceOverviewSelection: Bool {
        guard let selectedSidebarSelection else {
            return false
        }

        if case .source = selectedSidebarSelection {
            return true
        }

        return false
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
        .disabled(!areFileActionsEnabled(for: item))

        Button(exportMenuTitle(for: item)) {
            saveItem(item)
        }
        .disabled(!areFileActionsEnabled(for: item))

        Divider()

        Button("Reveal in Finder") {
            revealInFinder(item)
        }
        .disabled(!areFileActionsEnabled(for: item))
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

    private func refreshDirectoryPreviewContents() async {
        guard let item = currentSelectedItem, let source = currentSource else {
            await MainActor.run {
                directoryPreviewContents = []
            }
            return
        }

        let contents = (try? await library.listContents(for: item, in: source)) ?? []
        guard !Task.isCancelled else {
            return
        }

        await MainActor.run {
            directoryPreviewContents = Array(contents.prefix(directoryPreviewLimit))
        }
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

        selectedSidebarSelection = .source(sourceID: sourceID)
    }

    private func removeSource(_ sourceID: URL) {
        let fallbackSourceID = library.visibleSources.first(where: { $0.id != sourceID })?.id
        library.removeSource(withID: sourceID)

        if selectedSidebarSelection?.sourceID == sourceID {
            selectedSidebarSelection = fallbackSourceID.map { .source(sourceID: $0) }
        }

        if let selectedItemID, currentSelectedItem?.id != selectedItemID {
            self.selectedItemID = nil
        }
    }

    private func addConnectedDeviceSource(from entry: ConnectedDeviceSidebarEntry) {
        guard let container = entry.minecraftContainer else {
            return
        }

        let source = deviceSourceFactory.makeSource(device: entry.device, container: container)
        let sourceID = library.addSource(source, shouldPersist: true, shouldScan: true)
        selectedSidebarSelection = .source(sourceID: sourceID)
        selectedItemID = nil
    }

    private func syncSelection(with sourceIDs: [URL]) {
        if let selectedSidebarSelection, !sourceIDs.contains(selectedSidebarSelection.sourceID) {
            self.selectedSidebarSelection = sourceIDs.first.map { .source(sourceID: $0) }
        } else if self.selectedSidebarSelection == nil, let firstSourceID = sourceIDs.first {
            self.selectedSidebarSelection = .source(sourceID: firstSourceID)
        }

        if let selectedItemID {
            let itemStillExists = library.visibleSources
                .flatMap(\.items)
                .contains(where: { $0.id == selectedItemID })

            if !itemStillExists {
                self.selectedItemID = nil
            }
        }
    }

    private func areFileActionsEnabled(for item: MinecraftContentItem) -> Bool {
        guard let source = library.visibleSources.first(where: { $0.items.contains(where: { $0.id == item.id }) }) else {
            return false
        }

        return source.availability == .available
    }

    private func saveItem(_ item: MinecraftContentItem) {
        guard !isPerformingItemAction, areFileActionsEnabled(for: item) else {
            return
        }
        let source = currentSource

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.showsTagField = false
        panel.title = exportMenuTitle(for: item)
        panel.prompt = "Save"
        panel.nameFieldStringValue = ContentPackageExporter.suggestedBaseFilename(for: item)
        panel.allowedContentTypes = [archiveType(for: item)]

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }

        isPerformingItemAction = true

        Task {
            do {
                let finalURL = try await Task.detached(priority: .userInitiated) {
                    try await ContentPackageExporter.createArchiveFile(
                        for: item,
                        source: source,
                        destinationURL: destinationURL
                    )
                }.value

                await MainActor.run {
                    isPerformingItemAction = false
                    _ = finalURL
                }
            } catch {
                await MainActor.run {
                    isPerformingItemAction = false
                }
            }
        }
    }

    private func shareItem(_ item: MinecraftContentItem, from anchorView: NSView?) {
        guard !isPerformingItemAction, areFileActionsEnabled(for: item) else {
            return
        }
        let source = currentSource

        isPerformingItemAction = true

        Task {
            do {
                let shareURL = try await Task.detached(priority: .userInitiated) {
                    try await ContentPackageExporter.createArchiveFile(
                        for: item,
                        source: source
                    )
                }.value

                await MainActor.run {
                    isPerformingItemAction = false

                    let presentationView = anchorView ?? NSApp.keyWindow?.contentView
                    guard let presentationView else {
                        return
                    }

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
                }
            }
        }
    }

    private func revealInFinder(_ item: MinecraftContentItem) {
        guard let source = currentSource, areFileActionsEnabled(for: item) else {
            return
        }

        if source.origin.kind == .localFolder {
            NSWorkspace.shared.activateFileViewerSelecting([item.folderURL])
            return
        }

        guard !isPerformingItemAction else {
            return
        }

        isPerformingItemAction = true

        Task {
            do {
                let revealURL = try await library.materializeItem(item, in: source)

                await MainActor.run {
                    isPerformingItemAction = false
                    NSWorkspace.shared.activateFileViewerSelecting([revealURL])
                }
            } catch {
                await MainActor.run {
                    isPerformingItemAction = false
                }
            }
        }
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
