// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

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
