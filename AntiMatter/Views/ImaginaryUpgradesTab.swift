//
//  ImaginaryUpgradesTab.swift
//  AntiMatter
//
//  Imaginary Upgrades — 25 upgrades in a 5×5 grid.
//  Rows 1-2 (IDs 1-10): rebuyable amplifiers (Autobuyer unlocks at ImaginaryUpgrade(20)).
//  Rows 3-5 (IDs 11-25): single-purchase upgrades with requirements.
//  Visual language matches RealityUpgradesTab (same color palette + card states).
//

import SwiftUI

struct ImaginaryUpgradesTab: View {
    let engine: GameEngine

    @State private var showAlternate = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if engine.pelleDoomed {
                    PelleSimpleDisabledBanner(
                        text: "Imaginary Upgrades are disabled while Doomed (except those that unlock Dark Matter Dimensions and Celestials)."
                    )
                    .padding(.horizontal, 8)
                }
                ImaginaryUpgradesCapHeader(engine: engine)
                ImaginaryUpgradesInfoText(engine: engine)
                ImaginaryUpgradesToggleButton(showAlternate: $showAlternate)
                ImaginaryUpgradesGrid(engine: engine, showAlternate: showAlternate)

                PhoneTabBarSpacer()
            }
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Header

private struct ImaginaryUpgradesCapHeader: View {
    let engine: GameEngine

    var body: some View {
        let imState = engine.gameState.imaginaryUpgrades
        VStack(spacing: 4) {
            Text("You have \(Text(imState.iMAmount).foregroundStyle(GameColor.reality)) Imaginary Machines.")
                .foregroundStyle(.secondary)
                .font(.subheadline.monospacedDigit())
            Text("Your Machine cap is \(Text(imState.iMCapText).foregroundStyle(GameColor.reality)).")
                .foregroundStyle(.secondary)
                .font(.caption.monospacedDigit())
        }
    }
}

private struct ImaginaryUpgradesInfoText: View {
    let engine: GameEngine

