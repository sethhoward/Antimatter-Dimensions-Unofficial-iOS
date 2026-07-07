//
//  LaitelaTab.swift
//  AntiMatter
//
//  Lai'tela celestial tab — Dark Matter Dimensions, Singularities, Continuum,
//  Annihilation, Singularity Milestones, and the Reality run button.
//
//  Mirrors web `LaitelaTab.vue` + subcomponents:
//    DarkMatterDimensionRow.vue, SingularityPane.vue,
//    SingularityMilestonePane.vue, AnnihilationButton.vue,
//    LaitelaAutobuyerPane.vue, LaitelaRunButton.vue.
//

import SwiftUI

struct LaitelaTab: View {
    let engine: GameEngine

    var body: some View {
        LaitelaTabContent(engine: engine)
    }
}

private struct LaitelaTabContent: View {
    let engine: GameEngine
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.sidebarState) private var sidebarState
    @Environment(\.scenePhase) private var scenePhase

    @State private var showAllMilestones = false
    @State private var autoAnnihilationText: String = ""
    @State private var showQuoteHistory = false
    #if DEBUG
    @State private var laitelaTierStepper: Int = 0
    #endif

    private var laitela: LaitelaState { engine.gameState.celestials.laitela }

    /// True only when Lai'tela is the visible subtab AND the scene is active.
    /// Drives `LaitelaSparkleIcon.isActive` so the rotating sparkles tear
    /// down off-screen / on backgrounding.
    private var isVisible: Bool {
        sidebarState?.activeSubtab == .laitela && scenePhase == .active
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !laitela.ready {
                    ProgressView().padding(.top, 40)
                }
                headerSection
                if laitela.isUnlocked {
                    SingularityPaneView(engine: engine, state: laitela.singularity, isDoomed: laitela.isDoomed)
                } else {
                    singularityUnlockTeaser
                }

                if laitela.autobuyers.isVisible {
                    LaitelaAutobuyerPaneView(engine: engine, pane: laitela.autobuyers)
                }

                LaitelaRunButtonView(engine: engine, state: laitela.run, isVisible: isVisible)

                dmdSection

                if laitela.annihilation.isVisible {
                    LaitelaAnnihilationButtonView(
                        engine: engine,
                        info: laitela.annihilation,
                        autoAnnihilationText: $autoAnnihilationText
                    )
                }

                if !laitela.allMilestones.isEmpty {
                    SingularityMilestoneCarousel(
                        engine: engine,
                        milestones: laitela.nextMilestones,
                        showAll: $showAllMilestones
                    )
                }

                #if DEBUG
                debugCheats
                #endif

                PhoneTabBarSpacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, metrics.isCompact ? 10 : 16)
        }
        .sheet(isPresented: $showAllMilestones) {
            SingularityMilestonesSheet(milestones: laitela.allMilestones, isPelleDoomed: engine.pelleDoomed)
        }
        .sheet(isPresented: $showQuoteHistory) {
            CelestialQuoteHistoryView(celestialKey: "laitela", engine: engine)
        }
        .onAppear {
            autoAnnihilationText = laitela.annihilation.autoMultiplier == 0
                ? ""
                : String(format: "%g", laitela.annihilation.autoMultiplier)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 6) {
            HStack {
                Spacer()
                Text("Lai'tela, Celestial of Dimensions")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(GameColor.laitela)
                Spacer()
                Button {
                    engine.loadQuoteHistory(for: "laitela")
                    showQuoteHistory = true
                } label: {
                    Image(systemName: "quote.bubble")
                        .font(.callout)
                        .foregroundStyle(GameColor.laitela)
                        .padding(8)
                        .background(GameColor.laitela.opacity(0.15), in: Circle())
                }
                .buttonStyle(.plain)
            }

            // Vue LaitelaTab.vue:97-102 — current DM amount with Average/s
            // suffix when uncapped, "(capped)" when at the Number.MAX_VALUE
            // ceiling.
            let dmValue = Text(laitela.darkMatter)
                .foregroundStyle(laitela.darkMatterCapped ? GameColor.laitela : .white)
                .fontWeight(.semibold)
            if laitela.darkMatterCapped {
                Text("You have \(dmValue) Dark Matter (capped).")
                    .font(metrics.isCompact ? .callout : .title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.9))
            } else {
                Text("You have \(dmValue) Dark Matter. (Average: \(laitela.darkMatterPerSecText)/s)")
                    .font(metrics.isCompact ? .callout : .title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Vue LaitelaTab.vue:103-107 — always shows max-ever; suffix
            // gated on `!isDoomed`.
            let maxValue = Text(laitela.maxDarkMatterEver)
                .foregroundStyle(laitela.darkMatterCapped ? GameColor.laitela : .white)
                .fontWeight(.semibold)
            if laitela.isDoomed {
                Text("Your maximum Dark Matter ever is \(maxValue).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Your maximum Dark Matter ever is \(maxValue), giving \(laitela.continuumBonusPct) more purchases from Continuum.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Dark Matter Dimensions are unaffected by storing real time.")
                .font(.caption2)
                .foregroundStyle(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)

            if laitela.isDoomed {
                Text("Destroyed by Pelle")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var singularityUnlockTeaser: some View {
        VStack(spacing: 6) {
            Text("Singularities")
                .font(.headline)
                .foregroundStyle(GameColor.laitela.readableOnDark())
            // Vue LaitelaTab.vue:114-117 — "Unlock Singularities in X." +
            // "(DE / cap Dark Energy)". iOS retains the pedagogical line
            // above as supplementary context for first-time players.
            if !laitela.singularityUnlockTime.isEmpty {
                Text("Unlock Singularities in \(laitela.singularityUnlockTime).")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GameColor.laitela.readableOnDark())
                    .multilineTextAlignment(.center)
            }
            Text("Charge Dark Energy to \(Text(laitela.singularity.cap).fontWeight(.semibold)), then Condense to form a Singularity.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Dark Energy:")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Text("\(laitela.singularity.darkEnergy) / \(laitela.singularity.cap)")
                    .font(.caption.monospacedDigit())
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.3))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(GameColor.laitela.opacity(0.3), lineWidth: 1))
        )
    }

    // MARK: - DMD section

    private var dmdSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Dark Matter Dimensions")
                    .font(.headline)
                    .foregroundStyle(GameColor.laitela.readableOnDark())
                Spacer()
                Button {
                    engine.laitelaMaxAllDMD()
                } label: {
                    Text("Max all")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(GameColor.laitela)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.black)
                        .roundedBorder(GameColor.laitela, lineWidth: 1)
                }
                .buttonStyle(.plain)
                .allowsHitTesting(!laitela.isDoomed)
                .opacity(laitela.isDoomed ? 0.4 : 1)
            }
            ForEach(laitela.dimensions) { row in
                DarkMatterDimensionRowView(engine: engine, row: row, isDoomed: laitela.isDoomed)
                    .equatable()
            }
        }
    }

    // MARK: - Debug cheats

    #if DEBUG
    @ViewBuilder
    private var debugCheats: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DEBUG")
                .font(.caption.weight(.bold))
                .foregroundStyle(.orange)
            HStack(spacing: 8) {
                Button("Max DMD") { engine.laitelaMaxAllDMD() }
                    .buttonStyle(.bordered)
                Button("+ tier") { engine.devCompleteLaitelaTier() }
                    .buttonStyle(.bordered)
                Button("+100 Sing") { engine.devGrantSingularities(100) }
                    .buttonStyle(.bordered)
                Button("+1e6 Sing") { engine.devGrantSingularities(1e6) }
                    .buttonStyle(.bordered)
                Button("+1e9 Sing") { engine.devGrantSingularities(1e9) }
                    .buttonStyle(.bordered)
            }
            .font(.caption)
            HStack(spacing: 8) {
                // "Seed DMDs" recovers from the stuck-at-zero state where
                // DMD1.amount = 0 (production = amount × ticks, so DM stops
                // growing entirely). Web seeds DMD1..4.amount to 1 in
                // ImaginaryUpgrade(15..18).onPurchased, but a Laitela.reset
                // or save migration can clear it.
                Button("Seed DMDs") { engine.devSeedDarkMatterDimensions() }
                    .buttonStyle(.borderedProminent)
                // 1e60 DM unlocks the first Annihilation. Higher tiers are
                // bumps for testing post-annihilation milestones. Capped at
                // 1e300 because Swift `Double` overflows above 1e308; for
                // bigger jumps, hit Annihilation a few times to compound.
                Button("DM = 1e60") { engine.devSetDarkMatter(1e60) }
                    .buttonStyle(.bordered)
                Button("DM = 1e150") { engine.devSetDarkMatter(1e150) }
                    .buttonStyle(.bordered)
                Button("DM = 1e300") { engine.devSetDarkMatter(1e300) }
                    .buttonStyle(.bordered)
                Button("DE = 1e9") { engine.devSetDarkEnergy(1e9) }
                    .buttonStyle(.bordered)
            }
            .font(.caption)
            HStack(spacing: 8) {
                Stepper("Difficulty tier: \(laitelaTierStepper)/8",
                        value: $laitelaTierStepper,
                        in: 0...8)
                    .font(.caption)
                Button("Apply") {
                    engine.devSetLaitelaDifficultyTier(laitelaTierStepper)
                }
                .buttonStyle(.borderedProminent)
                .font(.caption)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.4), lineWidth: 1)
        )
        .onAppear { laitelaTierStepper = laitela.run.difficultyTier }
        .onChange(of: laitela.run.difficultyTier) { _, newValue in
            laitelaTierStepper = newValue
        }
    }
    #endif
}

