// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

enum SidebarSelection: Hashable, Sendable {
    case source(sourceID: URL)
    case sourceCandidate(candidateID: String)
    case connectedDevice(deviceID: String)
    case allContent(sourceID: URL)
    case contentType(sourceID: URL, contentType: MinecraftContentType)
    case contentKind(sourceID: URL, contentKind: MinecraftContentKind)

    var sourceID: URL? {
        switch self {
        case .source(let sourceID), .allContent(let sourceID), .contentType(let sourceID, _), .contentKind(let sourceID, _):
            return sourceID
        case .sourceCandidate, .connectedDevice:
            return nil
        }
    }
}

struct SidebarFilter: Identifiable, Hashable {
    var id: SidebarSelection { selection }
    let title: String
    let iconName: String
    let count: Int
    let selection: SidebarSelection
}

private struct SidebarNode: Identifiable, Hashable {
    let id: SidebarSelection
    let row: SidebarNodeRow
    let children: [SidebarNode]?

    var selection: SidebarSelection { id }
}

private enum SidebarNodeRow: Hashable {
    case source(MinecraftSource)
    case filter(SidebarFilter)
    case connectedDevice(ConnectedDeviceSidebarEntry)
    case sourceCandidate(SourceCandidate)
}

struct SourcesSidebarView: View {
    let sources: [MinecraftSource]
    let connectedDevices: [ConnectedDeviceSidebarEntry]
    let sourceCandidates: [SourceCandidate]
    let isDiscoveringSourceCandidates: Bool
    @Binding var selection: SidebarSelection?
    let addSourceAction: () -> Void
    let discoverSourcesAction: () -> Void
    let addCandidateSourceAction: (SourceCandidate) -> Void
    let addDeviceSourceAction: () -> Void
    let addConnectedDeviceAction: (ConnectedDeviceSidebarEntry) -> Void
    let rescanSourceAction: (MinecraftSource) -> Void
    let removeSourceAction: (MinecraftSource) -> Void
    let filters: (MinecraftSource) -> [SidebarFilter]

