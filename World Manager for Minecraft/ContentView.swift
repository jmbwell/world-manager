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
    @State private var itemActionAlert: ItemActionAlert?
    @State private var isPerformingItemAction = false

    var body: some View {
        NavigationSplitView {
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
        } content: {
            if library.sources.isEmpty {
                EmptySourcesView(
                    isDropTargeted: isDropTargeted,
                    chooseFolder: pickFolder
                )
                .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted, perform: handleDroppedProviders)
            } else {
                List(filteredItems, selection: $selectedItem) { item in
                    HStack(alignment: .top, spacing: 10) {
                        ItemThumbnailView(iconURL: item.iconURL)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.displayName)
                                .lineLimit(1)

                            Text(item.contentType.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(item.folderName)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
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
                    .tag(item)
                    .contextMenu {
                        itemContextMenu(for: item)
                    }
                }
                .navigationTitle(contentListTitle)
                .searchable(text: $searchText, placement: .toolbar, prompt: "Search Content")
            }
        } detail: {
            if library.sources.isEmpty {
                Text("Add a source folder to start scanning Minecraft content")
                    .foregroundStyle(.secondary)
            } else if let selectedItem = currentSelectedItem {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .top, spacing: 16) {
                            LargeItemThumbnailView(iconURL: selectedItem.iconURL)

                            VStack(alignment: .leading, spacing: 8) {
                                Text(selectedItem.displayName)
                                    .font(.title2)

                                Text(selectedItem.contentType.rawValue)
                                    .font(.headline)
                                    .foregroundStyle(.secondary)

                                Text(selectedItem.folderName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)

                            VStack(alignment: .trailing, spacing: 8) {
                                SharingPickerButton(
                                    title: "Share",
                                    systemImage: "square.and.arrow.up",
                                    isEnabled: !isPerformingItemAction
                                ) { anchorView in
                                    shareItem(selectedItem, from: anchorView)
                                }

                                Button {
                                    saveItem(selectedItem)
                                } label: {
                                    Label("Export .\(selectedItem.contentType.archiveExtension)", systemImage: "square.and.arrow.down")
                                }
                                .disabled(isPerformingItemAction)

                                Button {
                                    revealInFinder(selectedItem)
                                } label: {
                                    Label("Reveal in Finder", systemImage: "folder")
                                }
                                .disabled(isPerformingItemAction)
                            }
                        }

                        detailSection("Location") {
                            detailRow(title: "Folder Path", value: selectedItem.folderURL.path)
                            detailRow(title: "Collection Root", value: selectedItem.collectionRootURL.path)
                        }

                        detailSection("Details") {
                            if let modifiedDate = selectedItem.modifiedDate {
                                detailRow(
                                    title: "Modified",
                                    value: modifiedDate.formatted(date: .abbreviated, time: .shortened)
                                )
                            }

                            if let sizeBytes = selectedItem.sizeBytes {
                                detailRow(
                                    title: "Size",
                                    value: ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
                                )
                            }

                            detailRow(
                                title: "Metadata",
                                value: selectedItem.metadataLoaded ? "Loaded" : "Loading..."
                            )
                        }

                        detailSection("Contents") {
                            let previewEntries = directoryPreviewEntries(for: selectedItem)

                            if previewEntries.isEmpty {
                                Text("No visible files or folders")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(previewEntries) { entry in
                                    HStack(spacing: 10) {
                                        Image(systemName: entry.isDirectory ? "folder" : "doc")
                                            .foregroundStyle(.secondary)
                                        Text(entry.name)
                                            .lineLimit(1)
                                        Spacer()
                                    }
                                }

                                if previewEntries.count == directoryPreviewLimit {
                                    Text("Showing the first \(directoryPreviewLimit) items")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding()
                }
            } else {
                Text("Select a world or pack to see details")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Minecraft World Manager")
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

                    Button {
                        saveItem(selectedExportableItem)
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.down")
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

            ToolbarItem(placement: .secondaryAction) {
                if let activeScanSummary = library.activeScanSummary {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)

                        Text(activeScanSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 320, alignment: .trailing)
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
        .alert(item: $itemActionAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private let directoryPreviewLimit = 12

    private var filteredItems: [MinecraftContentItem] {
        guard let selectedSidebarSelection else {
            return []
        }

        let scopedItems: [MinecraftContentItem]

        switch selectedSidebarSelection {
        case .allContent(let sourceID):
            scopedItems = library.source(withID: sourceID)?.items ?? []
        case .contentType(let sourceID, let contentType):
            scopedItems = library.source(withID: sourceID)?.items.filter { $0.contentType == contentType } ?? []
        }

        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearchText.isEmpty else {
            return scopedItems
        }

        return scopedItems.filter { item in
            item.displayName.localizedCaseInsensitiveContains(trimmedSearchText)
                || item.folderName.localizedCaseInsensitiveContains(trimmedSearchText)
                || item.contentType.rawValue.localizedCaseInsensitiveContains(trimmedSearchText)
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

    private var contentListTitle: String {
        guard let selectedSidebarSelection else {
            return "Minecraft Content"
        }

        switch selectedSidebarSelection {
        case .allContent(let sourceID):
            return library.source(withID: sourceID)?.displayName ?? "Minecraft Content"
        case .contentType(_, let contentType):
            return sidebarTitle(for: contentType)
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
    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            content()
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
    private func itemContextMenu(for item: MinecraftContentItem) -> some View {
        Button("Share...") {
            shareItem(item, from: nil)
        }

        Button("Export .\(item.contentType.archiveExtension)") {
            saveItem(item)
        }

        Divider()

        Button("Reveal in Finder") {
            revealInFinder(item)
        }
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
        panel.title = "Export \(item.contentType.exportTitle)"
        panel.message = "Choose where to save the .\(item.contentType.archiveExtension) file."
        panel.nameFieldStringValue = ContentPackageExporter.suggestedBaseFilename(for: item)
        panel.allowedContentTypes = [archiveType(for: item)]

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }

        isPerformingItemAction = true

        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try ContentPackageExporter.exportItem(item, to: destinationURL)
                }.value

                await MainActor.run {
                    isPerformingItemAction = false
                    itemActionAlert = ItemActionAlert(
                        title: "Export Complete",
                        message: "\"\(item.displayName)\" was exported as \(ContentPackageExporter.suggestedFilename(for: item))."
                    )
                }
            } catch {
                await MainActor.run {
                    isPerformingItemAction = false
                    itemActionAlert = ItemActionAlert(
                        title: "Export Failed",
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    private func shareItem(_ item: MinecraftContentItem, from anchorView: NSView?) {
        guard !isPerformingItemAction else {
            return
        }

        isPerformingItemAction = true

        Task {
            do {
                let shareURL = try await Task.detached(priority: .userInitiated) {
                    try ContentPackageExporter.prepareShareFile(for: item)
                }.value

                await MainActor.run {
                    isPerformingItemAction = false

                    let presentationView = anchorView ?? NSApp.keyWindow?.contentView
                    guard let presentationView else {
                        itemActionAlert = ItemActionAlert(
                            title: "Share Failed",
                            message: "Could not find a view to present the sharing menu."
                        )
                        return
                    }

                    let picker = NSSharingServicePicker(items: [shareURL])
                    let targetRect = anchorView?.bounds ?? presentationView.bounds.insetBy(dx: presentationView.bounds.width / 2, dy: presentationView.bounds.height / 2)
                    picker.show(relativeTo: targetRect, of: presentationView, preferredEdge: .minY)
                }
            } catch {
                await MainActor.run {
                    isPerformingItemAction = false
                    itemActionAlert = ItemActionAlert(
                        title: "Share Failed",
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    private func revealInFinder(_ item: MinecraftContentItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.folderURL])
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

private struct ItemActionAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
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
                    .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: 220, height: 160)

                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
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
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
                .frame(width: 36, height: 36)
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
                .frame(width: 128, height: 128)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary)
                .frame(width: 128, height: 128)
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
