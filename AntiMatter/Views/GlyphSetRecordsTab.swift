//
//  GlyphSetRecordsTab.swift
//  AntiMatter
//
//  Statistics > Glyph Set Records subtab. Mirrors `GlyphSetRecordsTab.vue`.
//  8 records (some gated on celestial unlocks): for each, the equipped
//  glyph set that achieved the record is rendered as a horizontal row of
//  `MiniPresetGlyph` tiles (the same compact preview used in the Glyph
//  Presets sheet).
//
//  Fetched on appear via `engine.loadGlyphSetRecords` — not per-tick polled.
//  Records only change after a Reality / celestial event. A `BIG_CRUNCH_AFTER`-
//  level refresh trigger is overkill; an `.onAppear` refetch on every nav
//  is sufficient because the user has to leave + re-enter the subtab to
//  notice a missed update.
//

import SwiftUI

struct GlyphSetRecordsTab: View {
    let engine: GameEngine
    @State private var state: GlyphSetRecordsState = .empty

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if state.records.isEmpty {
                    Text(verbatim: "No glyph set records yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 60)
                } else {
                    ForEach(state.records) { record in
                        GlyphSetRecordCard(record: record)
                    }
                }
                PhoneTabBarSpacer()
            }
            .padding()
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        engine.loadGlyphSetRecords { state in self.state = state }
    }
}

private struct GlyphSetRecordCard: View {
    let record: GlyphSetRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: record.label + ":")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            HStack(spacing: 6) {
                ForEach(record.glyphs) { g in
                    MiniPresetGlyph(glyph: g, size: 36)
                }
                Spacer(minLength: 8)
                Text(verbatim: record.value)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
