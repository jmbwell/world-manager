# Provider Refactor Migration Plan

This plan moves the app from a Bedrock-oriented source-access architecture to an
engine/platform-provider architecture while keeping behavior working at each
step.

## Phase 1: Document and Name the Boundary

- Add provider architecture documentation.
- Add neutral model names alongside existing names:
  - `MinecraftEdition`
  - `MinecraftContentKind`
  - `MinecraftPlatformContentType`
  - `PlatformContentMetadata`
  - `ContentItemCapabilities`
  - `SourceAccessStatus`
  - `WorkStage`
  - `ProviderEvent`
- Keep existing `MinecraftContentType` as a compatibility alias/wrapper until
  call sites move.

## Phase 2: Neutralize Content Items

- Add edition, kind, platform type, capabilities, and platform metadata to
  `MinecraftContentItem`.
- Preserve existing Bedrock fields as computed compatibility accessors where
  practical.
- Move Bedrock world and pack metadata into `BedrockContentMetadata`.
- Update search text to pull from generic fields and provider metadata.
- Update tests/fixtures to construct items through the new neutral initializer.

## Phase 3: Provider-Shaped Access

- Introduce provider protocol types as a superset of current source access.
- Adapt `SourceAccessMethod` to emit provider IDs and access status.
- Register providers through a provider registry/coordinator.
- Rename current generic local folder access to Bedrock local folder access.
- Keep a compatibility typealias or wrapper named `LocalFolderSourceAccess` until
  all call sites are migrated.

## Phase 4: Split Bedrock Platform Module

- Move Bedrock-specific scanner/metadata/export code under a Bedrock platform
  namespace/folder.
- Rename `WorldScanner` to `BedrockContentScanner`.
- Rename `MinecraftContentMetadataReader` to `BedrockContentMetadataReader`.
- Keep temporary wrappers for Quick Look and legacy call sites.
- Move Bedrock relationship building out of generic indexing.

## Phase 5: Event-Driven Scan Pipeline

- Add provider events and work stages.
- Let providers report progress stages.
- Let the engine consume discovered/inspected events.
- Preserve existing scan-stage behavior until provider events fully replace it.
- Keep worker limits in the engine, with provider-declared concurrency policy as
  a later extension.

## Phase 6: Capability-Aware Actions

- Move archive extension and portable export format selection off
  `MinecraftContentType`.
- Add item/provider capabilities for reveal/export/share/copy.
- Adapt `ContentItemActionService` and exporters to route by provider/platform
  type.
- Keep Bedrock package output unchanged.

## Phase 7: Java Local Provider

- Add Java local provider as read-only initially.
- Discover Java saves, resource packs, and datapacks.
- Add Java metadata reader for `level.dat` and `pack.mcmeta` incrementally.
- Export Java folder-backed content as `.zip` where supported.
- Do not add Java-Bedrock conversion in this phase.

## Phase 8: Cleanup

- Remove compatibility aliases after UI, tests, Quick Look, and exporters use
  provider-aware models.
- Rename UI labels from Bedrock-specific categories where appropriate.
- Add provider fixtures and contract tests.
- Keep build/test verification passing after each phase.

## Verification

At each milestone:

- Run Swift tests.
- Run the app target build.
- Check existing Bedrock local and connected-device behavior remains intact.
- Add focused tests for model migration, indexing, export format selection, and
  provider event consumption.
