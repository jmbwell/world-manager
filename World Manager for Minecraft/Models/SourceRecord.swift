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

struct SourceAccessDescriptor: Hashable, Sendable, Codable {
    var accessorIdentifier: SourceAccessorIdentifier
    var kind: MinecraftSourceKind
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
