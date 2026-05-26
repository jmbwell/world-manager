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
                    fileSharingEnabled: application["uiFileSharingEnabled"] as? Bool ?? false,
                    supportsOpeningDocumentsInPlace: application["supportsOpeningDocumentsInPlace"] as? Bool ?? false
                )
            }
        }.value
    }
}
