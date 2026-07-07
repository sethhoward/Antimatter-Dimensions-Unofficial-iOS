//
//  SpeedrunMilestonesTab.swift
//  AntiMatter
//
//  Statistics > Speedrun Milestones subtab. Mirrors
//  `SpeedrunMilestonesTab.vue`. Replaces the inline Speedrun section that
//  previously lived inside `StatisticsTab.swift`.
//
//  Visible only when `engine.speedrunMilestonesVisible == true`
//  (= `player.speedrun.isActive`). Active-run summary on top + full
//  milestone list with per-row splits. The "Describe all milestones" toggle
//  is persisted via `player.speedrun.displayAllMilestones`.
//

import SwiftUI

struct SpeedrunMilestonesTab: View {
    let engine: GameEngine

    @State private var history: SpeedrunHistoryState = SpeedrunHistoryState()
    @State private var displayAll: Bool = false
    @State private var startTimeStr: String = ""
    @State private var hasStarted: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                runHeader
                Toggle(isOn: $displayAll) {
                    Text(verbatim: "Describe all milestones")
                        .font(.subheadline)
                }
                .onChange(of: displayAll) { _, newValue in
                    engine.setSpeedrunDisplayAllMilestones(newValue)
                }
                Divider().overlay(.white.opacity(0.3))
                Text(verbatim: startTimeStr)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                milestonesList
                PhoneTabBarSpacer()
            }
            .padding()
        }
        .onAppear { refresh() }
        .onChange(of: engine.speedrunQuick.mostRecentId) { _, _ in refresh() }
        .onChange(of: engine.speedrunQuick.mostRecentMs) { _, _ in refresh() }
    }

    // MARK: - Active-run summary

    @ViewBuilder
    private var runHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "Speedrun")
                .font(.title2.weight(.bold))
                .foregroundStyle(GameColor.celestials)
            let q = engine.speedrunQuick
            if q.isActive {
                Text(verbatim: "Run: \(q.name.isEmpty ? "—" : q.name)")
                    .font(.subheadline)
                Text(verbatim: "Time since start: \(formatElapsed(q.elapsedMs, hasStarted: q.hasStarted))")
                    .font(.subheadline)
                Text(verbatim: history.isSegmented ? "Segment type: Segmented" : "Segment type: Single-segment")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(verbatim: "No active speedrun.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Milestones list

    @ViewBuilder
    private var milestonesList: some View {
        let maxReached = history.milestones.lastIndex(where: { $0.timeMs > 0 }) ?? -1
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(history.milestones.enumerated()), id: \.element.id) { idx, m in
                // Web shows reached + (displayAll ? all : up-to-current).
                // We add a hide rule for far-future milestones until either
                // toggled or reached.
                if displayAll || idx <= maxReached + 1 {
                    SpeedrunMilestoneRow(milestone: m,
                                         reached: m.timeMs > 0)
                }
            }
        }
    }

    private func refresh() {
        engine.loadSpeedrunHistory { state in self.history = state }
        engine.loadSpeedrunMilestonesMeta { all, startStr, started in
            self.displayAll = all
            self.startTimeStr = startStr.isEmpty ? "Speedrun not started yet." : startStr
            self.hasStarted = started
        }
    }

    private func formatElapsed(_ ms: Double, hasStarted: Bool) -> String {
        guard hasStarted && ms > 0 else { return "00:00:00" }
        let totalSec = Int(ms / 1000)
        let h = totalSec / 3600
        let m = (totalSec % 3600) / 60
        let s = totalSec % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

// MARK: - Single milestone row

private struct SpeedrunMilestoneRow: View {
    let milestone: SpeedrunMilestoneInfo
    let reached: Bool

    var body: some View {
        HStack {
            Text(verbatim: milestone.name)
                .font(.subheadline)
                .foregroundStyle(reached ? .white : Color.secondary)
            Spacer()
            Text(verbatim: reached ? formatTime(milestone.timeMs) : "—")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(reached ? .white : Color.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.white.opacity(reached ? 0.25 : 0.1))
        )
    }

    private func formatTime(_ ms: Double) -> String {
        let totalSec = Int(ms / 1000)
        let h = totalSec / 3600
        let m = (totalSec % 3600) / 60
        let s = totalSec % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
