import Foundation

struct ContentViewDependencies {
    let library: SourceLibrary
    let connectedDeviceAccess: AppleMobileDeviceSourceAccess
    let deviceSourceFactory: ConnectedDeviceSourceFactory
    let itemActionService: ContentItemActionService

    static func makeDefault() -> ContentViewDependencies {
        let connectedDeviceAccess = AppleMobileDeviceSourceAccess()
        return ContentViewDependencies(
            library: SourceLibrary(
                sourceAccessMethod: SourceAccessCoordinator(
                    connectedDeviceAccess: connectedDeviceAccess
                ),
                connectedDeviceAccessMethod: connectedDeviceAccess
            ),
            connectedDeviceAccess: connectedDeviceAccess,
            deviceSourceFactory: ConnectedDeviceSourceFactory(),
            itemActionService: ContentItemActionService()
        )
    }
}
