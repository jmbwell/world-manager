//
//  World_Manager_for_MinecraftTests.swift
//  World Manager for MinecraftTests
//
//  Created by John Burwell on 2026-05-25.
//

import Foundation
import Testing
@testable import World_Manager_for_Minecraft

@MainActor
struct World_Manager_for_MinecraftTests {

    @Test func packIdentityUsesUUIDAndVersion() async throws {
        let first = PackIdentity(
            type: .behaviorPack,
            uuid: "ABC-123",
            version: "1.0.0",
            fallbackName: "Pack A",
            fallbackLocationHint: "behavior_packs/pack-a"
        )
        let second = PackIdentity(
            type: .behaviorPack,
            uuid: "abc-123",
            version: "1.0.0",
            fallbackName: "Different Name",
            fallbackLocationHint: "minecraftWorlds/world/behavior_packs/copy"
        )
        let third = PackIdentity(
            type: .behaviorPack,
            uuid: "abc-123",
            version: "2.0.0",
            fallbackName: "Pack A",
            fallbackLocationHint: "behavior_packs/pack-a-v2"
        )

        #expect(first == second)
        #expect(first != third)
        #expect(first.isSuspicious == false)
    }

    @Test func minecraftSourceItemsUseLogicalPackRepresentative() async throws {
        let sourceURL = URL(fileURLWithPath: "/tmp/source")
        let worldURL = sourceURL.appendingPathComponent("minecraftWorlds/WorldA", isDirectory: true)
        let topLevelPackURL = sourceURL.appendingPathComponent("behavior_packs/PackA", isDirectory: true)
        let embeddedPackURL = worldURL.appendingPathComponent("behavior_packs/PackA", isDirectory: true)

        let world = MinecraftContentItem(
            folderURL: worldURL,
            folderName: "WorldA",
            contentType: .world,
            collectionRootURL: sourceURL.appendingPathComponent("minecraftWorlds", isDirectory: true)
        )
        let topLevelPack = MinecraftContentItem(
            folderURL: topLevelPackURL,
            folderName: "PackA",
            contentType: .behaviorPack,
            collectionRootURL: sourceURL.appendingPathComponent("behavior_packs", isDirectory: true),
            displayName: "Pack A"
        )
        let embeddedPack = MinecraftContentItem(
            folderURL: embeddedPackURL,
            folderName: "PackA",
            contentType: .behaviorPack,
            collectionRootURL: worldURL.appendingPathComponent("behavior_packs", isDirectory: true),
            displayName: "Pack A"
        )
        let packID = PackIdentity(
            type: .behaviorPack,
            uuid: "pack-a",
            version: "1.0.0",
            fallbackName: "Pack A",
            fallbackLocationHint: "behavior_packs/PackA"
        )

        var source = MinecraftSource(folderURL: sourceURL)
        source.rawItems = [world, topLevelPack, embeddedPack]
        source.logicalWorlds = [
            LogicalWorld(
                id: world.id,
                itemID: world.id,
                usedPackIDs: [packID],
                unresolvedReferences: []
            )
        ]
        source.logicalPacks = [
            LogicalPack(
                id: packID,
                contentType: .behaviorPack,
                displayName: "Pack A",
                uuid: "pack-a",
                version: "1.0.0",
                representativeItemID: topLevelPack.id,
                instanceItemIDs: [topLevelPack.id, embeddedPack.id],
                isSuspicious: false
            )
        ]

        let displayedItems = source.items

        #expect(displayedItems.count == 2)
        #expect(displayedItems.contains(where: { $0.id == world.id }))
        #expect(displayedItems.contains(where: { $0.id == topLevelPack.id }))
        #expect(displayedItems.contains(where: { $0.id == embeddedPack.id }) == false)
    }

