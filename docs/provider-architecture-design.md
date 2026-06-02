# Provider Architecture Design

World Manager should treat Minecraft libraries as sources of content units that
can be discovered, inspected, cached, displayed, materialized, exported, and
eventually copied between sources. Bedrock local folders, Bedrock iOS devices,
Java local folders, and possible future platforms should be cohesive provider
modules behind one engine contract.

## Goals

- Keep provider-specific knowledge inside provider modules.
- Give the UI a uniform model for equivalent concepts: name, edition, kind,
  source, icon, dates, size, availability, progress, and actions.
- Preserve variable metadata for platform details that do not translate across
  editions.
- Allow scan workflows to stream events instead of forcing every provider into
  the same fixed stages.
- Keep connected-device and remote-like sources free to throttle work more
  aggressively than local filesystem sources.

## Shape

```text
Platforms/Bedrock
  BedrockLocalFolderProvider
  BedrockIOSDeviceProvider
  BedrockContentScanner
  BedrockMetadataReader
  BedrockExporter
  BedrockMaterializer

Platforms/Java
  JavaLocalFolderProvider
  JavaContentScanner
  JavaMetadataReader
  JavaExporter
  JavaMaterializer

Engine
  ProviderRegistry
  SourceEngine
  Scan orchestration
  Cache/snapshot persistence
  Generic indexing/search/projection
  Generic action dispatch

UI
  Generic source and item surfaces
  Provider/edition-specific detail sections
```

## Core Concepts

### Local Folder Intake

The folder picker should not decide the platform. A picked folder is a local
access root; providers decide whether it contains Bedrock, Java, or another
platform.

```text
User picks folder
  -> provider registry asks local providers to probe it
  -> strongest probe chooses provider, edition, and source root
  -> source is stored as a local folder with providerID/accessDescriptor
  -> scans route through the selected provider
```

This keeps filesystem access separate from Minecraft format knowledge. For
example, selecting a wrapper folder that contains one Java modpack instance can
resolve to the nested instance folder while still using local folder access.

```swift
struct SourceProbeResult {
    let providerID: PlatformProviderID
    let edition: MinecraftEdition
    let confidence: SourceProbeConfidence
    let sourceRootURL: URL
    let displayName: String
    let detectedKinds: Set<MinecraftContentKind>
    let warnings: [String]
}
```

### Provider

A provider is the unit that knows a platform and access method. A provider can
represent an edition/access pairing such as Bedrock local folder, Bedrock iOS
device, or Java local folder.

```swift
protocol MinecraftPlatformProvider: Sendable {
    var id: PlatformProviderID { get }
    var displayName: String { get }

    func accessDescriptor(for source: MinecraftSource) -> SourceAccessDescriptor
    func accessStatus(for source: MinecraftSource) async -> SourceAccessStatus
    func capabilities(for source: MinecraftSource) async -> SourceCapabilities

    func scan(_ request: ProviderScanRequest) -> AsyncThrowingStream<ProviderEvent, Error>
    func materialize(_ unit: MinecraftContentItem, in source: MinecraftSource) async throws -> URL
    func export(_ unit: MinecraftContentItem, in source: MinecraftSource, request: ExportRequest) async throws -> URL
}
```

The current `SourceAccessMethod` is already close to this role. The refactor
should evolve it rather than replace the whole source system at once.

### Content Unit

The engine should pass around an edition-aware content unit with a strong common
surface and boxed platform metadata.

```swift
struct MinecraftContentItem {
    let id: URL
    let folderURL: URL
    let folderName: String
    let sourceEdition: MinecraftEdition
    let contentKind: MinecraftContentKind
    let platformType: MinecraftPlatformContentType
    let collectionRootURL: URL

    var displayName: String
    var iconURL: URL?
    var modifiedDate: Date?
    var sizeBytes: Int64?
    var capabilities: ContentItemCapabilities
    var platformMetadata: PlatformContentMetadata
}
```

The model can retain compatibility shims during migration, but new code should
prefer edition, kind, capabilities, and boxed metadata over Bedrock-only fields.

### Metadata

Generic UI should avoid flattening provider metadata. Platform details should be
boxed and rendered by edition/provider-aware detail sections.

```swift
enum PlatformContentMetadata: Hashable, Sendable, Codable {
    case bedrock(BedrockContentMetadata)
    case java(JavaContentMetadata)
    case none
}
```

### Access Status

Availability should be richer than local-vs-device.

```swift
enum SourceAccessMode: String, Hashable, Sendable, Codable {
    case localFileSystem
    case securityScopedLocalFolder
    case usbDevice
    case networkDevice
    case archive
    case unknown
}

struct SourceAccessStatus: Hashable, Sendable, Codable {
    var availability: SourceAvailability
    var mode: SourceAccessMode
    var displayName: String
    var iconSystemName: String
    var statusText: String?
    var warningText: String?
}
```

### Event-Driven Scanning

Providers should be able to stream discoveries, metadata, progress, and warnings.

```swift
enum ProviderEvent: Sendable {
    case accessStatusChanged(SourceAccessStatus)
    case stageUpdated(WorkStage)
    case discovered(MinecraftContentItem)
    case inspected(MinecraftContentItem)
    case warning(ProviderWarning)
}
```

The engine consumes events, updates source state, updates indexes, persists
snapshots, and exposes UI-ready projections.

### Source Candidate Discovery

Source candidate discovery is separate from source content discovery. Candidate
discovery answers whether a potential source exists in the current environment;
content discovery scans an accepted source for worlds, packs, mods, and other
items.

```text
Engine asks providers for source candidates
  -> each provider uses its own bounded discovery process
  -> providers stream candidate events
  -> engine deduplicates and filters already-added sources
  -> UI shows suggestions that the user can accept
```

For example, the Java local provider can check known macOS launcher roots and
shallow-search likely instance folders, while Bedrock local folders can remain a
no-op and rely on folder picking. Connected-device providers can later emit
device-backed candidates from USB or network discovery.

## Responsibilities

### Engine Owns

- Provider registration/routing.
- Source candidate discovery orchestration and deduplication.
- Source lifecycle and persistence.
- Scan task ownership, cancellation, and worker limits.
- Cache and snapshot persistence hooks.
- Generic item search, sorting, counts, and projections.
- Generic action dispatch and user-facing error normalization.

### Provider Owns

- Access method details.
- Source candidate discovery strategy.
- Discovery layout and content markers.
- Metadata parsing.
- Platform relationships.
- Materialization.
- Export formats.
- Provider-specific progress stages and warnings.
- Provider-specific detail metadata.

## Current Fit

Existing app pieces already map to this design:

- `SourceAccessMethod`: provider-like boundary.
- `SourceAccessCoordinator`: provider registry/router.
- `SourceLibrary`: engine/orchestrator.
- `MinecraftSource`: source session and persisted model.
- `SourcePersistenceStore`: persistence.
- `SourceContentIndexer`: generic indexing plus Bedrock-specific relationship
  logic that should be split.
- `ContentItemActionService` and `ContentPackageExporter`: action/export layer
  that should become capability/provider aware.

The main mismatch is that shared models and UI currently carry Bedrock-specific
types and fields directly.
