//
//  GlyphSelectionSheet.swift
//  AntiMatter
//
//  Glyph selection modal — matches web RealityModal.vue.
//  Title → gain summary → glyph row → level stats → buttons.
//

import SwiftUI

struct GlyphSelectionSheet: View {
    let choices: [GlyphInfo]
    let engine: GameEngine

    @State private var selectedIndex: Int? = nil

    // Sticky cache of the modal's reality strings. The IIFE that populates
    // `state.infinity.realityGainSummary` (and siblings) is throttled to every
    // 4th poll *and* sits inside a `canReality` gate that briefly drops the
    // values to "" between mod-4 ticks under certain conditions. Without this
    // cache the `if !isEmpty` guards on those Text views flip true→false→true
    // and the modal layout jumps. Pattern: take the latest non-empty value
    // every time state mutates, fall back to the last seen value otherwise.
    @State private var sticky = StickyFields()

    private var state: InfinityState { engine.gameState.infinity }

    private var displayedSummary: String { sticky.gainSummary.isEmpty ? state.realityGainSummary : sticky.gainSummary }
    private var displayedLevelStats: String { sticky.levelStats.isEmpty ? state.realityLevelStats : sticky.levelStats }
    private var displayedGlyphLevel: String { sticky.gainedGlyphLevel.isEmpty ? state.gainedGlyphLevel : sticky.gainedGlyphLevel }
    private var displayedMachineStats: String { sticky.machineStats.isEmpty ? state.machineStats : sticky.machineStats }
    private var displayedPPGained: String { sticky.ppGained.isEmpty ? state.realityPPGained : sticky.ppGained }
    private var displayedShardsInfo: String { sticky.shardsInfo.isEmpty ? state.realityShardsInfo : sticky.shardsInfo }
    private var displayedCelestialInfo: String { sticky.celestialInfo.isEmpty ? state.realityCelestialInfo : sticky.celestialInfo }

    private struct StickyFields {
        var gainSummary = ""
        var levelStats = ""
        var gainedGlyphLevel = ""
        var machineStats = ""
        var ppGained = ""
        var shardsInfo = ""
        var celestialInfo = ""
    }

