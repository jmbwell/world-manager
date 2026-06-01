# Quick Look Plan

## Current State

Quick Look thumbnail and preview extension targets are present in the project and share the app's Bedrock package inspection layer:

- `World Manager for Minecraft/Services/MinecraftPackageInspector.swift`
  - extracts `.mcworld`, `.mcpack`, `.mctemplate`, and `.mcaddon`
  - normalizes archives with either flat contents or a single nested top-level folder
  - infers pack type for ambiguous `.mcpack` and `.mcaddon` archives
- `World Manager for Minecraft/Services/MinecraftContentMetadataReader.swift`
  - shared manifest, icon, display-name, and world metadata parsing
- `World Manager for Minecraft/QuickLook/MinecraftPackageTypes.swift`
  - central UTType identifiers and extension definitions
- `World Manager for Minecraft/QuickLook/MinecraftPackageQuickLookModel.swift`
  - preview-friendly summary model
- `World Manager for Minecraft/QuickLook/MinecraftPackageThumbnailRenderer.swift`
  - branded thumbnail rendering with icon fallback
- `MinecraftPackageThumbnailExtension/ThumbnailProvider.swift`
  - renders Quick Look thumbnails for supported Minecraft package files
- `MinecraftPackagePreviewExtension/PreviewViewController.swift`
  - renders a basic image preview from package icons or generated thumbnail art

Archive inspection is covered by tests in `World Manager for MinecraftTests/World_Manager_for_MinecraftTests.swift`.

## Remaining Work

The target layer is intentionally thin, but the preview experience can still be improved:

- render structured metadata with `MinecraftPackageQuickLookModelBuilder`
- include:
  - package icon or branded artwork
  - title
  - package kind
  - key facts like version, UUID, minimum engine, game mode, difficulty, and last played
- add explicit UI tests or fixture-driven render tests for package previews

## Verification Notes

- `xcodebuild ... build` succeeds.
- `xcodebuild ... test` should be run before release and whenever the shared archive inspection layer changes.
