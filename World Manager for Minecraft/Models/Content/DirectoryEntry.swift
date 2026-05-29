import Foundation

struct DirectoryEntry: Identifiable, Hashable, Sendable {
    let id = UUID()
    let name: String
    let isDirectory: Bool
}
