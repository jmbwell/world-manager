// SPDX-FileCopyrightText: 2026 John Burwell and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct SourceCandidateDetailView: View {
    let candidate: SourceCandidate
    let addAction: () -> Void
    let revealAction: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(candidate.displayName)
                        .font(.largeTitle.weight(.semibold))

                    Text("Found source candidate")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button("Add Source") {
                        addAction()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Reveal in Finder") {
                        revealAction()
                    }
                    .buttonStyle(.bordered)
                }

                sourceSection(title: "Overview", rows: overviewRows)
                sourceSection(title: "Detected Content", rows: contentRows)
                sourceSection(title: "Location", rows: locationRows)
                sourceSection(title: "Technical Details", rows: technicalRows)
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(28)
        }
    }

    private var overviewRows: [(String, String)] {
        [
            ("Edition", editionLabel),
            ("Provider", providerLabel),
            ("Confidence", confidenceLabel),
            ("Reason", candidate.reason)
        ]
    }

    private var contentRows: [(String, String)] {
        guard !candidate.detectedKinds.isEmpty else {
            return [("Detected Kinds", "None")]
        }

        return [("Detected Kinds", orderedKindLabels.joined(separator: ", "))]
    }

    private var locationRows: [(String, String)] {
        [
            ("Filesystem Path", candidate.sourceRootURL.path)
        ]
    }

    private var technicalRows: [(String, String)] {
        [
            ("Provider ID", candidate.providerID),
            ("Candidate ID", candidate.id)
        ]
    }

    private var editionLabel: String {
        switch candidate.edition {
        case .bedrock:
            return "Bedrock"
        case .java:
            return "Java"
        }
    }

    private var providerLabel: String {
        switch candidate.providerID {
        case JavaLocalFolderSourceAccess().accessorIdentifier:
            return "Java Local Folder"
        case LocalFolderSourceAccess().accessorIdentifier:
            return "Bedrock Local Folder"
        case AppleMobileDeviceSourceAccess().accessorIdentifier:
            return "Bedrock iOS Device"
        default:
            return candidate.providerID
        }
    }

    private var confidenceLabel: String {
        switch candidate.confidence {
        case .none:
            return "None"
        case .weak:
            return "Weak"
        case .medium:
            return "Medium"
        case .strong:
            return "Strong"
        case .exact:
            return "Exact"
        }
    }

    private var orderedKindLabels: [String] {
        let orderedKinds: [(MinecraftContentKind, String)] = [
            (.world, "Worlds"),
            (.behaviorPack, "Behavior Packs"),
            (.resourcePack, "Resource Packs"),
            (.dataPack, "Data Packs"),
            (.skinPack, "Skin Packs"),
            (.worldTemplate, "World Templates"),
            (.shaderPack, "Shader Packs"),
            (.mod, "Mods")
        ]

        return orderedKinds.compactMap { kind, label in
            candidate.detectedKinds.contains(kind) ? label : nil
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
