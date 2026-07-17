//
//  AutobuyersTab.swift
//  AntiMatter
//
//  Autobuyers tab — automatic purchasers matching the web Modern UI layout.
//  Order: Big Crunch, Galaxy, DimBoost, Tickspeed, Dimensions (high→low prestige).
//

import SwiftUI

// MARK: - SecretAchievement(28) "Nice." easter egg

/// Watch any autobuyer `TextField`'s bound text — fire SecretAchievement(28)
/// the first time the user enters exactly "69". Mirrors web
/// `AutobuyerInput.vue:73-74` `handleChange`, which checks the raw display
/// value before parsing. Pre-parse check is intentional: a parsed numeric
/// `69` would also match the typed "69", but typing something else that
/// rounds to 69 (`"69.0"`, `"070-1"`, etc.) shouldn't trigger.
fileprivate extension View {
    func detectsNiceEasterEgg(_ text: String, engine: GameEngine) -> some View {
        onChange(of: text) { _, new in
            if new == "69" {
                engine.devCommand("SecretAchievement(28).unlock();")
            }
        }
    }
}

struct AutobuyersTab: View {
    let engine: GameEngine

    var body: some View {
        ScrollView {
            AutobuyersContent(engine: engine)
        }
        .scrollDismissesKeyboard(.interactively)
        .preserveScrollPosition(key: "autobuyers")
    }
}

/// Reads `engine.gameState.autobuyers` internally so the parent
/// `AutobuyersTab` body never re-evaluates from per-tick state churn.
/// All sub-views, gating bools, and the controls row live here.
private struct AutobuyersContent: View {
    let engine: GameEngine

    @Environment(\.layoutMetrics) private var metrics

    private var state: AutobuyersState { engine.gameState.autobuyers }

    /// All 8 AD autobuyers are bought with maxed intervals — show compact collapsed row
    private var allDimsCollapsed: Bool {
        state.dimensions.count == 8 &&
        state.dimensions.allSatisfy { ($0.isBought || $0.canBeUpgraded) && $0.hasMaxedInterval && $0.hasMaxedBulk }
    }

    /// Whether any simple autobuyers are unlocked (drives visibility of the
    /// wrapping VStack that hosts every "advanced" autobuyer card). Must
    /// include every autobuyer rendered inside the `if hasSimpleAutobuyers
    /// || allDimsCollapsed` block below — otherwise late-game unlocks (Reality
    /// / Imaginary rebuyables, Black Hole power upgrades) can flip
    /// `isUnlocked = true` without lighting up this flag, leaving their cards
    /// stranded behind the parent gate. (`reality`, `eternityAutobuyer`, and
    /// `bigCrunch` live above the gate so they don't need to be listed.)
    private var hasSimpleAutobuyers: Bool {
        state.ipMult.isUnlocked || state.replicantiGalaxy.isUnlocked
        || state.sacrifice.isUnlocked
        || engine.gameState.infinityDimensions.isAnyAutobuyerUnlocked
        || state.replicantiUpgrades.isAnyUnlocked
        || state.timeDimensions.isUnlocked
        || state.dilationUpgrades.isUnlocked
        || state.epMult.isUnlocked
        || state.realityUpgradeRebuyables.isUnlocked
        || state.imaginaryUpgradeRebuyables.isUnlocked
        || state.blackHolePower.anyUnlocked
    }

    var body: some View {
        VStack(spacing: 12) {
                if engine.pelleDoomed {
                    PelleSimpleDisabledBanner(
                        text: "Pre-Doom autobuyers are disabled. Each autobuyer must be re-acquired through a Pelle Upgrade."
                    )
                }
                // 1. Global controls
                controlButtons

                // 2. Info text
                Text("Autobuyers with no displayed bulk have unlimited bulk by default.\nAntimatter Dimension Autobuyers can have their bulk upgraded once interval is below 100 ms.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                // 3. Prestige autobuyers (high → low, matching web AutobuyersTab.vue order)
                if state.reality.isUnlocked {
                    RealityAutobuyerCard(info: state.reality, engine: engine)
                }
                if state.eternityAutobuyer.isUnlocked {
                    EternityAutobuyerCard(info: state.eternityAutobuyer, engine: engine)
                }
                if state.bigCrunch.isUnlocked {
                    BigCrunchAutobuyerCard(info: state.bigCrunch, allOn: state.allOn, engine: engine)
                }

                // 4. Galaxy, DimBoost, Tickspeed
                if state.galaxy.isUnlocked {
                    GalaxyAutobuyerCard(info: state.galaxy, allOn: state.allOn, engine: engine)
                }
                if state.dimBoost.isUnlocked {
                    DimBoostAutobuyerCard(info: state.dimBoost, allOn: state.allOn, engine: engine)
                }
                // Tickspeed autobuyer hidden when Lai'tela's Continuum is
                // active — matches web `<TickspeedAutobuyerBox v-if="!hasContinuum" />`
                // (continuum replaces explicit tickspeed purchases entirely).
                // Visibility mirrors web `AutobuyerBox.vue` template: render
                // when `isUnlocked || isBought || canBeBought`. The JS getter
                // factors `Pelle.isDisabled("tickspeedAutobuyer")` so this
                // hides at the start of Doom until the corresponding Pelle
                // Upgrade is bought. `canBeBought` is the "earned-but-not-
                // yet-purchased" state (post-first-Eternity reward, pre-IP
                // purchase) — required to render the unlock card.
                if !(engine.continuumUnlocked && !engine.continuumDisabled),
                   state.tickspeed.isUnlocked || state.tickspeed.isBought || state.tickspeed.canBeBought {
                    UpgradeableAutobuyerCard(
                        info: state.tickspeed,
                        allOn: state.allOn,
                        onPurchase: { engine.purchaseAutobuyer("tickspeed") },
                        onToggle: { engine.toggleAutobuyer("tickspeed") },
                        onUpgrade: { engine.upgradeAutobuyerInterval("tickspeed") },
                        onToggleMode: { engine.toggleAutobuyerMode("tickspeed") }
                    )
                }

                // 5. AD autobuyers — replaced by the Continuum info banner
                //    when continuum is active (web `MultipleAutobuyersBox.vue`
                //    v-else-if="isADBox && continuumActive").
                if engine.continuumUnlocked && !engine.continuumDisabled {
                    ContinuumInfoBanner()
                } else if !allDimsCollapsed {
                    // Gate per-tier — mirrors web `AutobuyerBox.vue`
                    // `isUnlocked || isBought` plus the `canBeBought`
                    // pre-purchase state (web renders that as the "Tap to
                    // unlock" card via AutobuyerBox's v-else-if branch). The
                    // JS `isUnlocked` getter factors `Pelle.isDisabled` per
                    // tier, so cards correctly hide at the start of Doom and
                    // reappear as their owning Pelle Upgrades are purchased.
                    ForEach(state.dimensions) { dim in
                        if dim.isUnlocked || dim.isBought || dim.canBeBought {
                            DimensionAutobuyerCard(dim: dim, allOn: state.allOn, engine: engine)
                        }
                    }
                }

                // 6. Simple autobuyers section (collapsed groups + toggle-only).
                // Pelle disables every "advanced" autobuyer here (TD, ID, RU
                // rebuyables, IU rebuyables, BH power upgrades, dilation
                // upgrades, replicanti upgrades, sacrifice, repl galaxy, TT,
                // IP/EP mult, DMD/Annihilation/Singularity). Only the
                // collapsed AD-autobuyer card may reappear once the player
                // buys back AD autobuyers via Pelle Upgrades.
                if hasSimpleAutobuyers || allDimsCollapsed {
                    VStack(spacing: 8) {
                        // Collapsed AD autobuyers — survives Doom because the
                        // AD autobuyers themselves can be re-acquired via
                        // Pelle Upgrades antimatterDimAutobuyers1/2.
                        if allDimsCollapsed {
                            CollapsedDimensionAutobuyers(dims: state.dimensions, allOn: state.allOn, engine: engine)
                        }

                        if !engine.pelleDoomed {
                            // Collapsed ID autobuyers
                            if engine.gameState.infinityDimensions.isAnyAutobuyerUnlocked {
                                InfinityDimAutobuyersCard(
                                    dims: engine.gameState.infinityDimensions.dimensions,
                                    engine: engine
                                )
                            }

                            // Time Dimension autobuyers (unlocked by RealityUpgrade(13))
                            if state.timeDimensions.isUnlocked {
                                TDAutobuyersCard(info: state.timeDimensions, engine: engine)
                            }

                            // Replicanti Upgrade autobuyers (unlocked at 50/60/80 eternities)
                            if state.replicantiUpgrades.isAnyUnlocked {
                                ReplicantiUpgradeAutobuyersCard(
                                    info: state.replicantiUpgrades,
                                    engine: engine
                                )
                            }

                            // Dilation Upgrade autobuyers (unlocked by Perk.autobuyerDilation)
                            if state.dilationUpgrades.isUnlocked {
                                DilationAutobuyersCard(info: state.dilationUpgrades, engine: engine)
                            }

                            // Reality Upgrade rebuyable autobuyers (Ra V pet lv 1)
                            if state.realityUpgradeRebuyables.isUnlocked {
                                RealityUpgradeAutobuyersCard(info: state.realityUpgradeRebuyables, engine: engine)
                            }

                            // Imaginary Upgrade rebuyable autobuyers — 10 tiles,
                            // unlocked by ImaginaryUpgrade(20) "Vacuum Acceleration".
                            if state.imaginaryUpgradeRebuyables.isUnlocked {
                                ImaginaryUpgradeAutobuyersCard(info: state.imaginaryUpgradeRebuyables, engine: engine)
                            }

                            // Black Hole power upgrade autobuyers (Ra Enslaved pet lv 1)
                            if state.blackHolePower.anyUnlocked {
                                BlackHolePowerAutobuyersCard(info: state.blackHolePower, engine: engine)
                            }

                            // Single special autobuyers — horizontal grid
                            // (Sacrifice, Replicanti Galaxy, TT, IP/EP Mult,
                            // Dark Matter Dims, Dark Matter Dims Ascension,
                            // Singularity, Annihilation). Matches web
                            // `MultipleSingleAutobuyersGroup.vue`.
                            SingleAutobuyersRow(state: state, engine: engine)
                        }
                    }
                }

            PhoneTabBarSpacer()
        }
        .padding()
    }

    // MARK: - Control buttons (Pause + Enable/Disable all + Continuum)

    private var controlButtons: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                GameButton(borderColor: state.allOn ? .green : GameColor.pausedActive) {
                    engine.toggleAllAutobuyers()
                } label: {
                    Text(state.allOn ? "Pause autobuyers" : "Resume autobuyers")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: Self.controlButtonHeight)
                }
                .frame(width: metrics.isCompact ? nil : 200)
                .frame(maxWidth: metrics.isCompact ? .infinity : nil)

