//
//  PelleGalaxyGeneratorPanel.swift
//  AntiMatter
//
//  Phase 5 of the Pelle port. The Galaxy Generator: a passive galaxy
//  source that spends 5 currencies (galaxies / antimatter / IP / EP) on
//  upgrades, with a phase-progression system that drains the cap-rift's
//  reduceTo to 0 to advance to the next phase (4 phases total).
//
//  Mirrors:
//    src/components/tabs/celestial-pelle/PelleGalaxyGeneratorPanel.vue
//    src/core/celestials/pelle/galaxy-generator.js
//    src/core/secret-formula/celestials/galaxy-generator.js
//

import SwiftUI

struct PelleGalaxyGeneratorPanel: View {
    let engine: GameEngine
    @Environment(\.layoutMetrics) private var metrics

    private var gg: PelleGalaxyGeneratorInfo {
        engine.gameState.celestials.pelle.galaxyGenerator
    }

    /// Crimson → cyan vertical gradient — web `linear-gradient(--color-pelle--secondary, --color-pelle--base)`
    /// reversed so cyan sits at the bottom (matches the screenshot direction).
    private var pelleGradient: LinearGradient {
        LinearGradient(
            colors: [GameColor.pelle, GameColor.pelleSecondary],
            startPoint: .top, endPoint: .bottom
        )
    }

