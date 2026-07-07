//
//  ChallengeRecordsTab.swift
//  AntiMatter
//
//  Best completion times for Normal and Infinity Challenges.
//

import SwiftUI

struct ChallengeRecordsTab: View {
    let engine: GameEngine

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                StatsMaxAllButton(engine: engine)
                ChallengeRecordsNormalSection(engine: engine)
                ChallengeRecordsInfinitySection(engine: engine)
                PhoneTabBarSpacer()
            }
            .padding()
        }
    }
}

// MARK: - Normal Challenges

private struct ChallengeRecordsNormalSection: View {
    let engine: GameEngine

    var body: some View {
        let records = engine.gameState.challengeRecords
        StatSection(title: "Normal Challenges") {
            ForEach(0..<11, id: \.self) { i in
                StatRow(label: "Challenge \(i + 2)", value: records.normalTimes[i])
            }
            Divider().padding(.horizontal, 14)
            if let sum = records.normalSum {
                StatRow(label: "Sum of record times", value: sum)
            } else {
                Text("You have not completed all Normal Challenges yet.")
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
    }
}

// MARK: - Infinity Challenges

private struct ChallengeRecordsInfinitySection: View {
    let engine: GameEngine

    var body: some View {
        let records = engine.gameState.challengeRecords
        if records.showInfinityChallenges {
            StatSection(title: "Infinity Challenges") {
                ForEach(0..<8, id: \.self) { i in
                    StatRow(label: "Infinity Challenge \(i + 1)", value: records.infinityTimes[i])
                }
                Divider().padding(.horizontal, 14)
                if let sum = records.infinitySum {
                    StatRow(label: "Sum of record times", value: sum)
                } else {
                    Text("You have not completed all Infinity Challenges yet.")
                        .font(.subheadline)
                        .italic()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            }
        }
    }
}
