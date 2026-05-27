//
//  SourceRecord.swift
//  World Manager for Minecraft
//
//  Created by OpenAI on 2026-05-26.
//

import Foundation

typealias SourceAccessorIdentifier = String

enum SourceAvailability: String, Hashable, Sendable, Codable {
    case unknown
    case available
    case disconnected
    case limited
    case unavailable
}

enum SourceRefreshStrategy: String, Hashable, Sendable, Codable {
    case eagerFullScan
    case staged
}

struct SourceCapabilities: Hashable, Sendable, Codable {
    var supportsDirectFileAccess: Bool
    var supportsStagedRefresh: Bool
    var supportsPersistentCaching: Bool
    var supportsLazyMaterialization: Bool

    nonisolated static let localFolder = SourceCapabilities(
        supportsDirectFileAccess: true,
        supportsStagedRefresh: false,
        supportsPersistentCaching: false,
        supportsLazyMaterialization: false
    )

    nonisolated static let connectedDevice = SourceCapabilities(
        supportsDirectFileAccess: false,
        supportsStagedRefresh: true,
        supportsPersistentCaching: true,
        supportsLazyMaterialization: true
    )
}

struct SourceAccessDescriptor: Hashable, Sendable, Codable {
    var accessorIdentifier: SourceAccessorIdentifier
    var kind: MinecraftSourceKind
    var capabilities: SourceCapabilities
    var refreshStrategy: SourceRefreshStrategy
}

struct SourceRecord: Identifiable, Hashable, Sendable, Codable {
    let id: URL
    var displayName: String
    var rootURL: URL
    var origin: MinecraftSourceOrigin
    var accessDescriptor: SourceAccessDescriptor
    var availability: SourceAvailability
    var lastRefreshDate: Date?
}
