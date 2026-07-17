//
//  StatisticsSharedComponents.swift
//  AntiMatter
//
//  Legacy components shared between the older `ChallengeRecordsTab` and
//  `PastPrestigeRunsTab` subtabs (which still use the key/value layout)
//  and the rest of the app. The main `StatisticsTab` general subtab moved
//  to sentence-form rendering in 2026-05; these are retained because the
//  other subtabs in the Statistics parent still use the older shape.
//

import SwiftUI

/// Title + content card with an ultra-thin material background.
/// Used by ChallengeRecordsTab + PastPrestigeRunsTab.
struct StatSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: title)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0) {
                content
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

/// Label / value HStack — value right-aligned, monospaced digits.
struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(verbatim: label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// Press-and-hold Max All button surfaced at the top of every Statistics-
/// adjacent subtab as a quick affordance (web puts it inline too).
struct StatsMaxAllButton: View {
    let engine: GameEngine

    var body: some View {
        GameButton(borderColor: .green) {
            engine.maxAll()
        } label: {
            Text(verbatim: "Max All")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, minHeight: 36)
        .onHoldRepeat { engine.maxAll() }
    }
}
