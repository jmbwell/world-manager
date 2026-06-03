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
            if !sources.isEmpty {
                Section {
                    ForEach(sources) { source in
                        sourceSectionRows(for: source)
                    }
                } header: {
                    SidebarSourcesSectionHeaderView(title: "Libraries")
                }
            }

            if !connectedDevices.isEmpty {
                Section {
                    ForEach(connectedDevices) { entry in
                        connectedDeviceSectionRows(for: entry)
                    }
                } header: {
                    SidebarSourcesSectionHeaderView(title: "Available Devices")
                }
            }

            if !sourceCandidates.isEmpty {
                Section {
                    ForEach(sourceCandidates) { candidate in
                        SourceCandidateRow(
                            candidate: candidate,
                            onSelect: {
                                selection = .sourceCandidate(candidateID: candidate.id)
                            },
                            addAction: {
                                addCandidateSourceAction(candidate)
                            }
                        )
                        .tag(SidebarSelection.sourceCandidate(candidateID: candidate.id) as SidebarSelection?)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    }
                } header: {
                    SidebarSourcesSectionHeaderView(title: "Found Sources")
                }
            }
        }
        .listStyle(.sidebar)
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

    @ViewBuilder
    private func sourceSectionRows(for source: MinecraftSource) -> some View {
        let sourceFilters = filters(source)

        SourceHeaderRow(
            source: source,
            isSelected: selection == .source(sourceID: source.id),
            onSelect: {
                selection = .source(sourceID: source.id)
            }
        )
            .tag(SidebarSelection.source(sourceID: source.id) as SidebarSelection?)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            .contextMenu {
                Button("Rescan \"\(source.displayName)\"") {
                    rescanSourceAction(source)
                }

                Divider()

                Button("Remove \"\(source.displayName)\"", role: .destructive) {
                    removeSourceAction(source)
                }
            }

        ForEach(sourceFilters) { filter in
            SidebarFilterRow(filter: filter, isIndented: true)
                .tag(filter.selection as SidebarSelection?)
        }
    }

    @ViewBuilder
    private func connectedDeviceSectionRows(for entry: ConnectedDeviceSidebarEntry) -> some View {
        ConnectedDeviceRow(
            entry: entry,
            onSelect: {
                selection = .connectedDevice(deviceID: entry.id)
            },
            addAction: entry.hasMinecraftContainer ? {
                addConnectedDeviceAction(entry)
            } : nil
        )
        .tag(SidebarSelection.connectedDevice(deviceID: entry.id) as SidebarSelection?)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 0, trailing: 8))
    }
}

private struct SourceCandidateRow: View {
    let candidate: SourceCandidate
    let onSelect: () -> Void
    let addAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.displayName)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: addAction) {
                Text("Add")
            }
            .appMiniProminentButton()
            .help("Add Source")
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
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
    let isIndented: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: filter.iconName)
                .frame(width: 16)
                .foregroundStyle(.secondary)

            Text(filter.title)

            Spacer()

            Text(filter.count, format: .number)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, isIndented ? 16 : 0)
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
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: headerSymbolName)
                .foregroundStyle(.secondary)

            Text(source.displayName)
                .lineLimit(1)

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if let availabilityBadgeText {
                    SourceAvailabilityBadge(text: availabilityBadgeText, emphasis: availabilityBadgeEmphasis)
                }

                if let connection {
                    SourceConnectionBadge(connection: connection)
                }

                if showsStatusAccessory {
                    statusAccessory
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.18))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
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
                    CircularScanProgressView(progress: scanProgress)
                } else {
                    ProgressView()
                        .appActivityIndicatorStyle(.small)
                }
            }
        }
}

private struct SourceConnectionBadge: View {
    let connection: DeviceConnection

    var body: some View {
        Image(systemName: symbolName)
            .appCapsuleLabelStyle(.sidebarSubtle)
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

    var body: some View {
        Text(text)
            .appCapsuleLabelStyle(emphasis ? .sidebarAccent : .sidebarSubtle)
    }
}

private struct CircularScanProgressView: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.18), lineWidth: 3)

            Circle()
                .trim(from: 0, to: max(0.02, min(progress, 1)))
                .stroke(
                    Color.appAccent,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 18, height: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scan progress")
        .accessibilityValue(Text("\(Int((progress * 100).rounded())) percent"))
    }
}

private struct ConnectedDeviceRow: View {
    let entry: ConnectedDeviceSidebarEntry
    let onSelect: () -> Void
    let addAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ConnectedDeviceTransportIcon(
                baseSymbolName: iconName,
                connection: entry.device.connection,
                tint: iconColor
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.device.name)
                    .appTextStyle(.rowTitle)
                    .foregroundStyle(titleColor)

                Text(statusText)
                    .appTextStyle(.supportingCompact)
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
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
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
