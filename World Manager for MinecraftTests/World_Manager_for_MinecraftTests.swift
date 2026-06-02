// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import SQLite3
import Testing
import UniformTypeIdentifiers
@testable import World_Manager_for_Minecraft

@MainActor
struct World_Manager_for_MinecraftTests {

    @Test func sourceOriginsExposeOutboundCapabilities() async throws {
        let localSource = MinecraftSource(folderURL: URL(fileURLWithPath: "/tmp/local"))
        #expect(localSource.capabilities == .localFolder)
        #expect(localSource.edition == .bedrock)
        #expect(localSource.providerID == LocalFolderSourceAccess().accessorIdentifier)
        #expect(localSource.accessStatus.mode == .localFileSystem)

        let device = ConnectedDevice(
            udid: "device",
            name: "Device",
            productType: nil,
            osVersion: nil,
            connection: .usb,
            trustState: .trusted
        )
        let container = DeviceAppContainer(
            deviceUDID: device.udid,
            appID: "com.mojang.minecraftpe",
            appName: "Minecraft",
            accessMode: .documents,
            minecraftFolderRelativePath: "Documents/games/com.mojang"
        )
        let deviceSource = MinecraftSource(
            folderURL: URL(fileURLWithPath: "/tmp/device"),
            origin: .connectedDevice(device: device, container: container)
        )

        #expect(deviceSource.capabilities == .connectedDevice)
        #expect(deviceSource.edition == .bedrock)
        #expect(deviceSource.providerID == AppleMobileDeviceSourceAccess().accessorIdentifier)
        #expect(deviceSource.accessStatus.mode == .usbDevice)
    }

    @Test func contentItemsExposeNeutralProviderSurface() async throws {
        let rootURL = URL(fileURLWithPath: "/tmp/source")
        let item = MinecraftContentItem(
            folderURL: rootURL.appendingPathComponent("minecraftWorlds/WorldA", isDirectory: true),
            folderName: "WorldA",
            contentType: .world,
            collectionRootURL: rootURL.appendingPathComponent("minecraftWorlds", isDirectory: true),
            displayName: "World A",
            packUUID: "ABC-123",
            packVersion: "1.0.0"
        )

        #expect(item.sourceEdition == .bedrock)
        #expect(item.contentKind == .world)
        #expect(item.platformType == .bedrock(.world))
        #expect(item.capabilities.portablePackageExtension == "mcworld")
        if case .bedrock(let metadata) = item.platformMetadata {
            #expect(metadata.packUUID == "abc-123")
            #expect(metadata.packVersion == "1.0.0")
        } else {
            Issue.record("Expected Bedrock metadata")
        }
    }

    @Test func bedrockCompatibilityFieldsSynchronizePlatformMetadata() async throws {
        let rootURL = URL(fileURLWithPath: "/tmp/source")
        var item = MinecraftContentItem(
            folderURL: rootURL.appendingPathComponent("behavior_packs/PackA", isDirectory: true),
            folderName: "PackA",
            contentType: .behaviorPack,
            collectionRootURL: rootURL.appendingPathComponent("behavior_packs", isDirectory: true)
        )

        item.packUUID = "PACK-A"
        item.packVersion = "2.0.0"

        if case .bedrock(let metadata) = item.platformMetadata {
            #expect(metadata.packUUID == "pack-a")
            #expect(metadata.packVersion == "2.0.0")
        } else {
            Issue.record("Expected Bedrock metadata")
        }
    }

    @Test func localFolderAccessStreamsProviderEvents() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let itemURL = rootURL.appendingPathComponent("minecraftWorlds/WorldA", isDirectory: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        try fileManager.createDirectory(at: itemURL, withIntermediateDirectories: true)
        try "World A".write(
            to: itemURL.appendingPathComponent("levelname.txt"),
            atomically: true,
            encoding: .utf8
        )

        let source = MinecraftSource(folderURL: rootURL)
        let access = LocalFolderSourceAccess()
        var sawAccessStatus = false
        var sawRunningStage = false
        var sawFinishedStage = false
        var discoveredItems: [MinecraftContentItem] = []

        for try await event in access.scanEvents(for: source, mode: .fullScan) {
            switch event {
            case .accessStatusChanged(let status):
                sawAccessStatus = true
                #expect(status.availability == .available)
                #expect(status.mode == .localFileSystem)
            case .stageUpdated(let stage):
                if stage.state == .running {
                    sawRunningStage = true
                }
                if stage.state == .succeeded {
                    sawFinishedStage = true
                }
            case .discovered(let item):
                discoveredItems.append(item)
            case .inspected, .warning:
                break
            }
        }

        #expect(sawAccessStatus)
        #expect(sawRunningStage)
        #expect(sawFinishedStage)
        #expect(discoveredItems.map(\.displayName).contains("WorldA"))
    }

    @Test func javaLocalFolderSourceUsesJavaProviderDefaults() async throws {
        let source = MinecraftSource(
            folderURL: URL(fileURLWithPath: "/tmp/java"),
            origin: .javaLocalFolder(bookmarkData: nil)
        )

        #expect(source.edition == .java)
        #expect(source.providerID == JavaLocalFolderSourceAccess().accessorIdentifier)
        #expect(source.accessDescriptor.accessorIdentifier == JavaLocalFolderSourceAccess().accessorIdentifier)
        #expect(source.accessStatus.mode == .localFileSystem)
    }

    @Test func javaLocalFolderAccessDiscoversWorldsAndResourcePacks() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let instanceURL = rootURL.appendingPathComponent("Better MC [NEOFORGE] BMC5", isDirectory: true)
        let worldURL = instanceURL.appendingPathComponent("saves/JavaWorld", isDirectory: true)
        let packURL = instanceURL.appendingPathComponent("resourcepacks/JavaPack", isDirectory: true)
        let zippedPackURL = instanceURL.appendingPathComponent("resourcepacks/JavaPack.zip")
        let shaderPackURL = instanceURL.appendingPathComponent("shaderpacks/Shader.zip")
        let modURL = instanceURL.appendingPathComponent("mods/ExampleMod.jar")
        defer { try? fileManager.removeItem(at: rootURL) }