    var body: some View {
        VStack(spacing: 0) {
            // Scrollable content — previous layout truncated multi-line text
            // (`realityLevelStats`, `realityGainSummary`) when the combined
            // height exceeded the sheet, especially with the glyph tooltip
            // expanded. ScrollView + fixedSize(vertical: true) on each Text
            // guarantees nothing clips, and the action buttons stay pinned
            // to the bottom outside the scrolling region.
            ScrollView {
                VStack(spacing: 16) {
                    // Title
                    Text("You are about to Reality")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.top, 20)

                    // Gain summary
                    if !displayedSummary.isEmpty {
                        Text(displayedSummary)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal)
                    }

                    // Glyph choices — LazyVGrid wraps into multiple rows when
                    // Ra's `extraGlyphChoicesAndRelicShardRarityAlwaysMax` unlock
                    // doubles choices (up to 10). Previously a single HStack
                    // overflowed off-screen on iPhone and dragged the whole
                    // sheet content wider than the parent, clipping the summary
                    // / level-stats text on both sides.
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 80), spacing: 12, alignment: .top)],
                        alignment: .center,
                        spacing: 12
                    ) {
                        ForEach(Array(choices.enumerated()), id: \.element.id) { index, glyph in
                            GlyphChoiceCell(
                                glyph: glyph,
                                isSelected: selectedIndex == index,
                                onTap: { selectedIndex = index }
                            )
                            .equatable()
                        }
                    }
                    .padding(.horizontal, 8)

                    // Selected glyph tooltip (tap = hover on web)
                    if let idx = selectedIndex, idx < choices.count {
                        GlyphSelectionTooltip(glyph: choices[idx])
                            .equatable()
                            .padding(.horizontal, 16)
                    }

                    // Level stats — full text, wraps as many lines as needed
                    if !displayedLevelStats.isEmpty {
                        Text(displayedLevelStats)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal)
                    }

                    // Detailed gains
                    realityDetails
                        .padding(.horizontal, 16)

                    // Warning when no glyph selected
                    if selectedIndex == nil {
                        Text("You must select a Glyph in order to continue.")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal)
                    }
                }
                // Force the VStack to the parent (sheet) width. Without this,
                // a too-wide child (the old glyph HStack pre-grid fix, or any
                // future wide content) lets the parent expand beyond the sheet
                // bounds and drags text rows / detail HStacks (label ↔ Spacer
                // ↔ value) off-screen equally on both sides.
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)
            }

            // Action buttons — mirrors web RealityModal.vue:
            //   Cancel | Sacrifice (when RealityUpgrade(19) is active) | Confirm
            HStack(spacing: 12) {
                Button("Cancel") {
                    engine.cancelGlyphSelection()
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(white: 0.15), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                )

                // Sacrifice — only visible once RealityUpgrade(19).isEffectActive.
                // Sacrifices the selected glyph instead of adding it to inventory.
                if engine.canSacrificeGlyphOnReality {
                    Button("Sacrifice") {
                        if let idx = selectedIndex {
                            engine.confirmRealityWithGlyph(idx, sacrifice: true)
                        }
                    }
                    .font(.headline.weight(.bold))
                    .foregroundStyle(selectedIndex != nil ? .white : .white.opacity(0.5))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(selectedIndex != nil ? Color.orange : Color(white: 0.2), in: RoundedRectangle(cornerRadius: 8))
                    .allowsHitTesting(selectedIndex != nil)
                }

                Button("Confirm") {
                    if let idx = selectedIndex {
                        engine.confirmRealityWithGlyph(idx, sacrifice: false)
                    }
                }
                .font(.headline.weight(.bold))
                .foregroundStyle(selectedIndex != nil ? .black : .gray)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(selectedIndex != nil ? GameColor.reality : Color(white: 0.2), in: RoundedRectangle(cornerRadius: 8))
                .allowsHitTesting(selectedIndex != nil)
            }
            .padding(.bottom, 24)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { refreshSticky() }
        .onChange(of: state.realityGainSummary) { _, _ in refreshSticky() }
        .onChange(of: state.realityLevelStats) { _, _ in refreshSticky() }
        .onChange(of: state.gainedGlyphLevel) { _, _ in refreshSticky() }
        .onChange(of: state.machineStats) { _, _ in refreshSticky() }
        .onChange(of: state.realityPPGained) { _, _ in refreshSticky() }
        .onChange(of: state.realityShardsInfo) { _, _ in refreshSticky() }
        .onChange(of: state.realityCelestialInfo) { _, _ in refreshSticky() }
    }

    private func refreshSticky() {
        if !state.realityGainSummary.isEmpty { sticky.gainSummary = state.realityGainSummary }
        if !state.realityLevelStats.isEmpty { sticky.levelStats = state.realityLevelStats }
        if !state.gainedGlyphLevel.isEmpty { sticky.gainedGlyphLevel = state.gainedGlyphLevel }
        if !state.machineStats.isEmpty { sticky.machineStats = state.machineStats }
        if !state.realityPPGained.isEmpty { sticky.ppGained = state.realityPPGained }
        if !state.realityShardsInfo.isEmpty { sticky.shardsInfo = state.realityShardsInfo }
        if !state.realityCelestialInfo.isEmpty { sticky.celestialInfo = state.realityCelestialInfo }
    }

    // MARK: - Reality detail rows

    @ViewBuilder
    private var realityDetails: some View {
        let hasRate = !displayedMachineStats.isEmpty
        let hasShards = !displayedShardsInfo.isEmpty
        let hasCelestial = !displayedCelestialInfo.isEmpty

        VStack(spacing: 6) {
            if !displayedGlyphLevel.isEmpty {
                detailRow("Glyph Level", displayedGlyphLevel.replacingOccurrences(of: "Glyph lvl: ", with: ""))
            }
            if hasRate {
                detailRow("RM Rate", displayedMachineStats)
            }
            if !displayedPPGained.isEmpty {
                detailRow("Perk Points", displayedPPGained)
            }
                if hasShards {
                    let lines = displayedShardsInfo.components(separatedBy: "\n")
                    detailRow("Relic Shards", lines[0])
                    if lines.count > 1 {
                        detailRow("Shard Peak", lines[1].replacingOccurrences(of: "Peak: ", with: ""))
                    }
                }
                if hasCelestial {
                    ForEach(displayedCelestialInfo.components(separatedBy: "\n").filter { !$0.isEmpty }, id: \.self) { line in
                        detailRow("Celestial", line)
                    }
                }
            }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }

}

