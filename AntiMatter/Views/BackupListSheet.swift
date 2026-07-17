//
//  BackupListSheet.swift
//  AntiMatter
//
//  Half-height sheet listing the 8 rolling backups for a save slot. The JS
//  game core already writes these automatically (AutoBackupSlots: 1 min, 5
//  min, 20 min, 1 h, offline 10 min, offline 1 h, offline 5 h, reserve) —
//  this view just surfaces them. Restoring a backup from a dormant slot
//  requires switching to that slot first (enforced both in JS and here).
//

import SwiftUI

struct BackupListSheet: View {
    let engine: GameEngine
    let slot: SaveSlotInfo
    let onRestored: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: SaveBackupsSnapshot = .empty(slotId: 0)
    @State private var restoreConfirm: SaveBackupInfo?
    @State private var isRestoring = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    if !slot.isActive {
                        inactiveNotice
                    }

                    Text("Automatic backups are created at fixed intervals. Older backups further down let you roll back further if something went wrong.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                    ForEach(snapshot.backups) { backup in
                        BackupCard(
                            backup: backup,
                            canRestore: slot.isActive && !backup.isEmpty && !isRestoring
                        ) {
                            restoreConfirm = backup
                        }
                    }

                    if snapshot.backups.allSatisfy(\.isEmpty) {
                        Text("No backups yet. They'll appear here as you play.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 20)
                    }
                }
                .padding(.vertical)
            }
            .background(GameColor.baseBackground)
            .adaptiveSheetTitle(headerTitle)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { refresh() }
            .alert("Restore Backup", isPresented: restoreAlertBinding, presenting: restoreConfirm) { backup in
                Button("Restore", role: .destructive) {
                    isRestoring = true
                    engine.restoreBackup(slotId: slot.id, backupId: backup.backupId) { ok in
                        isRestoring = false
                        if ok {
                            onRestored()
                            dismiss()
                        } else {
                            refresh()
                        }
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: { backup in
                Text("Replace your current progress in Slot \(slot.id + 1) with the \(backup.intervalLabel.lowercased().isEmpty ? "reserve" : backup.intervalLabel.lowercased()) backup? Your current progress will be lost.")
            }
        }
    }

    private var headerTitle: String {
        let base = slot.saveFileName.isEmpty ? "Slot \(slot.id + 1)" : slot.saveFileName
        return base + " Backups"
    }

    private var inactiveNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(GameColor.infinity)
            Text("Switch to this slot first to restore one of its backups.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GameColor.infinity.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
    }

    private var restoreAlertBinding: Binding<Bool> {
        Binding(get: { restoreConfirm != nil }, set: { if !$0 { restoreConfirm = nil } })
    }

    private func refresh() {
        engine.loadBackups(for: slot.id) { snap in
            snapshot = snap
        }
    }
}

// MARK: - Backup card

private struct BackupCard: View {
    let backup: SaveBackupInfo
    let canRestore: Bool
    let onRestore: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(typeBadge)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(typeColor.opacity(0.25), in: Capsule())
                        .foregroundStyle(typeColor)
                }

                if backup.isEmpty {
                    Text("No backup yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(backup.stage)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(stageColor)
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text("\(backup.antimatter) AM")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            if Int(backup.realities) ?? 0 > 0 {
                                Text("\(backup.realities) realities")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else if Int(backup.eternities) ?? 0 > 0 {
                                Text("\(backup.eternities) eternities")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(backup.realTimePlayed + " played")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if backup.date > 0 {
                                Text("• " + relativeDateText)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            GameButton(borderColor: canRestore ? .green : .gray, isEnabled: canRestore) {
                onRestore()
            } label: {
                Text("Restore")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .padding(.horizontal)
    }

    private var title: String {
        if !backup.intervalLabel.isEmpty {
            return "Every " + backup.intervalLabel
        }
        return "Reserve slot"
    }

    private var typeBadge: String {
        switch backup.type {
        case "offline": return "OFFLINE"
        case "reserve": return "RESERVE"
        default: return "ONLINE"
        }
    }

    private var typeColor: Color {
        switch backup.type {
        case "offline": return GameColor.infinity
        case "reserve": return GameColor.eternity
        default: return GameColor.good
        }
    }

    private var stageColor: Color {
        switch backup.stage {
        case "Reality", "Doomed": return GameColor.reality
        case "Eternity": return GameColor.eternity
        case "Infinity": return GameColor.infinity
        case "Empty": return .secondary
        default: return GameColor.antimatter
        }
    }

    private var relativeDateText: String {
        guard backup.date > 0 else { return "" }
        let date = Date(timeIntervalSince1970: backup.date / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
