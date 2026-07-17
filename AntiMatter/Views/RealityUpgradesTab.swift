//
//  RealityUpgradesTab.swift
//  AntiMatter
//
//  Reality Upgrades — 25 upgrades in a 5×5 grid.
//  Row 1 (IDs 1-5): rebuyable amplifiers.
//  Rows 2-5 (IDs 6-25): single-purchase upgrades with requirements.
//  Colors from web t-dark .c-reality-upgrade-btn CSS classes.
//

import SwiftUI

struct RealityUpgradesTab: View {
    let engine: GameEngine

    /// Toggles card display: false = normal (unlocked→effect, locked→requirement),
    /// true = swapped (unlocked→requirement, locked→effect). Mirrors web Shift key.
    @State private var showAlternate = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                RealityUpgradesCurrencyHeader(engine: engine)
                RealityUpgradesInfoText()
                RealityUpgradesToggleButton(showAlternate: $showAlternate)
                RealityUpgradesGrid(engine: engine, showAlternate: showAlternate)

                PhoneTabBarSpacer()
            }
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Currency header

private struct RealityUpgradesCurrencyHeader: View {
    let engine: GameEngine

    var body: some View {
        Text("You have \(Text(engine.currentRM).foregroundStyle(GameColor.reality)) Reality Machines.")
            .foregroundStyle(.secondary)
            .font(.subheadline.monospacedDigit())
    }
}

// MARK: - Info text + toggle (static)

private struct RealityUpgradesInfoText: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("The first row of upgrades can be purchased endlessly for increasing costs and the rest are single-purchase.")
            Text("Single-purchase upgrades also have requirements which, once completed, permanently unlock the ability to purchase the upgrades at any point.")
            Text("Locked upgrades show their requirement by default; unlocked ones show their effect, current bonus, and cost. Use the toggle below to swap this behavior.")
            Text("Long-press upgrades with a lock icon to prevent failing their unlock condition this Reality.")
            Text("Every completed row of purchased upgrades increases your Glyph level by 1.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 12)
    }
}

private struct RealityUpgradesToggleButton: View {
    @Binding var showAlternate: Bool

