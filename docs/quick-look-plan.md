# Quick Look Architecture

## Summary

The app includes Quick Look thumbnail and preview extensions for Minecraft Bedrock package files:

- `.mcworld`
- `.mcpack`
- `.mctemplate`
- `.mcaddon`

Both extensions share the same package inspection and thumbnail rendering code used by the app target where possible.

## Targets

### Thumbnail Extension

`MinecraftPackageThumbnailExtension/ThumbnailProvider.swift`

- Implements `QLThumbnailProvider`.
- Calls `MinecraftPackageInspector.inspectArchive(at:)`.
- Renders a `CGImage` with `MinecraftPackageThumbnailRenderer`.
- Cleans up the temporary extraction directory with `MinecraftPackageInspector.cleanup`.

### Preview Extension

`MinecraftPackagePreviewExtension/PreviewViewController.swift`

- Implements `QLPreviewingController`.
- Inspects the selected package archive.
- Displays the package icon when one exists.
- Falls back to the generated thumbnail artwork.
- Keeps the inspection result alive while the preview is displayed, then removes temporary extraction files in `deinit`.

The preview is currently image-focused. `MinecraftPackageQuickLookModelBuilder` already builds structured facts, but the preview controller does not render those facts yet.

## Shared Package Inspection

`MinecraftPackageInspector` is the central archive reader for Quick Look:

- Accepts `.mcworld`, `.mcpack`, `.mctemplate`, and `.mcaddon`.
- Uses `ZipArchiveReader` to inspect ZIP entries.
- Supports packages with content at the archive root or under one top-level folder.
- Extracts only metadata-relevant files into a temporary inspection directory.
- Resolves content type from extension and manifest metadata.
- Reads display name, icon, world metadata, and manifest metadata.

Inspection results include:

- archive URL
- temporary extraction root
- resolved content root
- content type
- display name
- icon URL
- world metadata
- manifest metadata

Callers are responsible for cleanup.

## Metadata Readers

`MinecraftContentMetadataReader` provides shared metadata parsing:

- World display names from `levelname.txt`.
- Pack display names from `manifest.json`.
- World icons from `world_icon.*`.
- Pack icons from `pack_icon.*`.
- World metadata from `level.dat` through `BedrockLevelMetadataDecoder`.
- Manifest UUID, version, and minimum engine version.
- Pack type inference for ambiguous `.mcpack` and `.mcaddon` archives.

`MinecraftPackageQuickLookModelBuilder` converts inspection results into preview-friendly facts such as version, UUID, engine version, game mode, difficulty, last played date, seed, and Bedrock version.

## Thumbnail Rendering

`MinecraftPackageThumbnailRenderer` renders square thumbnail artwork:

- If the package has an icon, it draws that icon cropped to a rounded square with a subtle border.
- If no icon is present, it draws a generated voxel-style badge with content-type-specific colors.
- Rendering is done with AppKit bitmap drawing and returns a `CGImage`.

## Type Registration

The main app registers exported UTTypes and document roles for Minecraft package extensions in `World-Manager-for-Minecraft-Info.plist`.

The extension Info.plists list the same internal UTTypes under `QLSupportedContentTypes`:

- `us.b-wells.minecraft.mcworld`
- `us.b-wells.minecraft.mcpack`
- `us.b-wells.minecraft.mctemplate`
- `us.b-wells.minecraft.mcaddon`

## Relevant Files

- `World-Manager-for-Minecraft-Info.plist`
- `MinecraftPackageThumbnailExtension/Info.plist`
- `MinecraftPackageThumbnailExtension/ThumbnailProvider.swift`
- `MinecraftPackagePreviewExtension/Info.plist`
- `MinecraftPackagePreviewExtension/PreviewViewController.swift`
- `World Manager for Minecraft/QuickLook/MinecraftPackageTypes.swift`
- `World Manager for Minecraft/QuickLook/MinecraftPackageQuickLookModel.swift`
- `World Manager for Minecraft/QuickLook/MinecraftPackageThumbnailRenderer.swift`
- `World Manager for Minecraft/Services/ArchiveInspection/MinecraftPackageInspector.swift`
- `World Manager for Minecraft/Services/ArchiveInspection/MinecraftContentMetadataReader.swift`
- `World Manager for Minecraft/Services/ArchiveInspection/ZipArchiveReader.swift`

## Current Limitations

- Preview rendering shows only an image, not the structured metadata facts.
- `.mcaddon` support resolves one content root; multi-pack add-ons are not yet presented as a compound package.
- The inspector extracts only metadata files, which is intentional for Quick Look speed but means package validation is shallow.

## Verification

Run:

```sh
xcodebuild \
  -project "World Manager for Minecraft.xcodeproj" \
  -scheme "World Manager for Minecraft" \
  -configuration Debug \
  build
```

The unit tests cover archive inspection behavior in `World Manager for MinecraftTests/World_Manager_for_MinecraftTests.swift`.