    var body: some View {
        let imState = engine.gameState.imaginaryUpgrades
        VStack(spacing: 6) {
            Text("You have reached the limits of Reality and cannot hold more than \(imState.capRM) Reality Machines.")
            Text("Machines gained in excess of \(imState.baseRMCap) will raise the maximum amount of Imaginary Machines you can have.")
            Text("Imaginary Machines are gained passively over time up to the cap, but gain slows exponentially near the cap. Every \(imState.scaleTimeSeconds) seconds the gap between current iM and cap is halved.")
            Text("The first two rows can be purchased endlessly; the rest are one-time upgrades with requirements.")
            Text("Long-press an upgrade with a lock icon to prevent failing its unlock condition this Reality.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 12)
    }
}

private struct ImaginaryUpgradesToggleButton: View {
    @Binding var showAlternate: Bool

    var body: some View {
        Button {
            showAlternate.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: showAlternate ? "lock.fill" : "eye")
                Text(showAlternate ? "Shift mode: tap to toggle lock" : "Normal mode: tap to purchase")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(showAlternate ? .yellow : GameColor.reality)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black)
            .roundedBorder(showAlternate ? .yellow : GameColor.reality, lineWidth: 1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Grid (compact + regular)

private struct ImaginaryUpgradesGrid: View {
    let engine: GameEngine
    let showAlternate: Bool

    @Environment(\.layoutMetrics) private var metrics

    private static let rowLabels = [
        "Row 1 — Rebuyable",
        "Row 2 — Rebuyable",
        "Row 3",
        "Row 4",
        "Row 5"
    ]

    @State private var compactRowWidth: CGFloat = 0

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        let upgrades = engine.gameState.imaginaryUpgrades.upgrades

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
            LazyVGrid(columns: Self.columns, spacing: 8) {
                ForEach(upgrades) { upgrade in
                    Self.card(engine: engine, upgrade: upgrade, showAlternate: showAlternate)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private static func card(engine: GameEngine, upgrade: ImaginaryUpgradeInfo, showAlternate: Bool) -> ImaginaryUpgradeCard {
        ImaginaryUpgradeCard(
            upgrade: upgrade,
            showAlternate: showAlternate,
            onBuy: { engine.buyImaginaryUpgrade(upgrade.id) },
            onToggleLock: { engine.toggleImaginaryUpgradeLock(upgrade.id) },
            onToggleAutobuyer: { on in engine.toggleImaginaryUpgradeAutobuyer(upgrade.id, on: on) },
            onDebugBuy: { engine.devCommand("ImaginaryUpgrade(\(upgrade.id)).purchase()") },
            onDebugToggle: {
                if upgrade.isRebuyable { return }
                if upgrade.isBought {
                    engine.devCommand("player.reality.imaginaryUpgradeBits &= ~(1 << \(upgrade.id))")
                } else {
                    engine.devCommand("player.reality.imaginaryUpgReqs |= (1 << \(upgrade.id)); player.reality.imaginaryUpgradeBits |= (1 << \(upgrade.id)); EventHub.dispatch(GAME_EVENT.IMAGINARY_UPGRADE_BOUGHT)")
                }
            },
            onDebugUnlock: {
                engine.devCommand("player.reality.imaginaryUpgReqs |= (1 << \(upgrade.id))")
            }
        )
    }
}

// MARK: - Imaginary Upgrade Card

private struct ImaginaryUpgradeCard: View {
    let upgrade: ImaginaryUpgradeInfo
    let showAlternate: Bool
    let onBuy: () -> Void
    let onToggleLock: () -> Void
    let onToggleAutobuyer: (Bool) -> Void
    var onDebugBuy: () -> Void = {}
    var onDebugToggle: () -> Void = {}
    var onDebugUnlock: () -> Void = {}

    private var isBoughtOrCapped: Bool {
        !upgrade.isRebuyable && upgrade.isBought
    }

    private var canInteract: Bool {
        if upgrade.isRebuyable { return upgrade.isAffordable }
        return !upgrade.isBought && upgrade.isAvailable && upgrade.isAffordable
    }

    private var showRequirement: Bool {
        guard !upgrade.isRebuyable else { return false }
        return showAlternate == upgrade.isAvailable
    }

    private var borderColor: Color {
        if upgrade.isPelleDisabled { return GameColor.pelle }
        if isBoughtOrCapped { return GameColor.boughtBorderGreen }
        return GameColor.reality
    }

    private var bgColor: Color {
        // Pelle wins: nullified upgrades show red so they're distinguishable
        // from the regular bought/available/locked states. Mirrors web
        // `c-reality-upgrade-btn--useless`.
        if upgrade.isPelleDisabled { return GameColor.lockedBgRed }
        if isBoughtOrCapped { return GameColor.reality }
        if !upgrade.isAvailable {
            return upgrade.isPossible ? GameColor.possibleBg : GameColor.lockedBgRed
        }
        if upgrade.isAffordable { return .black }
        return GameColor.unavailableBg
    }

    private var textColor: Color {
        if upgrade.isPelleDisabled { return GameColor.pelle.readableOnDark() }
        if isBoughtOrCapped { return .black }
        if !upgrade.isAvailable {
            return upgrade.isPossible ? .black : .white
        }
        return GameColor.reality
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 3) {
                    Text(upgrade.name)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(textColor)
                        .strikethrough(upgrade.isPelleDisabled)

                    Text(upgrade.description)
                        .font(.caption2)
                        .foregroundStyle(textColor.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .minimumScaleFactor(0.7)
                        .strikethrough(upgrade.isPelleDisabled)

                    if showRequirement {
                        if !upgrade.requirementText.isEmpty {
                            Text("Requirement: \(upgrade.requirementText)")
                                .font(.caption2)
                                .foregroundStyle(textColor)
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.7)
                                .strikethrough(upgrade.isPelleDisabled)
                        }
                    } else {
                        if !upgrade.effectText.isEmpty {
                            Text("Currently: \(upgrade.effectText)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(isBoughtOrCapped ? .black.opacity(0.7) : textColor.opacity(0.75))
                                .strikethrough(upgrade.isPelleDisabled)
                        }
                        if !isBoughtOrCapped {
                            Text("Cost: \(upgrade.cost) iM")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(textColor.opacity(0.7))
                            if !upgrade.etaText.isEmpty {
                                Text(upgrade.etaText)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(textColor.opacity(0.6))
                            }
                        }
                    }

                    if upgrade.isRebuyable && upgrade.boughtAmount > 0 {
                        Text("Bought: \(upgrade.boughtAmount)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(textColor.opacity(0.75))
                            .strikethrough(upgrade.isPelleDisabled)
                    }
                }
                .frame(maxWidth: .infinity)

                if upgrade.canLock || upgrade.hasLock {
                    Image(systemName: upgrade.hasLock ? "lock.fill" : "lock.open")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(upgrade.hasLock ? .yellow : .white.opacity(0.6))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.black.opacity(0.75)))
                        .offset(x: 8, y: -8)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: 110)
            .background(bgColor)
            .roundedBorder(borderColor, lineWidth: 1.5)
            .contentShape(Rectangle())
            .onTapGesture {
                // In shift mode, tap toggles lock (if lockable); otherwise buy.
                if showAlternate, upgrade.canLock || upgrade.hasLock {
                    onToggleLock()
                } else if canInteract {
                    onBuy()
                }
            }
            #if DEBUG
            .contextMenu {
                if upgrade.isRebuyable {
                    Button { onDebugBuy() } label: { Label("Buy +1", systemImage: "plus.circle") }
                } else if upgrade.isBought {
                    Button(role: .destructive) { onDebugToggle() } label: {
                        Label("Unbuy Upgrade", systemImage: "xmark.circle")
                    }
                } else {
                    Button { onDebugToggle() } label: {
                        Label("Force Buy", systemImage: "checkmark.circle")
                    }
                    if !upgrade.isAvailable {
                        Button { onDebugUnlock() } label: {
                            Label("Unlock Requirement", systemImage: "lock.open")
                        }
                    }
                }
            }
            #endif

            if upgrade.isRebuyable && upgrade.autobuyerAvailable {
                Toggle(isOn: Binding(
                    get: { upgrade.isAutobuyerOn },
                    set: { onToggleAutobuyer($0) }
                )) {
                    Text("Auto")
                        .font(.caption2)
                        .foregroundStyle(GameColor.reality)
                }
                .toggleStyle(.switch)
                .labelsHidden()
                .scaleEffect(0.7)
                .frame(height: 20)
            }
        }
    }
}
