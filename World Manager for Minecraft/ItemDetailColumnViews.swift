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

private struct SourceDetailView: View {
    private enum StageStatus {
        case pending
        case inProgress
        case completed
    }

    private struct StageRow: Identifiable {
        let id: String
        let title: String
        let detail: String
        let status: StageStatus
        let progress: Double?
        let showsIndeterminateProgress: Bool
    }

    let source: MinecraftSource

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(source.displayName)
                        .font(.largeTitle.weight(.semibold))

                    Text(sourceSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if showsStatusSection {
                    sourceStatusSection
                }

                sourceSection(title: "Overview", rows: overviewRows)
                sourceSection(title: "Contents", rows: contentRows)
                sourceSection(title: "Location", rows: locationRows)

                if !technicalRows.isEmpty {
                    sourceSection(title: "Technical Details", rows: technicalRows)
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(28)
        }
    }

    private var sourceSummary: String {
        switch source.origin {
        case .localFolder:
            return "Local filesystem source"
        case .connectedDevice(let device, let container):
            return "\(device.name) • \(container.appName)"
        }
    }

    private var showsStatusSection: Bool {
        if source.isScanning || source.scanError != nil || source.availability != .available {
            return true
        }

        guard !source.scanStatus.isEmpty else {
            return false
        }

        if source.scanStatus == "No Minecraft items found." {
            return false
        }

        if source.scanStatus.hasPrefix("Loaded ") {
            return false
        }

        return true
    }

    private var statusTitle: String {
        if !source.isScanning, source.availability != .available {
            return source.availabilityDisplayText
        }

        if let scanError = source.scanError, !scanError.isEmpty {
            return "Scan Failed"
        }

        if source.isScanning {
            return source.liveScanStatusTitle
        }

        if !source.scanStatus.isEmpty {
            return source.scanStatus
        }

        return "Scanning Minecraft library..."
    }

    private var statusDetail: String? {
        if !source.isScanning, source.availability != .available {
            if let scanDiagnostic = source.scanDiagnostic, !scanDiagnostic.isEmpty {
                return scanDiagnostic
            }

            if let cachedAvailabilityDetailText = source.cachedAvailabilityDetailText {
                return cachedAvailabilityDetailText
            }

            if let lastScanDate = source.lastScanDate {
                return "Cached from \(lastScanDate.formatted(date: .abbreviated, time: .shortened))"
            }

            return nil
        }

        if let scanError = source.scanError, !scanError.isEmpty {
            return scanError
        }

        if let diagnostic = source.scanDiagnostic, !diagnostic.isEmpty {
            return diagnostic
        }

        if source.isScanning {
            return nil
        }

        return "\(source.indexedDetailCount) of \(source.indexedItemCount) indexed"
    }

