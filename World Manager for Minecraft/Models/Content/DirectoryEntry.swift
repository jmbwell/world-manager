// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

struct DirectoryEntry: Identifiable, Hashable, Sendable {
    let id = UUID()
    let name: String
    let isDirectory: Bool
}
