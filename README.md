# World Manager for Minecraft

World Manager for Minecraft is a macOS app for inspecting and managing Minecraft Bedrock content libraries. It scans worlds, behavior packs, resource packs, and templates from local folders, and can mirror content from a trusted connected iPhone or iPad for browsing on the Mac.

NOT AN OFFICIAL MINECRAFT PRODUCT. NOT APPROVED BY OR ASSOCIATED WITH MOJANG OR MICROSOFT.

## Features

- Browse Minecraft Bedrock libraries from local folders.
- Detect worlds, resource packs, behavior packs, and world templates.
- Inspect package metadata, pack relationships, icons, versions, UUIDs, and basic world facts.
- Export worlds and packs as portable `.mcworld`, `.mcpack`, `.mctemplate`, and `.mcaddon` packages.
- Preview and thumbnail supported Minecraft package files with Quick Look extensions.
- Mirror Minecraft content from connected iOS or iPadOS devices using Apple's MobileDevice/House Arrest interfaces.

## Requirements

- macOS 26.2 or newer, based on the current Xcode project deployment target.
- Xcode with the macOS SDK that supports that deployment target.
- A local copy of Minecraft Bedrock content, or a trusted connected iPhone/iPad with Minecraft installed for connected-device browsing.

Connected-device access uses Apple MobileDevice interfaces that are not a stable public SDK surface. It is useful for local tooling, but should be treated as best-effort and may not be suitable for Mac App Store distribution.

## Building

Open `World Manager for Minecraft.xcodeproj` in Xcode and build the `World Manager for Minecraft` scheme.

From the command line:

```sh
xcodebuild \
  -project "World Manager for Minecraft.xcodeproj" \
  -scheme "World Manager for Minecraft" \
  -configuration Debug \
  build
```

To run the unit test scheme:

```sh
xcodebuild \
  -project "World Manager for Minecraft.xcodeproj" \
  -scheme "World Manager for MinecraftTests" \
  test
```

## Developer Tools

The repository includes a local connected-device probe harness:

```sh
Scripts/run_mobile_device_probe.sh summary
Scripts/run_mobile_device_probe.sh apps
Scripts/run_mobile_device_probe.sh details com.mojang.minecraftpe
Scripts/run_mobile_device_probe.sh probe-paths com.mojang.minecraftpe
Scripts/run_mobile_device_probe.sh mirror com.mojang.minecraftpe 'Documents/games/com.mojang' /tmp/wmm-minecraft-device-mirror
```

See [docs/ios-device-access.md](docs/ios-device-access.md) for the current device-access notes.

## Project Status

This is pre-release software. Back up Minecraft worlds and packs before using file export, import, or management features. The project is currently focused on read-side library inspection, export, and connected-device discovery.

## Trademarks

Minecraft, Mojang, and Microsoft names, brands, assets, and related rights belong to their respective owners. This project uses the Minecraft name only to describe compatibility with Minecraft Bedrock content formats.

Do not use this repository's name, icons, screenshots, or generated builds in a way that suggests endorsement by Mojang or Microsoft.

## AI Assistance

Portions of this project were developed with AI coding assistance, including OpenAI Codex, under human direction and review. Contributions remain the responsibility of the human contributor who submits them.

## License

This project is licensed under the GNU Affero General Public License v3.0 or later. See [LICENSE](LICENSE).
