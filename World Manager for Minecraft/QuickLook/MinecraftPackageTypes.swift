//
//  MinecraftPackageTypes.swift
//  World Manager for Minecraft
//
//  Created by OpenAI on 2026-05-26.
//

import Foundation
import UniformTypeIdentifiers

struct MinecraftPackageTypeDefinition: Sendable, Hashable {
    let contentType: MinecraftContentType?
    let pathExtension: String
    let utTypeIdentifier: String
    let displayName: String
}

enum MinecraftPackageTypes {
    nonisolated static let world = MinecraftPackageTypeDefinition(
        contentType: .world,
        pathExtension: "mcworld",
        utTypeIdentifier: "us.b-wells.minecraft.mcworld",
        displayName: "Minecraft World"
    )

    nonisolated static let pack = MinecraftPackageTypeDefinition(
        contentType: nil,
        pathExtension: "mcpack",
        utTypeIdentifier: "us.b-wells.minecraft.mcpack",
        displayName: "Minecraft Pack"
    )

    nonisolated static let template = MinecraftPackageTypeDefinition(
        contentType: .worldTemplate,
        pathExtension: "mctemplate",
        utTypeIdentifier: "us.b-wells.minecraft.mctemplate",
        displayName: "Minecraft World Template"
    )

    nonisolated static let addon = MinecraftPackageTypeDefinition(
        contentType: nil,
        pathExtension: "mcaddon",
        utTypeIdentifier: "us.b-wells.minecraft.mcaddon",
        displayName: "Minecraft Add-On"
    )

    nonisolated static let all: [MinecraftPackageTypeDefinition] = [
        world,
        pack,
        template,
        addon
    ]

    nonisolated static func definition(for pathExtension: String) -> MinecraftPackageTypeDefinition? {
        all.first { $0.pathExtension == pathExtension.lowercased() }
    }

    nonisolated static func supportedContentType(for url: URL) -> UTType? {
        definition(for: url.pathExtension).flatMap { UTType($0.utTypeIdentifier) }
    }
}

extension UTType {
    static let minecraftWorld = UTType(exportedAs: MinecraftPackageTypes.world.utTypeIdentifier, conformingTo: .zip)
    static let minecraftPack = UTType(exportedAs: MinecraftPackageTypes.pack.utTypeIdentifier, conformingTo: .zip)
    static let minecraftTemplate = UTType(exportedAs: MinecraftPackageTypes.template.utTypeIdentifier, conformingTo: .zip)
    static let minecraftAddon = UTType(exportedAs: MinecraftPackageTypes.addon.utTypeIdentifier, conformingTo: .zip)
}