// MARK: - Dark Matter Dimension row

private struct DarkMatterDimensionRowView: View, Equatable {
    let engine: GameEngine
    let row: DarkMatterDimensionInfo
    let isDoomed: Bool
    @Environment(\.layoutMetrics) private var metrics

    static func == (lhs: DarkMatterDimensionRowView, rhs: DarkMatterDimensionRowView) -> Bool {
        lhs.row == rhs.row && lhs.isDoomed == rhs.isDoomed
        // engine excluded (identity-stable). LayoutMetrics is an env value
        // — observed via @Environment, not via Equatable.
    }

    private var accent: Color { GameColor.laitela }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title + amount + ascension badge
            HStack {
                Text("Dark Matter Dimension \(row.tier)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent.readableOnDark())
                if row.ascensionCount > 0 {
                    Text("Ascended ×\(row.ascensionCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(GameColor.laitela))
                }
                Spacer()
                Text(row.amount)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.white)
            }

            if !row.isUnlocked {
                Text("Locked — unlocked by Imaginary Upgrade")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Interval timer + production rate
                GeometryReader { geo in
                    let w = geo.size.width * CGFloat(row.timerPct)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.08))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(accent.opacity(0.5))
                            .frame(width: max(0, w))
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("Interval \(row.interval)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    Text("DE \(row.dePerSec)/sec")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(accent)
                }

                // Three buy buttons
                let btnFont: Font = metrics.isCompact ? .caption2.weight(.medium) : .caption.weight(.medium)
                let buttons = HStack(spacing: 6) {
                    DMDBuyButton(
                        title: row.isIntervalCapped ? "Ascend" : "Interval",
                        value: row.interval,
                        cost: row.intervalCost,
                        canBuy: row.isIntervalCapped ? true : row.canBuyInterval,
                        isDoomed: isDoomed,
                        font: btnFont
                    ) {
                        if row.isIntervalCapped { engine.laitelaAscend(tier: row.tier) }
                        else { engine.laitelaBuyInterval(tier: row.tier) }
                    }
                    DMDBuyButton(
                        title: "DM",
                        value: row.powerDM,
                        cost: row.powerDMCost,
                        canBuy: row.canBuyPowerDM,
                        isDoomed: isDoomed,
                        font: btnFont
                    ) {
                        engine.laitelaBuyPowerDM(tier: row.tier)
                    }
                    DMDBuyButton(
                        title: "DE",
                        value: row.powerDE,
                        cost: row.powerDECost,
                        canBuy: row.canBuyPowerDE,
                        isDoomed: isDoomed,
                        font: btnFont
                    ) {
                        engine.laitelaBuyPowerDE(tier: row.tier)
                    }
                }
                buttons
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(row.isUnlocked ? accent.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

private struct DMDBuyButton: View {
    let title: String
    let value: String
    let cost: String
    let canBuy: Bool
    let isDoomed: Bool
    let font: Font
    let action: () -> Void

    var body: some View {
        let enabled = canBuy && !isDoomed
        Button(action: {
            Haptics.tap()
            action()
        }) {
            VStack(spacing: 2) {
                Text(title).font(font).foregroundStyle(enabled ? GameColor.laitela : .white.opacity(0.5))
                Text(value).font(.caption2.monospacedDigit()).foregroundStyle(.white)
                // Interval / PowerDM / PowerDE upgrades are all priced in
                // Dark Matter — append the unit so the cost line matches web
                // `DarkMatterDimensionRow.vue`.
                Text("Cost: \(cost) DM")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(.black)
            .roundedBorder(enabled ? GameColor.laitela : Color.gray.opacity(0.3), lineWidth: 1)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(enabled)
        .opacity(isDoomed ? 0.5 : 1)
    }
}

// MARK: - Singularity pane

private struct SingularityPaneView: View {
    let engine: GameEngine
    let state: SingularityInfo
    let isDoomed: Bool
    @Environment(\.layoutMetrics) private var metrics

    private var isSingleSingularity: Bool {
        // singularitiesRaw is a plain JS number that can exceed Int.max
        // post-Reality. Compare as Double to avoid an Int.max cast crash.
        state.singularitiesRaw.rounded() == 1
    }

    var body: some View {
        VStack(spacing: 10) {
            // Two-column layout matching SingularityPane.vue: condense button
            // on the left, time-to-condense + gain-rate info on the right.
            let layout: AnyLayout = metrics.isCompact
                ? AnyLayout(VStackLayout(spacing: 10))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            layout {
                leftPane
                rightPane
            }

            // ± Singularity cap controls. Always visible once Lai'tela is
            // unlocked — the buttons enable/disable based on the current cap
            // level (JS guards: 0 ≤ capIncreases ≤ 50).
            HStack(spacing: 8) {
                GameButton(theme: .laitela, isEnabled: state.capIncreases > 0 && !isDoomed) {
                    engine.singularityDecreaseCap()
                } label: {
                    Text("Decrease Singularity cap.")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                GameButton(theme: .laitela, isEnabled: state.capIncreases < state.maxCapIncreases && !isDoomed) {
                    engine.singularityIncreaseCap()
                } label: {
                    Text("Increase Singularity cap.")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
            }
            // Static explainer: matches web `SingularityPane.vue` info text.
            Text("Each step increases the required Dark Energy by ×\(state.darkEnergyPerCapStep), but also increases gained Singularities by ×\(state.gainPerCapStep).")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if state.capIncreases > 0 {
                Text("Cap increased ×\(state.capIncreases)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
            }

            if state.hasAutoCondense {
                Text("Auto-Condense: \(state.autoCondenseActive ? "Active" : "Idle") \(state.autoCondenseFactorText.isEmpty ? "" : "(\(state.autoCondenseFactorText))")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.35))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(GameColor.laitela.opacity(0.5), lineWidth: 1))
        )
    }

    /// Left: "You have N Singularity" + Condense button + wait-text status.
    private var leftPane: some View {
        VStack(spacing: 6) {
            Text("You have \(state.singularities) \(isSingleSingularity ? "Singularity" : "Singularities")")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GameColor.laitela.readableOnDark())

            // Vue SingularityPane.vue uses `singularityFormText` + a separate
            // `singularityWaitText` line under the button. The JS bridge emits
            // both verbatim so iOS doesn't have to replicate the multi-
            // singularity / pre-cap branching itself.
            GameButton(theme: .laitela, isEnabled: state.canPerform && !isDoomed) {
                engine.singularityPerform()
            } label: {
                VStack(spacing: 2) {
                    Text(state.formText.isEmpty
                         ? "Condense all Dark Energy into a Singularity"
                         : state.formText)
                        .font(.callout.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if !state.waitText.isEmpty {
                        Text(state.waitText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Right: DE readout + bulk-unlock hint + time-to-(auto-)condense + gain
    /// rate(s). Labels switch when auto-condense is unlocked, matching web
    /// `SingularityPane.vue`.
    private var rightPane: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("You have \(state.darkEnergy) Dark Energy. (+\(state.darkEnergyPerSec)/s)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.trailing)
            if !state.hasBulkUnlocked {
                Text("Reach 10 Singularities to unlock Bulk Singularities.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            // Time-to-condense line. Auto-condense mode adds both the
            // parenthesised label tweak and an extra-delay suffix.
            if state.hasAutoCondense {
                let suffix = state.extraTimeAfterSingularityText.isEmpty
                    ? ""
                    : " (+\(state.extraTimeAfterSingularityText))"
                Text("Total time to (auto-)condense: \(state.timePerCondenseText)\(suffix)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("Manual Singularity gain rate: \(state.gainPerHourText) per hour")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("Automatic Singularity gain rate: \(state.autoGainPerHourText) per hour")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("Total time to condense: \(state.timePerCondenseText)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("Singularity gain rate: \(state.gainPerHourText) per hour")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Singularity Milestones

private struct SingularityMilestoneCarousel: View {
    let engine: GameEngine
    let milestones: [SingularityMilestoneInfo]
    @Binding var showAll: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Singularity Milestones")
                    .font(.headline)
                    .foregroundStyle(GameColor.laitela.readableOnDark())
                Spacer()
                Button {
                    showAll = true
                } label: {
                    Text("Show all")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(GameColor.laitela)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.black)
                        .roundedBorder(GameColor.laitela, lineWidth: 1)
                }
                .buttonStyle(.plain)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 8)], spacing: 8) {
                ForEach(milestones) { m in
                    SingularityMilestoneCard(milestone: m, isPelleDoomed: engine.pelleDoomed)
                        .equatable()
                }
            }
        }
    }
}

private struct SingularityMilestonesSheet: View {
    let milestones: [SingularityMilestoneInfo]
    let isPelleDoomed: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 10)], spacing: 10) {
                    ForEach(milestones) { m in
                        SingularityMilestoneCard(milestone: m, isPelleDoomed: isPelleDoomed)
                            .equatable()
                    }
                }
                .padding(16)
            }
            .adaptiveSheetTitle("Singularity Milestones")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .tint(GameColor.laitela)
                }
            }
        }
    }
}

private struct SingularityMilestoneCard: View, Equatable {
    let milestone: SingularityMilestoneInfo
    /// Doom strikes through every label in the card. Mirrors web
    /// `SingularityMilestoneComponent.vue:129` which wraps the entire content
    /// `<span>` in `o-pelle-disabled` when `Pelle.isDoomed`. No per-milestone
    /// gating — Lai'tela's milestones are uniformly nullified during doom
    /// (Singularity itself is `Pelle.isDisabled("singularity")`).
    var isPelleDoomed: Bool = false

    static func == (lhs: SingularityMilestoneCard, rhs: SingularityMilestoneCard) -> Bool {
        lhs.milestone == rhs.milestone && lhs.isPelleDoomed == rhs.isPelleDoomed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text(milestone.description)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
                    .strikethrough(isPelleDoomed)
                Spacer()
                if !milestone.isUnique {
                    Text("\(milestone.completions)/\(milestone.limit >= 999 ? "∞" : "\(milestone.limit)")")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .strikethrough(isPelleDoomed)
                }
            }
            if !milestone.effectText.isEmpty {
                HStack(spacing: 4) {
                    Text(milestone.effectText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(GameColor.laitela.readableOnDark())
                        .strikethrough(isPelleDoomed)
                    if !milestone.nextEffectText.isEmpty {
                        Text("➜")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .strikethrough(isPelleDoomed)
                        Text(milestone.nextEffectText)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                            .strikethrough(isPelleDoomed)
                    }
                }
            }
            // Progress bar
            GeometryReader { geo in
                let w = geo.size.width * CGFloat(milestone.progressPct)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(milestone.isMaxed ? Color.green : GameColor.laitela.opacity(0.7))
                        .frame(width: max(0, w))
                }
            }
            .frame(height: 4)

            HStack {
                if milestone.isMaxed {
                    Text("Maxed")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.green)
                        .strikethrough(isPelleDoomed)
                } else {
                    Text("In \(milestone.remainingSingularities) Singularities")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .strikethrough(isPelleDoomed)
                }
                Spacer()
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(milestone.isMaxed ? Color.green.opacity(0.4) : GameColor.laitela.opacity(milestone.isUnlocked ? 0.5 : 0.25), lineWidth: 1)
                )
        )
    }
}

// MARK: - Annihilation

private struct LaitelaAnnihilationButtonView: View {
    let engine: GameEngine
    let info: LaitelaAnnihilationInfo
    @Binding var autoAnnihilationText: String

    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        VStack(spacing: 6) {
            Text("Annihilation")
                .font(.headline)
                .foregroundStyle(GameColor.laitela.readableOnDark())
                .frame(maxWidth: .infinity, alignment: .leading)

            GameButton(theme: .laitela, isEnabled: info.canAnnihilate) {
                engine.laitelaAnnihilate()
            } label: {
                VStack(spacing: 2) {
                    if info.canAnnihilate {
                        Text("Annihilate: \(info.darkMatterMult) \(info.darkMatterMultRatio)")
                            .font(.callout.weight(.semibold))
                    } else {
                        Text(info.requirementText)
                            .font(.callout.weight(.medium))
                    }
                    Text("Current: \(info.darkMatter) DM | Mult \(info.darkMatterMult) ➜ gain \(info.darkMatterMultGain)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            if info.autoUnlocked {
                // Isolated, Equatable so it skips body re-eval on the 30Hz ticks
                // that update the DM/gain readout above — otherwise re-applying the
                // `.alert` each tick yanks first responder and the keyboard flickers.
                LaitelaAutoAnnihilationEntry(
                    autoMultiplier: info.autoMultiplier,
                    isCompact: metrics.isCompact,
                    autoAnnihilationText: $autoAnnihilationText,
                    commit: { commitAutoMultiplier() }
                )
                .equatable()
            }
        }
    }

    private func commitAutoMultiplier() {
        let v = Double(autoAnnihilationText.replacingOccurrences(of: ",", with: ".")) ?? 0
        engine.laitelaSetAnnihilationMultiplier(v)
    }
}

/// Auto-Annihilation threshold entry row + its window-level alert. Split out of
/// `LaitelaAnnihilationButtonView` (which redraws at 30Hz for the live DM readout)
/// and made `Equatable` on only the stable inputs so the alert isn't torn down
/// every tick — that tear-down was dismissing the keyboard the instant it opened.
/// The `@Binding` + `commit` closure are intentionally excluded from `==`.
private struct LaitelaAutoAnnihilationEntry: View, Equatable {
    let autoMultiplier: Double
    let isCompact: Bool
    @Binding var autoAnnihilationText: String
    let commit: () -> Void

    @State private var showAutoAlert = false

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.autoMultiplier == rhs.autoMultiplier && lhs.isCompact == rhs.isCompact
    }

    private var displayText: String {
        autoMultiplier == 0 ? String(localized: "Set…") : String(format: "%g", autoMultiplier)
    }

    var body: some View {
        Group {
            if isCompact {
                // iPhone: inline TextField focus is unreliable inside SubtabPager
                // (@FocusState/.focused doesn't engage in the UIHostingController, so the
                // keypad never appears). Route entry through a window-level alert.
                HStack {
                    Text("Auto at mult gain ≥")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        autoAnnihilationText = autoMultiplier == 0 ? "" : String(format: "%g", autoMultiplier)
                        showAutoAlert = true
                    } label: {
                        Text(displayText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack {
                    Text("Auto at mult gain ≥")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("0", text: $autoAnnihilationText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .onSubmit { commit() }
                    Button("Set") { commit() }
                        .buttonStyle(.bordered)
                        .font(.caption)
                }
            }
        }
        .alert(String(localized: "Auto-Annihilation Multiplier"), isPresented: $showAutoAlert) {
            TextField("0", text: $autoAnnihilationText)
                .keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) { }
            Button("Set") { commit() }
        } message: {
            Text("Automatically annihilate when the Dark Matter multiplier gain reaches this value.")
        }
    }
}

// MARK: - Autobuyer pane

private struct LaitelaAutobuyerPaneView: View {
    let engine: GameEngine
    let pane: LaitelaAutobuyerPaneInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Autobuyers")
                .font(.headline)
                .foregroundStyle(GameColor.laitela.readableOnDark())
            // Only render unlocked toggles — matches web LaitelaAutobuyerPane.vue
            // where each row is gated by its own milestone `v-if`.
            if pane.dimension.isUnlocked    { row(toggle: pane.dimension, name: "dimension") }
            if pane.ascension.isUnlocked    { row(toggle: pane.ascension, name: "ascension") }
            if pane.singularity.isUnlocked  { row(toggle: pane.singularity, name: "singularity") }
            if pane.annihilation.isUnlocked { row(toggle: pane.annihilation, name: "annihilation") }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.3))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(GameColor.laitela.opacity(0.3), lineWidth: 1))
        )
    }

    @ViewBuilder
    private func row(toggle: LaitelaAutobuyerToggle, name: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(toggle.label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                Text(toggle.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { toggle.isActive },
                set: { newValue in engine.laitelaToggleAutobuyer(name, active: newValue) }
            ))
            .labelsHidden()
            .tint(GameColor.laitela)
        }
    }
}

// MARK: - Run button

private struct LaitelaRunButtonView: View {
    let engine: GameEngine
    let state: LaitelaRunInfo
    /// True only when the Lai'tela subtab is on-screen and the scene is
    /// active — propagated down to `LaitelaSparkleIcon` so its rotation
    /// CAAnimation tears down off-screen / on backgrounding.
    let isVisible: Bool

