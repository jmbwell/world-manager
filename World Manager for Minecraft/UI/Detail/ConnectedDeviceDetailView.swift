// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct ConnectedDeviceDetailView: View {
    let entry: ConnectedDeviceSidebarEntry
    let addAction: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.device.name)
                        .font(.largeTitle.weight(.semibold))

                    Text("Available connected device")
                        .foregroundStyle(.secondary)
                }

                if let addAction {
                    Button("Add Source") {
                        addAction()
                    }
                    .buttonStyle(.borderedProminent)
                }

                sourceSection(title: "Overview", rows: overviewRows)
                sourceSection(title: "Minecraft Access", rows: minecraftRows)
                sourceSection(title: "Technical Details", rows: technicalRows)
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(28)
        }
    }

    private var overviewRows: [(String, String)] {
        var rows: [(String, String)] = [
            ("Connection", connectionLabel),
            ("Trust State", trustStateLabel),
            ("Availability", entry.hasMinecraftContainer ? "Ready to add" : "Not ready")
        ]

        if let productType = entry.device.productType, !productType.isEmpty {
            rows.append(("Product Type", productType))
        }
        if let osVersion = entry.device.osVersion, !osVersion.isEmpty {
            rows.append(("OS Version", osVersion))
        }

        return rows
    }

    private var minecraftRows: [(String, String)] {
        if let error = entry.discoveryErrorDescription, !error.isEmpty {
            return [("Discovery Error", error)]
        }

        guard let container = entry.minecraftContainer else {
            return [("Minecraft Container", "Not found")]
        }

        var rows: [(String, String)] = [
            ("Minecraft Container", container.appName),
            ("App ID", container.appID),
            ("Access Mode", container.accessMode.rawValue)
        ]

        if let relativePath = container.minecraftFolderRelativePath, !relativePath.isEmpty {
            rows.append(("Minecraft Path", relativePath))
        }

        return rows
    }

    private var technicalRows: [(String, String)] {
        [
            ("UDID", entry.device.udid),
            ("Device ID", entry.id)
        ]
    }

    private var connectionLabel: String {
        switch entry.device.connection {
        case .usb:
            return "USB"
        case .network:
            return "Network"
        }
    }

    private var trustStateLabel: String {
        switch entry.device.trustState {
        case .trusted:
            return "Trusted"
        case .locked:
            return "Locked"
        case .untrusted:
            return "Untrusted"
        case .unavailable:
            return "Unavailable"
        }
    }

    @ViewBuilder
    private func sourceSection(title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .appSectionTitleStyle(.section)

            VStack(spacing: 0) {
                ForEach(rows, id: \.0) { title, value in
                    detailRow(title: title, value: value)
                }
            }
            .appDetailSectionCard()
        }
    }

    @ViewBuilder
    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .appTextStyle(.fieldLabel)
                .frame(width: 150, alignment: .leading)

            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
    }
}