    var body: some View {
        List(selection: $selection) {
            if !libraryNodes.isEmpty {
                Section {
                    OutlineGroup(libraryNodes, children: \.children, content: sidebarNodeRow)
                } header: {
                    SidebarSourcesSectionHeaderView(title: "Libraries")
                }
            }

            if !deviceNodes.isEmpty {
                Section {
                    OutlineGroup(deviceNodes, children: \.children, content: sidebarNodeRow)
                } header: {
                    SidebarSourcesSectionHeaderView(title: "Available Devices")
                }
            }

            if !candidateNodes.isEmpty {
                Section {
                    OutlineGroup(candidateNodes, children: \.children, content: sidebarNodeRow)
                } header: {
                    SidebarSourcesSectionHeaderView(title: "Found Sources")
                }
            }
        }
        .listStyle(.sidebar)
        .transaction { transaction in
            transaction.animation = nil
        }
        .toolbar {
            ToolbarItem {
                Button(action: discoverSourcesAction) {
                    if isDiscoveringSourceCandidates {
                        ProgressView()
                            .appActivityIndicatorStyle(.small)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                }
                .disabled(isDiscoveringSourceCandidates)
                .help("Find Minecraft Sources")
            }

            ToolbarItem {
                Button(action: addSourceAction) {
                    Image(systemName: "folder.badge.plus")
                }
                .help("Add Source Folder")
            }

            ToolbarItem {
                Button(action: addDeviceSourceAction) {
                    Image(systemName: "iphone.gen3")
                }
                .help("Add Connected Device Source")
            }
        }
    }

    private var libraryNodes: [SidebarNode] {
        sources.map { source in
            let childNodes = filters(source).map { filter in
                SidebarNode(
                    id: filter.selection,
                    row: .filter(filter),
                    children: nil
                )
            }

            return SidebarNode(
                id: .source(sourceID: source.id),
                row: .source(source),
                children: childNodes.isEmpty ? nil : childNodes
            )
        }
    }

    private var deviceNodes: [SidebarNode] {
        connectedDevices.map { entry in
            SidebarNode(
                id: .connectedDevice(deviceID: entry.id),
                row: .connectedDevice(entry),
                children: nil
            )
        }
    }

    private var candidateNodes: [SidebarNode] {
        sourceCandidates.map { candidate in
            SidebarNode(
                id: .sourceCandidate(candidateID: candidate.id),
                row: .sourceCandidate(candidate),
                children: nil
            )
        }
    }

    @ViewBuilder
    private func sidebarNodeRow(_ node: SidebarNode) -> some View {
        switch node.row {
        case .source(let source):
            SourceHeaderRow(source: source, isSelected: selection == node.selection)
                .tag(node.selection as SidebarSelection?)
                .listRowSeparator(.hidden)
                .contextMenu {
                    Button("Rescan \"\(source.displayName)\"") {
                        rescanSourceAction(source)
                    }

                    Divider()

                    Button("Remove \"\(source.displayName)\"", role: .destructive) {
                        removeSourceAction(source)
                    }
                }
        case .filter(let filter):
            SidebarFilterRow(filter: filter)
                .tag(node.selection as SidebarSelection?)
        case .connectedDevice(let entry):
            ConnectedDeviceRow(
                entry: entry,
                addAction: entry.hasMinecraftContainer ? {
                    addConnectedDeviceAction(entry)
                } : nil
            )
            .tag(node.selection as SidebarSelection?)
            .listRowSeparator(.hidden)
        case .sourceCandidate(let candidate):
            SourceCandidateRow(
                candidate: candidate,
                addAction: {
                    addCandidateSourceAction(candidate)
                }
            )
            .tag(node.selection as SidebarSelection?)
            .listRowSeparator(.hidden)
        }
    }
}

private struct SourceCandidateRow: View {
    let candidate: SourceCandidate
    let addAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.displayName)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } icon: {
                Image(systemName: symbolName)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button(action: addAction) {
                Text("Add")
            }
            .appMiniProminentButton()
            .help("Add Source")
        }
        .padding(.vertical, 4)
    }

    private var symbolName: String {
        switch candidate.edition {
        case .bedrock:
            return "folder"
        case .java:
            return "curlybraces"
        }
    }

    private var subtitle: String {
        let editionName = candidate.edition == .java ? "Java" : "Bedrock"
        return "\(editionName) - \(candidate.sourceRootURL.lastPathComponent)"
    }
}

private struct SidebarFilterRow: View {
    let filter: SidebarFilter

