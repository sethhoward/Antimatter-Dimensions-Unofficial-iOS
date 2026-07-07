//
//  StatisticsTab.swift
//  AntiMatter
//
//  Statistics > Statistics general subtab. Mirrors `StatisticsTab.vue` —
//  sentence-form copy ("You have made a total of X antimatter."), colored
//  section headers per the web --color-* CSS variables, gated paragraphs
//  for Infinity / Eternity / Reality / Doomed Reality.
//
//  The old key/value `StatRow` rendering + inline Speedrun section + Max
//  All button were dropped 2026-05 when the full Vue port landed. Speedrun
//  now lives in its own `.speedrunMilestones` subtab. Per-tick text reads
//  use plain SwiftUI `Text` — Statistics is a cold tab, and if profiling
//  later shows `ResolvedTextFilter` cost on this surface, escalate to
//  per-line Equatable view skips before CATextLayer.
//

import SwiftUI

struct StatisticsTab: View {
    let engine: GameEngine

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StatisticsGeneralSection(engine: engine)
                StatisticsMatterScaleSection(engine: engine)
                StatisticsNewsSection(engine: engine)

                if engine.gameState.statistics.infinityUnlocked {
                    StatisticsInfinitySection(engine: engine)
                }
                if engine.gameState.statistics.eternityUnlocked {
                    StatisticsEternitySection(engine: engine)
                }
                if engine.gameState.statistics.realityUnlocked {
                    StatisticsRealitySection(engine: engine)
                }
                if engine.gameState.statistics.isDoomed {
                    StatisticsDoomedSection(engine: engine)
                }
                PhoneTabBarSpacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}

// MARK: - General

private struct StatisticsGeneralSection: View {
    let engine: GameEngine

    var body: some View {
        let stats = engine.gameState.statistics
        let saveDate = Date(timeIntervalSince1970: stats.saveCreatedTime / 1000)
            .formatted(date: .abbreviated, time: .shortened)
        StatsSectionContainer(title: "General", color: .white) {
            StatsLine("You have made a total of \(stats.totalAntimatter) antimatter.")
            StatsLine("You have played for \(stats.realTimePlayed). (real time)")
            if let totalGameTime = stats.totalTimePlayedGameTime {
                StatsLine("Your existence has spanned \(totalGameTime) of time. (game time)")
            }
            StatsLine("Your save was created on \(saveDate) (\(stats.saveAge) ago).")

            if stats.fullGameCompletions > 0, let total = stats.fullTimePlayed {
                Text(verbatim: "")
                    .frame(height: 6)
                let times = stats.fullGameCompletions == 1 ? "time" : "times"
                StatsLine("You have completed the entire game \(stats.fullGameCompletions) \(times).")
                    .fontWeight(.semibold)
                StatsLine("You have played for \(total) across all playthroughs.")
                    .fontWeight(.semibold)
            }
        }
    }
}

// MARK: - Matter Scale

private struct StatisticsMatterScaleSection: View {
    let engine: GameEngine

