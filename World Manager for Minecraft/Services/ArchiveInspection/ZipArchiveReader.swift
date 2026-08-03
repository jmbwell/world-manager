// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import zlib

nonisolated struct ZipArchiveEntry: Sendable, Hashable {
    let path: String
    let compressionMethod: UInt16
    let compressedSize: UInt32
    let uncompressedSize: UInt32
    let localHeaderOffset: UInt32
    let isDirectory: Bool
    let isSymbolicLink: Bool
}

nonisolated enum ZipArchiveReaderError: LocalizedError {
    case invalidArchive
    case unsupportedCompressionMethod(UInt16)
    case unsupportedFeatures(String)
    case unsafeEntryPath(String)
    case entryNotFound(String)
    case decompressionFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .invalidArchive:
            return "The ZIP archive is invalid or unsupported."
        case .unsupportedCompressionMethod(let method):
            return "Unsupported ZIP compression method: \(method)."
        case .unsupportedFeatures(let message):
            return message
        case .unsafeEntryPath(let path):
            return "The ZIP archive contains an unsafe entry path: \(path)"
        case .entryNotFound(let path):
            return "ZIP entry not found: \(path)"
        case .decompressionFailed(let code):
            return "ZIP decompression failed with zlib error \(code)."
        }
    }
}

