//
//  MinecraftPackageQuickLookModel.swift
//  World Manager for Minecraft
//
//  Created by OpenAI on 2026-05-26.
//

import Foundation

struct MinecraftPackageQuickLookFact: Sendable, Hashable {
    let label: String
    let value: String
}

struct MinecraftPackageQuickLookModel: Sendable, Hashable {
    let title: String
    let subtitle: String
    let facts: [MinecraftPackageQuickLookFact]
}

enum MinecraftPackageQuickLookModelBuilder {
    nonisolated static func makeModel(from inspection: MinecraftPackageInspector.InspectionResult) -> MinecraftPackageQuickLookModel {
        let subtitle = subtitle(for: inspection.contentType)
        var facts: [MinecraftPackageQuickLookFact] = []

        if let version = inspection.manifestMetadata?.version {
            facts.append(MinecraftPackageQuickLookFact(label: "Version", value: version))
        }

        if let minimumEngineVersion = inspection.manifestMetadata?.minimumEngineVersion {
            facts.append(MinecraftPackageQuickLookFact(label: "Minimum Engine", value: minimumEngineVersion))
        }

        if let uuid = inspection.manifestMetadata?.uuid {
            facts.append(MinecraftPackageQuickLookFact(label: "UUID", value: uuid))
        }

        if let worldMetadata = inspection.worldMetadata {
            if let gameMode = worldMetadata.gameMode {
                facts.append(MinecraftPackageQuickLookFact(label: "Game Mode", value: gameMode))
            }
            if let difficulty = worldMetadata.difficulty {
                facts.append(MinecraftPackageQuickLookFact(label: "Difficulty", value: difficulty))
            }
            if let lastPlayedDate = worldMetadata.lastPlayedDate {
                facts.append(
                    MinecraftPackageQuickLookFact(
                        label: "Last Played",
                        value: formattedQuickLookDate(lastPlayedDate)
                    )
                )
            }
            if let seed = worldMetadata.seed {
                facts.append(MinecraftPackageQuickLookFact(label: "Seed", value: seed))
            }
            if let version = worldMetadata.lastOpenedWithVersion {
                facts.append(MinecraftPackageQuickLookFact(label: "Bedrock Version", value: version))
            }
        }

        return MinecraftPackageQuickLookModel(
            title: inspection.displayName,
            subtitle: subtitle,
            facts: facts
        )
    }

    nonisolated private static func subtitle(for contentType: MinecraftContentType) -> String {
        switch contentType {
        case .world:
            return "Minecraft World"
        case .behaviorPack:
            return "Behavior Pack"
        case .resourcePack:
            return "Resource Pack"
        case .skinPack:
            return "Skin Pack"
        case .worldTemplate:
            return "World Template"
        }
    }

    nonisolated private static func formattedQuickLookDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
