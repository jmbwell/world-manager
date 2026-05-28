//
//  AppleMobileDeviceAccess.swift
//  World Manager for Minecraft
//
//  Created by OpenAI on 2026-05-26.
//

import Foundation

struct AppleMobileDeviceSummary: Sendable {
    let deviceName: String
    let deviceIdentifier: String
    let productType: String
    let productVersion: String
    let connectionType: String
    let trustState: DeviceTrustState
}

struct AppleMobileDeviceApplicationSummary: Sendable {
    let bundleIdentifier: String
    let displayName: String
    let fileSharingEnabled: Bool
    let supportsOpeningDocumentsInPlace: Bool
}

struct AppleMobileMinecraftLibraryItemSummary: Sendable {
    let contentType: String
    let collectionFolderName: String
    let relativePath: String
    let folderName: String
    let displayName: String
    let hasIcon: Bool
}

struct AppleMobilePackReferenceSummary: Sendable {
    let name: String
    let contentType: String
    let uuid: String?
    let version: String?
    let source: String
}

struct AppleMobileMinecraftItemMetadataSummary: Sendable {
    let relativePath: String
    let displayName: String?
    let packUUID: String?
    let packVersion: String?
    let minimumEngineVersion: String?
    let packReferences: [AppleMobilePackReferenceSummary]
}

struct AppleMobileDevicePathMetrics: Sendable {
    let sizeBytes: Int64?
    let modifiedDate: Date?
}

actor AppleMobileDeviceOperationLimiter {
    static let shared = AppleMobileDeviceOperationLimiter()

    private var activeDevices = Set<String>()
    private var waitingContinuations: [String: [CheckedContinuation<Void, Never>]] = [:]

    func run<T: Sendable>(
        for deviceIdentifier: String,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        await acquire(deviceIdentifier: deviceIdentifier)
        defer { release(deviceIdentifier: deviceIdentifier) }
        return try await operation()
    }

    private func acquire(deviceIdentifier: String) async {
        guard activeDevices.contains(deviceIdentifier) else {
            activeDevices.insert(deviceIdentifier)
            return
        }

        await withCheckedContinuation { continuation in
            waitingContinuations[deviceIdentifier, default: []].append(continuation)
        }
    }

    private func release(deviceIdentifier: String) {
        guard var queuedContinuations = waitingContinuations[deviceIdentifier], !queuedContinuations.isEmpty else {
            activeDevices.remove(deviceIdentifier)
            waitingContinuations[deviceIdentifier] = nil
            return
        }

        let continuation = queuedContinuations.removeFirst()
        waitingContinuations[deviceIdentifier] = queuedContinuations.isEmpty ? nil : queuedContinuations
        continuation.resume()
    }
}

enum AppleMobileDeviceAccess {
    static func connectedDevices() async throws -> [AppleMobileDeviceSummary] {
        try await Task.detached(priority: .userInitiated) {
            var error: NSError?
            guard let response = WMMCopyConnectedDeviceSummaries(&error) else {
                throw error ?? NSError(
                    domain: "AppleMobileDeviceAccess",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "No connected device could be read from MobileDevice.framework."]
                )
            }

            guard let rawDevices = response["devices"] as? [[String: Any]] else {
                throw NSError(
                    domain: "AppleMobileDeviceAccess",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "The MobileDevice summary returned an unexpected payload."]
                )
            }

            return try rawDevices.map { device in
                guard
                    let deviceName = device["deviceName"] as? String,
                    let deviceIdentifier = device["deviceIdentifier"] as? String,
                    let productType = device["productType"] as? String,
                    let productVersion = device["productVersion"] as? String,
                    let connectionType = device["connectionType"] as? String,
                    let trustStateRawValue = device["trustState"] as? String,
                    let trustState = DeviceTrustState(rawValue: trustStateRawValue)
                else {
                    throw NSError(
                        domain: "AppleMobileDeviceAccess",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "The MobileDevice summary returned an unexpected payload."]
                    )
                }

