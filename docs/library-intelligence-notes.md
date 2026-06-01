# Library Architecture and Future Intelligence

## Current Architecture

The app is organized around source-agnostic Minecraft libraries. A source can be a local folder or a connected iOS/iPadOS device, but the UI mostly interacts with the same `MinecraftSource` and `MinecraftContentItem` models for both.

The main runtime owner is `SourceLibrary`:

- Stores visible sources and connected-device sidebar entries.
- Starts and cancels scans.
- Restores/persists cached sources.
- Refreshes source availability.
- Builds item lookup indexes for selection and file actions.
- Routes filesystem-like operations through `SourceAccessMethod`.

`ContentView` renders the three-column app:

- source/device sidebar
- projected item list
- detail/metadata/action column

The item list is built from an `ItemCollectionProjectionRequest` and generated off the main actor by `ItemCollectionProjector`.

## Source Access

`SourceAccessMethod` is the boundary between source-specific I/O and source-independent app behavior.

The protocol covers:

- access descriptor
- availability
- capabilities
- discovery
- enrichment
- preview assets
- size loading
- directory listing
- item materialization
- cache cleanup

Implemented access methods:

- `LocalFolderSourceAccess`
  - resolves security-scoped bookmarks
  - scans local Minecraft folders with `WorldScanner`
  - reads local directory listings
  - returns native folder URLs for materialization

- `AppleMobileDeviceSourceAccess`
  - enumerates devices and app containers through MobileDevice
  - discovers Minecraft content through device summaries and metadata batches
  - loads icons, sizes, and directory contents on demand
  - materializes device items by mirroring one subtree to a temporary directory

`ContentViewDependencies.makeDefault()` wires `SourceLibrary` with a `SourceAccessCoordinator` that dispatches between local-folder access and Apple MobileDevice access.

## Scanning Pipeline

`SourceScanExecutor` runs source scans in stages:

1. Mark source as scanning and update availability.
2. Start a `WorldScanner` scan session.
3. Discover items through the source-access method.
4. Feed discovered items into `SourceIndexActor`.
5. Enrich metadata through worker tasks.
6. Build and publish normalized index snapshots.
7. Load preview assets.
8. Load size metrics for local sources; connected-device size loading uses a faster batched path.
9. Persist source state after major stages.
10. Update final status and send scan notifications when appropriate.

Local reconcile scans can reuse cached items for unchanged collection snapshots. Connected-device reconcile scans preserve cached collections when a device response omits a collection that was previously known.

## Content Model

The app recognizes these content types:

- worlds: `minecraftWorlds`
- behavior packs: `behavior_packs`
- resource packs: `resource_packs`
- skin packs: `skin_packs`
- world templates: `world_templates`

`MinecraftContentItem` stores:

- stable folder URL identity
- content type and collection root
- display name and icon
- dates and size
- pack UUID/version/engine metadata
- world metadata from `level.dat`
- pack references
- metadata/preview/size loading flags

`WorldScanner` handles local folder discovery and enrichment:

- finds candidate collection folders
- detects embedded behavior/resource packs inside worlds
- reads `levelname.txt`, `manifest.json`, icons, and `level.dat`
- computes collection snapshots for reconcile scans

## Normalized Index

`SourceContentIndexer` turns raw discovered items into normalized source data:

- `rawItems`
- `logicalPacks`
- `logicalWorlds`
- `packInstances`
- `worldPackRelationships`
- `displayItems`
- content-type counts

Packs are grouped by `PackIdentity` using UUID/version when available, or fallback name/location when metadata is incomplete. A representative pack is chosen for display, preferring top-level packs over embedded world copies, loaded metadata, icons, recent modified dates, and stable path ordering.

World relationships resolve pack references to logical packs when possible. Unresolved references remain visible on the world detail side.

The displayed item list uses worlds, representative packs, skin packs, and templates. Embedded duplicate pack instances remain available through detail views.

## Persistence and Offline Cache

`SourcePersistenceStore` stores source cache data in SQLite under Application Support:

```text
Library/Application Support/World Manager for Minecraft/LibraryCache-v2026-05-28.sqlite
```

Persisted records include:

- source ID and folder URL
- source origin
- access descriptor
- availability
- bookmark data
- display name
- raw item payloads
- source snapshots
- last scan date

`SourcePersistenceCoordinator` restores sources at launch, applies cached images, repairs older records when needed, refreshes availability, then schedules reconcile scans when cached data may be stale.

This is what allows disconnected device-backed sources to display cached results.

## File Actions

File operations are currently focused on export, share, reveal/materialize, and directory preview:

- `ContentItemActionService` provides filenames, archive types, archive creation, and persistence of external representations.
- `ContentPackageExporter` stages content and creates ZIP-based Minecraft package archives through `/usr/bin/ditto`.
- Local source items can use native folders directly.
- Connected-device items are mirrored into temporary staging before export or reveal.

Archive extensions:

- worlds -> `.mcworld`
- behavior/resource/skin packs -> `.mcpack`
- world templates -> `.mctemplate`

## Current Product Capabilities

Implemented:

- Browse multiple local and connected-device sources.
- Restore cached sources at launch.
- Reconcile source changes.
- Search within the selected source/list projection.
- Sort by name, modified/last-played date, or size.
- Inspect world and pack metadata.
- Resolve world-to-pack relationships when metadata allows.
- Show embedded and backing pack instances.
- Export/share/reveal items.
- Preview package files with Quick Look.

Not implemented yet:

- Global cross-source search.
- User-created smart folders.
- Dedicated duplicate/integrity dashboard.
- Backup/restore workflows as first-class operations.
- Cross-source copy/move/import workflows.

## Future Intelligence Direction

The existing normalized index provides most of the data needed for richer library intelligence. Future work should build on `SourceContentIndexer`, persisted source caches, and projection requests rather than introducing a separate scanning path.

Useful next features:

- Global search across all visible and cached sources.
- Built-in smart folders for large worlds, recent worlds, unresolved pack references, duplicate packs, suspicious packs, and offline cached results.
- Duplicate analysis across sources by UUID/version, fallback identity, size, and modified date.
- Integrity checks for missing `level.dat`, malformed manifests, broken archives, and unresolved world pack references.
- Backup manifests that make exported backups browsable and restorable later.

Suggested implementation order:

1. Add a global read-only index projection over all `SourceLibrary.visibleSources`.
2. Add built-in smart folders backed by predicates over the normalized index.
3. Add cross-source duplicate and integrity analyzers.
4. Add explicit copy/backup/restore operations after analysis and conflict detection are reliable.

Keep search, smart folders, and analysis distinct in the UI even if they share the same underlying source/index data.
