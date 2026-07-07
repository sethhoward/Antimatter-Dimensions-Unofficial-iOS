//
//  EternityUpgradesTab.swift
//  AntiMatter
//
//  Eternity Upgrades — 6 one-time upgrades + repeatable EP multiplier.
//  Layout mirrors web EternityUpgradesTab.vue (2 rows of 3 + EP mult below).
//  Colors from t-dark .o-eternity-upgrade--* CSS classes.
//

import SwiftUI

struct EternityUpgradesTab: View {
    let engine: GameEngine

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if engine.pelleDoomed {
                    PelleSimpleDisabledBanner(
                        text: "Pre-Doom Eternity Upgrades and EP multipliers are disabled. Their effects do not apply while Doomed."
                    )
                    .padding(.horizontal, 12)
                }

                EternityUpgradesGrid(engine: engine)

                EternityEPMultSection(engine: engine)

                // Cost threshold info
                VStack(spacing: 4) {
                    Text("The cost for the \u{00d7}5 multiplier jumps at 1e100, 1.80e308, and 1e1300 Eternity Points.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("The cost increases super-exponentially after 1e4000 Eternity Points.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)

                PhoneTabBarSpacer()
            }
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Upgrade Grid (2 rows of 3)

private struct EternityUpgradesGrid: View {
    let engine: GameEngine
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        let upgrades = engine.gameState.eternity.upgrades
        let topRow = Array(upgrades.prefix(3))
        let bottomRow = Array(upgrades.dropFirst(3).prefix(3))
        VStack(spacing: metrics.isCompact ? 8 : 16) {
            EternityUpgradeRow(engine: engine, upgrades: topRow)
            EternityUpgradeRow(engine: engine, upgrades: bottomRow)
        }
    }
}

private struct EternityUpgradeRow: View {
    let engine: GameEngine
    let upgrades: [EternityUpgradeInfo]
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        HStack(spacing: metrics.isCompact ? 8 : 12) {
            ForEach(upgrades) { upgrade in
                EternityUpgradeCard(upgrade: upgrade) {
                    engine.buyEternityUpgrade(upgrade.id)
                }
                .equatable()
            }
        }
        .padding(.horizontal, metrics.contentHPadding)
    }
}

// MARK: - EP Multiplier section

private struct EternityEPMultSection: View {
    let engine: GameEngine

    var body: some View {
        let epMult = engine.gameState.eternity.epMult
        let doomed = engine.pelleDoomed
        VStack(spacing: 8) {
            EPMultiplyButton(engine: engine, epMult: epMult, doomed: doomed).equatable()
            EPMultBuyMaxButton(engine: engine, epMult: epMult, doomed: doomed).equatable()
            if epMult.isAutoUnlocked {
                EPMultAutobuyerToggleRow(engine: engine, isAutoActive: epMult.isAutoActive).equatable()
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - EP Multiplier subviews (Equatable on `EPMultState` slice)

private struct EPMultiplyButton: View, Equatable {
    let engine: GameEngine
    let epMult: EPMultState
    let doomed: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.epMult == rhs.epMult && lhs.doomed == rhs.doomed
    }

    var body: some View {
        Button {
            engine.buyEPMult()
        } label: {
            VStack(spacing: 4) {
                Text("Multiply Eternity Points from all sources by x5")
                    .font(.subheadline.weight(.medium))
                    .strikethrough(doomed)
                Text("Currently: \(epMult.currentMult)")
                    .font(.caption.monospacedDigit())
                    .strikethrough(doomed)
                if !epMult.isCapped {
                    Text("Cost: \(epMult.cost) EP")
                        .font(.caption.monospacedDigit())
                }
            }
            .foregroundStyle(doomed
                ? GameColor.pelle.readableOnDark()
                : (epMult.isAffordable ? GameColor.eternity : GameColor.unavailableText))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 400)
            .background(doomed
                ? GameColor.lockedBgRed
                : (epMult.isAffordable ? .black : GameColor.unavailableBg))
            .roundedBorder(doomed ? GameColor.pelle : GameColor.eternity, lineWidth: doomed ? 2 : 1.5)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!doomed && epMult.isAffordable && !epMult.isCapped)
    }
}

private struct EPMultBuyMaxButton: View, Equatable {
    let engine: GameEngine
    let epMult: EPMultState
    let doomed: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.epMult == rhs.epMult && lhs.doomed == rhs.doomed
    }

    var body: some View {
        Button {
            engine.buyMaxEPMult()
        } label: {
            Text("Max EP mult")
                .font(.caption.weight(.medium))
                .foregroundStyle(doomed
                    ? GameColor.pelle.readableOnDark()
                    : (epMult.isAffordable ? GameColor.eternity : GameColor.unavailableText))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: 400)
                .background(doomed
                    ? GameColor.lockedBgRed
                    : (epMult.isAffordable ? .black : GameColor.unavailableBg))
                .roundedBorder(doomed ? GameColor.pelle : GameColor.eternity, lineWidth: 1.5)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!doomed && epMult.isAffordable && !epMult.isCapped)
    }
}

