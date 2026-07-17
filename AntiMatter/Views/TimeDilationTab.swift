//
//  TimeDilationTab.swift
//  AntiMatter
//
//  Time Dilation — late-eternity mechanic with Tachyon Particles,
//  Dilated Time, Tachyon Galaxies, and dilation upgrades.
//

import SwiftUI

struct TimeDilationTab: View {
    let engine: GameEngine
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if engine.pelleDoomed {
                    PelleSimpleDisabledBanner(
                        text: "Pre-Doom Dilated Time and Tachyon Particle multipliers are disabled. Only the ×2 buyable upgrade still applies."
                    )
                }
                TimeDilationHeaderSection(engine: engine)
                TimeDilationButton(engine: engine)
                TimeDilationCurrencySection(engine: engine)
                TimeDilationGalaxySection(engine: engine)
                TimeDilationUpgradesSection(engine: engine)
                PhoneTabBarSpacer()
            }
            .padding(.vertical, 16)
            .padding(.horizontal, metrics.contentHPadding)
        }
    }
}

// MARK: - Header

private struct TimeDilationHeaderSection: View {
    let engine: GameEngine

    var body: some View {
        let dilation = engine.gameState.eternity.dilation
        VStack(spacing: 6) {
            Text("Time Dilation")
                .font(.title3.weight(.medium))

            Text("You have \(Text(dilation.tachyonParticles).foregroundStyle(GameColor.dilationGreen)) Tachyon Particles.")
                .foregroundStyle(.secondary)
                .font(.subheadline.monospacedDigit())
        }
    }
}

// MARK: - Dilation button

private struct TimeDilationButton: View {
    let engine: GameEngine

