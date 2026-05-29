//
//  SourceContentIndex.swift
//  World Manager for Minecraft
//
//  Created by OpenAI Codex on 2026-05-29.
//

import Foundation

struct SourceContentIndex {
    let rawItems: [MinecraftContentItem]
    let logicalPacks: [LogicalPack]
    let logicalWorlds: [LogicalWorld]
    let packInstances: [PackInstance]
    let worldPackRelationships: [WorldPackRelationship]
    let displayItems: [MinecraftContentItem]
}

enum SourceContentIndexer {
    static func buildIndex(for source: MinecraftSource) -> SourceContentIndex {
        let rawItems = source.rawItems.sorted(by: WorldScanner.sortItems)
        let rawItemsByID = Dictionary(uniqueKeysWithValues: rawItems.map { ($0.id, $0) })

        let rawPacks = rawItems.filter {
            $0.contentType == .behaviorPack || $0.contentType == .resourcePack
        }
        let rawWorlds = rawItems.filter { $0.contentType == .world }

        let packMetadataByItemID = Dictionary(uniqueKeysWithValues: rawPacks.map { item in
            (item.id, packMetadata(for: item, sourceRootURL: source.folderURL))
        })

        var chosenRepresentativeByIdentity: [PackIdentity: MinecraftContentItem] = [:]
        var allPackItemsByIdentity: [PackIdentity: [MinecraftContentItem]] = [:]

        for item in rawPacks {
            let metadata = packMetadataByItemID[item.id] ?? packMetadata(for: item, sourceRootURL: source.folderURL)
            let identity = metadata.identity
            allPackItemsByIdentity[identity, default: []].append(item)

            guard let existing = chosenRepresentativeByIdentity[identity] else {
                chosenRepresentativeByIdentity[identity] = item
                continue
            }

            if shouldPreferPackItem(item, over: existing) {
                chosenRepresentativeByIdentity[identity] = item
            }
        }

        let logicalPacks = allPackItemsByIdentity.keys.sorted {
            let lhs = chosenRepresentativeByIdentity[$0]?.displayName ?? ""
            let rhs = chosenRepresentativeByIdentity[$1]?.displayName ?? ""
            let nameOrder = lhs.localizedStandardCompare(rhs)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }

            return $0.id.localizedStandardCompare($1.id) == .orderedAscending
        }.compactMap { identity -> LogicalPack? in
            guard
                let representativeItem = chosenRepresentativeByIdentity[identity],
                let instances = allPackItemsByIdentity[identity]
            else {
                return nil
            }

            let metadata = packMetadataByItemID[representativeItem.id]

            return LogicalPack(
                id: identity,
                contentType: identity.type,
                displayName: representativeItem.displayName,
                uuid: metadata?.uuid,
                version: metadata?.version,
                representativeItemID: representativeItem.id,
                instanceItemIDs: instances.map(\.id).sorted {
                    $0.path.localizedStandardCompare($1.path) == .orderedAscending
                },
                isSuspicious: identity.isSuspicious
            )
        }

        var packInstances: [PackInstance] = []
        for logicalPack in logicalPacks {
            for itemID in logicalPack.instanceItemIDs {
                guard let item = rawItemsByID[itemID] else {
                    continue
                }

                packInstances.append(
                    PackInstance(
                        id: item.id,
                        itemID: item.id,
                        sourceID: source.id,
                        logicalPackID: logicalPack.id,
                        origin: packOrigin(for: item),
                        hostWorldItemID: hostWorldItemID(for: item, in: rawWorlds)
                    )
                )
            }
        }

        let logicalPacksByID = Dictionary(uniqueKeysWithValues: logicalPacks.map { ($0.id, $0) })
        var worldRelationships: [WorldPackRelationship] = []
        var logicalWorlds: [LogicalWorld] = []

        for world in rawWorlds {
            var usedPackIDs = Set<PackIdentity>()
            var unresolvedReferences: [ContentPackReference] = []

            for reference in world.packReferences {
                let referenceIdentity = PackIdentity(
                    type: reference.type,
                    uuid: reference.uuid,
                    version: reference.version,
                    fallbackName: reference.name,
                    fallbackLocationHint: world.folderName
                )
                let resolvedID = logicalPacksByID[referenceIdentity]?.id

                if let resolvedID {
                    usedPackIDs.insert(resolvedID)
                } else {
                    unresolvedReferences.append(reference)
                }

                worldRelationships.append(
                    WorldPackRelationship(
                        worldItemID: world.id,
                        logicalPackID: resolvedID,
                        reference: reference
                    )
                )
            }

            logicalWorlds.append(
                LogicalWorld(
                    id: world.id,
                    itemID: world.id,
                    usedPackIDs: usedPackIDs.sorted {
                        $0.id.localizedStandardCompare($1.id) == .orderedAscending
                    },
                    unresolvedReferences: unresolvedReferences
                )
            )
        }

