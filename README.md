# World Manager for Minecraft

World Manager for Minecraft is a macOS app for inspecting and exporting items in Minecraft Bedrock content libraries on Apple devices. It scans worlds, behavior packs, resource packs, and templates from local folders, and can mirror content from a trusted connected iPhone or iPad for browsing on the Mac.

Its creator is a dad often tasked with finding and retrieving worlds and modpacks from mobile devices thrust at him, often with an immediate deadline. "Why can't a computer do this for me," he more or less asked himself one day. He fired up Xcode, roughed in a UI, and peppered Codex with questions about getting at the files programmatically. The result is this thing. With it, the days of digging around in the Files app on a device and coaxing iOS to zip them up, rename them, and share them to a friend are BEHIND US.

Now, because I'm referring to a product well known to popular from a company well known to be litigious, let me say in lawyerly all-caps so there's no ambiguity:

NOT AN OFFICIAL MINECRAFT PRODUCT. NOT APPROVED BY OR ASSOCIATED WITH MOJANG OR MICROSOFT.

This thing is called "World Manager," and it happens to pertain to someone else's thing, called "Minecraft." That thing is the thing this is for, but that thing is not the thing that this thing is. They're different things, and I hope that that is that on this.

## Features

- Browse Minecraft Bedrock libraries on connected iOS devices or in a local folder on your computer.
- Access iOS devices via USB or, once "trusted" on the Mac, via Wi-Fi.
- Detect worlds, resource packs, behavior packs, and world templates.
- Inspect package metadata, pack relationships, icons, versions, UUIDs, and basic world facts.
- Export worlds and packs as portable `.mcworld`, `.mcpack`, `.mctemplate`, and `.mcaddon` packages, or share them via Messages, AirDrop, etc. via the "Share" sheet.
- Preview and thumbnail supported Minecraft package files with Quick Look extensions.

## Requirements

- macOS 26.2 or newer, based on the current Xcode project deployment target. Could work with older macOS. I don't have any so I don't know.
- Xcode with the macOS SDK that supports that deployment target.
- A local copy of Minecraft Bedrock content, or a trusted connected iPhone/iPad with Minecraft installed for connected-device browsing.

Connected-device access uses Apple MobileDevice interfaces that are not a stable public SDK surface. It is useful for local tooling, but should be treated as best-effort.

## Compatibility

- This is designed to work with Minecraft Bedrock Edition ("Minecraft PE.")
- It works with iOS devices because we can access those files through Apple APIs.
- Right now it does not work with Nintendo devices, because it does not look like Nintendo provides any way to access those files. Sorry, friends, the Realms transfer method still seems to be the only way. Maybe one day that will change.
- I don't know whether it works with Java Edition. Believe it or not, it only occurred to me to look into that as I write this.

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

This is pre-release software. Make sure Minecraft worlds and packs are being backed up by other means before using this app. The project is currently focused on read-only library access and export, and connected-device discovery, so it shouldn't be doing anything that can break your existing libraries.

## Trademarks

Minecraft, Mojang, and Microsoft names, brands, assets, and related rights belong to their respective owners. This project uses the Minecraft name only to describe compatibility with Minecraft Bedrock content formats.

Do not use this repository's name, icons, screenshots, or generated builds in a way that suggests endorsement by Mojang or Microsoft.

## AI Assistance

Large portions of this project were developed with AI coding assistance, including OpenAI Codex, under human direction and review. I know some Swift and application architecture and UX, but I am not steeped in knowledge of Apple's dizzying array of arcane APIs. In any case, future contributions remain the responsibility of the human contributor who submits them.

## License

This project is licensed under the GNU Affero General Public License v3.0 or later. See [LICENSE](LICENSE).
