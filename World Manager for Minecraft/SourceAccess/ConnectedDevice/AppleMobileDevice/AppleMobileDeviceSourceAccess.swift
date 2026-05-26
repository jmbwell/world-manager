//
//  AppleMobileDeviceSourceAccess.swift
//  World Manager for Minecraft
//
//  Created by OpenAI on 2026-05-26.
//

import Foundation

struct AppleMobileDeviceSourceAccess: ConnectedDeviceSourceAccessMethod {
    private let mirrorRootURL: URL

    nonisolated init(
        mirrorRootURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorldManagerConnectedDevices", isDirectory: true)
    ) {
        self.mirrorRootURL = mirrorRootURL
    }

    nonisolated func listConnectedDevices() async throws -> [ConnectedDevice] {
        let device = try await AppleMobileDeviceAccess.firstConnectedDevice()
        return [
            ConnectedDevice(
                udid: device.deviceIdentifier,
                name: device.deviceName,
                productType: device.productType.isEmpty ? nil : device.productType,
                osVersion: device.productVersion.isEmpty ? nil : device.productVersion,
                connection: .usb,
                trustState: device.trustState
            )
        ]
    }

    nonisolated func listAccessibleContainers(for device: ConnectedDevice) async throws -> [DeviceAppContainer] {
        let applications = try await AppleMobileDeviceAccess.listApplications()

        return applications
            .filter { $0.fileSharingEnabled }
            .map { application in
                DeviceAppContainer(
                    deviceUDID: device.udid,
                    appID: application.bundleIdentifier,
                    appName: application.displayName,
                    accessMode: .documents,
                    minecraftFolderRelativePath: application.bundleIdentifier == "com.mojang.minecraftpe"
                        ? "Documents/games/com.mojang"
                        : nil
                )
            }
            .sorted { lhs, rhs in
                if lhs.appID == "com.mojang.minecraftpe" {
                    return true
                }
                if rhs.appID == "com.mojang.minecraftpe" {
                    return false
                }
                return lhs.appName.localizedStandardCompare(rhs.appName) == .orderedAscending
            }
    }

    nonisolated func prepareScanRoot(for source: MinecraftSource) async throws -> PreparedScanRoot {
        guard case .connectedDevice(_, let container) = source.origin else {
            throw SourceAccessError.accessFailed(
                reason: "The selected source is not backed by a connected mobile device."
            )
        }

        let requestedSubpath = container.minecraftFolderRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !requestedSubpath.isEmpty else {
            throw SourceAccessError.accessFailed(
                reason: "A device-backed source requires a vend-relative Minecraft path."
            )
        }

        let fileManager = FileManager.default
        let mirrorURL = mirrorRootURL
            .appendingPathComponent(container.deviceUDID, isDirectory: true)
            .appendingPathComponent(container.appID.replacingOccurrences(of: ".", with: "_"), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        do {
            try fileManager.createDirectory(at: mirrorURL, withIntermediateDirectories: true)
            try await AppleMobileDeviceAccess.mirrorSubtree(
                bundleIdentifier: container.appID,
                relativePath: requestedSubpath,
                destinationDirectoryURL: mirrorURL
            )
        } catch {
            try? fileManager.removeItem(at: mirrorURL)
            throw SourceAccessError.accessFailed(reason: error.localizedDescription)
        }

        return PreparedScanRoot(
            sourceID: source.id,
            rootURL: mirrorURL,
            mountPointURL: mirrorURL,
            cleanupBehavior: .deleteTemporaryDirectory
        )
    }

    nonisolated func releaseScanRoot(_ preparedScanRoot: PreparedScanRoot) async {
        guard case .deleteTemporaryDirectory = preparedScanRoot.cleanupBehavior,
              let mountPointURL = preparedScanRoot.mountPointURL else {
            return
        }

        try? FileManager.default.removeItem(at: mountPointURL)
    }
}
