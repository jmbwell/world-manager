//
//  SourcePersistenceStore.swift
//  World Manager for Minecraft
//
//  Created by OpenAI on 2026-05-25.
//

import Foundation
import SQLite3

struct PersistedSourceRecord: Sendable {
    let sourceID: URL
    let folderURL: URL
    let origin: MinecraftSourceOrigin
    let accessDescriptor: SourceAccessDescriptor
    let availability: SourceAvailability
    let bookmarkData: Data?
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
    let sourceIdentifier: String
    let rootModifiedDate: Date?
    let collectionSnapshots: [PersistedCollectionSnapshotPayload]
    let itemSnapshots: [PersistedItemSnapshotPayload]

    nonisolated init(_ snapshot: SourceSnapshot) {
        self.sourceIdentifier = snapshot.sourceID.absoluteString
        self.rootModifiedDate = snapshot.rootModifiedDate
        self.collectionSnapshots = snapshot.collectionSnapshots.map(PersistedCollectionSnapshotPayload.init)
        self.itemSnapshots = snapshot.itemSnapshots.map(PersistedItemSnapshotPayload.init)
    }

    nonisolated var sourceSnapshot: SourceSnapshot {
        SourceSnapshot(
            sourceID: URL(string: sourceIdentifier) ?? URL(fileURLWithPath: sourceIdentifier),
            rootModifiedDate: rootModifiedDate,
            collectionSnapshots: collectionSnapshots.map(\.collectionSnapshot),
            itemSnapshots: itemSnapshots.map(\.itemSnapshot)
        )
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sourceIdentifier = try container.decode(String.self, forKey: .sourceIdentifier)
        self.rootModifiedDate = try container.decodeIfPresent(Date.self, forKey: .rootModifiedDate)
        self.collectionSnapshots = try container.decode([PersistedCollectionSnapshotPayload].self, forKey: .collectionSnapshots)
        self.itemSnapshots = try container.decode([PersistedItemSnapshotPayload].self, forKey: .itemSnapshots)
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceIdentifier, forKey: .sourceIdentifier)
        try container.encodeIfPresent(rootModifiedDate, forKey: .rootModifiedDate)
        try container.encode(collectionSnapshots, forKey: .collectionSnapshots)
        try container.encode(itemSnapshots, forKey: .itemSnapshots)
    }

    private enum CodingKeys: String, CodingKey {
        case sourceIdentifier
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
        SELECT source_id, folder_path, origin_json, access_descriptor_json, availability_state,
               bookmark_data, display_name, raw_items_json, snapshot_json, last_scan_date
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
            guard let folderPathPointer = sqlite3_column_text(statement, 1) else {
                continue
            }

            let sourceID = sourceID(from: statement) ?? URL(fileURLWithPath: String(cString: folderPathPointer)).standardizedFileURL
            let folderPath = String(cString: folderPathPointer)
            let origin = try decodeColumn(MinecraftSourceOrigin.self, statement: statement, columnIndex: 2)
                ?? .localFolder(bookmarkData: nil)
            let accessDescriptor = try decodeColumn(SourceAccessDescriptor.self, statement: statement, columnIndex: 3)
                ?? SourceAccessDescriptor(
                    accessorIdentifier: origin.defaultAccessorIdentifier,
                    kind: origin.kind,
                    capabilities: origin.defaultCapabilities,
                    refreshStrategy: origin.defaultRefreshStrategy
                )
            let availability = decodeAvailability(statement: statement, columnIndex: 4)
            let bookmarkData = decodeDataColumn(statement: statement, columnIndex: 5)
            let displayName = String(cString: sqlite3_column_text(statement, 6))
            let rawItems = try decodeColumn([MinecraftContentItem].self, statement: statement, columnIndex: 7) ?? []
            let snapshotPayload = try decodeColumn(PersistedSourceSnapshotPayload.self, statement: statement, columnIndex: 8)
            let snapshot = snapshotPayload?.sourceSnapshot
            let lastScanDate = sqlite3_column_type(statement, 9) == SQLITE_NULL
                ? nil
                : Date(timeIntervalSince1970: sqlite3_column_double(statement, 9))

            records.append(
                PersistedSourceRecord(
                    sourceID: sourceID,
                    folderURL: URL(fileURLWithPath: folderPath, isDirectory: true).standardizedFileURL,
                    origin: origin,
                    accessDescriptor: accessDescriptor,
                    availability: availability,
                    bookmarkData: bookmarkData,
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
            source_id,
            folder_path,
            origin_json,
            access_descriptor_json,
            availability_state,
            bookmark_data,
            display_name,
            raw_items_json,
            snapshot_json,
            last_scan_date
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(source_id) DO UPDATE SET
            bookmark_data = excluded.bookmark_data,
            folder_path = excluded.folder_path,
            origin_json = excluded.origin_json,
            access_descriptor_json = excluded.access_descriptor_json,
            availability_state = excluded.availability_state,
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

        try bindText(normalizedIdentifierText(for: source.id), to: statement, at: 1)
        try bindText(source.folderURL.path, to: statement, at: 2)
        try bindJSON(source.origin, to: statement, at: 3)
        try bindJSON(source.accessDescriptor, to: statement, at: 4)
        try bindText(source.availability.rawValue, to: statement, at: 5)
        try bindData(source.bookmarkData, to: statement, at: 6)
        try bindText(source.displayName, to: statement, at: 7)
        try bindJSON(source.rawItems, to: statement, at: 8)
        try bindJSON(source.snapshot.map(PersistedSourceSnapshotPayload.init), to: statement, at: 9)

        if let lastScanDate = source.lastScanDate {
            sqlite3_bind_double(statement, 10, lastScanDate.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, 10)
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw databaseError(database)
        }
    }

    func deleteSource(withID sourceID: URL) throws {
        let database = try openDatabase()
        defer { sqlite3_close(database) }

        let sql = "DELETE FROM source_cache WHERE source_id = ? OR folder_path = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError(database)
        }
        defer { sqlite3_finalize(statement) }

        try bindText(normalizedIdentifierText(for: sourceID), to: statement, at: 1)
        try bindText(sourceID.isFileURL ? sourceID.standardizedFileURL.path : sourceID.path, to: statement, at: 2)

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
                source_id TEXT,
                folder_path TEXT PRIMARY KEY,
                origin_json BLOB,
                access_descriptor_json BLOB,
                availability_state TEXT,
                bookmark_data BLOB,
                display_name TEXT NOT NULL,
                raw_items_json BLOB NOT NULL,
                snapshot_json BLOB,
                last_scan_date REAL
            );
            """,
            on: database
        )
        let existingColumns = try columns(in: "source_cache", on: database)
        try addColumnIfNeeded("bookmark_data", sql: "ALTER TABLE source_cache ADD COLUMN bookmark_data BLOB;", existingColumns: existingColumns, on: database)
        try addColumnIfNeeded("source_id", sql: "ALTER TABLE source_cache ADD COLUMN source_id TEXT;", existingColumns: existingColumns, on: database)
        try addColumnIfNeeded("origin_json", sql: "ALTER TABLE source_cache ADD COLUMN origin_json BLOB;", existingColumns: existingColumns, on: database)
        try addColumnIfNeeded("access_descriptor_json", sql: "ALTER TABLE source_cache ADD COLUMN access_descriptor_json BLOB;", existingColumns: existingColumns, on: database)
        try addColumnIfNeeded("availability_state", sql: "ALTER TABLE source_cache ADD COLUMN availability_state TEXT;", existingColumns: existingColumns, on: database)
        try execute(
            """
            UPDATE source_cache
            SET source_id = folder_path
            WHERE source_id IS NULL OR source_id = '';
            """,
            on: database
        )
        try execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS source_cache_source_id_idx ON source_cache(source_id);",
            on: database
        )

        return database
    }

    private func columns(in tableName: String, on database: OpaquePointer?) throws -> Set<String> {
        let sql = "PRAGMA table_info(\(tableName));"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError(database)
        }
        defer { sqlite3_finalize(statement) }

        var columns = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let namePointer = sqlite3_column_text(statement, 1) {
                columns.insert(String(cString: namePointer))
            }
        }

        return columns
    }

    private func addColumnIfNeeded(
        _ columnName: String,
        sql: String,
        existingColumns: Set<String>,
        on database: OpaquePointer?
    ) throws {
        guard !existingColumns.contains(columnName) else {
            return
        }

        try execute(sql, on: database)
    }

    private func execute(_ sql: String, on database: OpaquePointer?, ignoringDuplicateColumn: Bool = false) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            if ignoringDuplicateColumn,
               let database,
               String(cString: sqlite3_errmsg(database)).localizedCaseInsensitiveContains("duplicate column name") {
                return
            }
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
        try bindData(data, to: statement, at: index)
    }

    private func bindData(_ value: Data?, to statement: OpaquePointer?, at index: Int32) throws {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }

        let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        let result = value.withUnsafeBytes { rawBuffer in
            sqlite3_bind_blob(statement, index, rawBuffer.baseAddress, Int32(value.count), transientDestructor)
        }

        guard result == SQLITE_OK else {
            throw persistenceError("Failed to bind data parameter.")
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

    private func decodeDataColumn(statement: OpaquePointer?, columnIndex: Int32) -> Data? {
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

        return Data(bytes: bytes, count: byteCount)
    }

    private func sourceID(from statement: OpaquePointer?) -> URL? {
        guard let pointer = sqlite3_column_text(statement, 0) else {
            return nil
        }

        let value = String(cString: pointer)
        return URL(string: value) ?? URL(fileURLWithPath: value)
    }

    private func decodeAvailability(statement: OpaquePointer?, columnIndex: Int32) -> SourceAvailability {
        guard
            let pointer = sqlite3_column_text(statement, columnIndex),
            let availability = SourceAvailability(rawValue: String(cString: pointer))
        else {
            return .unknown
        }

        return availability
    }

    private func normalizedIdentifierText(for sourceID: URL) -> String {
        if sourceID.isFileURL {
            return sourceID.standardizedFileURL.absoluteString
        }

        return sourceID.standardized.absoluteString
    }

    private func databaseError(_ database: OpaquePointer?) -> Error {
        persistenceError(String(cString: sqlite3_errmsg(database)))
    }

    private func persistenceError(_ message: String) -> Error {
        NSError(domain: "SourcePersistenceStore", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
