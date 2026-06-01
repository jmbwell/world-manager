// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct SourceDetailView: View {
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
                Text(source.displayName)
                    .font(.largeTitle.weight(.semibold))

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
            return SourcePresentation.availabilityDisplayText(for: source)
        }

        if let scanError = source.scanError, !scanError.isEmpty {
            return "Scan Failed"
        }

        if source.isScanning {
            return SourcePresentation.liveScanStatusTitle(for: source)
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

            if let cachedAvailabilityDetailText = SourcePresentation.cachedAvailabilityDetailText(for: source) {
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
                .appSectionTitleStyle(.section)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    if SourcePresentation.showsIndeterminateScanActivityIndicator(for: source) {
                        ProgressView()
                            .appActivityIndicatorStyle(.small)
                    } else if !source.isScanning {
                        sourceStatusIcon
                    }

                    Text(statusTitle)
                        .appTextStyle(.rowTitle)
                }

                if let statusDetail, !statusDetail.isEmpty {
                    Text(statusDetail)
                        .appTextStyle(.supporting)
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
            .appDetailSectionCard()
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
        [previewStageRow, sizeStageRow]
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
        let scanPhase = SourcePresentation.scanPhase(for: source)
        if previewsAreFullyLoaded || scanPhase == .sizing || scanPhase == .completed {
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
        switch SourcePresentation.scanPhase(for: source) {
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
                    .appTextStyle(.rowTitle)

                Spacer()

                Text(stage.detail)
                    .appTextStyle(.fieldLabel)
            }

            if stage.status == .completed {
                EmptyView()
            } else if stage.showsIndeterminateProgress {
                ProgressView()
                    .progressViewStyle(.linear)
                    .appActivityIndicatorStyle(.small)
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
                .appSectionTitleStyle(.section)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 16) {
                        Text(row.0)
                            .appTextStyle(.emphasisLabel)
                            .frame(width: 170, alignment: .leading)

                        Text(row.1)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .appDetailSectionCard()
        }
    }
}