                return AppleMobileDeviceSummary(
                    deviceName: deviceName,
                    deviceIdentifier: deviceIdentifier,
                    productType: productType,
                    productVersion: productVersion,
                    connectionType: connectionType,
                    trustState: trustState
                )
            }
        }.value
    }

    static func mirrorSubtree(
        deviceIdentifier: String,
        bundleIdentifier: String,
        relativePath: String,
        destinationDirectoryURL: URL
    ) async throws {
        try await AppleMobileDeviceOperationLimiter.shared.run(for: deviceIdentifier) {
            try await Task.detached(priority: .userInitiated) {
                var error: NSError?
                let didCopy = WMMCopyConnectedDeviceAppSubtreeToLocalDirectory(
                    deviceIdentifier,
                    bundleIdentifier,
                    relativePath,
                    destinationDirectoryURL,
                    &error
                )

                if !didCopy {
                    throw error ?? NSError(
                        domain: "AppleMobileDeviceAccess",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "The MobileDevice subtree mirror failed."]
                    )
                }
            }.value
        }
    }

    static func listApplications(deviceIdentifier: String) async throws -> [AppleMobileDeviceApplicationSummary] {
        try await AppleMobileDeviceOperationLimiter.shared.run(for: deviceIdentifier) {
            try await Task.detached(priority: .userInitiated) {
                var error: NSError?
                guard let response = WMMCopyConnectedDeviceApplicationList(deviceIdentifier, &error) else {
                    throw error ?? NSError(
                        domain: "AppleMobileDeviceAccess",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "The MobileDevice application listing failed."]
                    )
                }

                guard let rawApplications = response["applications"] as? [[String: Any]] else {
                    throw NSError(
                        domain: "AppleMobileDeviceAccess",
                        code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "The MobileDevice application listing returned an unexpected payload."]
                    )
                }

                return rawApplications.compactMap { application in
                    guard
                        let bundleIdentifier = application["bundleIdentifier"] as? String,
                        let displayName = application["displayName"] as? String
                    else {
                        return nil
                    }

                    return AppleMobileDeviceApplicationSummary(
                        bundleIdentifier: bundleIdentifier,
                        displayName: displayName,
                        fileSharingEnabled: flexibleBool(from: application["uiFileSharingEnabled"]),
                        supportsOpeningDocumentsInPlace: flexibleBool(from: application["supportsOpeningDocumentsInPlace"])
                    )
                }
            }.value
        }
    }

    static func listDirectory(
        deviceIdentifier: String,
        bundleIdentifier: String,
        relativePath: String
    ) async throws -> [String] {
        try await AppleMobileDeviceOperationLimiter.shared.run(for: deviceIdentifier) {
            try await Task.detached(priority: .userInitiated) {
                var error: NSError?
                guard let response = WMMCopyConnectedDeviceAppDirectoryListing(
                    deviceIdentifier,
                    bundleIdentifier,
                    relativePath,
                    &error
                ) else {
                    throw error ?? NSError(
                        domain: "AppleMobileDeviceAccess",
                        code: 7,
                        userInfo: [NSLocalizedDescriptionKey: "The MobileDevice directory listing failed."]
                    )
                }

                return (response["entries"] as? [String] ?? []).filter { $0 != "." && $0 != ".." }
            }.value
        }
    }

    static func fileData(
        deviceIdentifier: String,
        bundleIdentifier: String,
        relativePath: String
    ) async throws -> Data {
        try await AppleMobileDeviceOperationLimiter.shared.run(for: deviceIdentifier) {
            try await Task.detached(priority: .userInitiated) {
                var error: NSError?
                guard let data = WMMCopyConnectedDeviceAppFileData(
                    deviceIdentifier,
                    bundleIdentifier,
                    relativePath,
                    &error
                ) else {
                    throw error ?? NSError(
                        domain: "AppleMobileDeviceAccess",
                        code: 8,
                        userInfo: [NSLocalizedDescriptionKey: "The MobileDevice file read failed."]
                    )
                }

                return data as Data
            }.value
        }
    }

    static func minecraftLibrarySnapshot(
        deviceIdentifier: String,
        bundleIdentifier: String,
        relativePath: String
    ) async throws -> [AppleMobileMinecraftLibraryItemSummary] {
        try await AppleMobileDeviceOperationLimiter.shared.run(for: deviceIdentifier) {
            try await Task.detached(priority: .userInitiated) {
                var error: NSError?
                guard let response = WMMCopyConnectedDeviceMinecraftLibrarySnapshot(
                    deviceIdentifier,
                    bundleIdentifier,
                    relativePath,
                    &error
                ) else {
                    throw error ?? NSError(
                        domain: "AppleMobileDeviceAccess",
                        code: 5,
                        userInfo: [NSLocalizedDescriptionKey: "The MobileDevice Minecraft library scan failed."]
                    )
                }

                guard let rawItems = response["items"] as? [[String: Any]] else {
                    throw NSError(
                        domain: "AppleMobileDeviceAccess",
                        code: 6,
                        userInfo: [NSLocalizedDescriptionKey: "The MobileDevice Minecraft library scan returned an unexpected payload."]
                    )
                }

                return rawItems.compactMap { item in
                    guard
                        let contentType = item["contentType"] as? String,
                        let collectionFolderName = item["collectionFolderName"] as? String,
                        let relativePath = item["relativePath"] as? String,
                        let folderName = item["folderName"] as? String,
                        let displayName = item["displayName"] as? String
                    else {
                        return nil
                    }

                    return AppleMobileMinecraftLibraryItemSummary(
                        contentType: contentType,
                        collectionFolderName: collectionFolderName,
                        relativePath: relativePath,
                        folderName: folderName,
                        displayName: displayName,
                        hasIcon: flexibleBool(from: item["hasIcon"])
                    )
                }
            }.value
        }
    }

    static func minecraftMetadataBatch(
        deviceIdentifier: String,
        bundleIdentifier: String,
        relativePath: String,
        items: [AppleMobileMinecraftLibraryItemSummary]
    ) async throws -> [AppleMobileMinecraftItemMetadataSummary] {
        try await AppleMobileDeviceOperationLimiter.shared.run(for: deviceIdentifier) {
            try await Task.detached(priority: .userInitiated) {
                let requestItems = items.map { item in
                    [
                        "contentType": item.contentType,
                        "relativePath": item.relativePath,
                        "folderName": item.folderName
                    ]
                }

                var error: NSError?
                guard let response = WMMCopyConnectedDeviceMinecraftMetadataBatch(
                    deviceIdentifier,
                    bundleIdentifier,
                    relativePath,
                    requestItems,
                    &error
                ) else {
                    throw error ?? NSError(
                        domain: "AppleMobileDeviceAccess",
                        code: 10,
                        userInfo: [NSLocalizedDescriptionKey: "The MobileDevice metadata batch failed."]
                    )
                }

                guard let rawItems = response["items"] as? [[String: Any]] else {
                    throw NSError(
                        domain: "AppleMobileDeviceAccess",
                        code: 11,
                        userInfo: [NSLocalizedDescriptionKey: "The MobileDevice metadata batch returned an unexpected payload."]
                    )
                }

                return rawItems.compactMap { item in
                    guard let relativePath = item["relativePath"] as? String else {
                        return nil
                    }

                    return AppleMobileMinecraftItemMetadataSummary(
                        relativePath: relativePath,
                        displayName: item["displayName"] as? String,
                        packUUID: (item["packUUID"] as? String)?.lowercased(),
                        packVersion: item["packVersion"] as? String,
                        minimumEngineVersion: item["minimumEngineVersion"] as? String,
                        packReferences: (item["packReferences"] as? [[String: Any]] ?? []).compactMap { reference in
                            guard
                                let name = reference["name"] as? String,
                                let contentType = reference["contentType"] as? String,
                                let source = reference["source"] as? String
                            else {
                                return nil
                            }

                            return AppleMobilePackReferenceSummary(
                                name: name,
                                contentType: contentType,
                                uuid: (reference["uuid"] as? String)?.lowercased(),
                                version: reference["version"] as? String,
                                source: source
                            )
                        }
                    )
                }
            }.value
        }
    }

    static func pathMetrics(
        deviceIdentifier: String,
        bundleIdentifier: String,
        relativePath: String
    ) async throws -> AppleMobileDevicePathMetrics {
        try await AppleMobileDeviceOperationLimiter.shared.run(for: deviceIdentifier) {
            try await Task.detached(priority: .utility) {
                var error: NSError?
                guard let response = WMMCopyConnectedDeviceAppPathMetrics(
                    deviceIdentifier,
                    bundleIdentifier,
                    relativePath,
                    &error
                ) else {
                    throw error ?? NSError(
                        domain: "AppleMobileDeviceAccess",
                        code: 9,
                        userInfo: [NSLocalizedDescriptionKey: "The MobileDevice path metrics lookup failed."]
                    )
                }

                let rawSize = response["sizeBytes"]
                let sizeBytes: Int64?
                switch rawSize {
                case let number as NSNumber:
                    sizeBytes = number.int64Value
                case let value as Int64:
                    sizeBytes = value
                case let value as Int:
                    sizeBytes = Int64(value)
                default:
                    sizeBytes = nil
                }

                return AppleMobileDevicePathMetrics(
                    sizeBytes: sizeBytes,
                    modifiedDate: response["modifiedDate"] as? Date
                )
            }.value
        }
    }

    nonisolated private static func flexibleBool(from value: Any?) -> Bool {
        switch value {
        case let value as Bool:
            return value
        case let value as NSNumber:
            return value.boolValue
        case let value as NSString:
            return value.boolValue
        case let value as String:
            return NSString(string: value).boolValue
        default:
            return false
        }
    }
}
