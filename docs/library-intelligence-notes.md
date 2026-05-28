# Library Intelligence Notes

## Focus Areas

- Cross-library search across all scanned sources, not just the currently selected library.
- Smart folders as saved queries over indexed content.
- Automated analysis that surfaces outliers, integrity issues, and duplicates.
- File operations for moving, copying, backing up, and restoring Minecraft content across sources.

## File Operations

Core operations:

- Copy a world from one library to another.
- Copy packs or templates between libraries.
- Export selected items as archives.
- Import archives or folders into a target library.
- Back up an entire accessible Minecraft library from a device or folder source.
- Restore items from a backup into a chosen target source.

Operational concerns:

- Detect duplicate world or pack identities before writing.
- Handle naming conflicts with overwrite, rename, or skip behavior.
- Validate that the destination source supports the content being copied.
- Show progress for long-running copy or backup work.
- Keep operations source-agnostic where possible so local folders, connected devices, and removable media can share the same workflow.

Future file-operation ideas:

- Batch copy selected worlds or packs.
- Sync or compare two libraries before copying.
- One-click backup of a connected device's Minecraft content.
- Backup manifests so backups remain browsable and restorable later.
- Restore preview showing what will be created or overwritten.

## Cross-Library Search

Goals:

- Search across every scanned source in one place.
- Show which library or device each result came from.
- Keep search useful even when some device-backed sources are offline by using cached scan results where possible.

Useful filters:

- Content type: worlds, behavior packs, resource packs, skin packs, templates.
- Source kind: local folders, connected devices, removable media.
- Source name or device name.
- Health state: complete, partial metadata, broken, unresolved references.
- Size ranges and date ranges.

Useful result metadata:

- Display name.
- Source name.
- Content type.
- Size.
- Last played or modified date.
- Availability state for the backing source.

## Smart Folders

Definition:

- Smart folders are saved predicates over indexed content, not physical folders on disk.

Built-in smart folder candidates:

- Largest Worlds
- Largest Archives
- Recently Modified
- Recently Played
- Broken Archives
- Worlds With Missing Packs
- Duplicate Packs
- Suspicious Packs
- Offline Results
- Incomplete Metadata

Future direction:

- Allow users to create custom smart folders from filters and sort rules.

## Automated Analysis

Potential analyses:

- Largest content items by size.
- Broken archives or invalid package structures.
- Worlds missing `level.dat` or other expected files.
- Worlds with unresolved pack references.
- Duplicate packs across libraries by UUID and version.
- Diverged duplicates that appear related but differ in size, modified date, or fingerprint.
- Orphaned packs not referenced by any world.
- Changes since the last scan.

Possible outputs:

- Smart folder population.
- Sidebar badges or warnings.
- A future dashboard or “Insights” view.

## Suggested Order

1. Add global search across all scanned libraries.
2. Add a small set of built-in smart folders.
3. Add integrity and duplicate analysis to feed those folders.
4. Add custom smart folders later if the built-ins prove useful.

## Product Notes

- “Search” solves retrieval.
- “Smart folders” solve recurring saved views.
- “Analysis” solves discovery and problem finding.

These should stay distinct in the product even if they share the same underlying index.
