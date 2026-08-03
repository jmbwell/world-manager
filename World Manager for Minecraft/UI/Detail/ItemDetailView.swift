// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI

struct ItemDetailView: View {
    private let detailContentMaxWidth: CGFloat = 760
    private let heroContentMaxWidth: CGFloat = 1080

    let item: MinecraftContentItem
    let source: MinecraftSource?
    let behaviorPacks: [ContentPackReference]
    let resourcePacks: [ContentPackReference]
    let worldsUsingPack: [MinecraftContentItem]
    let backingPackInstances: [MinecraftContentItem]
    let isSuspiciousPack: Bool
    let contents: [DirectoryEntry]
    let directoryPreviewLimit: Int
    let isPerformingItemAction: Bool
    let areFileActionsEnabled: Bool
    let exportTitle: String?
    let exportAction: () -> Void
    let revealAction: () -> Void
    let shareAction: (NSView?) -> Void
    @State private var storageBreakdown = StorageBreakdown.loading

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroSection

                VStack(alignment: .leading, spacing: 28) {
                    recordSection(title: "About") {
                        summaryGrid
                    }

                    if !worldSettingsRows.isEmpty {
                        recordSection(title: "World Settings") {
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(worldSettingsRows, id: \.title) { row in
                                    detailValueRow(title: row.title, value: row.value)
                                }
                            }
                        }
                    }

                    if let healthMessages, !healthMessages.isEmpty {
                        recordSection(title: "Compatibility") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(healthMessages, id: \.self) { message in
                                    Label(message, systemImage: "exclamationmark.triangle")
                                        .font(.subheadline)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }

                    if item.contentType == .world, !behaviorPacks.isEmpty || !resourcePacks.isEmpty || !relationshipHighlights.isEmpty {
                        recordSection(title: "Packs Used") {
                            VStack(alignment: .leading, spacing: 16) {
                                if !relationshipHighlights.isEmpty {
                                    summaryLines(relationshipHighlights)
                                }

                                if !behaviorPacks.isEmpty {
                                    packSection(title: "Behavior Packs", packs: behaviorPacks)
                                }

                                if !resourcePacks.isEmpty {
                                    packSection(title: "Resource Packs", packs: resourcePacks)
                                }
                            }
                        }
                    }

                    if (item.contentType == .behaviorPack || item.contentType == .resourcePack), !worldsUsingPack.isEmpty {
                        recordSection(title: "Used By Worlds") {
                            VStack(alignment: .leading, spacing: 14) {
                                summaryLines(packUsageHighlights)

                                ForEach(worldsUsingPack) { world in
                                    recordListRow(
                                        title: world.displayName,
                                        subtitle: worldUsageSecondaryText(for: world),
                                        iconURL: world.iconURL,
                                        fallbackSystemImage: "globe.europe.africa"
                                    )
                                }
                            }
                        }
                    }

                    if (item.contentType == .behaviorPack || item.contentType == .resourcePack), !backingPackInstances.isEmpty {
                        recordSection(title: "Pack Instances") {
                            VStack(alignment: .leading, spacing: 14) {
                                summaryLines(instanceHighlights)

                                ForEach(backingPackInstances) { instance in
                                    recordListRow(
                                        title: instance.folderName,
                                        subtitle: packInstanceSecondaryText(for: instance),
                                        iconURL: instance.iconURL,
                                        fallbackSystemImage: fallbackIconName
                                    )
                                }
                            }
                        }
                    }

                    recordSection(title: "Storage") {
                        VStack(alignment: .leading, spacing: 14) {
                            if !storageHighlights.isEmpty {
                                summaryLines(storageHighlights)
                            }

                            detailValueRow(title: "Primary Data", value: storageBreakdown.primaryDataText)
                            detailValueRow(title: "Resources", value: storageBreakdown.resourcesText)
                            detailValueRow(title: "Metadata", value: storageBreakdown.metadataText)
                            detailValueRow(title: "Artwork", value: item.iconURL == nil ? "No icon found" : "Thumbnail found")
                        }
                    }

                    recordSection(title: "Locations") {
                        VStack(alignment: .leading, spacing: 14) {
                            detailRow(title: "Source Library", value: source?.displayName ?? item.collectionRootURL.deletingLastPathComponent().lastPathComponent)
                            detailRow(title: "Record Path", value: item.folderURL.path)
                            detailRow(title: "Collection Root", value: item.collectionRootURL.path)
                        }
                    }

                    recordSection(title: "Activity") {
                        VStack(alignment: .leading, spacing: 14) {
                            detailValueRow(title: "Indexed", value: source?.lastScanDate?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown")
                            detailValueRow(title: "Visible Items", value: visibleContentsCountText)

                            if !contents.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Recent Folder Contents")
                                        .appTextStyle(.rowTitle)

                                    ForEach(contents) { entry in
                                        HStack(spacing: 10) {
                                            Image(systemName: entry.isDirectory ? "folder.fill" : "doc.text")
                                                .foregroundStyle(.secondary)
                                            Text(entry.name)
                                                .lineLimit(1)
                                            Spacer()
                                        }
                                    }

                                    if contents.count == directoryPreviewLimit {
                                        Text("Showing the first \(directoryPreviewLimit) items")
                                            .appTextStyle(.fieldLabel)
                                    }
                                }
                            }
                        }
                    }

