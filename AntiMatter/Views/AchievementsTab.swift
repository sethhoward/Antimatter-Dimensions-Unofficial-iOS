//
//  AchievementsTab.swift
//  AntiMatter
//
//  Achievement grid — 18 rows x 8 columns of achievement tiles
//  with artwork, ID numbers, star indicators, and header info.
//

import SwiftUI

struct AchievementsTab: View {
    let engine: GameEngine

    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                AchievementsHeaderSection(engine: engine)
                    .padding(.horizontal)
                AchievementsGridSection(engine: engine)
                    // No horizontal padding — grid spans edge-to-edge for
                    // the largest possible tile size on narrow screens.
            }
            .padding(.vertical)
            .padding(.bottom, metrics.isCompact ? 100 : 0)
        }
    }
}

// MARK: - Header

private struct AchievementsHeaderSection: View {
    let engine: GameEngine

    var body: some View {
        let state = engine.gameState
        let achievements = state.achievements
        let achievementPower = state.achievementPower
        let unlockedCount = achievements.filter(\.isUnlocked).count
        let timer = state.achievementTimer
        VStack(spacing: 8) {
            if engine.pelleDoomed {
                PelleSimpleDisabledBanner(
                    text: "The Achievement multiplier and most achievement rewards are disabled while Doomed."
                )
            }
            Text("Achievements: \(unlockedCount) / \(achievements.count)")
                .font(.title3.weight(.medium))

            Text("Achievements provide a multiplier to:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Mirrors web `NormalAchievementsTab.vue` `boostText` — the
            // Antimatter Dimensions line is always shown; Infinity / Time
            // are appended in-line as they unlock; Tachyon Particles, Black
            // Hole Power, and Time Theorem production are separate lines
            // gated on later milestones.
            VStack(spacing: 2) {
                Text("\(dimensionList(state)) Dimensions: \(achievementPower)")
                    .font(.subheadline.weight(.semibold))
                if state.achMultToTP, !state.achTPMultiplier.isEmpty {
                    Text("Tachyon Particles: \(state.achTPMultiplier)")
                        .font(.subheadline.weight(.semibold))
                }
                if state.achMultToBH {
                    Text("Black Hole Power: \(achievementPower)")
                        .font(.subheadline.weight(.semibold))
                }
                if state.achMultToTT {
                    Text("Time Theorem production: \(achievementPower)")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .multilineTextAlignment(.center)

            HStack(spacing: 4) {
                Text("Achievements with a")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                Text("icon also give an additional reward.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if timer.isVisible {
                AutoAchieveSection(timer: timer, engine: engine)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// "Antimatter" → "Antimatter and Infinity" → "Antimatter, Infinity, and Time".
    /// Mirrors `makeEnumeration` from web's `NormalAchievementsTab.vue`.
    private func dimensionList(_ state: GameState) -> String {
        var parts = ["Antimatter"]
        if state.achMultToIDS { parts.append("Infinity") }
        if state.achMultToTDS { parts.append("Time") }
        switch parts.count {
        case 1: return parts[0]
        case 2: return "\(parts[0]) and \(parts[1])"
        default:
            let head = parts.dropLast().joined(separator: ", ")
            return "\(head), and \(parts.last!)"
        }
    }
}

/// Auto-achieve toggle + countdown blurbs. Mirrors `NormalAchievementsTab.vue`
/// lines 139-176. Visible only post-Reality and while Perk 205 is unbought.
private struct AutoAchieveSection: View {
    let timer: AchievementTimerState
    let engine: GameEngine

    var body: some View {
        VStack(spacing: 6) {
            Toggle(isOn: Binding(
                get: { timer.isAutoActive },
                set: { engine.setAutoAchieve($0) }
            )) {
                Text("Auto Achievements")
                    .font(.subheadline.weight(.medium))
            }
            .toggleStyle(.switch)
            .tint(.green)
            .frame(maxWidth: 320)

            if timer.missingCount > 0 {
                if timer.nextSeconds > 0 {
                    Text(nextLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Automatically gain the next missing Achievement as soon as you enable Auto Achievements. (left-to-right, top-to-bottom)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if timer.totalSeconds > 0 {
                    Text(totalLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.top, 4)
    }

    private var nextLine: String {
        let suffix = timer.isAutoActive ? "" : " once Auto is turned on"
        return "Automatically gain the next missing Achievement in \(timer.nextCountdownText)\(suffix). (left-to-right, top-to-bottom)"
    }

    private var totalLine: String {
        let tail = timer.isAutoActive ? "stays enabled" : "is turned on"
        return "You will regain all remaining achievements after \(timer.totalCountdownText) if Auto Achievement \(tail)."
    }
}

// MARK: - Grid

private struct AchievementsGridSection: View {
    let engine: GameEngine

    var body: some View {
        let achievements = engine.gameState.achievements
        let rows = Dictionary(grouping: achievements, by: \.row)
            .sorted { $0.key < $1.key }
            .map { $0.value.sorted { $0.column < $1.column } }
        VStack(spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                let allUnlocked = !row.isEmpty && row.allSatisfy(\.isUnlocked)
                HStack(spacing: 4) {
                    ForEach(row) { achievement in
                        AchievementCell(achievement: achievement, engine: engine)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(2)
                .background(
                    // Mirrors web `.c-achievement-grid__row--completed` —
                    // solid dark green backdrop behind a fully-unlocked row.
                    RoundedRectangle(cornerRadius: 6)
                        .fill(allUnlocked ? GameColor.achievementRowCompleted : .clear)
                )
            }
        }
    }
}
