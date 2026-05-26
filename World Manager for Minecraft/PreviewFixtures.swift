import Foundation
import SwiftUI

enum PreviewFixtures {
    static let baseDate = Date(timeIntervalSinceReferenceDate: 770_000_000)

    static let sourceOneURL = URL(fileURLWithPath: "/tmp/preview-library-1")
    static let sourceTwoURL = URL(fileURLWithPath: "/tmp/preview-library-2")

    static let worldCollectionURL = sourceOneURL.appendingPathComponent(MinecraftContentType.world.collectionFolderName)
    static let behaviorCollectionURL = sourceOneURL.appendingPathComponent(MinecraftContentType.behaviorPack.collectionFolderName)
    static let resourceCollectionURL = sourceOneURL.appendingPathComponent(MinecraftContentType.resourcePack.collectionFolderName)

    static let behaviorPackIdentity = PackIdentity(
        type: .behaviorPack,
        uuid: "874117c4-3f9c-432e-bd64-da7336313337",
        version: "3.0.0",
        fallbackName: "Wither Storm Behavior",
        fallbackLocationHint: behaviorCollectionURL.lastPathComponent
    )

    static let resourcePackIdentity = PackIdentity(
        type: .resourcePack,
        uuid: "823cbe13-eac7-49a4-b9cd-1dd25ab1048a",
        version: "3.0.0",
        fallbackName: "Wither Storm Resources",
        fallbackLocationHint: resourceCollectionURL.lastPathComponent
    )

    static let behaviorPackReference = ContentPackReference(
        name: "§5Cracker's Wither Storm Mod",
        type: .behaviorPack,
        uuid: behaviorPackIdentity.uuid,
        version: behaviorPackIdentity.version,
        source: .referencedByWorld
    )

    static let resourcePackReference = ContentPackReference(
        name: "§5Cracker's Wither Storm Mod",
        type: .resourcePack,
        uuid: resourcePackIdentity.uuid,
        version: resourcePackIdentity.version,
        source: .referencedByWorld
    )

    static let featuredWorld = MinecraftContentItem(
        folderURL: worldCollectionURL.appendingPathComponent("world-alpha"),
        folderName: "world-alpha",
        contentType: .world,
        collectionRootURL: worldCollectionURL,
        displayName: "THE ABSOLUTELY ENORMOUS KID CHAOS LAB WITH 9999 TNT AND A SECRET LLAMA BUNKER v2.0",
        lastPlayedDate: baseDate.addingTimeInterval(-86_400 * 3),
        modifiedDate: baseDate.addingTimeInterval(-86_400 * 2),
        sizeBytes: 35_500_000,
        packReferences: [behaviorPackReference, resourcePackReference],
        metadataLoaded: true,
        sizeLoaded: true
    )

    static let siblingWorld = MinecraftContentItem(
        folderURL: worldCollectionURL.appendingPathComponent("world-beta"),
        folderName: "world-beta",
        contentType: .world,
        collectionRootURL: worldCollectionURL,
        displayName: "Sky Battle Arena",
        modifiedDate: baseDate.addingTimeInterval(-86_400 * 14),
        sizeBytes: 14_200_000,
        packReferences: [resourcePackReference],
        metadataLoaded: true,
        sizeLoaded: true
    )

    static let archiveWorld = MinecraftContentItem(
        folderURL: worldCollectionURL.appendingPathComponent("world-gamma"),
        folderName: "world-gamma",
        contentType: .world,
        collectionRootURL: worldCollectionURL,
        displayName: "Grandma's Survival Backup But Everyone Has Netherite",
        modifiedDate: baseDate.addingTimeInterval(-86_400 * 60),
        sizeBytes: 227_500_000,
        metadataLoaded: true,
        sizeLoaded: true
    )

    static let behaviorPackItem = MinecraftContentItem(
        folderURL: behaviorCollectionURL.appendingPathComponent("wither-storm-bp"),
        folderName: "wither-storm-bp",
        contentType: .behaviorPack,
        collectionRootURL: behaviorCollectionURL,
        displayName: "§5Cracker's Wither Storm Mod",
        modifiedDate: baseDate.addingTimeInterval(-86_400 * 6),
        sizeBytes: 5_300_000,
        packUUID: behaviorPackIdentity.uuid,
        packVersion: behaviorPackIdentity.version,
        metadataLoaded: true,
        sizeLoaded: true
    )

