# iOS Device Access Notes

## Summary

This project can now read Minecraft Bedrock content directly from a connected iPhone or iPad on macOS using `MobileDevice.framework` and House Arrest.

The app does **not** scan the device live through custom file APIs. Instead, it:

1. Detects a connected trusted device with `MobileDevice.framework`.
2. Opens House Arrest for `com.mojang.minecraftpe`.
3. Uses `VendDocuments`.
4. Mirrors the proven Minecraft subtree into a temporary local folder.
5. Hands that local folder to the existing `WorldScanner`.

That keeps the rest of the app filesystem-based.

## Proven Findings

### Correct bundle ID

Minecraft on the tested device is:

- `com.mojang.minecraftpe`

### App metadata

The app record reported:

- `UIFileSharingEnabled = 1`
- `LSSupportsOpeningDocumentsInPlace = 1`

So Minecraft does expose a vendable Documents surface.

### Correct vend root

House Arrest `VendDocuments` succeeds, but the Minecraft content is **not** rooted at:

- `games/com.mojang`

The proven path is:

- `Documents/games/com.mojang`

### Proven subfolders

These paths were verified through AFC on the real device:

- `Documents/games/com.mojang/minecraftWorlds`
- `Documents/games/com.mojang/resource_packs`
- `Documents/games/com.mojang/behavior_packs`
- `Documents/games/com.mojang/world_templates`

## Important API Findings

### `AMDeviceCreateHouseArrestService`

The direct helper path still returned a device-side error on the tested device:

- `InstallationLookupFailed`
- `e80000b7`

So the app currently relies on the explicit vend flow instead:

1. `AMDeviceSecureStartService("com.apple.mobile.house_arrest")`
2. `AMDServiceConnectionSendMessage` with `VendDocuments`
3. `AMDServiceConnectionReceiveMessage`
4. Create AFC from the returned service connection

### `VendDocuments` vs `VendContainer`

`VendDocuments` is the working path for Minecraft on the tested device.

### AFC path behavior

The AFC root is not a normal `/` root for this vend. Examples:

- `"/"` returned AFC status `0xA`
- `"/games/com.mojang"` returned AFC status `0x8`
- `"Documents/games/com.mojang"` worked

So code should use the proven vend-relative path instead of assuming a container root layout.

## Current Project Shape

## Source Access Architecture

Source intake is now organized around access methods rather than one-off services.

- `SourceAccess/Core`
  - shared contracts and the `SourceAccessCoordinator`
- `SourceAccess/LocalFolder`
  - the local disk access method
- `SourceAccess/ConnectedDevice`
  - connected-device source creation and picker UI
- `SourceAccess/ConnectedDevice/AppleMobileDevice`
  - the built-in Apple mobile-device transport

The key abstraction is `SourceAccessMethod`.

Each access method is responsible for:

1. turning a `MinecraftSource` into a local `PreparedScanRoot`
2. cleaning up that prepared root when scanning finishes

That keeps the rest of the app indifferent to how a source is reached.

### App path

User flow:

- `SourcesSidebarView` opens the connected-device sheet.
- `ConnectedDeviceSourcePickerView` lets the user select a device/app and a subpath.
- `AppleMobileDeviceSourceAccess` is the active connected-device access method.

### Scan-root preparation

`SourceAccessCoordinator` chooses between:

- local folder sources
- connected device sources

For connected devices:

- the built-in `AppleMobileDeviceSourceAccess`
- future connected-device access methods can implement the same contracts

### Mirror behavior

The MobileDevice fallback:

- mirrors the subtree into a temporary directory
- returns that directory as `PreparedScanRoot.rootURL`
- cleans it up with `CleanupBehavior.deleteTemporaryDirectory`

## Relevant Files

- `World Manager for Minecraft/SourceAccess/ConnectedDevice/AppleMobileDevice/AppleMobileDeviceBridge.m`
- `World Manager for Minecraft/SourceAccess/ConnectedDevice/AppleMobileDevice/AppleMobileDeviceBridge.h`
- `World Manager for Minecraft/SourceAccess/ConnectedDevice/AppleMobileDevice/AppleMobileDeviceAccess.swift`
- `World Manager for Minecraft/SourceAccess/ConnectedDevice/AppleMobileDevice/AppleMobileDeviceSourceAccess.swift`
- `World Manager for Minecraft/SourceAccess/Core/SourceAccessCoordinator.swift`
- `World Manager for Minecraft/SourceAccess/LocalFolder/LocalFolderSourceAccess.swift`
- `World Manager for Minecraft/Models/SourceOrigin.swift`
- `World Manager for Minecraft/SourceAccess/ConnectedDevice/ConnectedDeviceSourcePickerView.swift`

## Developer CLI

A local probe harness was added for iteration:

- `Scripts/run_mobile_device_probe.sh`
- `Tools/mobile_device_probe.m`

Useful commands:

```sh
Scripts/run_mobile_device_probe.sh summary
Scripts/run_mobile_device_probe.sh apps
Scripts/run_mobile_device_probe.sh details com.mojang.minecraftpe
Scripts/run_mobile_device_probe.sh probe-paths com.mojang.minecraftpe
Scripts/run_mobile_device_probe.sh mirror com.mojang.minecraftpe 'Documents/games/com.mojang' /tmp/wmm-minecraft-device-mirror
```

These commands generally need to run outside the agent sandbox to access the real connected device.

## Known Cleanup Targets

Not part of the device-access implementation itself:

- `layoutSubtreeIfNeeded` warning: SwiftUI/AppKit layout issue
- `duplicate column name: bookmark_data`: persistence migration issue
- preview actor-isolation warnings in `PreviewFixtures.swift`

## Recommendation

Keep the CLI probe and this document.

They provide a reproducible path for future device-access debugging without going back through GUI-based experimentation.