                    recordSection(title: "Technical Details") {
                        VStack(alignment: .leading, spacing: 14) {
                            detailRow(title: "Folder ID", value: item.folderID)
                            detailRow(title: "Type", value: item.platformType.displayName)
                            detailRow(title: "Collection Folder", value: item.collectionRootURL.lastPathComponent)
                            if let spawn = item.worldMetadata?.spawn {
                                detailValueRow(title: "Spawn", value: spawn)
                            }
                            if let storageVersion = item.worldMetadata?.storageVersion {
                                detailValueRow(title: "Storage Version", value: storageVersion)
                            }
                            if let networkVersion = item.worldMetadata?.networkVersion {
                                detailValueRow(title: "Network Version", value: networkVersion)
                            }
                        }
                    }
                }
                .frame(maxWidth: detailContentMaxWidth, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: item.id) {
            storageBreakdown = await loadStorageBreakdown(for: item)
        }
    }

    private var heroSection: some View {
        RecordHeroView(
            item: item,
            metadataChips: heroMetadata,
            fallbackSystemImage: fallbackIconName,
            copyAction: {
                copyToPasteboard(item.displayName)
            },
            actionRow: AnyView(actionRow),
            contentMaxWidth: heroContentMaxWidth
        )
    }

    private var actionRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                actionButtons
            }

            VStack(alignment: .leading, spacing: 10) {
                actionButtons
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            detailRow(title: "Name", value: item.displayName)
            detailValueRow(title: "Size", value: sizeText)
            detailValueRow(title: item.displayDateLabel, value: displayDateText)
            detailValueRow(title: "Created", value: fileFacts.createdDateText)

            if let gameMode = item.worldMetadata?.gameMode {
                detailValueRow(title: "Game Mode", value: gameMode)
            }

            if let difficulty = item.worldMetadata?.difficulty {
                detailValueRow(title: "Difficulty", value: difficulty)
            }

            if let seed = item.worldMetadata?.seed {
                detailValueRow(title: "Seed", value: seed)
            }

            if let lastOpenedWithVersion = item.worldMetadata?.lastOpenedWithVersion {
                detailValueRow(title: "Last Opened With", value: lastOpenedWithVersion)
            }

            if let inventoryVersion = item.worldMetadata?.inventoryVersion {
                detailValueRow(title: "Inventory Version", value: inventoryVersion)
            }

            if item.contentType == .world {
                detailValueRow(
                    title: "Pack References",
                    value: "\(behaviorPacks.count + resourcePacks.count)"
                )
            }

            if item.sourceEdition == .bedrock && (item.contentType == .behaviorPack || item.contentType == .resourcePack) {
                detailValueRow(title: "UUID", value: item.packUUID ?? "Unavailable")
                detailValueRow(title: "Version", value: item.packVersion ?? "Unavailable")
                if let minimumEngineVersion = item.packMetadataDetails?.minimumEngineVersion {
                    detailValueRow(title: "Minimum Engine", value: minimumEngineVersion)
                }
            }

            if let javaPackMetadata {
                if let description = javaPackMetadata.description {
                    detailRow(title: javaModMetadata == nil ? "Description" : "Pack Description", value: description)
                }
                if let packFormat = javaPackMetadata.packFormat {
                    detailValueRow(title: "Pack Format", value: String(packFormat))
                }
                if let supportedFormats = javaPackMetadata.supportedFormats {
                    detailValueRow(title: "Supported Formats", value: supportedFormats)
                }
            }

            if let javaModMetadata {
                if let modID = javaModMetadata.modID {
                    detailValueRow(title: "Mod ID", value: modID)
                }
                if let version = javaModMetadata.version {
                    detailValueRow(title: "Mod Version", value: version)
                }
                if let description = javaModMetadata.description {
                    detailRow(title: "Mod Description", value: description)
                }
                if !javaModMetadata.authors.isEmpty {
                    detailValueRow(title: "Authors", value: javaModMetadata.authors.joined(separator: ", "))
                }
                if let license = javaModMetadata.license {
                    detailValueRow(title: "License", value: license)
                }
                if let environment = javaModMetadata.environment {
                    detailValueRow(title: "Environment", value: environment)
                }
                if let minecraftRequirement = javaModMetadata.minecraftVersionRequirement {
                    detailValueRow(title: "Minecraft", value: minecraftRequirement)
                }
            }
        }
    }

    private var worldSettingsRows: [(title: String, value: String)] {
        guard let metadata = item.worldMetadata else {
            return []
        }

        return [
            booleanRow("Cheats Enabled", metadata.cheatsEnabled),
            booleanRow("Commands Enabled", metadata.commandsEnabled),
            booleanRow("Education Features", metadata.educationFeaturesEnabled),
            booleanRow("Coordinates Shown", metadata.coordinatesShown),
            booleanRow("Keep Inventory", metadata.keepInventory),
            booleanRow("Mob Griefing", metadata.mobGriefingEnabled),
            booleanRow("Daylight Cycle", metadata.daylightCycleEnabled),
            booleanRow("Weather Cycle", metadata.weatherCycleEnabled)
        ].compactMap { $0 }
    }

    private var healthMessages: [String]? {
        var messages: [String] = []

        if isSuspiciousPack {
            messages.append("Manifest UUID is missing or unreadable for this pack, so matching is using a weaker fallback identity.")
        }

        if let unresolvedCount, unresolvedCount > 0 {
            messages.append("\(unresolvedCount) referenced pack\(unresolvedCount == 1 ? "" : "s") could not be matched in this library.")
        }

        return messages.isEmpty ? nil : messages
    }

    private var relationshipHighlights: [String] {
        guard item.contentType == .world else {
            return []
        }

        var highlights: [String] = []
        let totalPackCount = behaviorPacks.count + resourcePacks.count
        if totalPackCount > 0 {
            highlights.append("Uses \(totalPackCount) pack\(totalPackCount == 1 ? "" : "s")")
        }

        if let resolvedCount {
            highlights.append("\(resolvedCount) found in this library")
        }

        if let unresolvedCount, unresolvedCount > 0 {
            highlights.append("\(unresolvedCount) unresolved")
        }

        let relatedWorldCount = otherWorldsSharingReferencedPacks
        if relatedWorldCount > 0 {
            highlights.append("Shared by \(relatedWorldCount) other world\(relatedWorldCount == 1 ? "" : "s")")
        }

        return highlights
    }

    private var packUsageHighlights: [String] {
        [
            "\(worldsUsingPack.count) world\(worldsUsingPack.count == 1 ? "" : "s") use this",
            backingPackInstances.count > 1 ? "\(backingPackInstances.count) copies indexed" : "1 indexed copy"
        ]
    }

    private var instanceHighlights: [String] {
        let embeddedCount = backingPackInstances.filter {
            $0.folderURL.pathComponents.contains(MinecraftContentType.world.collectionFolderName)
        }.count
        let topLevelCount = backingPackInstances.count - embeddedCount

        var highlights: [String] = []
        if topLevelCount > 0 {
            highlights.append("\(topLevelCount) library cop\(topLevelCount == 1 ? "y" : "ies")")
        }
        if embeddedCount > 0 {
            highlights.append("\(embeddedCount) embedded in worlds")
        }
        return highlights
    }

    private var storageHighlights: [String] {
        var highlights = [fileFacts.storageFormatLabel]
        if let approximateAgeText = fileFacts.approximateAgeText {
            highlights.append(approximateAgeText)
        }
        return highlights
    }

    private var heroMetadata: [String] {
        var chips = [item.platformType.displayName, sizeText, "\(item.displayDateLabel) \(displayDateText)"]

        if let modID = javaModMetadata?.modID {
            chips.append(modID)
        } else if let packFormat = javaPackMetadata?.packFormat {
            chips.append("Format \(packFormat)")
        }

        if item.contentType == .world {
            let packCount = behaviorPacks.count + resourcePacks.count
            if packCount > 0 {
                chips.append("\(packCount) pack\(packCount == 1 ? "" : "s")")
            }
        }

        return chips
    }

    private var unresolvedCount: Int? {
        source?.logicalWorld(forItemID: item.id)?.unresolvedReferences.count
    }

    private var resolvedCount: Int? {
        guard let logicalWorld = source?.logicalWorld(forItemID: item.id) else {
            return nil
        }

        return logicalWorld.usedPackIDs.count
    }

    private var otherWorldsSharingReferencedPacks: Int {
        guard
            let source,
            let logicalWorld = source.logicalWorld(forItemID: item.id)
        else {
            return 0
        }

        let relatedWorldIDs = Set(logicalWorld.usedPackIDs.flatMap { packID in
            source.worldsUsingPack(packID).map(\.id)
        })

        return max(0, relatedWorldIDs.subtracting([item.id]).count)
    }

    private var javaPackMetadata: JavaPackMetadata? {
        if case .java(let metadata) = item.platformMetadata {
            return metadata.pack
        }

        return nil
    }

    private var javaModMetadata: JavaModMetadata? {
        if case .java(let metadata) = item.platformMetadata {
            return metadata.mod
        }

        return nil
    }

    private var actionRowExportTitle: String {
        if exportTitle != nil {
            switch item.contentType {
            case .world:
                return "Export World"
            case .behaviorPack, .resourcePack, .skinPack:
                return "Export Pack"
            case .worldTemplate:
                return "Export Template"
            }
        }

        return "Export"
    }

    private var fallbackIconName: String {
        switch item.contentType {
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

    private var fileFacts: ContentItemFileFacts {
        ContentItemFileFacts(item: item)
    }

    private var visibleContentsCountText: String {
        if contents.isEmpty {
            return "No visible files or folders"
        }

        return "\(contents.count)\(contents.count == directoryPreviewLimit ? "+" : "") visible entries"
    }

    private func recordSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .appSectionTitleStyle(.section)

            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .appDetailSectionCard()
        }
    }

    @ViewBuilder
    private func packSection(title: String, packs: [ContentPackReference]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .appTextStyle(.rowTitle)

            ForEach(packs) { pack in
                recordListRow(
                    title: pack.name,
                    subtitle: packSecondaryText(pack),
                    iconURL: pack.iconURL,
                    fallbackSystemImage: pack.type == .resourcePack ? "paintpalette" : "shippingbox"
                )
            }
        }
    }

    @ViewBuilder
    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(title)
                .appTextStyle(.emphasisLabel)
                .frame(width: 170, alignment: .leading)

            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func detailValueRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .appTextStyle(.emphasisLabel)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .lineLimit(3)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func booleanRow(_ title: String, _ value: Bool?) -> (title: String, value: String)? {
        guard let value else {
            return nil
        }

        return (title, value ? "Yes" : "No")
    }

    private var sizeText: String {
        if let sizeBytes = item.sizeBytes {
            return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
        }

        if item.sizeLoaded {
            return "Unavailable"
        }

        return item.metadataLoaded ? "Calculating..." : "Loading..."
    }

    private var displayDateText: String {
        item.displayDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Unknown"
    }

    private func packSecondaryText(_ pack: ContentPackReference) -> String? {
        let components = [pack.version.map { "v\($0)" }, pack.uuid]
            .compactMap { $0 }
        return components.isEmpty ? nil : components.joined(separator: " • ")
    }

    private func worldUsageSecondaryText(for world: MinecraftContentItem) -> String {
        let dateText = world.displayDate?.formatted(date: .abbreviated, time: .omitted) ?? "Date unavailable"
        return "\(world.displayDateLabel) \(dateText)"
    }

    private func packInstanceSecondaryText(for instance: MinecraftContentItem) -> String {
        if instance.folderURL.pathComponents.contains(MinecraftContentType.world.collectionFolderName) {
            return "Embedded in world copy"
        }

        return "Top-level pack folder"
    }

    private func summaryLines(_ values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(values, id: \.self) { value in
                Label(value, systemImage: "checkmark.circle")
                    .appTextStyle(.supporting)
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        ActionPillButton(
            title: actionRowExportTitle,
            systemImage: "arrow.down.circle.fill",
            isDisabled: isPerformingItemAction || !areFileActionsEnabled,
            prominence: .primary,
            action: exportAction
        )

        ActionPillButton(
            title: "Reveal",
            systemImage: "folder.fill",
            isDisabled: isPerformingItemAction || !areFileActionsEnabled,
            prominence: .secondary,
            action: revealAction
        )

        SharingPillButton(
            title: "Share",
            systemImage: "square.and.arrow.up",
            isEnabled: !isPerformingItemAction && areFileActionsEnabled,
            action: shareAction
        )
    }

    @ViewBuilder
    private func recordListRow(
        title: String,
        subtitle: String?,
        iconURL: URL?,
        fallbackSystemImage: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            PackReferenceIconView(iconURL: iconURL, fallbackSystemImage: fallbackSystemImage)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(2)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .appTextStyle(.fieldLabel)
                        .lineLimit(3)
                }
            }
        }
    }

    private func loadStorageBreakdown(for item: MinecraftContentItem) async -> StorageBreakdown {
        await Task.detached(priority: .utility) {
            StorageBreakdown.build(for: item)
        }.value
    }
}
