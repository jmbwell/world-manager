//
//  ScanNotificationService.swift
//  World Manager for Minecraft
//
//  Created by Codex on 2026-05-27.
//

import AppKit
import Foundation
import UserNotifications

@MainActor
protocol ScanNotificationServicing: AnyObject {
    func requestAuthorizationIfNeeded() async
    func notifyScanCompleted(for source: MinecraftSource, duration: TimeInterval) async
}

@MainActor
final class ScanNotificationService: NSObject, ScanNotificationServicing {
    static let shared = ScanNotificationService()

    static let longScanThreshold: TimeInterval = 8

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
    }

    func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else {
            return
        }

        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return
        }
    }

    func notifyScanCompleted(for source: MinecraftSource, duration: TimeInterval) async {
        guard shouldNotifyAboutCompletedScan(duration: duration, isAppActive: NSApp.isActive) else {
            return
        }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Scan complete"
        content.subtitle = source.displayName
        content.body = Self.completionMessage(itemCount: source.indexedItemCount)
        content.sound = .default

        let identifier = "scan-complete-\(source.id.absoluteString)-\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        do {
            try await center.add(request)
        } catch {
            return
        }
    }

    func shouldNotifyAboutCompletedScan(duration: TimeInterval, isAppActive: Bool) -> Bool {
        duration >= Self.longScanThreshold && !isAppActive
    }

    nonisolated static func completionMessage(itemCount: Int) -> String {
        switch itemCount {
        case 0:
            return "No worlds or packs were found."
        case 1:
            return "Found 1 item."
        default:
            return "Found \(itemCount) items."
        }
    }
}