    static let resourcePackItem = MinecraftContentItem(
        folderURL: resourceCollectionURL.appendingPathComponent("wither-storm-rp"),
        folderName: "wither-storm-rp",
        contentType: .resourcePack,
        collectionRootURL: resourceCollectionURL,
        displayName: "§5Cracker's Wither Storm Mod",
        modifiedDate: baseDate.addingTimeInterval(-86_400 * 6),
        sizeBytes: 8_900_000,
        packUUID: resourcePackIdentity.uuid,
        packVersion: resourcePackIdentity.version,
        metadataLoaded: true,
        sizeLoaded: true
    )

    static let secondLibraryPack = MinecraftContentItem(
        folderURL: sourceTwoURL
            .appendingPathComponent(MinecraftContentType.resourcePack.collectionFolderName)
            .appendingPathComponent("cartoon-rp"),
        folderName: "cartoon-rp",
        contentType: .resourcePack,
        collectionRootURL: sourceTwoURL.appendingPathComponent(MinecraftContentType.resourcePack.collectionFolderName),
        displayName: "Cartoon Blocks Remix",
        modifiedDate: baseDate.addingTimeInterval(-86_400 * 11),
        sizeBytes: 12_700_000,
        packUUID: "246df391-7dd1-4df6-b7aa-308a94a85d81",
        packVersion: "1.4.2",
        metadataLoaded: true,
        sizeLoaded: true
    )

    static let primarySource: MinecraftSource = {
        var source = MinecraftSource(folderURL: sourceOneURL)
        source.displayName = "Kid iPad Imports"
        source.displayItems = [
            featuredWorld,
            siblingWorld,
            archiveWorld,
            behaviorPackItem,
            resourcePackItem
        ]
        source.rawItems = source.displayItems
        source.logicalPacks = [
            LogicalPack(
                id: behaviorPackIdentity,
                contentType: .behaviorPack,
                displayName: behaviorPackItem.displayName,
                uuid: behaviorPackItem.packUUID,
                version: behaviorPackItem.packVersion,
                representativeItemID: behaviorPackItem.id,
                instanceItemIDs: [behaviorPackItem.id],
                isSuspicious: false
            ),
            LogicalPack(
                id: resourcePackIdentity,
                contentType: .resourcePack,
                displayName: resourcePackItem.displayName,
                uuid: resourcePackItem.packUUID,
                version: resourcePackItem.packVersion,
                representativeItemID: resourcePackItem.id,
                instanceItemIDs: [resourcePackItem.id],
                isSuspicious: false
            )
        ]
        source.logicalWorlds = [
            LogicalWorld(
                id: featuredWorld.id,
                itemID: featuredWorld.id,
                usedPackIDs: [behaviorPackIdentity, resourcePackIdentity],
                unresolvedReferences: []
            ),
            LogicalWorld(
                id: siblingWorld.id,
                itemID: siblingWorld.id,
                usedPackIDs: [resourcePackIdentity],
                unresolvedReferences: []
            )
        ]
        source.packInstances = [
            PackInstance(
                id: behaviorPackItem.id,
                itemID: behaviorPackItem.id,
                sourceID: source.id,
                logicalPackID: behaviorPackIdentity,
                origin: .foundInCollection,
                hostWorldItemID: nil
            ),
            PackInstance(
                id: resourcePackItem.id,
                itemID: resourcePackItem.id,
                sourceID: source.id,
                logicalPackID: resourcePackIdentity,
                origin: .foundInCollection,
                hostWorldItemID: nil
            )
        ]
        source.worldPackRelationships = [
            WorldPackRelationship(
                worldItemID: featuredWorld.id,
                logicalPackID: behaviorPackIdentity,
                reference: behaviorPackReference
            ),
            WorldPackRelationship(
                worldItemID: featuredWorld.id,
                logicalPackID: resourcePackIdentity,
                reference: resourcePackReference
            ),
            WorldPackRelationship(
                worldItemID: siblingWorld.id,
                logicalPackID: resourcePackIdentity,
                reference: resourcePackReference
            )
        ]
        source.indexedItemCount = source.displayItems.count
        source.indexedDetailCount = source.displayItems.count
        source.lastScanDate = baseDate
        return source
    }()

