//
//  CloudFirstEnableSheet.swift
//  AntiMatter
//
//  One-shot sheet shown the first time the user turns on iCloud sync on
//  a device that already has a local save AND finds a save on iCloud.
//  Forces an explicit choice: upload this device's save, download the
//  cloud save (after a secondary confirmation since it overwrites local),
//  or cancel.
//
//  When only one side has data, CloudSaveService auto-routes without
//  showing this sheet.
//

import SwiftUI

struct CloudFirstEnableSheet: View {
    let engine: GameEngine
    let prompt: FirstEnablePrompt

    @Environment(\.dismiss) private var dismiss
    @State private var showDownloadWarning = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header

                    cloudSideCard

                    VStack(spacing: 10) {
                        GameButton(borderColor: GameColor.good) {
                            prompt.onResolve(.uploadLocal)
                            dismiss()
                        } label: {
                            VStack(spacing: 2) {
                                Text("Upload this device's save")
                                    .font(.subheadline.weight(.semibold))
                                Text("Overwrites whatever's in iCloud")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }

                        GameButton(borderColor: GameColor.infinity) {
                            showDownloadWarning = true
                        } label: {
                            VStack(spacing: 2) {
                                Text("Download iCloud save")
                                    .font(.subheadline.weight(.semibold))
                                Text("Replaces this device's current slot")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }

                        Button(role: .cancel) {
                            prompt.onResolve(.cancel)
                            dismiss()
                        } label: {
                            Text("Not now")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                    }
                }
                .padding()
            }
            .background(GameColor.baseBackground)
            .adaptiveSheetTitle("Sync to iCloud")
            .alert("Overwrite local save?", isPresented: $showDownloadWarning) {
                Button("Replace", role: .destructive) {
                    prompt.onResolve(.downloadCloud)
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Your current progress on this device will be replaced by the iCloud save. This can't be undone. Consider exporting your current save to clipboard first.")
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Both sides have data")
                .font(.headline)
            Text("This device and iCloud each have a save for slot \(prompt.slotId + 1). Choose which one should become the canonical version.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var cloudSideCard: some View {
        if let meta = prompt.cloudMeta {
            VStack(alignment: .leading, spacing: 6) {
                Text("iCloud save")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GameColor.infinity)

                VStack(alignment: .leading, spacing: 4) {
                    infoRow("Device", meta.deviceName.isEmpty ? "—" : meta.deviceName)
                    if !meta.saveFileName.isEmpty {
                        infoRow("Name", meta.saveFileName)
                    }
                    if !meta.stage.isEmpty {
                        infoRow("Stage", meta.stage)
                    }
                    infoRow("Written", relativeDateString(seconds: meta.writtenAt))
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(GameColor.infinity.opacity(0.4), lineWidth: 1)
            )
        }
    }

    private func infoRow(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func relativeDateString(seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "never" }
        let date = Date(timeIntervalSince1970: seconds)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
