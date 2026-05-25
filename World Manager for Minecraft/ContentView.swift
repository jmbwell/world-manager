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
    @State private var selectedItem: MinecraftContentItem?
    @State private var selectedSidebarSelection: SidebarSelection?
    @State private var searchText = ""
    @State private var isDropTargeted = false
    @State private var isPerformingItemAction = false

    private let directoryPreviewLimit = 12

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selectedSidebarSelection) {
                    ForEach(library.sources) { source in
                        Section(source.displayName) {
                            ForEach(sidebarFilters(for: source)) { filter in
                                SidebarFilterRow(filter: filter)
                                    .tag(filter.selection as SidebarSelection?)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .navigationTitle("Sources")

                Divider()

                SidebarFooterView(
                    state: library.sidebarFooterState,
                    revealAction: revealURLInFinder(_:)
                )
            }
        } content: {
            if library.sources.isEmpty {
                EmptySourcesView(
                    isDropTargeted: isDropTargeted,
                    chooseFolder: pickFolder
                )
                .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted, perform: handleDroppedProviders)
            } else {
                VStack(spacing: 0) {
                    ContentCollectionHeaderView(
                        title: collectionHeaderTitle,
                        subtitle: collectionHeaderSubtitle,
                        prompt: searchPrompt,
                        searchText: $searchText
                    )

                    Divider()

                    List(filteredItems, selection: $selectedItem) { item in
                        ContentRowView(item: item)
                            .tag(item)
                            .contextMenu {
                                itemContextMenu(for: item)
                            }
                    }
                    .listStyle(.inset)
                }
            }
        } detail: {
            if library.sources.isEmpty {
                Text("Add a source folder to start scanning Minecraft content")
                    .foregroundStyle(.secondary)
            } else if let selectedItem = currentSelectedItem {
                ItemDetailView(
                    item: selectedItem,
                    behaviorPacks: packReferences(for: selectedItem, type: .behaviorPack),
                    resourcePacks: packReferences(for: selectedItem, type: .resourcePack),
                    contents: directoryPreviewEntries(for: selectedItem),
                    directoryPreviewLimit: directoryPreviewLimit,
                    isPerformingItemAction: isPerformingItemAction,
                    primaryActionTitle: primaryActionTitle(for: selectedItem),
                    primaryActionSubtitle: primaryActionSubtitle(for: selectedItem),
                    primaryAction: { saveItem(selectedItem) },
                    shareAction: { anchorView in shareItem(selectedItem, from: anchorView) },
                    revealAction: { revealInFinder(selectedItem) }
                )
            } else {
                Text("Select a world or pack to see details")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Minecraft World Manager")
        .tint(.minecraftAccent)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let selectedExportableItem = selectedExportableItem {
                    SharingPickerButton(
                        title: nil,
                        systemImage: "square.and.arrow.up",
                        isEnabled: !isPerformingItemAction
                    ) { anchorView in
                        shareItem(selectedExportableItem, from: anchorView)
                    }
                    .help("Share")

                    Button {
                        saveItem(selectedExportableItem)
                    } label: {
                        Label("Export", systemImage: "arrow.down.circle")
                    }
                    .disabled(isPerformingItemAction)

                    Button {
                        revealInFinder(selectedExportableItem)
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                    .disabled(isPerformingItemAction)
                }

                Button {
                    pickFolder()
                } label: {
                    Label("Add Source", systemImage: "plus")
                }

                if let currentSource = currentSource {
                    Menu {
                        Button("Rescan \"\(currentSource.displayName)\"") {
                            library.rescanSource(withID: currentSource.id)
                        }

                        Divider()

                        Button("Remove \"\(currentSource.displayName)\"", role: .destructive) {
                            removeSource(currentSource.id)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .help("Source actions")
                }
            }
        }
        .onChange(of: filteredItems.map(\.id)) { _, filteredIDs in
            guard let selectedItem, !filteredIDs.contains(selectedItem.id) else {
                return
            }

            self.selectedItem = nil
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

    private var currentSource: MinecraftSource? {
        guard let sourceID = selectedSidebarSelection?.sourceID else {
            return library.sources.first
        }

        return library.source(withID: sourceID)
    }

    private var currentSelectedItem: MinecraftContentItem? {
        guard let selectedItem else {
            return nil
        }

        return library.sources
            .flatMap(\.items)
            .first(where: { $0.id == selectedItem.id }) ?? selectedItem
    }

    private var selectedExportableItem: MinecraftContentItem? {
        currentSelectedItem
    }

    private var collectionHeaderTitle: String {
        guard let selectedSidebarSelection else {
            return "Minecraft Content"
        }

        switch selectedSidebarSelection {
        case .allContent:
            return "All Content"
        case .contentType(_, let contentType):
            return sidebarTitle(for: contentType)
        }
    }

    private var collectionHeaderSubtitle: String {
        let totalCount = scopedItems.count
        let filteredCount = filteredItems.count
        let noun = collectionCountNoun

        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(totalCount.formatted(.number)) \(noun)"
        }

        return "\(filteredCount.formatted(.number)) of \(totalCount.formatted(.number)) \(noun)"
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
            return "Search All Content"
        case .some(.contentType(_, let contentType)):
            return "Search \(sidebarTitle(for: contentType))"
        case .none:
            return "Search Content"
        }
    }

    private func sidebarFilters(for source: MinecraftSource) -> [SidebarFilter] {
        var filters = [
            SidebarFilter(
                title: "All Content",
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

    private func packReferences(for item: MinecraftContentItem, type: MinecraftContentType) -> [ContentPackReference] {
        item.packReferences.filter { $0.type == type }
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

        if let selectedItem, currentSelectedItem?.id != selectedItem.id {
            self.selectedItem = nil
        }
    }

    private func syncSelection(with sourceIDs: [URL]) {
        if let selectedSidebarSelection, !sourceIDs.contains(selectedSidebarSelection.sourceID) {
            self.selectedSidebarSelection = sourceIDs.first.map { .allContent(sourceID: $0) }
        } else if self.selectedSidebarSelection == nil, let firstSourceID = sourceIDs.first {
            self.selectedSidebarSelection = .allContent(sourceID: firstSourceID)
        }

        if let selectedItem {
            let itemStillExists = library.sources
                .flatMap(\.items)
                .contains(where: { $0.id == selectedItem.id })

            if !itemStillExists {
                self.selectedItem = nil
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

private struct SidebarFilter: Identifiable, Hashable {
    var id: SidebarSelection { selection }
    let title: String
    let iconName: String
    let count: Int
    let selection: SidebarSelection
}

private struct SidebarFilterRow: View {
    let filter: SidebarFilter

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
        .background(.bar)
    }

    private var primaryColor: Color {
        switch state.style {
        case .idle, .inProgress:
            return .primary
        case .failure:
            return .red
        case .success:
            return .minecraftAccent
        }
    }
}

private struct ContentCollectionHeaderView: View {
    let title: String
    let subtitle: String
    let prompt: String
    @Binding var searchText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2.weight(.semibold))

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField(prompt, text: $searchText)
                .textFieldStyle(.roundedBorder)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
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

            if !item.metadataLoaded {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var metadataLine: String {
        let sizeText = item.sizeBytes.map {
            ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
        } ?? "Size unavailable"
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
    let contents: [DirectoryPreviewEntry]
    let directoryPreviewLimit: Int
    let isPerformingItemAction: Bool
    let primaryActionTitle: String
    let primaryActionSubtitle: String
    let primaryAction: () -> Void
    let shareAction: (NSView) -> Void
    let revealAction: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    LargeItemThumbnailView(iconURL: item.iconURL)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.displayName)
                            .font(.largeTitle.weight(.semibold))

                        Text(item.contentType.rawValue)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 18) {
                        metadataChip(title: "Size", value: sizeText)
                        metadataChip(title: item.displayDateLabel, value: displayDateText)

                        if item.lastPlayedDate == nil, item.contentType == .world {
                            metadataChip(title: "Last Played", value: "Not available")
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Actions")
                        .font(.headline)

                    Button(primaryActionTitle) {
                        primaryAction()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isPerformingItemAction)

                    Text(primaryActionSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        SharingPickerButton(
                            title: "Share...",
                            systemImage: "square.and.arrow.up",
                            isEnabled: !isPerformingItemAction
                        ) { anchorView in
                            shareAction(anchorView)
                        }

                        Button("Reveal in Finder") {
                            revealAction()
                        }
                        .disabled(isPerformingItemAction)
                    }
                }

                if item.contentType == .world {
                    if !behaviorPacks.isEmpty || !resourcePacks.isEmpty {
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

                DisclosureGroup("Technical Details") {
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
                }
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private func metadataChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.medium))
        }
    }

    @ViewBuilder
    private func packSection(title: String, packs: [ContentPackReference]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            ForEach(packs) { pack in
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

    private var sizeText: String {
        item.sizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Unknown"
    }

    private var displayDateText: String {
        item.displayDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Unknown"
    }

    private func packSecondaryText(_ pack: ContentPackReference) -> String? {
        let components = [pack.version.map { "v\($0)" }, pack.uuid]
            .compactMap { $0 }
        return components.isEmpty ? nil : components.joined(separator: " • ")
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

private struct EmptySourcesView: View {
    let isDropTargeted: Bool
    let chooseFolder: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10, 10]))
                    .foregroundStyle(isDropTargeted ? Color.minecraftAccent : Color.secondary.opacity(0.25))
                    .frame(width: 220, height: 160)

                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(isDropTargeted ? Color.minecraftAccent : Color.secondary)
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

    var body: some View {
        if let image = loadImage(from: iconURL) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 180, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(.quaternary)
                .frame(width: 180, height: 180)
                .overlay(
                    Image(systemName: "shippingbox")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                )
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
    static let minecraftAccent = Color(red: 0.36, green: 0.63, blue: 0.24)
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
