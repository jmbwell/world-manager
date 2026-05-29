//
//  SourceCapabilities.swift
//  World Manager for Minecraft
//
//  Created by OpenAI on 2026-05-29.
//

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
