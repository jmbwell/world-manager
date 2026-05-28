//
//  PreviewViewController.swift
//  MinecraftPackagePreviewExtension
//
//  Created by John Burwell on 2026-05-27.
//

import Cocoa
import OSLog
import Quartz

final class PreviewViewController: NSViewController, QLPreviewingController {
    private let logger = Logger(
        subsystem: "us.b-wells.World-Manager-for-Minecraft",
        category: "PreviewExtension"
    )

    private var currentInspection: MinecraftPackageInspector.InspectionResult?
    private let imageView = NSImageView()
    private let scrollView = NSScrollView()

    override func loadView() {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter

        let containerView = NSView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(imageView)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.documentView = containerView

        rootView.addSubview(scrollView)
        view = rootView

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: rootView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            containerView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: -32),
            containerView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 32),
            containerView.topAnchor.constraint(equalTo: imageView.topAnchor, constant: -32),
            containerView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 32),

            imageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
        ])
    }

    func preparePreviewOfFile(at url: URL) async throws {
        logger.notice("Preview extension hit: \(url.path, privacy: .public)")

        if let currentInspection {
            MinecraftPackageInspector.cleanup(currentInspection)
            self.currentInspection = nil
        }

        let inspection = try MinecraftPackageInspector.inspectArchive(at: url)
        let image = makePreviewImage(for: inspection)

        await MainActor.run {
            imageView.image = image
            updateImageConstraints(for: image)
        }

        currentInspection = inspection
    }

    private func makePreviewImage(for inspection: MinecraftPackageInspector.InspectionResult) -> NSImage? {
        if let iconURL = inspection.iconURL,
           let image = NSImage(contentsOf: iconURL) {
            return image
        }

        guard let cgImage = MinecraftPackageThumbnailRenderer.makeThumbnail(
            for: inspection,
            size: CGSize(width: 480, height: 480),
            scale: NSScreen.main?.backingScaleFactor ?? 2
        ) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: 480, height: 480))
    }

    private func updateImageConstraints(for image: NSImage?) {
        imageView.constraints.forEach { imageView.removeConstraint($0) }

        guard let image, image.size.width > 0, image.size.height > 0 else {
            return
        }

        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: image.size.width),
            imageView.heightAnchor.constraint(equalToConstant: image.size.height)
        ])
    }

    deinit {
        if let currentInspection {
            MinecraftPackageInspector.cleanup(currentInspection)
        }
    }
}
