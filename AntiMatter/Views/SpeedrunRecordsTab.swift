//
//  SpeedrunRecordsTab.swift
//  AntiMatter
//
//  Statistics > Speedrun Records subtab. Mirrors `PreviousSpeedrunTab.vue`.
//
//  Visible only when `engine.speedrunRecordsVisible == true`
//  (= `Object.keys(player.speedrun.previousRuns).length > 0`).
//
//  Lists every previously-completed speedrun. Tap a run to compare its
//  milestone splits against the current run + the best-ever per milestone.
//  Web shows pagination over 10 runs per page; iOS uses a single ScrollView
//  since the list is rarely more than a handful of runs.
//

import SwiftUI

struct SpeedrunRecordsTab: View {
    let engine: GameEngine
    @State private var state: SpeedrunRecordsState = .empty
    @State private var selectedRunId: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summaryHeader
                if state.runs.isEmpty {
                    Text(verbatim: "No previous speedruns yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else {
                    ForEach(state.runs) { run in
                        SpeedrunRecordRow(run: run,
                                          isSelected: run.id == selectedRunId,
                                          onTap: { toggleSelect(run) })
                    }

                    if let sel = selectedRun() {
                        Divider().overlay(.white.opacity(0.3))
                        Text(verbatim: "Milestones for \(sel.name)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(GameColor.celestials)
                        ForEach(sel.milestones) { m in
                            milestoneRow(m)
                        }
                    }
                }
                PhoneTabBarSpacer()
            }
            .padding()
        }
        .onAppear { refresh() }
    }

    @ViewBuilder
    private var summaryHeader: some View {
        let count = state.runs.count
        let label = count == 1 ? "speedrun" : "speedruns"
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "Speedrun Records")
                .font(.title2.weight(.bold))
                .foregroundStyle(GameColor.celestials)
            Text(verbatim: "You have completed \(count) \(label) prior to this playthrough.")
                .font(.subheadline)
                .foregroundStyle(.white)
            Text(verbatim: "Tap a run to view its milestone splits.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func toggleSelect(_ run: SpeedrunPreviousRun) {
        selectedRunId = (selectedRunId == run.id) ? nil : run.id
    }

    private func selectedRun() -> SpeedrunPreviousRun? {
        guard let id = selectedRunId else { return nil }
        return state.runs.first(where: { $0.id == id })
    }

    @ViewBuilder
    private func milestoneRow(_ m: SpeedrunPreviousMilestone) -> some View {
        HStack {
            Text(verbatim: m.name)
                .font(.subheadline)
            Spacer()
            Text(verbatim: m.timeMs > 0 ? formatTime(m.timeMs) : "—")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(m.timeMs > 0 ? .white : Color.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private func refresh() {
        engine.loadSpeedrunRecords { state in self.state = state }
    }

    private func formatTime(_ ms: Double) -> String {
        let totalSec = Int(ms / 1000)
        let h = totalSec / 3600
        let m = (totalSec % 3600) / 60
        let s = totalSec % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

private struct SpeedrunRecordRow: View {
    let run: SpeedrunPreviousRun
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "chevron.down.circle.fill" : "magnifyingglass")
                    .foregroundStyle(isSelected ? GameColor.celestials : .white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: run.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(verbatim: "\(formatTime(run.totalTimeMs)) • \(run.isSegmented ? "Segmented" : "Single-segment")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? GameColor.celestials : .white.opacity(0.25))
            )
        }
        .buttonStyle(.plain)
    }

    private func formatTime(_ ms: Double) -> String {
        let totalSec = Int(ms / 1000)
        let h = totalSec / 3600
        let m = (totalSec % 3600) / 60
        let s = totalSec % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
