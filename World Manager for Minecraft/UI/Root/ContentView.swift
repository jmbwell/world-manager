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
    @State private var showsProjectionLoadingState = false
    @State private var itemListProjection = ItemCollectionProjection.placeholder(
        for: ItemCollectionProjectionRequest(
            selection: nil,
            searchText: "",
            sortMode: .name,
            source: nil
        )
    )

    private let connectedDeviceAccess: AppleMobileDeviceSourceAccess
    private let deviceSourceFactory: ConnectedDeviceSourceFactory
    private let itemActionService: ContentItemActionService
    private let directoryPreviewLimit = 12
    private let projectionLoadingDelay: Duration = .milliseconds(150)

    init() {
        let dependencies = ContentViewDependencies.makeDefault()
        self.connectedDeviceAccess = dependencies.connectedDeviceAccess
        self.deviceSourceFactory = dependencies.deviceSourceFactory
        self.itemActionService = dependencies.itemActionService
        _library = StateObject(
            wrappedValue: dependencies.library
        )
    }

    var body: some View {
        let isEmptyLibrary = library.visibleSources.isEmpty && library.connectedDevices.isEmpty
        let resolvedCurrentSource = currentSource
        let currentProjectionRequest = ItemCollectionProjectionRequest(
            selection: selectedSidebarSelection,
            searchText: searchText,
            sortMode: sortMode,
            source: resolvedCurrentSource
        )
        let fastPathProjection = fastProjection(for: currentProjectionRequest, previousRequest: itemListProjection.request)
        let reusesCurrentProjectedItems =
            itemListProjection.request.selection == currentProjectionRequest.selection &&
            itemListProjection.request.source?.id == currentProjectionRequest.source?.id
        let resolvedItemListProjection = if let fastPathProjection {
            fastPathProjection
        } else if itemListProjection.request == currentProjectionRequest {
            itemListProjection
        } else {
            ItemCollectionProjection.placeholder(for: currentProjectionRequest)
        }
        let resolvedCurrentSelectedItem = currentSelectedItem(in: resolvedCurrentSource)
        let resolvedDisplayedItems: [MinecraftContentItem] = if let fastPathProjection {
            fastPathProjection.items
        } else if reusesCurrentProjectedItems {
            itemListProjection.items
        } else {
            []
        }

        NavigationSplitView(columnVisibility: $columnVisibility) {
            SourcesSidebarView(
                sources: library.sidebarSources,
                connectedDevices: library.connectedDevices,
                selection: sidebarSelectionBinding,
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
                isEmpty: isEmptyLibrary,
                isDropTargeted: $isDropTargeted,
                selectedItemID: $selectedItemID,
                searchText: $searchText,
                sortMode: $sortMode,
                showsHeader: shouldShowItemListHeader,
                sourceName: resolvedItemListProjection.sourceName,
                showsSourceName: !isSidebarVisible,
                title: resolvedItemListProjection.title,
                subtitle: resolvedItemListProjection.subtitle,
                showsSubtitle: isSearching || showsProjectionLoadingState,
                isRefreshing: resolvedCurrentSource?.isScanning == true,
                showsProjectionLoadingState: showsProjectionLoadingState,
                items: resolvedDisplayedItems,
                searchPrompt: resolvedItemListProjection.searchPrompt,
                chooseFolderAction: pickFolder,
                dropAction: handleDroppedProviders(_:),
                itemContextMenu: itemContextMenu(for:)
            )
            .navigationSplitViewColumnWidth(min: 340, ideal: 400, max: 460)
        } detail: {
            ItemDetailColumnView(
                item: resolvedCurrentSelectedItem,
                source: resolvedCurrentSource,
                showsSourceDetails: resolvedCurrentSelectedItem == nil && isSourceOverviewSelection,
                behaviorPacks: resolvedCurrentSelectedItem.map { logicalPackReferences(for: $0, type: .behaviorPack) } ?? [],
                resourcePacks: resolvedCurrentSelectedItem.map { logicalPackReferences(for: $0, type: .resourcePack) } ?? [],
                worldsUsingPack: resolvedCurrentSelectedItem.map(worldsUsingPack(for:)) ?? [],
                backingPackInstances: resolvedCurrentSelectedItem.map(backingPackInstances(for:)) ?? [],
                isSuspiciousPack: resolvedCurrentSelectedItem.map(isSuspiciousPack(_:)) ?? false,
                contents: directoryPreviewContents,
                directoryPreviewLimit: directoryPreviewLimit,
                isEmpty: isEmptyLibrary,
                isPerformingItemAction: isPerformingItemAction,
                areFileActionsEnabled: areCurrentItemFileActionsEnabled,
                exportTitle: resolvedCurrentSelectedItem.map(primaryActionTitle(for:)),
                exportAction: {
                    guard let item = resolvedCurrentSelectedItem else {
                        return
                    }

                    saveItem(item)
                },
                revealAction: {
                    guard let item = resolvedCurrentSelectedItem else {
                        return
                    }

                    revealInFinder(item)
                },
                shareAction: { anchorView in
                    guard let item = resolvedCurrentSelectedItem else {
                        return
                    }

                    shareItem(item, from: anchorView)
                }
            )
            .frame(minWidth: 450)
        }
        .overlay {
            if library.isRestoringPersistedSources && isEmptyLibrary {
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
        .disabled(library.isRestoringPersistedSources && isEmptyLibrary)
        .onChange(of: resolvedDisplayedItems.map(\.id)) { _, filteredIDs in
            guard let selectedItemID, !filteredIDs.contains(selectedItemID) else {
                return
            }

            self.selectedItemID = nil
        }
        .onChange(of: library.sources.map(\.id)) { _, _ in
            syncSelection(with: library.visibleSources.map(\.id))
        }
        .onChange(of: library.connectedDevices.map { "\($0.id)::\($0.matchedSourceID?.absoluteString ?? "nil")" }) { _, _ in
            syncSelection(with: library.visibleSources.map(\.id))
        }
        .task(id: currentProjectionRequest) {
            let request = currentProjectionRequest
            if let fastPathProjection = fastProjection(for: request, previousRequest: itemListProjection.request) {
                showsProjectionLoadingState = false
                itemListProjection = fastPathProjection
                return
            }

            let projection = await Task.detached(priority: .userInitiated) {
                ItemCollectionProjector.makeProjection(for: request)
            }.value
            guard !Task.isCancelled else {
                return
            }
            showsProjectionLoadingState = false
            itemListProjection = projection
        }
        .task(id: currentProjectionRequest) {
            showsProjectionLoadingState = false

            guard itemListProjection.request != currentProjectionRequest else {
                return
            }

            guard fastProjection(for: currentProjectionRequest, previousRequest: itemListProjection.request) == nil else {
                return
            }

            try? await Task.sleep(for: projectionLoadingDelay)
            guard !Task.isCancelled else {
                return
            }

            if itemListProjection.request != currentProjectionRequest {
                showsProjectionLoadingState = true
            }
        }
        .task(id: resolvedCurrentSelectedItem?.id) {
            await refreshDirectoryPreviewContents()
        }
    }

    private var sidebarSelectionBinding: Binding<SidebarSelection?> {
        Binding(
            get: { selectedSidebarSelection },
            set: { newSelection in
                if newSelection != selectedSidebarSelection {
                    selectedItemID = nil
                }

                selectedSidebarSelection = newSelection
            }
        )
    }

    private var currentSource: MinecraftSource? {
        guard let sourceID = selectedSidebarSelection?.sourceID else {
            return library.visibleSources.first
        }

        return library.source(withID: sourceID)
    }

    private func currentSelectedItem(in source: MinecraftSource?) -> MinecraftContentItem? {
        guard let selectedItemID else {
            return nil
        }

        if let source,
           let item = source.items.first(where: { $0.id == selectedItemID }) {
            return item
        }

        if let sourceID = library.sourceID(forItemID: selectedItemID),
           let source = library.source(withID: sourceID) {
            return source.items.first(where: { $0.id == selectedItemID })
        }

        return nil
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

    private var areCurrentItemFileActionsEnabled: Bool {
        guard currentSelectedItem(in: currentSource) != nil else {
            return false
        }

        return currentSource?.availability == .available
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

    private func sidebarFilters(for source: MinecraftSource) -> [SidebarFilter] {
        return MinecraftContentType.allCases.compactMap { contentType in
            guard let count = source.displayItemCountsByType[contentType], count > 0 else {
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
        guard let source = currentSource,
              let item = currentSelectedItem(in: source) else {
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

        if let selectedItemID, currentSelectedItem(in: currentSource)?.id != selectedItemID {
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
            if !library.containsItem(withID: selectedItemID) {
                self.selectedItemID = nil
            }
        }
    }

    private func areFileActionsEnabled(for item: MinecraftContentItem) -> Bool {
        guard
            let sourceID = library.sourceID(forItemID: item.id),
            let source = library.source(withID: sourceID)
        else {
            return false
        }

        return source.availability == .available && source.capabilities.canExportPortablePackages
    }

    private func sourceForItem(_ item: MinecraftContentItem) -> MinecraftSource? {
        guard let sourceID = library.sourceID(forItemID: item.id) else {
            return nil
        }

        return library.source(withID: sourceID)
    }

    private func fastProjection(
        for request: ItemCollectionProjectionRequest,
        previousRequest: ItemCollectionProjectionRequest
    ) -> ItemCollectionProjection? {
        guard
            let sourceID = request.source?.id,
            sourceID == previousRequest.source?.id,
            request.searchText == previousRequest.searchText,
            request.sortMode == previousRequest.sortMode,
            request.selection != previousRequest.selection
        else {
            return nil
        }

        return ItemCollectionProjector.makeProjection(for: request)
    }

    private func saveItem(_ item: MinecraftContentItem) {
        guard !isPerformingItemAction, areFileActionsEnabled(for: item) else {
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.showsTagField = false
        panel.title = exportMenuTitle(for: item)
        panel.prompt = "Save"
        panel.nameFieldStringValue = itemActionService.suggestedFilename(for: item)
        panel.allowedContentTypes = [archiveType(for: item)]

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }

        isPerformingItemAction = true

        Task {
            do {
                guard let source = currentSource else {
                    await MainActor.run {
                        isPerformingItemAction = false
                    }
                    return
                }

                let finalURL = try await Task.detached(priority: .userInitiated) {
                    let representation = try await library.externalRepresentation(
                        for: item,
                        in: source,
                        preferredKind: .portablePackage
                    )
                    return try itemActionService.persistExternalRepresentation(
                        representation,
                        to: destinationURL
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

        isPerformingItemAction = true

        Task {
            do {
                guard let source = currentSource else {
                    await MainActor.run {
                        isPerformingItemAction = false
                    }
                    return
                }

                let shareURL = try await Task.detached(priority: .userInitiated) {
                    let representation = try await library.externalRepresentation(
                        for: item,
                        in: source,
                        preferredKind: .portablePackage
                    )
                    return representation.url
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

        guard !isPerformingItemAction else {
            return
        }

        isPerformingItemAction = true

        Task {
            do {
                let representation = try await library.externalRepresentation(
                    for: item,
                    in: source,
                    preferredKind: .nativeFolder
                )

                await MainActor.run {
                    isPerformingItemAction = false
                    NSWorkspace.shared.activateFileViewerSelecting([representation.url])
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

    private func dragProvider(for item: MinecraftContentItem) -> NSItemProvider {
        let provider = NSItemProvider()
        let contentType = archiveType(for: item)
        provider.suggestedName = itemActionService.suggestedArchiveFilename(for: item)

        provider.registerFileRepresentation(
            forTypeIdentifier: contentType.identifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            guard let source = sourceForItem(item), areFileActionsEnabled(for: item) else {
                completion(nil, false, SourceAccessError.accessFailed(reason: "This item is not currently available for export."))
                return nil
            }

            let task = Task {
                do {
                    let representation = try await library.externalRepresentation(
                        for: item,
                        in: source,
                        preferredKind: .portablePackage
                    )
                    completion(representation.url, representation.isTemporary, nil)
                } catch {
                    completion(nil, false, error)
                }
            }

            let progress = Progress(totalUnitCount: 1)
            progress.cancellationHandler = {
                task.cancel()
            }
            return progress
        }

        return provider
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
