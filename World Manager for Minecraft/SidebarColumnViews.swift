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
    @Binding var selection: SidebarSelection?
    let footerState: SidebarFooterState
    let addSourceAction: () -> Void
    let rescanSourceAction: (MinecraftSource) -> Void
    let removeSourceAction: (MinecraftSource) -> Void
    let revealFooterURLAction: (URL) -> Void
    let filters: (MinecraftSource) -> [SidebarFilter]

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(sources) { source in
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
            } header: {
                SidebarSourcesSectionHeaderView()
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
        }
        .animation(.easeInOut(duration: 0.2), value: footerState.style)
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
    var body: some View {
        Text("Libraries")
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

private struct SidebarFooterView: View {
    let state: SidebarFooterState
    let revealAction: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if state.style == .inProgress {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(state.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(primaryColor)
                    .lineLimit(2)
            }

            if let subtitle = state.subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
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
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var primaryColor: Color {
        switch state.style {
        case .idle, .inProgress:
            return .primary
        case .failure:
            return .red
        case .success:
            return .appAccent
        }
    }
}

struct SidebarColumnViews_Previews: PreviewProvider {
    static var previews: some View {
        SidebarColumnPreviewContainer()
    }
}