// MARK: - Glyph choice cell (Equatable)

/// Equatable on `(glyph, isSelected)` — both transition-only while the
/// modal is open. The 5–10 cells skip body unless selection or glyph data
/// changes. Closure excluded (closes over a stable `@State` binding).
private struct GlyphChoiceCell: View, Equatable {
    let glyph: GlyphInfo
    let isSelected: Bool
    let onTap: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.glyph == rhs.glyph && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        VStack(spacing: 4) {
            GlyphComponent(glyph: glyph, size: 65, isCircular: true)
                .equatable()
                .overlay {
                    if isSelected {
                        Circle()
                            .strokeBorder(Color.white, lineWidth: 3)
                            .frame(width: 69, height: 69)
                    }
                }

            Text("Lv. \(glyph.level)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)

            Text(glyph.rarityName)
                .font(.caption2)
                .foregroundStyle(Color(hex: glyph.rarityColor))
        }
        .padding(6)
        .background(isSelected ? Color.white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Glyph tooltip (Equatable)

/// Equatable on `glyph` only. Tooltip body skips every tick while the same
/// glyph stays selected; rebuilds once on selection change.
private struct GlyphSelectionTooltip: View, Equatable {
    let glyph: GlyphInfo

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.glyph == rhs.glyph
    }

    var body: some View {
        let rarityColor = Color(hex: glyph.rarityColor)
        let typeColor = Color(hex: glyph.typeColor)

        return VStack(spacing: 0) {
            // Header: rarity + type name, level, rarity %
            VStack(spacing: 4) {
                Text("\(glyph.rarityName) Glyph of \(glyph.type.capitalized)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)

                HStack(spacing: 4) {
                    Text("Level: \(glyph.level)")
                        .foregroundStyle(.white)
                    Text("|")
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Rarity:")
                        .foregroundStyle(.white)
                    Text("\(String(format: "%.1f%%", glyph.rarityPercent))")
                        .foregroundStyle(rarityColor)
                }
                .font(.caption.monospacedDigit())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color(white: 0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(rarityColor, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Effects — match the equipped-glyph tooltip (`GlyphRichCard.effectsList`):
            // white base text, values in green (or per-effect EMPOWER/BOOST
            // color when active), `[…]` bracket runs bold (and ADDITION-colored
            // when active). The JS helper `_formatGlyphEffectBlock` emits the
            // `§…§` value markers and `[…]` bracket markers; `glyphEffectStyledText`
            // parses them into the three styled runs.
            VStack(spacing: 8) {
                let descs = glyph.effects.isEmpty ? glyph.shortEffects : glyph.effects
                let boostColors = glyph.effectBoostColors
                let additionColors = glyph.effectAdditionColors
                ForEach(Array(descs.enumerated()), id: \.offset) { i, effect in
                    let boost = i < boostColors.count ? boostColors[i] : ""
                    let addition = i < additionColors.count ? additionColors[i] : ""
                    let valueColor: Color = boost.isEmpty ? .green : Color(hex: boost).readableOnDark()
                    let addColor: Color = addition.isEmpty
                        ? .white
                        : Color(hex: addition).readableOnDark()
                    glyphEffectStyledText(
                        effect,
                        baseColor: .white,
                        valueColor: valueColor,
                        additionColor: addColor
                    )
                    .font(.caption.monospacedDigit())
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color(white: 0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(typeColor.opacity(0.5), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.top, 4)
        }
    }
}
