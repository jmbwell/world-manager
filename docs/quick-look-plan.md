# Quick Look Plan

## Current State

The shared Bedrock package inspection layer is implemented in app code and ready to be reused by Quick Look targets:

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

Archive inspection is covered by tests in `World Manager for MinecraftTests/World_Manager_for_MinecraftTests.swift`.

## Why The Extension Target Is Not Landed Yet

The project is using Xcode's filesystem-synchronized project format. Adding a new Quick Look target by hand in `project.pbxproj` is possible, but it is the highest-risk part of this feature to do blind because:

- the target graph, extension point declaration, product embedding, and bundle metadata all need to be correct together
- a malformed `pbxproj` can break the project more broadly than a normal source change
- the extension will need generated or explicit Info.plist keys for document/UTType registration

The parsing and rendering code is now in a shape where the target layer can stay thin.

## Recommended Next Steps

1. Add a `Quick Look Thumbnail Extension` target in Xcode.
2. Point it at the shared package inspector and thumbnail renderer.
3. Register support for:
   - `.mcworld`
   - `.mcpack`
   - `.mctemplate`
   - `.mcaddon`
4. Add a `Quick Look Preview Extension` target after thumbnails are working.
5. Render the preview from `MinecraftPackageQuickLookModel`.

## Thumbnail Extension Outline

Implement a provider roughly like this:

```swift
final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        do {
            let inspection = try MinecraftPackageInspector.inspectArchive(at: request.fileURL)
            defer { MinecraftPackageInspector.cleanup(inspection) }

            guard let image = MinecraftPackageThumbnailRenderer.makeThumbnail(
                for: inspection,
                size: request.maximumSize,
                scale: request.scale
            ) else {
                handler(nil, CocoaError(.fileReadCorruptFile))
                return
            }

            handler(
                QLThumbnailReply(contextSize: request.maximumSize) { context in
                    context.draw(image, in: CGRect(origin: .zero, size: request.maximumSize))
                    return true
                },
                nil
            )
        } catch {
            handler(nil, error)
        }
    }
}
```

## Preview Extension Outline

The preview target can:

- inspect the archive with `MinecraftPackageInspector`
- build display content with `MinecraftPackageQuickLookModelBuilder`
- render a compact SwiftUI summary view with:
  - package icon or branded artwork
  - title
  - package kind
  - key facts like version, UUID, minimum engine, game mode, difficulty, and last played

## Verification Notes

- `xcodebuild ... build` succeeds.
- `xcodebuild ... test` currently does not complete cleanly because the existing test target already references `IFuseDeviceServices`, which is not in scope for the test build. That issue predates the Quick Look work.
