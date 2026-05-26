//
//  SourcePersistenceStore.swift
//  World Manager for Minecraft
//
//  Created by OpenAI on 2026-05-25.
//

import Foundation
import SQLite3

struct PersistedSourceRecord: Sendable {
    let folderURL: URL
    let displayName: String
    let rawItems: [MinecraftContentItem]
    let snapshot: SourceSnapshot?
    let lastScanDate: Date?
}

private struct PersistedItemSnapshotPayload: Codable, Sendable {
    let idPath: String
    let relativePath: String
    let modifiedDate: Date?
    let sizeBytes: Int64?
    let packUUID: String?
    let packVersion: String?

    nonisolated init(_ snapshot: ItemSnapshot) {
        self.idPath = snapshot.id.path
        self.relativePath = snapshot.relativePath
        self.modifiedDate = snapshot.modifiedDate
        self.sizeBytes = snapshot.sizeBytes
        self.packUUID = snapshot.packUUID
        self.packVersion = snapshot.packVersion
    }

    nonisolated var itemSnapshot: ItemSnapshot {
        ItemSnapshot(
            id: URL(fileURLWithPath: idPath),
            relativePath: relativePath,
            modifiedDate: modifiedDate,
            sizeBytes: sizeBytes,
            packUUID: packUUID,
            packVersion: packVersion
        )
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.idPath = try container.decode(String.self, forKey: .idPath)
        self.relativePath = try container.decode(String.self, forKey: .relativePath)
        self.modifiedDate = try container.decodeIfPresent(Date.self, forKey: .modifiedDate)
        self.sizeBytes = try container.decodeIfPresent(Int64.self, forKey: .sizeBytes)
        self.packUUID = try container.decodeIfPresent(String.self, forKey: .packUUID)
        self.packVersion = try container.decodeIfPresent(String.self, forKey: .packVersion)
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(idPath, forKey: .idPath)
        try container.encode(relativePath, forKey: .relativePath)
        try container.encodeIfPresent(modifiedDate, forKey: .modifiedDate)
        try container.encodeIfPresent(sizeBytes, forKey: .sizeBytes)
        try container.encodeIfPresent(packUUID, forKey: .packUUID)
        try container.encodeIfPresent(packVersion, forKey: .packVersion)
    }

    private enum CodingKeys: String, CodingKey {
        case idPath
        case relativePath
        case modifiedDate
        case sizeBytes
        case packUUID
        case packVersion
    }
}

private struct PersistedCollectionSnapshotPayload: Codable, Sendable {
    let folderName: String
    let modifiedDate: Date?
    let childDirectoryCount: Int
    let fingerprint: String

    nonisolated init(_ snapshot: CollectionSnapshot) {
        self.folderName = snapshot.folderName
        self.modifiedDate = snapshot.modifiedDate
        self.childDirectoryCount = snapshot.childDirectoryCount
        self.fingerprint = snapshot.fingerprint
    }

    nonisolated var collectionSnapshot: CollectionSnapshot {
        CollectionSnapshot(
            folderName: folderName,
            modifiedDate: modifiedDate,
            childDirectoryCount: childDirectoryCount,
            fingerprint: fingerprint
        )
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.folderName = try container.decode(String.self, forKey: .folderName)
        self.modifiedDate = try container.decodeIfPresent(Date.self, forKey: .modifiedDate)
        self.childDirectoryCount = try container.decode(Int.self, forKey: .childDirectoryCount)
        self.fingerprint = try container.decode(String.self, forKey: .fingerprint)
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(folderName, forKey: .folderName)
        try container.encodeIfPresent(modifiedDate, forKey: .modifiedDate)
        try container.encode(childDirectoryCount, forKey: .childDirectoryCount)
        try container.encode(fingerprint, forKey: .fingerprint)
    }

    private enum CodingKeys: String, CodingKey {
        case folderName
        case modifiedDate
        case childDirectoryCount
        case fingerprint
    }
}

private struct PersistedSourceSnapshotPayload: Codable, Sendable {
    let sourcePath: String
    let rootModifiedDate: Date?
    let collectionSnapshots: [PersistedCollectionSnapshotPayload]
    let itemSnapshots: [PersistedItemSnapshotPayload]

    nonisolated init(_ snapshot: SourceSnapshot) {
        self.sourcePath = snapshot.sourceID.path
        self.rootModifiedDate = snapshot.rootModifiedDate
        self.collectionSnapshots = snapshot.collectionSnapshots.map(PersistedCollectionSnapshotPayload.init)
        self.itemSnapshots = snapshot.itemSnapshots.map(PersistedItemSnapshotPayload.init)
    }

    nonisolated var sourceSnapshot: SourceSnapshot {
        SourceSnapshot(
            sourceID: URL(fileURLWithPath: sourcePath),
            rootModifiedDate: rootModifiedDate,
            collectionSnapshots: collectionSnapshots.map(\.collectionSnapshot),
            itemSnapshots: itemSnapshots.map(\.itemSnapshot)
        )
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sourcePath = try container.decode(String.self, forKey: .sourcePath)
        self.rootModifiedDate = try container.decodeIfPresent(Date.self, forKey: .rootModifiedDate)
        self.collectionSnapshots = try container.decode([PersistedCollectionSnapshotPayload].self, forKey: .collectionSnapshots)
        self.itemSnapshots = try container.decode([PersistedItemSnapshotPayload].self, forKey: .itemSnapshots)
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourcePath, forKey: .sourcePath)
        try container.encodeIfPresent(rootModifiedDate, forKey: .rootModifiedDate)
        try container.encode(collectionSnapshots, forKey: .collectionSnapshots)
        try container.encode(itemSnapshots, forKey: .itemSnapshots)
    }

    private enum CodingKeys: String, CodingKey {
        case sourcePath
        case rootModifiedDate
        case collectionSnapshots
        case itemSnapshots
    }
}

