//
//  GlyphComponent.swift
//  AntiMatter
//
//  Reusable glyph tile — matches web GlyphComponent.vue dark theme:
//  Dark background, type-colored border (with glow), rarity-colored symbol.
//  Level in top-right, effect dots along bottom.
//

import SwiftUI

struct GlyphComponent: View, Equatable {
    let glyph: GlyphInfo
    var size: CGFloat = 50
    var isCircular: Bool = false
    var showLevel: Bool = true

    /// `GlyphInfo` is `Equatable` (synthesized). All four stored fields are
    /// transition-only — `glyph` only changes on equip/unequip/sacrifice/
    /// rarity-reroll, the visual params (`size`, `isCircular`, `showLevel`)
    /// never change tick-to-tick. Massive impact: 120-cell inventory grid
    /// + equipped slots + peek glyphs all skip body when the parent runs.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.glyph == rhs.glyph
            && lhs.size == rhs.size
            && lhs.isCircular == rhs.isCircular
            && lhs.showLevel == rhs.showLevel
    }

    private var typeColor: Color { Color(hex: glyph.typeColor) }
    private var rarityColor: Color { Color(hex: glyph.rarityColor) }
    private var isCompanion: Bool { glyph.type == "companion" }

    /// iOS fallback for glyph symbols that aren't in system fonts.
    /// Web uses `⸸` (U+2E38) for cursed glyphs — renders as tofu on
    /// iOS. Dagger `†` (U+2020) is widely supported and visually
    /// matches the single-vertical-stroke silhouette.
    ///
    /// Companion always renders as a heart (`♥` + VS15 to force text
    /// presentation, otherwise iOS picks the color-emoji variant).
    /// We ignore whatever `glyph.symbol` carries because web themes /
    /// cosmetic symbolMaps can stuff private-use codepoints into it
    /// (e.g. S11 blobheart ``), and on iOS those PUA codes hit
    /// arbitrary glyphs in the Apple font cascade — recently observed
    /// rendering as the raised-fist emoji.
    private var displaySymbol: String {
        if isCompanion { return "♥\u{FE0E}" }
        if glyph.symbol == "⸸" { return "†" }
        return glyph.symbol
    }

    private var borderWidth: CGFloat {
        // Thick border so type color is prominent (matches web)
        return max(size * 0.06, 3)
    }

    private var dotSize: CGFloat { max(size * 0.07, 3) }

    /// Effect dots are tinted the glyph's rarity color (the same color as the
    /// symbol), matching web `GlyphComponent.vue` — its dots use `symbolColor`
    /// at 0.8 opacity. (iOS renders the symbol with `rarityColor`; we don't
    /// port `swapGlyphColors`, so rarity color is always the symbol color.)
    private var dotColor: Color { rarityColor.opacity(0.8) }

    /// Bitmask-index offset per glyph type — mirrors web `GlyphComponent.vue`
    /// `glyphEffects()`. Each type's effects occupy a contiguous slot in the
    /// bitmask (4 bits, or 7 for effarig); shifting down by this offset yields
    /// the per-type relative effect IDs (0…3, or 0…6 for effarig).
    private static func minEffectID(for type: String) -> Int {
        switch type {
        case "dilation", "reality": return 4
        case "replication": return 8
        case "infinity": return 12
        case "power": return 16
        case "effarig": return 20
        default: return 0   // time, cursed, companion
        }
    }

    /// Relative effect IDs set in the bitmask, mirroring web's `glyphEffects`.
    private var effectDotIDs: [Int] {
        var remaining = glyph.effectBitmask >> Self.minEffectID(for: glyph.type)
        guard remaining > 0 else { return [] }
        var ids: [Int] = []
        var id = 0
        while remaining > 0 {
            if remaining & 1 == 1 { ids.append(id) }
            remaining >>= 1
            id += 1
        }
        return ids
    }

    /// Dot placement around the glyph center — port of web `effectIconPos`.
    /// Clockwise from bottom-left; 90° spacing (basic) or 45° (effarig).
    /// SwiftUI's +y axis points down, matching web's CSS `translate`.
    private func effectDotOffset(id: Int) -> (dx: CGFloat, dy: CGFloat) {
        let angle: CGFloat = glyph.type == "effarig"
            ? (.pi / 4) * CGFloat(id + 1)
            : (.pi / 2) * (CGFloat(id) + 0.5)
        let scale = 0.28 * size
        return (dx: -scale * sin(angle), dy: scale * (cos(angle) + 0.15))
    }

    var body: some View {
        ZStack {
            // Dark background — circle or rounded rect to match the rest of
            // the inventory grid. Companion uses the same rounded-rect tile
            // as every other glyph; the heart is drawn inside instead of
            // reshaping the container.
            backgroundShape

            if isCompanion {
                // Filled heart silhouette as the symbol. Inset so it sits
                // comfortably inside the rounded-rect tile. Type color +
                // glow matches the symbol/border styling used elsewhere.
                HeartShape()
                    .fill(typeColor)
                    .shadow(color: typeColor.opacity(0.5), radius: size * 0.04)
                    .frame(width: size * 0.55, height: size * 0.55)
            } else {
                // Symbol — colored by rarity. Cursed glyphs use the Unicode
                // double cross `⸸` (U+2E38) on web, which iOS system fonts
                // don't include — it renders as tofu. Substitute a dagger
                // `†` which is widely supported and visually matches the
                // single-bar silhouette.
                Text(displaySymbol)
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(rarityColor)
                    .shadow(color: rarityColor.opacity(0.5), radius: size * 0.04)
            }

            // Effect dots — positioned around the glyph perimeter (web
            // `GlyphComponent.vue` `effectIconPos`): each effect occupies a
            // fixed angular slot, so the dots convey WHICH effects a glyph has,
            // not merely how many. Companion/cursed render no dots (web
            // `glyphEffectDots` returns {} for them). Sources that don't carry
            // the raw bitmask (e.g. celestial run-record previews) fall back to
            // the legacy centered row.
            if size >= 36 && glyph.type != "companion" && glyph.type != "cursed" {
                if glyph.effectBitmask != 0 {
                    ForEach(effectDotIDs, id: \.self) { dotID in
                        let off = effectDotOffset(id: dotID)
                        Circle()
                            .fill(dotColor)
                            .frame(width: dotSize, height: dotSize)
                            .offset(x: off.dx, y: off.dy)
                    }
                } else if glyph.effectCount > 0 {
                    HStack(spacing: 2) {
                        ForEach(0..<glyph.effectCount, id: \.self) { _ in
                            Circle()
                                .fill(dotColor)
                                .frame(width: max(size * 0.06, 3), height: max(size * 0.06, 3))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, size * 0.08)
                }
            }

        }
        .frame(width: size, height: size)
        // Type-colored border with subtle glow
        .overlay { borderShape }
        // Level number — on top of border. Uses the celestial-adjusted
        // `displayLevel` (web `GlyphTooltip.vue.effectiveLevel`) so a doomed
        // run shows the capped level instead of the raw one. Coloring + arrow
        // markers signal whether the cap kicked in.
        .overlay(alignment: .topTrailing) {
            if showLevel {
                let style = GlyphLevelStyle(level: glyph.level, displayLevel: glyph.displayLevel)
                Text(style.compactLabel)
                    .font(.system(size: max(size * 0.18, 8), weight: .bold, design: .monospaced))
                    .foregroundStyle(style.color)
                    .shadow(color: .black, radius: 2)
                    .padding(size * 0.06)
            }
        }
    }

    @ViewBuilder
    private var backgroundShape: some View {
        if isCircular {
            Circle().fill(Color(white: 0.06))
        } else {
            RoundedRectangle(cornerRadius: size * 0.12)
                .fill(Color(white: 0.06))
        }
    }

    @ViewBuilder
    private var borderShape: some View {
        if isCircular {
            Circle()
                .strokeBorder(typeColor, lineWidth: borderWidth)
                .shadow(color: typeColor.opacity(0.7), radius: size * 0.08)
        } else {
            RoundedRectangle(cornerRadius: size * 0.12)
                .strokeBorder(typeColor, lineWidth: borderWidth)
                .shadow(color: typeColor.opacity(0.7), radius: size * 0.08)
        }
    }
}

