//
//  MinecraftPackageThumbnailRenderer.swift
//  MinecraftPackagePreviewExtension
//

import AppKit
import Foundation

enum MinecraftPackageThumbnailRenderer {
    nonisolated static func makeThumbnail(
        for inspection: MinecraftPackageInspector.InspectionResult,
        size: CGSize,
        scale: CGFloat = 1
    ) -> CGImage? {
        let pixelSize = CGSize(
            width: max(size.width * scale, 1),
            height: max(size.height * scale, 1)
        )

        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: max(Int(pixelSize.width.rounded(.up)), 1),
                pixelsHigh: max(Int(pixelSize.height.rounded(.up)), 1),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        else {
            return nil
        }

        bitmap.size = pixelSize

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }

        NSGraphicsContext.current = context
        let rect = CGRect(origin: .zero, size: pixelSize)

        if let iconURL = inspection.iconURL,
           let iconImage = NSImage(contentsOf: iconURL) {
            drawSquareThumbnail(iconImage, in: rect)
        } else {
            drawFallbackThumbnail(for: inspection.contentType, in: rect)
        }

        context.flushGraphics()
        return bitmap.cgImage
    }

    nonisolated private static func drawSquareThumbnail(_ image: NSImage, in rect: CGRect) {
        NSColor.clear.setFill()
        rect.fill()

        let cornerRadius = min(rect.width, rect.height) * 0.10
        let clipRect = rect.insetBy(dx: max(rect.width * 0.02, 1), dy: max(rect.height * 0.02, 1))
        let clipPath = NSBezierPath(
            roundedRect: clipRect,
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        clipPath.addClip()

        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            image.draw(in: clipRect)
            return
        }

        let scale = max(clipRect.width / imageSize.width, clipRect.height / imageSize.height)
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let drawRect = CGRect(
            x: clipRect.midX - drawSize.width / 2,
            y: clipRect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )

        image.draw(in: drawRect)

        NSColor.black.withAlphaComponent(0.10).setStroke()
        let borderPath = NSBezierPath(
            roundedRect: clipRect.insetBy(dx: 0.5, dy: 0.5),
            xRadius: max(cornerRadius - 0.5, 0),
            yRadius: max(cornerRadius - 0.5, 0)
        )
        borderPath.lineWidth = max(1, rect.width * 0.01)
        borderPath.stroke()
    }

    nonisolated private static func drawFallbackThumbnail(
        for contentType: MinecraftContentType,
        in rect: CGRect
    ) {
        let path = NSBezierPath(
            roundedRect: rect,
            xRadius: rect.width * 0.10,
            yRadius: rect.width * 0.10
        )

        let gradient = NSGradient(colors: backgroundColors(for: contentType))
        gradient?.draw(in: path, angle: -45)

        let badgeRect = rect.insetBy(dx: rect.width * 0.18, dy: rect.height * 0.18)
        drawVoxelBadge(in: badgeRect)

        NSColor.black.withAlphaComponent(0.10).setStroke()
        path.lineWidth = max(1, rect.width * 0.01)
        path.stroke()
    }

    nonisolated private static func drawVoxelBadge(in rect: CGRect) {
        let topFace = NSBezierPath()
        topFace.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        topFace.line(to: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.18))
        topFace.line(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.36))
        topFace.line(to: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.18))
        topFace.close()
        NSColor(calibratedRed: 0.78, green: 0.94, blue: 0.63, alpha: 1).setFill()
        topFace.fill()

        let leftFace = NSBezierPath()
        leftFace.move(to: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.18))
        leftFace.line(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.36))
        leftFace.line(to: CGPoint(x: rect.midX, y: rect.minY))
        leftFace.line(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.18))
        leftFace.close()
        NSColor(calibratedRed: 0.34, green: 0.61, blue: 0.24, alpha: 1).setFill()
        leftFace.fill()

        let rightFace = NSBezierPath()
        rightFace.move(to: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.18))
        rightFace.line(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.36))
        rightFace.line(to: CGPoint(x: rect.midX, y: rect.minY))
        rightFace.line(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.18))
        rightFace.close()
        NSColor(calibratedRed: 0.14, green: 0.34, blue: 0.13, alpha: 1).setFill()
        rightFace.fill()

        NSColor.black.withAlphaComponent(0.18).setStroke()
        [topFace, leftFace, rightFace].forEach {
            $0.lineWidth = max(1, rect.width * 0.02)
            $0.stroke()
        }
    }

    nonisolated private static func backgroundColors(for contentType: MinecraftContentType) -> [NSColor] {
        switch contentType {
        case .world:
            return [
                NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.25, alpha: 1),
                NSColor(calibratedRed: 0.47, green: 0.75, blue: 0.31, alpha: 1)
            ]
        case .behaviorPack:
            return [
                NSColor(calibratedRed: 0.58, green: 0.29, blue: 0.15, alpha: 1),
                NSColor(calibratedRed: 0.86, green: 0.60, blue: 0.22, alpha: 1)
            ]
        case .resourcePack:
            return [
                NSColor(calibratedRed: 0.12, green: 0.38, blue: 0.66, alpha: 1),
                NSColor(calibratedRed: 0.31, green: 0.68, blue: 0.85, alpha: 1)
            ]
        case .skinPack:
            return [
                NSColor(calibratedRed: 0.53, green: 0.19, blue: 0.43, alpha: 1),
                NSColor(calibratedRed: 0.84, green: 0.39, blue: 0.62, alpha: 1)
            ]
        case .worldTemplate:
            return [
                NSColor(calibratedRed: 0.23, green: 0.23, blue: 0.54, alpha: 1),
                NSColor(calibratedRed: 0.53, green: 0.52, blue: 0.89, alpha: 1)
            ]
        }
    }
}