private struct EPMultAutobuyerToggleRow: View, Equatable {
    let engine: GameEngine
    let isAutoActive: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isAutoActive == rhs.isAutoActive
    }

    var body: some View {
        Toggle(isOn: Binding(
            get: { isAutoActive },
            set: { _ in engine.toggleEPMultAutobuyer() }
        )) {
            Text("Autobuy EP mult")
                .font(.caption.weight(.medium))
                .foregroundStyle(GameColor.eternity)
        }
        .toggleStyle(.switch)
        .tint(GameColor.eternity)
        .frame(maxWidth: 400)
        .padding(.horizontal, 16)
    }
}

// MARK: - Individual upgrade card
// CSS: t-dark .o-eternity-upgrade
//   --available: color: eternity, bg: black, border: eternity
//   --unavailable: color: black, bg: #263238, border: #691fa5
//   --bought: color: white, bg: eternity, border: #691fa5

private struct EternityUpgradeCard: View, Equatable {
    let upgrade: EternityUpgradeInfo
    let onBuy: () -> Void

    @Environment(\.layoutMetrics) private var metrics

    /// Closure excluded; everything else compared via the `EternityUpgradeInfo`
    /// Equatable. Most fields (cost, description, isBought, isAffordable) are
    /// transition-only. `effectText` can be volatile for some EUs (e.g. the
    /// real-time-based TD multiplier) — same shape as `unspentIPMult` in the
    /// Infinity Upgrades grid; the card rebuilds on those ticks but the
    /// stable cards skip body.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.upgrade == rhs.upgrade
    }

    private static let unavailableBg = GameColor.unavailableBg
    private static let darkPurpleBorder = GameColor.darkPurpleBorder

    private var borderColor: Color {
        if upgrade.isBought { return .black }
        if upgrade.isAffordable { return GameColor.eternity }
        return Self.darkPurpleBorder
    }

    private var bgColor: Color {
        if upgrade.isBought { return GameColor.eternity }
        if upgrade.isAffordable { return .black }
        return Self.unavailableBg
    }

    private var textColor: Color {
        if upgrade.isBought { return .black }
        if upgrade.isAffordable { return GameColor.eternity }
        return GameColor.unavailableText
    }

    var body: some View {
        // Uniform tile height enforced via `frame(height:)` so all 6 cards
        // read as the same size regardless of description length, bought
        // state, or cost-line presence. Drops `fixedSize(vertical:)` on
        // description so `minimumScaleFactor` engages and long copy
        // scales to fit. Mirror of the pattern shipped for Break Infinity.
        let tileHeight: CGFloat = metrics.isCompact ? 140 : 110
        Button {
            Haptics.tap()
            onBuy()
        } label: {
            VStack(spacing: 4) {
                Text(upgrade.description)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(textColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(metrics.isCompact ? 6 : 4)
                    .minimumScaleFactor(0.6)

                Group {
                    // Two literal keys ("Capped: %@" / "Currently: %@") so the
                    // String Catalog extracts both, mirroring web `EffectDisplay.vue`.
                    if upgrade.isCapped {
                        Text("Capped: \(upgrade.effectText)")
                    } else {
                        Text("Currently: \(upgrade.effectText)")
                    }
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(upgrade.isBought ? .black.opacity(0.7) : textColor)
                .lineLimit(2)
                .minimumScaleFactor(0.6)

                if !upgrade.isBought {
                    Text("Cost: \(upgrade.cost) Eternity Points")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(textColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: tileHeight, maxHeight: tileHeight)
            .background(bgColor)
            .roundedBorder(borderColor, lineWidth: 1.5)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!upgrade.isBought && upgrade.isAffordable)
    }
}