                GameButton(borderColor: .green) {
                    engine.toggleAllAutobuyerStates()
                } label: {
                    Text(state.allAutobuyersDisabled ? "Enable all autobuyers" : "Disable all autobuyers")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: Self.controlButtonHeight)
                }
                .frame(width: metrics.isCompact ? nil : 220)
                .frame(maxWidth: metrics.isCompact ? .infinity : nil)
            }

            // Continuum toggle — matches web `AutobuyerToggles.vue` v-if="showContinuum".
            // Label flips relative to the `disableContinuum` player flag: when
            // continuum is currently disabled the button offers to Enable it.
            if engine.laitelaUnlocked {
                GameButton(borderColor: .green) {
                    // setContinuum(enabled:) takes the *desired* state — the
                    // inverse of the current disableContinuum flag.
                    engine.laitelaSetContinuum(enabled: engine.continuumDisabled)
                } label: {
                    Text(engine.continuumDisabled ? "Enable Continuum" : "Disable Continuum")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: Self.controlButtonHeight)
                }
                .frame(width: metrics.isCompact ? nil : 220)
                .frame(maxWidth: metrics.isCompact ? .infinity : nil)
            }
        }
        .padding(.bottom, 4)
    }

    /// Tall tap target for the global control buttons. Matches web's
    /// `o-autobuyer-btn { height: 3.5rem }` (~56pt).
    private static let controlButtonHeight: CGFloat = 52
}

// MARK: - Card background

private struct AutobuyerCardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
    }
}

// MARK: - Globally-paused indicator
//
// `\.autobuyersGloballyPaused` env key + `.pausedAwareTint(isActive:)` modifier
// now live in `Helpers/PausedAwareTint.swift` so every tab with inline autobuyer
// toggles (ID, TD, Replicanti, Black Hole, etc.) can use them. Set once at the
// app shell from `engine.gameState.autobuyers.allOn`.

// MARK: - Collapsed Dimension Autobuyers

