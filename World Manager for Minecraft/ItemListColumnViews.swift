import SwiftUI
import UniformTypeIdentifiers

enum ItemSortMode: String, CaseIterable, Identifiable {
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

struct ItemListColumnView<MenuContent: View>: View {
    let isEmpty: Bool
    @Binding var isDropTargeted: Bool
    @Binding var selectedItemID: MinecraftContentItem.ID?
    @Binding var searchText: String
    @Binding var sortMode: ItemSortMode
    let showsHeader: Bool
    let sourceName: String
    let showsSourceName: Bool
    let title: String
    let subtitle: String
    let showsSubtitle: Bool
    let isRefreshing: Bool
    let items: [MinecraftContentItem]
    let searchPrompt: String
    let chooseFolderAction: () -> Void
    let dropAction: ([NSItemProvider]) -> Bool
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
        .safeAreaInset(edge: .top, spacing: 0) {
            if !isEmpty && showsHeader {
                ItemListHeaderView(
                    sourceName: sourceName,
                    showsSourceName: showsSourceName,
                    title: title,
                    subtitle: subtitle,
                    showsSubtitle: showsSubtitle,
                    isRefreshing: isRefreshing
                )
            }
        }
        .searchable(text: $searchText, prompt: searchPrompt)
        .navigationTitle(isEmpty ? "Library" : title)
        .navigationSubtitle(isEmpty ? "" : subtitle)
        .toolbar {
            if !isEmpty {
                ToolbarItemGroup {
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

private struct ItemListHeaderView: View {
    let sourceName: String
    let showsSourceName: Bool
    let title: String
    let subtitle: String
    let showsSubtitle: Bool
    let isRefreshing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsSourceName {
                Text(sourceName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)

                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if showsSubtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Divider()
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

struct ItemListColumnViews_Previews: PreviewProvider {
    static var previews: some View {
        ItemListColumnPreviewContainer()
    }
}