nonisolated struct ZipArchiveReader {
    private let data: Data
    let entries: [ZipArchiveEntry]

    init(url: URL) throws {
        self.data = try Data(contentsOf: url, options: .mappedIfSafe)
        self.entries = try ZipArchiveReader.parseEntries(in: data)
    }

    func entry(named path: String) -> ZipArchiveEntry? {
        let normalizedPath = Self.normalizedPath(path)
        return entries.first { $0.path == normalizedPath }
    }

    func extract(_ entry: ZipArchiveEntry) throws -> Data {
        let localHeaderOffset = Int(entry.localHeaderOffset)
        guard localHeaderOffset + 30 <= data.count else {
            throw ZipArchiveReaderError.invalidArchive
        }

        guard data.readUInt32LE(at: localHeaderOffset) == 0x04034b50 else {
            throw ZipArchiveReaderError.invalidArchive
        }

        let generalPurposeFlags = data.readUInt16LE(at: localHeaderOffset + 6)
        if generalPurposeFlags & 0x0001 != 0 {
            throw ZipArchiveReaderError.unsupportedFeatures("Encrypted ZIP entries are not supported.")
        }

        let filenameLength = Int(data.readUInt16LE(at: localHeaderOffset + 26))
        let extraFieldLength = Int(data.readUInt16LE(at: localHeaderOffset + 28))
        let payloadOffset = localHeaderOffset + 30 + filenameLength + extraFieldLength
        let compressedSize = Int(entry.compressedSize)

        guard payloadOffset >= 0, payloadOffset + compressedSize <= data.count else {
            throw ZipArchiveReaderError.invalidArchive
        }

        let compressedData = data.subdata(in: payloadOffset ..< payloadOffset + compressedSize)

        switch entry.compressionMethod {
        case 0:
            guard compressedData.count == Int(entry.uncompressedSize) else {
                throw ZipArchiveReaderError.invalidArchive
            }
            return compressedData
        case 8:
            return try Self.inflateRawDeflate(compressedData, expectedSize: Int(entry.uncompressedSize))
        default:
            throw ZipArchiveReaderError.unsupportedCompressionMethod(entry.compressionMethod)
        }
    }

    private static func parseEntries(in data: Data) throws -> [ZipArchiveEntry] {
        let endOfCentralDirectoryOffset = try locateEndOfCentralDirectory(in: data)
        let totalEntries = Int(data.readUInt16LE(at: endOfCentralDirectoryOffset + 10))
        let centralDirectorySize = Int(data.readUInt32LE(at: endOfCentralDirectoryOffset + 12))
        let centralDirectoryOffset = Int(data.readUInt32LE(at: endOfCentralDirectoryOffset + 16))

        guard centralDirectoryOffset >= 0, centralDirectorySize >= 0, centralDirectoryOffset + centralDirectorySize <= data.count else {
            throw ZipArchiveReaderError.invalidArchive
        }

        var entries: [ZipArchiveEntry] = []
        var offset = centralDirectoryOffset

        for _ in 0 ..< totalEntries {
            guard offset + 46 <= data.count else {
                throw ZipArchiveReaderError.invalidArchive
            }

            guard data.readUInt32LE(at: offset) == 0x02014b50 else {
                throw ZipArchiveReaderError.invalidArchive
            }

            let compressionMethod = data.readUInt16LE(at: offset + 10)
            let compressedSize = data.readUInt32LE(at: offset + 20)
            let uncompressedSize = data.readUInt32LE(at: offset + 24)
            let filenameLength = Int(data.readUInt16LE(at: offset + 28))
            let extraFieldLength = Int(data.readUInt16LE(at: offset + 30))
            let fileCommentLength = Int(data.readUInt16LE(at: offset + 32))
            let localHeaderOffset = data.readUInt32LE(at: offset + 42)
            let externalAttributes = data.readUInt32LE(at: offset + 38)

            let filenameStart = offset + 46
            let filenameEnd = filenameStart + filenameLength
            guard filenameEnd <= data.count else {
                throw ZipArchiveReaderError.invalidArchive
            }

            let filenameData = data.subdata(in: filenameStart ..< filenameEnd)
            guard let filename = String(data: filenameData, encoding: .utf8) ?? String(data: filenameData, encoding: .isoLatin1) else {
                throw ZipArchiveReaderError.invalidArchive
            }

            try validateEntryPath(filename)
            let normalizedPath = Self.normalizedPath(filename)
            let unixMode = UInt16((externalAttributes >> 16) & 0xffff)
            entries.append(
                ZipArchiveEntry(
                    path: normalizedPath,
                    compressionMethod: compressionMethod,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localHeaderOffset,
                    isDirectory: normalizedPath.hasSuffix("/"),
                    isSymbolicLink: unixMode & 0o170000 == 0o120000
                )
            )

            offset = filenameEnd + extraFieldLength + fileCommentLength
        }

        return entries
    }

    private static func locateEndOfCentralDirectory(in data: Data) throws -> Int {
        let minimumLength = 22
        guard data.count >= minimumLength else {
            throw ZipArchiveReaderError.invalidArchive
        }

        let searchStart = max(0, data.count - (minimumLength + 65_535))
        let signature: UInt32 = 0x06054b50

        for offset in stride(from: data.count - minimumLength, through: searchStart, by: -1) {
            if data.readUInt32LE(at: offset) == signature {
                return offset
            }
        }

        throw ZipArchiveReaderError.invalidArchive
    }

    private static func normalizedPath(_ path: String) -> String {
        let replaced = path.replacingOccurrences(of: "\\", with: "/")
        let components = replaced
            .split(separator: "/")
            .filter { $0 != "." && !$0.isEmpty }
            .map(String.init)

        let trailingSlash = replaced.hasSuffix("/")
        let joined = components.joined(separator: "/")
        if trailingSlash, !joined.isEmpty {
            return joined + "/"
        }
        return joined
    }

    private static func validateEntryPath(_ path: String) throws {
        let replaced = path.replacingOccurrences(of: "\\", with: "/")
        let components = replaced.split(separator: "/", omittingEmptySubsequences: false)
        guard
            !replaced.hasPrefix("/"),
            !replaced.contains("\0"),
            !components.contains(where: { $0 == ".." })
        else {
            throw ZipArchiveReaderError.unsafeEntryPath(path)
        }
    }

    private static func inflateRawDeflate(_ data: Data, expectedSize: Int) throws -> Data {
        if data.isEmpty {
            return Data()
        }

        var stream = z_stream()
        stream.zalloc = nil
        stream.zfree = nil
        stream.opaque = nil

        let initCode = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initCode == Z_OK else {
            throw ZipArchiveReaderError.decompressionFailed(initCode)
        }

        defer {
            inflateEnd(&stream)
        }

        var output = Data()
        let chunkSize = max(expectedSize, 64 * 1024)
        var status: Int32 = Z_OK

        try data.withUnsafeBytes { compressedBytes in
            guard let compressedBase = compressedBytes.bindMemory(to: Bytef.self).baseAddress else {
                throw ZipArchiveReaderError.decompressionFailed(Z_DATA_ERROR)
            }

            stream.next_in = UnsafeMutablePointer(mutating: compressedBase)
            stream.avail_in = uInt(data.count)

            var buffer = [UInt8](repeating: 0, count: chunkSize)

            repeat {
                try buffer.withUnsafeMutableBufferPointer { bufferPointer in
                    guard let baseAddress = bufferPointer.baseAddress else {
                        throw ZipArchiveReaderError.decompressionFailed(Z_DATA_ERROR)
                    }

                    stream.next_out = baseAddress
                    stream.avail_out = uInt(bufferPointer.count)

                    status = inflate(&stream, Z_NO_FLUSH)
                    if status != Z_OK && status != Z_STREAM_END {
                        throw ZipArchiveReaderError.decompressionFailed(status)
                    }

                    let producedByteCount = bufferPointer.count - Int(stream.avail_out)
                    if producedByteCount > 0 {
                        output.append(contentsOf: bufferPointer.prefix(producedByteCount))
                        guard output.count <= expectedSize else {
                            throw ZipArchiveReaderError.invalidArchive
                        }
                    }
                }
            } while status != Z_STREAM_END
        }

        guard output.count == expectedSize else {
            throw ZipArchiveReaderError.invalidArchive
        }
        return output
    }
}

private nonisolated extension Data {
    func readUInt16LE(at offset: Int) -> UInt16 {
        return self.withUnsafeBytes { bytes in
            let base = bytes.baseAddress!.advanced(by: offset)
            return base.loadUnaligned(as: UInt16.self).littleEndian
        }
    }

    func readUInt32LE(at offset: Int) -> UInt32 {
        return self.withUnsafeBytes { bytes in
            let base = bytes.baseAddress!.advanced(by: offset)
            return base.loadUnaligned(as: UInt32.self).littleEndian
        }
    }
}