// MARK: - Heart silhouette

/// Classic two-lobe heart fitted to the proposed rect. Used for companion
/// glyph tiles to mirror web `GlyphComponent.vue`'s "companion" gradient
/// branch (`generateGradient` line 149 — "Special case to make the companion
/// border look like a heart").
struct HeartShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let cx = rect.midX
        // Start at the top center dip between the two lobes.
        let topDip = CGPoint(x: cx, y: rect.minY + h * 0.22)
        // Left side: dip → up-and-over the left lobe → down the left flank → bottom point.
        p.move(to: topDip)
        p.addCurve(
            to: CGPoint(x: rect.minX + w * 0.02, y: rect.minY + h * 0.32),
            control1: CGPoint(x: cx - w * 0.12, y: rect.minY - h * 0.02),
            control2: CGPoint(x: rect.minX + w * 0.02, y: rect.minY - h * 0.02)
        )
        p.addCurve(
            to: CGPoint(x: cx, y: rect.maxY - h * 0.02),
            control1: CGPoint(x: rect.minX + w * 0.02, y: rect.minY + h * 0.62),
            control2: CGPoint(x: cx - w * 0.25, y: rect.minY + h * 0.82)
        )
        // Right side: bottom point → up the right flank → over the right lobe → dip.
        p.addCurve(
            to: CGPoint(x: rect.maxX - w * 0.02, y: rect.minY + h * 0.32),
            control1: CGPoint(x: cx + w * 0.25, y: rect.minY + h * 0.82),
            control2: CGPoint(x: rect.maxX - w * 0.02, y: rect.minY + h * 0.62)
        )
        p.addCurve(
            to: topDip,
            control1: CGPoint(x: rect.maxX - w * 0.02, y: rect.minY - h * 0.02),
            control2: CGPoint(x: cx + w * 0.12, y: rect.minY - h * 0.02)
        )
        p.closeSubpath()
        return p
    }
}

