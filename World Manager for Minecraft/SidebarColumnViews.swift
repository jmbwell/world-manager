import SwiftUI

enum SidebarSelection: Hashable {
    case allContent(sourceID: URL)
    case contentType(sourceID: URL, contentType: MinecraftContentType)

    var sourceID: URL {
        switch self {
        case .allContent(let sourceID), .contentType(let sourceID, _):
            return sourceID
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
    @Binding var selection: SidebarSelection?
    let footerState: SidebarFooterState
    let addSourceAction: () -> Void
    let addDeviceSourceAction: () -> Void
    let addConnectedDeviceAction: (ConnectedDeviceSidebarEntry) -> Void
    let rescanSourceAction: (MinecraftSource) -> Void
    let removeSourceAction: (MinecraftSource) -> Void
    let revealFooterURLAction: (URL) -> Void
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
                    SidebarSourcesSectionHeaderView(title: "Connected Devices")
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
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
        SourceHeaderRow(source: source)
            .listRowSeparator(.hidden)
            .padding(.top, 6)
            .contextMenu {
                Button("Rescan \"\(source.displayName)\"") {
                    rescanSourceAction(source)
                }

                Divider()

                Button("Remove \"\(source.displayName)\"", role: .destructive) {
                    removeSourceAction(source)
                }
            }

        ForEach(filters(source)) { filter in
            SidebarFilterRow(filter: filter, isIndented: true)
                .tag(filter.selection as SidebarSelection?)
        }
    }

    @ViewBuilder
    private func connectedDeviceSectionRows(for entry: ConnectedDeviceSidebarEntry) -> some View {
        ConnectedDeviceRow(
            entry: entry,
            addAction: entry.hasMinecraftContainer ? {
                addConnectedDeviceAction(entry)
            } : nil
        )
        .listRowSeparator(.hidden)
        .padding(.top, 6)
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
            .font(.headline)
            .foregroundStyle(.secondary)
            .textCase(nil)
    }
}

private struct SourceHeaderRow: View {
    let source: MinecraftSource
    @State private var isPresentingStatusPopover = false

    var body: some View {
        HStack(spacing: 8) {
            Text(source.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            if let connection {
                SourceConnectionBadge(connection: connection)
            }

            if showsStatusButton {
                Button {
                    isPresentingStatusPopover = true
                } label: {
                    statusIndicator
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(scanStatusHelpText)
                .popover(isPresented: $isPresentingStatusPopover, arrowEdge: .top) {
                    SourceStatusPopover(source: source)
                }
            }
        }
    }

    private var connection: DeviceConnection? {
        guard case .connectedDevice(let device, _) = source.origin else {
            return nil
        }

        return device.connection
    }

    private var scanStatusHelpText: String {
        if let scanError = source.scanError, !scanError.isEmpty {
            return scanError
        }

        if !source.scanStatus.isEmpty {
            return source.scanStatus
        }

        return "Scanning library…"
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if source.isScanning {
            if let scanProgress = source.scanProgress {
                CircularScanProgressView(progress: scanProgress)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        } else if source.scanError != nil {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.secondary)
        } else {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
    }

    private var showsStatusButton: Bool {
        source.isScanning || source.scanError != nil
    }
}

private struct SourceConnectionBadge: View {
    let connection: DeviceConnection

    var body: some View {
        Image(systemName: symbolName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.secondary.opacity(0.12), in: Capsule())
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

private struct SourceStatusPopover: View {
    let source: MinecraftSource

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                if !source.isScanning, source.scanError != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else if !source.isScanning {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }

                Text(titleText)
                    .font(.headline)
            }

            if source.isScanning, let scanProgress = source.scanProgress {
                ProgressView(value: scanProgress, total: 1)
            }

            if let subtitleText {
                Text(subtitleText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let detailText {
                Text(detailText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 280, alignment: .leading)
        .padding(14)
    }

    private var titleText: String {
        if let scanError = source.scanError, !scanError.isEmpty {
            return "Scan Failed"
        }

        if !source.scanStatus.isEmpty {
            return source.scanStatus
        }

        return "Scanning Minecraft library..."
    }

    private var subtitleText: String? {
        if let scanError = source.scanError, !scanError.isEmpty {
            return scanError
        }

        if source.indexedItemCount > 0 {
            return source.displayName
        }

        return "Searching \(source.displayName)"
    }

    private var detailText: String? {
        if let diagnostic = source.scanDiagnostic, !diagnostic.isEmpty {
            return diagnostic
        }

        guard source.scanError == nil, source.indexedItemCount > 0 else {
            return nil
        }

        if source.isScanning, let scanProgress = source.scanProgress {
            let percentage = Int((scanProgress * 100).rounded())
            let previewLoadedCount = source.rawItems.filter(\.previewLoaded).count
            let sizeLoadedCount = source.rawItems.filter(\.sizeLoaded).count
            if sizeLoadedCount > 0 || source.scanStatus.contains("Calculating sizes") {
                return "\(sizeLoadedCount) of \(source.indexedItemCount) sizes calculated • \(percentage)%"
            }
            if previewLoadedCount > 0 || source.scanStatus.contains("Loading previews") {
                return "\(previewLoadedCount) of \(source.indexedItemCount) previews loaded • \(percentage)%"
            }

            return "\(source.indexedDetailCount) of \(source.indexedItemCount) indexed • \(percentage)%"
        }

        return "\(source.indexedDetailCount) of \(source.indexedItemCount) indexed"
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
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(titleColor)

                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if let addAction {
                Button("Add") {
                    addAction()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
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
            if entry.hasMinecraftContainer, let container = entry.minecraftContainer {
                return "Minecraft found in \(container.appName)"
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
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.primary)
                .padding(4)
                .background(.thinMaterial, in: Circle())
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

private struct SidebarFooterView: View {
    let state: SidebarFooterState
    let revealAction: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if state.style == .inProgress {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.appAccent)
                }

                Text(state.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(primaryColor)
                    .lineLimit(3)
            }

            if let subtitle = state.subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let detail = state.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let revealURL = state.revealURL {
                Button("Reveal in Finder") {
                    revealAction(revealURL)
                }
                .buttonStyle(.link)
                .font(.footnote)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(cardStroke)
        }
    }

    private var primaryColor: Color {
        switch state.style {
        case .idle:
            return .primary
        case .inProgress:
            return .appAccent
        case .failure:
            return .red
        case .success:
            return .appAccent
        }
    }

    private var cardBackground: AnyShapeStyle {
        switch state.style {
        case .inProgress:
            return AnyShapeStyle(Color.appAccent.opacity(0.08))
        default:
            return AnyShapeStyle(.regularMaterial)
        }
    }

    private var cardStroke: Color {
        switch state.style {
        case .inProgress:
            return Color.appAccent.opacity(0.18)
        case .failure:
            return .red.opacity(0.18)
        case .success:
            return Color.appAccent.opacity(0.16)
        case .idle:
            return .white.opacity(0.08)
        }
    }
}

struct SidebarColumnViews_Previews: PreviewProvider {
    static var previews: some View {
        SidebarColumnPreviewContainer()
    }
}