        let sortedLogicalWorlds = logicalWorlds.sorted {
            guard
                let lhs = rawItemsByID[$0.itemID],
                let rhs = rawItemsByID[$1.itemID]
            else {
                return $0.itemID.path.localizedStandardCompare($1.itemID.path) == .orderedAscending
            }

            return WorldScanner.sortItems(lhs, rhs)
        }

        let sortedPackInstances = packInstances.sorted {
            $0.itemID.path.localizedStandardCompare($1.itemID.path) == .orderedAscending
        }

        return SourceContentIndex(
            rawItems: rawItems,
            logicalPacks: logicalPacks,
            logicalWorlds: sortedLogicalWorlds,
            packInstances: sortedPackInstances,
            worldPackRelationships: worldRelationships,
            displayItems: buildDisplayItems(
                from: rawItems,
                logicalPacks: logicalPacks,
                rawItemsByID: rawItemsByID
            )
        )
    }

    private static func buildDisplayItems(
        from rawItems: [MinecraftContentItem],
        logicalPacks: [LogicalPack],
        rawItemsByID: [URL: MinecraftContentItem]
    ) -> [MinecraftContentItem] {
        var normalizedItemIDs = Set<URL>()
        var normalizedItems: [MinecraftContentItem] = []

        for item in rawItems where item.contentType == .world {
            guard normalizedItemIDs.insert(item.id).inserted else {
                continue
            }

            normalizedItems.append(item)
        }

        for logicalPack in logicalPacks {
            guard
                let item = rawItemsByID[logicalPack.representativeItemID],
                normalizedItemIDs.insert(item.id).inserted
            else {
                continue
            }

            normalizedItems.append(item)
        }

        for item in rawItems where item.contentType == .skinPack || item.contentType == .worldTemplate {
            guard normalizedItemIDs.insert(item.id).inserted else {
                continue
            }

            normalizedItems.append(item)
        }

        return normalizedItems
    }

    private static func shouldPreferPackItem(_ candidate: MinecraftContentItem, over existing: MinecraftContentItem) -> Bool {
        let candidateEmbedded = isEmbeddedWorldPack(candidate)
        let existingEmbedded = isEmbeddedWorldPack(existing)

        if candidateEmbedded != existingEmbedded {
            return !candidateEmbedded
        }

        if candidate.metadataLoaded != existing.metadataLoaded {
            return candidate.metadataLoaded
        }

        if (candidate.iconURL != nil) != (existing.iconURL != nil) {
            return candidate.iconURL != nil
        }

        if candidate.previewLoaded != existing.previewLoaded {
            return candidate.previewLoaded
        }

        if candidate.modifiedDate != existing.modifiedDate {
            return (candidate.modifiedDate ?? .distantPast) > (existing.modifiedDate ?? .distantPast)
        }

        return candidate.folderURL.path.localizedStandardCompare(existing.folderURL.path) == .orderedAscending
    }

    private static func packOrigin(for item: MinecraftContentItem) -> PackSource {
        isEmbeddedWorldPack(item) ? .embeddedInWorld : .foundInCollection
    }

    private static func isEmbeddedWorldPack(_ item: MinecraftContentItem) -> Bool {
        item.folderURL.pathComponents.contains(MinecraftContentType.world.collectionFolderName)
    }

    private static func hostWorldItemID(for packItem: MinecraftContentItem, in rawWorlds: [MinecraftContentItem]) -> URL? {
        rawWorlds.first(where: { world in
            packItem.folderURL.path.hasPrefix(world.folderURL.path + "/")
        })?.id
    }

    private static func packMetadata(for item: MinecraftContentItem, sourceRootURL: URL) -> IndexedPackMetadata {
        let uuid = item.packUUID
        let version = item.packVersion

        return IndexedPackMetadata(
            uuid: uuid,
            version: version,
            identity: PackIdentity(
                type: item.contentType,
                uuid: uuid,
                version: version,
                fallbackName: item.displayName,
                fallbackLocationHint: relativePathHint(for: item, sourceRootURL: sourceRootURL)
            )
        )
    }

    private static func relativePathHint(for item: MinecraftContentItem, sourceRootURL: URL) -> String {
        item.folderURL.path.replacingOccurrences(of: sourceRootURL.path + "/", with: "")
    }
}

private struct IndexedPackMetadata {
    let uuid: String?
    let version: String?
    let identity: PackIdentity
}
