// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

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
                refreshStrategy: .staged
            )
        )
        source.displayName = displayName(for: device, container: container)
        return source
    }

    nonisolated func displayName(for device: ConnectedDevice, container _: DeviceAppContainer) -> String {
        device.name
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