    @State private var showGlyphSet = false

    var body: some View {
        VStack(spacing: 6) {
            Button {
                guard !engine.pelleDoomed else { return }
                engine.requestLaitelaRun()
            } label: {
                VStack(spacing: 6) {
                    HStack(spacing: 10) {
                        // Continuously rotating sigil — 15s/360° idle, 5s/360°
                        // running. Mirrors the web's o-laitela-run-button__icon
                        // scroll animation (we substitute spin for the tiled
                        // SVG scroll because we don't bundle the asset; the
                        // intent is "ongoing motion in the void"). See
                        // `LaitelaRunButton.swift` for parity notes.
                        LaitelaSparkleIcon(isRunning: state.isRunning, isActive: isVisible)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.isRunning ? "Running Lai'tela's Reality" : "Start Lai'tela's Reality")
                                .font(.callout.weight(.semibold))
                                .strikethrough(engine.pelleDoomed)
                            if state.difficultyTier > 0 {
                                Text("Destabilised tier \(state.difficultyTier)/8  |  Max DMD \(state.maxAllowedDimension)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.75))
                                    .strikethrough(engine.pelleDoomed)
                            } else {
                                Text("Complete to destabilise Lai'tela and unlock rewards.")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.75))
                                    .strikethrough(engine.pelleDoomed)
                            }
                        }
                        Spacer()
                        Text(state.realityReward)
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(GameColor.laitela)
                    }

                    // Vue LaitelaRunButton.vue:55-83 — multiplier line + tier
                    // status + run-effects + description. iOS previously only
                    // surfaced the fastest-completion sentinel.
                    if !state.multiplierLine.isEmpty {
                        Text(state.multiplierLine)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(GameColor.laitela.readableOnDark())
                            .strikethrough(engine.pelleDoomed)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    let hasCompleted = state.difficultyTier > 0 || state.fastestCompletionSeconds < 3600
                    if hasCompleted {
                        // Mirrors Vue: tier 1-7 surfaces "Highest active
                        // dimension: N"; tier 8 (fully destabilised) shows the
                        // "+×8 Dark Energy + cannot improve" reward copy.
                        if state.maxAllowedDimension > 0 && state.maxAllowedDimension <= 7 {
                            Text("Highest active dimension: \(state.maxAllowedDimension)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.85))
                                .strikethrough(engine.pelleDoomed)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else if state.isFullyDestabilized {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("You also gain an additional ×8 Dark Energy.")
                                    .font(.caption2.weight(.semibold))
                                Text("Lai'tela's Reality has been fully destabilized and cannot have its reward further improved.")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.65))
                            }
                            .strikethrough(engine.pelleDoomed)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text("Fastest completion: \(state.fastestCompletionText)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("Never completed (reward scales with speed once you finish).")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Per-line run effects (`descriptions[5].effects()`)
                    // followed by the standalone description paragraph.
                    if !state.runEffectsLines.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(state.runEffectsLines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.85))
                                    .strikethrough(engine.pelleDoomed)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !state.description.isEmpty {
                        Text(state.description)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .strikethrough(engine.pelleDoomed)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Color.black)
                .roundedBorder(GameColor.laitela, lineWidth: 2)
            }
            .buttonStyle(.plain)
            .opacity(engine.pelleDoomed ? 0.4 : 1)
            .allowsHitTesting(!engine.pelleDoomed)
            if engine.pelleDoomed {
                Text("Other Celestial Realities are sealed by Doom.")
                    .font(.caption)
                    .foregroundStyle(GameColor.pelle.readableOnDark())
                    .multilineTextAlignment(.center)
            }

            // Web LaitelaRunButton.vue:79-89 — Glyph Set used for the
            // fastest destabilization, shown inline below the run button.
            // iOS surfaces it as a tappable preview row that opens a sheet
            // with the shared GlyphRichCard layout, mirroring how Teresa
            // shows her bestAMSet.
            if !state.bestSet.isEmpty {
                Button { showGlyphSet = true } label: {
                    VStack(spacing: 4) {
                        Text("Fastest Destabilization Glyph Set")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                        HStack(spacing: 6) {
                            ForEach(state.bestSet) { g in
                                GlyphComponent(glyph: g.asGlyphInfo, size: 36, isCircular: true, showLevel: true)
                                    .equatable()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showGlyphSet) {
                    LaitelaGlyphSetSheet(glyphs: state.bestSet)
                }
            }
        }
    }
}

// MARK: - Lai'tela glyph-set detail sheet

private struct LaitelaGlyphSetSheet: View {
    let glyphs: [TeresaGlyphRecord]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Fastest Destabilization Glyph Set")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(GameColor.laitela)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

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
