// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

typealias SourceAccessorIdentifier = String

nonisolated enum SourceAvailability: String, Hashable, Sendable, Codable {
    case unknown
    case available
    case disconnected
    case limited
    case unavailable
}

nonisolated enum SourceRefreshStrategy: String, Hashable, Sendable, Codable {
    case eagerFullScan
    case staged
}

nonisolated struct SourceAccessDescriptor: Hashable, Sendable, Codable {
    var accessorIdentifier: SourceAccessorIdentifier
    var kind: MinecraftSourceKind
    var refreshStrategy: SourceRefreshStrategy
}

nonisolated struct SourceRecord: Identifiable, Hashable, Sendable, Codable {
    let id: URL
    var displayName: String
    var rootURL: URL
    var origin: MinecraftSourceOrigin
    var accessDescriptor: SourceAccessDescriptor
    var availability: SourceAvailability
    var lastRefreshDate: Date?
}
