//
//  EffarigGlyphPresetsSheet.swift
//  AntiMatter
//
//  Sheet unlocked by EffarigUnlock.setSaves — the 7-slot Glyph preset
//  save/load UI. Mirrors src/components/tabs/glyphs/sidebar/GlyphSetSavePanel.vue.
//  Match-loading logic (including ignoreGlyph* slack settings) is ported into
//  _nativeLoadGlyphPreset in celestial-helpers.js.
//

import SwiftUI

struct EffarigGlyphPresetsSheet: View {
    let engine: GameEngine
    @Environment(\.dismiss) private var dismiss

    @State private var renameTargets: [Int: String] = [:]
    @State private var pendingDelete: Int?

    private var state: EffarigPresetsState { engine.effarigGlyphPresets ?? EffarigPresetsState() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    leniencyCard
                    ForEach(state.slots) { slot in
                        slotCard(slot)
                    }
                }
                .padding(16)
            }
            .adaptiveSheetTitle("Glyph Presets")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .tint(GameColor.effarig)
                }
            }
        }
        .presentationDetents([.large])
        .task {
            engine.loadGlyphPresets()
        }
        .confirmationDialog("Delete preset?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { slot in
            Button("Delete", role: .destructive) {
                engine.deleteGlyphPreset(slot: slot)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("This permanently removes the saved Glyph loadout.")
        }
    }

    // MARK: - Leniency card

    private var leniencyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Matching leniency")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text("When loading a preset, allow better Glyphs to substitute for the saved ones if exact matches aren't available.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Effects (Include vs Exact)", isOn: Binding(
                get: { state.ignoreEffects },
                set: { engine.setGlyphPresetIgnore(field: "effects", value: $0) }
            )).tint(GameColor.effarig)
            Toggle("Rarity (Increased vs Exact)", isOn: Binding(
                get: { state.ignoreRarity },
                set: { engine.setGlyphPresetIgnore(field: "rarity", value: $0) }
            )).tint(GameColor.effarig)
            Toggle("Level (Increased vs Exact)", isOn: Binding(
                get: { state.ignoreLevel },
                set: { engine.setGlyphPresetIgnore(field: "level", value: $0) }
            )).tint(GameColor.effarig)
        }
        .padding(12)
        .modifier(RoundedBorderModifier(color: GameColor.effarig.opacity(0.4), cornerRadius: 10, lineWidth: 1))
    }

    // MARK: - Slot card

    @ViewBuilder
    private func slotCard(_ slot: GlyphPresetSlot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Preset #\(slot.id + 1)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(GameColor.effarig.readableOnDark())
                TextField("Custom name", text: Binding(
                    get: { renameTargets[slot.id] ?? slot.name },
                    set: { renameTargets[slot.id] = String($0.prefix(20)) }
                ), onCommit: {
                    let new = renameTargets[slot.id] ?? ""
                    engine.renameGlyphPreset(slot: slot.id, name: new)
                })
                .font(.caption)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
            }

            // Glyph preview
            if slot.isEmpty {
                Text("Empty slot")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, minHeight: 40)
            } else {
                HStack(spacing: 8) {
                    ForEach(slot.glyphs) { g in
                        GlyphComponent(glyph: g.asGlyphInfo, size: 36, isCircular: true, showLevel: true)
                    }
                    Spacer()
                }
            }

            // Action row
            HStack(spacing: 8) {
                GameButton(theme: .effarig, isEnabled: state.hasEquipped && slot.isEmpty) {
                    engine.saveGlyphPreset(slot: slot.id)
                } label: {
                    Text("Save")
                        .font(.caption.weight(.semibold))
                        .frame(minWidth: 60)
                        .padding(.vertical, 6)
                }
                GameButton(theme: .effarig, isEnabled: !slot.isEmpty) {
                    engine.loadGlyphPreset(slot: slot.id)
                } label: {
                    Text("Load")
                        .font(.caption.weight(.semibold))
                        .frame(minWidth: 60)
                        .padding(.vertical, 6)
                }
                GameButton(theme: .effarig, isEnabled: !slot.isEmpty) {
                    pendingDelete = slot.id
                } label: {
                    Text("Delete")
                        .font(.caption.weight(.semibold))
                        .frame(minWidth: 60)
                        .padding(.vertical, 6)
                }
                Spacer()
            }
        }
        .padding(12)
        .modifier(RoundedBorderModifier(color: GameColor.effarig.opacity(0.3), cornerRadius: 10, lineWidth: 1))
    }
}
