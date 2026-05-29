import AppKit
import SwiftUI

enum AppChrome {
    static let sidebarRowCornerRadius: CGFloat = 10
    static let placeholderCardCornerRadius: CGFloat = 16
    static let panelCardCornerRadius: CGFloat = 18
}

enum AppCardStyle {
    case primaryPanel
    case secondaryPanel
    case placeholder

    fileprivate var cornerRadius: CGFloat {
        switch self {
        case .primaryPanel, .secondaryPanel:
            return AppChrome.panelCardCornerRadius
        case .placeholder:
            return AppChrome.placeholderCardCornerRadius
        }
    }

    fileprivate var fillStyle: AnyShapeStyle {
        switch self {
        case .primaryPanel:
            return AnyShapeStyle(.regularMaterial)
        case .secondaryPanel:
            return AnyShapeStyle(.quaternary.opacity(0.32))
        case .placeholder:
            return AnyShapeStyle(.thinMaterial)
        }
    }
}

private struct AppCardSurfaceModifier: ViewModifier {
    let style: AppCardStyle

    func body(content: Content) -> some View {
        content.background(
            style.fillStyle,
            in: RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
        )
    }
}

extension View {
    func appCardSurface(_ style: AppCardStyle) -> some View {
        modifier(AppCardSurfaceModifier(style: style))
    }

    func appSidebarRowSurface(isHighlighted: Bool) -> some View {
        let fillStyle = isHighlighted
            ? AnyShapeStyle(.secondary.opacity(0.08))
            : AnyShapeStyle(Color.clear)
        return background(
            fillStyle,
            in: RoundedRectangle(cornerRadius: AppChrome.sidebarRowCornerRadius, style: .continuous)
        )
    }
}

struct ToolbarShareButton: View {
    let systemImage: String
    let isEnabled: Bool
    let action: (NSView?) -> Void
    @State private var anchorView: NSView?

    var body: some View {
        Button {
            action(anchorView)
        } label: {
            Image(systemName: systemImage)
        }
        .disabled(!isEnabled)
        .background {
            ShareAnchorView(anchorView: $anchorView)
        }
    }
}

struct ActionPillButton: View {
    enum Prominence {
        case primary
        case secondary
    }

    let title: String
    let systemImage: String
    var isDisabled = false
    var prominence: Prominence = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HeroActionLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(HeroActionButtonStyle(prominence: prominence))
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
    }
}

struct SharingPillButton: View {
    let title: String
    let systemImage: String
    let isEnabled: Bool
    let action: (NSView?) -> Void
    @State private var anchorView: NSView?

    var body: some View {
        Button {
            action(anchorView)
        } label: {
            HeroActionLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(HeroActionButtonStyle(prominence: .secondary))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .background {
            ShareAnchorView(anchorView: $anchorView)
        }
    }
}

struct HeroActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
    }
}

struct HeroActionButtonStyle: ButtonStyle {
    let prominence: ActionPillButton.Prominence

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .background(backgroundColor.opacity(configuration.isPressed ? pressedOpacity : 1), in: Capsule())
            .overlay {
                if prominence == .secondary {
                    Capsule()
                        .strokeBorder(.white.opacity(0.14))
                }
            }
            .controlSize(.large)
    }

    private var backgroundColor: Color {
        switch prominence {
        case .primary:
            return .appAccent
        case .secondary:
            return Color.black.opacity(0.22)
        }
    }

    private var pressedOpacity: CGFloat {
        switch prominence {
        case .primary:
            return 0.88
        case .secondary:
            return 0.72
        }
    }
}

struct ShareAnchorView: NSViewRepresentable {
    @Binding var anchorView: NSView?

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            anchorView = view
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if anchorView !== nsView {
            DispatchQueue.main.async {
                anchorView = nsView
            }
        }
    }
}

struct RecordHeroView: View {
    private let heroHeight: CGFloat = 360
    private let heroTopPadding: CGFloat = 74
    private let heroBottomPadding: CGFloat = 20
    private let titleLineLimit = 5
    private let titleMinimumScale: CGFloat = 0.78
    private let detailsColumnSpacing: CGFloat = 18

    let item: MinecraftContentItem
    let metadataChips: [String]
    let fallbackSystemImage: String
    let copyAction: () -> Void
    let actionRow: AnyView
    let contentMaxWidth: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let innerHeight = max(0, proxy.size.height - heroTopPadding - heroBottomPadding)

