//
//  ReplicantiTab.swift
//  AntiMatter
//
//  Replicanti tab — unlock button, amount/multiplier display,
//  3 upgrade buttons (chance, interval, galaxies), gain text,
//  and galaxy button. Styled to match web Modern UI.
//

import SwiftUI

struct ReplicantiTab: View {
    let engine: GameEngine

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if engine.pelleDoomed {
                    PelleSimpleDisabledBanner(
                        text: "Pre-Doom Replicanti speed multipliers are disabled. Replicanti slows down dramatically above 1.80e308."
                    )
                }
                if engine.replicantiUnlocked {
                    ReplicantiDescriptionSection(engine: engine)
                    ReplicantiMaxAllButton(engine: engine)
                    ReplicantiUpgradeRow(engine: engine)
                    ReplicantiGalaxyCostInfo(engine: engine)
                    ReplicantiGainText(engine: engine)
                    ReplicantiGalaxySection(engine: engine)
                } else {
                    ReplicantiUnlockSection(engine: engine)
                }
                PhoneTabBarSpacer()
            }
            .padding()
        }
    }
}

// MARK: - Description (matches web c-replicanti-description)

private struct ReplicantiDescriptionSection: View {
    let engine: GameEngine

    var body: some View {
        let state = engine.gameState.replicanti
        VStack(spacing: 6) {
            // "You have {amount} Replicanti, translated to"
            Text("You have \(Text(state.amount).foregroundStyle(GameColor.replicanti)) Replicanti, translated to")
                .foregroundStyle(.white)
                .font(.subheadline.monospacedDigit())

            // "a {mult} multiplier on all Infinity Dimensions."
            Text("a \(Text(state.mult).foregroundStyle(GameColor.replicanti)) multiplier on all Infinity Dimensions.")
                .foregroundStyle(.white)
                .font(.subheadline.monospacedDigit())
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Unlock Section

private struct ReplicantiUnlockSection: View {
    let engine: GameEngine

    var body: some View {
        let state = engine.gameState.replicanti
        VStack(spacing: 16) {
            Text("Replicanti")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text("Unlock Replicanti to gain a multiplier on all Infinity Dimensions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            GameButton(borderColor: GameColor.goodDark, isEnabled: state.isUnlockAffordable) {
                engine.unlockReplicanti()
            } label: {
                VStack(spacing: 2) {
                    Text("Unlock Replicanti")
                        .font(.subheadline.weight(.semibold))
                    Text("Cost: \(state.unlockCost) IP")
                        .font(.caption)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - Max All button

private struct ReplicantiMaxAllButton: View {
    let engine: GameEngine

    var body: some View {
        let state = engine.gameState.replicanti
        let anyUpgradeBuyable = [state.chanceUpgrade, state.intervalUpgrade, state.galaxyUpgrade]
            .contains { $0.canBeBought && !$0.isCapped }
        GameButton(borderColor: GameColor.goodDark, isEnabled: anyUpgradeBuyable) {
            engine.maxAllReplicantiUpgrades()
        } label: {
            Text("Max All")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .onHoldRepeat { engine.maxAllReplicantiUpgrades() }
    }
}

// MARK: - Upgrade Row (3 buttons with auto toggles, web spoon-btn-group style)

private struct ReplicantiUpgradeRow: View {
    let engine: GameEngine

    var body: some View {
        let state = engine.gameState.replicanti
        HStack(alignment: .top, spacing: 6) {
            ReplicantiUpgradeButton(
                engine: engine,
                info: state.chanceUpgrade,
                autoUnlocked: state.chanceAutoUnlocked,
                autoActive: state.chanceAutoActive,
                isEC8Running: state.isEC8Running,
                autoId: 1,
                action: { engine.buyReplicantiUpgrade("chance") }
            )
            ReplicantiUpgradeButton(
                engine: engine,
                info: state.intervalUpgrade,
                autoUnlocked: state.intervalAutoUnlocked,
                autoActive: state.intervalAutoActive,
                isEC8Running: state.isEC8Running,
                autoId: 2,
                action: { engine.buyReplicantiUpgrade("interval") }
            )
            ReplicantiUpgradeButton(
                engine: engine,
                info: state.galaxyUpgrade,
                autoUnlocked: state.galaxiesAutoUnlocked,
                autoActive: state.galaxiesAutoActive,
                isEC8Running: state.isEC8Running,
                autoId: 3,
                action: { engine.buyReplicantiUpgrade("galaxies") }
            )
        }
    }
}

private struct ReplicantiUpgradeButton: View {
    let engine: GameEngine
    let info: ReplicantiUpgradeInfo
    let autoUnlocked: Bool
    let autoActive: Bool
    let isEC8Running: Bool
    let autoId: Int
    let action: () -> Void

    var body: some View {
        let canBuy = info.canBeBought && !info.isCapped
        let showAuto = autoUnlocked && !isEC8Running
        VStack(spacing: 0) {
            Button(action: action) {
                VStack(spacing: 3) {
                    Text(info.description)
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if info.isCapped {
                        Text("CAPPED")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    } else {
                        Text(info.costDescription)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 70)
                .padding(6)
                .background(
                    canBuy ? GameColor.sidebarBackground : GameColor.disabled,
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(canBuy ? GameColor.goodDark : GameColor.disabledBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .allowsHitTesting(canBuy)

            if showAuto {
                HStack(spacing: 6) {
                    Text("Auto")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white)
                    Toggle(isOn: Binding(
                        get: { autoActive },
                        set: { _ in engine.toggleReplicantiUpgradeAutobuyer(autoId) }
                    )) { EmptyView() }
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .scaleEffect(0.75)
                        .pausedAwareTint(isActive: autoActive)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: 28)
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Galaxy cost info text

private struct ReplicantiGalaxyCostInfo: View {
    let engine: GameEngine

    var body: some View {
        let state = engine.gameState.replicanti
        VStack(spacing: 2) {
            Text("The Max Replicanti Galaxy upgrade can be purchased endlessly, but costs increase")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("more rapidly above \(state.distantRG) Replicanti Galaxies and even more so above \(state.remoteRG) Replicanti Galaxies.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .allowsHitTesting(false)
    }
}

// MARK: - Gain text

private struct ReplicantiGainText: View {
    let engine: GameEngine

    var body: some View {
        let state = engine.gameState.replicanti
        VStack(spacing: 2) {
            if !state.remainingTimeText.isEmpty {
                Text(state.remainingTimeText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if !state.galaxyText.isEmpty {
                Text(state.galaxyText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Galaxy Section

private struct ReplicantiGalaxySection: View {
    let engine: GameEngine

    var body: some View {
        let state = engine.gameState.replicanti
        if state.canSeeGalaxyButton {
            VStack(spacing: 4) {
                GameButton(borderColor: GameColor.goodDark, isEnabled: state.canBuyGalaxy) {
                    engine.replicantiGalaxy()
                } label: {
                    VStack(spacing: 2) {
                        Text("\(state.galaxyResetText) for a Replicanti Galaxy")
                            .font(.subheadline.weight(.semibold))
                        Text("Currently: \(state.galaxiesBought)\(state.galaxiesExtra > 0 ? "+\(state.galaxiesExtra)" : "")")
                            .font(.caption.monospacedDigit())
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .onHoldRepeat(isEnabled: state.canBuyGalaxy) { engine.replicantiGalaxy() }

                if state.galaxyAutoUnlocked {
                    HStack(spacing: 6) {
                        Text("Auto Galaxy\(!state.galaxyAutoEnabled ? " (disabled)" : "")")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(state.galaxyAutoEnabled ? .white : .white.opacity(0.5))
                        Toggle(isOn: Binding(
                            get: { state.galaxyAutoActive },
                            set: { _ in engine.toggleReplicantiGalaxyAutobuyer() }
                        )) { EmptyView() }
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .scaleEffect(0.75)
                            .pausedAwareTint(isActive: state.galaxyAutoActive)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }
}
