//
//  AutomatorTab.swift
//  AntiMatter
//
//  Automator tab — unlock progress screen (pre-100 AP) or full editor (post-unlock).
//  Unlock progress: three-column layout matching AutomatorPointsList.vue.
//  Editor: AutomatorEditorView with controls, text editor, script management.
//

import SwiftUI

struct AutomatorTab: View {
    let engine: GameEngine

    var body: some View {
        // Editor vs unlock-progress dispatch — `state.isUnlocked` flips once
        // per game (at 100 AP) so reading it here doesn't matter for tick
        // re-eval; once the editor unlocks, the parent body never re-runs.
        if engine.gameState.automatorState.isUnlocked {
            AutomatorEditorView(engine: engine)
        } else {
            ScrollView {
                AutomatorUnlockProgressList(engine: engine)
            }
        }
    }
}

// MARK: - Unlock Progress

private struct AutomatorUnlockProgressList: View {
    let engine: GameEngine

    var body: some View {
        let state = engine.gameState.automatorState
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Text("You have \(state.totalPoints) / \(state.pointsRequired) Automator Points towards unlocking the Automator.")
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)

                // Progress bar
                GeometryReader { geo in
                    let fraction = min(Double(state.totalPoints) / Double(max(state.pointsRequired, 1)), 1.0)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(white: 0.15))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(GameColor.reality)
                            .frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 8)
                .padding(.horizontal, 40)

                Text("You gain Automator Points from the following sources:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)

            // Three-column layout
            HStack(alignment: .top, spacing: 12) {
                // LEFT: Perks
                Self.sourceColumn(
                    title: "Perks",
                    icon: "point.3.connected.trianglepath.dotted",
                    totalAP: state.pointsFromPerks,
                    sources: state.perkSources,
                    showLabel: true
                )

                // CENTER: Other
                VStack(spacing: 12) {
                    ForEach(state.otherSources) { source in
                        Self.otherSourceCard(source)
                    }
                }
                .frame(maxWidth: .infinity)

                // RIGHT: Reality Upgrades
                Self.sourceColumn(
                    title: "Reality Upgrades",
                    icon: "arrow.up",
                    totalAP: state.pointsFromUpgrades,
                    sources: state.upgradeSources,
                    showLabel: false
                )
            }
            .padding(.horizontal, 12)

            // Footer
            VStack(spacing: 8) {
                Text("The Automator allows (amongst other things) buying full Time Study Trees, entering Eternity Challenges, or starting Dilation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("It can also force prestige events on certain conditions independently from your Autobuyers or modify some of your Autobuyer settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("The speed of the Automator gradually increases as you get more Realities. If unlocked right now, it would run \(state.automatorSpeed) commands per real-time second.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            PhoneTabBarSpacer()
        }
        .padding(.top, 16)
    }

    // MARK: - Source Column (Perks / Upgrades)

    private static func sourceColumn(title: String, icon: String, totalAP: Int, sources: [AutomatorPointSource], showLabel: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.15))
                Spacer()
                Text("\(totalAP) AP")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Text(title)
                .font(.title3.weight(.medium))

            // Source entries
            ForEach(sources) { source in
                HStack(spacing: 4) {
                    if showLabel {
                        Text(source.name)
                            .font(.caption.weight(.bold).monospaced())
                            .frame(width: 40, alignment: .leading)
                            .lineLimit(1)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        if !showLabel {
                            Text(source.name)
                                .font(.caption.weight(.bold))
                        }
                        Text(source.description)
                            .font(.caption2)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 4)

                    Text("\(source.points) AP")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .foregroundStyle(source.isBought ? .green : GameColor.badPink)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Other Source Card (Reality Count, Black Hole)

    private static func otherSourceCard(_ source: AutomatorPointSource) -> some View {
        VStack(spacing: 6) {
            HStack {
                Spacer()
                Text("\(source.points) AP")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Text(source.name)
                .font(.title3.weight(.medium))

            Text(source.description)
                .font(.caption)
                .foregroundStyle(source.isBought ? .green : GameColor.badPink)
                .multilineTextAlignment(.center)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
