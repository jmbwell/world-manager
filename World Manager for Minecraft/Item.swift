//
//  Item.swift
//  World Manager for Minecraft
//
//  Created by John Burwell on 2026-05-25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