    var body: some View {
        Button {
            showAlternate.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: showAlternate ? "eye.slash" : "eye")
                Text(showAlternate ? "Showing: Alternate" : "Showing: Default")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(GameColor.reality)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black)
            .roundedBorder(GameColor.reality, lineWidth: 1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Grid (compact + regular)

private struct RealityUpgradesGrid: View {
    let engine: GameEngine
    let showAlternate: Bool

    @Environment(\.layoutMetrics) private var metrics

    @State private var compactRowWidth: CGFloat = 0

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    /// Row labels matching web upgrade structure
    private static let rowLabels = [
        "Row 1 — Rebuyable",
        "Row 2",
        "Row 3",
        "Row 4",
        "Row 5"
    ]

    var body: some View {
        let upgrades = engine.gameState.realityUpgrades

        if metrics.isCompact {
            // 2 cards visible + ~28pt peek, padding 12 each side, spacing 8 between.
            let cardWidth = max(110, (compactRowWidth - 12 - 8 - 28 - 12) / 2)
            VStack(spacing: 16) {
                ForEach(0..<5, id: \.self) { rowIdx in
                    let start = min(rowIdx * 5, upgrades.count)
                    let end = min(start + 5, upgrades.count)
                    let rowUpgrades = Array(upgrades[start..<end])
                    let allBought = rowUpgrades.allSatisfy { $0.isBought || ($0.isRebuyable && $0.boughtAmount > 0) }

                    VStack(alignment: .leading, spacing: 6) {
                        // Row header
                        HStack(spacing: 6) {
                            Text(Self.rowLabels[rowIdx])
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            if allBought {
                                Text("✓ Complete")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(GameColor.reality)
                            }
                        }
                        .padding(.leading, 12)

                        // Horizontal scroll of cards
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(rowUpgrades) { upgrade in
                                    Self.card(engine: engine, upgrade: upgrade, showAlternate: showAlternate)
                                        .frame(width: cardWidth)
                                }
                            }
                            .scrollTargetLayout()
                            .padding(.horizontal, 12)
                        }
                        .scrollTargetBehavior(.viewAligned)
                        .scrollEdgeFade()
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                compactRowWidth = newWidth
            }
        } else {
            // 5×5 grid (iPad)
            LazyVGrid(columns: Self.columns, spacing: 8) {
                ForEach(upgrades) { upgrade in
                    Self.card(engine: engine, upgrade: upgrade, showAlternate: showAlternate)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private static func card(engine: GameEngine, upgrade: RealityUpgradeInfo, showAlternate: Bool) -> RealityUpgradeCard {
        let disabledByPelle = engine.pelleDoomed && engine.pelleDisabledRUPGs.contains(upgrade.id)
        return RealityUpgradeCard(
            upgrade: upgrade,
            showAlternate: showAlternate,
            isDisabledByPelle: disabledByPelle,
            onBuy: { engine.buyRealityUpgrade(upgrade.id) },
            onToggleLock: { engine.toggleRealityUpgradeLock(upgrade.id) },
            onToggleAutobuyer: { on in engine.toggleRealityUpgradeAutobuyer(upgrade.id, on: on) },
            onDebugBuy: { engine.devCommand("RealityUpgrade(\(upgrade.id)).purchase()") },
            onDebugToggle: {
                if upgrade.isRebuyable { return }
                if upgrade.isBought {
                    // Clear the bit
                    engine.devCommand("player.reality.upgradeBits &= ~(1 << \(upgrade.id))")
                } else {
                    // Set the bit + unlock requirement + dispatch event so achievements check
                    engine.devCommand("player.reality.upgReqs |= (1 << \(upgrade.id)); player.reality.upgradeBits |= (1 << \(upgrade.id)); EventHub.dispatch(GAME_EVENT.REALITY_UPGRADE_BOUGHT)")
                }
            },
            onDebugUnlock: {
                engine.devCommand("player.reality.upgReqs |= (1 << \(upgrade.id))")
            }
        )
    }
}

// Reality Upgrade IDs nullified by Pelle's Doomed Reality are now sourced
// from `engine.pelleDisabledRUPGs` — populated once at startup from
// `Pelle.disabledRUPGs` (`pelle.js:197-199`) via `_nativePelleDisabledLists()`.

// MARK: - Reality Upgrade Card

private struct RealityUpgradeCard: View {
    let upgrade: RealityUpgradeInfo
    let showAlternate: Bool
    /// True when the upgrade has been bought but Pelle nullifies its effect.
    /// Renders a "Disabled by Pelle" overlay so the player understands why
    /// the upgrade's bonus isn't applying.
    var isDisabledByPelle: Bool = false
    let onBuy: () -> Void
    let onToggleLock: () -> Void
    let onToggleAutobuyer: (Bool) -> Void
    var onDebugBuy: () -> Void = {}
    var onDebugToggle: () -> Void = {}
    var onDebugUnlock: () -> Void = {}

    private static let boughtBorder = GameColor.boughtBorderGreen
    private static let unavailableBg = GameColor.unavailableBg
    private static let lockedBg = GameColor.lockedBgRed
    private static let possibleBg = GameColor.possibleBg

    private var isBoughtOrCapped: Bool {
        !upgrade.isRebuyable && upgrade.isBought
    }

    private var canInteract: Bool {
        if upgrade.isRebuyable { return upgrade.isAffordable }
        return !upgrade.isBought && upgrade.isAvailable && upgrade.isAffordable
    }

    /// Web logic: show requirement when (shiftDown == isAvailable) && !isRebuyable
    /// Normal: locked → requirement, unlocked → effect
    /// Alternate: locked → effect, unlocked → requirement
    private var showRequirement: Bool {
        guard !upgrade.isRebuyable else { return false }
        return showAlternate == upgrade.isAvailable
    }

    private var borderColor: Color {
        if isBoughtOrCapped { return Self.boughtBorder }
        return GameColor.reality
    }

    private var bgColor: Color {
        // Pelle nullifies the upgrade — Pelle red wins over the bought/locked
        // hierarchy so the player can spot the disabled cards at a glance.
        if isDisabledByPelle { return GameColor.lockedBgRed }
        if isBoughtOrCapped { return GameColor.reality }
        if !upgrade.isAvailable {
            return upgrade.isPossible ? Self.possibleBg : Self.lockedBg
        }
        if upgrade.isAffordable { return .black }
        return Self.unavailableBg
    }

    private var textColor: Color {
        if isDisabledByPelle { return GameColor.pelle.readableOnDark() }
        if isBoughtOrCapped { return .black }
        if !upgrade.isAvailable {
            return upgrade.isPossible ? .black : .white
        }
        return GameColor.reality
    }

    var body: some View {
        VStack(spacing: 4) {
            cardBody
            if upgrade.isRebuyable && upgrade.autobuyerAvailable {
                Toggle(isOn: Binding(
                    get: { upgrade.isAutobuyerOn },
                    set: { onToggleAutobuyer($0) }
                )) {
                    Text("Auto")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(GameColor.reality)
                }
                .toggleStyle(.switch)
                .labelsHidden()
                .scaleEffect(0.7)
                .frame(height: 20)
            }
        }
    }

    private var cardBody: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 3) {
                Text(upgrade.name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(textColor)
                    .strikethrough(isDisabledByPelle)

                Text(upgrade.description)
                    .font(.caption2)
                    .foregroundStyle(textColor.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .minimumScaleFactor(0.7)
                    .strikethrough(isDisabledByPelle)

                if showRequirement {
                    if !upgrade.requirementText.isEmpty {
                        Text("Requirement: \(upgrade.requirementText)")
                            .font(.caption2)
                            .foregroundStyle(textColor)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.7)
                            .strikethrough(isDisabledByPelle)
                    }
                } else {
                    if !upgrade.effectText.isEmpty {
                        Text("Currently: \(upgrade.effectText)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(isBoughtOrCapped ? .black.opacity(0.7) : textColor.opacity(0.75))
                            .strikethrough(isDisabledByPelle)
                    }
                    if !isBoughtOrCapped {
                        Text("Cost: \(upgrade.cost) RM")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(textColor.opacity(0.7))
                    }
                }

                if upgrade.isRebuyable && upgrade.boughtAmount > 0 {
                    Text("Bought: \(upgrade.boughtAmount)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(textColor.opacity(0.75))
                        .strikethrough(isDisabledByPelle)
                }
            }
            .frame(maxWidth: .infinity)

            // Lock icon — sits on the top-right corner of the card
            if upgrade.canLock || upgrade.hasLock {
                Image(systemName: upgrade.hasLock ? "lock.fill" : "lock.open")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(upgrade.hasLock ? .yellow : .white.opacity(0.6))
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.75))
                    )
                    .offset(x: 8, y: -8)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 110)
        .background(bgColor)
        .overlay(pelleDisabledOverlay)
        .roundedBorder(borderColor, lineWidth: 1.5)
        .contentShape(Rectangle())
        .onTapGesture {
            if canInteract {
                Haptics.tap()
                onBuy()
            }
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            if upgrade.canLock { onToggleLock() }
        }
        #if DEBUG
        .contextMenu {
            if upgrade.isRebuyable {
                Button {
                    onDebugBuy()
                } label: {
                    Label("Buy +1", systemImage: "plus.circle")
                }
            } else if upgrade.isBought {
                Button(role: .destructive) {
                    onDebugToggle()
                } label: {
                    Label("Unbuy Upgrade", systemImage: "xmark.circle")
                }
            } else {
                Button {
                    onDebugToggle()
                } label: {
                    Label("Force Buy", systemImage: "checkmark.circle")
                }
                if !upgrade.isAvailable {
                    Button {
                        onDebugUnlock()
                    } label: {
                        Label("Unlock Requirement", systemImage: "lock.open")
                    }
                }
            }
        }
        #endif
    }

    /// "♅ Disabled" badge tucked into the top-right corner of nullified
    /// cards. Cross-hatching was removed in favor of the red bg +
    /// strikethrough treatment which reads as "broken" without obscuring
    /// the description text.
    @ViewBuilder
    private var pelleDisabledOverlay: some View {
        if isDisabledByPelle {
            Text("♅")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(GameColor.pelle.readableOnDark())
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Color.black.opacity(0.7), in: Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(4)
                .allowsHitTesting(false)
        }
    }
}
