// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

struct ItemCollectionProjectionRequest: Hashable, Sendable {
    let selection: SidebarSelection?
    let searchText: String
    let sortMode: ItemSortMode
    let source: MinecraftSource?
}

struct ItemCollectionProjection: Sendable {
    let request: ItemCollectionProjectionRequest
    let sourceName: String
    let title: String
    let subtitle: String
    let searchPrompt: String
    let items: [MinecraftContentItem]

    nonisolated static func placeholder(for request: ItemCollectionProjectionRequest) -> ItemCollectionProjection {
        ItemCollectionProjection(
            request: request,
            sourceName: request.source?.displayName ?? "Library",
            title: ItemCollectionProjector.title(
                for: request.selection,
                isSearching: !ItemCollectionProjector.trimmedSearchText(for: request).isEmpty
            ),
            subtitle: "",
            searchPrompt: ItemCollectionProjector.searchPrompt(for: request.selection, source: request.source),
            items: []
        )
    }
}

enum ItemCollectionProjector {
    nonisolated static func makeProjection(for request: ItemCollectionProjectionRequest) -> ItemCollectionProjection {
        let trimmedSearchText = trimmedSearchText(for: request)
        let scopedItems = request.source?.items(matching: request.selection) ?? []
        let filteredItems: [MinecraftContentItem]

        if trimmedSearchText.isEmpty {
            filteredItems = scopedItems
        } else {
            filteredItems = scopedItems.filter { item in
                item.searchText.localizedCaseInsensitiveContains(trimmedSearchText)
            }
        }

        let displayedItems = filteredItems.sorted(by: sortComparator(for: request.sortMode))
        let countNoun = collectionCountNoun(for: request.selection, scopedItemCount: scopedItems.count)
        let subtitle: String

        if trimmedSearchText.isEmpty {
            subtitle = "\(scopedItems.count.formatted(.number)) \(countNoun)"
        } else {
            subtitle = "\(displayedItems.count.formatted(.number)) of \(scopedItems.count.formatted(.number)) \(countNoun)"
        }

        return ItemCollectionProjection(
            request: request,
            sourceName: request.source?.displayName ?? "Library",
            title: title(for: request.selection, isSearching: !trimmedSearchText.isEmpty),
            subtitle: subtitle,
            searchPrompt: searchPrompt(for: request.selection, source: request.source),
            items: displayedItems
        )
    }

    nonisolated static func title(for selection: SidebarSelection?, isSearching: Bool) -> String {
        if isSearching {
            return "Searching “\(searchScopeTitle(for: selection))”"
        }

        guard let selection else {
            return "Library"
        }

        switch selection {
        case .sourceCandidate:
            return "Source Candidate"
        case .connectedDevice:
            return "Connected Device"
        case .source, .allContent:
            return "All Items"
        case .contentType(_, let contentType):
            return sidebarTitle(for: contentType)
        case .contentKind(_, let contentKind):
            return sidebarTitle(for: contentKind)
        }
    }

    nonisolated static func searchPrompt(for selection: SidebarSelection?, source: MinecraftSource?) -> String {
        switch selection {
        case .some(.sourceCandidate), .some(.connectedDevice):
            return "Search Library"
        case .some(.source):
            return "Search \(source?.displayName ?? "Library")"
        case .some(.allContent):
            return "Search All Items"
        case .some(.contentType(_, let contentType)):
            return "Search \(sidebarTitle(for: contentType))"
        case .some(.contentKind(_, let contentKind)):
            return "Search \(sidebarTitle(for: contentKind))"
        case .none:
            return "Search Library"
        }
    }

    nonisolated private static func searchScopeTitle(for selection: SidebarSelection?) -> String {
        switch selection {
        case .some(.sourceCandidate):
            return "Source Candidate"
        case .some(.connectedDevice):
            return "Connected Device"
        case .some(.source):
            return "Library"
        case .some(.allContent):
            return "All"
        case .some(.contentType(_, let contentType)):
            return sidebarTitle(for: contentType)
        case .some(.contentKind(_, let contentKind)):
            return sidebarTitle(for: contentKind)
        case .none:
            return "Library"
        }
    }

    nonisolated private static func collectionCountNoun(for selection: SidebarSelection?, scopedItemCount: Int) -> String {
        guard let selection else {
            return "items"
        }

        switch selection {
        case .sourceCandidate, .connectedDevice:
            return "items"
        case .source, .allContent:
            return scopedItemCount == 1 ? "item" : "items"
        case .contentType(_, let contentType):
            switch contentType {
            case .world:
                return scopedItemCount == 1 ? "world" : "worlds"
            case .behaviorPack, .resourcePack, .skinPack, .worldTemplate:
                return scopedItemCount == 1 ? "pack" : "packs"
            }
        case .contentKind(_, let contentKind):
            switch contentKind {
            case .world:
                return scopedItemCount == 1 ? "world" : "worlds"
            case .mod:
                return scopedItemCount == 1 ? "mod" : "mods"
            case .shaderPack:
                return scopedItemCount == 1 ? "shader pack" : "shader packs"
            case .behaviorPack, .resourcePack, .dataPack, .skinPack, .worldTemplate:
                return scopedItemCount == 1 ? "pack" : "packs"
            }
        }
    }

    nonisolated private static func sidebarTitle(for contentType: MinecraftContentType) -> String {
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

    nonisolated private static func sidebarTitle(for contentKind: MinecraftContentKind) -> String {
        switch contentKind {
        case .world:
            return "Worlds"
        case .behaviorPack:
            return "Behavior Packs"
        case .resourcePack:
            return "Resource Packs"
        case .dataPack:
            return "Data Packs"
        case .skinPack:
            return "Skin Packs"
        case .worldTemplate:
            return "World Templates"
        case .shaderPack:
            return "Shader Packs"
        case .mod:
            return "Mods"
        }
    }

    nonisolated static func trimmedSearchText(for request: ItemCollectionProjectionRequest) -> String {
        request.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func sortComparator(for mode: ItemSortMode) -> (MinecraftContentItem, MinecraftContentItem) -> Bool {
        switch mode {
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
}
