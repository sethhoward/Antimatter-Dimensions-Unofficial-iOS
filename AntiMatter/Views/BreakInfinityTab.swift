//
//  BreakInfinityTab.swift
//  AntiMatter
//
//  Break Infinity tab — Break button + 4×3 upgrade grid.
//  Reuses InfinityUpgradeButton for consistent styling.
//

import SwiftUI

struct BreakInfinityTab: View {
    let engine: GameEngine
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                BreakInfinityHeader(engine: engine)
                BreakInfinityActionButton(engine: engine)
                BreakInfinityUpgradeGrid(engine: engine)
                PhoneTabBarSpacer()
            }
            .padding(.vertical, 16)
            .padding(.horizontal, metrics.contentHPadding)
        }
    }
}

// MARK: - Header

private struct BreakInfinityHeader: View {
    let engine: GameEngine

    var body: some View {
        VStack(spacing: 8) {
            Text("You have \(engine.gameState.infinity.currentIP) Infinity Points")
                .font(.title3.weight(.medium).monospacedDigit())
                .foregroundStyle(GameColor.infinity)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Break Button

private struct BreakInfinityActionButton: View {
    let engine: GameEngine

    var body: some View {
        let state = engine.gameState.breakInfinity
        Group {
            if engine.enslavedIsRunning {
                // Inside The Nameless Ones' Reality — the button swaps to
                // "FEEL ETERNITY" and routes to `Enslaved.feelEternity()`,
                // regardless of the normal hasMaxedInterval / isBroken gates
                // (web BreakInfinityButton.vue:37-40 does the same).
                Button {
                    engine.enslavedFeelEternity()
                } label: {
                    VStack(spacing: 4) {
                        Text("FEEL ETERNITY")
                            .font(.title2.weight(.black))
                            .foregroundStyle(.black)
                        Text("...eons stacked on eons...")
                            .font(.caption2)
                            .foregroundStyle(.black.opacity(0.75))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(GameColor.enslaved, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(GameColor.enslaved.opacity(0.8), lineWidth: 2)
                    )
                }
            } else if !state.hasMaxedInterval {
                // Locked — show requirement
                VStack(spacing: 8) {
                    Text("BREAK INFINITY")
                        .font(.title2.weight(.black))
                        .foregroundStyle(.gray)
                    Text("Reduce the interval of the Big Crunch Autobuyer to 0.1 seconds to unlock.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(GameColor.sidebarBackground, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1)
                )
            } else if !state.isBroken {
                // Available — can break
                Button {
                    engine.breakInfinity()
                } label: {
                    Text("BREAK INFINITY")
                        .font(.title2.weight(.black))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(GameColor.infinity, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(GameColor.infinity.opacity(0.8), lineWidth: 2)
                        )
                }
            } else {
                // Broken
                Text("INFINITY IS BROKEN")
                    .font(.title2.weight(.black))
                    .foregroundStyle(GameColor.infinity)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(GameColor.sidebarBackground, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(GameColor.infinity.opacity(0.5), lineWidth: 1)
                    )
            }
        }
    }
}

// MARK: - Upgrade Grid (3 columns × 4 rows)

private struct BreakInfinityUpgradeGrid: View {
    let engine: GameEngine

    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        let state = engine.gameState.breakInfinity
        if state.hasMaxedInterval {
            // Group upgrades into rows (0-3), sorted by column within each row
            let rows: [[InfinityUpgradeInfo]] = (0...3).map { row in
                state.upgrades.filter { $0.row == row }.sorted { $0.column < $1.column }
            }
            // Uniform tile height enforced via `fixedHeight` so all 12
            // cards read as the same size regardless of description
            // length, bought state, or rebuyable row variants. The
            // shared `InfinityUpgradeButton`'s `fixedSize(vertical:)`
            // is dropped when `fixedHeight` is set so
            // `minimumScaleFactor(0.6)` actually clamps long copy.
            let tileHeight: CGFloat = metrics.isCompact ? 130 : 90
            VStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(rows[row]) { upgrade in
                            InfinityUpgradeButton(
                                upgrade: upgrade,
                                column: 0,
                                accentOverride: GameColor.infinity,
                                isMultiplierRow: row == 3,
                                isPelleDoomed: engine.pelleDoomed,
                                fixedHeight: tileHeight
                            ) {
                                engine.buyBreakUpgrade(upgrade.id)
                            }
                            .equatable()
                        }
                    }
                }
            }
        }
    }
}
