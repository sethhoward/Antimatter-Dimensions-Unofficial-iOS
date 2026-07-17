//
//  EffarigGlyphFilterSheet.swift
//  AntiMatter
//
//  Sheet unlocked by EffarigUnlock.glyphFilter — configures the auto-sacrifice
//  filter. Matches the web `GlyphFilterPanel.vue` layout:
//   • "Current Filter Mode: <name>" header
//   • Row of mode icons (7 total, last two gated on Glyph Alchemy)
//   • Mode-specific body (description / stepper / per-type rarity / effect
//     toggles / effect scores)
//  The per-type modes (RARITY_THRESHOLD, SPECIFIED_EFFECT, EFFECT_SCORE) use
//  a horizontal Glyph Type picker with the selected type's symbol highlighted
//  in its own type-color (mirrors web `advancedTypeSelectStyle`).
//

import SwiftUI

// AUTO_GLYPH_SCORE (web constants.js:384)
private enum FilterMode: Int, CaseIterable {
    case lowestSacrifice = 0
    case effectCount = 1
    case rarityThreshold = 2
    case specifiedEffect = 3
    case effectScore = 4
    case lowestAlchemy = 5
    case alchemyValue = 6

    var name: String {
        switch self {
        case .lowestSacrifice: "Lowest Sacrifice Total"
        case .effectCount: "Effect Count"
        case .rarityThreshold: "Rarity Threshold"
        case .specifiedEffect: "Specified Effects"
        case .effectScore: "Effect Score"
        case .lowestAlchemy: "Lowest Alchemy Resource"
        case .alchemyValue: "Alchemy Value"
        }
    }

    /// SF Symbol that stands in for each web Font Awesome icon
    /// (modeIcon() in GlyphFilterPanel.vue lines 92-110).
    var icon: String {
        switch self {
        case .lowestSacrifice: "flame.fill"      // fa-burn
        case .effectCount: "list.bullet"          // fa-list-ul
        case .rarityThreshold: "diamond.fill"     // fa-gem
        case .specifiedEffect: "checklist"        // fa-tasks
        case .effectScore: "list.number"          // fa-list-ol
        case .lowestAlchemy: "atom"               // fa-atom
        case .alchemyValue: "testtube.2"          // fa-flask (closest SF)
        }
    }

    var requiresAlchemy: Bool { self == .lowestAlchemy || self == .alchemyValue }
}

struct EffarigGlyphFilterSheet: View {
    let engine: GameEngine
    @Environment(\.dismiss) private var dismiss

    /// Currently-selected glyph type for per-type modes (advancedType in web).
    /// Defaults to first type; re-synced whenever the filter state loads.
    @State private var selectedType: String = "power"
    @State private var showImportSheet = false

    private var state: GlyphFilterState { engine.effarigGlyphFilter ?? GlyphFilterState() }

    private var currentMode: FilterMode { FilterMode(rawValue: state.selectMode) ?? .lowestSacrifice }

    private var availableModes: [FilterMode] {
        FilterMode.allCases.filter { !$0.requiresAlchemy || state.alchemyUnlocked }
    }

