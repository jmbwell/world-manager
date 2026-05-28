//
//  ConnectedDeviceSourcePickerView.swift
//  World Manager for Minecraft
//
//  Created by OpenAI on 2026-05-26.
//

import SwiftUI

struct ConnectedDeviceSourcePickerView: View {
    let deviceDiscoveryService: ConnectedDeviceSourceAccessMethod
    let sourceFactory: ConnectedDeviceSourceFactory
    let onAddSource: (MinecraftSource) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var devices: [ConnectedDevice] = []
    @State private var containers: [DeviceAppContainer] = []
    @State private var selectedDeviceID: ConnectedDevice.ID?
    @State private var selectedContainerID: DeviceAppContainer.ID?
    @State private var preferredMinecraftSubpath = "Documents/games/com.mojang"
    @State private var isLoadingDevices = false
    @State private var isLoadingContainers = false
    @State private var availabilityMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if let availabilityMessage {
                Text(availabilityMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 18)
            }

            HStack(alignment: .top, spacing: 18) {
                deviceColumn
                containerColumn
            }
            .frame(maxHeight: .infinity, alignment: .top)

            VStack(alignment: .leading, spacing: 8) {
                Text("Minecraft Subpath")
                    .font(.subheadline.weight(.semibold))
                TextField("Documents/games/com.mojang", text: $preferredMinecraftSubpath)
                    .textFieldStyle(.roundedBorder)
                Text("Used after the app container is mounted. The current proven path is `Documents/games/com.mojang`.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)

            footer
        }
        .frame(minWidth: 760, minHeight: 420)
        .padding(.vertical, 18)
        .task {
            await loadDevices()
        }
        .onChange(of: selectedDeviceID) { _, _ in
            Task {
                await loadContainersForSelectedDevice()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Add Connected Device Source")
                .font(.title2.weight(.semibold))
            Text("Choose a connected device source and scan its Minecraft documents just like a local folder.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
    }

    private var deviceColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Devices")
                    .font(.headline)

                Spacer()

                Button("Refresh") {
                    Task {
                        await loadDevices()
                    }
                }
                .disabled(isLoadingDevices)
            }

            Group {
                if isLoadingDevices {
                    loadingState("Searching for connected devices...")
                } else if devices.isEmpty {
                    emptyState("No devices found")
                } else {
                    List(devices, selection: $selectedDeviceID) { device in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.name)
                                .font(.subheadline.weight(.semibold))
                            Text(deviceSubtitle(device))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .tag(device.id)
                    }
                    .listStyle(.inset)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 18)
    }

    private var containerColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Accessible Apps")
                .font(.headline)

            Group {
                if selectedDevice == nil {
                    emptyState("Select a device to list file-sharing apps")
                } else if isLoadingContainers {
                    loadingState("Listing accessible app containers...")
                } else if containers.isEmpty {
                    emptyState("No accessible apps found for this device")
                } else {
                    List(containers, selection: $selectedContainerID) { container in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(container.appName)
                                .font(.subheadline.weight(.semibold))
                            Text(container.appID)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .tag(container.id)
                    }
                    .listStyle(.inset)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 18)
    }

    private var footer: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }

            Spacer()

            Button("Add Device Source") {
                guard let selectedDevice, let selectedContainer else {
                    return
                }

                var adjustedContainer = selectedContainer
                let trimmedSubpath = preferredMinecraftSubpath.trimmingCharacters(in: .whitespacesAndNewlines)
                adjustedContainer.minecraftFolderRelativePath = trimmedSubpath.isEmpty ? nil : trimmedSubpath
                let source = sourceFactory.makeSource(device: selectedDevice, container: adjustedContainer)
                onAddSource(source)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedDevice == nil || selectedContainer == nil)
        }
        .padding(.horizontal, 18)
    }

    private var selectedDevice: ConnectedDevice? {
        devices.first(where: { $0.id == selectedDeviceID })
    }

    private var selectedContainer: DeviceAppContainer? {
        containers.first(where: { $0.id == selectedContainerID })
    }

    private func loadDevices() async {
        isLoadingDevices = true
        availabilityMessage = nil
        errorMessage = nil
        let previousSelectedDeviceID = selectedDeviceID

        do {
            let devices = try await deviceDiscoveryService.listConnectedDevices()
            let resolvedSelectedDeviceID = devices.contains(where: { $0.id == previousSelectedDeviceID })
                ? previousSelectedDeviceID
                : devices.first?.id
            let shouldReloadContainers = resolvedSelectedDeviceID != nil && resolvedSelectedDeviceID == previousSelectedDeviceID

            await MainActor.run {
                self.devices = devices
                self.selectedDeviceID = resolvedSelectedDeviceID
                if devices.isEmpty {
                    self.containers = []
                    self.selectedContainerID = nil
                }
                self.isLoadingDevices = false
            }

            if shouldReloadContainers {
                await loadContainersForSelectedDevice()
            }
        } catch {
            await MainActor.run {
                self.devices = []
                self.containers = []
                self.selectedDeviceID = nil
                self.selectedContainerID = nil
                self.errorMessage = error.localizedDescription
                self.isLoadingDevices = false
                self.isLoadingContainers = false
            }
        }
    }

    private func loadContainersForSelectedDevice() async {
        guard let selectedDevice else {
            await MainActor.run {
                containers = []
                selectedContainerID = nil
                isLoadingContainers = false
            }
            return
        }

        isLoadingContainers = true
        availabilityMessage = nil
        errorMessage = nil

        do {
            let containers = try await deviceDiscoveryService.listAccessibleContainers(for: selectedDevice)
            await MainActor.run {
                self.containers = containers
                self.selectedContainerID = preferredContainerID(in: containers)
                self.isLoadingContainers = false
            }
        } catch {
            await MainActor.run {
                self.containers = []
                self.selectedContainerID = nil
                self.errorMessage = error.localizedDescription
                self.isLoadingContainers = false
            }
        }
    }

    private func preferredContainerID(in containers: [DeviceAppContainer]) -> DeviceAppContainer.ID? {
        if let minecraftContainer = containers.first(where: { $0.appID == "com.mojang.minecraftpe" }) {
            return minecraftContainer.id
        }

        return containers.first?.id
    }

    private func deviceSubtitle(_ device: ConnectedDevice) -> String {
        [
            device.productType,
            device.osVersion.map { "iOS/iPadOS \($0)" },
            device.connection == .network ? "Network" : "USB"
        ]
        .compactMap { $0 }
        .joined(separator: " • ")
    }

    private func loadingState(_ title: String) -> some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func emptyState(_ title: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