// MARK: - Glyph text halo

extension View {
    /// Web's `text-shadow` halo on glyph-effect / sacrifice / set-name text —
    /// 4-direction 1px dark outline + 3px colored glow in the type color.
    /// We collapse the 4-shadow outline into a single broad dark shadow for
    /// cheap composition; visually nearly identical at the sizes we render.
    /// Pass `enabled: false` to drop the treatment when the player has the
    /// `glyphTextColors` option off (web `CurrentGlyphEffect.vue:31`).
    func glyphTextHalo(color: Color, enabled: Bool = true) -> some View {
        modifier(GlyphTextHaloModifier(color: color, enabled: enabled))
    }
}

private struct GlyphTextHaloModifier: ViewModifier {
    let color: Color
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content
                .shadow(color: .black.opacity(0.95), radius: 1)
                .shadow(color: color.opacity(0.6), radius: 3)
        } else {
            content
        }
    }
}

// MARK: - Glyph level styling helper

/// Resolves the level number + arrow + color treatment used everywhere a glyph
/// level is rendered. Mirrors web `GlyphTooltip.vue.levelText`:
///   level capped (doomed / Effarig run) → red text + ▼
///   level boosted (Enslaved run)        → green text + ▲
///   default                              → white text, no arrows
struct GlyphLevelStyle {
    let level: Int
    let displayLevel: Int
    var isCapped: Bool { displayLevel != 0 && displayLevel < level }
    var isBoosted: Bool { displayLevel != 0 && displayLevel > level }
    var effectiveLevel: Int { displayLevel == 0 ? level : displayLevel }
    /// "▼ 608 ▼" / "▲ 8,000 ▲" / "50,000". Web `formatInt` uses thousands
    /// separators; iOS matches via `NumberFormatter` so card text stays
    /// readable for high-level glyphs.
    var paddedLabel: String {
        let s = Self.formatter.string(from: NSNumber(value: effectiveLevel)) ?? String(effectiveLevel)
        if isCapped { return "▼ \(s) ▼" }
        if isBoosted { return "▲ \(s) ▲" }
        return s
    }
    /// Compact form for the corner-of-tile badge — single arrow on each side
    /// hugging the number, no thousands separator (tile is too narrow).
    var compactLabel: String {
        let n = effectiveLevel
        if isCapped { return "▼\(n)▼" }
        if isBoosted { return "▲\(n)▲" }
        return "\(n)"
    }
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()
    /// Web colors `#ff4444` (red) / `#44FF44` (green) / inherited.
    var color: Color {
        if isCapped { return Color(red: 1.0, green: 0.27, blue: 0.27) }
        if isBoosted { return Color(red: 0.27, green: 1.0, blue: 0.27) }
        return .white
    }
}

/// Glyph-effect renderer with three styled runs: base text, `§...§` value runs,
/// and `[...]` addition-altered runs. Mirrors web's `GlyphTooltipEffect.convertToHTML`
/// behaviour: bracket markers wrap an alteration-added text section that web
/// renders bold + glowing in the addition color. iOS strips the brackets and
/// renders that section bold in `additionColor`. § markers wrap the formatted
/// value(s) and render in `valueColor` (default green; replaced with the
/// per-effect EMPOWER/BOOST color when active).
func glyphEffectStyledText(
    _ text: String,
    baseColor: Color,
    valueColor: Color,
    additionColor: Color
) -> Text {
    var result = Text("")
    var current = ""
    var inAddition = false
    var inValue = false

    func flush() {
        guard !current.isEmpty else { return }
        let color: Color = inValue ? valueColor : (inAddition ? additionColor : baseColor)
        var run = Text(current).foregroundStyle(color)
        if inAddition { run = run.bold() }
        result = Text("\(result)\(run)")
        current = ""
    }

    for ch in text {
        switch ch {
        case "[":
            flush()
            inAddition = true
        case "]":
            flush()
            inAddition = false
        case "§":
            flush()
            inValue.toggle()
        default:
            current.append(ch)
        }
    }
    flush()
    return result
}
