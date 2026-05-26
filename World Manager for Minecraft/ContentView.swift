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

private enum SidebarSelection: Hashable {
    case allContent(sourceID: URL)
    case contentType(sourceID: URL, contentType: MinecraftContentType)

    var sourceID: URL {
        switch self {
        case .allContent(let sourceID), .contentType(let sourceID, _):
            return sourceID
        }
    }
}

private enum ItemSortMode: String, CaseIterable, Identifiable {
    case name
    case modifiedDate
    case size

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name:
            return "Name"
        case .modifiedDate:
            return "Modified Date"
        case .size:
            return "Size"
        }
    }
}

private struct SidebarFilter: Identifiable, Hashable {
    var id: SidebarSelection { selection }
    let title: String
    let iconName: String
    let count: Int
    let selection: SidebarSelection
}

private struct SourcesSidebarView: View {
    let sources: [MinecraftSource]
    @Binding var selection: SidebarSelection?
    let footerState: SidebarFooterState
    let addSourceAction: () -> Void
    let rescanSourceAction: (MinecraftSource) -> Void
    let removeSourceAction: (MinecraftSource) -> Void
    let revealFooterURLAction: (URL) -> Void
    let filters: (MinecraftSource) -> [SidebarFilter]

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(sources) { source in
                    SourceHeaderRow(title: source.displayName)
                        .listRowSeparator(.hidden)
                        .padding(.top, 6)
                        .contextMenu {
                            Button("Rescan \"\(source.displayName)\"") {
                                rescanSourceAction(source)
                            }

                            Divider()

                            Button("Remove \"\(source.displayName)\"", role: .destructive) {
                                removeSourceAction(source)
                            }
                        }

                    ForEach(filters(source)) { filter in
                        SidebarFilterRow(filter: filter, isIndented: true)
                            .tag(filter.selection as SidebarSelection?)
                    }
                }
            } header: {
                SidebarSourcesSectionHeaderView()
            }
        }
        .listStyle(.sidebar)
        .overlay(alignment: .bottom) {
            if footerState.style != .idle {
                SidebarFooterView(
                    state: footerState,
                    revealAction: revealFooterURLAction
                )
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .toolbar {
            ToolbarItem {
                Button(action: addSourceAction) {
                    Image(systemName: "folder.badge.plus")
                }
                .help("Add Source Folder")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: footerState.style)
    }
}

private struct SidebarFilterRow: View {
    let filter: SidebarFilter
    let isIndented: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: filter.iconName)
                .frame(width: 16)
                .foregroundStyle(.secondary)

            Text(filter.title)

            Spacer()

            Text(filter.count, format: .number)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, isIndented ? 16 : 0)
    }
}

private struct SidebarSourcesSectionHeaderView: View {
    var body: some View {
        Text("Libraries")
            .font(.headline)
            .foregroundStyle(.secondary)
        .textCase(nil)
    }
}

