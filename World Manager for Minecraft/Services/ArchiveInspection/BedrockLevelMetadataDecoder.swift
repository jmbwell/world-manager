import Foundation

enum BedrockLevelMetadataDecoder {
    nonisolated static func decode(fromLevelDatAt url: URL) -> WorldMetadata? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        return decode(fromLevelDatData: data)
    }

    nonisolated static func decode(fromLevelDatData data: Data) -> WorldMetadata? {
        guard data.count > 8 else {
            return nil
        }

        let payloadLength = Int(readInt32LE(from: data, offset: 4))
        let payloadStart = 8
        let payloadEnd = min(data.count, payloadStart + max(0, payloadLength))
        guard payloadEnd > payloadStart else {
            return nil
        }

        let payload = data.subdata(in: payloadStart..<payloadEnd)
        var decoder = BedrockNBTDecoder(data: payload)
        guard let root = try? decoder.decodeRootCompound() else {
            return nil
        }

        return worldMetadata(from: root)
    }

    nonisolated private static func worldMetadata(from root: [String: NBTValue]) -> WorldMetadata {
        let gameModeCode = root["GameType"]?.intValue
        let difficultyCode = root["Difficulty"]?.intValue
        let spawn = formattedSpawn(from: root)
        let lastPlayedRaw = root["LastPlayed"]?.longValue
        let lastPlayedDate = lastPlayedRaw.map(dateFromBedrockTimestamp(_:))

        return WorldMetadata(
            gameMode: gameModeCode.map(gameModeName(for:)),
            difficulty: difficultyCode.map(difficultyName(for:)),
            seed: root["RandomSeed"]?.stringifiedScalar,
            lastPlayedDate: lastPlayedDate,
            lastOpenedWithVersion: versionString(from: root["lastOpenedWithVersion"] ?? root["MinimumCompatibleClientVersion"]),
            inventoryVersion: versionString(from: root["InventoryVersion"]),
            cheatsEnabled: root["cheatsEnabled"]?.boolValue,
            commandsEnabled: root["commandsEnabled"]?.boolValue,
            educationFeaturesEnabled: root["educationFeaturesEnabled"]?.boolValue ?? root["eduLevel"]?.boolValue,
            coordinatesShown: root["showcoordinates"]?.boolValue,
            keepInventory: root["keepinventory"]?.boolValue,
            mobGriefingEnabled: root["mobgriefing"]?.boolValue,
            daylightCycleEnabled: root["dodaylightcycle"]?.boolValue,
            weatherCycleEnabled: root["doweathercycle"]?.boolValue,
            spawn: spawn,
            storageVersion: root["StorageVersion"]?.stringifiedScalar,
            networkVersion: root["NetworkVersion"]?.stringifiedScalar
        )
    }

    nonisolated private static func gameModeName(for value: Int) -> String {
        switch value {
        case 0:
            return "Survival"
        case 1:
            return "Creative"
        case 2:
            return "Adventure"
        case 3:
            return "Spectator"
        default:
            return String(value)
        }
    }

    nonisolated private static func difficultyName(for value: Int) -> String {
        switch value {
        case 0:
            return "Peaceful"
        case 1:
            return "Easy"
        case 2:
            return "Normal"
        case 3:
            return "Hard"
        default:
            return String(value)
        }
    }

    nonisolated private static func formattedSpawn(from root: [String: NBTValue]) -> String? {
        guard
            let x = root["SpawnX"]?.intValue,
            let y = root["SpawnY"]?.intValue,
            let z = root["SpawnZ"]?.intValue
        else {
            return nil
        }

        return "\(x), \(y), \(z)"
    }

    nonisolated private static func versionString(from value: NBTValue?) -> String? {
        guard let value else {
            return nil
        }

        switch value {
        case .string(let string):
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case .list(_, let values):
            let components = values.compactMap(\.intValue).map(String.init)
            return components.isEmpty ? nil : components.joined(separator: ".")
        case .intArray(let values):
            return values.isEmpty ? nil : values.map(String.init).joined(separator: ".")
        case .byteArray(let values):
            return values.isEmpty ? nil : values.map(String.init).joined(separator: ".")
        default:
            return value.stringifiedScalar
        }
    }

    nonisolated private static func dateFromBedrockTimestamp(_ value: Int64) -> Date {
        if value > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: TimeInterval(value) / 1000)
        }

        return Date(timeIntervalSince1970: TimeInterval(value))
    }

    nonisolated private static func readInt32LE(from data: Data, offset: Int) -> Int32 {
        let range = offset..<(offset + 4)
        return data.subdata(in: range).withUnsafeBytes { buffer in
            Int32(littleEndian: buffer.loadUnaligned(as: Int32.self))
        }
    }
}

private enum NBTValue: Hashable, Sendable {
    case byte(Int8)
    case short(Int16)
    case int(Int32)
    case long(Int64)
    case float(Float)
    case double(Double)
    case byteArray([Int8])
    case string(String)
    case list(UInt8, [NBTValue])
    case compound([String: NBTValue])
    case intArray([Int32])
    case longArray([Int64])

