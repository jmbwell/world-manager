# Connected iOS Device Access

## Summary

World Manager can browse Minecraft Bedrock content from a trusted iPhone or iPad on macOS using Apple's private `MobileDevice.framework` and the House Arrest service.

Connected-device sources are modeled as normal `MinecraftSource` values, but they are not scanned through a live filesystem mirror. The current implementation asks the device for library item summaries, metadata, icons, sizes, and directory listings through `AppleMobileDeviceSourceAccess`. Only explicit materialization operations, such as reveal/export/share, mirror an item subtree into a temporary local directory.

## Current Flow

1. `SourceLibrary` owns a `ConnectedDeviceRuntime` refresh loop when a connected-device access method is configured.
2. `AppleMobileDeviceSourceAccess.listConnectedDevices()` enumerates devices through `AppleMobileDeviceAccess.connectedDevices()`.
3. `AppleMobileDeviceSourceAccess.listAccessibleContainers(for:)` lists app containers and prioritizes `com.mojang.minecraftpe`.
4. `ConnectedDeviceSourcePickerView` lets the user add a device-backed Minecraft source.
5. `ConnectedDeviceSourceFactory` creates a stable synthetic source identifier:

   ```text
   wmminecraft-device://<device-udid>/<bundle-id>?mode=documents
   ```

6. `SourceScanExecutor` scans the source through the generic `SourceAccessMethod` protocol.
7. `AppleMobileDeviceSourceAccess.discoverItems` calls `minecraftLibrarySnapshot` for item summaries and `minecraftMetadataBatch` for metadata.
8. Preview icons, size metrics, directory contents, and full item materialization are loaded lazily through the same source-access method.

This keeps UI, indexing, export, and persistence mostly source-agnostic while allowing connected devices to avoid a full upfront mirror.

## Minecraft Container

The tested Minecraft bundle identifier is:

```text
com.mojang.minecraftpe
```

Minecraft exposes a vendable Documents surface. The working Minecraft content root for House Arrest `VendDocuments` is:

```text
Documents/games/com.mojang
```

The app treats that value as a vend-relative path stored on `DeviceAppContainer.minecraftFolderRelativePath`.

Expected subfolders under that root:

- `minecraftWorlds`
- `resource_packs`
- `behavior_packs`
- `skin_packs`
- `world_templates`

## House Arrest Details

The implementation uses the explicit House Arrest flow in the Objective-C bridge:

1. Start `com.apple.mobile.house_arrest`.
2. Send `VendDocuments`.
3. Receive the vend response.
4. Use AFC against the returned service connection.

The direct `AMDeviceCreateHouseArrestService` helper returned `InstallationLookupFailed` / `e80000b7` on the tested device, so it is not the primary path.

The AFC root for this vend should not be treated as a normal `/` filesystem root. Paths are relative to the vend surface, and Minecraft content is reached through `Documents/games/com.mojang`.

## Runtime Behavior

Connected-device sources use a staged refresh strategy:

- Availability is derived from current device presence and trust state.
- Trusted devices are available.
- Locked or untrusted devices are limited.
- Missing or inaccessible devices are disconnected.
- When a source becomes available, `SourceSyncRuntime` can queue a reconcile scan instead of a full scan if cached content exists.

Scan execution uses fewer workers for connected-device sources than local folders to avoid overloading AFC/MobileDevice calls.

During scan:

- `minecraftLibrarySnapshot` returns candidate content items.
- `minecraftMetadataBatch` returns display names, UUIDs, versions, minimum engine versions, and world pack references.
- Icons are loaded with `minecraftIconBatch` or individual file reads and cached through `ImageCacheStore`.
- Size information is loaded through `pathMetricsBatch`.
- Directory previews call `listDirectory`.

During materialization:

- `materializeItem` mirrors one remote item subtree into `NSTemporaryDirectory()/WMMConnectedDeviceReveal/...`.
- `ContentPackageExporter` mirrors the selected item into archive staging when exporting connected-device content.
- Temporary materialized folders are treated as disposable.

## Persistence

Connected-device sources are persisted in the SQLite source cache with:

- source identifier
- source origin and device/container metadata
- access descriptor
- availability
- raw item cache
- source snapshot
- last scan date

On app launch, cached sources and items are restored before availability refreshes complete, so offline device-backed sources can still show cached results.

## Relevant Files

- `World Manager for Minecraft/SourceAccess/ConnectedDevice/AppleMobileDevice/AppleMobileDeviceBridge.m`
- `World Manager for Minecraft/SourceAccess/ConnectedDevice/AppleMobileDevice/AppleMobileDeviceBridge.h`
- `World Manager for Minecraft/SourceAccess/ConnectedDevice/AppleMobileDevice/AppleMobileDeviceAccess.swift`
- `World Manager for Minecraft/SourceAccess/ConnectedDevice/AppleMobileDevice/AppleMobileDeviceSourceAccess.swift`
- `World Manager for Minecraft/SourceAccess/ConnectedDevice/ConnectedDeviceSourceFactory.swift`
- `World Manager for Minecraft/SourceAccess/ConnectedDevice/ConnectedDeviceSourcePickerView.swift`
- `World Manager for Minecraft/Services/Sources/ConnectedDevice/SourceConnectedDeviceRuntime.swift`
- `World Manager for Minecraft/Services/Sources/Scanning/SourceScanExecution.swift`

## Developer Probe

The local probe harness is useful for debugging MobileDevice behavior outside the app:

```sh
Scripts/run_mobile_device_probe.sh summary
Scripts/run_mobile_device_probe.sh apps
Scripts/run_mobile_device_probe.sh details com.mojang.minecraftpe
Scripts/run_mobile_device_probe.sh probe-paths com.mojang.minecraftpe
Scripts/run_mobile_device_probe.sh mirror com.mojang.minecraftpe 'Documents/games/com.mojang' /tmp/wmm-minecraft-device-mirror
```

These commands require a trusted connected device and generally need to run outside restricted automation sandboxes.

## Caveats

- `MobileDevice.framework`, House Arrest, and AFC are private Apple interfaces.
- Behavior can change across macOS, iOS, iPadOS, and Minecraft releases.
- Device access requires trust, unlock state, and a vendable app container.
- Connected-device export/reveal operations may be slower than local folder operations because they materialize remote content on demand.