    var body: some View {
        VStack(spacing: 14) {
            titleHeader
            if gg.isUnlocked {
                totalsLine
                generationBar
                upgradesGrid
            } else {
                unlockButton
            }
        }
        .padding(metrics.isCompact ? 12 : 16)
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

    // MARK: - Title (web-style centred header)

    private var titleHeader: some View {
        VStack(spacing: 2) {
            Text("Galaxy Generator")
                .font(.system(size: metrics.isCompact ? 22 : 32, weight: .bold, design: .monospaced))
                .foregroundStyle(GameColor.pelle.readableOnDark())
            if gg.isUnlocked {
                Text("Phase \(gg.phase + 1) of 4")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Unlock button (pre-click state)

    private var unlockButton: some View {
        GameButton(theme: .pelle, isEnabled: true) {
            engine.unlockGalaxyGenerator()
        } label: {
            Text("Unlock the Galaxy Generator")
                .font(.callout.weight(.bold))
                .multilineTextAlignment(.center)
                .padding(.vertical, 14)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Totals line ("You have a total of X Galaxies. +Y/s")

    private var totalsLine: some View {
        let bigSize: CGFloat = metrics.isCompact ? 22 : 28
        let smallSize: CGFloat = metrics.isCompact ? 13 : 16
        let big = Font.system(size: bigSize, weight: .bold, design: .monospaced)
        let small = Font.system(size: smallSize)
        let valueColor = GameColor.pelleSecondary
        let line = Text("\(Text("You have a total of ").font(small).foregroundStyle(.secondary))\(Text(gg.galaxiesText).font(big).foregroundStyle(valueColor))\(Text(" Galaxies.  ").font(small).foregroundStyle(.secondary))\(Text("+" + gg.gainPerSecText).font(big).foregroundStyle(valueColor))")
        return line
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Generation / sacrifice bar

    private var barLabel: String {
        if gg.isCapped {
            if gg.capRiftCycledName.isEmpty {
                return gg.sacrificeActive ? "Sacrificing…" : "Generation capped"
            }
            return gg.sacrificeActive
                ? "Getting rid of all that \(gg.capRiftCycledName)…"
                : "Sacrifice your \(gg.capRiftCycledName)"
        }
        return "\(gg.generatedGalaxiesText) / \(gg.capText) Galaxies generated"
    }

    private var generationBar: some View {
        let height: CGFloat = metrics.isCompact ? 70 : 100
        let canTapToSacrifice = gg.isCapped && !gg.sacrificeActive && !gg.capRiftCycledName.isEmpty
        return ZStack {
            // Fill (white→crimson vertical gradient, width-driven by barFraction).
            GeometryReader { geo in
                let w = max(0, min(1, gg.barFraction)) * geo.size.width
                LinearGradient(
                    colors: [Color.white.opacity(0.95), GameColor.pelle],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(width: w)
                .frame(maxHeight: .infinity, alignment: .leading)
                .animation(.linear(duration: 0.1), value: gg.barFraction)
            }
            // Centred label, plus a small subtitle when capped.
            VStack(spacing: 4) {
                if gg.isCapped {
                    Text(gg.sacrificeActive
                         ? "Draining the cap-rift…"
                         : "Generation capped — drain to advance phase")
                        .font(.system(size: metrics.isCompact ? 10 : 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                Text(barLabel)
                    .font(.system(size: metrics.isCompact ? 14 : 20,
                                  weight: .semibold,
                                  design: .monospaced))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                if gg.sacrificeActive && !gg.sacrificeProgressText.isEmpty {
                    Text("Drained: \(gg.sacrificeProgressText)" +
                         (gg.phaseCompletionText.isEmpty ? "" : "  •  \(gg.phaseCompletionText)"))
                        .font(.system(size: metrics.isCompact ? 9 : 11).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                } else if !gg.timeToCapText.isEmpty && !gg.isCapped {
                    Text("Cap in \(gg.timeToCapText)")
                        .font(.system(size: metrics.isCompact ? 9 : 11).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 14)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(GameColor.pelleBarBg)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(GameColor.pelle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture {
            if canTapToSacrifice {
                Haptics.tap()
                engine.startGalaxyGenSacrifice()
            }
        }
        .allowsHitTesting(canTapToSacrifice)
    }

    // MARK: - Upgrades grid (5 cards in an adaptive row)

    private var upgradesGrid: some View {
        let minWidth: CGFloat = metrics.isCompact ? 145 : 130
        let cols = [GridItem(.adaptive(minimum: minWidth), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(gg.upgrades) { u in
                PelleGalaxyGenUpgradeCard(
                    engine: engine,
                    upgrade: u,
                    isCompact: metrics.isCompact,
                    gradient: pelleGradient
                )
            }
        }
    }
}

// MARK: - Upgrade card

private struct PelleGalaxyGenUpgradeCard: View {
    let engine: GameEngine
    let upgrade: PelleGalaxyGeneratorUpgradeInfo
    let isCompact: Bool
    let gradient: LinearGradient

    var body: some View {
        Button {
            // Card is always-tappable (JS no-ops when unaffordable); gate the
            // haptic so unaffordable taps don't buzz.
            if upgrade.isAffordable { Haptics.tap() }
            engine.buyGalaxyGenUpgrade(upgrade.id)
        } label: {
            VStack(spacing: 4) {
                Text(upgrade.name)
                    .font(.system(size: isCompact ? 12 : 13, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if !upgrade.effectText.isEmpty {
                    HStack(spacing: 3) {
                        Text("Currently:")
                            .font(.system(size: isCompact ? 10 : 11))
                            .foregroundStyle(.white.opacity(0.85))
                        Text(upgrade.effectText)
                            .font(.system(size: isCompact ? 11 : 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white)
                        if !upgrade.nextEffectText.isEmpty {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.7))
                            Text(upgrade.nextEffectText)
                                .font(.system(size: isCompact ? 11 : 12, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Color.yellow)
                        }
                    }
                    .multilineTextAlignment(.center)
                }
                Text("Cost: \(upgrade.costText) \(upgrade.costCurrencyName)")
                    .font(.system(size: isCompact ? 10 : 11).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !upgrade.timeToAffordText.isEmpty {
                    Text(upgrade.timeToAffordText)
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .frame(minHeight: isCompact ? 96 : 110)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(upgrade.isAffordable
                          ? AnyShapeStyle(gradient)
                          : AnyShapeStyle(GameColor.unavailableBg))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(upgrade.isAffordable ? GameColor.pelleSecondary : GameColor.pelle.opacity(0.5),
                            lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        // Don't disable / hide unaffordable cards — JS purchase() no-ops when
        // the player can't afford. Keeping the button always-tappable avoids
        // a SwiftUI rendering issue where flipping `allowsHitTesting` after a
        // purchase coincided with the upgrade cards collapsing.
    }
}
