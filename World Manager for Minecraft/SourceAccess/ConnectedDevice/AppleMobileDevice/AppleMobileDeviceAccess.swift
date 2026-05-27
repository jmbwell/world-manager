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
    let packUUID: String?
    let packVersion: String?
    let minimumEngineVersion: String?
}

struct AppleMobileDevicePathMetrics: Sendable {
    let sizeBytes: Int64?
    let modifiedDate: Date?
}

enum AppleMobileDeviceAccess {
    static func firstConnectedDevice() async throws -> AppleMobileDeviceSummary {
        try await Task.detached(priority: .userInitiated) {
            var error: NSError?
            guard let response = WMMCopyFirstConnectedDeviceSummary(&error) else {
                throw error ?? NSError(
                    domain: "AppleMobileDeviceAccess",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "No connected device could be read from MobileDevice.framework."]
                )
            }

            guard
                let deviceName = response["deviceName"] as? String,
                let deviceIdentifier = response["deviceIdentifier"] as? String,
                let productType = response["productType"] as? String,
                let productVersion = response["productVersion"] as? String,
                let trustStateRawValue = response["trustState"] as? String,
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
                trustState: trustState
            )
        }.value
    }

    static func mirrorSubtree(
        bundleIdentifier: String,
        relativePath: String,
        destinationDirectoryURL: URL
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            var error: NSError?
            let didCopy = WMMCopyFirstConnectedDeviceAppSubtreeToLocalDirectory(
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

    static func listApplications() async throws -> [AppleMobileDeviceApplicationSummary] {
        try await Task.detached(priority: .userInitiated) {
            var error: NSError?
            guard let response = WMMCopyFirstConnectedDeviceApplicationList(&error) else {
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

    static func listDirectory(
        bundleIdentifier: String,
        relativePath: String
    ) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            var error: NSError?
            guard let response = WMMCopyFirstConnectedDeviceAppDirectoryListing(
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

    static func fileData(
        bundleIdentifier: String,
        relativePath: String
    ) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            var error: NSError?
            guard let data = WMMCopyFirstConnectedDeviceAppFileData(
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

    static func minecraftLibrarySnapshot(
        bundleIdentifier: String,
        relativePath: String
    ) async throws -> [AppleMobileMinecraftLibraryItemSummary] {
        try await Task.detached(priority: .userInitiated) {
            var error: NSError?
            guard let response = WMMCopyFirstConnectedDeviceMinecraftLibrarySnapshot(
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
                    packUUID: (item["packUUID"] as? String)?.lowercased(),
                    packVersion: item["packVersion"] as? String,
                    minimumEngineVersion: item["minimumEngineVersion"] as? String
                )
            }
        }.value
    }

    static func pathMetrics(
        bundleIdentifier: String,
        relativePath: String
    ) async throws -> AppleMobileDevicePathMetrics {
        try await Task.detached(priority: .utility) {
            var error: NSError?
            guard let response = WMMCopyFirstConnectedDeviceAppPathMetrics(
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

    private static func flexibleBool(from value: Any?) -> Bool {
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
