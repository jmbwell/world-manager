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

nonisolated enum SourceAccessMode: String, Hashable, Sendable, Codable {
    case localFileSystem
    case securityScopedLocalFolder
    case usbDevice
    case networkDevice
    case archive
    case unknown
}

nonisolated struct SourceAccessStatus: Hashable, Sendable, Codable {
    var availability: SourceAvailability
    var mode: SourceAccessMode
    var displayName: String
    var iconSystemName: String
    var statusText: String?
    var warningText: String?
}

nonisolated enum WorkStageState: String, Hashable, Sendable, Codable {
    case pending
    case running
    case succeeded
    case failed
    case skipped
    case cancelled
}

nonisolated enum WorkProgress: Hashable, Sendable, Codable {
    case indeterminate
    case fraction(Double)
    case count(completed: Int, total: Int?)
}

nonisolated struct WorkStage: Identifiable, Hashable, Sendable, Codable {
    let id: String
    var title: String
    var detail: String?
    var state: WorkStageState
    var progress: WorkProgress
}

nonisolated struct ProviderWarning: Identifiable, Hashable, Sendable, Codable {
    let id: String
    var message: String
    var detail: String?
}

nonisolated enum ProviderEvent: Sendable {
    case accessStatusChanged(SourceAccessStatus)
    case stageUpdated(WorkStage)
    case discovered(MinecraftContentItem)
    case inspected(MinecraftContentItem)
    case warning(ProviderWarning)
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
