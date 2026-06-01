// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import Foundation
import OSLog
import QuickLookThumbnailing

final class ThumbnailProvider: QLThumbnailProvider {
    private let logger = Logger(
        subsystem: "us.b-wells.World-Manager-for-Minecraft",
        category: "ThumbnailExtension"
    )

    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        logger.notice("Thumbnail extension hit: \(request.fileURL.path, privacy: .public)")

        do {
            let inspection = try MinecraftPackageInspector.inspectArchive(at: request.fileURL)
            defer { MinecraftPackageInspector.cleanup(inspection) }

            guard let image = MinecraftPackageThumbnailRenderer.makeThumbnail(
                for: inspection,
                size: request.maximumSize,
                scale: request.scale
            ) else {
                handler(nil, CocoaError(.fileReadCorruptFile))
                return
            }

            let size = request.maximumSize
            let reply = QLThumbnailReply(contextSize: size) { context in
                let rect = CGRect(origin: .zero, size: size)
                context.clear(rect)
                context.draw(image, in: rect)
                return true
            }

            logger.notice("Thumbnail extension produced image for: \(request.fileURL.lastPathComponent, privacy: .public)")
            handler(reply, nil)
        } catch {
            logger.error("Thumbnail extension failed for \(request.fileURL.path, privacy: .public): \(String(describing: error), privacy: .public)")
            handler(nil, error)
        }
    }
}
