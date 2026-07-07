//
//  PelleUpgradesPanel.swift
//  AntiMatter
//
//  Phase 4 of the Pelle port. The post-doom upgrades shop:
//    - 5 rebuyable upgrades (always 5 cards: AD mult, time-speed, glyph
//      levels, infinity conversion, galaxy power) with current effect,
//      next effect, cost, single-buy + buy-max.
//    - ~23 one-time upgrades (autobuyer packs, "keep X across Armageddon"
//      flags) sorted by ascending cost; bought entries hidden when the
//      "Show bought" toggle is off.
//
//  Mirrors:
//    src/components/tabs/celestial-pelle/PelleUpgradePanel.vue
//    src/components/tabs/celestial-pelle/PelleUpgrade.vue
//    src/core/secret-formula/celestials/pelle-upgrades.js
//

import SwiftUI

struct PelleUpgradesPanel: View {
    let engine: GameEngine
    @Environment(\.layoutMetrics) private var metrics

    private var pelle: PelleState { engine.gameState.celestials.pelle }

    private var oneTimeColumns: [GridItem] {
        // Two columns on iPhone, three on iPad. Matches the density of
        // existing upgrade grids (RealityUpgradesTab pattern).
        let count = metrics.isCompact ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !pelle.rebuyableUpgrades.isEmpty {
                rebuyablesSection
            }
            // Web `PelleUpgradePanel.vue:108-113` places the showBought toggle
            // between rebuyables and one-times as a full-width status button.
            // The label is declarative ("Showing bought upgrades" /
            // "Bought upgrades hidden") rather than imperative — taps invert
            // the state. Mirrors `Pelle.cel.showBought` directly.
            boughtToggleButton
            if !pelle.oneTimeUpgrades.isEmpty {
                oneTimesSection
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(GameColor.pelle.opacity(0.4), lineWidth: 1)
                )
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("Pelle Upgrades")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GameColor.pelle.readableOnDark())
            Spacer()
        }
    }

    // MARK: - Show / hide bought toggle

    /// Full-width status-style button between rebuyables and one-times.
    /// Matches web `PelleUpgradePanel.vue:108-113` placement + declarative
    /// labels. State is `pelle.showBought` (`Pelle.cel.showBought`); tap
    /// inverts via `engine.togglePelleShowBought()` which already exists.
    private var boughtToggleButton: some View {
        Button {
            engine.togglePelleShowBought()
        } label: {
            Text(pelle.showBought ? "Showing bought upgrades" : "Bought upgrades hidden")
                .font(.caption.weight(.semibold))
                .foregroundStyle(GameColor.pelle.readableOnDark())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(pelle.showBought
                              ? GameColor.pelle.opacity(0.25)
                              : Color.black.opacity(0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(GameColor.pelle, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rebuyables

    private var rebuyablesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rebuyables")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                ForEach(pelle.rebuyableUpgrades) { u in
                    PelleRebuyableCard(engine: engine, upgrade: u)
                        .equatable()
                }
            }
        }
    }

    // MARK: - One-time grid

    private var oneTimesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Permanent unlocks")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: oneTimeColumns, spacing: 8) {
                ForEach(pelle.oneTimeUpgrades) { u in
                    PelleOneTimeCard(engine: engine, upgrade: u)
                        .equatable()
                }
            }
        }
    }
}

// MARK: - Rebuyable card

private struct PelleRebuyableCard: View, Equatable {
    let engine: GameEngine
    let upgrade: PelleUpgradeInfo

    static func == (lhs: PelleRebuyableCard, rhs: PelleRebuyableCard) -> Bool {
        lhs.upgrade == rhs.upgrade
        // engine excluded (identity-stable). When the upgrade's costText /
        // timeToAffordText churn per tick the body re-evaluates as it
        // should; once bought-out / fully capped the inputs freeze and
        // body skips.
    }