        try fileManager.createDirectory(at: worldURL, withIntermediateDirectories: true)
        try Data().write(to: worldURL.appendingPathComponent("level.dat"))
        try "Displayed Java World".write(
            to: worldURL.appendingPathComponent("levelname.txt"),
            atomically: true,
            encoding: .utf8
        )
        try fileManager.createDirectory(at: packURL, withIntermediateDirectories: true)
        try "{}".write(
            to: packURL.appendingPathComponent("pack.mcmeta"),
            atomically: true,
            encoding: .utf8
        )
        try fileManager.createDirectory(at: zippedPackURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("zip".utf8).write(to: zippedPackURL)
        try fileManager.createDirectory(at: shaderPackURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("shader".utf8).write(to: shaderPackURL)
        try fileManager.createDirectory(at: modURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("jar".utf8).write(to: modURL)

        let access = SourceAccessCoordinator(
            accessMethods: [
                LocalFolderSourceAccess(),
                JavaLocalFolderSourceAccess()
            ]
        )
        let probe = await access.probeLocalFolder(rootURL)
        #expect(probe?.providerID == JavaLocalFolderSourceAccess().accessorIdentifier)
        #expect(probe?.sourceRootURL == instanceURL.standardizedFileURL)
        #expect(probe?.detectedKinds.contains(.mod) == true)

        var source = MinecraftSource(
            folderURL: instanceURL,
            origin: .localFolder(bookmarkData: nil),
            accessDescriptor: SourceAccessDescriptor(
                accessorIdentifier: JavaLocalFolderSourceAccess().accessorIdentifier,
                kind: .localFolder,
                refreshStrategy: .eagerFullScan
            )
        )
        source.edition = .java
        source.providerID = JavaLocalFolderSourceAccess().accessorIdentifier
        var discoveredItems: [MinecraftContentItem] = []

        for try await event in access.scanEvents(for: source, mode: .fullScan) {
            if case .discovered(let item) = event {
                discoveredItems.append(item)
            }
        }
        var enrichedItems: [MinecraftContentItem] = []
        for item in discoveredItems {
            enrichedItems.append(await access.enrich(item, for: source))
        }

        #expect(discoveredItems.count == 5)
        #expect(discoveredItems.allSatisfy { $0.sourceEdition == .java })
        #expect(discoveredItems.contains { $0.platformType == .java(.world) && $0.capabilities.portablePackageExtension == "zip" })
        #expect(discoveredItems.contains { $0.platformType == .java(.resourcePack) && $0.contentType == .resourcePack })
        #expect(discoveredItems.contains { $0.platformType == .java(.shaderPack) && $0.contentKind == .shaderPack })
        #expect(discoveredItems.contains { $0.platformType == .java(.mod) && $0.contentKind == .mod })
        #expect(enrichedItems.contains { $0.displayName == "Displayed Java World" })

        var indexedSource = source
        indexedSource.rawItems = enrichedItems
        let index = SourceContentIndexer.buildIndex(for: indexedSource)
        #expect(index.displayItemCountsByKind[.world] == 1)
        #expect(index.displayItemCountsByKind[.resourcePack] == 2)
        #expect(index.displayItemCountsByKind[.shaderPack] == 1)
        #expect(index.displayItemCountsByKind[.mod] == 1)

        indexedSource.rawItems = enrichedItems
        let snapshot = SourceScanPolicy.buildSnapshot(for: indexedSource, scanRootURL: instanceURL)
        #expect(snapshot.collectionSnapshots.map(\.folderName).contains("saves"))
        #expect(snapshot.collectionSnapshots.map(\.folderName).contains("resourcepacks"))
        #expect(snapshot.collectionSnapshots.map(\.folderName).contains("shaderpacks"))
        #expect(snapshot.collectionSnapshots.map(\.folderName).contains("mods"))
    }

    @Test func javaArchiveEnrichmentReadsModMetadataPackMetadataAndIcons() async throws {
        let fileManager = FileManager.default
        let workingURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let modSourceURL = workingURL.appendingPathComponent("ModSource", isDirectory: true)
        let resourceSourceURL = workingURL.appendingPathComponent("ResourceSource", isDirectory: true)
        let modArchiveURL = workingURL.appendingPathComponent("ExampleMod.jar")
        let resourceArchiveURL = workingURL.appendingPathComponent("ExamplePack.zip")
        defer { try? fileManager.removeItem(at: workingURL) }

        try fileManager.createDirectory(at: modSourceURL.appendingPathComponent("META-INF", isDirectory: true), withIntermediateDirectories: true)
        try """
        modLoader = "javafml"
        loaderVersion = "[1,)"

        [[mods]]
        modId = "examplemod"
        displayName = "Example Java Mod"
        logoFile = "icon.png"
        description = "A test mod."
        """.write(
            to: modSourceURL.appendingPathComponent("META-INF/neoforge.mods.toml"),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "pack": {
            "description": "Example Mod Resources",
            "pack_format": 31
          }
        }
        """.write(to: modSourceURL.appendingPathComponent("pack.mcmeta"), atomically: true, encoding: .utf8)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: modSourceURL.appendingPathComponent("icon.png"))
        try makeArchive(from: modSourceURL, to: modArchiveURL)

        try fileManager.createDirectory(at: resourceSourceURL, withIntermediateDirectories: true)
        try """
        {
          "pack": {
            "description": "Example Resource Pack",
            "pack_format": 34
          }
        }
        """.write(to: resourceSourceURL.appendingPathComponent("pack.mcmeta"), atomically: true, encoding: .utf8)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: resourceSourceURL.appendingPathComponent("pack.png"))
        try makeArchive(from: resourceSourceURL, to: resourceArchiveURL)

        let modItem = MinecraftContentItem(
            folderURL: modArchiveURL,
            folderName: modArchiveURL.lastPathComponent,
            contentType: .resourcePack,
            sourceEdition: .java,
            contentKind: .mod,
            platformType: .java(.mod),
            collectionRootURL: workingURL,
            capabilities: .java(contentType: .mod),
            platformMetadata: .java(JavaContentMetadata())
        )
        let resourceItem = MinecraftContentItem(
            folderURL: resourceArchiveURL,
            folderName: resourceArchiveURL.lastPathComponent,
            contentType: .resourcePack,
            sourceEdition: .java,
            contentKind: .resourcePack,
            platformType: .java(.resourcePack),
            collectionRootURL: workingURL,
            capabilities: .java(contentType: .resourcePack),
            platformMetadata: .java(JavaContentMetadata())
        )

        let enrichedMod = await JavaContentScanner.enrich(item: modItem)
        let enrichedResource = await JavaContentScanner.enrich(item: resourceItem)

        #expect(enrichedMod.displayName == "Example Java Mod")
        #expect(enrichedMod.iconURL != nil)
        #expect(enrichedMod.hasKnownIcon)
        if case .java(let metadata) = enrichedMod.platformMetadata {
            #expect(metadata.pack?.description == "Example Mod Resources")
            #expect(metadata.pack?.packFormat == 31)
        } else {
            Issue.record("Expected Java metadata")
        }

        #expect(enrichedResource.iconURL != nil)
        if case .java(let metadata) = enrichedResource.platformMetadata {
            #expect(metadata.pack?.description == "Example Resource Pack")
            #expect(metadata.pack?.packFormat == 34)
        } else {
            Issue.record("Expected Java metadata")
        }
    }

    @Test func javaProviderDiscoversSourceCandidatesFromBoundedRoots() async throws {
        let fileManager = FileManager.default
        let workingURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let instanceRootURL = workingURL
            .appendingPathComponent("PrismLauncher/instances/Example Instance/.minecraft", isDirectory: true)
        let modURL = instanceRootURL.appendingPathComponent("mods/ExampleMod.jar")
        defer { try? fileManager.removeItem(at: workingURL) }

        try fileManager.createDirectory(at: modURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("jar".utf8).write(to: modURL)
        try fileManager.createDirectory(
            at: instanceRootURL.appendingPathComponent("resourcepacks", isDirectory: true),
            withIntermediateDirectories: true
        )

        let access = JavaLocalFolderSourceAccess(candidateDiscoveryRoots: [workingURL])
        var candidates: [SourceCandidate] = []

        for try await event in access.discoverSourceCandidates() {
            if case .candidate(let candidate) = event {
                candidates.append(candidate)
            }
        }

        #expect(candidates.contains { candidate in
            candidate.providerID == JavaLocalFolderSourceAccess().accessorIdentifier
                && candidate.edition == .java
                && candidate.sourceRootURL == instanceRootURL.standardizedFileURL
                && candidate.detectedKinds.contains(.mod)
                && candidate.detectedKinds.contains(.resourcePack)
        })
    }

    @Test func javaProviderCollapsesNestedSourceCandidatesToSearchRoot() async throws {
        let fileManager = FileManager.default
        let workingURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let firstInstanceURL = workingURL.appendingPathComponent("a/b/c", isDirectory: true)
        let secondInstanceURL = workingURL.appendingPathComponent("a/e/f", isDirectory: true)
        defer { try? fileManager.removeItem(at: workingURL) }

        for instanceURL in [firstInstanceURL, secondInstanceURL] {
            try fileManager.createDirectory(
                at: instanceURL.appendingPathComponent("mods", isDirectory: true),
                withIntermediateDirectories: true
            )
            try Data("jar".utf8).write(to: instanceURL.appendingPathComponent("mods/ExampleMod.jar"))
        }

        let candidates = JavaContentScanner.discoverSourceCandidates(
            providerID: JavaLocalFolderSourceAccess().accessorIdentifier,
            searchRoots: [workingURL]
        )

        #expect(candidates.count == 1)
        #expect(candidates.first?.sourceRootURL == workingURL.standardizedFileURL)
        #expect(candidates.first?.displayName == workingURL.lastPathComponent)
        #expect(candidates.first?.detectedKinds.contains(.mod) == true)
    }

    @Test func javaAggregateRootDiscoversNestedInstanceItems() async throws {
        let fileManager = FileManager.default
        let workingURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let firstInstanceURL = workingURL.appendingPathComponent("a/b/c", isDirectory: true)
        let secondInstanceURL = workingURL.appendingPathComponent("a/e/f", isDirectory: true)
        defer { try? fileManager.removeItem(at: workingURL) }

        try fileManager.createDirectory(
            at: firstInstanceURL.appendingPathComponent("mods", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("jar".utf8).write(to: firstInstanceURL.appendingPathComponent("mods/ExampleMod.jar"))

        try fileManager.createDirectory(
            at: secondInstanceURL.appendingPathComponent("resourcepacks", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("zip".utf8).write(to: secondInstanceURL.appendingPathComponent("resourcepacks/ExamplePack.zip"))

        let items = try JavaContentScanner.discoverItems(in: workingURL)
        let snapshots = JavaContentScanner.collectionSnapshots(in: workingURL)

        #expect(items.contains { $0.contentKind == .mod && $0.folderName == "ExampleMod.jar" })
        #expect(items.contains { $0.contentKind == .resourcePack && $0.folderName == "ExamplePack.zip" })
        #expect(snapshots.map(\.folderName).contains("a/b/c/mods"))
        #expect(snapshots.map(\.folderName).contains("a/e/f/resourcepacks"))
    }

    @Test func sourceLibraryAddSourceResolvesJavaWrapperFolder() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let instanceURL = rootURL.appendingPathComponent("Better MC [NEOFORGE] BMC5", isDirectory: true)
        let modURL = instanceURL.appendingPathComponent("mods/ExampleMod.jar")
        defer { try? fileManager.removeItem(at: rootURL) }

        try fileManager.createDirectory(at: modURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("jar".utf8).write(to: modURL)
        try fileManager.createDirectory(
            at: instanceURL.appendingPathComponent("resourcepacks", isDirectory: true),
            withIntermediateDirectories: true
        )

        let access = SourceAccessCoordinator(
            accessMethods: [
                LocalFolderSourceAccess(),
                JavaLocalFolderSourceAccess()
            ]
        )
        let library = SourceLibrary(sourceAccessMethod: access)

        let sourceID = await library.addSource(at: rootURL)
        guard let source = library.source(withID: sourceID) else {
            Issue.record("Expected added source")
            return
        }

        #expect(source.folderURL == instanceURL.standardizedFileURL)
        #expect(source.origin.kind == .localFolder)
        #expect(source.edition == .java)
        #expect(source.providerID == JavaLocalFolderSourceAccess().accessorIdentifier)
        #expect(source.accessDescriptor.accessorIdentifier == JavaLocalFolderSourceAccess().accessorIdentifier)
    }

    @Test func libraryExternalRepresentationUsesPortablePackageByDefault() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let itemURL = rootURL.appendingPathComponent("minecraftWorlds/WorldA", isDirectory: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        try fileManager.createDirectory(at: itemURL, withIntermediateDirectories: true)
        try "hello".write(
            to: itemURL.appendingPathComponent("levelname.txt"),
            atomically: true,
            encoding: .utf8
        )

        let item = MinecraftContentItem(
            folderURL: itemURL,
            folderName: "WorldA",
            contentType: .world,
            collectionRootURL: rootURL.appendingPathComponent("minecraftWorlds", isDirectory: true),
            displayName: "World A"
        )
        let source = MinecraftSource(folderURL: rootURL)
        let library = SourceLibrary()

        let representation = try await library.externalRepresentation(for: item, in: source)

        #expect(representation.kind == .portablePackage)
        #expect(representation.suggestedFilename == "World A.mcworld")
        #expect(representation.contentType.preferredFilenameExtension == "mcworld")
        #expect(representation.isTemporary)
        #expect(fileManager.fileExists(atPath: representation.url.path))
    }

    @Test func libraryExternalRepresentationUsesNativeFolderWhenRequested() async throws {
        let rootURL = URL(fileURLWithPath: "/tmp/source-root", isDirectory: true)
        let itemURL = rootURL.appendingPathComponent("minecraftWorlds/WorldA", isDirectory: true)
        let item = MinecraftContentItem(
            folderURL: itemURL,
            folderName: "WorldA",
            contentType: .world,
            collectionRootURL: rootURL.appendingPathComponent("minecraftWorlds", isDirectory: true),
            displayName: "World A"
        )
        let source = MinecraftSource(folderURL: rootURL)
        let library = SourceLibrary()

        let representation = try await library.externalRepresentation(
            for: item,
            in: source,
            preferredKind: .nativeFolder
        )

        #expect(representation.kind == .nativeFolder)
        #expect(representation.url == itemURL)
        #expect(representation.suggestedFilename == "World A")
        #expect(representation.contentType == .folder)
        #expect(representation.isTemporary == false)
    }

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

    @Test func minecraftSourceResolvedPackReferencesUseLogicalPackRepresentative() async throws {
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
        source.worldPackRelationships = [
            WorldPackRelationship(
                worldItemID: world.id,
                logicalPackID: packID,
                reference: ContentPackReference(
                    name: "Embedded Copy",
                    type: .behaviorPack,
                    uuid: "pack-a",
                    version: "1.0.0",
                    source: .embeddedInWorld
                )
            )
        ]

        let references = source.resolvedPackReferences(for: world.id, type: .behaviorPack)

        #expect(references.count == 1)
        #expect(references.first?.name == "Pack A")
        #expect(references.first?.uuid == "pack-a")
        #expect(references.first?.version == "1.0.0")
        #expect(references.first?.iconURL == topLevelPack.iconURL)
    }

    @Test func minecraftSourceRelationshipHelpersAndCacheStateReflectCurrentData() async throws {
        let sourceURL = URL(fileURLWithPath: "/tmp/source")
        let worldA = MinecraftContentItem(
            folderURL: sourceURL.appendingPathComponent("minecraftWorlds/WorldA", isDirectory: true),
            folderName: "WorldA",
            contentType: .world,
            collectionRootURL: sourceURL.appendingPathComponent("minecraftWorlds", isDirectory: true),
            displayName: "Alpha"
        )
        let worldB = MinecraftContentItem(
            folderURL: sourceURL.appendingPathComponent("minecraftWorlds/WorldB", isDirectory: true),
            folderName: "WorldB",
            contentType: .world,
            collectionRootURL: sourceURL.appendingPathComponent("minecraftWorlds", isDirectory: true),
            displayName: "Beta"
        )
        let packID = PackIdentity(
            type: .behaviorPack,
            uuid: "pack-a",
            version: "1.0.0",
            fallbackName: "Pack A",
            fallbackLocationHint: "behavior_packs/PackA"
        )
        let packItem = MinecraftContentItem(
            folderURL: sourceURL.appendingPathComponent("behavior_packs/PackA", isDirectory: true),
            folderName: "PackA",
            contentType: .behaviorPack,
            collectionRootURL: sourceURL.appendingPathComponent("behavior_packs", isDirectory: true),
            displayName: "Pack A"
        )

        var source = MinecraftSource(folderURL: sourceURL, availability: .disconnected)
        source.displayName = "Source"
        source.displayItems = [worldA]
        source.rawItems = [worldB, packItem, worldA]
        source.logicalPacks = [
            LogicalPack(
                id: packID,
                contentType: .behaviorPack,
                displayName: "Pack A",
                uuid: "pack-a",
                version: "1.0.0",
                representativeItemID: packItem.id,
                instanceItemIDs: [packItem.id],
                isSuspicious: false
            )
        ]
        source.logicalWorlds = [
            LogicalWorld(
                id: worldA.id,
                itemID: worldA.id,
                usedPackIDs: [packID],
                unresolvedReferences: []
            )
        ]
        source.packInstances = [
            PackInstance(
                id: packItem.id,
                itemID: packItem.id,
                sourceID: source.id,
                logicalPackID: packID,
                origin: .foundInCollection,
                hostWorldItemID: nil
            )
        ]
        source.worldPackRelationships = [
            WorldPackRelationship(
                worldItemID: worldB.id,
                logicalPackID: packID,
                reference: ContentPackReference(name: "Pack A", type: .behaviorPack, uuid: "pack-a", version: "1.0.0", source: .foundInCollection)
            ),
            WorldPackRelationship(
                worldItemID: worldA.id,
                logicalPackID: packID,
                reference: ContentPackReference(name: "Pack A", type: .behaviorPack, uuid: "pack-a", version: "1.0.0", source: .foundInCollection)
            ),
            WorldPackRelationship(
                worldItemID: worldA.id,
                logicalPackID: packID,
                reference: ContentPackReference(name: "Pack A", type: .behaviorPack, uuid: "pack-a", version: "1.0.0", source: .foundInCollection)
            )
        ]
        source.lastScanDate = Date(timeIntervalSince1970: 123)

        #expect(source.itemCount == 1)
        #expect(source.hasCachedContent)
        #expect(source.isOfflineCached)
        #expect(source.items == [worldA])
        #expect(source.rawItem(withID: worldA.id) == worldA)
        #expect(source.logicalPack(forRepresentativeItemID: packItem.id)?.id == packID)
        #expect(source.logicalWorld(forItemID: worldA.id)?.id == worldA.id)
        #expect(source.packInstances(for: packID).count == 1)

        let worldsUsingPack = source.worldsUsingPack(packID)
        #expect(worldsUsingPack == [worldA, worldB])

        let sourceRecord = source.sourceRecord
        #expect(sourceRecord.id == source.id)
        #expect(sourceRecord.displayName == "Source")
        #expect(sourceRecord.rootURL == source.folderURL)
        #expect(sourceRecord.origin == source.origin)
        #expect(sourceRecord.accessDescriptor == source.accessDescriptor)
        #expect(sourceRecord.availability == .disconnected)
        #expect(sourceRecord.lastRefreshDate == source.lastScanDate)
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

    @Test func worldScannerDiscoversItemsAcrossCollectionsAndEmbeddedPacks() async throws {
        let fileManager = FileManager.default
        let sourceURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let worldURL = sourceURL.appendingPathComponent("minecraftWorlds/WorldA", isDirectory: true)
        let invalidWorldURL = sourceURL.appendingPathComponent("minecraftWorlds/NotAWorld", isDirectory: true)
        let embeddedBehaviorPackURL = worldURL.appendingPathComponent("behavior_packs/EmbeddedBehavior", isDirectory: true)
        let embeddedResourcePackURL = worldURL.appendingPathComponent("resource_packs/EmbeddedResource", isDirectory: true)
        let topLevelBehaviorPackURL = sourceURL.appendingPathComponent("behavior_packs/TopBehavior", isDirectory: true)
        let topLevelResourcePackURL = sourceURL.appendingPathComponent("RESOURCE_PACKS/TopResource", isDirectory: true)
        defer { try? fileManager.removeItem(at: sourceURL) }

        try fileManager.createDirectory(at: worldURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: invalidWorldURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: embeddedBehaviorPackURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: embeddedResourcePackURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: topLevelBehaviorPackURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: topLevelResourcePackURL, withIntermediateDirectories: true)

        try Data().write(to: worldURL.appendingPathComponent("level.dat"))
        try "{}".write(to: embeddedBehaviorPackURL.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: embeddedResourcePackURL.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: topLevelBehaviorPackURL.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try Data().write(to: topLevelResourcePackURL.appendingPathComponent("pack_icon.png"))

        let discoveredRecorder = LockedRecorder<URL>()
        let discovered = try WorldScanner.discoverItems(in: sourceURL) { item in
            discoveredRecorder.append(item.id)
        }

        #expect(discovered.count == 5)
        #expect(Set(discovered.map(\.id)) == Set(discoveredRecorder.values))
        #expect(discovered.contains { $0.folderURL.standardizedFileURL == worldURL.standardizedFileURL && $0.contentType == .world })
        #expect(discovered.contains { $0.folderURL.standardizedFileURL == embeddedBehaviorPackURL.standardizedFileURL && $0.contentType == .behaviorPack })
        #expect(discovered.contains { $0.folderURL.standardizedFileURL == embeddedResourcePackURL.standardizedFileURL && $0.contentType == .resourcePack })
        #expect(discovered.contains { $0.folderURL.standardizedFileURL == topLevelBehaviorPackURL.standardizedFileURL && $0.contentType == .behaviorPack })
        #expect(discovered.contains { $0.folderURL.standardizedFileURL == topLevelResourcePackURL.standardizedFileURL && $0.contentType == .resourcePack })
        #expect(discovered.contains { $0.folderURL.standardizedFileURL == invalidWorldURL.standardizedFileURL } == false)
    }

    @Test func worldScannerCollectionRootDiscoverySnapshotsAndSizeLoading() async throws {
        let fileManager = FileManager.default
        let sourceURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let worldsURL = sourceURL.appendingPathComponent("minecraftWorlds", isDirectory: true)
        let worldAURL = worldsURL.appendingPathComponent("WorldA", isDirectory: true)
        let worldBURL = worldsURL.appendingPathComponent("WorldB", isDirectory: true)
        let packsURL = sourceURL.appendingPathComponent("behavior_packs", isDirectory: true)
        let packURL = packsURL.appendingPathComponent("PackA", isDirectory: true)
        defer { try? fileManager.removeItem(at: sourceURL) }

        try fileManager.createDirectory(at: worldAURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: worldBURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: packURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: worldAURL.appendingPathComponent("db", isDirectory: true), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: worldAURL.appendingPathComponent("level.dat"))
        try "World B".write(to: worldBURL.appendingPathComponent("levelname.txt"), atomically: true, encoding: .utf8)
        try Data([4, 5]).write(to: worldAURL.appendingPathComponent("db/chunk.bin"), options: .atomic)
        try "{}".write(to: packURL.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try "ignore".write(to: worldsURL.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        let callbackRecorder = LockedRecorder<Int>()
        let worlds = try WorldScanner.discoverItems(inCollectionRootURL: worldsURL, contentType: .world) { _ in
            callbackRecorder.append(1)
        }
        let snapshots = WorldScanner.collectionSnapshots(in: sourceURL)
        let sizedWorld = WorldScanner.loadSize(for: worlds[0])
        await WorldScanner.endScanSession(for: sourceURL)

        #expect(worlds.count == 2)
        #expect(callbackRecorder.values.count == 2)
        #expect(snapshots.count == 2)
        #expect(snapshots.contains { $0.folderName == "minecraftWorlds" && $0.childDirectoryCount == 2 })
        #expect(snapshots.contains { $0.folderName == "behavior_packs" && $0.childDirectoryCount == 1 })
        #expect(snapshots.first(where: { $0.folderName == "minecraftWorlds" })?.fingerprint.contains("WorldA@") == true)
        #expect(sizedWorld.sizeLoaded)
        #expect(sizedWorld.sizeBytes == 5)
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

    @Test func minecraftContentMetadataReaderPrefersExpectedNamesIconsAndVersions() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let worldURL = rootURL.appendingPathComponent("WorldA", isDirectory: true)
        let packURL = rootURL.appendingPathComponent("PackA", isDirectory: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        try fileManager.createDirectory(at: worldURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: packURL, withIntermediateDirectories: true)

        try "  My World  ".write(to: worldURL.appendingPathComponent("levelname.txt"), atomically: true, encoding: .utf8)
        try Data([1]).write(to: worldURL.appendingPathComponent("world_icon.jpg"))
        try Data([2]).write(to: worldURL.appendingPathComponent("world_icon.png"))

        let manifest = """
        {
          "header": {
            "name": "  Fancy Pack  ",
            "uuid": "ABC-123",
            "version": [1, "2", 3],
            "min_engine_version": "1.21.0"
          }
        }
        """
        try manifest.write(to: packURL.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try Data([3]).write(to: packURL.appendingPathComponent("pack_icon.jpeg"))
        try Data([4]).write(to: packURL.appendingPathComponent("pack_icon.jpg"))

        #expect(MinecraftContentMetadataReader.displayName(for: worldURL, contentType: .world, fallbackName: "Fallback") == "My World")
        #expect(MinecraftContentMetadataReader.displayName(for: packURL, contentType: .behaviorPack, fallbackName: "Fallback") == "Fancy Pack")
        #expect(MinecraftContentMetadataReader.iconURL(for: worldURL, contentType: .world) == worldURL.appendingPathComponent("world_icon.jpg"))
        #expect(MinecraftContentMetadataReader.iconURL(for: packURL, contentType: .behaviorPack) == packURL.appendingPathComponent("pack_icon.jpeg"))
        #expect(MinecraftContentMetadataReader.packIconURL(in: packURL) == packURL.appendingPathComponent("pack_icon.jpeg"))
        #expect(MinecraftContentMetadataReader.manifestMetadata(in: packURL)?.uuid == "abc-123")
        #expect(MinecraftContentMetadataReader.manifestMetadata(in: packURL)?.version == "1.2.3")
        #expect(MinecraftContentMetadataReader.manifestMetadata(in: packURL)?.minimumEngineVersion == "1.21.0")
        #expect(MinecraftContentMetadataReader.versionString(from: "") == nil)
        #expect(MinecraftContentMetadataReader.versionString(from: [1, "2", 3]) == "1.2.3")
        #expect(MinecraftContentMetadataReader.versionString(from: [[:]]) == nil)
    }

    @Test func minecraftContentMetadataReaderInfersPackTypesAndFallbacks() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let resourceURL = rootURL.appendingPathComponent("ResourcePack", isDirectory: true)
        let skinURL = rootURL.appendingPathComponent("SkinPack", isDirectory: true)
        let behaviorURL = rootURL.appendingPathComponent("BehaviorPack", isDirectory: true)
        let fallbackURL = rootURL.appendingPathComponent("FallbackPack", isDirectory: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        try fileManager.createDirectory(at: resourceURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: skinURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: behaviorURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: fallbackURL, withIntermediateDirectories: true)

        try """
        { "modules": [{ "type": "resources" }] }
        """.write(to: resourceURL.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try """
        { "metadata": { "product_type": "skin_pack" } }
        """.write(to: skinURL.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try """
        { "modules": [{ "type": "script" }] }
        """.write(to: behaviorURL.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try """
        { "header": { "name": "   " } }
        """.write(to: fallbackURL.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        #expect(MinecraftContentMetadataReader.inferredPackContentType(for: resourceURL) == .resourcePack)
        #expect(MinecraftContentMetadataReader.inferredPackContentType(for: skinURL) == .skinPack)
        #expect(MinecraftContentMetadataReader.inferredPackContentType(for: behaviorURL) == .behaviorPack)
        #expect(MinecraftContentMetadataReader.inferredPackContentType(for: rootURL.appendingPathComponent("Missing", isDirectory: true)) == .behaviorPack)
        #expect(MinecraftContentMetadataReader.displayName(for: fallbackURL, contentType: .behaviorPack, fallbackName: "Ignored") == "FallbackPack")
    }

    @Test func minecraftPackageInspectorReadsMcworldMetadata() async throws {
        let fileManager = FileManager.default
        let workingURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceDirectoryURL = workingURL.appendingPathComponent("WorldSource", isDirectory: true)
        let archiveURL = workingURL.appendingPathComponent("WorldA.mcworld", isDirectory: false)
        defer { try? fileManager.removeItem(at: workingURL) }

        try fileManager.createDirectory(at: sourceDirectoryURL, withIntermediateDirectories: true)
        try "World A".write(
            to: sourceDirectoryURL.appendingPathComponent("levelname.txt"),
            atomically: true,
            encoding: .utf8
        )

        let lastPlayedMilliseconds: Int64 = 1_700_000_000_000
        let levelDat = makeBedrockLevelDat(
            root: .compound([
                "GameType": .int(0),
                "Difficulty": .int(2),
                "LastPlayed": .long(lastPlayedMilliseconds)
            ]),
            storageVersion: 10
        )
        try levelDat.write(to: sourceDirectoryURL.appendingPathComponent("level.dat"))
        try makeArchive(from: sourceDirectoryURL, to: archiveURL)

        let inspection = try MinecraftPackageInspector.inspectArchive(at: archiveURL)
        defer { MinecraftPackageInspector.cleanup(inspection) }

        #expect(inspection.contentType == .world)
        #expect(inspection.displayName == "World A")
        #expect(inspection.worldMetadata?.gameMode == "Survival")
        #expect(inspection.worldMetadata?.difficulty == "Normal")
        #expect(inspection.worldMetadata?.lastPlayedDate == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test func minecraftPackageInspectorInfersMcpackTypeAndManifest() async throws {
        let fileManager = FileManager.default
        let workingURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceDirectoryURL = workingURL.appendingPathComponent("PackSource", isDirectory: true)
        let archiveURL = workingURL.appendingPathComponent("PackA.mcpack", isDirectory: false)
        defer { try? fileManager.removeItem(at: workingURL) }

        try fileManager.createDirectory(at: sourceDirectoryURL, withIntermediateDirectories: true)
        let manifest = """
        {
          "header": {
            "name": "Resource Pack A",
            "uuid": "b92836dc-f5a4-4f10-9d29-6a2d2ea3a2f7",
            "version": [2, 1, 0],
            "min_engine_version": [1, 21, 0]
          },
          "modules": [
            {
              "type": "resources",
              "uuid": "818ac674-bf84-4955-a1db-5bf7acd63488",
              "version": [2, 1, 0]
            }
          ]
        }
        """
        try manifest.write(
            to: sourceDirectoryURL.appendingPathComponent("manifest.json"),
            atomically: true,
            encoding: .utf8
        )
        try makeArchive(from: sourceDirectoryURL, to: archiveURL)

        let inspection = try MinecraftPackageInspector.inspectArchive(at: archiveURL)
        defer { MinecraftPackageInspector.cleanup(inspection) }

        #expect(inspection.contentType == .resourcePack)
        #expect(inspection.displayName == "Resource Pack A")
        #expect(inspection.manifestMetadata?.uuid == "b92836dc-f5a4-4f10-9d29-6a2d2ea3a2f7")
        #expect(inspection.manifestMetadata?.version == "2.1.0")
        #expect(inspection.manifestMetadata?.minimumEngineVersion == "1.21.0")
    }

    @Test func minecraftPackageInspectorAcceptsSingleNestedTopLevelFolder() async throws {
        let fileManager = FileManager.default
        let workingURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let archiveRootURL = workingURL.appendingPathComponent("ArchiveRoot", isDirectory: true)
        let nestedPackURL = archiveRootURL.appendingPathComponent("Nested Pack", isDirectory: true)
        let archiveURL = workingURL.appendingPathComponent("Nested.mcpack", isDirectory: false)
        defer { try? fileManager.removeItem(at: workingURL) }

        try fileManager.createDirectory(at: nestedPackURL, withIntermediateDirectories: true)
        let manifest = """
        {
          "header": {
            "name": "Nested Behavior Pack",
            "uuid": "2bcd9b1a-c558-4906-9521-7cccd2f9ca56",
            "version": [1, 0, 1]
          },
          "modules": [
            {
              "type": "data",
              "uuid": "4fbe707b-7cd1-4d10-80a5-b4fb45f79095",
              "version": [1, 0, 1]
            }
          ]
        }
        """
        try manifest.write(
            to: nestedPackURL.appendingPathComponent("manifest.json"),
            atomically: true,
            encoding: .utf8
        )
        try makeArchive(from: archiveRootURL, to: archiveURL)

        let inspection = try MinecraftPackageInspector.inspectArchive(at: archiveURL)
        defer { MinecraftPackageInspector.cleanup(inspection) }

        #expect(inspection.contentRootURL.lastPathComponent == "Nested Pack")
        #expect(inspection.contentType == .behaviorPack)
        #expect(inspection.displayName == "Nested Behavior Pack")
    }

    @Test func minecraftPackageInspectorRejectsUnsupportedExtension() async throws {
        let fileManager = FileManager.default
        let workingURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let archiveURL = workingURL.appendingPathComponent("Invalid.zip", isDirectory: false)
        defer { try? fileManager.removeItem(at: workingURL) }

        try fileManager.createDirectory(at: workingURL, withIntermediateDirectories: true)
        try Data().write(to: archiveURL)

        do {
            _ = try MinecraftPackageInspector.inspectArchive(at: archiveURL)
            Issue.record("Expected unsupported file type error.")
        } catch let error as MinecraftPackageInspector.InspectionError {
            switch error {
            case .unsupportedFileType(let pathExtension):
                #expect(pathExtension == "zip")
            default:
                Issue.record("Expected unsupported file type error but received \(error).")
            }
            #expect(error.errorDescription == "Unsupported Minecraft package type: .zip")
        }
    }

    @Test func minecraftPackageInspectorRejectsAmbiguousNestedArchiveLayout() async throws {
        let fileManager = FileManager.default
        let workingURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let archiveRootURL = workingURL.appendingPathComponent("ArchiveRoot", isDirectory: true)
        let firstPackURL = archiveRootURL.appendingPathComponent("PackOne", isDirectory: true)
        let secondPackURL = archiveRootURL.appendingPathComponent("PackTwo", isDirectory: true)
        let archiveURL = workingURL.appendingPathComponent("Ambiguous.mcpack", isDirectory: false)
        defer { try? fileManager.removeItem(at: workingURL) }

        try fileManager.createDirectory(at: firstPackURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: secondPackURL, withIntermediateDirectories: true)
        try "{}".write(to: firstPackURL.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: secondPackURL.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try makeArchive(from: archiveRootURL, to: archiveURL)

        do {
            _ = try MinecraftPackageInspector.inspectArchive(at: archiveURL)
            Issue.record("Expected invalid archive layout error.")
        } catch let error as MinecraftPackageInspector.InspectionError {
            switch error {
            case .invalidArchiveLayout:
                break
            default:
                Issue.record("Expected invalid archive layout error but received \(error).")
            }
            #expect(error.errorDescription == "The Minecraft package did not contain a valid world or pack layout.")
        }
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
        #expect(restored.first?.snapshot?.sourceID == snapshot.sourceID)
        #expect(restored.first?.snapshot?.rootModifiedDate == snapshot.rootModifiedDate)
        #expect(restored.first?.snapshot?.collectionSnapshots == snapshot.collectionSnapshots)
        #expect(restored.first?.snapshot?.itemSnapshots.count == snapshot.itemSnapshots.count)
        #expect(
            normalizedTestFileURLPath(restored.first?.snapshot?.itemSnapshots.first?.id)
            == normalizedTestFileURLPath(snapshot.itemSnapshots.first?.id)
        )
        #expect(restored.first?.snapshot?.itemSnapshots.first?.relativePath == snapshot.itemSnapshots.first?.relativePath)
        #expect(restored.first?.snapshot?.itemSnapshots.first?.modifiedDate == snapshot.itemSnapshots.first?.modifiedDate)
        #expect(restored.first?.snapshot?.itemSnapshots.first?.sizeBytes == snapshot.itemSnapshots.first?.sizeBytes)
        #expect(restored.first?.snapshot?.itemSnapshots.first?.packUUID == snapshot.itemSnapshots.first?.packUUID)
        #expect(restored.first?.snapshot?.itemSnapshots.first?.packVersion == snapshot.itemSnapshots.first?.packVersion)
        #expect(restored.first?.lastScanDate == source.lastScanDate)
    }

    @Test func sourcePersistenceStoreDeletesSavedSource() async throws {
        let fileManager = FileManager.default
        let workingURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = workingURL.appendingPathComponent("cache.sqlite", isDirectory: false)
        let sourceURL = workingURL.appendingPathComponent("Source", isDirectory: true)
        defer { try? fileManager.removeItem(at: workingURL) }

        let store = SourcePersistenceStore(databaseURL: databaseURL)
        try await store.save(source: MinecraftSource(folderURL: sourceURL))
        #expect(try await store.loadSources().count == 1)

        try await store.deleteSource(withID: sourceURL)

        #expect(try await store.loadSources().isEmpty)
    }

    @Test func sourcePersistenceStoreRepairsLegacyPayloadsLeniently() async throws {
        let fileManager = FileManager.default
        let workingURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = workingURL.appendingPathComponent("cache.sqlite", isDirectory: false)
        let sourceURL = workingURL.appendingPathComponent("Source", isDirectory: true)
        defer { try? fileManager.removeItem(at: workingURL) }

        let store = SourcePersistenceStore(databaseURL: databaseURL)
        try await store.save(source: MinecraftSource(folderURL: sourceURL))

        let validItem = MinecraftContentItem(
            folderURL: sourceURL.appendingPathComponent("minecraftWorlds/WorldA", isDirectory: true),
            folderName: "WorldA",
            contentType: .world,
            collectionRootURL: sourceURL.appendingPathComponent("minecraftWorlds", isDirectory: true),
            displayName: "World A"
        )
        let mixedRawItems = try JSONSerialization.data(withJSONObject: [
            try jsonObject(for: validItem),
            5
        ])

        try withSQLiteDatabase(at: databaseURL) { database in
            try sqliteExec(
                """
                UPDATE source_cache
                SET origin_json = ?,
                    access_descriptor_json = ?,
                    raw_items_json = ?,
                    snapshot_json = ?,
                    availability_state = 'bogus'
                WHERE folder_path = ?;
                """,
                on: database,
                bindings: [
                    .blob(Data("{".utf8)),
                    .blob(Data("{".utf8)),
                    .blob(mixedRawItems),
                    .blob(Data("{".utf8)),
                    .text(sourceURL.path)
                ]
            )
        }

        let repaired = try await store.loadSources()

        #expect(repaired.count == 1)
        #expect(repaired[0].needsRepair)
        #expect(repaired[0].origin.kind == .localFolder)
        #expect(repaired[0].accessDescriptor.kind == .localFolder)
        #expect(repaired[0].accessDescriptor.refreshStrategy == .eagerFullScan)
        #expect(repaired[0].availability == .unknown)
        #expect(repaired[0].rawItems == [validItem])
        #expect(repaired[0].snapshot == nil)
    }

    @Test func sourcePersistenceStoreRepairPersistsNormalizedRecord() async throws {
        let fileManager = FileManager.default
        let workingURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = workingURL.appendingPathComponent("cache.sqlite", isDirectory: false)
        let sourceURL = workingURL.appendingPathComponent("Source", isDirectory: true)
        defer { try? fileManager.removeItem(at: workingURL) }

        let legacyRecord = PersistedSourceRecord(
            sourceID: sourceURL,
            folderURL: sourceURL,
            origin: .localFolder(bookmarkData: nil),
            accessDescriptor: SourceAccessDescriptor(
                accessorIdentifier: LocalFolderSourceAccess().accessorIdentifier,
                kind: .localFolder,
                refreshStrategy: .eagerFullScan
            ),
            availability: .available,
            bookmarkData: nil,
            displayName: "Repaired Source",
            rawItems: [],
            snapshot: nil,
            lastScanDate: Date(timeIntervalSince1970: 999),
            needsRepair: true
        )

        let store = SourcePersistenceStore(databaseURL: databaseURL)
        try await store.repair(record: legacyRecord)

        let restored = try await store.loadSources()
        #expect(restored.count == 1)
        #expect(restored[0].displayName == "Repaired Source")
        #expect(restored[0].sourceID == sourceURL.standardizedFileURL)
        #expect(restored[0].availability == .available)
        #expect(restored[0].lastScanDate == legacyRecord.lastScanDate)
    }

    @Test func sourceRestorationPreservesJavaProviderResolvedLocalFolder() async throws {
        let sourceURL = URL(fileURLWithPath: "/tmp/JavaInstance", isDirectory: true)
        let accessDescriptor = SourceAccessDescriptor(
            accessorIdentifier: JavaLocalFolderSourceAccess().accessorIdentifier,
            kind: .localFolder,
            refreshStrategy: .eagerFullScan
        )
        let record = PersistedSourceRecord(
            sourceID: sourceURL,
            folderURL: sourceURL,
            origin: .localFolder(bookmarkData: nil),
            accessDescriptor: accessDescriptor,
            availability: .available,
            bookmarkData: nil,
            displayName: "Java Instance",
            rawItems: [],
            snapshot: nil,
            lastScanDate: nil,
            needsRepair: false
        )

        let source = SourceRestoration.restoredSource(from: record) { _, _ in "" }

        #expect(source.origin.kind == .localFolder)
        #expect(source.edition == .java)
        #expect(source.providerID == JavaLocalFolderSourceAccess().accessorIdentifier)
        #expect(source.accessDescriptor == accessDescriptor)
    }

    @Test func javaRestoredSnapshotDoesNotRequestRefreshWhenUnchanged() async throws {
        let fileManager = FileManager.default
        let sourceURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let modURL = sourceURL.appendingPathComponent("mods/ExampleMod.jar")
        defer { try? fileManager.removeItem(at: sourceURL) }

        try fileManager.createDirectory(at: modURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("jar".utf8).write(to: modURL)

        let item = MinecraftContentItem(
            folderURL: modURL,
            folderName: modURL.lastPathComponent,
            contentType: .resourcePack,
            sourceEdition: .java,
            contentKind: .mod,
            platformType: .java(.mod),
            collectionRootURL: modURL.deletingLastPathComponent(),
            displayName: "ExampleMod",
            capabilities: .java(contentType: .mod),
            platformMetadata: .java(JavaContentMetadata())
        )
        var source = MinecraftSource(
            folderURL: sourceURL,
            origin: .localFolder(bookmarkData: nil),
            accessDescriptor: SourceAccessDescriptor(
                accessorIdentifier: JavaLocalFolderSourceAccess().accessorIdentifier,
                kind: .localFolder,
                refreshStrategy: .eagerFullScan
            ),
            availability: .available
        )
        source.providerID = JavaLocalFolderSourceAccess().accessorIdentifier
        source.edition = .java
        SourceRestoration.applyRestoredItemState(
            [item],
            lastScanDate: Date(timeIntervalSince1970: 1_000),
            snapshot: nil,
            to: &source
        )
        source.snapshot = SourceScanPolicy.buildSnapshot(for: source, scanRootURL: sourceURL)

        let record = PersistedSourceRecord(
            sourceID: source.id,
            folderURL: source.folderURL,
            origin: source.origin,
            accessDescriptor: source.accessDescriptor,
            availability: source.availability,
            bookmarkData: nil,
            displayName: source.displayName,
            rawItems: source.rawItems,
            snapshot: source.snapshot,
            lastScanDate: source.lastScanDate,
            needsRepair: false
        )

        let refreshReason = SourceRestoration.startupRefreshReason(
            for: source,
            persistedRecord: record
        ) { url, edition in
            switch edition {
            case .bedrock:
                return WorldScanner.collectionSnapshots(in: url)
            case .java:
                return JavaContentScanner.collectionSnapshots(in: url)
            }
        }

        #expect(refreshReason == nil)
        #expect(source.snapshot?.collectionSnapshots.first?.childDirectoryCount == 1)
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
        #expect(source.displayName == "John's iPhone")
    }

    @Test func connectedDeviceDiscoveryCachePolicyHonorsTransportSpecificTTL() async throws {
        let usbDevice = ConnectedDevice(
            udid: "usb-device",
            name: "USB Device",
            productType: nil,
            osVersion: nil,
            connection: .usb,
            trustState: .trusted
        )
        let networkDevice = ConnectedDevice(
            udid: "network-device",
            name: "Network Device",
            productType: nil,
            osVersion: nil,
            connection: .network,
            trustState: .trusted
        )
        let cache: [String: CachedConnectedDeviceDiscovery] = [
            usbDevice.udid: ConnectedDeviceDiscoveryCachePolicy.cacheDiscovery(
                for: usbDevice,
                containers: [],
                discoveryErrorDescription: nil,
                now: Date(timeIntervalSince1970: 100)
            ),
            networkDevice.udid: ConnectedDeviceDiscoveryCachePolicy.cacheDiscovery(
                for: networkDevice,
                containers: [],
                discoveryErrorDescription: nil,
                now: Date(timeIntervalSince1970: 100)
            )
        ]

        let usbFresh = ConnectedDeviceDiscoveryCachePolicy.cachedDiscovery(
            for: usbDevice,
            cache: cache,
            isActivelyScanning: false,
            now: Date(timeIntervalSince1970: 159)
        )
        let usbExpired = ConnectedDeviceDiscoveryCachePolicy.cachedDiscovery(
            for: usbDevice,
            cache: cache,
            isActivelyScanning: false,
            now: Date(timeIntervalSince1970: 161)
        )
        let networkFresh = ConnectedDeviceDiscoveryCachePolicy.cachedDiscovery(
            for: networkDevice,
            cache: cache,
            isActivelyScanning: false,
            now: Date(timeIntervalSince1970: 279)
        )
        let networkExpired = ConnectedDeviceDiscoveryCachePolicy.cachedDiscovery(
            for: networkDevice,
            cache: cache,
            isActivelyScanning: false,
            now: Date(timeIntervalSince1970: 281)
        )

        #expect(usbFresh != nil)
        #expect(usbExpired == nil)
        #expect(networkFresh != nil)
        #expect(networkExpired == nil)
    }

    @Test func connectedDeviceSourcePolicyDerivesAvailabilityAndPreferredName() async throws {
        #expect(ConnectedDeviceSourcePolicy.availability(for: .init(
            udid: "trusted",
            name: "John's iPhone",
            productType: nil,
            osVersion: nil,
            connection: .usb,
            trustState: .trusted
        ), hasMinecraftContainer: true) == .available)
        #expect(ConnectedDeviceSourcePolicy.availability(for: .init(
            udid: "locked",
            name: "John's iPhone",
            productType: nil,
            osVersion: nil,
            connection: .usb,
            trustState: .locked
        ), hasMinecraftContainer: true) == .limited)
        #expect(ConnectedDeviceSourcePolicy.availability(for: .init(
            udid: "missing",
            name: "John's iPhone",
            productType: nil,
            osVersion: nil,
            connection: .usb,
            trustState: .trusted
        ), hasMinecraftContainer: false) == .unavailable)

        #expect(ConnectedDeviceSourcePolicy.preferredDeviceName(
            currentName: "  John's iPad  ",
            fallbackDeviceName: "Backup Name",
            fallbackDisplayName: "Display Name • Minecraft"
        ) == "John's iPad")
        #expect(ConnectedDeviceSourcePolicy.preferredDeviceName(
            currentName: "Unknown Device",
            fallbackDeviceName: "  John's Switch  ",
            fallbackDisplayName: "Ignored • Minecraft"
        ) == "John's Switch")
        #expect(ConnectedDeviceSourcePolicy.preferredDeviceName(
            currentName: "Unknown Device",
            fallbackDeviceName: "",
            fallbackDisplayName: "Bedroom iPad • Minecraft"
        ) == "Bedroom iPad")
    }

    @Test func connectedDeviceSourcePolicyDetectsRefreshDebt() async throws {
        let device = ConnectedDevice(
            udid: "device",
            name: "Device",
            productType: nil,
            osVersion: nil,
            connection: .usb,
            trustState: .trusted
        )
        let container = DeviceAppContainer(
            deviceUDID: device.udid,
            appID: "com.mojang.minecraftpe",
            appName: "Minecraft",
            accessMode: .documents,
            minecraftFolderRelativePath: "Documents/games/com.mojang"
        )
        var source = ConnectedDeviceSourceFactory().makeSource(device: device, container: container)

        #expect(ConnectedDeviceSourcePolicy.hasRefreshDebt(source))

        source.rawItems = [
            MinecraftContentItem(
                folderURL: source.folderURL.appendingPathComponent("minecraftWorlds/WorldA", isDirectory: true),
                folderName: "WorldA",
                contentType: .world,
                collectionRootURL: source.folderURL.appendingPathComponent("minecraftWorlds", isDirectory: true)
            )
        ]
        source.previewLoadedCount = 1
        source.sizeLoadedCount = 1

        #expect(ConnectedDeviceSourcePolicy.hasRefreshDebt(source) == false)
    }

    @Test func scanNotificationServiceFormatsCompletionMessage() async throws {
        #expect(ScanNotificationService.completionMessage(itemCount: 0) == "No worlds or packs were found.")
        #expect(ScanNotificationService.completionMessage(itemCount: 1) == "Found 1 item.")
        #expect(ScanNotificationService.completionMessage(itemCount: 42) == "Found 42 items.")
    }

    @Test func scanNotificationServiceOnlyNotifiesForLongBackgroundScans() async throws {
        let service = ScanNotificationService()

        #expect(service.shouldNotifyAboutCompletedScan(duration: 2, isAppActive: false) == false)
        #expect(service.shouldNotifyAboutCompletedScan(duration: 8, isAppActive: true) == false)
        #expect(service.shouldNotifyAboutCompletedScan(duration: 8, isAppActive: false) == true)
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

private func makeArchive(from sourceDirectoryURL: URL, to archiveURL: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.currentDirectoryURL = sourceDirectoryURL
    process.arguments = [
        "-c",
        "-k",
        "--norsrc",
        ".",
        archiveURL.path
    ]

    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = outputPipe

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        throw ArchiveTestError.failedToCreateArchive(output)
    }
}

private enum ArchiveTestError: LocalizedError {
    case failedToCreateArchive(String)

    var errorDescription: String? {
        switch self {
        case .failedToCreateArchive(let output):
            return output.isEmpty ? "Failed to create test archive." : output
        }
    }
}

private func normalizedTestFileURLPath(_ url: URL?) -> String? {
    guard let path = url?.standardizedFileURL.path else {
        return nil
    }

    if path.count > 1, path.hasSuffix("/") {
        return String(path.dropLast())
    }

    return path
}

private enum SQLiteBinding {
    case text(String)
    case blob(Data)
}

private final class LockedRecorder<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []

    func append(_ value: Value) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var values: [Value] {
        lock.lock()
        let values = storage
        lock.unlock()
        return values
    }
}

private func withSQLiteDatabase(at url: URL, perform body: (OpaquePointer?) throws -> Void) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK else {
        defer { sqlite3_close(database) }
        throw NSError(domain: "TestSQLite", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open database."])
    }
    defer { sqlite3_close(database) }
    try body(database)
}

private func sqliteExec(_ sql: String, on database: OpaquePointer?, bindings: [SQLiteBinding] = []) throws {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
        throw NSError(domain: "TestSQLite", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare SQL statement."])
    }
    defer { sqlite3_finalize(statement) }

    let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    for (index, binding) in bindings.enumerated() {
        switch binding {
        case .text(let value):
            guard sqlite3_bind_text(statement, Int32(index + 1), value, -1, transientDestructor) == SQLITE_OK else {
                throw NSError(domain: "TestSQLite", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to bind text parameter."])
            }
        case .blob(let value):
            let result = value.withUnsafeBytes { rawBuffer in
                sqlite3_bind_blob(statement, Int32(index + 1), rawBuffer.baseAddress, Int32(value.count), transientDestructor)
            }
            guard result == SQLITE_OK else {
                throw NSError(domain: "TestSQLite", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to bind blob parameter."])
            }
        }
    }

    guard sqlite3_step(statement) == SQLITE_DONE else {
        throw NSError(domain: "TestSQLite", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to execute SQL statement."])
    }
}

private func jsonObject<T: Encodable>(for value: T) throws -> Any {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
}

private func appendLE<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
    var value = value.littleEndian
    withUnsafeBytes(of: &value) { bytes in
        data.append(contentsOf: bytes)
    }
}
