//
//  SaveSlotsSection.swift
//  AntiMatter
//
//  Multi-save slot UI for the Options tab. Surfaces the 3 save slots that
//  already exist in GameStorage.saves[0..2] — tap a card to open its action
//  sheet (switch / rename / export / restore / delete). Backup restore opens
//  a half-height sheet (BackupListSheet).
//
//  Data is pulled on demand via engine.loadSaveSlots() and refreshed after
//  each mutating action. Not polled per-tick.
//

import SwiftUI
import UIKit

struct SaveSlotsSection: View {
    let engine: GameEngine

    @State private var snapshot: SaveSlotsSnapshot = .empty
    @State private var pendingAction: SlotPendingAction?
    @State private var renamingSlot: SaveSlotInfo?
    @State private var renameDraft: String = ""
    @State private var deleteConfirmSlot: SaveSlotInfo?
    @State private var switchConfirmSlot: SaveSlotInfo?
    @State private var backupSheetSlot: SaveSlotInfo?



    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Save Slots")
                    .font(.headline)
                Spacer()
            }

            Text("Keep up to 3 independent games. Tap a slot for actions.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { idx in
                    let slot = slotAt(idx)
                    SlotCard(slot: slot) {
                        pendingAction = .init(slot: slot)
                    }
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .onAppear { refresh() }
        // engine.saveSignal bumps after every GameStorage.save (autosave,
        // manual save, import, hard reset, slot switch, backup restore). This
        // catches the import-into-slot case where the card was blank until
        // the user left and returned — refresh lands immediately now.
        .onChange(of: engine.saveSignal) { _, _ in refresh() }
        .confirmationDialog(
            actionDialogTitle,
            isPresented: actionSheetBinding,
            titleVisibility: .visible,
            presenting: pendingAction
        ) { action in
            actionButtons(for: action.slot)
        }
        .alert("Switch Slot", isPresented: switchAlertBinding, presenting: switchConfirmSlot) { slot in
            Button("Switch", role: .destructive) {
                engine.switchSaveSlot(slot.id) { _ in refresh() }
            }
            Button("Cancel", role: .cancel) { }
        } message: { slot in
            Text("Switch to Slot \(slot.id + 1)? Your current slot will be saved first and remains untouched.")
        }
        .alert("Delete Slot", isPresented: deleteAlertBinding, presenting: deleteConfirmSlot) { slot in
            Button("Delete", role: .destructive) {
                engine.deleteSaveSlot(slot.id) { _ in refresh() }
            }
            Button("Cancel", role: .cancel) { }
        } message: { slot in
            Text("Permanently delete Slot \(slot.id + 1)? This cannot be undone.")
        }
        .alert("Rename Slot", isPresented: renameAlertBinding, presenting: renamingSlot) { slot in
            TextField("Slot name", text: $renameDraft)
            Button("Save") {
                engine.renameSaveSlot(slot.id, name: renameDraft) { _ in refresh() }
            }
            Button("Cancel", role: .cancel) { }
        } message: { slot in
            Text("Give Slot \(slot.id + 1) a nickname.")
        }
        .sheet(item: $backupSheetSlot) { slot in
            BackupListSheet(engine: engine, slot: slot) {
                refresh()
            }
        }
    }

    // MARK: - Data

    private func slotAt(_ idx: Int) -> SaveSlotInfo {
        if let existing = snapshot.slots.first(where: { $0.id == idx }) {
            return existing
        }
        return SaveSlotInfo(
            id: idx,
            isEmpty: true,
            isActive: snapshot.current == idx,
            saveFileName: "",
            antimatter: "0",
            realities: "0",
            eternities: "0",
            infinitied: "0",
            realTimePlayed: "0s",
            lastUpdate: 0,
            stage: "Empty"
        )
    }

    private func refresh() {
        engine.loadSaveSlots { snap in
            snapshot = snap
        }
    }

    // MARK: - Action sheet

    private var actionDialogTitle: String {
        guard let action = pendingAction else { return "" }
        let name = action.slot.saveFileName.isEmpty ? "Slot \(action.slot.id + 1)" : action.slot.saveFileName
        return name
    }

    private var actionSheetBinding: Binding<Bool> {
        Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } })
    }

    private var switchAlertBinding: Binding<Bool> {
        Binding(get: { switchConfirmSlot != nil }, set: { if !$0 { switchConfirmSlot = nil } })
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(get: { deleteConfirmSlot != nil }, set: { if !$0 { deleteConfirmSlot = nil } })
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(get: { renamingSlot != nil }, set: { if !$0 { renamingSlot = nil } })
    }

    @ViewBuilder
    private func actionButtons(for slot: SaveSlotInfo) -> some View {
        if slot.isEmpty {
            Button("Start New Game Here") {
                switchConfirmSlot = slot
            }
            Button("Cancel", role: .cancel) { }
        } else {
            if !slot.isActive {
                Button("Switch to This Slot") {
                    switchConfirmSlot = slot
                }
            }
            Button("Rename") {
                renameDraft = slot.saveFileName
                renamingSlot = slot
            }
            Button("Export to Clipboard") {
                engine.exportSaveSlot(slot.id)
            }
            Button("Restore from Backup…") {
                backupSheetSlot = slot
            }
            if !slot.isActive {
                Button("Delete", role: .destructive) {
                    deleteConfirmSlot = slot
                }
            }
            Button("Cancel", role: .cancel) { }
        }
    }
}

// MARK: - Per-slot card

private struct SlotCard: View {
    let slot: SaveSlotInfo
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(titleText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        if slot.isActive {
                            Text("ACTIVE")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(GameColor.good.opacity(0.25), in: Capsule())
                                .foregroundStyle(GameColor.good)
                        }
                        Spacer(minLength: 0)
                    }

                    if slot.isEmpty {
                        Text("Empty — tap to start a new game here")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(slot.stage)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(stageColor)
                                Text("•")
                                    .foregroundStyle(.secondary)
                                Text("\(slot.antimatter) AM")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 8) {
                                if Int(slot.realities) ?? 0 > 0 {
                                    Text("\(slot.realities) realities")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                } else if Int(slot.eternities) ?? 0 > 0 {
                                    Text("\(slot.eternities) eternities")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                } else if Int(slot.infinitied) ?? 0 > 0 {
                                    Text("\(slot.infinitied) infinities")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text(slot.realTimePlayed + " played")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("• " + lastUpdateText)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(cardBorder, lineWidth: slot.isActive ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var titleText: String {
        let base = "Slot \(slot.id + 1)"
        if slot.saveFileName.isEmpty { return base }
        return "\(base): \(slot.saveFileName)"
    }

    private var cardBackground: Color {
        slot.isActive ? GameColor.good.opacity(0.08) : Color.black.opacity(0.25)
    }

    private var cardBorder: Color {
        slot.isActive ? GameColor.good.opacity(0.6) : Color.white.opacity(0.15)
    }

    private var stageColor: Color {
        switch slot.stage {
        case "Reality", "Doomed": return GameColor.reality
        case "Eternity": return GameColor.eternity
        case "Infinity": return GameColor.infinity
        case "Empty": return .secondary
        default: return GameColor.antimatter
        }
    }

    private var lastUpdateText: String {
        guard slot.lastUpdate > 0 else { return "never" }
        let date = Date(timeIntervalSince1970: slot.lastUpdate / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Pending action wrapper

private struct SlotPendingAction: Identifiable {
    let slot: SaveSlotInfo
    var id: Int { slot.id }
}