    var body: some View {
        let lines = engine.gameState.statistics.matterScale
        // Fixed height: the matter-scale strings change length every tick
        // ("3 seconds" → "1 minute, 5 seconds" → "1 hour", etc.). On narrow
        // iPhone widths those length changes flip the line-wrap count for
        // a Text, growing/shrinking the VStack. Without a fixed reservation
        // every section below this one (Infinity / Eternity / Reality) jitters
        // each tick. Mirrors web's `.c-matter-scale-container { height: 5rem }`
        // with a slightly larger reservation to absorb iPhone wrapping.
        VStack(spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(verbatim: line)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(height: 110, alignment: .center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        // Belt-and-suspenders: if a worst-case multi-line message exceeds the
        // reservation, clip rather than letting it push siblings.
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - News + secret achievements

private struct StatisticsNewsSection: View {
    let engine: GameEngine

    var body: some View {
        let stats = engine.gameState.statistics
        StatsSectionContainer(title: nil, color: .white) {
            let newsTotal = stats.totalNews == 1 ? "news message" : "news messages"
            StatsLine("You have seen \(stats.totalNews) \(newsTotal) in total.")
            let newsUnique = stats.uniqueNews == 1 ? "unique news message" : "unique news messages"
            StatsLine("You have seen \(stats.uniqueNews) \(newsUnique).")
            let secretLabel = stats.secretAchievementCount == 1 ? "Secret Achievement" : "Secret Achievements"
            StatsLine("You have unlocked \(stats.secretAchievementCount) \(secretLabel).")
            if stats.paperclips > 0 {
                let clip = stats.paperclips == 1 ? "useless paperclip" : "useless paperclips"
                StatsLine("You have \(stats.paperclips) \(clip).")
            }
        }
    }
}

// MARK: - Infinity

private struct StatisticsInfinitySection: View {
    let engine: GameEngine

    var body: some View {
        let stats = engine.gameState.statistics
        StatsSectionContainer(title: "Infinity", color: GameColor.infinity) {
            if let count = stats.infinityCount {
                let suffix = stats.eternityUnlocked ? " this Eternity" : ""
                StatsLine("You have \(count)\(suffix).")
            } else {
                let suffix = stats.eternityUnlocked ? " this Eternity" : ""
                StatsLine("You have no Infinities\(suffix).")
            }
            if let banked = stats.bankedInfinities {
                StatsLine("You have \(banked).")
            }
            if let best = stats.bestInfinityTime {
                StatsLine("Your fastest Infinity was \(best).")
            } else {
                let suffix = stats.eternityUnlocked ? " this Eternity" : ""
                StatsLine("You have no fastest Infinity\(suffix).")
            }
            if let current = stats.thisInfinityTime {
                if let real = stats.thisInfinityRealTime {
                    StatsLine("You have spent \(current) in this Infinity. (\(real) real time)")
                } else {
                    StatsLine("You have spent \(current) in this Infinity.")
                }
            }
            if let rate = stats.bestIPPerMin {
                let suffix = stats.eternityUnlocked
                    ? "Your best Infinity Points per minute this Eternity is \(rate)."
                    : "Your best Infinity Points per minute is \(rate)."
                StatsLine(suffix)
            }
        }
    }
}

// MARK: - Eternity

private struct StatisticsEternitySection: View {
    let engine: GameEngine

    var body: some View {
        let stats = engine.gameState.statistics
        StatsSectionContainer(title: "Eternity", color: GameColor.eternity) {
            if let count = stats.eternityCount {
                let suffix = stats.realityUnlocked ? " this Reality" : ""
                StatsLine("You have \(count)\(suffix).")
            }
            // Projected banked on next Eternity.
            if let projected = stats.projectedBankedOnEternity {
                if let rate = stats.projectedBankedRatePerMin {
                    StatsLine("You will gain \(projected) on Eternity (\(rate) per minute).")
                } else {
                    StatsLine("You will gain \(projected) on Eternity.")
                }
            } else if stats.bankedInfinities != nil {
                StatsLine("You will gain no Banked Infinities on Eternity.")
            }
            if let best = stats.bestEternityTime {
                StatsLine("Your fastest Eternity was \(best).")
            } else {
                let suffix = stats.realityUnlocked ? " this Reality" : ""
                StatsLine("You have no fastest Eternity\(suffix).")
            }
            if let current = stats.thisEternityTime {
                if let real = stats.thisEternityRealTime {
                    StatsLine("You have spent \(current) in this Eternity. (\(real) real time)")
                } else {
                    StatsLine("You have spent \(current) in this Eternity.")
                }
            }
            if let rate = stats.bestEPPerMin {
                let suffix = stats.realityUnlocked
                    ? "Your best Eternity Points per minute this Reality is \(rate)."
                    : "Your best Eternity Points per minute is \(rate)."
                StatsLine(suffix)
            }
        }
    }
}

// MARK: - Reality

private struct StatisticsRealitySection: View {
    let engine: GameEngine

    var body: some View {
        let stats = engine.gameState.statistics
        let isDoomed = stats.isDoomed
        let titleColor: Color = isDoomed ? GameColor.pelle : GameColor.reality
        let title = isDoomed ? "Doomed Reality" : "Reality"
        StatsSectionContainer(title: title, color: titleColor) {
            if let count = stats.realityCount {
                let label = count == "1" ? "Reality" : "Realities"
                StatsLine("You have \(count) \(label).")
            }
            if let best = stats.bestRealityTime {
                StatsLine("Your fastest game-time Reality was \(best).")
            }
            if let best = stats.bestRealityRealTime {
                StatsLine("Your fastest real-time Reality was \(best).")
            }
            if let current = stats.thisRealityTime, let real = stats.thisRealityRealTime {
                let label = isDoomed ? "Armageddon" : "Reality"
                let line = "You have spent \(current) in this \(label). (\(real) real time)"
                if isDoomed {
                    StatsLine(line).foregroundStyle(GameColor.pelle)
                } else {
                    StatsLine(line)
                }
            }
            if let rate = stats.bestRMPerMin {
                StatsLine("Your best Reality Machines per minute is \(rate).")
            }
            if let rarity = stats.bestGlyphRarity {
                StatsLine("Your best Glyph rarity is \(rarity).")
            }
        }
    }
}

// MARK: - Doom standalone block

private struct StatisticsDoomedSection: View {
    let engine: GameEngine

    var body: some View {
        let stats = engine.gameState.statistics
        if let real = stats.realTimeDoomed {
            StatsSectionContainer(title: nil, color: GameColor.pelle) {
                StatsLine("You have been Doomed for \(real), real time.")
                    .foregroundStyle(GameColor.pelle)
            }
        }
    }
}

// MARK: - Reusable components

/// Section container with optional colored title above an indented body.
struct StatsSectionContainer<Content: View>: View {
    let title: String?
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(verbatim: title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 4) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Wrapper for a single sentence-form stats line — uses interpolated
/// `Text` so values appear inline rather than right-aligned in a column.
/// Does NOT use a localizable-string call-site (the strings carry runtime
/// values from the JS side that aren't extractable). Localization audit
/// follow-up if the rest of the catalog ever covers this surface.
struct StatsLine: View {
    private let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(verbatim: text)
            .font(.subheadline)
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
