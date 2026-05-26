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

    @Test func worldScannerDecodesBedrockLevelMetadata() async throws {
        let fileManager = FileManager.default
        let sourceURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let worldURL = sourceURL.appendingPathComponent("minecraftWorlds/WorldA", isDirectory: true)
        defer { try? fileManager.removeItem(at: sourceURL) }

        try fileManager.createDirectory(at: worldURL, withIntermediateDirectories: true)
        let lastPlayedMilliseconds: Int64 = 1_695_427_200_000
        let levelDat = makeBedrockLevelDat(
            root: .compound([
                "GameType": .int(1),
                "Difficulty": .int(1),
                "RandomSeed": .long(664_021_225),
                "LastPlayed": .long(lastPlayedMilliseconds),
                "lastOpenedWithVersion": .list(.int, [.int(1), .int(20), .int(13)]),
                "InventoryVersion": .list(.int, [.int(1), .int(20), .int(13)]),
                "cheatsEnabled": .byte(1),
                "commandsEnabled": .byte(1),
                "educationFeaturesEnabled": .byte(1),
                "showcoordinates": .byte(1),
                "keepinventory": .byte(1),
                "mobgriefing": .byte(0),
                "dodaylightcycle": .byte(0),
                "doweathercycle": .byte(1),
                "SpawnX": .int(0),
                "SpawnY": .int(32767),
                "SpawnZ": .int(0),
                "StorageVersion": .int(10),
                "NetworkVersion": .int(594)
            ]),
            storageVersion: 10
        )
        try levelDat.write(to: worldURL.appendingPathComponent("level.dat"))

        let world = MinecraftContentItem(
            folderURL: worldURL,
            folderName: "WorldA",
            contentType: .world,
            collectionRootURL: sourceURL.appendingPathComponent("minecraftWorlds", isDirectory: true)
        )

        let enrichedWorld = await WorldScanner.enrich(item: world)

        #expect(enrichedWorld.worldMetadata?.gameMode == "Creative")
        #expect(enrichedWorld.worldMetadata?.difficulty == "Easy")
        #expect(enrichedWorld.worldMetadata?.seed == "664021225")
        #expect(enrichedWorld.lastPlayedDate == Date(timeIntervalSince1970: 1_695_427_200))
        #expect(enrichedWorld.worldMetadata?.lastOpenedWithVersion == "1.20.13")
        #expect(enrichedWorld.worldMetadata?.inventoryVersion == "1.20.13")
        #expect(enrichedWorld.worldMetadata?.cheatsEnabled == true)
        #expect(enrichedWorld.worldMetadata?.commandsEnabled == true)
        #expect(enrichedWorld.worldMetadata?.educationFeaturesEnabled == true)
        #expect(enrichedWorld.worldMetadata?.coordinatesShown == true)
        #expect(enrichedWorld.worldMetadata?.keepInventory == true)
        #expect(enrichedWorld.worldMetadata?.mobGriefingEnabled == false)
        #expect(enrichedWorld.worldMetadata?.daylightCycleEnabled == false)
        #expect(enrichedWorld.worldMetadata?.weatherCycleEnabled == true)
        #expect(enrichedWorld.worldMetadata?.spawn == "0, 32767, 0")
        #expect(enrichedWorld.worldMetadata?.storageVersion == "10")
        #expect(enrichedWorld.worldMetadata?.networkVersion == "594")
    }

    @Test func worldScannerReadsPackMinimumEngineVersion() async throws {
        let fileManager = FileManager.default
        let sourceURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let packURL = sourceURL.appendingPathComponent("behavior_packs/PackA", isDirectory: true)
        defer { try? fileManager.removeItem(at: sourceURL) }

        try fileManager.createDirectory(at: packURL, withIntermediateDirectories: true)
        let manifest = """
        {
          "header": {
            "name": "Pack A",
            "uuid": "056e5d6e-6135-4daf-844f-5b775b019e56",
            "version": [0, 1, 0],
            "min_engine_version": [1, 19, 50]
          }
        }
        """
        try manifest.write(to: packURL.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        let pack = MinecraftContentItem(
            folderURL: packURL,
            folderName: "PackA",
            contentType: .behaviorPack,
            collectionRootURL: sourceURL.appendingPathComponent("behavior_packs", isDirectory: true)
        )

        let enrichedPack = await WorldScanner.enrich(item: pack)

        #expect(enrichedPack.displayName == "Pack A")
        #expect(enrichedPack.packUUID == "056e5d6e-6135-4daf-844f-5b775b019e56")
        #expect(enrichedPack.packVersion == "0.1.0")
        #expect(enrichedPack.packMetadataDetails?.minimumEngineVersion == "1.19.50")
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

    @Test func connectedDeviceSourceFactoryCreatesStableSyntheticIdentifier() async throws {
        let device = ConnectedDevice(
            udid: "00008110-001234560E90001E",
            name: "John's iPhone",
            productType: "iPhone16,2",
            osVersion: "18.0",
            connection: .usb,
            trustState: .trusted
        )
        let container = DeviceAppContainer(
            deviceUDID: device.udid,
            appID: "com.mojang.minecraftpe",
            appName: "Minecraft",
            accessMode: .documents,
            minecraftFolderRelativePath: "games/com.mojang"
        )

        let source = ConnectedDeviceSourceFactory().makeSource(device: device, container: container)

        #expect(source.origin.kind == .connectedDevice)
        #expect(source.id.scheme == "wmminecraft-device")
        #expect(source.id.host == device.udid)
        #expect(source.displayName == "John's iPhone • Minecraft")
    }

    @Test func ifuseDeviceServicesParsesListAppsOutputAcrossCommonFormats() async throws {
        let output = """
        com.mojang.minecraftpe - Minecraft
        VLC (org.videolan.vlc-ios)
        Documents\tcom.readdle.ReaddleDocs
        com.apple.Pages
        """

        let containers = IFuseDeviceServices.parseAppContainers(
            from: output,
            deviceUDID: "device-1"
        )

        #expect(containers.count == 4)
        #expect(containers.contains { $0.appID == "com.mojang.minecraftpe" && $0.appName == "Minecraft" })
        #expect(containers.contains { $0.appID == "org.videolan.vlc-ios" && $0.appName == "VLC" })
        #expect(containers.contains { $0.appID == "com.readdle.ReaddleDocs" && $0.appName == "Documents" })
        #expect(containers.contains { $0.appID == "com.apple.Pages" && $0.appName == "com.apple.Pages" })
    }

    @Test func ifuseDeviceServicesParsesIdeviceInfoKeyValueOutput() async throws {
        let output = """
        DeviceName: John's iPad
        ProductType: iPad14,5
        ProductVersion: 18.1
        ConnectionType: USB
        """

        let values = IFuseDeviceServices.parseKeyValueOutput(output)

        #expect(values["DeviceName"] == "John's iPad")
        #expect(values["ProductType"] == "iPad14,5")
        #expect(values["ProductVersion"] == "18.1")
        #expect(values["ConnectionType"] == "USB")
    }

}

private enum TestNBTTagType: UInt8 {
    case end = 0
    case byte = 1
    case short = 2
    case int = 3
    case long = 4
    case string = 8
    case list = 9
    case compound = 10
}

private enum TestNBTValue {
    case byte(Int8)
    case short(Int16)
    case int(Int32)
    case long(Int64)
    case string(String)
    case list(TestNBTTagType, [TestNBTValue])
    case compound([String: TestNBTValue])

    var tagType: TestNBTTagType {
        switch self {
        case .byte:
            return .byte
        case .short:
            return .short
        case .int:
            return .int
        case .long:
            return .long
        case .string:
            return .string
        case .list:
            return .list
        case .compound:
            return .compound
        }
    }
}

private func makeBedrockLevelDat(root: TestNBTValue, storageVersion: Int32) -> Data {
    var payload = Data()
    payload.append(TestNBTTagType.compound.rawValue)
    appendLE(UInt16(0), to: &payload)
    appendTagPayload(root, to: &payload)

    var data = Data()
    appendLE(storageVersion, to: &data)
    appendLE(Int32(payload.count), to: &data)
    data.append(payload)
    return data
}

private func appendNamedTag(name: String, value: TestNBTValue, to data: inout Data) {
    data.append(value.tagType.rawValue)
    appendString(name, to: &data)
    appendTagPayload(value, to: &data)
}

private func appendTagPayload(_ value: TestNBTValue, to data: inout Data) {
    switch value {
    case .byte(let value):
        data.append(UInt8(bitPattern: value))
    case .short(let value):
        appendLE(value, to: &data)
    case .int(let value):
        appendLE(value, to: &data)
    case .long(let value):
        appendLE(value, to: &data)
    case .string(let string):
        appendString(string, to: &data)
    case .list(let itemType, let values):
        data.append(itemType.rawValue)
        appendLE(Int32(values.count), to: &data)
        for value in values {
            appendTagPayload(value, to: &data)
        }
    case .compound(let values):
        for key in values.keys.sorted() {
            if let value = values[key] {
                appendNamedTag(name: key, value: value, to: &data)
            }
        }
        data.append(TestNBTTagType.end.rawValue)
    }
}

private func appendString(_ string: String, to data: inout Data) {
    let utf8 = Data(string.utf8)
    appendLE(UInt16(utf8.count), to: &data)
    data.append(utf8)
}

private func appendLE<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
    var value = value.littleEndian
    withUnsafeBytes(of: &value) { bytes in
        data.append(contentsOf: bytes)
    }
}
