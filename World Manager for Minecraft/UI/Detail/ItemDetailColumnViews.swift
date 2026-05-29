import AppKit
import SwiftUI

struct DirectoryPreviewEntry: Identifiable {
    let id = UUID()
    let name: String
    let isDirectory: Bool
}

struct ItemDetailColumnView: View {
    let item: MinecraftContentItem?
    let source: MinecraftSource?
    let showsSourceDetails: Bool
    let behaviorPacks: [ContentPackReference]
    let resourcePacks: [ContentPackReference]
    let worldsUsingPack: [MinecraftContentItem]
    let backingPackInstances: [MinecraftContentItem]
    let isSuspiciousPack: Bool
    let contents: [DirectoryPreviewEntry]
    let directoryPreviewLimit: Int
    let isEmpty: Bool
    let isPerformingItemAction: Bool
    let areFileActionsEnabled: Bool
    let exportTitle: String?
    let exportAction: () -> Void
    let revealAction: () -> Void
    let shareAction: (NSView?) -> Void

    var body: some View {
        Group {
            if isEmpty {
            } else if let item {
                ItemDetailView(
                    item: item,
                    source: source,
                    behaviorPacks: behaviorPacks,
                    resourcePacks: resourcePacks,
                    worldsUsingPack: worldsUsingPack,
                    backingPackInstances: backingPackInstances,
                    isSuspiciousPack: isSuspiciousPack,
                    contents: contents,
                    directoryPreviewLimit: directoryPreviewLimit,
                    isPerformingItemAction: isPerformingItemAction,
                    areFileActionsEnabled: areFileActionsEnabled,
                    exportTitle: exportTitle,
                    exportAction: exportAction,
                    revealAction: revealAction,
                    shareAction: shareAction
                )
            } else if showsSourceDetails, let source {
                SourceDetailView(source: source)
            } else {
                Text("Select a world or pack to see details")
                    .foregroundStyle(.secondary)
            }
        }
        .toolbar {
            if item != nil {
                ToolbarItem {
                    Button(action: exportAction) {
                        Image(systemName: "arrow.down.circle")
                    }
                    .disabled(isPerformingItemAction || !areFileActionsEnabled)
                    .help(exportTitle ?? "Export")
                }

                ToolbarItem {
                    Button(action: revealAction) {
                        Image(systemName: "folder")
                    }
                    .disabled(isPerformingItemAction || !areFileActionsEnabled)
                    .help("Reveal in Finder")
                }

                ToolbarItem {
                    ToolbarShareButton(
                        systemImage: "square.and.arrow.up",
                        isEnabled: !isPerformingItemAction && areFileActionsEnabled
                    ) { anchorView in
                        shareAction(anchorView)
                    }
                    .help("Share")
                }
            }
        }
    }
}

#if DEBUG
struct ItemDetailColumnViews_Previews: PreviewProvider {
    static var previews: some View {
        ItemDetailColumnPreviewContainer()
    }
}
#endif