            ZStack(alignment: .topLeading) {
                artworkBackground

                LinearGradient(
                    colors: [.black.opacity(0.12), .black.opacity(0.22), .black.opacity(0.5)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                HStack(alignment: .top, spacing: 18) {
                    HeroThumbnailView(
                        iconURL: item.iconURL,
                        contentType: item.contentType,
                        availableHeight: innerHeight
                    )

                    VStack(alignment: .leading, spacing: detailsColumnSpacing) {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack(alignment: .top, spacing: 10) {
                                Text(item.displayName)
                                    .font(titleFont)
                                    .foregroundStyle(.white)
                                    .lineLimit(titleLineLimit)
                                    .minimumScaleFactor(titleMinimumScale)
                                    .truncationMode(.tail)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)

                                Button(action: copyAction) {
                                    Image(systemName: "document.on.document")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.88))
                                }
                                .buttonStyle(.plain)
                            }

                            recordHeroChips
                        }

                        Spacer(minLength: 16)

                        actionRow
                    }
                    .frame(maxWidth: .infinity, maxHeight: innerHeight, alignment: .topLeading)
                }
                .frame(maxWidth: contentMaxWidth, maxHeight: innerHeight, alignment: .topLeading)
                .padding(.horizontal, 28)
                .padding(.top, heroTopPadding)
                .padding(.bottom, heroBottomPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: heroHeight, alignment: .top)
        .clipShape(Rectangle())
        .ignoresSafeArea(edges: .top)
    }

    private var artworkBackground: some View {
        Group {
            if let image = loadImage(from: item.iconURL) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 36)
                    .saturation(1.08)
            } else {
                LinearGradient(
                    colors: [Color.appAccent.opacity(0.9), Color.black.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: fallbackSystemImage)
                        .font(.system(size: 84))
                        .foregroundStyle(.white.opacity(0.2))
                }
            }
        }
    }

    private var recordHeroChips: some View {
        FlexibleTagLayout(spacing: 8, rowSpacing: 8, items: metadataChips) { chip in
            Text(chip)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.95))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.white.opacity(0.14), in: Capsule())
        }
    }

    private var titleFont: Font {
        .system(
            item.displayName.count > 70 ? .title2 : .largeTitle,
            design: .rounded
        ).weight(.semibold)
    }
}

private struct HeroThumbnailView: View {
    private let thumbnailMaxWidth: CGFloat = 280
    private let thumbnailMaxHeight: CGFloat = 180
    private let thumbnailMinHeight: CGFloat = 120

    let iconURL: URL?
    let contentType: MinecraftContentType
    let availableHeight: CGFloat

    var body: some View {
        Group {
            if let image = loadImage(from: iconURL) {
                let frame = thumbnailFrame(for: image.size)

                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: frame.width, height: frame.height)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 28)
                    .fill(.white.opacity(0.14))
                    .frame(width: 220, height: 160)
                    .overlay(
                        Image(systemName: fallbackIconName)
                            .font(.system(size: 52))
                            .foregroundStyle(.white.opacity(0.75))
                    )
            }
        }
        .padding(10)
        .background(.ultraThinMaterial.opacity(0.55), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(.white.opacity(0.14))
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 22, y: 10)
    }

    private func thumbnailFrame(for imageSize: CGSize) -> CGSize {
        let aspectRatio = max(0.4, min(3.0, imageSize.width / max(1, imageSize.height)))
        let maxHeight = min(thumbnailMaxHeight, max(thumbnailMinHeight, availableHeight))
        let widthFromHeight = maxHeight * aspectRatio

        if widthFromHeight <= thumbnailMaxWidth {
            return CGSize(width: widthFromHeight, height: maxHeight)
        }

        return CGSize(width: thumbnailMaxWidth, height: thumbnailMaxWidth / aspectRatio)
    }

    private var fallbackIconName: String {
        switch contentType {
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
}

struct LaunchRestoreOverlayView: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)

                Text("Opening Library…")
                    .font(.title3.weight(.semibold))
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(.background.opacity(0.92))
            )
        }
    }
}

struct PackReferenceIconView: View {
    let iconURL: URL?
    let fallbackSystemImage: String

    var body: some View {
        if let image = loadImage(from: iconURL) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: fallbackSystemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                )
        }
    }
}