    static let secondarySource: MinecraftSource = {
        var source = MinecraftSource(folderURL: sourceTwoURL)
        source.displayName = "Downloads"
        source.displayItems = [secondLibraryPack]
        source.rawItems = source.displayItems
        source.indexedItemCount = source.displayItems.count
        source.indexedDetailCount = source.displayItems.count
        source.lastScanDate = baseDate.addingTimeInterval(-3_600)
        return source
    }()

    static let allSources = [primarySource, secondarySource]

    static let sidebarFooter = SidebarFooterState(
        style: .success,
        title: "Export Complete",
        subtitle: "Saved a preview copy of \(featuredWorld.displayName)",
        revealURL: featuredWorld.folderURL
    )

    static let directoryEntries = [
        DirectoryPreviewEntry(name: "db", isDirectory: true),
        DirectoryPreviewEntry(name: "level.dat", isDirectory: false),
        DirectoryPreviewEntry(name: "levelname.txt", isDirectory: false),
        DirectoryPreviewEntry(name: "world_icon.jpeg", isDirectory: false),
        DirectoryPreviewEntry(name: "resource_packs", isDirectory: true)
    ]

    nonisolated static func sidebarFilters(for source: MinecraftSource) -> [SidebarFilter] {
        let allFilter = SidebarFilter(
            title: "All Content",
            iconName: "square.stack.3d.up",
            count: source.items.count,
            selection: .allContent(sourceID: source.id)
        )

        let groupedFilters = MinecraftContentType.allCases.compactMap { contentType -> SidebarFilter? in
            let count = source.items.filter { $0.contentType == contentType }.count
            guard count > 0 else {
                return nil
            }

            return SidebarFilter(
                title: contentType.rawValue,
                iconName: iconName(for: contentType),
                count: count,
                selection: .contentType(sourceID: source.id, contentType: contentType)
            )
        }

        return [allFilter] + groupedFilters
    }

    nonisolated static func iconName(for contentType: MinecraftContentType) -> String {
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

struct SidebarColumnPreviewContainer: View {
    @State private var selection: SidebarSelection? = .allContent(sourceID: PreviewFixtures.primarySource.id)

    var body: some View {
        NavigationStack {
            SourcesSidebarView(
                sources: PreviewFixtures.allSources,
                selection: $selection,
                footerState: PreviewFixtures.sidebarFooter,
                addSourceAction: {},
                rescanSourceAction: { _ in },
                removeSourceAction: { _ in },
                revealFooterURLAction: { _ in },
                filters: PreviewFixtures.sidebarFilters(for:)
            )
        }
    }
}

struct ItemListColumnPreviewContainer: View {
    @State private var isDropTargeted = false
    @State private var selectedItemID: MinecraftContentItem.ID? = PreviewFixtures.featuredWorld.id
    @State private var searchText = ""
    @State private var sortMode: ItemSortMode = .modifiedDate

    var body: some View {
        NavigationStack {
            ItemListColumnView(
                isEmpty: false,
                isDropTargeted: $isDropTargeted,
                selectedItemID: $selectedItemID,
                searchText: $searchText,
                sortMode: $sortMode,
                title: "All Items",
                subtitle: "5 items in Kid iPad Imports",
                items: PreviewFixtures.primarySource.displayItems,
                searchPrompt: "Search Worlds",
                chooseFolderAction: {},
                dropAction: { _ in false },
                refreshAction: {},
                itemContextMenu: { item in
                    Button("Reveal \(item.displayName)") {}
                }
            )
        }
    }
}

struct ItemDetailColumnPreviewContainer: View {
    var body: some View {
        NavigationStack {
            ItemDetailColumnView(
                item: PreviewFixtures.featuredWorld,
                source: PreviewFixtures.primarySource,
                behaviorPacks: PreviewFixtures.primarySource.resolvedPackReferences(for: PreviewFixtures.featuredWorld.id, type: .behaviorPack),
                resourcePacks: PreviewFixtures.primarySource.resolvedPackReferences(for: PreviewFixtures.featuredWorld.id, type: .resourcePack),
                worldsUsingPack: [],
                backingPackInstances: [],
                isSuspiciousPack: false,
                contents: PreviewFixtures.directoryEntries,
                directoryPreviewLimit: 12,
                isEmpty: false,
                isPerformingItemAction: false,
                exportTitle: PreviewFixtures.featuredWorld.contentType.exportTitle,
                exportAction: {},
                revealAction: {},
                shareAction: { _ in }
            )
        }
    }
}