private struct CollapsedDimensionAutobuyers: View {
    let dims: [AutobuyerDimInfo]
    let allOn: Bool
    let engine: GameEngine

    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        Group {
            if metrics.isCompact {
                compactLayout
            } else {
                regularLayout
            }
        }
        .padding(12)
        .background(GameColor.sidebarBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(cardBorderColor.opacity(0.4), lineWidth: 1)
        )
    }

    private var compactLayout: some View {
        VStack(spacing: 8) {
            VStack(spacing: 4) {
                Text("Antimatter Dimension Autobuyers")
                    .font(.caption.weight(.medium))
                    .multilineTextAlignment(.center)
                Text("Current interval: 0.10 seconds")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            tileRow(Array(dims.prefix(4)))
            tileRow(Array(dims.suffix(4)))
        }
    }

    private var regularLayout: some View {
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("Antimatter Dimension\nAutobuyers")
                    .font(.caption.weight(.medium))
                    .multilineTextAlignment(.center)
                Text("Current interval: 0.10 seconds")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 160)

            tileRow(dims)
        }
    }

    private func tileRow(_ items: [AutobuyerDimInfo]) -> some View {
        AutobuyerTileRow(items: items) { dim in
            AutobuyerTile(
                tier: dim.tier,
                isUnlocked: true,
                isActive: dim.isActive,
                onToggle: { engine.toggleAutobuyer("antimatterDimension", tier: dim.tier) }
            ) {
                Button {
                    engine.toggleAutobuyerMode("antimatterDimension", tier: dim.tier)
                } label: {
                    Text(dim.mode == "BUY_10" ? "Buys max" : "Buys 1")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(cardBorderColor.opacity(0.4), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Infinity Dimension Autobuyers (compact card)

private struct InfinityDimAutobuyersCard: View {
    let dims: [InfinityDimState]
    let engine: GameEngine

    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        Group {
            if metrics.isCompact {
                compactLayout
            } else {
                regularLayout
            }
        }
        .padding(12)
        .background(GameColor.sidebarBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(cardBorderColor.opacity(0.4), lineWidth: 1)
        )
    }

    private var compactLayout: some View {
        VStack(spacing: 8) {
            Text("Infinity Dimension Autobuyers")
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
            tileRow(Array(dims.prefix(4)))
            tileRow(Array(dims.suffix(4)))
        }
    }

    private var regularLayout: some View {
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("Infinity Dimension\nAutobuyers")
                    .font(.caption.weight(.medium))
                    .multilineTextAlignment(.center)
            }
            .frame(width: 160)

            tileRow(dims)
        }
    }

    private func tileRow(_ items: [InfinityDimState]) -> some View {
        AutobuyerTileRow(items: items) { dim in
            AutobuyerTile(
                tier: dim.tier,
                isUnlocked: dim.isAutobuyerUnlocked,
                isActive: dim.isAutobuyerActive,
                onToggle: { engine.toggleInfinityDimAutobuyer(dim.tier) }
            ) {
                EmptyView()
            }
        }
    }
}

// MARK: - Time Dimension Autobuyers Card

private struct TDAutobuyersCard: View {
    let info: TDAutobuyersInfo
    let engine: GameEngine

    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        Group {
            if metrics.isCompact {
                VStack(spacing: 8) {
                    headerContent
                    tileRow(Array(info.tiers.prefix(4)))
                    tileRow(Array(info.tiers.suffix(4)))
                }
            } else {
                HStack(spacing: 0) {
                    headerContent
                        .frame(width: 160)
                    tileRow(info.tiers)
                }
            }
        }
        .padding(12)
        .background(GameColor.sidebarBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(cardBorderColor.opacity(0.4), lineWidth: 1)
        )
    }

    private var headerContent: some View {
        VStack(spacing: 4) {
            Text(metrics.isCompact ? "Time Dimension Autobuyers" : "Time Dimension\nAutobuyers")
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)

            Button {
                engine.toggleAllTimeDimensionAutobuyers()
            } label: {
                Text("Toggle all")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(GameColor.eternity)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(white: 0.15), in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
        }
    }

    private func tileRow(_ items: [TDAutobuyerTierInfo]) -> some View {
        AutobuyerTileRow(items: items) { tier in
            AutobuyerTile(
                tier: tier.tier,
                isUnlocked: true,
                isActive: tier.isActive,
                onToggle: { engine.toggleTimeDimensionAutobuyer(tier.tier) }
            ) {
                EmptyView()
            }
        }
    }
}

// MARK: - Dilation Upgrade Autobuyers Card

private struct DilationAutobuyersCard: View {
    let info: DilationAutobuyersInfo
    let engine: GameEngine

    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        Group {
            if metrics.isCompact {
                VStack(spacing: 8) {
                    Text("Dilation Upgrade Autobuyers")
                        .font(.caption.weight(.medium))
                        .multilineTextAlignment(.center)
                    HStack(spacing: 6) {
                        ForEach(info.upgrades) { upgrade in
                            dilationTile(upgrade)
                        }
                    }
                }
            } else {
                HStack(spacing: 0) {
                    Text("Dilation Upgrade\nAutobuyers")
                        .font(.caption.weight(.medium))
                        .multilineTextAlignment(.center)
                        .frame(width: 160)
                    HStack(spacing: 6) {
                        ForEach(info.upgrades) { upgrade in
                            dilationTile(upgrade)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(GameColor.sidebarBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(cardBorderColor.opacity(0.4), lineWidth: 1)
        )
    }

    private func dilationTile(_ upgrade: DilationAutobuyerEntry) -> some View {
        VStack(spacing: 4) {
            Toggle(isOn: Binding(
                get: { upgrade.isActive },
                set: { _ in engine.toggleDilationUpgradeAutobuyer(upgrade.id) }
            )) {
                EmptyView()
            }
            .toggleStyle(.switch)
            .labelsHidden()
            .pausedAwareTint(isActive: upgrade.isActive, normalColor: GameColor.dilationGreen)

            Text(upgrade.name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Reality Upgrade autobuyers

/// Collapsed card for the 5 Reality Upgrade rebuyable autobuyers.
/// Unlocked by Ra V pet lv 1. Mirrors `DilationAutobuyersCard` layout.
private struct RealityUpgradeAutobuyersCard: View {
    let info: RealityUpgradeAutobuyersInfo
    let engine: GameEngine

    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        Group {
            if metrics.isCompact {
                VStack(spacing: 8) {
                    Text("Reality Upgrade Autobuyers")
                        .font(.caption.weight(.medium))
                        .multilineTextAlignment(.center)
                    HStack(spacing: 6) {
                        ForEach(info.upgrades) { upgrade in
                            tile(upgrade)
                        }
                    }
                }
            } else {
                HStack(spacing: 0) {
                    Text("Reality Upgrade\nAutobuyers")
                        .font(.caption.weight(.medium))
                        .multilineTextAlignment(.center)
                        .frame(width: 160)
                    HStack(spacing: 6) {
                        ForEach(info.upgrades) { upgrade in
                            tile(upgrade)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(GameColor.sidebarBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(GameColor.reality.opacity(0.4), lineWidth: 1)
        )
    }

    private func tile(_ upgrade: RealityUpgradeAutobuyerEntry) -> some View {
        VStack(spacing: 4) {
            Toggle(isOn: Binding(
                get: { upgrade.isActive },
                set: { on in engine.toggleRealityUpgradeAutobuyer(upgrade.id, on: on) }
            )) {
                EmptyView()
            }
            .toggleStyle(.switch)
            .labelsHidden()
            .pausedAwareTint(isActive: upgrade.isActive, normalColor: GameColor.reality)

            Text(upgrade.name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Continuum info banner

/// Full-width banner shown in place of the AD autobuyer cards + Tickspeed
/// autobuyer when Lai'tela's Continuum is active. Mirrors web
/// `MultipleAutobuyersBox.vue`'s `isADBox && continuumActive` branch.
private struct ContinuumInfoBanner: View {
    var body: some View {
        Text("Continuum replaces your Antimatter Dimension and Tickspeed Autobuyers, as your production multipliers now automatically and continuously scale based on how many purchases you would have had otherwise.")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.85))
            .multilineTextAlignment(.center)
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(GameColor.sidebarBackground, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(GameColor.laitela.opacity(0.5), lineWidth: 1)
            )
    }
}

// MARK: - Imaginary Upgrade autobuyers

/// 10-tile card for the rebuyable Imaginary Upgrade autobuyers. Unlocked by
/// `ImaginaryUpgrade(20).canBeApplied` (Vacuum Acceleration). Mirrors web
/// `MultipleAutobuyersBox` for `Autobuyer.imaginaryUpgrade` — 5×2 grid on
/// iPhone, one horizontal row on iPad.
private struct ImaginaryUpgradeAutobuyersCard: View {
    let info: ImaginaryUpgradeAutobuyersInfo
    let engine: GameEngine

    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        Group {
            if metrics.isCompact {
                VStack(spacing: 8) {
                    Text("Imaginary Upgrade Autobuyers")
                        .font(.caption.weight(.medium))
                        .multilineTextAlignment(.center)
                    Text("Current interval: Instant")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 6),
                                        GridItem(.flexible(), spacing: 6),
                                        GridItem(.flexible(), spacing: 6),
                                        GridItem(.flexible(), spacing: 6),
                                        GridItem(.flexible(), spacing: 6)],
                              spacing: 6) {
                        ForEach(info.upgrades) { tile($0) }
                    }
                }
            } else {
                HStack(spacing: 0) {
                    VStack(alignment: .center, spacing: 4) {
                        Text("Imaginary Upgrade")
                        Text("Autobuyers")
                        Text("Current interval: Instant")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption.weight(.medium))
                    .multilineTextAlignment(.center)
                    .frame(width: 180)
                    HStack(spacing: 6) {
                        ForEach(info.upgrades) { tile($0) }
                    }
                }
            }
        }
        .padding(12)
        .background(GameColor.sidebarBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(GameColor.reality.opacity(0.4), lineWidth: 1)
        )
    }

    private func tile(_ upgrade: ImaginaryUpgradeAutobuyerEntry) -> some View {
        VStack(spacing: 4) {
            Toggle(isOn: Binding(
                get: { upgrade.isActive },
                set: { on in engine.toggleImaginaryUpgradeAutobuyer(upgrade.id, on: on) }
            )) { EmptyView() }
            .toggleStyle(.switch)
            .labelsHidden()
            .pausedAwareTint(isActive: upgrade.isActive, normalColor: GameColor.reality)

            Text(upgrade.name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Black Hole power autobuyers

/// Collapsed card for the 6 Black Hole power upgrade autobuyers
/// (BH1/BH2 × interval/power/duration). Unlocked individually per BH as
/// their upgrades become available; Ra Enslaved pet lv 1 is the gate.
private struct BlackHolePowerAutobuyersCard: View {
    let info: BlackHolePowerAutobuyersInfo
    let engine: GameEngine

    @Environment(\.layoutMetrics) private var metrics

    /// Group the 6 entries by black hole (1 and 2) so each row labels its BH.
    private var groupedByBH: [(bhId: Int, entries: [BlackHolePowerAutobuyerEntry])] {
        let unlocked = info.upgrades.filter(\.isUnlocked)
        let bh1 = unlocked.filter { $0.bhId == 1 }
        let bh2 = unlocked.filter { $0.bhId == 2 }
        var out: [(Int, [BlackHolePowerAutobuyerEntry])] = []
        if !bh1.isEmpty { out.append((1, bh1)) }
        if !bh2.isEmpty { out.append((2, bh2)) }
        return out
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("Black Hole Power Autobuyers")
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)

            ForEach(groupedByBH, id: \.bhId) { group in
                HStack(spacing: 6) {
                    Text("BH\(group.bhId)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36)
                    ForEach(group.entries) { entry in
                        tile(entry)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(GameColor.sidebarBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(GameColor.enslaved.opacity(0.4), lineWidth: 1)
        )
    }

    private func tile(_ entry: BlackHolePowerAutobuyerEntry) -> some View {
        VStack(spacing: 4) {
            Toggle(isOn: Binding(
                get: { entry.isActive },
                set: { on in engine.toggleBlackHoleUpgradeAutobuyer(upgradeId: entry.id, on: on) }
            )) {
                EmptyView()
            }
            .toggleStyle(.switch)
            .labelsHidden()
            .pausedAwareTint(isActive: entry.isActive, normalColor: GameColor.enslaved)

            Text(entry.type.capitalized)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Shared Autobuyer Tile Components

/// Shared row layout for collapsed 8-tile autobuyer cards (AD and ID).
private struct AutobuyerTileRow<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items) { item in
                content(item)
            }
        }
    }
}

/// Single tile in a collapsed autobuyer card — toggle + tier name + optional extra content.
private struct AutobuyerTile<Extra: View>: View {
    let tier: Int
    let isUnlocked: Bool
    let isActive: Bool
    let onToggle: () -> Void
    @ViewBuilder let extra: Extra

    var body: some View {
        VStack(spacing: 6) {
            if isUnlocked {
                Toggle("", isOn: Binding(
                    get: { isActive },
                    set: { _ in onToggle() }
                ))
                .labelsHidden()
                .scaleEffect(0.65)
                .frame(height: 24)
                .pausedAwareTint(isActive: isActive)
            } else {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(height: 24)
            }

            Text(DimensionState.safeTierName(tier))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isUnlocked ? .white : .secondary)

            extra
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background(GameColor.sidebarBackground, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(cardBorderColor.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Helpers

private let cardButtonHeight: CGFloat = 36
private let cardBorderColor = GameColor.antimatter
private let upgradeButtonCompactWidth: CGFloat = 100
private let modeButtonCompactWidth: CGFloat = 80

private func intervalText(_ ms: Int) -> String {
    if ms <= 100 { return "Instant" }
    let seconds = Double(ms) / 1000.0
    return String(format: "%.2f seconds", seconds)
}

// MARK: - Interval + Upgrade row (shared by all upgradeable autobuyers)

private struct IntervalUpgradeRow: View {
    @Environment(\.layoutMetrics) private var metrics
    let interval: Int
    let bulk: Int?
    let cost: String
    let canUpgrade: Bool
    let canBeUpgraded: Bool
    let hasMaxedInterval: Bool
    let onUpgrade: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if hasMaxedInterval {
                // No upgrade button
            } else if canBeUpgraded {
                Button(action: onUpgrade) {
                    VStack(spacing: 2) {
                        Text("40% smaller interval")
                            .font(.caption2.weight(.medium))
                        Text("Cost: \(cost) IP")
                            .font(.caption2)
                    }
                    .frame(minHeight: cardButtonHeight)
                    .frame(width: metrics.isCompact ? upgradeButtonCompactWidth : nil)
                    .padding(.horizontal, 10)
                    .background(canUpgrade ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
                    .roundedBorder(cardBorderColor.opacity(canUpgrade ? 0.8 : 0.3))
                }
                .buttonStyle(.plain)
                .allowsHitTesting(canUpgrade)
                .opacity(canUpgrade ? 1.0 : 0.5)
            } else {
                Text("Complete the challenge to upgrade interval")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: cardButtonHeight)
                    .frame(width: metrics.isCompact ? upgradeButtonCompactWidth : nil)
                    .padding(.horizontal, 10)
                    .background(Color.white.opacity(0.03))
                    .roundedBorder(cardBorderColor.opacity(0.3))
            }
        }
    }
}

// MARK: - Dimension Autobuyer Card

private struct DimensionAutobuyerCard: View {
    @Environment(\.layoutMetrics) private var metrics
    let dim: AutobuyerDimInfo
    let allOn: Bool
    let engine: GameEngine

    private var tierName: String { DimensionState.safeTierName(dim.tier) }

    var body: some View {
        if dim.isBought || dim.canBeUpgraded {
            boughtCard
        } else if dim.canBeBought {
            purchaseCard
        } else {
            lockedCard
        }
    }

    private var boughtCard: some View {
        Group {
            if metrics.isCompact {
                compactBoughtCard
            } else {
                regularBoughtCard
            }
        }
    }

    private var compactBoughtCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(tierName) Dimension Autobuyer")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Toggle("", isOn: Binding(get: { dim.isActive }, set: { _ in
                    engine.toggleAutobuyer("antimatterDimension", tier: dim.tier)
                }))
                .labelsHidden()
                .controlSize(.small)
                .pausedAwareTint(isActive: dim.isActive)
            }

            HStack(spacing: 12) {
                Text("Interval: \(intervalText(dim.interval))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Bulk: ×\(dim.bulk)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                upgradeButton
                modeButton
                Spacer()
            }
        }
        .modifier(AutobuyerCardBackground())
    }

    private var regularBoughtCard: some View {
        HStack(spacing: 12) {
            // Left: name + interval + bulk
            VStack(alignment: .leading, spacing: 2) {
                Text("\(tierName) Dimension Autobuyer")
                    .font(.subheadline.weight(.medium))
                Text("Current interval: \(intervalText(dim.interval))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Current bulk: ×\(dim.bulk)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Center: upgrade + mode buttons
            HStack(spacing: 8) {
                upgradeButton
                modeButton
            }

            Spacer()

            // Right: toggle
            Toggle("", isOn: Binding(get: { dim.isActive }, set: { _ in
                engine.toggleAutobuyer("antimatterDimension", tier: dim.tier)
            }))
            .labelsHidden()
            .controlSize(.small)
            .pausedAwareTint(isActive: dim.isActive)
        }
        .modifier(AutobuyerCardBackground())
    }

    @ViewBuilder
    private var upgradeButton: some View {
        if dim.hasMaxedInterval && !dim.hasMaxedBulk {
            Button {
                engine.upgradeAutobuyerBulk(dim.tier)
            } label: {
                VStack(spacing: 2) {
                    Text("Double bulk buy")
                        .font(.caption2.weight(.medium))
                    Text("Cost: \(dim.cost) IP")
                        .font(.caption2)
                }
                .frame(minHeight: cardButtonHeight)
                .frame(width: metrics.isCompact ? upgradeButtonCompactWidth : nil)
                .padding(.horizontal, 10)
                .background(dim.canUpgradeBulk ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
                .roundedBorder(cardBorderColor.opacity(dim.canUpgradeBulk ? 0.8 : 0.3))
            }
            .buttonStyle(.plain)
            .allowsHitTesting(dim.canUpgradeBulk)
            .opacity(dim.canUpgradeBulk ? 1.0 : 0.5)
        } else if dim.hasMaxedInterval && dim.hasMaxedBulk {
            Text("×512 bulk buy (capped)")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(minHeight: cardButtonHeight)
                .frame(width: metrics.isCompact ? upgradeButtonCompactWidth : nil)
                .padding(.horizontal, 10)
                .background(Color.white.opacity(0.03))
                .roundedBorder(cardBorderColor.opacity(0.3))
        } else if dim.canBeUpgraded {
            Button {
                engine.upgradeAutobuyerInterval("antimatterDimension", tier: dim.tier)
            } label: {
                VStack(spacing: 2) {
                    Text("40% smaller interval")
                        .font(.caption2.weight(.medium))
                    Text("Cost: \(dim.cost) IP")
                        .font(.caption2)
                }
                .frame(minHeight: cardButtonHeight)
                .frame(width: metrics.isCompact ? upgradeButtonCompactWidth : nil)
                .padding(.horizontal, 10)
                .background(dim.canUpgrade ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
                .roundedBorder(cardBorderColor.opacity(dim.canUpgrade ? 0.8 : 0.3))
            }
            .buttonStyle(.plain)
            .allowsHitTesting(dim.canUpgrade)
            .opacity(dim.canUpgrade ? 1.0 : 0.5)
        } else {
            Text("Complete the challenge to upgrade interval")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(minHeight: cardButtonHeight)
                .frame(width: metrics.isCompact ? upgradeButtonCompactWidth : nil)
                .padding(.horizontal, 10)
                .background(Color.white.opacity(0.03))
                .roundedBorder(cardBorderColor.opacity(0.3))
        }
    }

    private var modeButton: some View {
        Button {
            engine.toggleAutobuyerMode("antimatterDimension", tier: dim.tier)
        } label: {
            Text(dim.mode == "BUY_10" ? "Buys max" : "Buys singles")
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(minHeight: cardButtonHeight)
                .frame(width: metrics.isCompact ? modeButtonCompactWidth : nil)
                .padding(.horizontal, metrics.isCompact ? 10 : 14)
                .background(Color.white.opacity(0.08))
                .roundedBorder(cardBorderColor.opacity(0.6))
        }
        .buttonStyle(.plain)
    }

    private var purchaseCard: some View {
        Button {
            engine.purchaseAutobuyer("antimatterDimension", tier: dim.tier)
        } label: {
            HStack {
                Text("\(tierName) Dimension Autobuyer")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("Tap to unlock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
            .padding(12)
            .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var lockedCard: some View {
        HStack {
            Text("\(tierName) Dimension Autobuyer")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text("Requires \(dim.antimatterCost) total AM")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Upgradeable Autobuyer Card (Tickspeed)

private struct UpgradeableAutobuyerCard: View {
    @Environment(\.layoutMetrics) private var metrics
    let info: AutobuyerSingleInfo
    let allOn: Bool
    let onPurchase: () -> Void
    let onToggle: () -> Void
    let onUpgrade: () -> Void
    var onToggleMode: (() -> Void)? = nil

    var body: some View {
        if info.isBought {
            boughtView
        } else if info.canBeBought {
            purchaseView
        } else {
            lockedView
        }
    }

    @ViewBuilder private var boughtView: some View {
        if metrics.isCompact {
            compactBoughtView
        } else {
            regularBoughtView
        }
    }

    private var compactBoughtView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(info.name)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Toggle("", isOn: Binding(get: { info.isActive }, set: { _ in onToggle() }))
                    .labelsHidden()
                    .controlSize(.small)
                    .pausedAwareTint(isActive: info.isActive)
            }

            Text("Interval: \(intervalText(info.interval))")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                IntervalUpgradeRow(
                    interval: info.interval, bulk: nil, cost: info.cost,
                    canUpgrade: info.canUpgrade, canBeUpgraded: info.canBeUpgraded,
                    hasMaxedInterval: info.hasMaxedInterval, onUpgrade: onUpgrade
                )
                if let toggleMode = onToggleMode {
                    modeButton(toggleMode: toggleMode)
                }
                Spacer()
            }
        }
        .modifier(AutobuyerCardBackground())
    }

    private var regularBoughtView: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(info.name)
                    .font(.subheadline.weight(.medium))
                Text("Current interval: \(intervalText(info.interval))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            IntervalUpgradeRow(
                interval: info.interval, bulk: nil, cost: info.cost,
                canUpgrade: info.canUpgrade, canBeUpgraded: info.canBeUpgraded,
                hasMaxedInterval: info.hasMaxedInterval, onUpgrade: onUpgrade
            )

            if let toggleMode = onToggleMode {
                modeButton(toggleMode: toggleMode)
            }

            Spacer()

            Toggle("", isOn: Binding(get: { info.isActive }, set: { _ in onToggle() }))
                .labelsHidden()
                .controlSize(.small)
                .pausedAwareTint(isActive: info.isActive)
        }
        .modifier(AutobuyerCardBackground())
    }

    private func modeButton(toggleMode: @escaping () -> Void) -> some View {
        Button {
            toggleMode()
        } label: {
            Text(info.isModeLocked
                 ? "Complete the challenge to change mode"
                 : (info.isBuyMax ? "Buys max" : "Buys singles"))
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(info.isModeLocked ? nil : 1)
                .minimumScaleFactor(0.85)
                .frame(minHeight: cardButtonHeight)
                .frame(width: metrics.isCompact ? (info.isModeLocked ? upgradeButtonCompactWidth : modeButtonCompactWidth) : nil)
                .padding(.horizontal, metrics.isCompact ? 10 : 14)
                .background(Color.white.opacity(0.08))
                .roundedBorder(cardBorderColor.opacity(info.isModeLocked ? 0.3 : 0.6))
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!info.isModeLocked)
    }

    @ViewBuilder private var purchaseView: some View {
        Button(action: onPurchase) {
            HStack {
                Text(info.name)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("Tap to unlock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
            .padding(12)
            .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var lockedView: some View {
        HStack {
            Text(info.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text("Requires \(info.antimatterCost) total AM")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - DimBoost Autobuyer Card

private struct DimBoostAutobuyerCard: View {
    let info: DimBoostAutobuyerInfo
    let allOn: Bool
    let engine: GameEngine

    @State private var buyMaxText: String = ""
    @FocusState private var isEditingBuyMax: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dimension Boost Autobuyer")
                        .font(.subheadline.weight(.medium))
                    if info.isBuyMaxUnlocked {
                        Text("Buys max every interval")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Current interval: \(intervalText(info.interval))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !info.isBuyMaxUnlocked {
                    IntervalUpgradeRow(
                        interval: info.interval, bulk: nil, cost: info.cost,
                        canUpgrade: info.canUpgrade, canBeUpgraded: true,
                        hasMaxedInterval: info.hasMaxedInterval,
                        onUpgrade: { engine.upgradeDimBoostAutobuyer() }
                    )
                }

                Spacer()

                Toggle("", isOn: Binding(get: { info.isActive }, set: { _ in
                    engine.toggleDimBoostAutobuyer()
                }))
                .labelsHidden()
                .controlSize(.small)
                .pausedAwareTint(isActive: info.isActive)
            }

            Divider().opacity(0.3)

            if info.isBuyMaxUnlocked {
                // Buy-max interval input
                HStack(spacing: 8) {
                    Text("Activates every")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    TextField("seconds", text: $buyMaxText)
                        .font(.caption.monospacedDigit())
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .focused($isEditingBuyMax)
                        .onSubmit { commitBuyMax() }
                        .onAppear { buyMaxText = info.buyMaxInterval }
                        .onChange(of: info.buyMaxInterval) { _, newVal in
                            if !isEditingBuyMax { buyMaxText = newVal }
                        }
                        .onChange(of: isEditingBuyMax) { _, editing in
                            if !editing { commitBuyMax() }
                        }
                        .onDisappear { commitBuyMax() }
                        .detectsNiceEasterEgg(buyMaxText, engine: engine)
                    Text("seconds")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            // Limit boosts — only when buy max is NOT unlocked
            if !info.isBuyMaxUnlocked {
                LimitSettingRow(
                    label: "Limit boosts to:",
                    isEnabled: info.limitDimBoosts,
                    value: info.maxDimBoosts,
                    onToggle: { newVal in engine.setDimBoostLimit(enabled: newVal, max: info.maxDimBoosts) },
                    onChange: { newVal in engine.setDimBoostLimit(enabled: info.limitDimBoosts, max: newVal) }
                )
            }

            LimitSettingRow(
                label: info.isBuyMaxUnlocked
                    ? "Only Dimboost to unlock new Dimensions until X Galaxies:"
                    : "Galaxies required to always Dimboost, ignoring the limit:",
                isEnabled: info.limitUntilGalaxies,
                value: info.galaxies,
                onToggle: { newVal in engine.setDimBoostGalaxyLimit(enabled: newVal, galaxies: info.galaxies) },
                onChange: { newVal in engine.setDimBoostGalaxyLimit(enabled: info.limitUntilGalaxies, galaxies: newVal) }
            )
        }
        .modifier(AutobuyerCardBackground())
    }

    private func commitBuyMax() {
        let trimmed = buyMaxText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        engine.setDimBoostBuyMaxInterval(trimmed)
        isEditingBuyMax = false
    }
}

// MARK: - Galaxy Autobuyer Card

private struct GalaxyAutobuyerCard: View {
    let info: GalaxyAutobuyerInfo
    let allOn: Bool
    let engine: GameEngine

    @State private var buyMaxText: String = ""
    @FocusState private var isEditingBuyMax: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Antimatter Galaxy Autobuyer")
                        .font(.subheadline.weight(.medium))
                    if info.isBuyMaxUnlocked {
                        Text("Buys max every interval")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Current interval: \(intervalText(info.interval))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !info.isBuyMaxUnlocked {
                    IntervalUpgradeRow(
                        interval: info.interval, bulk: nil, cost: info.cost,
                        canUpgrade: info.canUpgrade, canBeUpgraded: true,
                        hasMaxedInterval: info.hasMaxedInterval,
                        onUpgrade: { engine.upgradeGalaxyAutobuyer() }
                    )
                }

                Spacer()

                Toggle("", isOn: Binding(get: { info.isActive }, set: { _ in
                    engine.toggleGalaxyAutobuyer()
                }))
                .labelsHidden()
                .controlSize(.small)
                .pausedAwareTint(isActive: info.isActive)
            }

            Divider().opacity(0.3)

            if info.isBuyMaxUnlocked {
                HStack(spacing: 8) {
                    Text("Activates every")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    TextField("seconds", text: $buyMaxText)
                        .font(.caption.monospacedDigit())
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .focused($isEditingBuyMax)
                        .onSubmit { commitBuyMax() }
                        .onAppear { buyMaxText = info.buyMaxInterval }
                        .onChange(of: info.buyMaxInterval) { _, newVal in
                            if !isEditingBuyMax { buyMaxText = newVal }
                        }
                        .onChange(of: isEditingBuyMax) { _, editing in
                            if !editing { commitBuyMax() }
                        }
                        .onDisappear { commitBuyMax() }
                        .detectsNiceEasterEgg(buyMaxText, engine: engine)
                    Text("seconds")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            LimitSettingRow(
                label: "Limit galaxies to:",
                isEnabled: info.limitGalaxies,
                value: info.maxGalaxies,
                onToggle: { newVal in engine.setGalaxyLimit(enabled: newVal, max: info.maxGalaxies) },
                onChange: { newVal in engine.setGalaxyLimit(enabled: info.limitGalaxies, max: newVal) }
            )
        }
        .modifier(AutobuyerCardBackground())
    }

    private func commitBuyMax() {
        let trimmed = buyMaxText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        engine.setGalaxyBuyMaxInterval(trimmed)
        isEditingBuyMax = false
    }
}

// MARK: - Big Crunch Autobuyer Card

// MARK: - Replicanti Upgrade Autobuyers Card (grouped, matching web MultipleAutobuyersBox)

private struct ReplicantiUpgradeAutobuyersCard: View {
    let info: ReplicantiUpgradeAutobuyersInfo
    let engine: GameEngine

    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        Group {
            if metrics.isCompact {
                compactLayout
            } else {
                regularLayout
            }
        }
        .padding(12)
        .background(GameColor.sidebarBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(cardBorderColor.opacity(0.4), lineWidth: 1)
        )
    }

    private var compactLayout: some View {
        VStack(spacing: 8) {
            VStack(spacing: 4) {
                Text("Replicanti Upgrade Autobuyers")
                    .font(.caption.weight(.medium))
                    .multilineTextAlignment(.center)
                Text(info.intervalText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            tiles
        }
    }

    private var regularLayout: some View {
        HStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("Replicanti Upgrade\nAutobuyers")
                    .font(.caption.weight(.medium))
                    .multilineTextAlignment(.center)
                Text(info.intervalText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 180)

            tiles
        }
    }

    private var tiles: some View {
        HStack(spacing: 6) {
            ForEach(info.entries) { entry in
                VStack(spacing: 6) {
                    Toggle("", isOn: Binding(
                        get: { entry.isActive },
                        set: { _ in engine.toggleReplicantiUpgradeAutobuyer(entry.id) }
                    ))
                    .labelsHidden()
                    .scaleEffect(0.65)
                    .frame(height: 24)
                    .pausedAwareTint(isActive: entry.isActive)

                    Text(entry.name)
                        .font(.caption2.weight(.medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity)
                .background(GameColor.sidebarBackground, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(cardBorderColor.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }
}

// MARK: - Single Autobuyers Row (horizontal grid matching web)

private struct SingleAutobuyersRow: View {
    let state: AutobuyersState
    let engine: GameEngine

    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        let cards = buildCards()
        if !cards.isEmpty {
            if metrics.isCompact {
                // Non-lazy 2-column layout (chunked HStacks), NOT LazyVGrid: a lazy
                // grid inside the ScrollView recycles/destroys the cell whose tile is
                // presenting the multiplier-entry alert the moment the keyboard slides
                // up and reflows the layout — tearing down the tile's @State and
                // dismissing the alert (keyboard pops up then instantly disappears).
                // A non-lazy container keeps every tile alive, so the alert survives.
                let rows = stride(from: 0, to: cards.count, by: 2).map {
                    Array(cards[$0 ..< min($0 + 2, cards.count)])
                }
                VStack(spacing: 8) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 8) {
                            ForEach(row) { card in
                                SimpleAutobuyerTile(card: card, engine: engine)
                                    .equatable()
                                    .frame(maxWidth: .infinity)
                            }
                            // Keep a lone trailing tile at half-width (matches the grid).
                            if row.count == 1 {
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ForEach(cards) { card in
                        SimpleAutobuyerTile(card: card, engine: engine)
                            .equatable()
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func buildCards() -> [SimpleAutobuyerCard] {
        var cards: [SimpleAutobuyerCard] = []
        if state.sacrifice.isUnlocked {
            cards.append(SimpleAutobuyerCard(
                id: "sacrifice",
                name: metrics.isCompact ? "Sacrifice" : "Dimensional Sacrifice",
                isActive: state.sacrifice.isActive,
                intervalText: "Current interval: Instant",
                extraText: state.sacrifice.isAutomatic ? "Automatic (Achievement 118)" : nil,
                hasInput: !state.sacrifice.isAutomatic,
                inputLabel: "Multiplier:",
                inputValue: state.sacrifice.multiplier,
                onToggle: { engine.toggleAutobuyer("sacrifice") },
                onInput: { engine.setSacrificeMultiplier(parseDecimalInput($0)) }
            ))
        }
        if state.replicantiGalaxy.isUnlocked {
            cards.append(SimpleAutobuyerCard(
                id: "replicantiGalaxy",
                name: "Replicanti Galaxy",
                isActive: state.replicantiGalaxy.isActive,
                intervalText: "Current interval: Instant",
                extraText: "Current bulk: \u{00d7}1",
                onToggle: { engine.toggleReplicantiGalaxyAutobuyer() }
            ))
        }
        if state.timeTheorem.isUnlocked {
            cards.append(SimpleAutobuyerCard(
                id: "timeTheorem",
                name: "Time Theorem",
                isActive: state.timeTheorem.isActive,
                intervalText: "Current interval: Instant",
                onToggle: { engine.toggleTTAutobuyer() }
            ))
        }
        if state.ipMult.isUnlocked {
            cards.append(SimpleAutobuyerCard(
                id: "ipMult",
                name: metrics.isCompact ? "IP Multiplier" : "Infinity Point Multiplier",
                isActive: state.ipMult.isActive,
                intervalText: "Current interval: Instant",
                onToggle: { engine.toggleIPMultAutobuyer() }
            ))
        }
        if state.epMult.isUnlocked {
            cards.append(SimpleAutobuyerCard(
                id: "epMult",
                name: metrics.isCompact ? "EP Multiplier" : "Eternity Point Multiplier",
                isActive: state.epMult.isActive,
                intervalText: "Current interval: Instant",
                onToggle: { engine.toggleEPMultAutobuyer() }
            ))
        }
        // Lai'tela single-autobuyers — matches web `MultipleSingleAutobuyersGroup.vue`
        // which appends Autobuyer.darkMatterDims/.darkMatterDimsAscension/
        // .singularity/.annihilation to the "single" row once their gating
        // SingularityMilestones unlock.
        if engine.laiAutoDimUnlocked {
            cards.append(SimpleAutobuyerCard(
                id: "darkMatterDims",
                name: metrics.isCompact ? "Dark Matter Dims" : "Dark Matter Dimensions",
                isActive: engine.laiAutoDimActive,
                intervalText: "Current interval: Instant",
                onToggle: { engine.laitelaToggleAutobuyer("dimension", active: !engine.laiAutoDimActive) }
            ))
        }
        if engine.laiAutoAscUnlocked {
            cards.append(SimpleAutobuyerCard(
                id: "darkMatterDimsAscension",
                name: metrics.isCompact ? "DMD Ascension" : "Dark Matter Dimension Ascension",
                isActive: engine.laiAutoAscActive,
                intervalText: "Current interval: Instant",
                onToggle: { engine.laitelaToggleAutobuyer("ascension", active: !engine.laiAutoAscActive) }
            ))
        }
        if engine.laiAutoSingUnlocked {
            cards.append(SimpleAutobuyerCard(
                id: "singularity",
                name: "Singularity",
                isActive: engine.laiAutoSingActive,
                intervalText: "Current interval: Instant",
                onToggle: { engine.laitelaToggleAutobuyer("singularity", active: !engine.laiAutoSingActive) }
            ))
        }
        if engine.laiAutoAnniUnlocked {
            // Read the always-on engine mirror, not gameState.celestials.laitela —
            // the latter is only refreshed on the Celestials tab and reads 0 here.
            let mult = engine.laiAutoAnniMultiplier
            cards.append(SimpleAutobuyerCard(
                id: "annihilation",
                name: "Annihilation",
                isActive: engine.laiAutoAnniActive,
                intervalText: "Current interval: Instant",
                hasInput: true,
                inputLabel: "Mult. gain ≥",
                inputValue: mult > 0 ? String(format: "%g", mult) : "",
                onToggle: { engine.laitelaToggleAutobuyer("annihilation", active: !engine.laiAutoAnniActive) },
                onInput: { raw in
                    let v = Double(raw.replacingOccurrences(of: ",", with: ".")) ?? 0
                    engine.laitelaSetAnnihilationMultiplier(v)
                }
            ))
        }
        return cards
    }
}

private struct SimpleAutobuyerCard: Identifiable {
    let id: String
    let name: String
    let isActive: Bool
    let intervalText: String
    var extraText: String? = nil
    var hasInput: Bool = false
    var inputLabel: String = ""
    var inputValue: String = ""
    let onToggle: () -> Void
    var onInput: ((String) -> Void)? = nil
}

private struct SimpleAutobuyerTile: View, Equatable {
    let card: SimpleAutobuyerCard
    let engine: GameEngine

    @Environment(\.layoutMetrics) private var metrics
    @State private var inputText: String = ""
    @State private var showInputAlert = false
    @FocusState private var isEditing: Bool

    // `SingleAutobuyersRow` rebuilds every tick (it reads `gameState.autobuyers`),
    // handing a fresh `SimpleAutobuyerCard` (new closures) each time. Without an
    // Equatable skip the tile's body re-evaluates at 30Hz and re-applies the
    // `.alert` modifier, which yanks first responder away from the alert's
    // TextField — the keyboard pops up and instantly dismisses. Compare only the
    // visible value fields (closures aren't Equatable and have no observable
    // change; `engine` is an app-lifetime singleton).
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.card.id == rhs.card.id
            && lhs.card.name == rhs.card.name
            && lhs.card.isActive == rhs.card.isActive
            && lhs.card.intervalText == rhs.card.intervalText
            && lhs.card.extraText == rhs.card.extraText
            && lhs.card.hasInput == rhs.card.hasInput
            && lhs.card.inputLabel == rhs.card.inputLabel
            && lhs.card.inputValue == rhs.card.inputValue
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                Text(card.name)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)

                Text(card.intervalText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let extra = card.extraText {
                    Text(extra)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if card.hasInput {
                    if metrics.isCompact {
                        // iPhone: inline TextField focus is unreliable inside SubtabPager
                        // (@FocusState doesn't engage inside the UIHostingController, so the
                        // keypad never appears and focus-loss commit never fires). Route entry
                        // through a window-level alert — UIAlertController presents outside the
                        // hosting controller and focuses reliably. Mirrors the Automator rename fix.
                        Button {
                            inputText = card.inputValue
                            showInputAlert = true
                        } label: {
                            HStack(spacing: 4) {
                                Text(card.inputLabel)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(card.inputValue.isEmpty ? String(localized: "Set…") : card.inputValue)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        HStack(spacing: 4) {
                            Text(card.inputLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            TextField("", text: $inputText)
                                .font(.caption.monospacedDigit())
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .focused($isEditing)
                                .onSubmit { commitInput() }
                                .onChange(of: isEditing) { _, editing in if !editing { commitInput() } }
                                .onAppear { inputText = card.inputValue }
                                .onChange(of: card.inputValue) { _, newVal in
                                    if !isEditing { inputText = newVal }
                                }
                                .detectsNiceEasterEgg(inputText, engine: engine)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 90, alignment: .center)
            .padding(.top, 20)
            .padding(.bottom, 12)
            .padding(.horizontal, 8)

            // Toggle in top-right corner
            Toggle("", isOn: Binding(
                get: { card.isActive },
                set: { _ in card.onToggle() }
            ))
            .labelsHidden()
            .scaleEffect(0.65)
            .padding(.top, 6)
            .padding(.trailing, 6)
            .pausedAwareTint(isActive: card.isActive)
        }
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .alert(card.name, isPresented: $showInputAlert) {
            TextField(card.inputLabel, text: $inputText)
                .keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) { }
            Button("Set") { commitAlertInput() }
        } message: {
            Text(card.inputLabel)
        }
    }

    /// Commit from the iPhone alert — the user explicitly tapped Set, so commit
    /// any non-empty value (no "unchanged" short-circuit needed).
    private func commitAlertInput() {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        card.onInput?(trimmed)
    }

    private func commitInput() {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // See PrestigeModeSelector.commitAmount — don't re-commit the formatted
        // display value (letter notation isn't round-trippable through parseDecimalInput).
        guard trimmed != card.inputValue.trimmingCharacters(in: .whitespaces) else { return }
        card.onInput?(trimmed)
        isEditing = false
    }
}

// MARK: - Prestige Mode Selector (shared by Eternity + Big Crunch autobuyers)

/// Reusable mode selector + amount input + dynamic toggle for prestige autobuyers.
private struct PrestigeModeSelector: View {
    let mode: Int
    let modeLabel: String
    let amount: String
    let isDynamic: Bool
    let hasAdditionalModes: Bool
    let accentColor: Color
    let unitLabel: String                // "EP" or "IP"
    let modeLabels: [String]             // e.g. ["Eternity at X EP", "Seconds between Eternities", ...]
    let fallbackLabel: String            // label when no additional modes
    let onSetMode: (Int) -> Void
    let onCommit: (String) -> Void
    let onToggleDynamic: () -> Void
    let engine: GameEngine

    @State private var amountText: String = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        HStack(spacing: 8) {
            if hasAdditionalModes {
                Menu {
                    ForEach(Array(modeLabels.enumerated()), id: \.offset) { idx, label in
                        Button(label) { onSetMode(idx) }
                    }
                } label: {
                    Text(modeLabel)
                        .font(.caption)
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
            } else {
                Text(fallbackLabel)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }

            TextField("Amount", text: $amountText)
                .font(.caption.monospacedDigit())
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
                .focused($isEditing)
                .onSubmit { commitAmount() }
                .onAppear { amountText = amount }
                .onChange(of: amount) { _, newVal in
                    if !isEditing { amountText = newVal }
                }
                .onChange(of: isEditing) { _, editing in
                    if !editing { commitAmount() }
                }
                .detectsNiceEasterEgg(amountText, engine: engine)
                .onDisappear { commitAmount() }

            if mode == 0 {
                Text(unitLabel)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                Button {
                    onToggleDynamic()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isDynamic ? "checkmark.square.fill" : "square")
                            .foregroundStyle(isDynamic ? accentColor : .white.opacity(0.5))
                        Text("Dynamic amount")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .buttonStyle(.plain)
            } else {
                Spacer()
            }
        }
    }

    private func commitAmount() {
        let trimmed = amountText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // Only commit genuine user edits. The poll writes the *formatted* value
        // back into the field (e.g. 1000 → "1.00a" under Letters notation), and
        // parseDecimalInput can't reverse letter notation — re-committing it would
        // parse "1.00a" as 1 and corrupt the threshold (e.g. on tab switch via
        // onDisappear). If the text still matches the formatted display value,
        // the engine already holds that value, so there is nothing to commit.
        guard trimmed != amount.trimmingCharacters(in: .whitespaces) else { return }
        onCommit(trimmed)
        isEditing = false
    }
}

// MARK: - Reality Autobuyer Card

/// Automatic Reality — mirrors web's `RealityAutobuyerBox.vue`. Six modes; up
/// to two threshold inputs (RM/time/shard + optional glyph level). Not built
/// on PrestigeModeSelector because Reality needs a second input.
private struct RealityAutobuyerCard: View {
    let info: RealityAutobuyerInfo
    let engine: GameEngine

    @State private var primaryDraft: String = ""
    @State private var glyphDraft: String = ""
    @FocusState private var isEditingPrimary: Bool
    @FocusState private var isEditingGlyph: Bool

    private var modeLabels: [String] {
        var labels = ["Reality Machines", "Glyph level", "RM or Level", "RM and Level", "Real-time (seconds)"]
        if info.hasRelicMode { labels.append("Relic Shards") }
        return labels
    }

    private var primaryValueText: String {
        switch info.mode {
        case 4: String(format: "%.1f", info.time)
        case 5: info.shard
        default: info.rm
        }
    }

    private var glyphExceedsCap: Bool {
        info.showsGlyphInput && info.glyph > info.glyphLevelCap
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Automatic Reality")
                    .font(.subheadline.weight(.medium))

                Spacer()

                Toggle("", isOn: Binding(get: { info.isActive }, set: { _ in
                    engine.toggleRealityAutobuyer()
                }))
                .labelsHidden()
                .controlSize(.small)
                .pausedAwareTint(isActive: info.isActive)
            }

            Divider().opacity(0.3)

            // Mode menu
            HStack(spacing: 8) {
                Text("Trigger")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(Array(modeLabels.enumerated()), id: \.offset) { idx, label in
                        Button(label) { engine.setRealityAutobuyerMode(idx) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(info.modeLabel)
                            .font(.caption.weight(.medium))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                    .foregroundStyle(GameColor.reality)
                }
            }

            // Primary threshold input
            VStack(alignment: .leading, spacing: 4) {
                Text(info.primaryInputLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("", text: $primaryDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospacedDigit())
                    .keyboardType(.numbersAndPunctuation)
                    .submitLabel(.done)
                    .focused($isEditingPrimary)
                    .onAppear { primaryDraft = primaryValueText }
                    .onChange(of: primaryValueText) { _, newValue in
                        if !isEditingPrimary { primaryDraft = newValue }
                    }
                    .onSubmit { commitPrimary() }
                    .onChange(of: isEditingPrimary) { _, editing in
                        if !editing { commitPrimary() }
                    }
                    .onDisappear { commitPrimary() }
                    .detectsNiceEasterEgg(primaryDraft, engine: engine)
            }

            // Optional glyph-level input (modes 1/2/3)
            if info.showsGlyphInput {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Target Glyph level")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("", text: $glyphDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption.monospacedDigit())
                        .keyboardType(.numberPad)
                        .submitLabel(.done)
                        .focused($isEditingGlyph)
                        .onAppear { glyphDraft = String(info.glyph) }
                        .onChange(of: info.glyph) { _, newValue in
                            if !isEditingGlyph { glyphDraft = String(newValue) }
                        }
                        .onSubmit { commitGlyph() }
                        .onChange(of: isEditingGlyph) { _, editing in
                            if !editing { commitGlyph() }
                        }
                        .onDisappear { commitGlyph() }
                        .detectsNiceEasterEgg(glyphDraft, engine: engine)

                    if glyphExceedsCap {
                        Text("Target exceeds current level cap of \(info.glyphLevelCap)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .modifier(AutobuyerCardBackground())
    }

    private func commitPrimary() {
        let trimmed = primaryDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // See PrestigeModeSelector.commitAmount — skip re-committing the formatted
        // display value, which letter notation makes non-round-trippable.
        guard trimmed != primaryValueText.trimmingCharacters(in: .whitespaces) else { return }
        let parsed = parseDecimalInput(trimmed)
        switch info.mode {
        case 4:
            engine.setRealityAutobuyerTime(Double(parsed) ?? 0)
        case 5:
            engine.setRealityAutobuyerShard(parsed)
        default:
            engine.setRealityAutobuyerRM(parsed)
        }
    }

    private func commitGlyph() {
        if let value = Int(glyphDraft.trimmingCharacters(in: .whitespaces)) {
            engine.setRealityAutobuyerGlyph(max(0, value))
        }
    }
}

// MARK: - Eternity Autobuyer Card

private struct EternityAutobuyerCard: View {
    let info: EternityAutobuyerInfo
    let engine: GameEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Automatic Eternity")
                    .font(.subheadline.weight(.medium))

                Spacer()

                Toggle("", isOn: Binding(get: { info.isActive }, set: { _ in
                    engine.toggleEternityAutobuyer()
                }))
                .labelsHidden()
                .controlSize(.small)
                .pausedAwareTint(isActive: info.isActive)
            }

            Divider().opacity(0.3)

            PrestigeModeSelector(
                mode: info.mode,
                modeLabel: info.modeLabel,
                amount: info.amount,
                isDynamic: info.isDynamic,
                hasAdditionalModes: info.hasAdditionalModes,
                accentColor: GameColor.eternity,
                unitLabel: "EP",
                modeLabels: ["Eternity at X EP", "Seconds between Eternities", "X times highest EP"],
                fallbackLabel: info.modeLabel,
                onSetMode: { engine.setEternityAutobuyerMode($0) },
                onCommit: { text in
                    let parsed = parseDecimalInput(text)
                    switch info.mode {
                    case 0: engine.setEternityAutobuyerAmount(parsed)
                    case 1: engine.setEternityAutobuyerTime(Double(parsed) ?? 1)
                    case 2: engine.setEternityAutobuyerXHighest(parsed)
                    default: break
                    }
                },
                onToggleDynamic: { engine.toggleEternityAutobuyerDynamic() },
                engine: engine
            )
        }
        .modifier(AutobuyerCardBackground())
    }
}

// MARK: - Big Crunch Autobuyer Card

private struct BigCrunchAutobuyerCard: View {
    let info: BigCrunchAutobuyerInfo
    let allOn: Bool
    let engine: GameEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automatic Big Crunch")
                        .font(.subheadline.weight(.medium))
                    Text("Current interval: \(intervalText(info.interval))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                IntervalUpgradeRow(
                    interval: info.interval, bulk: nil, cost: info.cost,
                    canUpgrade: info.canUpgrade, canBeUpgraded: true,
                    hasMaxedInterval: info.hasMaxedInterval,
                    onUpgrade: { engine.upgradeBigCrunchAutobuyer() }
                )

                Spacer()

                Toggle("", isOn: Binding(get: { info.isActive }, set: { _ in
                    engine.toggleBigCrunchAutobuyer()
                }))
                .labelsHidden()
                .controlSize(.small)
                .pausedAwareTint(isActive: info.isActive)
            }

            if info.hasMaxedInterval {
                Divider().opacity(0.3)

                PrestigeModeSelector(
                    mode: info.mode,
                    modeLabel: info.modeLabel,
                    amount: info.currentModeAmount,
                    isDynamic: info.isDynamic,
                    hasAdditionalModes: info.hasAdditionalModes,
                    accentColor: GameColor.infinity,
                    unitLabel: "IP",
                    modeLabels: ["Big Crunch at X IP", "Seconds between Crunches", "X times highest IP"],
                    fallbackLabel: "Big Crunch at",
                    onSetMode: { engine.setBigCrunchMode($0) },
                    onCommit: { text in
                        let parsed = parseDecimalInput(text)
                        switch info.mode {
                        case 1: engine.setBigCrunchTime(parsed)
                        case 2: engine.setBigCrunchXHighest(parsed)
                        default: engine.setBigCrunchAmount(parsed)
                        }
                    },
                    onToggleDynamic: { engine.toggleBigCrunchDynamic() },
                    engine: engine
                )
            }
        }
        .modifier(AutobuyerCardBackground())
    }
}

// MARK: - Limit Setting Row (Toggle + Stepper)

/// Reusable row for "Limit X to: [stepper]" controls in autobuyer cards.
/// Owns local @State for the stepper value, synced from the model via .onChange.
private struct LimitSettingRow: View {
    let label: String
    let isEnabled: Bool
    let value: Int
    let onToggle: (Bool) -> Void
    let onChange: (Int) -> Void

    @State private var localValue: Int

    init(label: String, isEnabled: Bool, value: Int, onToggle: @escaping (Bool) -> Void, onChange: @escaping (Int) -> Void) {
        self.label = label
        self.isEnabled = isEnabled
        self.value = value
        self.onToggle = onToggle
        self.onChange = onChange
        self._localValue = State(initialValue: value)
    }

    var body: some View {
        HStack(spacing: 8) {
            Toggle(label, isOn: Binding(
                get: { isEnabled },
                set: { onToggle($0) }
            ))
            .font(.caption)

            Stepper(value: $localValue, in: 0...9999) {
                Text("\(localValue)")
                    .font(.caption.monospaced())
                    .frame(minWidth: 30, alignment: .trailing)
            }
            .controlSize(.small)
            .onChange(of: localValue) { _, newVal in
                onChange(newVal)
            }
        }
        .onChange(of: value) { _, newVal in localValue = newVal }
    }
}