struct EmptySourcesView: View {
    let isDropTargeted: Bool
    let chooseFolder: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10, 10]))
                    .foregroundStyle(isDropTargeted ? Color.appAccent : Color.secondary.opacity(0.25))
                    .frame(width: 220, height: 160)

                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(isDropTargeted ? Color.appAccent : Color.secondary)
            }

            VStack(spacing: 8) {
                Text("Add a Minecraft Source")
                    .font(.title2)

                Text("Choose a copied Minecraft folder or drop one here to start scanning worlds, packs, and templates.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            Button("Choose Minecraft Folder...") {
                chooseFolder()
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct ItemThumbnailView: View {
    let iconURL: URL?
    let fallbackSystemImage: String = "shippingbox"

    var body: some View {
        if let image = loadImage(from: iconURL) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        } else {
            RoundedRectangle(cornerRadius: 7)
                .fill(.quaternary)
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: fallbackSystemImage)
                        .foregroundStyle(.secondary)
                )
        }
    }
}

struct FlexibleTagLayout<Item: Hashable, Content: View>: View {
    let spacing: CGFloat
    let rowSpacing: CGFloat
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        HStack(spacing: 0) {
            GeometryReader { geometry in
                generateContent(in: geometry)
            }
        }
        .frame(minHeight: 1)
    }

    private func generateContent(in geometry: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero

        return ZStack(alignment: .topLeading) {
            ForEach(items, id: \.self) { item in
                content(item)
                    .alignmentGuide(.leading) { dimensions in
                        if abs(width - dimensions.width) > geometry.size.width {
                            width = 0
                            height -= dimensions.height + rowSpacing
                        }

                        let result = width
                        if item == items.last {
                            width = 0
                        } else {
                            width -= dimensions.width + spacing
                        }
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        if item == items.last {
                            height = 0
                        }
                        return result
                    }
            }
        }
    }
}

struct StorageBreakdown {
    let primaryDataSize: Int64?
    let resourceSize: Int64?
    let metadataSize: Int64?

    static let loading = StorageBreakdown(primaryDataSize: nil, resourceSize: nil, metadataSize: nil)

    nonisolated static func build(for item: MinecraftContentItem) -> StorageBreakdown {
        let fileManager = FileManager.default

        switch item.contentType {
        case .world:
            let dbURL = item.folderURL.appendingPathComponent("db", isDirectory: true)
            let behaviorURL = item.folderURL.appendingPathComponent("behavior_packs", isDirectory: true)
            let resourceURL = item.folderURL.appendingPathComponent("resource_packs", isDirectory: true)

            let primarySize = folderSize(at: dbURL, fileManager: fileManager)
            let resourcesSize = (folderSize(at: behaviorURL, fileManager: fileManager) ?? 0)
                + (folderSize(at: resourceURL, fileManager: fileManager) ?? 0)
            let totalSize = folderSize(at: item.folderURL, fileManager: fileManager)
            let metadata = totalSize.map { total in
                max(0, total - (primarySize ?? 0) - resourcesSize)
            }

            return StorageBreakdown(
                primaryDataSize: primarySize,
                resourceSize: resourcesSize == 0 ? nil : resourcesSize,
                metadataSize: metadata
            )
        case .behaviorPack, .resourcePack, .skinPack, .worldTemplate:
            let totalSize = folderSize(at: item.folderURL, fileManager: fileManager)
            return StorageBreakdown(
                primaryDataSize: totalSize,
                resourceSize: nil,
                metadataSize: nil
            )
        }
    }

    var primaryDataText: String {
        sizeText(for: primaryDataSize)
    }

    var resourcesText: String {
        sizeText(for: resourceSize)
    }

    var metadataText: String {
        sizeText(for: metadataSize)
    }

    private func sizeText(for size: Int64?) -> String {
        guard let size else {
            return "Unavailable"
        }

        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private nonisolated static func folderSize(at folderURL: URL, fileManager: FileManager) -> Int64? {
        guard fileManager.fileExists(atPath: folderURL.path) else {
            return nil
        }

        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var totalSize: Int64 = 0

        for case let fileURL as URL in enumerator {
            guard
                let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                values.isRegularFile == true,
                let fileSize = values.fileSize
            else {
                continue
            }

            totalSize += Int64(fileSize)
        }

        return totalSize
    }
}

func loadImage(from url: URL?) -> NSImage? {
    guard let url else {
        return nil
    }

    return NSImage(contentsOf: url)
}

func copyToPasteboard(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
}

extension Color {
    static let appAccent = Color("AccentColor")
}
