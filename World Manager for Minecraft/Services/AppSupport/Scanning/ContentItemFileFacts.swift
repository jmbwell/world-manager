import Foundation

struct ContentItemFileFacts: Sendable {
    let storageFormatLabel: String
    let createdDateText: String
    let approximateAgeText: String?

    nonisolated init(item: MinecraftContentItem, now: Date = .now, fileManager: FileManager = .default) {
        let createdDate = try? item.folderURL.resourceValues(forKeys: [.creationDateKey]).creationDate
        self.createdDateText = createdDate?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown"

        if let createdDate {
            let components = Calendar.current.dateComponents([.year, .month], from: createdDate, to: now)
            if let year = components.year, year > 0 {
                self.approximateAgeText = year == 1 ? "About 1 year old" : "About \(year) years old"
            } else if let month = components.month, month > 0 {
                self.approximateAgeText = month == 1 ? "About 1 month old" : "About \(month) months old"
            } else {
                self.approximateAgeText = "Recently created"
            }
        } else {
            self.approximateAgeText = nil
        }

        switch item.contentType {
        case .world:
            let levelDBURL = item.folderURL.appendingPathComponent("db", isDirectory: true)
            self.storageFormatLabel = fileManager.fileExists(atPath: levelDBURL.path)
                ? "LevelDB world storage"
                : "Flat-file world storage"
        case .behaviorPack, .resourcePack, .skinPack, .worldTemplate:
            self.storageFormatLabel = "Manifest-based package"
        }
    }
}
