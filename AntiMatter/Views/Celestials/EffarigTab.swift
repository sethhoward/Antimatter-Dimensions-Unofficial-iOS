//
//  EffarigTab.swift
//  AntiMatter
//
//  Effarig's Reality — shop, Relic Shards, run button, stage-unlock milestones,
//  and the three glyph-management sub-features unlocked by shop upgrades.
//  Mirrors src/components/tabs/celestial-effarig/EffarigTab.vue.
//

import SwiftUI

struct EffarigTab: View {
    let engine: GameEngine

    var body: some View {
        EffarigTabContent(engine: engine)
    }
}

private struct EffarigTabContent: View {
    let engine: GameEngine
    @Environment(\.sidebarState) private var sidebarState
    @Environment(\.scenePhase) private var scenePhase

    @State private var showHistory = false
    @State private var showWeights = false
    @State private var showFilter = false
    @State private var showPresets = false

    private var e: EffarigState { engine.gameState.celestials.effarig }

    /// True only when Effarig is the visible subtab AND the scene is active.
    /// Drives `EffarigRunButton.isActive` so cached SubtabPager pages and
    /// backgrounded scenes don't keep the glow CAAnimation scheduled.
    /// Same pattern as TeresaTab.
    private var isVisible: Bool {
        sidebarState?.activeSubtab == .effarig && scenePhase == .active
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                shardGainBlock        // moved up to match Vue ordering
                shardGainHints        // "More EP slightly increases..." static line
                shopSection
                if e.vIsFlipped {
                    cursedGlyphButton
                }
                if e.runUnlocked {
                    EffarigRunSection(
                        engine: engine,
                        isRunning: e.isRunning,
                        runDescription: e.runDescription,
                        currentStageName: e.currentStageName,
                        glyphLevelCap: e.glyphLevelCap,
                        isActive: isVisible,
                        isPelleDoomed: engine.pelleDoomed
                    )
                    .equatable()
                    milestonesSection
                }
                PhoneTabBarSpacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .sheet(isPresented: $showHistory) {
            CelestialQuoteHistoryView(celestialKey: "effarig", engine: engine)
        }
        .sheet(isPresented: $showWeights) {
            EffarigGlyphWeightsSheet(engine: engine)
        }
        .sheet(isPresented: $showFilter) {
            EffarigGlyphFilterSheet(engine: engine)
        }
        .sheet(isPresented: $showPresets) {
            EffarigGlyphPresetsSheet(engine: engine)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("You have \(e.relicShards) Relic Shards.")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.white)
                    // Web EffarigTab.vue:105-112 — rarity boost line varies on
                    // Ra's `extraGlyphChoicesAndRelicShardRarityAlwaysMax`.
                    if !e.shardRarityBoostPct.isEmpty {
                        if e.relicShardRarityAlwaysMax {
                            Text("The rarity of new Glyphs is being increased by +\(e.shardRarityBoostPct).")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.75))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("Each new Glyph will have its rarity increased by a random value between +0% and +\(e.shardRarityBoostPct).")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.75))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    // Web EffarigTab.vue:113-116 — Ra shard-power boost on
                    // Glyph Sacrifice gain only (NOT rarity, despite name).
                    if !e.shardPower.isEmpty {
                        Text("Glyph Sacrifice gain is also being raised to \(e.shardPower).")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                Button {
                    engine.loadQuoteHistory(for: "effarig")
                    showHistory = true
                } label: {
                    Label("Quote History", systemImage: "quote.bubble")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(GameColor.effarig)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(GameColor.effarig.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Shard gain (moved up from footer; mirrors Vue header ordering)

    @ViewBuilder
    private var shardGainBlock: some View {
        if e.shardsGained != "0" {
            VStack(alignment: .leading, spacing: 4) {
                Text("You will gain \(e.shardsGained) Relic Shards next Reality (\(e.currentShardsRate)/min).")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                if e.amplification > 0 {
                    Text("Due to amplification of your current Reality, you will actually gain a total of \(e.amplifiedShards) Relic Shards (\(e.amplifiedShardsRate)/min).")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Web EffarigTab.vue:129-136 — static descriptive copy explaining what
    /// drives Relic Shard gain. Was missing from iOS.
    private var shardGainHints: some View {
        Text("More Eternity Points slightly increases Relic Shards gained. More distinct Glyph effects significantly increases Relic Shards gained.")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.6))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Shop

    private var shopSection: some View {
        // Web EffarigTab.vue:142-145 — `run` shop card is only rendered when
        // !runUnlocked (`v-if="!runUnlocked"`). The 3 standard shop upgrades
        // (adjuster, glyphFilter, setSaves) are always visible.
        VStack(alignment: .leading, spacing: 10) {
            Text("Shop")
                .font(.headline)
                .foregroundStyle(GameColor.effarig.readableOnDark())

            ForEach(visibleShopUpgrades) { up in
                EffarigShopCard(
                    upgrade: up,
                    onBuy: { engine.buyEffarigUpgrade(id: up.id) },
                    onOpen: { openSheet(for: up.key) }
                )
                .equatable()
            }
        }
        .padding(14)
        .modifier(RoundedBorderModifier(color: GameColor.effarig.opacity(0.4), cornerRadius: 12, lineWidth: 1))
    }

    private var visibleShopUpgrades: [EffarigShopUpgrade] {
        e.shopUpgrades.filter { up in
            !(up.key == "run" && e.runUnlocked)
        }
    }

    private func openSheet(for key: String) {
        switch key {
        case "adjuster": showWeights = true
        case "glyphFilter": showFilter = true
        case "setSaves": showPresets = true
        default: break
        }
    }

    // MARK: - Cursed glyph easter egg (V.isFlipped only)

    private var cursedGlyphButton: some View {
        VStack(spacing: 8) {
            GameButton(theme: .effarig, isEnabled: true) {
                engine.giveCursedGlyph()
            } label: {
                Text("Get a Cursed Glyph…")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 4) {
                Text("Cursed Glyphs can be created here or in the V tab.")
                Text("Cursed Glyphs count as −3 Glyphs for the purposes of all requirements related to Glyph count.")
                Text("The Black Hole can now be used to slow down time if they are both permanent.")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.75))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Stage milestones

    private var milestonesSection: some View {
        let doomed = engine.pelleDoomed
        return VStack(alignment: .leading, spacing: 10) {
            Text("Run Rewards")
                .font(.headline)
                .foregroundStyle(GameColor.effarig.readableOnDark())
                .strikethrough(doomed)

            ForEach(e.runUnlocks) { r in
                EffarigMilestoneCard(unlock: r, isPelleDoomed: doomed)
                    .equatable()
            }
        }
        .padding(14)
        .modifier(RoundedBorderModifier(color: GameColor.effarig.opacity(0.4), cornerRadius: 12, lineWidth: 1))
    }
}

// MARK: - Run Section (Equatable)

private struct EffarigRunSection: View, Equatable {
    let engine: GameEngine
    let isRunning: Bool
    let runDescription: String
    let currentStageName: String
    let glyphLevelCap: Int
    let isActive: Bool
    let isPelleDoomed: Bool

    static func == (lhs: EffarigRunSection, rhs: EffarigRunSection) -> Bool {
        lhs.isRunning == rhs.isRunning
            && lhs.runDescription == rhs.runDescription
            && lhs.currentStageName == rhs.currentStageName
            && lhs.glyphLevelCap == rhs.glyphLevelCap
            && lhs.isActive == rhs.isActive
            && lhs.isPelleDoomed == rhs.isPelleDoomed
        // engine excluded (identity-stable).
    }

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            // Web EffarigTab.vue:160 — "Enter Effarig's Reality."
            Text("Enter Effarig's Reality.")
                .font(.headline)
                .foregroundStyle(GameColor.effarig.readableOnDark())
                .strikethrough(isPelleDoomed)

            EffarigRunButton(isRunning: isRunning, isActive: isActive) {
                guard !isPelleDoomed else { return }
                engine.requestEffarigRun()
            }
            .opacity(isPelleDoomed ? 0.4 : 1)
            .allowsHitTesting(!isPelleDoomed && !isRunning)
            if isPelleDoomed {
                Text("Other Celestial Realities are sealed by Doom.")
                    .font(.caption)
                    .foregroundStyle(GameColor.pelle.readableOnDark())
                    .multilineTextAlignment(.center)
            }

            if !runDescription.isEmpty {
                Text(runDescription)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .strikethrough(isPelleDoomed)
            }

            // iPad addition (no web equivalent, documented as a deliberate
            // divergence): surface the current Effarig stage + glyph level
            // cap. Web only conveys this via the milestone-card unlock state.
            Text("Current stage: \(currentStageName) — Glyph level cap \(glyphLevelCap)")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
                .strikethrough(isPelleDoomed)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .modifier(RoundedBorderModifier(color: GameColor.effarig.opacity(0.4), cornerRadius: 12, lineWidth: 1))
    }
}

// MARK: - Shop card

private struct EffarigShopCard: View, Equatable {
    let upgrade: EffarigShopUpgrade
    let onBuy: () -> Void
    let onOpen: () -> Void

    static func == (lhs: EffarigShopCard, rhs: EffarigShopCard) -> Bool {
        lhs.upgrade == rhs.upgrade
        // Closures excluded (capture engine reference, identity-stable).
    }

    private var hasSheet: Bool {
        upgrade.key == "adjuster" || upgrade.key == "glyphFilter" || upgrade.key == "setSaves"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(upgrade.description)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if upgrade.isUnlocked {
                    Text("Unlocked")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(GameColor.boughtBorderGreen, in: Capsule())
                        .foregroundStyle(.white)
                }
            }

            HStack(spacing: 8) {
                if !upgrade.isUnlocked {
                    Text("Cost: \(upgrade.cost) Relic Shards")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(upgrade.canAfford ? GameColor.effarig : .white.opacity(0.55))
                    Spacer(minLength: 8)
                    GameButton(theme: .effarig, isEnabled: upgrade.canAfford) {
                        onBuy()
                    } label: {
                        Text("Buy")
                            .font(.caption.weight(.semibold))
                            .frame(minWidth: 60)
                            .padding(.vertical, 6)
                    }
                } else if hasSheet {
                    Spacer()
                    GameButton(theme: .effarig, isEnabled: true) {
                        onOpen()
                    } label: {
                        Text("Open…")
                            .font(.caption.weight(.semibold))
                            .frame(minWidth: 70)
                            .padding(.vertical, 6)
                    }
                }
                // `run` card stays hidden after unlock (web parity); no need
                // for an "after-unlock" affordance here.
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(GameColor.effarig.opacity(upgrade.isUnlocked ? 0.6 : 0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Milestone card

private struct EffarigMilestoneCard: View, Equatable {
    let unlock: EffarigRunUnlock
    var isPelleDoomed: Bool = false

    static func == (lhs: EffarigMilestoneCard, rhs: EffarigMilestoneCard) -> Bool {
        lhs.unlock == rhs.unlock && lhs.isPelleDoomed == rhs.isPelleDoomed
    }

    /// Glyph symbol for Effarig (GLYPH_SYMBOLS.effarig in web).
    private var effarigSymbol: String { "Ξ" }

    private var lines: [String] {
        // Prefer the per-line array from the JS bridge; fall back to the
        // single-string description if the bridge didn't populate it
        // (mirrors `EffarigRunUnlockReward.vue` `descriptionLines`).
        unlock.descriptionLines.isEmpty ? [unlock.description] : unlock.descriptionLines
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(unlock.label):")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(unlock.isUnlocked ? GameColor.effarig.readableOnDark() : Color.white.opacity(0.7))
                    .strikethrough(isPelleDoomed)
                Spacer()
                if unlock.isUnlocked {
                    Label("Unlocked", systemImage: "checkmark.circle.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(GameColor.good)
                } else {
                    Text("?")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            if unlock.isUnlocked {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: 6) {
                            Text(effarigSymbol)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(GameColor.effarig.readableOnDark())
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                                .strikethrough(isPelleDoomed)
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            unlock.isUnlocked ? GameColor.effarig.opacity(0.6) : GameColor.effarig.opacity(0.2),
                            lineWidth: 1
                        )
                )
        )
    }
}