actor SourcePersistenceStore {
    static let shared = SourcePersistenceStore()

    private let databaseURL: URL

    init(fileManager: FileManager = .default) {
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let directoryURL = applicationSupportURL
            .appendingPathComponent("World Manager for Minecraft", isDirectory: true)
        self.databaseURL = directoryURL.appendingPathComponent("LibraryCache.sqlite", isDirectory: false)
    }

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    func loadSources() throws -> [PersistedSourceRecord] {
        let database = try openDatabase()
        defer { sqlite3_close(database) }

        let sql = """
        SELECT folder_path, display_name, raw_items_json, snapshot_json, last_scan_date
        FROM source_cache
        ORDER BY display_name COLLATE NOCASE ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError(database)
        }
        defer { sqlite3_finalize(statement) }

        var records: [PersistedSourceRecord] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let folderPathPointer = sqlite3_column_text(statement, 0) else {
                continue
            }

            let folderPath = String(cString: folderPathPointer)
            let displayName = String(cString: sqlite3_column_text(statement, 1))
            let rawItems = try decodeColumn([MinecraftContentItem].self, statement: statement, columnIndex: 2) ?? []
            let snapshotPayload = try decodeColumn(PersistedSourceSnapshotPayload.self, statement: statement, columnIndex: 3)
            let snapshot = snapshotPayload?.sourceSnapshot
            let lastScanDate = sqlite3_column_type(statement, 4) == SQLITE_NULL
                ? nil
                : Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))

            records.append(
                PersistedSourceRecord(
                    folderURL: URL(fileURLWithPath: folderPath, isDirectory: true).standardizedFileURL,
                    displayName: displayName,
                    rawItems: rawItems,
                    snapshot: snapshot,
                    lastScanDate: lastScanDate
                )
            )
        }

        return records
    }

    func save(source: MinecraftSource) throws {
        let database = try openDatabase()
        defer { sqlite3_close(database) }

        let sql = """
        INSERT INTO source_cache (
            folder_path,
            display_name,
            raw_items_json,
            snapshot_json,
            last_scan_date
        ) VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(folder_path) DO UPDATE SET
            display_name = excluded.display_name,
            raw_items_json = excluded.raw_items_json,
            snapshot_json = excluded.snapshot_json,
            last_scan_date = excluded.last_scan_date;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError(database)
        }
        defer { sqlite3_finalize(statement) }

        try bindText(source.folderURL.path, to: statement, at: 1)
        try bindText(source.displayName, to: statement, at: 2)
        try bindJSON(source.rawItems, to: statement, at: 3)
        try bindJSON(source.snapshot.map(PersistedSourceSnapshotPayload.init), to: statement, at: 4)

        if let lastScanDate = source.lastScanDate {
            sqlite3_bind_double(statement, 5, lastScanDate.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, 5)
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw databaseError(database)
        }
    }

    func deleteSource(withID sourceID: URL) throws {
        let database = try openDatabase()
        defer { sqlite3_close(database) }

        let sql = "DELETE FROM source_cache WHERE folder_path = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError(database)
        }
        defer { sqlite3_finalize(statement) }

        try bindText(sourceID.standardizedFileURL.path, to: statement, at: 1)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw databaseError(database)
        }
    }

    private func openDatabase() throws -> OpaquePointer? {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK else {
            defer { sqlite3_close(database) }
            throw databaseError(database)
        }

        try execute(
            """
            CREATE TABLE IF NOT EXISTS source_cache (
                folder_path TEXT PRIMARY KEY,
                display_name TEXT NOT NULL,
                raw_items_json BLOB NOT NULL,
                snapshot_json BLOB,
                last_scan_date REAL
            );
            """,
            on: database
        )

        return database
    }

    private func execute(_ sql: String, on database: OpaquePointer?) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw databaseError(database)
        }
    }

    private func bindText(_ value: String, to statement: OpaquePointer?, at index: Int32) throws {
        let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, index, value, -1, transientDestructor) == SQLITE_OK else {
            throw persistenceError("Failed to bind text parameter.")
        }
    }

    private func bindJSON<T: Encodable>(_ value: T, to statement: OpaquePointer?, at index: Int32) throws {
        let data = try JSONEncoder().encode(value)
        let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        let result = data.withUnsafeBytes { rawBuffer in
            sqlite3_bind_blob(statement, index, rawBuffer.baseAddress, Int32(data.count), transientDestructor)
        }

        guard result == SQLITE_OK else {
            throw persistenceError("Failed to bind JSON parameter.")
        }
    }

    private func decodeColumn<T: Decodable>(_ type: T.Type, statement: OpaquePointer?, columnIndex: Int32) throws -> T? {
        guard sqlite3_column_type(statement, columnIndex) != SQLITE_NULL else {
            return nil
        }

        let byteCount = Int(sqlite3_column_bytes(statement, columnIndex))
        guard
            byteCount > 0,
            let bytes = sqlite3_column_blob(statement, columnIndex)
        else {
            return nil
        }

        let data = Data(bytes: bytes, count: byteCount)
        return try JSONDecoder().decode(type, from: data)
    }

    private func databaseError(_ database: OpaquePointer?) -> Error {
        persistenceError(String(cString: sqlite3_errmsg(database)))
    }

    private func persistenceError(_ message: String) -> Error {
        NSError(domain: "SourcePersistenceStore", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