private struct SourceHeaderRow: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct SidebarFooterView: View {
    let state: SidebarFooterState
    let revealAction: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if state.style == .inProgress {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(state.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(primaryColor)
                    .lineLimit(2)
            }

            if let subtitle = state.subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if let revealURL = state.revealURL {
                Button("Reveal in Finder") {
                    revealAction(revealURL)
                }
                .buttonStyle(.link)
                .font(.footnote)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var primaryColor: Color {
        switch state.style {
        case .idle, .inProgress:
            return .primary
        case .failure:
            return .red
        case .success:
            return .appAccent
        }
    }
}

private struct ItemListColumnView<MenuContent: View>: View {
    let isEmpty: Bool
    @Binding var isDropTargeted: Bool
    @Binding var selectedItemID: MinecraftContentItem.ID?
    @Binding var searchText: String
    @Binding var sortMode: ItemSortMode
    let title: String
    let subtitle: String
    let items: [MinecraftContentItem]
    let searchPrompt: String
    let chooseFolderAction: () -> Void
    let dropAction: ([NSItemProvider]) -> Bool
    let refreshAction: () -> Void
    let itemContextMenu: (MinecraftContentItem) -> MenuContent

    var body: some View {
        Group {
            if isEmpty {
                EmptySourcesView(
                    isDropTargeted: isDropTargeted,
                    chooseFolder: chooseFolderAction
                )
                .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted, perform: dropAction)
            } else {
                List(items, selection: $selectedItemID) { item in
                    ContentRowView(item: item)
                        .tag(item.id)
                        .contextMenu {
                            itemContextMenu(item)
                        }
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $searchText, prompt: searchPrompt)
        .navigationTitle(isEmpty ? "Library" : title)
        .navigationSubtitle(isEmpty ? "" : subtitle)
        .toolbar {
            if !isEmpty {
                ToolbarItemGroup {
                    Button(action: refreshAction) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Rescan Source")

                    Menu {
                        Picker("Sort By", selection: $sortMode) {
                            ForEach(ItemSortMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .help("List Options")
                }
            }
        }
    }
}

private struct ItemDetailColumnView: View {
    let item: MinecraftContentItem?
    let behaviorPacks: [ContentPackReference]
    let resourcePacks: [ContentPackReference]
    let worldsUsingPack: [MinecraftContentItem]
    let backingPackInstances: [MinecraftContentItem]
    let isSuspiciousPack: Bool
    let contents: [DirectoryPreviewEntry]
    let directoryPreviewLimit: Int
    let isEmpty: Bool
    let isPerformingItemAction: Bool
    let exportTitle: String?
    let exportAction: () -> Void
    let revealAction: () -> Void
    let shareAction: (NSView?) -> Void

    var body: some View {
        Group {
            if isEmpty {
                Text("Add a source folder to start scanning your Minecraft library")
                    .foregroundStyle(.secondary)
            } else if let item {
                ItemDetailView(
                    item: item,
                    behaviorPacks: behaviorPacks,
                    resourcePacks: resourcePacks,
                    worldsUsingPack: worldsUsingPack,
                    backingPackInstances: backingPackInstances,
                    isSuspiciousPack: isSuspiciousPack,
                    contents: contents,
                    directoryPreviewLimit: directoryPreviewLimit
                )
            } else {
                Text("Select a world or pack to see details")
                    .foregroundStyle(.secondary)
            }
        }
        .toolbar {
            if item != nil {
                ToolbarItemGroup {
                    Button(action: exportAction) {
                        Image(systemName: "arrow.down.circle")
                    }
                    .disabled(isPerformingItemAction)
                    .help(exportTitle ?? "Export")

                    Button(action: revealAction) {
                        Image(systemName: "folder")
                    }
                    .disabled(isPerformingItemAction)
                    .help("Reveal in Finder")

                    SharingPickerButton(
                        title: nil,
                        systemImage: "square.and.arrow.up",
                        isEnabled: !isPerformingItemAction
                    ) { anchorView in
                        shareAction(anchorView)
                    }
                    .help("Share")
                }
            }
        }
    }
}

private struct ContentRowView: View {
    let item: MinecraftContentItem

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ItemThumbnailView(iconURL: item.iconURL)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .lineLimit(1)

                Text(metadataLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if !item.metadataLoaded || !item.sizeLoaded {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var metadataLine: String {
        let sizeText: String
        if let sizeBytes = item.sizeBytes {
            sizeText = ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
        } else if item.metadataLoaded {
            sizeText = "Calculating size..."
        } else {
            sizeText = "Loading metadata..."
        }
        let dateText = item.displayDate.map {
            $0.formatted(date: .abbreviated, time: .omitted)
        } ?? "Date unavailable"

        return "\(item.contentType.rawValue) • \(sizeText) • \(item.displayDateLabel) \(dateText)"
    }
}

private struct ItemDetailView: View {
    let item: MinecraftContentItem
    let behaviorPacks: [ContentPackReference]
    let resourcePacks: [ContentPackReference]
    let worldsUsingPack: [MinecraftContentItem]
    let backingPackInstances: [MinecraftContentItem]
    let isSuspiciousPack: Bool
    let contents: [DirectoryPreviewEntry]
    let directoryPreviewLimit: Int
    @State private var isTechnicalDetailsExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 18) {
                    LargeItemThumbnailView(iconURL: item.iconURL, contentType: item.contentType)
                        .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.displayName)
                            .font(.largeTitle.weight(.semibold))

                        Text(item.contentType.rawValue)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }

                detailCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Details")
                            .font(.headline)

                        if isSuspiciousPack {
                            Label("Manifest UUID is missing or unreadable for this pack.", systemImage: "exclamationmark.triangle")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                        }

                        detailValueRow(title: "Size", value: sizeText)
                        detailValueRow(title: item.displayDateLabel, value: displayDateText)

                        if item.contentType == .world {
                            detailValueRow(
                                title: "Last Played",
                                value: item.lastPlayedDate?.formatted(date: .abbreviated, time: .omitted) ?? "Not available"
                            )
                        }
                    }
                }

                if item.contentType == .world, !behaviorPacks.isEmpty || !resourcePacks.isEmpty {
                    detailCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Packs Used")
                                .font(.headline)

                            if !behaviorPacks.isEmpty {
                                packSection(title: "Behavior Packs", packs: behaviorPacks)
                            }

                            if !resourcePacks.isEmpty {
                                packSection(title: "Resource Packs", packs: resourcePacks)
                            }
                        }
                    }
                }

                if (item.contentType == .behaviorPack || item.contentType == .resourcePack), !worldsUsingPack.isEmpty {
                    detailCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Used By Worlds")
                                .font(.headline)

                            ForEach(worldsUsingPack) { world in
                                HStack(alignment: .top, spacing: 12) {
                                    PackReferenceIconView(iconURL: world.iconURL)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(world.displayName)

                                        Text(worldUsageSecondaryText(for: world))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                if (item.contentType == .behaviorPack || item.contentType == .resourcePack), !backingPackInstances.isEmpty {
                    detailCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Pack Instances")
                                .font(.headline)

                            ForEach(backingPackInstances) { instance in
                                HStack(alignment: .top, spacing: 12) {
                                    PackReferenceIconView(iconURL: instance.iconURL)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(instance.folderName)

                                        Text(packInstanceSecondaryText(for: instance))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                detailCard {
                    DisclosureGroup(isExpanded: $isTechnicalDetailsExpanded) {
                        VStack(alignment: .leading, spacing: 18) {
                            detailRow(title: "Folder ID", value: item.folderID)
                            detailRow(title: "Folder Path", value: item.folderURL.path)
                            detailRow(title: "Collection Root", value: item.collectionRootURL.path)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Contents")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if contents.isEmpty {
                                    Text("No visible files or folders")
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(contents) { entry in
                                        HStack(spacing: 10) {
                                            Image(systemName: entry.isDirectory ? "folder" : "doc")
                                                .foregroundStyle(.secondary)
                                            Text(entry.name)
                                                .lineLimit(1)
                                            Spacer()
                                        }
                                    }

                                    if contents.count == directoryPreviewLimit {
                                        Text("Showing the first \(directoryPreviewLimit) items")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        HStack {
                            Text("Technical Details")
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isTechnicalDetailsExpanded.toggle()
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 450, alignment: .leading)
        }
    }

    @ViewBuilder
    private func detailCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func packSection(title: String, packs: [ContentPackReference]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            ForEach(packs) { pack in
                HStack(alignment: .top, spacing: 12) {
                    PackReferenceIconView(iconURL: pack.iconURL)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(pack.name)

                        if let secondary = packSecondaryText(pack), !secondary.isEmpty {
                            Text(secondary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func detailValueRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
    }

    private var sizeText: String {
        if let sizeBytes = item.sizeBytes {
            return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
        }

        return item.metadataLoaded ? "Calculating..." : "Loading..."
    }

    private var displayDateText: String {
        item.displayDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Unknown"
    }

    private func packSecondaryText(_ pack: ContentPackReference) -> String? {
        let components = [pack.version.map { "v\($0)" }, pack.uuid]
            .compactMap { $0 }
        return components.isEmpty ? nil : components.joined(separator: " • ")
    }

    private func worldUsageSecondaryText(for world: MinecraftContentItem) -> String {
        let dateText = world.displayDate?.formatted(date: .abbreviated, time: .omitted) ?? "Date unavailable"
        return "\(world.displayDateLabel) \(dateText)"
    }

    private func packInstanceSecondaryText(for instance: MinecraftContentItem) -> String {
        if instance.folderURL.pathComponents.contains(MinecraftContentType.world.collectionFolderName) {
            return "Embedded in world copy"
        }

        return "Top-level pack folder"
    }
}

private struct DirectoryPreviewEntry: Identifiable {
    let id = UUID()
    let name: String
    let isDirectory: Bool
}

private struct SharingPickerButton: NSViewRepresentable {
    let title: String?
    let systemImage: String
    let isEnabled: Bool
    let action: (NSView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.target = context.coordinator
        button.action = #selector(Coordinator.didPressButton(_:))
        button.bezelStyle = .texturedRounded
        update(button)
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.action = action
        update(nsView)
    }

    private func update(_ button: NSButton) {
        button.image = NSImage(
            systemSymbolName: systemImage,
            accessibilityDescription: title ?? "Share"
        )
        button.imagePosition = title == nil ? .imageOnly : .imageLeading
        button.title = title ?? ""
        button.isEnabled = isEnabled
    }

    final class Coordinator: NSObject {
        var action: (NSView) -> Void

        init(action: @escaping (NSView) -> Void) {
            self.action = action
        }

        @objc func didPressButton(_ sender: NSButton) {
            action(sender)
        }
    }
}

private struct PackReferenceIconView: View {
    let iconURL: URL?

    var body: some View {
        if let image = loadImage(from: iconURL) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "shippingbox")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                )
        }
    }
}

private struct EmptySourcesView: View {
    let isDropTargeted: Bool
    let chooseFolder: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10, 10]))
                    .foregroundStyle(isDropTargeted ? Color.appAccent : Color.secondary.opacity(0.25))
                    .frame(width: 220, height: 160)

                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(isDropTargeted ? Color.appAccent : Color.secondary)
            }

            VStack(spacing: 8) {
                Text("Add a Minecraft Source")
                    .font(.title2)

                Text("Choose a copied Minecraft folder or drop one here to start scanning worlds, packs, and templates.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            Button("Choose Minecraft Folder...") {
                chooseFolder()
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

private struct ItemThumbnailView: View {
    let iconURL: URL?

    var body: some View {
        if let image = loadImage(from: iconURL) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        } else {
            RoundedRectangle(cornerRadius: 7)
                .fill(.quaternary)
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "shippingbox")
                        .foregroundStyle(.secondary)
                )
        }
    }
}

private struct LargeItemThumbnailView: View {
    let iconURL: URL?
    let contentType: MinecraftContentType

    var body: some View {
        if let image = loadImage(from: iconURL) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(image.size, contentMode: .fit)
                .frame(maxWidth: 420, maxHeight: 340)
                .clipShape(RoundedRectangle(cornerRadius: 28))
        } else {
            RoundedRectangle(cornerRadius: 28)
                .fill(.quaternary)
                .frame(maxWidth: 420, minHeight: 260, maxHeight: 340)
                .overlay(
                    Image(systemName: fallbackIconName)
                        .font(.system(size: 56))
                        .foregroundStyle(.secondary)
                )
        }
    }

    private var fallbackIconName: String {
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
}

private func loadImage(from url: URL?) -> NSImage? {
    guard let url else {
        return nil
    }

    return NSImage(contentsOf: url)
}

private extension Color {
    static let appAccent = Color("AccentColor")
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