    nonisolated var intValue: Int? {
        switch self {
        case .byte(let value):
            return Int(value)
        case .short(let value):
            return Int(value)
        case .int(let value):
            return Int(value)
        case .long(let value):
            return Int(value)
        default:
            return nil
        }
    }

    nonisolated var longValue: Int64? {
        switch self {
        case .byte(let value):
            return Int64(value)
        case .short(let value):
            return Int64(value)
        case .int(let value):
            return Int64(value)
        case .long(let value):
            return value
        default:
            return nil
        }
    }

    nonisolated var boolValue: Bool? {
        intValue.map { $0 != 0 }
    }

    nonisolated var stringifiedScalar: String? {
        switch self {
        case .string(let value):
            return value
        case .byte(let value):
            return String(value)
        case .short(let value):
            return String(value)
        case .int(let value):
            return String(value)
        case .long(let value):
            return String(value)
        default:
            return nil
        }
    }
}

private struct BedrockNBTDecoder {
    private let data: Data
    private var offset = 0

    nonisolated init(data: Data) {
        self.data = data
    }

    nonisolated mutating func decodeRootCompound() throws -> [String: NBTValue] {
        let rootType = try readUInt8()
        guard rootType == 10 else {
            throw BedrockNBTError.invalidRootTag
        }

        _ = try readString()
        return try readCompoundPayload()
    }

    nonisolated private mutating func readCompoundPayload() throws -> [String: NBTValue] {
        var result: [String: NBTValue] = [:]

        while true {
            let tagType = try readUInt8()
            if tagType == 0 {
                return result
            }

            let name = try readString()
            result[name] = try readTagPayload(type: tagType)
        }
    }

    nonisolated private mutating func readTagPayload(type: UInt8) throws -> NBTValue {
        switch type {
        case 1:
            return .byte(try readInt8())
        case 2:
            return .short(try readInt16())
        case 3:
            return .int(try readInt32())
        case 4:
            return .long(try readInt64())
        case 5:
            return .float(try readFloat())
        case 6:
            return .double(try readDouble())
        case 7:
            let count = try readCount()
            return .byteArray(try (0..<count).map { _ in try readInt8() })
        case 8:
            return .string(try readString())
        case 9:
            let listType = try readUInt8()
            let count = try readCount()
            let values = try (0..<count).map { _ in try readTagPayload(type: listType) }
            return .list(listType, values)
        case 10:
            return .compound(try readCompoundPayload())
        case 11:
            let count = try readCount()
            return .intArray(try (0..<count).map { _ in try readInt32() })
        case 12:
            let count = try readCount()
            return .longArray(try (0..<count).map { _ in try readInt64() })
        default:
            throw BedrockNBTError.unsupportedTag(type)
        }
    }

    nonisolated private mutating func readCount() throws -> Int {
        let count = try readInt32()
        guard count >= 0 else {
            throw BedrockNBTError.invalidLength
        }
        return Int(count)
    }

    nonisolated private mutating func readUInt8() throws -> UInt8 {
        guard offset + 1 <= data.count else {
            throw BedrockNBTError.outOfBounds
        }

        defer { offset += 1 }
        return data[offset]
    }

    nonisolated private mutating func readInt8() throws -> Int8 {
        Int8(bitPattern: try readUInt8())
    }

    nonisolated private mutating func readInt16() throws -> Int16 {
        try readScalar(Int16.self)
    }

    nonisolated private mutating func readInt32() throws -> Int32 {
        try readScalar(Int32.self)
    }

    nonisolated private mutating func readInt64() throws -> Int64 {
        try readScalar(Int64.self)
    }

    nonisolated private mutating func readFloat() throws -> Float {
        let raw = try readScalar(UInt32.self)
        return Float(bitPattern: raw)
    }

    nonisolated private mutating func readDouble() throws -> Double {
        let raw = try readScalar(UInt64.self)
        return Double(bitPattern: raw)
    }

    nonisolated private mutating func readString() throws -> String {
        let length = Int(try readUInt16())
        guard offset + length <= data.count else {
            throw BedrockNBTError.outOfBounds
        }

        let stringData = data.subdata(in: offset..<(offset + length))
        offset += length
        return String(decoding: stringData, as: UTF8.self)
    }

    nonisolated private mutating func readUInt16() throws -> UInt16 {
        try readScalar(UInt16.self)
    }

    nonisolated private mutating func readScalar<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        let byteCount = MemoryLayout<T>.size
        guard offset + byteCount <= data.count else {
            throw BedrockNBTError.outOfBounds
        }

        let value = data.subdata(in: offset..<(offset + byteCount)).withUnsafeBytes { buffer in
            T(littleEndian: buffer.loadUnaligned(as: T.self))
        }
        offset += byteCount
        return value
    }
}

private enum BedrockNBTError: Error {
    case invalidRootTag
    case invalidLength
    case outOfBounds
    case unsupportedTag(UInt8)
}
