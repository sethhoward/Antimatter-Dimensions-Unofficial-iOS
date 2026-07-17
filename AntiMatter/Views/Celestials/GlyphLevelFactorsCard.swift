//
//  GlyphLevelFactorsCard.swift
//  AntiMatter
//
//  Shared "Glyph Level Factors" expandable card. Used by:
//   • GlyphsTab left column (per-tick data from `pollGlyphs`)
//   • EffarigGlyphWeightsSheet (on-demand snapshot via `loadGlyphLevelFactors`)
//
//  Mirrors web's `GlyphLevelsAndWeights.vue` disclosure panel: a row per
//  contributing factor (EP / Replicanti / DT / Eternities / Perk Shop /
//  Instability) with formula + op + value, then a bold "Final Level" row.
//

import SwiftUI

struct GlyphLevelFactorsCard: View {
    let state: GlyphLevelFactorsState
    @Binding var isExpanded: Bool
    /// Optional trailing action shown next to the section title — e.g. the
    /// "Adjust Weights" button surfaced in the Glyphs tab once EffarigUnlock
    /// .adjuster is bought. Hidden when nil.
    var trailingAction: AnyView? = nil

    var body: some View {
        if !state.factors.isEmpty {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(state.factors) { factor in
                        HStack(spacing: 6) {
                            Text(factor.name)
                                .font(.caption.weight(.medium))
                                .frame(width: 70, alignment: .leading)
                            if !factor.formula.isEmpty {
                                Text(factor.formula)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            Spacer()
                            Text(factor.op)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(factor.value)
                                .font(.caption.monospacedDigit().weight(.medium))
                                .foregroundStyle(GameColor.reality)
                        }
                    }

                    Divider()

                    HStack {
                        Text("Final Level")
                            .font(.subheadline.weight(.bold))
                        Spacer()
                        Text(state.finalLevel)
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(GameColor.reality)
                    }

                    Text("All resources are log\u{2081}\u{2080} of their actual values.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                .padding(.top, 4)
            } label: {
                HStack(spacing: 8) {
                    Text("Glyph Level Factors")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let action = trailingAction {
                        action
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(white: 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
