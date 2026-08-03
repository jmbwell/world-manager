# World Manager for Minecraft

World Manager for Minecraft is a macOS app for inspecting and exporting items in Minecraft Bedrock content libraries on Apple devices. It scans worlds, behavior packs, resource packs, and templates from local folders, and can export content from a trusted connected iPhone or iPad for browsing or sharing from the Mac.

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
- Import `.mcworld`, `.mcpack`, `.mctemplate`, and nested-package `.mcaddon` files into writable folder and connected-device sources.
- Copy an item between sources by dragging it onto the destination source in the sidebar.
- Preview and thumbnail supported Minecraft package files with Quick Look extensions.

## Usage

### Adding a Library

For a local folder, click the folder toolbar button and choose the folder that contains your Bedrock content, or drag the folder into the source list. World Manager will scan it and look for the usual Minecraft folders like `minecraftWorlds`, `behavior_packs`, `resource_packs`, and `world_templates`.

For an iPhone or iPad, connect the device over USB first. If iOS asks whether to trust the Mac, allow it on the device and unlock the device if needed. Once the device appears in the sidebar, click `Add`. After a device has trusted the Mac, it should usually be discoverable over the network even when it is not connected by USB.

Device discovery is not always instant. If a trusted device does not appear, try sleeping the device, waking and unlocking it again, then waiting a little while for Apple's MobileDevice services to catch up. You can also click the device toolbar icon and try to find it from the device picker.

Once a folder or device source is added, World Manager scans it and discovers the worlds, packs, templates, and other supported items it can find. If a device disconnects after it has been scanned, you can still browse cached results. Exporting and sharing from that device require reconnecting it. If a device disconnects while a discovery scan is in progress, the scan should resume when the source becomes available again.

### Browsing and Inspecting

Click a source in the sidebar to see all detected items and source details. Click one of the filter rows under a source to show only worlds, behavior packs, resource packs, skin packs, or templates.

Click an item in the item list to inspect it. The detail view shows the metadata World Manager could detect, including names, icons, dates, size, pack UUID/version information, basic world facts, and world-to-pack relationships where available.

### Exporting and Sharing

From an item's detail view, you can export it to a Minecraft package file on your Mac or share it directly through the macOS share sheet. Worlds export as `.mcworld`, packs as `.mcpack`, and templates as `.mctemplate`.

If you share to another device with AirDrop, Messages, or a similar route, opening the received file on that device should launch Minecraft and begin Minecraft's normal import flow.

### Importing and Copying

Select a source and use `Import...` on its overview, or drop a supported Minecraft package onto the source row in the sidebar. World Manager inspects the package and places each item in the collection appropriate to its content type.

You can also drag an existing world or pack from the item list onto another source. The app exports a temporary portable representation, validates it through the same import path, and installs it in the destination.

Imports are additive. Existing worlds are never overwritten. A second world import receives a unique directory name. Packs with a UUID already present in the destination are rejected instead of being silently replaced.

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

This is pre-release software. Make sure Minecraft worlds and packs are being backed up by other means before using this app. Connected-device installation writes through private Apple MobileDevice interfaces and should be treated as best-effort. The initial implementation installs only into new directories and does not replace or remove existing content.

## Trademarks

Minecraft, Mojang, and Microsoft names, brands, assets, and related rights belong to their respective owners. This project uses the Minecraft name only to describe compatibility with Minecraft Bedrock content formats.

Do not use this repository's name, icons, screenshots, or generated builds in a way that suggests endorsement by Mojang or Microsoft.

## AI Assistance

Large portions of this project were developed with AI coding assistance, including OpenAI Codex, under human direction and review. I know some Swift and application architecture and UX, but I am not steeped in knowledge of Apple's dizzying array of arcane APIs. In any case, future contributions remain the responsibility of the human contributor who submits them.

## License

This project is licensed under the GNU Affero General Public License v3.0 or later. See [LICENSE](LICENSE).