    @Test func worldScannerResolvesReferencedPackFromIndexedCollection() async throws {
        let fileManager = FileManager.default
        let sourceURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let worldsURL = sourceURL.appendingPathComponent("minecraftWorlds", isDirectory: true)
        let worldURL = worldsURL.appendingPathComponent("WorldA", isDirectory: true)
        let packsURL = sourceURL.appendingPathComponent("behavior_packs", isDirectory: true)
        let packURL = packsURL.appendingPathComponent("PackA", isDirectory: true)

        try fileManager.createDirectory(at: worldURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: packURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: sourceURL) }

        let manifest = """
        {
          "header": {
            "name": "Pack A",
            "uuid": "pack-a",
            "version": [1, 0, 0]
          }
        }
        """
        let worldReference = """
        [
          {
            "pack_id": "pack-a",
            "version": [1, 0, 0]
          }
        ]
        """

        try manifest.write(to: packURL.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try worldReference.write(
            to: worldURL.appendingPathComponent("world_behavior_packs.json"),
            atomically: true,
            encoding: .utf8
        )

        let world = MinecraftContentItem(
            folderURL: worldURL,
            folderName: "WorldA",
            contentType: .world,
            collectionRootURL: worldsURL
        )

        await WorldScanner.beginScanSession(for: sourceURL)
        let enrichedWorld = await WorldScanner.enrich(item: world)

        #expect(enrichedWorld.packReferences.count == 1)
        #expect(enrichedWorld.packReferences.first?.name == "Pack A")
        #expect(enrichedWorld.packReferences.first?.uuid == "pack-a")
        #expect(enrichedWorld.packReferences.first?.version == "1.0.0")
    }

    @Test func sourcePersistenceStoreRoundTripsCachedSource() async throws {
        let fileManager = FileManager.default
        let workingURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = workingURL.appendingPathComponent("cache.sqlite", isDirectory: false)
        let sourceURL = workingURL.appendingPathComponent("Source", isDirectory: true)
        defer { try? fileManager.removeItem(at: workingURL) }

        let item = MinecraftContentItem(
            folderURL: sourceURL.appendingPathComponent("minecraftWorlds/WorldA", isDirectory: true),
            folderName: "WorldA",
            contentType: .world,
            collectionRootURL: sourceURL.appendingPathComponent("minecraftWorlds", isDirectory: true),
            displayName: "World A",
            modifiedDate: Date(timeIntervalSince1970: 100),
            sizeBytes: 42,
            metadataLoaded: true,
            sizeLoaded: true
        )
        let snapshot = SourceSnapshot(
            sourceID: sourceURL,
            rootModifiedDate: Date(timeIntervalSince1970: 10),
            collectionSnapshots: [
                CollectionSnapshot(
                    folderName: MinecraftContentType.world.collectionFolderName,
                    modifiedDate: Date(timeIntervalSince1970: 11),
                    childDirectoryCount: 1,
                    fingerprint: "minecraftWorlds::1::11"
                )
            ],
            itemSnapshots: [
                ItemSnapshot(
                    id: item.id,
                    relativePath: "minecraftWorlds/WorldA",
                    modifiedDate: item.modifiedDate,
                    sizeBytes: item.sizeBytes,
                    packUUID: nil,
                    packVersion: nil
                )
            ]
        )

        var source = MinecraftSource(folderURL: sourceURL)
        source.displayName = "Source"
        source.rawItems = [item]
        source.snapshot = snapshot
        source.lastScanDate = Date(timeIntervalSince1970: 200)

        let store = SourcePersistenceStore(databaseURL: databaseURL)
        try await store.save(source: source)

        let restored = try await store.loadSources()

        #expect(restored.count == 1)
        #expect(restored.first?.folderURL == sourceURL.standardizedFileURL)
        #expect(restored.first?.displayName == "Source")
        #expect(restored.first?.rawItems == [item])
        #expect(restored.first?.snapshot == snapshot)
        #expect(restored.first?.lastScanDate == source.lastScanDate)
    }

}
