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
    let localSources: [MinecraftSource]
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
    let matchedSource: (ConnectedDeviceSidebarEntry) -> MinecraftSource?

    var body: some View {
        List(selection: $selection) {
            if !localSources.isEmpty {
                Section {
                    ForEach(localSources) { source in
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
        .overlay(alignment: .bottom) {
            if footerState.style != .idle {
                SidebarFooterView(
                    state: footerState,
                    revealAction: revealFooterURLAction
                )
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
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
        .animation(.easeInOut(duration: 0.2), value: footerState.style)
    }

    @ViewBuilder
    private func sourceSectionRows(for source: MinecraftSource) -> some View {
        SourceHeaderRow(title: source.displayName)
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
        if let source = matchedSource(entry) {
            sourceSectionRows(for: source)
        } else {
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
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct ConnectedDeviceRow: View {
    let entry: ConnectedDeviceSidebarEntry
    let addAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .frame(width: 16)
                .foregroundStyle(iconColor)

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
