// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

nonisolated struct ConnectedDevice: Identifiable, Hashable, Sendable, Codable {
    let udid: String
    var name: String
    var productType: String?
    var osVersion: String?
    var connection: DeviceConnection
    var trustState: DeviceTrustState

    var id: String { udid }
}

nonisolated enum DeviceConnection: String, Hashable, Sendable, Codable {
    case usb
    case network
}

nonisolated enum DeviceTrustState: String, Hashable, Sendable, Codable {
    case unavailable
    case locked
    case untrusted
    case trusted
}

nonisolated struct DeviceAppContainer: Identifiable, Hashable, Sendable, Codable {
    let deviceUDID: String
    let appID: String
    var appName: String
    var accessMode: DeviceContainerAccessMode
    var minecraftFolderRelativePath: String?

    var id: String {
        [deviceUDID, appID, accessMode.rawValue].joined(separator: "::")
    }
}

nonisolated enum DeviceContainerAccessMode: String, Hashable, Sendable, Codable {
    case documents
    case container
}

nonisolated enum MinecraftSourceOrigin: Hashable, Sendable, Codable {
    case localFolder(bookmarkData: Data?)
    case javaLocalFolder(bookmarkData: Data?)
    case connectedDevice(device: ConnectedDevice, container: DeviceAppContainer)

    nonisolated var defaultAccessorIdentifier: SourceAccessorIdentifier {
        switch self {
        case .localFolder:
            return LocalFolderSourceAccess().accessorIdentifier
        case .javaLocalFolder:
            return JavaLocalFolderSourceAccess().accessorIdentifier
        case .connectedDevice:
            return AppleMobileDeviceSourceAccess().accessorIdentifier
        }
    }

    nonisolated var defaultEdition: MinecraftEdition {
        switch self {
        case .localFolder, .connectedDevice:
            return .bedrock
        case .javaLocalFolder:
            return .java
        }
    }

    nonisolated var kind: MinecraftSourceKind {
        switch self {
        case .localFolder, .javaLocalFolder:
            return .localFolder
        case .connectedDevice:
            return .connectedDevice
        }
    }

    nonisolated var defaultRefreshStrategy: SourceRefreshStrategy {
        switch self {
        case .localFolder, .javaLocalFolder:
            return .eagerFullScan
        case .connectedDevice:
            return .staged
        }
    }

    nonisolated var defaultCapabilities: SourceCapabilities {
        switch self {
        case .localFolder, .javaLocalFolder:
            return .localFolder
        case .connectedDevice:
            return .connectedDevice
        }
    }

    nonisolated func defaultAccessStatus(displayName: String) -> SourceAccessStatus {
        switch self {
        case .localFolder(let bookmarkData), .javaLocalFolder(let bookmarkData):
            return SourceAccessStatus(
                availability: .unknown,
                mode: bookmarkData == nil ? .localFileSystem : .securityScopedLocalFolder,
                displayName: displayName,
                iconSystemName: "folder",
                statusText: nil,
                warningText: nil
            )
        case .connectedDevice(let device, _):
            return SourceAccessStatus(
                availability: .unknown,
                mode: device.connection == .usb ? .usbDevice : .networkDevice,
                displayName: displayName,
                iconSystemName: "iphone.gen3",
                statusText: nil,
                warningText: nil
            )
        }
    }
}

nonisolated enum MinecraftSourceKind: String, Hashable, Sendable, Codable {
    case localFolder
    case connectedDevice
}
