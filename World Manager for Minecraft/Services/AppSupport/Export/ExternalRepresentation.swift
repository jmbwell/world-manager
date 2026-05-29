//
//  ExternalRepresentation.swift
//  World Manager for Minecraft
//
//  Created by OpenAI on 2026-05-29.
//

import Foundation
import UniformTypeIdentifiers

enum ExternalRepresentationKind: Hashable, Sendable {
    case nativeFolder
    case portablePackage
}

struct ExternalRepresentation: Hashable, Sendable {
    let url: URL
    let kind: ExternalRepresentationKind
    let suggestedFilename: String
    let contentType: UTType
    let isTemporary: Bool
}
