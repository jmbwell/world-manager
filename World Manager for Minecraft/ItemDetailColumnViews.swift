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
    let behaviorPacks: [ContentPackReference]
    let resourcePacks: [ContentPackReference]
    let worldsUsingPack: [MinecraftContentItem]
    let backingPackInstances: [MinecraftContentItem]
    let isSuspiciousPack: Bool
    let contents: [DirectoryPreviewEntry]
    let directoryPreviewLimit: Int
    let isEmpty: Bool
    let isPerformingItemAction: Bool
    let exportTitle: String?
    let exportAction: () -> Void
    let revealAction: () -> Void
    let shareAction: (NSView?) -> Void

    var body: some View {
        Group {
            if isEmpty {
//                Text("Add a source folder to start scanning your Minecraft library")
//                    .foregroundStyle(.secondary)
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
                    exportTitle: exportTitle,
                    exportAction: exportAction,
                    revealAction: revealAction,
                    shareAction: shareAction
                )
            } else {
                Text("Select a world or pack to see details")
                    .foregroundStyle(.secondary)
            }
        }
        .toolbar {
            if item != nil {
                ToolbarItemGroup {
                    Button(action: exportAction) {
                        Image(systemName: "arrow.down.circle")
                    }
                    .disabled(isPerformingItemAction)
                    .help(exportTitle ?? "Export")

                    Button(action: revealAction) {
                        Image(systemName: "folder")
                    }
                    .disabled(isPerformingItemAction)
                    .help("Reveal in Finder")

                    SharingPickerButton(
                        title: nil,
                        systemImage: "square.and.arrow.up",
                        isEnabled: !isPerformingItemAction
                    ) { anchorView in
                        shareAction(anchorView)
                    }
                    .help("Share")
                }
            }
        }
    }
}

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
    let contents: [DirectoryPreviewEntry]
    let directoryPreviewLimit: Int
    let isPerformingItemAction: Bool
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
                                        .font(.subheadline.weight(.semibold))

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
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    recordSection(title: "Technical Details") {
                        VStack(alignment: .leading, spacing: 14) {
                            detailRow(title: "Folder ID", value: item.folderID)
                            detailRow(title: "Type", value: item.contentType.rawValue)
                            detailRow(title: "Collection Folder", value: item.collectionRootURL.lastPathComponent)
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
            detailValueRow(title: "Created", value: createdDateText)

            if item.contentType == .world {
                detailValueRow(
                    title: "Pack References",
                    value: "\(behaviorPacks.count + resourcePacks.count)"
                )
            }

            if item.contentType == .behaviorPack || item.contentType == .resourcePack {
                detailValueRow(title: "UUID", value: item.packUUID ?? "Unavailable")
                detailValueRow(title: "Version", value: item.packVersion ?? "Unavailable")
            }
        }
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
        var highlights = [storageFormatLabel]
        if let approximateAgeText {
            highlights.append(approximateAgeText)
        }
        return highlights
    }

    private var heroMetadata: [String] {
        var chips = [item.contentType.rawValue, sizeText, "\(item.displayDateLabel) \(displayDateText)"]

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

    private var storageFormatLabel: String {
        switch item.contentType {
        case .world:
            return FileManager.default.fileExists(atPath: item.folderURL.appendingPathComponent("db", isDirectory: true).path)
                ? "LevelDB world storage"
                : "Flat-file world storage"
        case .behaviorPack, .resourcePack, .skinPack, .worldTemplate:
            return "Manifest-based package"
        }
    }

    private var createdDateText: String {
        (try? item.folderURL.resourceValues(forKeys: [.creationDateKey]).creationDate)?
            .formatted(date: .abbreviated, time: .omitted) ?? "Unknown"
    }

    private var approximateAgeText: String? {
        guard let createdDate = try? item.folderURL.resourceValues(forKeys: [.creationDateKey]).creationDate else {
            return nil
        }

        let components = Calendar.current.dateComponents([.year, .month], from: createdDate, to: .now)
        if let year = components.year, year > 0 {
            return year == 1 ? "About 1 year old" : "About \(year) years old"
        }
        if let month = components.month, month > 0 {
            return month == 1 ? "About 1 month old" : "About \(month) months old"
        }
        return "Recently created"
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
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    @ViewBuilder
    private func packSection(title: String, packs: [ContentPackReference]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

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
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func detailValueRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .lineLimit(3)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private var sizeText: String {
        if let sizeBytes = item.sizeBytes {
            return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
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
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        ActionPillButton(
            title: actionRowExportTitle,
            systemImage: "arrow.down.circle.fill",
            isDisabled: isPerformingItemAction,
            prominence: .primary,
            action: exportAction
        )

        ActionPillButton(
            title: "Reveal",
            systemImage: "folder.fill",
            isDisabled: isPerformingItemAction,
            prominence: .secondary,
            action: revealAction
        )

        SharingPillButton(
            title: "Share",
            systemImage: "square.and.arrow.up",
            isEnabled: !isPerformingItemAction,
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

struct ItemDetailColumnViews_Previews: PreviewProvider {
    static var previews: some View {
        ItemDetailColumnPreviewContainer()
    }
}
