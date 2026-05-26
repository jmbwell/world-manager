//
//  SourceOrigin.swift
//  World Manager for Minecraft
//
//  Created by OpenAI on 2026-05-26.
//

import Foundation

struct ConnectedDevice: Identifiable, Hashable, Sendable, Codable {
    let udid: String
    var name: String
    var productType: String?
    var osVersion: String?
    var connection: DeviceConnection
    var trustState: DeviceTrustState

    var id: String { udid }
}

enum DeviceConnection: String, Hashable, Sendable, Codable {
    case usb
    case network
}

enum DeviceTrustState: String, Hashable, Sendable, Codable {
    case unavailable
    case locked
    case untrusted
    case trusted
}

struct DeviceAppContainer: Identifiable, Hashable, Sendable, Codable {
    let deviceUDID: String
    let appID: String
    var appName: String
    var accessMode: DeviceContainerAccessMode
    var minecraftFolderRelativePath: String?

    var id: String {
        [deviceUDID, appID, accessMode.rawValue].joined(separator: "::")
    }
}

enum DeviceContainerAccessMode: String, Hashable, Sendable, Codable {
    case documents
    case container
}

enum MinecraftSourceOrigin: Hashable, Sendable, Codable {
    case localFolder(bookmarkData: Data?)
    case connectedDevice(device: ConnectedDevice, container: DeviceAppContainer)

    var kind: MinecraftSourceKind {
        switch self {
        case .localFolder:
            return .localFolder
        case .connectedDevice:
            return .connectedDevice
        }
    }
}

enum MinecraftSourceKind: String, Hashable, Sendable, Codable {
    case localFolder
    case connectedDevice
}

struct PreparedScanRoot: Hashable, Sendable {
    let sourceID: URL
    let rootURL: URL
    let mountPointURL: URL?
    let cleanupBehavior: CleanupBehavior

    enum CleanupBehavior: Hashable, Sendable {
        case none
        case unmount
        case deleteTemporaryDirectory
    }
}
