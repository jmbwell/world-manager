import AppKit
import Foundation

let fileManager = FileManager.default
let currentDirectoryURL = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
let iconsetURL = currentDirectoryURL
    .appendingPathComponent("World Manager for Minecraft/MinecraftVoxelDocument.iconset", isDirectory: true)
let singleIconURL = currentDirectoryURL
    .appendingPathComponent("World Manager for Minecraft/MinecraftVoxelDocument.png")

let outputSizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for output in outputSizes {
    let image = try makeDocumentIcon(pixels: output.pixels)
    let destinationURL = iconsetURL.appendingPathComponent(output.name)
    try writePNG(image: image, to: destinationURL)
}

let primaryIcon = try makeDocumentIcon(pixels: 1024)
try writePNG(image: primaryIcon, to: singleIconURL)

func makeDocumentIcon(pixels: Int) throws -> NSImage {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }

    bitmap.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }

    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }

    NSGraphicsContext.current = context

    let size = CGFloat(pixels)
    let rect = CGRect(origin: .zero, size: CGSize(width: size, height: size))
    drawBackground(in: rect)
    drawVoxelBadge(in: rect.insetBy(dx: size * 0.20, dy: size * 0.18))
    drawBorder(in: rect)
    context.flushGraphics()

    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.addRepresentation(bitmap)
    return image
}

func drawBackground(in rect: CGRect) {
    let path = NSBezierPath(
        roundedRect: rect.insetBy(dx: 1, dy: 1),
        xRadius: rect.width * 0.20,
        yRadius: rect.height * 0.20
    )

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.25, alpha: 1),
        NSColor(calibratedRed: 0.47, green: 0.75, blue: 0.31, alpha: 1)
    ])
    gradient?.draw(in: path, angle: -45)
}

func drawVoxelBadge(in rect: CGRect) {
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

func drawBorder(in rect: CGRect) {
    let path = NSBezierPath(
        roundedRect: rect.insetBy(dx: 1, dy: 1),
        xRadius: rect.width * 0.20,
        yRadius: rect.height * 0.20
    )
    NSColor.black.withAlphaComponent(0.10).setStroke()
    path.lineWidth = max(1, rect.width * 0.01)
    path.stroke()
}

func writePNG(image: NSImage, to url: URL) throws {
    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw CocoaError(.fileWriteUnknown)
    }

    try pngData.write(to: url)
}