    @ViewBuilder
    private var sourceStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Status")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    if source.showsIndeterminateScanActivityIndicator {
                        ProgressView()
                            .controlSize(.small)
                    } else if !source.isScanning {
                        sourceStatusIcon
                    }

                    Text(statusTitle)
                        .font(.subheadline.weight(.semibold))
                }

                if let statusDetail, !statusDetail.isEmpty {
                    Text(statusDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if source.isScanning {
                    Divider()
                        .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(stageRows) { stage in
                            sourceStageRow(stage)
                        }
                    }
                }
            }
            .padding(18)
            .appCardSurface(.primaryPanel)
        }
    }

    @ViewBuilder
    private var sourceStatusIcon: some View {
        if source.availability == .limited {
            Image(systemName: "lock.circle.fill")
                .foregroundStyle(Color.appAccent)
        } else if source.availability != .available {
            Image(systemName: source.isOfflineCached ? "externaldrive.badge.exclamationmark" : "slash.circle")
                .foregroundStyle(.secondary)
        } else if source.scanError != nil {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
    }

    private var overviewRows: [(String, String)] {
        var rows: [(String, String)] = [
            ("Type", sourceTypeLabel),
            ("Availability", availabilityLabel)
        ]

        if let lastScanDate = source.lastScanDate {
            rows.append(("Last Successful Scan", lastScanDate.formatted(date: .abbreviated, time: .shortened)))
        }

        switch source.origin {
        case .localFolder:
            break
        case .connectedDevice(let device, let container):
            rows.append(("Connection", device.connection == .network ? "Network" : "USB"))
            rows.append(("App Container", container.appName))
            if let osVersion = device.osVersion, !osVersion.isEmpty {
                rows.append(("OS Version", osVersion))
            }
        }

        return rows
    }

    private var contentRows: [(String, String)] {
        [
            ("Total Items", source.items.count.formatted(.number)),
            ("Worlds", itemCount(for: .world).formatted(.number)),
            ("Behavior Packs", itemCount(for: .behaviorPack).formatted(.number)),
            ("Resource Packs", itemCount(for: .resourcePack).formatted(.number)),
            ("Skin Packs", itemCount(for: .skinPack).formatted(.number)),
            ("World Templates", itemCount(for: .worldTemplate).formatted(.number))
        ]
    }

    private var locationRows: [(String, String)] {
        switch source.origin {
        case .localFolder:
            return [("Filesystem Path", source.folderURL.path)]
        case .connectedDevice(_, let container):
            var rows: [(String, String)] = [
                ("Source Identifier", source.folderURL.absoluteString)
            ]
            if let relativePath = container.minecraftFolderRelativePath, !relativePath.isEmpty {
                rows.append(("Minecraft Path", relativePath))
            }
            return rows
        }
    }

    private var technicalRows: [(String, String)] {
        switch source.origin {
        case .localFolder:
            return []
        case .connectedDevice(let device, let container):
            var rows: [(String, String)] = [
                ("UDID", device.udid),
                ("App ID", container.appID),
                ("Access Mode", container.accessMode.rawValue)
            ]
            if let productType = device.productType, !productType.isEmpty {
                rows.append(("Product Type", productType))
            }
            rows.append(("Trust State", device.trustState.rawValue.capitalized))
            return rows
        }
    }

    private var sourceTypeLabel: String {
        switch source.origin {
        case .localFolder:
            return "Local Folder"
        case .connectedDevice:
            return "Connected Device"
        }
    }

    private var availabilityLabel: String {
        switch source.availability {
        case .unknown:
            return "Unknown"
        case .available:
            return "Available"
        case .disconnected:
            return "Disconnected"
        case .limited:
            return "Limited"
        case .unavailable:
            return "Unavailable"
        }
    }

    private var stageRows: [StageRow] {
        [
            previewStageRow,
            sizeStageRow
        ]
    }

    private var previewStageRow: StageRow {
        let total = source.indexedItemCount
        let progress = total > 0 ? min(Double(source.previewLoadedCount) / Double(total), 1) : 0
        let hasPreviewWorkStarted = source.previewLoadedCount > 0 || source.scanStatus.contains("Loading previews")
        let previewsAreFullyLoaded = total > 0 && source.previewLoadedCount >= total
        let shouldShowIndeterminatePreviewProgress = hasPreviewWorkStarted
            && source.isScanning
            && (source.scanProgress ?? 0) < 0.65

        let status: StageStatus
        if previewsAreFullyLoaded || source.scanPhase == .sizing || source.scanPhase == .completed {
            status = .completed
        } else if hasPreviewWorkStarted {
            status = .inProgress
        } else {
            status = .pending
        }

        let detail: String
        switch status {
        case .completed:
            detail = finishedStageDetail(duration: source.previewStageDuration ?? source.previewStageElapsed)
        case .inProgress:
            detail = stageProgressDetail(
                completed: source.previewLoadedCount,
                total: total,
                unit: "previews loaded",
                elapsed: source.previewStageElapsed
            )
        case .pending:
            detail = "Waiting for discovery to finish"
        }

        return StageRow(
            id: "previews",
            title: "Previews",
            detail: detail,
            status: status,
            progress: status == .completed ? 1 : progress,
            showsIndeterminateProgress: shouldShowIndeterminatePreviewProgress
        )
    }

    private var sizeStageRow: StageRow {
        let total = source.indexedItemCount
        let progress = total > 0 ? min(Double(source.sizeLoadedCount) / Double(total), 1) : 0
        let previewsAreFullyLoaded = total > 0 && source.previewLoadedCount >= total

        let status: StageStatus
        switch source.scanPhase {
        case .sizing:
            status = .inProgress
        case .completed:
            status = .completed
        case .discovering, .metadata, .previews, .idle:
            status = .pending
        }

        let detail: String
        switch status {
        case .completed:
            detail = finishedStageDetail(duration: source.sizeStageDuration)
        case .inProgress:
            detail = stageProgressDetail(
                completed: source.sizeLoadedCount,
                total: total,
                unit: "sizes calculated",
                elapsed: source.sizeStageElapsed
            )
        case .pending:
            detail = previewsAreFullyLoaded
                ? "Preparing size calculations..."
                : "Waiting for previews to finish loading"
        }

        return StageRow(
            id: "sizes",
            title: "Sizes",
            detail: detail,
            status: status,
            progress: status == .completed ? 1 : progress,
            showsIndeterminateProgress: false
        )
    }

    @ViewBuilder
    private func sourceStageRow(_ stage: StageRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: stageIconName(for: stage.status))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(stageIconColor(for: stage.status))
                    .frame(width: 14)

                Text(stage.title)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(stage.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if stage.status == .completed {
                EmptyView()
            } else if stage.showsIndeterminateProgress {
                ProgressView()
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                    .tint(Color.appAccent)
            } else if let progress = stage.progress {
                ProgressView(value: progress, total: 1)
                    .tint(stage.status == .pending ? .secondary.opacity(0.35) : Color.appAccent)
                    .opacity(stage.status == .pending ? 0.55 : 1)
            }
        }
    }

    private func stageIconName(for status: StageStatus) -> String {
        switch status {
        case .pending:
            return "circle"
        case .inProgress:
            return "clock"
        case .completed:
            return "checkmark.circle.fill"
        }
    }

    private func stageIconColor(for status: StageStatus) -> Color {
        switch status {
        case .pending:
            return .secondary.opacity(0.7)
        case .inProgress:
            return Color.appAccent
        case .completed:
            return .green
        }
    }

    private func stageProgressDetail(
        completed: Int,
        total: Int,
        unit: String,
        elapsed: TimeInterval?
    ) -> String {
        guard total > 0 else {
            return "Starting..."
        }

        var detail = "\(completed) of \(total) \(unit)"

        if let remainingEstimate = estimateRemainingTime(
            completed: completed,
            total: total,
            elapsed: elapsed
        ) {
            detail += " • about \(friendlyDuration(remainingEstimate)) left"
        }

        return detail
    }

    private func finishedStageDetail(duration: TimeInterval?) -> String {
        guard let duration else {
            return "Finished"
        }

        return "Finished in \(friendlyDuration(duration))"
    }

    private func estimateRemainingTime(
        completed: Int,
        total: Int,
        elapsed: TimeInterval?
    ) -> TimeInterval? {
        guard
            let elapsed,
            elapsed >= 10,
            completed >= 10,
            total > 0,
            completed < total
        else {
            return nil
        }

        let completionFraction = Double(completed) / Double(total)
        guard completionFraction >= 0.05 else {
            return nil
        }

        let secondsPerItem = elapsed / Double(completed)
        let remaining = max(Double(total - completed) * secondsPerItem, 1)
        guard remaining >= 60 else {
            return nil
        }

        return remaining
    }

    private func friendlyDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = duration >= 3600 ? 2 : 1
        formatter.allowedUnits = duration >= 3600 ? [.hour, .minute] : duration >= 60 ? [.minute] : [.second]
        formatter.includesApproximationPhrase = false
        formatter.includesTimeRemainingPhrase = false
        return formatter.string(from: duration) ?? "a moment"
    }

    private func itemCount(for type: MinecraftContentType) -> Int {
        source.items.filter { $0.contentType == type }.count
    }

    @ViewBuilder
    private func sourceSection(title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 16) {
                        Text(row.0)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 170, alignment: .leading)

                        Text(row.1)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(18)
            .appCardSurface(.primaryPanel)
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
            detailValueRow(title: "Created", value: createdDateText)

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

            if item.contentType == .behaviorPack || item.contentType == .resourcePack {
                detailValueRow(title: "UUID", value: item.packUUID ?? "Unavailable")
                detailValueRow(title: "Version", value: item.packVersion ?? "Unavailable")
                if let minimumEngineVersion = item.packMetadataDetails?.minimumEngineVersion {
                    detailValueRow(title: "Minimum Engine", value: minimumEngineVersion)
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
            .appCardSurface(.secondaryPanel)
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

#if DEBUG
struct ItemDetailColumnViews_Previews: PreviewProvider {
    static var previews: some View {
        ItemDetailColumnPreviewContainer()
    }
}
#endif