    private var canBuy: Bool { !upgrade.isBought && upgrade.isAffordable }

    var body: some View {
        // Layout mirrors web `PelleUpgrade.vue` — one tap-target tile per
        // upgrade with the description as the primary visual element,
        // followed by the "Currently:" effect line, then either the cost
        // or (when not yet affordable) an ETA derived from the current
        // Reality Shards/sec rate. NO Buy Max — `RebuyablePelleUpgradeState`
        // has no buyMax method and no panel button on web; single-buy only.
        Button {
            guard canBuy else { return }
            Haptics.tap()
            engine.buyPelleUpgrade(upgrade.id)
        } label: {
            VStack(spacing: 6) {
                Text(upgrade.description)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    Text(upgrade.isBought ? "Capped:" : "Currently:")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(upgrade.effectText)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(GameColor.pelle.readableOnDark())
                    if !upgrade.nextEffectText.isEmpty {
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(upgrade.nextEffectText)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                }
                HStack(spacing: 6) {
                    Text("Cost:")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("\(upgrade.costText) Reality Shards")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(GameColor.pelle.readableOnDark())
                    Text("(\(upgrade.boughtAmount)/\(upgrade.maxAmount))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if !upgrade.timeToAffordText.isEmpty && !upgrade.isBought && !upgrade.isAffordable {
                    Text("ETA: \(upgrade.timeToAffordText)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .padding(.vertical, 12).padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(upgrade.isBought ? GameColor.pelle.opacity(0.22) : Color.black.opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(GameColor.pelle.opacity(upgrade.isBought ? 0.7 : 0.5), lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .allowsHitTesting(canBuy)
    }
}

// MARK: - One-time card

private struct PelleOneTimeCard: View, Equatable {
    let engine: GameEngine
    let upgrade: PelleUpgradeInfo

    static func == (lhs: PelleOneTimeCard, rhs: PelleOneTimeCard) -> Bool {
        lhs.upgrade == rhs.upgrade
        // engine excluded. Bought one-times freeze entirely — Equatable
        // skips the body forever once `isBought` flips. Unbought cards
        // re-eval per tick during active accumulation (ETA shifts).
    }

    private var bgColor: Color {
        if upgrade.isBought { return GameColor.pelle.opacity(0.25) }
        if !upgrade.isAvailable { return GameColor.lockedBgRed }
        if upgrade.isAffordable { return Color.black.opacity(0.4) }
        return GameColor.unavailableBg
    }

    private var borderColor: Color {
        if upgrade.isBought { return GameColor.boughtBorderGreen }
        if !upgrade.isAvailable { return GameColor.pelle.opacity(0.5) }
        return GameColor.pelle.opacity(0.4)
    }

    /// Description text color. Web keeps the description fully readable
    /// (`color: var(--color-text)`) regardless of state — locked cards use
    /// background tint, NOT illegible text. Match that: bright white for
    /// available/bought, slightly dimmed for unavailable.
    private var textColor: Color {
        if upgrade.isBought { return .white }
        if !upgrade.isAvailable { return .white.opacity(0.85) }
        return .white
    }

    var body: some View {
        Button {
            guard !upgrade.isBought, upgrade.isAffordable, upgrade.isAvailable else { return }
            Haptics.tap()
            engine.buyPelleUpgrade(upgrade.id)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(upgrade.description)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(textColor)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if !upgrade.timeToAffordText.isEmpty && !upgrade.isBought && upgrade.isAvailable {
                    Text("ETA: \(upgrade.timeToAffordText)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
                HStack {
                    Spacer()
                    Text(upgrade.costText)
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(upgrade.isBought
                            ? GameColor.good.readableOnDark()
                            : (upgrade.isAffordable ? GameColor.pelle.readableOnDark() : .white.opacity(0.85)))
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(bgColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(borderColor, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!upgrade.isBought && upgrade.isAffordable && upgrade.isAvailable)
    }
}
