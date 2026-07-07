//
//  GlyphRichCard.swift
//  AntiMatter
//
//  Shared rich-card layout for glyph inspection. Mirrors web `GlyphTooltip.vue`
//  and replaces the previous `peekGlyphCard` / `equippedGlyphCard` divergence.
//
//  Used by:
//    - EquippedGlyphsSheet (multiple cards stacked, web parity with tap-equipped → all-equipped summary)
//    - PeekGlyphsSheet (multiple cards stacked, upcoming reality preview)
//    - GlyphTooltipSheet (single card + action buttons; inventory taps only)
//
//  Visual: `baseColor` body + type-colored border + type-colored outside glow,
//  rarity-colored inner header band with its own border + glow. Reality glyphs
//  hue-cycle the description text + outer glow (scene-phase gated). Cursed
//  glyphs invert contrast (white body / black text).
//

import SwiftUI

struct GlyphRichCard: View, Equatable {
    let glyph: GlyphInfo

    @Environment(\.scenePhase) private var scenePhase
    @State private var realityHuePhase: Double = 0

    /// Equatable on `glyph` only. `glyph` is the only stored let; the
    /// `@State realityHuePhase` and `@Environment scenePhase` aren't part
    /// of `==` (Equatable only sees stored let properties of value type
    /// fields). The hue-cycle animation is driven by Core Animation on
    /// the render server — once `withAnimation { realityHuePhase = 360 }`
    /// fires in `onAppear`, the rotation continues independently of body
    /// re-evaluations. Body skipping just preserves the view identity,
    /// which is what we want.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.glyph == rhs.glyph
    }

    // MARK: - Type gates

    private var isReality: Bool { glyph.type == "reality" }
    private var isCursed: Bool { glyph.type == "cursed" }
    private var isCompanion: Bool { glyph.type == "companion" }

    // MARK: - Colors

    /// Mirrors web `baseColor` / `textColor`. Cursed glyphs invert contrast.
    private var baseColor: Color { isCursed ? .white : Color(white: 0.05) }
    private var textColor: Color { isCursed ? .black : .white }
    /// Border + outer glow color. Cursed uses textColor to stay readable;
    /// Reality cycles via the hue rotation modifier on the wrapper.
    private var borderColor: Color { isCursed ? textColor : Color(hex: glyph.typeColor) }
    /// Header band + description text color. Cursed → textColor, companion → border, else rarity.
    private var headerAccent: Color {
        if isCursed { return textColor }
        if isCompanion { return Color(hex: glyph.typeColor) }
        return Color(hex: glyph.rarityColor)
    }

    private var animationsActive: Bool { scenePhase == .active }

    // MARK: - Description (web `GlyphTooltip.vue.description`)

    private var description: String {
        switch glyph.type {
        case "companion": return "Companion Glyph"
        case "cursed": return "Cursed Glyph"
        case "reality": return "Pure Glyph of Reality"
        default: return "\(glyph.rarityName) Glyph of \(glyph.type.capitalized)"
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 8) {
            headerCard
            effectsList
        }
        .padding(10)
        .background(baseColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(borderColor, lineWidth: 2)
        )
        .shadow(color: borderColor.opacity(0.6), radius: 6)
        .shadow(color: borderColor.opacity(0.4), radius: 2)
        .hueRotation(.degrees(isReality ? realityHuePhase : 0))
        .onAppear { startRealityCycleIfNeeded() }
        .onChange(of: scenePhase) { _, _ in startRealityCycleIfNeeded() }
    }

    // MARK: - Header card

    private var headerCard: some View {
        VStack(spacing: 6) {
            Text(description)
                .font(.headline.weight(.bold))
                .foregroundStyle(headerAccent)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if !isCompanion {
                levelAndRarityLine
            }

            if !subheaderParts.isEmpty {
                subheaderLine
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(baseColor)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(headerAccent, lineWidth: 1.5)
        )
        .shadow(color: headerAccent.opacity(0.5), radius: 4)
    }

    /// "Level: ▲ 9000 ▲ | Rarity: 73.2%". Companion has no level/rarity (skipped above).
    /// Reality has level but no rarity. Cursed has level but no rarity (`hasRarity` false).
    private var levelAndRarityLine: some View {
        let levelStyle = GlyphLevelStyle(level: glyph.level, displayLevel: glyph.displayLevel)
        return HStack(spacing: 6) {
            Text("Level:")
                .foregroundStyle(textColor)
            Text(levelStyle.paddedLabel)
                .foregroundStyle(levelStyle.color)
            if hasRarityLine {
                Text("|")
                    .foregroundStyle(textColor.opacity(0.4))
                Text("Rarity:")
                    .foregroundStyle(textColor)
                Text(String(format: "%.1f%%", glyph.rarityPercent))
                    .foregroundStyle(Color(hex: glyph.rarityColor).readableOnDark())
            }
        }
        .font(.subheadline.monospacedDigit())
    }

    /// Web `GlyphTypes[type].hasRarity` — false for companion, cursed, reality.
    private var hasRarityLine: Bool {
        !isCompanion && !isCursed && !isReality
    }

    // MARK: - Subheader (Sacrifice / Refine / Score)

    /// Each entry: pre-rendered Text with proper styling. Joined by " | " separators.
    private var subheaderParts: [(label: String, value: Text)] {
        var out: [(String, Text)] = []
        if !glyph.sacrificeGain.isEmpty {
            out.append((
                "Sacrifice",
                Text("\(Text("Sacrifice: ").foregroundStyle(textColor))\(Text(glyph.sacrificeGain).foregroundStyle(textColor).fontWeight(.medium))")
            ))
        }
        if !glyph.refineReward.isEmpty {
            // Web shows "Refine: X ⚡" or "Refine: X ⚡ (Actual value due to cap: Y ⚡)"
            // when uncapped != capped.
            let uncapped = glyph.uncappedRefineReward.isEmpty ? glyph.refineReward : glyph.uncappedRefineReward
            var refineText = Text("\(Text("Refine: ").foregroundStyle(textColor))\(Text("\(uncapped) \(glyph.symbol)").foregroundStyle(textColor).fontWeight(.medium))")
            if uncapped != glyph.refineReward {
                refineText = Text("\(refineText)\(Text(" (cap: \(glyph.refineReward) \(glyph.symbol))").foregroundStyle(textColor.opacity(0.7)))")
            }
            out.append(("Refine", refineText))
        }
        if !glyph.filterScore.isEmpty {
            out.append((
                "Score",
                Text("\(Text("Score: ").foregroundStyle(textColor))\(Text(glyph.filterScore).foregroundStyle(textColor).fontWeight(.medium))")
            ))
        }
        return out
    }

    @ViewBuilder
    private var subheaderLine: some View {
        let parts = subheaderParts
        let joined = parts.enumerated().reduce(Text("")) { acc, pair in
            let (i, part) = pair
            if i == 0 { return Text("\(acc)\(part.value)") }
            return Text("\(acc)\(Text(" | ").foregroundStyle(textColor.opacity(0.4)))\(part.value)")
        }
        joined
            .font(.caption)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Effects body

    private var effectsList: some View {
        let descs = glyph.effects.isEmpty ? glyph.shortEffects : glyph.effects
        let boostColors = glyph.effectBoostColors
        let additionColors = glyph.effectAdditionColors
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(descs.enumerated()), id: \.offset) { i, effect in
                // Per-effect alteration colors:
                //   boost (EMPOWER/BOOST) → overrides green value run; ▲ already baked in
                //   addition (ADDITION)   → applied to bracketed `[...]` text run, bold
                let boost = i < boostColors.count ? boostColors[i] : ""
                let addition = i < additionColors.count ? additionColors[i] : ""
                let valueColor: Color = boost.isEmpty ? .green : Color(hex: boost).readableOnDark()
                let addColor: Color = addition.isEmpty
                    ? textColor                                            // bracket text but no active addition → just bold
                    : Color(hex: addition).readableOnDark()
                glyphEffectStyledText(
                    effect,
                    baseColor: textColor,
                    valueColor: valueColor,
                    additionColor: addColor
                )
                .font(.subheadline)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Pelle chaos description — web `GlyphTooltip.vue` renders it as the
            // last entry in the effects list with a `pelle-current-glyph-effects`
            // accent class. iOS uses `GameColor.pelle` for the same callout.
            if !glyph.chaosDescription.isEmpty {
                Text(glyph.chaosDescription)
                    .font(.subheadline.italic())
                    .foregroundStyle(GameColor.pelle)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .padding(.top, 2)
    }

    // MARK: - Reality glyph hue cycle

    /// Mirrors web's `a-reality-glyph-tooltip-cycle 10s infinite` — full hue
    /// rotation over 10 seconds. Pauses on background per the the design notes
    /// repeating-animation rule. One-shot snap to 0° when leaving .active.
    private func startRealityCycleIfNeeded() {
        guard isReality else { return }
        if animationsActive {
            // Reset and animate forever.
            realityHuePhase = 0
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
                realityHuePhase = 360
            }
        } else {
            // Snap to a stable resting position; tear down the implicit animation.
            withAnimation(.linear(duration: 0)) {
                realityHuePhase = 0
            }
        }
    }
}
