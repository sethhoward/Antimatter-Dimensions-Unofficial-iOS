//
//  GlyphPresetsSheet.swift
//  AntiMatter
//
//  Modal sheet for Glyph Presets. Ports `GlyphSetSavePanel.vue` to a native
//  iOS sheet — three global matching toggles at top, 7 preset slots below.
//
//  The sheet has two modes:
//    • Slot list (default) — shows the 7 rows with Save/Load/Delete per row
//      and the global toggles at top.
//    • Diff preview (`pendingLoad != nil`) — morphed in-place when the user
//      taps Load. Shows per-saved-slot diff (saved → will-equip + match
//      kind), summary, and Cancel/Confirm buttons. Confirming applies the
//      load (mid-Reality, first calls `resetRealityForPresetLoad`).
//

import SwiftUI

struct GlyphPresetsSheet: View {
    let engine: GameEngine

    @Environment(\.dismiss) private var dismiss
    @Environment(\.layoutMetrics) private var metrics

    @State private var snapshot: GlyphPresetsSnapshot = .empty
    @State private var pendingLoad: GlyphLoadResult?
    @State private var pendingDeleteId: Int?
    @State private var isMutating = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let preview = pendingLoad {
                    diffView(for: preview)
                        .padding(.vertical, 12)
                } else {
                    slotListView
                        .padding(.vertical, 12)
                }
            }
            .background(GameColor.baseBackground)
            .adaptiveSheetTitle(pendingLoad == nil ? "Glyph Presets" : "Confirm Load")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(pendingLoad == nil ? "Done" : "Back") {
                        if pendingLoad != nil {
                            pendingLoad = nil
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .onAppear { refresh() }
            .alert("Delete Preset", isPresented: deleteAlertBinding, presenting: pendingDeleteId) { id in
                Button("Delete", role: .destructive) { performDelete(id: id) }
                Button("Cancel", role: .cancel) { pendingDeleteId = nil }
            } message: { id in
                let name = snapshot.sets[id].name
                if name.isEmpty {
                    Text("Delete Preset \(id + 1)? This won't sacrifice or remove the glyphs themselves.")
                } else {
                    Text("Delete '\(name)'? This won't sacrifice or remove the glyphs themselves.")
                }
            }
        }
    }

    // MARK: - Slot list

    @ViewBuilder
    private var slotListView: some View {
        VStack(spacing: 14) {
            togglesSection
            helpText
            ForEach(snapshot.sets) { slot in
                GlyphPresetRow(
                    slot: slot,
                    hasEquipped: snapshot.hasEquipped,
                    activeSlotCount: snapshot.activeSlotCount,
                    freeInventorySlots: snapshot.freeInventorySlots,
                    isMutating: isMutating,
                    onSave: { performSave(id: slot.id) },
                    onLoad: { performPreview(id: slot.id) },
                    onDelete: { pendingDeleteId = slot.id },
                    onRename: { newName in performRename(id: slot.id, name: newName) }
                )
                .padding(.horizontal, 12)
            }
        }
    }

    private var togglesSection: some View {
        let buttons: [(String, String, Bool, () -> Void)] = [
            ("Effects",
             snapshot.ignoreEffects ? "Including" : "Exact",
             snapshot.ignoreEffects,
             { toggleMatch(kind: "effects", on: !snapshot.ignoreEffects) }),
            ("Level",
             snapshot.ignoreLevel ? "Increased" : "Exact",
             snapshot.ignoreLevel,
             { toggleMatch(kind: "level", on: !snapshot.ignoreLevel) }),
            ("Rarity",
             snapshot.ignoreRarity ? "Increased" : "Exact",
             snapshot.ignoreRarity,
             { toggleMatch(kind: "rarity", on: !snapshot.ignoreRarity) })
        ]
        return HStack(spacing: 8) {
            ForEach(buttons, id: \.0) { tuple in
                let (label, modeText, _, action) = tuple
                GameButton(borderColor: .green, isEnabled: true) {
                    action()
                } label: {
                    VStack(spacing: 2) {
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(modeText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private var helpText: some View {
        Text("When loading a preset, try to match the following attributes. \"Exact\" will only equip Glyphs identical to the ones in the preset. The other settings will, loosely speaking, allow \"better\" Glyphs to be equipped in their place.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
    }

    // MARK: - Diff preview

    private func diffView(for result: GlyphLoadResult) -> some View {
        VStack(spacing: 14) {
            // Title row
            VStack(spacing: 4) {
                Text(result.presetName.isEmpty
                     ? "Preset \(result.presetId + 1)"
                     : result.presetName)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(result.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)

            // Per-slot diff
            VStack(spacing: 8) {
                ForEach(Array(result.slots.enumerated()), id: \.offset) { idx, slot in
                    GlyphPresetDiffRow(slotIndex: idx, slot: slot)
                        .padding(.horizontal, 12)
                }
            }

            // Action row
            HStack(spacing: 10) {
                GameButton(borderColor: .white.opacity(0.6), isEnabled: !isMutating) {
                    pendingLoad = nil
                } label: {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                GameButton(borderColor: .green, isEnabled: !isMutating) {
                    performLoad(presetId: result.presetId)
                } label: {
                    Text("Confirm")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Bindings

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteId != nil },
            set: { if !$0 { pendingDeleteId = nil } }
        )
    }

    // MARK: - Actions

    private func refresh() {
        engine.loadGlyphPresets { snap in
            snapshot = snap
        }
    }

    private func toggleMatch(kind: String, on: Bool) {
        // Optimistic: flip the snapshot locally so the toggle label updates
        // instantly. Then refresh to confirm.
        switch kind {
        case "effects": snapshot.ignoreEffects = on
        case "level": snapshot.ignoreLevel = on
        case "rarity": snapshot.ignoreRarity = on
        default: break
        }
        engine.setGlyphMatchToggle(kind, on: on) {
            refresh()
        }
    }

    private func performSave(id: Int) {
        isMutating = true
        engine.saveGlyphPreset(id) { _ in
            isMutating = false
            refresh()
        }
    }

    private func performDelete(id: Int) {
        pendingDeleteId = nil
        isMutating = true
        engine.deleteGlyphPreset(id) { _ in
            isMutating = false
            refresh()
        }
    }

    private func performRename(id: Int, name: String) {
        engine.renameGlyphPreset(id, name: name)
        // No refresh — the row owns its own local edit state and we trust
        // the cap is applied JS-side; a per-keystroke refresh would jitter.
    }

    private func performPreview(id: Int) {
        isMutating = true
        engine.previewLoadGlyphPreset(id) { result in
            isMutating = false
            switch result {
            case .success(let info):
                if info.requiresPreview {
                    pendingLoad = info
                } else {
                    // Fully-exact: skip the diff modal and apply
                    // immediately. Toast surfaces the result.
                    performLoad(presetId: id)
                }
            case .failure:
                refresh()
            }
        }
    }

    private func performLoad(presetId: Int) {
        isMutating = true
        engine.loadGlyphPreset(presetId) { result in
            isMutating = false
            pendingLoad = nil
            switch result {
            case .success:
                refresh()
                dismiss()
            case .failure:
                // Refresh in case state changed; keep sheet open so the
                // user can see the slot they tapped.
                refresh()
            }
        }
    }
}

// MARK: - Preset slot row

struct GlyphPresetRow: View {
    let slot: GlyphLoadoutSlot
    let hasEquipped: Bool
    let activeSlotCount: Int
    let freeInventorySlots: Int
    let isMutating: Bool

    let onSave: () -> Void
    let onLoad: () -> Void
    let onDelete: () -> Void
    let onRename: (String) -> Void

    @State private var editingName: String = ""
    @Environment(\.layoutMetrics) private var metrics

    private var isEmpty: Bool { slot.isEmpty }

    private var loadDisabledReason: String? {
        if isEmpty { return nil }
        if slot.glyphs.count > activeSlotCount {
            return "Needs \(slot.glyphs.count) active slots (you have \(activeSlotCount))"
        }
        // No inventory-space pre-check — web's matcher keeps already-equipped
        // glyphs that satisfy saved entries and only fills empty active slots.
        // The matcher reports any genuine deficit via the per-slot match
        // results surfaced in the diff preview after Load is tapped.
        return nil
    }

    private var canSave: Bool { !isMutating && hasEquipped && isEmpty }
    private var canLoad: Bool { !isMutating && !isEmpty && loadDisabledReason == nil }
    private var canDelete: Bool { !isMutating && !isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            previewRow
            nameField
            buttonRow
            if let reason = loadDisabledReason {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(GameColor.badPink)
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .onAppear { editingName = slot.name }
        .onChange(of: slot.name) { _, newValue in editingName = newValue }
    }

    private var previewRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header line — saved name (if any) + slot number, with the
            // auto-derived "Powerful Infinite Time" cute name underneath.
            HStack(spacing: 6) {
                if slot.name.isEmpty {
                    Text("Preset \(slot.id + 1)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(Text("Preset \(slot.id + 1): ").foregroundStyle(.secondary))\(Text(slot.name).foregroundStyle(.white))")
                        .font(.caption.weight(.semibold))
                }
                Spacer(minLength: 0)
            }

            // Glyph row + cute auto-name underneath
            if isEmpty {
                Text("No Glyph Preset saved in this slot")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        ForEach(slot.glyphs) { g in
                            MiniPresetGlyph(glyph: g, size: 32)
                        }
                        Spacer(minLength: 0)
                    }
                    if !slot.autoName.isEmpty {
                        Text(slot.autoName)
                            .font(.caption2.italic())
                            .foregroundStyle(Color(hex: slot.glyphs.first?.typeColor ?? "#888"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var nameField: some View {
        TextField("Custom set name", text: $editingName)
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .submitLabel(.done)
            .onSubmit { onRename(editingName) }
            .onChange(of: editingName) { _, newValue in
                let trimmed = String(newValue.prefix(20))
                if trimmed != newValue { editingName = trimmed }
            }
    }

    private var buttonRow: some View {
        HStack(spacing: 8) {
            GameButton(borderColor: canSave ? .green : .gray, isEnabled: canSave) {
                onSave()
            } label: {
                Text("Save")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            GameButton(borderColor: canLoad ? GameColor.reality : .gray, isEnabled: canLoad) {
                onLoad()
            } label: {
                Text("Load")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            GameButton(borderColor: canDelete ? GameColor.badPink : .gray, isEnabled: canDelete) {
                onDelete()
            } label: {
                Text("Delete")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
        }
    }
}

// MARK: - Mini preset glyph

/// Compact glyph tile used inside preset rows + diff previews. Mirrors
/// `GlyphComponent` styling (circular, rarity-colored symbol with glow,
/// type-colored border with glow, effect dots when there's room).
/// Distinct from `GlyphComponent` only because saved-glyph snapshots
/// carry the minimal `GlyphPresetGlyph` shape rather than full `GlyphInfo`.
struct MiniPresetGlyph: View, Equatable {
    let glyph: GlyphPresetGlyph
    var size: CGFloat = 24

    private var typeColor: Color { Color(hex: glyph.typeColor) }
    private var rarityColor: Color { Color(hex: glyph.rarityColor) }

    private var displaySymbol: String {
        glyph.symbol == "⸸" ? "†" : glyph.symbol
    }

    private var borderWidth: CGFloat { max(size * 0.06, 2) }

    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.06))

            Text(displaySymbol)
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(rarityColor)
                .shadow(color: rarityColor.opacity(0.5), radius: size * 0.04)

            // Effect dots along the bottom — only render when the tile has
            // enough room (matches GlyphComponent's `size >= 36` gate).
            if glyph.effectCount > 0 && size >= 36 {
                HStack(spacing: 2) {
                    ForEach(0..<glyph.effectCount, id: \.self) { _ in
                        Circle()
                            .fill(.white.opacity(0.7))
                            .frame(width: max(size * 0.06, 3), height: max(size * 0.06, 3))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, size * 0.08)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            Circle()
                .strokeBorder(typeColor, lineWidth: borderWidth)
                .shadow(color: typeColor.opacity(0.7), radius: size * 0.08)
        }
    }
}

// MARK: - Diff row (per-saved-glyph row in the load preview)

struct GlyphPresetDiffRow: View {
    let slotIndex: Int
    let slot: GlyphLoadSlotMatch

    var body: some View {
        HStack(spacing: 10) {
            Text("\(slotIndex + 1)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            // Saved
            if let saved = slot.savedGlyph {
                MiniPresetGlyph(glyph: saved, size: 32)
            } else {
                Color.clear.frame(width: 32, height: 32)
            }

            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.secondary)

            // Will-equip (or empty)
            if let will = slot.willEquipGlyph {
                MiniPresetGlyph(glyph: will, size: 32)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3]))
                        .frame(width: 32, height: 32)
                    Image(systemName: "questionmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Status badge
            HStack(spacing: 4) {
                if let color = slot.matchKind.badgeColor {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
                Text(slot.matchKind.label)
                    .font(.caption2)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
    }
}
