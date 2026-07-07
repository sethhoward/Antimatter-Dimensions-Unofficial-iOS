//
//  TeresaTab.swift
//  AntiMatter
//
//  Teresa's Reality — pour RM, run, and Perk Shop.
//  Mirrors src/components/tabs/celestial-teresa/TeresaTab.vue.
//

import SwiftUI

struct TeresaTab: View {
    let engine: GameEngine

    var body: some View {
        TeresaTabContent(engine: engine)
    }
}

private struct TeresaTabContent: View {
    let engine: GameEngine
    @Environment(\.sidebarState) private var sidebarState
    @Environment(\.scenePhase) private var scenePhase

    @State private var showHistory = false
    @State private var selectedUnlock: TeresaUnlockInfo?
    @State private var showGlyphSet = false

    private var t: TeresaState { engine.gameState.celestials.teresa }

    /// True only when Teresa is the visible subtab AND the scene is active.
    /// See `BlackHoleTab.isVisible` for the rationale.
    private var isVisible: Bool {
        sidebarState?.activeSubtab == .teresa && scenePhase == .active
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if t.hasRun {
                    TeresaRunSection(
                        engine: engine,
                        isRunning: t.isRunning,
                        runDescription: t.runDescription,
                        runCompleted: t.runCompleted,
                        bestRunAM: t.bestRunAM,
                        lastRepeatedMachinesLabel: t.lastRepeatedMachinesLabel,
                        bestAMSet: t.bestAMSet,
                        runReward: t.runReward,
                        hasEPGen: t.hasEPGen,
                        isActive: isVisible,
                        isPelleDoomed: engine.pelleDoomed,
                        onShowGlyphSet: { showGlyphSet = true }
                    )
                    .equatable()
                }
                pourSection
                if t.hasShop { perkShopSection }
                PhoneTabBarSpacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .sheet(isPresented: $showHistory) {
            CelestialQuoteHistoryView(celestialKey: "teresa", engine: engine)
        }
        .sheet(item: $selectedUnlock) { unlock in
            UnlockDetailSheet(unlock: unlock)
        }
        .sheet(isPresented: $showGlyphSet) {
            TeresaGlyphSetSheet(glyphs: t.bestAMSet)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("You have \(t.realityMachines) Reality Machines.")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    engine.loadQuoteHistory(for: "teresa")
                    showHistory = true
                } label: {
                    Label("Quote History", systemImage: "quote.bubble")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(GameColor.teresa)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(GameColor.teresa.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Pour section

    private var pourSection: some View {
        VStack(spacing: 12) {
            let isCapped = t.pouredAmountRaw >= t.pouredAmountCapRaw

            TeresaPourButton(
                isCapped: isCapped,
                onTick: { diffSec in engine.pourRM(diffSec: diffSec) },
                onRelease: { engine.stopPourRM() }
            )
            .frame(height: 56)

            TeresaFillBar(
                fill: t.fillFraction,
                possibleFill: t.possibleFillFraction,
                unlocks: t.unlocks,
                multiplierText: t.rmMultiplier,
                pouredAmount: t.pouredAmount,
                pouredCap: t.pouredAmountCap,
                onTapMilestone: { unlock in selectedUnlock = unlock }
            )
            .frame(height: 360)
        }
    }

    // MARK: - Perk Shop

    private var perkShopSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("You have \(t.perkPoints) Perk \(t.perkPoints == 1 ? "Point" : "Points").")
                .font(.subheadline)
                .foregroundStyle(.white)

            ForEach(t.perkShop) { up in
                PerkShopUpgradeRow(upgrade: up, isPelleDoomed: engine.pelleDoomed, engine: engine)
                    .equatable()
            }

            // Matches TeresaTab.vue:265 — static help line under the shop grid.
            Text("You can now modify the appearance of your Glyphs to look like Music Glyphs.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .modifier(RoundedBorderModifier(color: GameColor.teresa.opacity(0.4), cornerRadius: 12, lineWidth: 1))
    }
}

// MARK: - Run Section (Equatable)
//
// Extracted from `TeresaTabContent` so the per-tick parent body re-eval
// doesn't rebuild the run section's modifier chain. Inputs are stable
// post-completion: bestRunAM/lastRepeatedMachinesLabel/bestAMSet/runReward
// only change when a new record is set; runDescription/hasEPGen/hasRun are
// transition-only.

private struct TeresaRunSection: View, Equatable {
    let engine: GameEngine
    let isRunning: Bool
    let runDescription: String
    let runCompleted: Bool
    let bestRunAM: String
    let lastRepeatedMachinesLabel: String
    let bestAMSet: [TeresaGlyphRecord]
    let runReward: String
    let hasEPGen: Bool
    let isActive: Bool
    let isPelleDoomed: Bool
    let onShowGlyphSet: () -> Void

    static func == (lhs: TeresaRunSection, rhs: TeresaRunSection) -> Bool {
        lhs.isRunning == rhs.isRunning
            && lhs.runDescription == rhs.runDescription
            && lhs.runCompleted == rhs.runCompleted
            && lhs.bestRunAM == rhs.bestRunAM
            && lhs.lastRepeatedMachinesLabel == rhs.lastRepeatedMachinesLabel
            && lhs.bestAMSet == rhs.bestAMSet
            && lhs.runReward == rhs.runReward
            && lhs.hasEPGen == rhs.hasEPGen
            && lhs.isActive == rhs.isActive
            && lhs.isPelleDoomed == rhs.isPelleDoomed
        // engine + onShowGlyphSet excluded (identity-stable / not Equatable).
    }

    var body: some View {
        VStack(alignment: .center, spacing: 14) {
            Text("Start Teresa's Reality")
                .font(.headline)
                .foregroundStyle(GameColor.teresa.readableOnDark())
                .strikethrough(isPelleDoomed)

            TeresaRunButton(isRunning: isRunning, isActive: isActive) {
                guard !isPelleDoomed else { return }
                engine.requestTeresaRun()
            }
            .opacity(isPelleDoomed ? 0.4 : 1)
            .allowsHitTesting(!isPelleDoomed)
            if isPelleDoomed {
                Text("Other Celestial Realities are sealed by Doom.")
                    .font(.caption)
                    .foregroundStyle(GameColor.pelle.readableOnDark())
                    .multilineTextAlignment(.center)
            }

            // Run effects description (web: GameDatabase.celestials.descriptions[0].effects()).
            if !runDescription.isEmpty {
                Text(runDescription)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .strikethrough(isPelleDoomed)
            }

            // Static paragraph from web TeresaTab.vue.
            Text("This Reality can be repeated for a stronger reward based on the antimatter gained within it.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .strikethrough(isPelleDoomed)

            if runCompleted {
                VStack(spacing: 6) {
                    Text("Your record: \(bestRunAM) antimatter")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    if !lastRepeatedMachinesLabel.isEmpty {
                        Text("achieved with \(lastRepeatedMachinesLabel).")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    // Inline glyph set preview (mirrors web GlyphSetPreview)
                    if !bestAMSet.isEmpty {
                        VStack(spacing: 4) {
                            Text("Glyph Set used:")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                            Button { onShowGlyphSet() } label: {
                                HStack(spacing: 6) {
                                    ForEach(bestAMSet) { g in
                                        GlyphComponent(glyph: g.asGlyphInfo, size: 36, isCircular: true, showLevel: true)
                                            .equatable()
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text("Teresa Reality reward: Glyph Sacrifice power \(runReward)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GameColor.teresa.readableOnDark())
                }
            } else {
                Text("You have not completed Teresa's Reality yet.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }

            if hasEPGen {
                Text("Every second, you gain 1% of your peaked Eternity Points per minute this Reality.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .strikethrough(isPelleDoomed)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .modifier(RoundedBorderModifier(color: GameColor.teresa.opacity(0.4), cornerRadius: 12, lineWidth: 1))
    }
}

// MARK: - Fill Bar
//
// Mirrors `src/components/tabs/celestial-teresa/TeresaTab.vue` RM store layout:
//   - Tall bar on the left (dark fill = poured, light fill = possible with current RM)
//   - Milestone tick lines across the bar at log-scale heights
//   - Milestone labels on the right with price + description + color-coded state
//   - Multiplier + poured/cap label centered on the fill
//
// Layout uses explicit pixel positions inside a GeometryReader rather than
// nested Spacers — each milestone renders the tick on the bar and its label
// on the label column at the same y-offset.

private struct TeresaFillBar: View {
    let fill: Double
    let possibleFill: Double
    let unlocks: [TeresaUnlockInfo]
    let multiplierText: String
    let pouredAmount: String
    let pouredCap: String
    let onTapMilestone: (TeresaUnlockInfo) -> Void

    private let barWidth: CGFloat = 140
    private let tickExtension: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let labelColumnWidth = max(geo.size.width - barWidth - tickExtension - 16, 120)
            let labelGap: CGFloat = 8

            // Single top-leading ZStack, all positions computed from (0, 0) at top-left.
            ZStack(alignment: .topLeading) {
                // Bar container (fills full height)
                barContainer(height: h)
                    .frame(width: barWidth, height: h)

                // Tick lines — drawn across the bar + tickExtension past it
                ForEach(unlocks) { unlock in
                    let pos = milestonePosition(unlock.price)
                    let color = unlock.isUnlocked ? GameColor.good : Color.white.opacity(0.6)
                    Rectangle()
                        .fill(color)
                        .frame(width: barWidth + tickExtension, height: 2)
                        .offset(x: 0, y: h * (1 - CGFloat(pos)) - 1)
                        .allowsHitTesting(false)
                }

                // Labels — positioned in the right-side column
                ForEach(unlocks) { unlock in
                    milestoneLabel(unlock: unlock, height: h, columnWidth: labelColumnWidth)
                        .offset(x: barWidth + tickExtension + labelGap, y: 0)
                }
            }
            .frame(width: geo.size.width, height: h, alignment: .topLeading)
        }
    }

    // MARK: Bar

    @ViewBuilder
    private func barContainer(height h: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            // Outline + black fill
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(GameColor.teresa, lineWidth: 2)
                )

            // Possible fill (translucent) — drawn behind solid fill so solid
            // covers the portion that's actually poured.
            RoundedRectangle(cornerRadius: 4)
                .fill(GameColor.teresa.opacity(0.3))
                .frame(height: h * clamp(possibleFill))

            // Solid poured fill
            RoundedRectangle(cornerRadius: 4)
                .fill(GameColor.teresa)
                .frame(height: h * clamp(fill))

            // Centered numbers over the fill
            VStack(spacing: 2) {
                Text(multiplierText + " RM gain")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                Text("\(pouredAmount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
                Text("/ \(pouredCap)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.bottom, 10)
        }
    }

    // MARK: Tick across the bar

    @ViewBuilder
    private func milestoneTick(unlock: TeresaUnlockInfo, height h: CGFloat) -> some View {
        let pos = milestonePosition(unlock.price)
        let color = unlock.isUnlocked ? GameColor.good : Color.white.opacity(0.6)
        Rectangle()
            .fill(color)
            .frame(width: barWidth + tickExtension, height: 2)
            .offset(x: 0, y: h * (1 - CGFloat(pos)) - 1)
            .allowsHitTesting(false)
    }

    // MARK: Label on right side

    @ViewBuilder
    private func milestoneLabel(unlock: TeresaUnlockInfo, height h: CGFloat, columnWidth: CGFloat) -> some View {
        let pos = milestonePosition(unlock.price)
        // Anchor the label so the top of its card sits 14pt above the tick
        // line, keeping the tick visually near the middle of the price text.
        let y = h * (1 - CGFloat(pos)) - 14
        let color: Color = unlock.isUnlocked ? GameColor.good : GameColor.teresa
        Button {
            onTapMilestone(unlock)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(formatPrice(unlock.price))
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(color)
                Text(unlock.description)
                    .font(.caption2)
                    .foregroundStyle(unlock.isUnlocked ? color.opacity(0.9) : .white.opacity(0.7))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(width: columnWidth, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(color.opacity(0.5), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .offset(y: y)
    }

    // MARK: - Helpers

    private func clamp(_ v: Double) -> CGFloat {
        CGFloat(min(1, max(0, v)))
    }

    /// Normalized position along the bar (0 = bottom, 1 = top) for an unlock's price.
    /// Mirrors web's `log1p(price) / log1p(maxPrice)` spacing.
    private func milestonePosition(_ price: Double) -> Double {
        let maxPrice = unlocks.map(\.price).max() ?? 1e24
        guard maxPrice > 0 else { return 0 }
        return min(1, max(0, log1p(price) / log1p(maxPrice)))
    }

    private func formatPrice(_ price: Double) -> String {
        if price >= 1e6 {
            // Scientific for large values
            let exponent = floor(log10(price))
            let mantissa = price / pow(10, exponent)
            return String(format: "%.0fe%.0f RM", mantissa, exponent)
        }
        return String(format: "%.0f RM", price)
    }
}

// MARK: - Perk Shop Row

private struct PerkShopUpgradeRow: View, Equatable {
    let upgrade: PerkShopUpgradeInfo
    let isPelleDoomed: Bool
    let engine: GameEngine

    static func == (lhs: PerkShopUpgradeRow, rhs: PerkShopUpgradeRow) -> Bool {
        lhs.upgrade == rhs.upgrade && lhs.isPelleDoomed == rhs.isPelleDoomed
        // engine excluded (identity-stable).
    }

    /// True when the player is doomed AND this upgrade is the music-glyph
    /// pair that web flags `o-pelle-disabled`. Mirrors `PerkShopUpgradeButton.vue:32`:
    /// `Pelle.isDoomed && (upgrade === PerkShopUpgrade.musicGlyph || upgrade === PerkShopUpgrade.fillMusicGlyph)`.
    /// The other four perk shop entries (glyphLevel, rmMult, bulkDilation,
    /// autoSpeed) remain normally interactive — those still apply in doom.
    /// JS-side `upgrade.purchase()` already no-ops for the music glyphs in
    /// doom; this flag just adds the matching visual + hit-test disable
    /// so iOS doesn't surface a clickable "Buy" affordance for an action
    /// that silently won't fire.
    private var isPelleUseless: Bool {
        isPelleDoomed && (upgrade.key == "musicGlyph" || upgrade.key == "fillMusicGlyph")
    }

    var body: some View {
        // Vertical block layout mirrors web's `<br>`-separated perk shop button
        // (`PerkShopUpgradeButton.vue`): description gets full width so it
        // wraps cleanly on narrow iPhone screens, with effect/cost and the
        // Buy button sharing the bottom row.
        VStack(alignment: .leading, spacing: 6) {
            Text(upgrade.description)
                .font(.caption)
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .strikethrough(isPelleUseless)

            HStack(alignment: .center, spacing: 8) {
                if !upgrade.effectText.isEmpty {
                    HStack(spacing: 6) {
                        Text("Current: \(upgrade.effectText)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(GameColor.teresa)
                            .strikethrough(isPelleUseless)
                        if let cap = upgrade.capText {
                            Text("/ \(cap)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .strikethrough(isPelleUseless)
                        }
                    }
                }
                Spacer(minLength: 8)
                GameButton(
                    theme: .teresa,
                    isEnabled: !isPelleUseless && upgrade.isAffordable && !upgrade.isCapped
                ) {
                    engine.buyPerkShopUpgrade(id: upgrade.id)
                } label: {
                    VStack(spacing: 2) {
                        if upgrade.isCapped {
                            Text("Capped")
                                .font(.caption.weight(.medium))
                        } else {
                            Text("Buy")
                                .font(.caption.weight(.semibold))
                            Text(upgrade.cost + " PP")
                                .font(.caption2)
                        }
                    }
                    .frame(minWidth: 70)
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Unlock detail popover

private struct UnlockDetailSheet: View {
    let unlock: TeresaUnlockInfo

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Teresa Milestone")
                .font(.headline)
                .foregroundStyle(GameColor.teresa)
            Text(String(format: "Pour %.2e RM to unlock:", unlock.price))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(unlock.description)
                .font(.body)
                .foregroundStyle(.white)
            if unlock.isUnlocked {
                Label("Unlocked", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if unlock.canBeUnlocked {
                Label("Ready to unlock — keep pouring!", systemImage: "arrow.up.circle")
                    .foregroundStyle(GameColor.teresa)
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .presentationDetents([.height(220)])
    }
}

// MARK: - Glyph Set Detail Sheet
//
// Reuses the shared `GlyphRichCard` — same layout as `EquippedGlyphsSheet`
// and `PeekGlyphsSheet`. The previous bespoke per-glyph layout was a
// pre-`GlyphRichCard` duplicate.

private struct TeresaGlyphSetSheet: View {
    let glyphs: [TeresaGlyphRecord]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Teresa's Best Glyph Set")
                        .font(.title2.weight(.bold))

                    ForEach(glyphs) { g in
                        GlyphRichCard(glyph: g.asGlyphInfo)
                            .equatable()
                    }
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
