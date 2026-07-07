//
//  CloudConflictSheet.swift
//  AntiMatter
//
//  Shown when a cloud save conflict is detected (on foreground, on the
//  external-change notification, or on manual Sync now). Mirrors web's
//  `CloudSaveConflictModal.vue` — side-by-side comparison of Local vs
//  Cloud, with Keep local / Use cloud / Cancel actions.
//
//  The conflict itself is built in CloudSaveService.compareAndSurface and
//  observed via `engine.cloudSaveService?.pendingConflict`. Caller presents
//  this sheet with `.sheet(item:)` bound to that Identifiable optional.
//

import SwiftUI

struct CloudConflictSheet: View {
    let engine: GameEngine
    let conflict: CloudSaveConflict

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    summary
                    comparisonCards
                    warningBanner
                    actions
                }
                .padding()
            }
            .background(GameColor.baseBackground)
            .adaptiveSheetTitle("iCloud Conflict")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        engine.cloudSaveService?.dismissConflict()
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Summary

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headline)
                .font(.headline)
            Text(body_)
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

    private var headline: String {
        switch conflict.source {
        case .foreground:      "Your cloud save has changed"
        case .externalChange:  "Another device just saved"
        case .manualSync:      "Slot \(conflict.slotId + 1) differs from iCloud"
        }
    }

    private var body_: String {
        var parts: [String] = []
        let c = conflict.comparison
        if c.farther == -1 {
            parts.append("iCloud has made more progress than this device.")
        } else if c.farther == 1 {
            parts.append("This device has made more progress than iCloud.")
        }
        if c.hashMismatch {
            parts.append("iCloud was updated since you last pulled.")
        }
        if c.differentName {
            parts.append("The save file names are different.")
        }
        if parts.isEmpty {
            parts.append("Resolve the conflict by choosing which version to keep.")
        }
        if let writer = conflict.cloudMetaWriter {
            parts.append("Last written on \(writer).")
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Comparison

    private var comparisonCards: some View {
        HStack(alignment: .top, spacing: 10) {
            sideCard(
                title: "This Device",
                accent: .white,
                meta: conflict.comparison.local,
                isBetter: isLocalBetter
            )
            sideCard(
                title: "iCloud",
                accent: GameColor.infinity,
                meta: conflict.comparison.cloud,
                isBetter: isCloudBetter
            )
        }
    }

    private func sideCard(title: String, accent: Color, meta: CloudSideMeta?, isBetter: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                Spacer()
                if isBetter {
                    Text("AHEAD")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(GameColor.good.opacity(0.25), in: Capsule())
                        .foregroundStyle(GameColor.good)
                }
            }

            if let meta {
                VStack(alignment: .leading, spacing: 4) {
                    label("Stage", meta.stage.isEmpty ? "—" : meta.stage)
                    label("Antimatter", meta.antimatter)
                    if Int(meta.realities) ?? 0 > 0 {
                        label("Realities", meta.realities)
                    } else if Int(meta.eternities) ?? 0 > 0 {
                        label("Eternities", meta.eternities)
                    } else if Int(meta.infinitied) ?? 0 > 0 {
                        label("Infinities", meta.infinitied)
                    }
                    label("Time played", meta.realTimePlayed)
                    if !meta.saveFileName.isEmpty {
                        label("Save name", meta.saveFileName)
                    }
                    if meta.lastUpdate > 0 {
                        label("Last updated", relativeDateString(ms: meta.lastUpdate))
                    }
                }
            } else {
                Text("Empty")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isBetter ? GameColor.good.opacity(0.5) : Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    private func label(_ name: String, _ value: String) -> some View {
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

    // MARK: - Warning

    @ViewBuilder
    private var warningBanner: some View {
        if isLosingProgress {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(GameColor.antimatter)
                Text("Choosing the smaller save will **lose progress** on this slot. Consider exporting the ahead version to clipboard first as a backup.")
                    .font(.caption)
                    .foregroundStyle(.white)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GameColor.antimatter.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(GameColor.antimatter.opacity(0.5), lineWidth: 1)
            )
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 10) {
            GameButton(borderColor: keepLocalBorder) {
                engine.cloudSaveService?.resolveConflictKeepLocal()
                dismiss()
            } label: {
                Text("Keep this device's save")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }

            GameButton(borderColor: useCloudBorder) {
                engine.cloudSaveService?.resolveConflictUseCloud()
                dismiss()
            } label: {
                Text("Use iCloud save")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }

            Button(role: .cancel) {
                engine.cloudSaveService?.dismissConflict()
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Derived

    private var isLocalBetter: Bool { conflict.comparison.farther == 1 }
    private var isCloudBetter: Bool { conflict.comparison.farther == -1 }

    /// True when either side is ahead and we're about to overwrite it —
    /// the user is about to actively lose progress in that direction.
    private var isLosingProgress: Bool {
        conflict.comparison.farther != 0
    }

    /// Green border when keeping local means keeping the ahead version;
    /// red-tinted when local is behind.
    private var keepLocalBorder: Color {
        isLocalBetter ? GameColor.good : GameColor.antimatter
    }

    private var useCloudBorder: Color {
        isCloudBetter ? GameColor.good : GameColor.antimatter
    }

    private func relativeDateString(ms: Double) -> String {
        guard ms > 0 else { return "never" }
        let date = Date(timeIntervalSince1970: ms / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
