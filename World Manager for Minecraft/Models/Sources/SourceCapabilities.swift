// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

struct SourceCapabilities: Hashable, Sendable, Codable {
    var canScan: Bool = true
    var canMaterializeItems: Bool = true
    var canExportPortablePackages: Bool = true

    static let localFolder = SourceCapabilities(
        canScan: true,
        canMaterializeItems: true,
        canExportPortablePackages: true
    )

    static let connectedDevice = SourceCapabilities(
        canScan: true,
        canMaterializeItems: true,
        canExportPortablePackages: true
    )
}