    var body: some View {
        let dilation = engine.gameState.eternity.dilation
        // Mirror `DilationButton.vue`:
        //   - Doomed + active     → "Dilation is permanent." (no longer "Disable Dilation.")
        //   - Doomed + inactive + !canDilateInPelle → "Dilate time. Requires X Remnants" (button is a no-op)
        //   - Otherwise           → original behavior.
        let doomed = engine.pelleDoomed
        let primaryLabel: String = {
            if dilation.isActive {
                return doomed ? "Dilation is permanent." : "Disable Dilation."
            }
            return "Dilate Time."
        }()
        let showRemnantRequirement = doomed && !dilation.isActive && !dilation.pelleCanDilate
        // The button's tap is a no-op when doomed and below the remnant
        // requirement; matches `startDilatedEternityRequest()`'s early-return.
        let canTapWhenInactive = !doomed || dilation.pelleCanDilate
        GameButton(
            borderColor: GameColor.dilationGreen,
            isEnabled: true
        ) {
            if !dilation.isActive && !canTapWhenInactive { return }
            engine.requestDilation()
        } label: {
            VStack(spacing: 4) {
                Text(primaryLabel)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(GameColor.dilationGreen)

                if showRemnantRequirement {
                    Text("Requires \(dilation.pelleRemnantRequirement) Remnants")
                        .font(.caption)
                        .foregroundStyle(GameColor.dilationGreen)
                } else {
                    Group {
                        if dilation.canEternity && dilation.hasGain {
                            Text("Gain \(dilation.tachyonGain) Tachyon Particles.")
                        } else if dilation.hasGain {
                            Text("Reach \(dilation.eternityGoal) Infinity Points to Eternity and gain Tachyon Particles.")
                        } else {
                            Text("Reach \(dilation.requiredForGain) antimatter to gain more Tachyon Particles.")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(GameColor.dilationGreen)
                    .opacity(dilation.isActive ? 1 : 0)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(minHeight: 60)
        }
    }
}

// MARK: - Currency display

private struct TimeDilationCurrencySection: View {
    let engine: GameEngine

    var body: some View {
        let dilation = engine.gameState.eternity.dilation
        VStack(spacing: 4) {
            Text("You have \(Text(dilation.dilatedTime).foregroundStyle(GameColor.eternity)) Dilated Time. \(Text("+\(dilation.dilatedTimePerSec)/s").foregroundStyle(GameColor.eternity))")
                .foregroundStyle(.secondary)
                .font(.subheadline.monospacedDigit())
        }
    }
}

// MARK: - Galaxy display

private struct TimeDilationGalaxySection: View {
    let engine: GameEngine

    var body: some View {
        let dilation = engine.gameState.eternity.dilation
        VStack(spacing: 4) {
            Text("Next Tachyon Galaxy at \(Text(dilation.nextGalaxyThreshold).foregroundStyle(GameColor.eternity)) Dilated Time")
                .foregroundStyle(.secondary)
                .font(.caption.monospacedDigit())

            Text("Total Tachyon Galaxies: \(dilation.tachyonGalaxies)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            if !dilation.galaxyTimeEstimate.isEmpty {
                Text("Estimated: \(dilation.galaxyTimeEstimate)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Upgrades

private struct TimeDilationUpgradesSection: View {
    let engine: GameEngine

    private static let upgradeColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        let dilation = engine.gameState.eternity.dilation
        let rebuyableUpgrades = dilation.upgrades.filter { $0.isRebuyable && !$0.pelleOnly }
        let singleUpgrades = dilation.upgrades.filter { !$0.isRebuyable && !$0.pelleOnly }
        let pelleRebuyables = dilation.upgrades.filter { $0.isRebuyable && $0.pelleOnly }
        let pelleSingles = dilation.upgrades.filter { !$0.isRebuyable && $0.pelleOnly }

        VStack(spacing: 12) {
            DilationRebuyableRow(engine: engine, items: rebuyableUpgrades)

            // Pelle-only rebuyables (paradox milestone)
            if !pelleRebuyables.isEmpty {
                DilationRebuyableRow(engine: engine, items: pelleRebuyables)
            }

            // Single-purchase upgrades (grid)
            LazyVGrid(columns: Self.upgradeColumns, spacing: 8) {
                ForEach(singleUpgrades) { upgrade in
                    DilationUpgradeCard(upgrade: upgrade, isPelleDoomed: engine.pelleDoomed) {
                        engine.buyDilationUpgrade(upgrade.id)
                    }
                }
            }

            // Pelle-only single-purchase upgrades (paradox milestone)
            if !pelleSingles.isEmpty {
                LazyVGrid(columns: Self.upgradeColumns, spacing: 8) {
                    ForEach(pelleSingles) { upgrade in
                        DilationUpgradeCard(upgrade: upgrade, isPelleDoomed: engine.pelleDoomed) {
                            engine.buyDilationUpgrade(upgrade.id)
                        }
                    }
                }
            }
        }
    }
}

private struct DilationRebuyableRow: View {
    let engine: GameEngine
    let items: [DilationUpgradeInfo]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items) { upgrade in
                VStack(spacing: 4) {
                    DilationUpgradeCard(upgrade: upgrade, isPelleDoomed: engine.pelleDoomed) {
                        engine.buyDilationUpgrade(upgrade.id)
                    }
                    // Auto toggle is gated on `Autobuyer.dilationUpgrade.isUnlocked`
                    // which already returns `false` under doom (per
                    // `dilation-upgrade-autobuyer.js` `isUnlocked` getter).
                    if upgrade.isAutoUnlocked {
                        Toggle(isOn: Binding(
                            get: { upgrade.isAutoActive },
                            set: { _ in engine.toggleDilationUpgradeAutobuyer(upgrade.id) }
                        )) {
                            Text("Auto:")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(GameColor.dilationGreen)
                        }
                        .toggleStyle(.switch)
                        .tint(GameColor.dilationGreen)
                    }
                }
            }
        }
    }
}

// MARK: - Dilation Upgrade Card

private struct DilationUpgradeCard: View {
    let upgrade: DilationUpgradeInfo
    var isPelleDoomed: Bool = false
    let onBuy: () -> Void

    private let dilationGreen = GameColor.dilationGreen
    private let dilationBorder = GameColor.dilationBorder
    private let unavailableBg = GameColor.dilationDisabledBg

    private var isComplete: Bool { upgrade.isBought || upgrade.isCapped }

    /// Web `DilationUpgradeButton.vue.isUseless` — ids 3 (`tachyonGain`) and
    /// 7 (`ipMultDT`) are permanently disabled in Doomed Reality. Web applies
    /// `o-pelle-disabled-pointer` (cursor not-allowed + pointer-events: none)
    /// + `o-pelle-disabled` (strikethrough) + `o-dilation-upgrade--useless`
    /// (Pelle-red bg). Replicate all three on iOS.
    private var isPelleUseless: Bool {
        isPelleDoomed && (upgrade.id == 3 || upgrade.id == 7)
    }

    private var borderColor: Color {
        if isPelleUseless { return .black }
        if isComplete { return .black }
        return dilationBorder
    }

    private var bgColor: Color {
        if isPelleUseless { return GameColor.lockedBgRed }
        if isComplete { return dilationGreen }
        if upgrade.isAffordable { return .black }
        return unavailableBg
    }

    private var textColor: Color {
        if isPelleUseless { return .black }
        if isComplete { return .black }
        if upgrade.isAffordable { return dilationGreen }
        return Color(white: 0.35)
    }

    var body: some View {
        Button {
            Haptics.tap()
            onBuy()
        } label: {
            VStack(spacing: 4) {
                Text(upgrade.description)
                    .font(.caption2)
                    .foregroundStyle(textColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(7)
                    .minimumScaleFactor(0.65)
                    .strikethrough(isPelleUseless)

                if !upgrade.effectText.isEmpty {
                    Text(upgrade.effectText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(isPelleUseless ? .black : (isComplete ? .black : dilationGreen))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .strikethrough(isPelleUseless)
                }

                if upgrade.isRebuyable && upgrade.boughtAmount > 0 {
                    Text("Bought: \(upgrade.boughtAmount)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(isComplete ? .black : .secondary)
                }

                if upgrade.isCapped {
                    Text("Capped")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.black)
                } else if !upgrade.isBought && !isPelleUseless {
                    Text("Cost: \(upgrade.cost) DT")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(4)
            // Bumped from 120/100 — long descriptions like "Time Dimensions are
            // affected by Replicanti multiplier ^0.10, reduced effect above
            // 1e9000" + the effect line + cost truncated at 100pt.
            .frame(maxWidth: .infinity, minHeight: upgrade.isRebuyable ? 145 : 130, maxHeight: upgrade.isRebuyable ? 145 : 130)
            .background(bgColor)
            .roundedBorder(borderColor, lineWidth: 1.5)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(
            !isPelleUseless &&
            (upgrade.isRebuyable ? (upgrade.isAffordable && !upgrade.isCapped) : (!upgrade.isBought && upgrade.isAffordable))
        )
    }
}