    private var selectedTypeConfig: GlyphFilterTypeConfig? {
        state.types.first { $0.type == selectedType } ?? state.types.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    modeBody
                }
                .padding(16)
            }
            .adaptiveSheetTitle("Glyph Filter")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        Button {
                            engine.exportGlyphFilter()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .tint(GameColor.effarig)
                        .accessibilityLabel("Export filter settings")

                        Button {
                            showImportSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .tint(GameColor.effarig)
                        .accessibilityLabel("Import filter settings")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .tint(GameColor.effarig)
                }
            }
        }
        .presentationDetents([.large])
        .task {
            engine.loadGlyphFilter()
        }
        .sheet(isPresented: $showImportSheet) {
            GlyphFilterImportSheet(engine: engine)
        }
        .onChange(of: state.types.first?.type) { _, newFirst in
            // Sync the default selected type to the first available when the
            // filter state first loads (types is empty on first render).
            if !state.types.contains(where: { $0.type == selectedType }),
               let fallback = newFirst {
                selectedType = fallback
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 2) {
                    Text("Current Filter Mode:")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                    Text(currentMode.name)
                        .font(.headline)
                        .foregroundStyle(GameColor.effarig.readableOnDark())
                }
                .frame(maxWidth: .infinity)

                autoRealityButton
            }

            // Mode icons row — mirrors web .c-glyph-filter-mode-container
            HStack(spacing: 8) {
                ForEach(availableModes, id: \.rawValue) { mode in
                    modeButton(mode: mode, isSelected: mode == currentMode)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(GameColor.effarig, lineWidth: 2)
                )
        )
    }

    /// Recycle-style toggle that mirrors web `GlyphFilterPanel.vue:212-217`.
    /// When on, the Reality Autobuyer immediately Realitys if the best
    /// upcoming Glyph wouldn't pass the current filter. JS-side behaviour is
    /// implemented in `RealityAutobuyer.tick()` — iOS just exposes the
    /// toggle. The button is always visible (matching web's compact icon);
    /// the active state uses the same green/success styling as web's
    /// `o-quick-reality` class.
    private var autoRealityButton: some View {
        Button {
            engine.toggleGlyphFilterAutoReality()
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(state.autoRealityForFilter ? Color.black : GameColor.effarig)
                .frame(width: 36, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(state.autoRealityForFilter ? Color.green : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(state.autoRealityForFilter ? Color.green : GameColor.effarig, lineWidth: 1.5)
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Auto-Reality on filter fail"))
        .help("If on, ignore all other settings and immediately Reality if no upcoming Glyphs would be kept.")
    }

    @ViewBuilder
    private func modeButton(mode: FilterMode, isSelected: Bool) -> some View {
        Button {
            engine.setGlyphFilterMode(which: "select", value: mode.rawValue)
        } label: {
            Image(systemName: mode.icon)
                .font(.system(size: 22))
                .foregroundStyle(isSelected ? Color.black : GameColor.effarig)
                .frame(width: 48, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? GameColor.effarig : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(GameColor.effarig, lineWidth: 1.5)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mode-specific body

    @ViewBuilder
    private var modeBody: some View {
        switch currentMode {
        case .lowestSacrifice:
            infoCard(text: "Glyph score is assigned based on type. Priority is given to Glyphs belonging to the type of which you have the least total Glyph Sacrifice value.\n\nThis mode never keeps Glyphs, but will instead always sacrifice the Glyph it chooses.")

        case .effectCount:
            effectCountCard

        case .rarityThreshold:
            rarityThresholdList

        case .specifiedEffect:
            typePickerSection(mode: .specifiedEffect)

        case .effectScore:
            typePickerSection(mode: .effectScore)

        case .lowestAlchemy:
            infoCard(text: "Glyph score is assigned based on current Alchemy Resource totals. Priority is given to the Glyph type with the lowest associated alchemy resource total.\n\nThis mode never keeps Glyphs.")

        case .alchemyValue:
            infoCard(text: "Glyphs will be assigned values based on current refinement value, accounting for the type-specific resource caps. Priority is given to Glyphs which are worth the most alchemy resources; Glyphs which would cause you to hit a cap are effectively worth less.\n\nThis mode never keeps Glyphs.")
        }
    }

    private func infoCard(text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.85))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(GameColor.effarig.opacity(0.4), lineWidth: 1)
                    )
            )
    }

    // MARK: - Effect count mode

    private var effectCountCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Glyphs must have at least this many effects to be chosen. Rarer Glyphs are preferred in ties.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
            HStack {
                Text("Minimum effects")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                Spacer()
                integerInput(
                    value: state.simpleThreshold,
                    range: 0...8,
                    set: { engine.setGlyphFilterMode(which: "simple", value: $0) }
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(GameColor.effarig.opacity(0.4), lineWidth: 1)
                )
        )
    }

    // MARK: - Rarity threshold mode (per-type list)

    private var rarityThresholdList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Any Glyphs with rarity below these thresholds will be sacrificed.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
            ForEach(state.types) { type in
                rarityRow(type: type)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(GameColor.effarig.opacity(0.4), lineWidth: 1)
                )
        )
    }

    private func rarityRow(type: GlyphFilterTypeConfig) -> some View {
        let tColor = Color(cssColor: type.typeColor).readableOnDark()
        return HStack(spacing: 10) {
            Text(type.typeSymbol)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(tColor)
                .frame(width: 42)
            Text(type.typeDisplayName)
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(width: 88, alignment: .leading)
            Spacer()
            integerInput(
                value: type.rarity,
                range: 0...100,
                set: { engine.setGlyphFilterType(type: type.type, field: "rarity", value: $0) }
            )
            Text("%")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    // MARK: - Per-type mode section

    @ViewBuilder
    private func typePickerSection(mode: FilterMode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            typePicker
            if let cfg = selectedTypeConfig {
                switch mode {
                case .specifiedEffect: specifiedEffectBody(for: cfg)
                case .effectScore: effectScoreBody(for: cfg)
                default: EmptyView()
                }
            }
        }
    }

    private var typePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Glyph Type")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.75))
            HStack(spacing: 12) {
                ForEach(state.types) { type in
                    typeChoice(type)
                }
                Spacer()
            }
        }
    }

    private func typeChoice(_ type: GlyphFilterTypeConfig) -> some View {
        let isSelected = type.type == selectedType
        let tColor = Color(cssColor: type.typeColor).readableOnDark()
        return Button {
            selectedType = type.type
        } label: {
            Text(type.typeSymbol)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(isSelected ? tColor : Color.white.opacity(0.5))
                .shadow(color: isSelected ? tColor.opacity(0.8) : .clear, radius: 6)
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Specified effect body

    private func specifiedEffectBody(for type: GlyphFilterTypeConfig) -> some View {
        let tColor = Color(cssColor: type.typeColor).readableOnDark()
        return VStack(alignment: .leading, spacing: 10) {
            Text("Glyph score is rarity, minus 200 for every missing effect. Glyphs below the selected rarity are sacrificed. Additional effects beyond those specified do not increase score.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))

            HStack(spacing: 10) {
                Text(type.typeSymbol)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(tColor)
                    .frame(width: 42)
                Text("Rarity threshold")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                Spacer()
                integerInput(
                    value: type.rarity,
                    range: 0...100,
                    set: { engine.setGlyphFilterType(type: type.type, field: "rarity", value: $0) }
                )
                Text("%").font(.caption).foregroundStyle(.white.opacity(0.7))
            }

            HStack {
                Text("Selected Glyphs will have at least")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                integerInput(
                    value: type.effectCount,
                    range: 0...8,
                    set: { engine.setGlyphFilterType(type: type.type, field: "effectCount", value: $0) }
                )
                Text("of the following effects:")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }

            ForEach(Array(type.effectNames.enumerated()), id: \.offset) { idx, name in
                // `specifiedMask` uses the effect's ABSOLUTE bitmask index, not the
                // enumeration position — power/effarig/etc. effects start at bits
                // 16/20, so `1 << idx` would set the wrong bit and the JS-side score
                // (`specifiedMask & glyph.effects`) would count present effects as
                // missing (−200 each). See GitHub issue #67.
                let bitIndex = idx < type.effectBitmaskIndices.count ? type.effectBitmaskIndices[idx] : idx
                let bit = 1 << bitIndex
                let isOn = (type.specifiedMask & bit) != 0
                Button {
                    let newMask = isOn ? (type.specifiedMask & ~bit) : (type.specifiedMask | bit)
                    engine.setGlyphFilterType(type: type.type, field: "specifiedMask", value: newMask)
                } label: {
                    HStack {
                        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isOn ? tColor : Color.white.opacity(0.5))
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(isOn ? tColor : .white.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(tColor.opacity(isOn ? 1 : 0.35), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(tColor.opacity(0.4), lineWidth: 1)
                )
        )
    }

    // MARK: - Effect score body (EFFECT_SCORE mode)

    private func effectScoreBody(for type: GlyphFilterTypeConfig) -> some View {
        let tColor = Color(cssColor: type.typeColor).readableOnDark()
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Threshold score (rarity % + effect scores)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                integerInput(
                    value: type.score,
                    range: -999...999,
                    set: { engine.setGlyphFilterType(type: type.type, field: "score", value: $0) }
                )
            }
            ForEach(Array(type.effectNames.enumerated()), id: \.offset) { idx, name in
                let current = idx < type.effectScores.count ? type.effectScores[idx] : 0
                HStack {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(tColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    integerInput(
                        value: current,
                        range: -999...999,
                        set: { engine.setGlyphFilterEffectScore(type: type.type, idx: idx, value: $0) }
                    )
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(tColor.opacity(0.4), lineWidth: 1)
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(tColor.opacity(0.4), lineWidth: 1)
                )
        )
    }

    // MARK: - Shared numeric input (stepper + value)

    @ViewBuilder
    private func integerInput(value: Int, range: ClosedRange<Int>, set: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(GameColor.effarig)
                .frame(minWidth: 40, alignment: .trailing)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(GameColor.effarig.opacity(0.6), lineWidth: 1)
                )
            Stepper(
                "",
                value: Binding(get: { value }, set: set),
                in: range
            )
            .labelsHidden()
        }
    }
}
