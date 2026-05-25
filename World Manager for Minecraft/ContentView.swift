//
//  ContentView.swift
//  World Manager for Minecraft
//
//  Created by John Burwell on 2026-05-25.
//

import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var scanner = WorldScanner()
    @State private var folderURL: URL?
    @State private var selectedItem: MinecraftContentItem?
    @State private var selectedSidebarSelection: SidebarSelection = .all

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 12) {
                Button("Choose Minecraft Folder...") {
                    pickFolder()
                }

                if let folderURL {
                    Text(folderURL.path)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else {
                    Text("No folder selected")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let scanError = scanner.scanError {
                    Text(scanError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                List(selection: $selectedSidebarSelection) {
                    if let folderURL {
                        Section(folderURL.lastPathComponent) {
                            ForEach(sidebarFilters) { filter in
                                SidebarFilterRow(filter: filter)
                                    .tag(filter.selection)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .padding()
            .navigationTitle("Source")
        } content: {
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
            }
            .navigationTitle(contentListTitle)
        } detail: {
            if let selectedItem = currentSelectedItem {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
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
                        }

                        detailRow(title: "Folder Path", value: selectedItem.folderURL.path)
                        detailRow(title: "Collection Root", value: selectedItem.collectionRootURL.path)

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
                    .padding()
                }
            } else {
                Text("Select a world or pack to see details")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Minecraft World Manager")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if scanner.isScanning {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)

                        Text(scanner.scanStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 280, alignment: .trailing)
                }
            }
        }
        .onChange(of: filteredItems.map(\.id)) { _, filteredIDs in
            guard let selectedItem, !filteredIDs.contains(selectedItem.id) else {
                return
            }

            self.selectedItem = nil
        }
    }

    private var filteredItems: [MinecraftContentItem] {
        switch selectedSidebarSelection {
        case .all:
            return scanner.items
        case .contentType(let contentType):
            return scanner.items.filter { $0.contentType == contentType }
        }
    }

    private var currentSelectedItem: MinecraftContentItem? {
        guard let selectedItem else {
            return nil
        }

        return scanner.items.first(where: { $0.id == selectedItem.id }) ?? selectedItem
    }

    private var contentListTitle: String {
        switch selectedSidebarSelection {
        case .all:
            return "Minecraft Content"
        case .contentType(let contentType):
            return contentType.rawValue + "s"
        }
    }

    private var sidebarFilters: [SidebarFilter] {
        var filters = [
            SidebarFilter(
                title: "All Content",
                iconName: "square.grid.2x2",
                count: scanner.items.count,
                selection: .all
            )
        ]

        filters.append(
            contentsOf: MinecraftContentType.allCases.compactMap { contentType in
                let count = scanner.items.filter { $0.contentType == contentType }.count
                guard count > 0 else {
                    return nil
                }

                return SidebarFilter(
                    title: sidebarTitle(for: contentType),
                    iconName: sidebarIcon(for: contentType),
                    count: count,
                    selection: .contentType(contentType)
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
    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .textSelection(.enabled)
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.title = "Choose a Folder to Search"

        guard panel.runModal() == .OK, let pickedURL = panel.url else {
            return
        }

        folderURL = pickedURL
        selectedItem = nil
        selectedSidebarSelection = .all

        Task {
            await scanner.scan(at: pickedURL)
        }
    }
}

private enum SidebarSelection: Hashable {
    case all
    case contentType(MinecraftContentType)
}

private struct SidebarFilter: Identifiable, Hashable {
    let id = UUID()
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