    var body: some View {
        HStack {
            Label {
                Text(filter.title)
            } icon: {
                Image(systemName: filter.iconName)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(filter.count, format: .number)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SidebarSourcesSectionHeaderView: View {
    let title: String

    var body: some View {
        Text(title)
    }
}

private struct SourceHeaderRow: View {
    let source: MinecraftSource
    let isSelected: Bool

    var body: some View {
        HStack {
            Label {
                Text(source.displayName)
                    .lineLimit(1)
            } icon: {
                Image(systemName: headerSymbolName)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if let availabilityBadgeText {
                    SourceAvailabilityBadge(
                        text: availabilityBadgeText,
                        emphasis: availabilityBadgeEmphasis,
                        isSelected: isSelected
                    )
                }

                if let connection {
                    SourceConnectionBadge(connection: connection, isSelected: isSelected)
                }

                if showsStatusAccessory {
                    statusAccessory
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var connection: DeviceConnection? {
        guard source.availability == .available else {
            return nil
        }

        guard case .connectedDevice(let device, _) = source.origin else {
            return nil
        }

        return device.connection
    }

    private var headerSymbolName: String {
        switch source.origin {
        case .localFolder, .javaLocalFolder:
            return "folder"
        case .connectedDevice:
            return "iphone.gen3"
        }
    }

    private var availabilityBadgeText: String? {
        if source.isOfflineCached {
            return "Cached"
        }

        switch source.availability {
        case .limited:
            return "Limited"
        case .unavailable, .disconnected:
            return "Offline"
        case .available, .unknown:
            return nil
        }
    }

    private var availabilityBadgeEmphasis: Bool {
        source.availability == .limited
    }

    private var showsStatusAccessory: Bool {
        source.isScanning
    }

    @ViewBuilder
    private var statusAccessory: some View {
        if source.isScanning {
            if let scanProgress = source.scanProgress {
                CircularScanProgressView(progress: scanProgress, isSelected: isSelected)
            } else {
                ProgressView()
                    .appActivityIndicatorStyle(.small)
            }
        }
    }
}

private struct SourceConnectionBadge: View {
    let connection: DeviceConnection
    let isSelected: Bool

    var body: some View {
        Image(systemName: symbolName)
            .appCapsuleLabelStyle(isSelected ? .sidebarSelected : .sidebarSubtle)
            .help(helpText)
            .accessibilityLabel(helpText)
    }

    private var symbolName: String {
        switch connection {
        case .usb:
            return "cable.connector"
        case .network:
            return "wifi"
        }
    }

    private var helpText: String {
        switch connection {
        case .usb:
            return "USB"
        case .network:
            return "Network"
        }
    }
}

private struct SourceAvailabilityBadge: View {
    let text: String
    let emphasis: Bool
    let isSelected: Bool

    var body: some View {
        Text(text)
            .appCapsuleLabelStyle(isSelected ? .sidebarSelected : emphasis ? .sidebarAccent : .sidebarSubtle)
    }
}

private struct CircularScanProgressView: View {
    let progress: Double
    let isSelected: Bool

    private let size: CGFloat = 17
    private let lineWidth: CGFloat = 1.4

    var body: some View {
        ZStack {
            Circle()
                .stroke(isSelected ? .white.opacity(0.18) : Color.secondary.opacity(0.24), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(0, min(progress, 1)))
                .stroke(
                    isSelected ? .white.opacity(0.86) : Color.appAccent,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scan progress")
        .accessibilityValue(Text("\(Int((progress * 100).rounded())) percent"))
    }
}

private struct ConnectedDeviceRow: View {
    let entry: ConnectedDeviceSidebarEntry
    let addAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .top) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.device.name)
                        .appTextStyle(.rowTitle)
                        .foregroundStyle(titleColor)

                    Text(statusText)
                        .appTextStyle(.supportingCompact)
                }
            } icon: {
                ConnectedDeviceTransportIcon(
                    baseSymbolName: iconName,
                    connection: entry.device.connection,
                    tint: iconColor
                )
            }

            Spacer(minLength: 12)

            if let addAction {
                Button("Add") {
                    addAction()
                }
                .appMiniProminentButton()
            }
        }
        .opacity(addAction == nil ? 0.68 : 1)
    }

    private var iconName: String {
        if entry.hasMinecraftContainer {
            return "iphone.gen3"
        }

        switch entry.device.trustState {
        case .trusted:
            return "iphone.slash"
        case .locked, .untrusted:
            return "lock.iphone"
        case .unavailable:
            return "iphone.gen3.slash"
        }
    }

    private var iconColor: Color {
        entry.hasMinecraftContainer ? .appAccent : .secondary
    }

    private var titleColor: Color {
        addAction == nil ? .secondary : .primary
    }

    private var statusText: String {
        if let errorDescription = entry.discoveryErrorDescription, !errorDescription.isEmpty {
            return errorDescription
        }

        switch entry.device.trustState {
        case .trusted:
            if entry.hasMinecraftContainer {
                return "Ready to add Minecraft library"
            }

            return "No Minecraft source found"
        case .locked:
            return "Unlock this device to inspect apps"
        case .untrusted:
            return "Trust this device to inspect apps"
        case .unavailable:
            return "Device unavailable"
        }
    }
}

private struct ConnectedDeviceTransportIcon: View {
    let baseSymbolName: String
    let connection: DeviceConnection
    let tint: Color

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: baseSymbolName)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)

            Image(systemName: badgeSymbolName)
                .appTransportBadgeBubble()
                .offset(x: 4, y: 4)
        }
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(helpText)
    }

    private var badgeSymbolName: String {
        switch connection {
        case .usb:
            return "cable.connector"
        case .network:
            return "wifi"
        }
    }

    private var helpText: String {
        switch connection {
        case .usb:
            return "Connected by USB"
        case .network:
            return "Connected by Network"
        }
    }
}

#if DEBUG
struct SidebarColumnViews_Previews: PreviewProvider {
    static var previews: some View {
        SidebarColumnPreviewContainer()
    }
}
#endif
