import Foundation

struct ContentItemActionService: Sendable {
    nonisolated func suggestedFilename(for item: MinecraftContentItem) -> String {
        ContentPackageExporter.suggestedBaseFilename(for: item)
    }

    nonisolated func createArchiveFile(
        for item: MinecraftContentItem,
        source: MinecraftSource?,
        destinationURL: URL? = nil
    ) async throws -> URL {
        try await ContentPackageExporter.createArchiveFile(
            for: item,
            source: source,
            destinationURL: destinationURL
        )
    }
}
