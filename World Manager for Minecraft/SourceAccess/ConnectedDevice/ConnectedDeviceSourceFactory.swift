//
//  ConnectedDeviceSourceFactory.swift
//  World Manager for Minecraft
//
//  Created by OpenAI on 2026-05-26.
//

import Foundation

struct ConnectedDeviceSourceFactory: Sendable {
    nonisolated init() {}

    nonisolated func makeSource(
        device: ConnectedDevice,
        container: DeviceAppContainer
    ) -> MinecraftSource {
        let sourceID = makeSourceIdentifier(device: device, container: container)
        let cacheRootURL = ConnectedDeviceMirrorCache.rootURL(for: sourceID)

        var source = MinecraftSource(
            sourceID: sourceID,
            folderURL: cacheRootURL,
            origin: .connectedDevice(device: device, container: container),
            accessDescriptor: SourceAccessDescriptor(
                accessorIdentifier: AppleMobileDeviceSourceAccess().accessorIdentifier,
                kind: .connectedDevice,
                capabilities: .connectedDevice,
                refreshStrategy: .staged
            )
        )
        source.displayName = displayName(for: device, container: container)
        return source
    }

    nonisolated func displayName(for device: ConnectedDevice, container: DeviceAppContainer) -> String {
        "\(device.name) • \(container.appName)"
    }

    nonisolated func makeSourceIdentifier(device: ConnectedDevice, container: DeviceAppContainer) -> URL {
        var components = URLComponents()
        components.scheme = "wmminecraft-device"
        components.host = container.deviceUDID
        components.path = "/\(container.appID)"
        components.queryItems = [
            URLQueryItem(name: "mode", value: container.accessMode.rawValue)
        ]

        return components.url ?? URL(string: "wmminecraft-device://\(container.deviceUDID)/\(container.appID)")!
    }
}
