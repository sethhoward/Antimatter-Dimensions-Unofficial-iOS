//
//  PastPrestigeRunsTab.swift
//  AntiMatter
//
//  Shows the last 10 prestige runs for each unlocked prestige layer.
//  Mirrors `PastPrestigeRunsContainer.vue` columns:
//   Run | Game Time | Real Time? | Gained / Rate | Count / Rate
//       | Challenge? | Tachyon Particles? (Eternity)
//       | Glyph Level / Relic Shards? (Reality)
//
//  Rows are wide once all extras are visible (Reality + Real Time +
//  Relic Shards on the rate display mode = ~10 columns). The whole table
//  is wrapped in a horizontal `ScrollView` so it survives on iPhone
//  without crushing the cells.
//

import SwiftUI

struct PastPrestigeRunsTab: View {
    let engine: GameEngine

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                StatsMaxAllButton(engine: engine)
                PastPrestigeRunsCycleButton(engine: engine)
                PastPrestigeRunsList(engine: engine)
                PhoneTabBarSpacer()
            }
            .padding()
        }
    }
}

private struct PastPrestigeRunsCycleButton: View {
    let engine: GameEngine

    var body: some View {
        let state = engine.gameState.pastPrestigeRuns
        GameButton(borderColor: .green) {
            engine.cyclePrestigeRunDisplayMode()
        } label: {
            Text(state.displayMode.label)
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
    }
}

private struct PastPrestigeRunsList: View {
    let engine: GameEngine

    var body: some View {
        let state = engine.gameState.pastPrestigeRuns
        ForEach(state.sections.filter(\.isUnlocked), id: \.name) { section in
            PrestigeRunsSectionView(section: section, displayMode: state.displayMode)
        }
    }
}

// MARK: - Section View

private struct PrestigeRunsSectionView: View {
    let section: PrestigeRunsSection
    let displayMode: PrestigeRunDisplayMode

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text("Last 10 \(section.plural)")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 10)

            if isExpanded {
                // Horizontal scroll wrapper — table can be wide once all
                // extras (Real Time + Tachyon Particles / Glyph Level +
                // Relic Shards rate) are visible.
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(spacing: 0) {
                        headerRow
                        ForEach(section.runs) { run in
                            if run.isEmpty {
                                emptyRow(run: run)
                            } else {
                                dataRow(run: run)
                            }
                        }
                    }
                    .frame(minWidth: tableMinWidth, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - Column layout

    /// Total minimum width across all visible columns. Roughly proportional
    /// to the per-column widths below so the table stays readable on iPhone
    /// (which would otherwise compress columns until ellipses appear).
    private var tableMinWidth: CGFloat {
        var w: CGFloat = runColWidth
        var visibleCols = 2  // Run + Game Time
        w += timeColWidth                                       // Game Time
        if section.hasRealTime         { w += timeColWidth;       visibleCols += 1 }    // Real Time
        w += metricColWidth                                     // Col 1
        w += metricColWidth                                     // Col 2
        visibleCols += 2
        if section.hasChallenge        { w += challengeColWidth; visibleCols += 1 }
        if section.hasTachyonParticles { w += metricColWidth;    visibleCols += 1 }
        if section.hasGlyphLevel       { w += glyphLevelColWidth; visibleCols += 1 }
        if section.hasRelicShards      { w += metricColWidth;    visibleCols += 1 }
        // Inter-column gaps.
        w += CGFloat(max(visibleCols - 1, 0)) * gapColWidth
        return w
    }

    // Column widths sized for the worst-case content per column. Bumped
    // 2026-05 because endgame EP-rates like "4.25e27932 EP/min" + long
    // challenge names like "Eternity Challenge 12 (5/5)" were wrapping to
    // multiple lines or abutting the next column with no breathing room.
    // Each cell adds a small inner gap via `gapColWidth` between adjacent
    // columns; numeric cells get `.lineLimit(1)` so they never wrap.
    private var runColWidth: CGFloat        { 70 }
    private var timeColWidth: CGFloat       { 110 }
    private var metricColWidth: CGFloat     { 160 }
    private var challengeColWidth: CGFloat  { 170 }
    private var glyphLevelColWidth: CGFloat { 90 }
    private var gapColWidth: CGFloat        { 12 }

    private var col1Header: String { displayMode.columnHeaders.0 }
    private var col2Header: String { displayMode.columnHeaders.1 }
    private var relicShardsHeader: String {
        displayMode == .rate ? "Relic Shard Rate" : "Relic Shards"
    }

    private func col1Value(_ run: RecentRunRow) -> String {
        switch displayMode {
        case .absoluteGain:  run.currencyGain
        case .rate:          run.currencyRate
        case .currency:      run.currencyGain
        case .prestigeCount: run.prestigeCount
        }
    }

    private func col2Value(_ run: RecentRunRow) -> String {
        switch displayMode {
        case .absoluteGain:  run.prestigeCount
        case .rate:          run.prestigeCountRate
        case .currency:      run.currencyRate
        case .prestigeCount: run.prestigeCountRate
        }
    }

    private func relicShardValue(_ run: RecentRunRow) -> String {
        displayMode == .rate ? run.relicShardRate : run.relicShards
    }

    private var headerRow: some View {
        HStack(spacing: gapColWidth) {
            Text("Run")
                .frame(width: runColWidth, alignment: .leading)
            Text(section.hasRealTime ? "Game Time" : "Time in Run")
                .frame(width: timeColWidth, alignment: .trailing)
            if section.hasRealTime {
                Text("Real Time")
                    .frame(width: timeColWidth, alignment: .trailing)
            }
            Text(col1Header)
                .frame(width: metricColWidth, alignment: .trailing)
            Text(col2Header)
                .frame(width: metricColWidth, alignment: .trailing)
            if section.hasChallenge {
                Text("Challenge")
                    .frame(width: challengeColWidth, alignment: .trailing)
            }
            if section.hasTachyonParticles {
                Text("Tachyon Particles")
                    .frame(width: metricColWidth, alignment: .trailing)
            }
            if section.hasGlyphLevel {
                Text("Glyph Level")
                    .frame(width: glyphLevelColWidth, alignment: .trailing)
            }
            if section.hasRelicShards {
                Text(relicShardsHeader)
                    .frame(width: metricColWidth, alignment: .trailing)
            }
        }
        .lineLimit(1)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func dataRow(run: RecentRunRow) -> some View {
        VStack(spacing: 0) {
            if run.id > 0 || run.label == "Average" {
                Divider().padding(.horizontal, 14)
            }
            HStack(spacing: gapColWidth) {
                Text(run.label)
                    .frame(width: runColWidth, alignment: .leading)
                    .foregroundStyle(run.label == "Average" ? Color.yellow : .primary)
                Text(run.gameTime)
                    .frame(width: timeColWidth, alignment: .trailing)
                if section.hasRealTime {
                    Text(run.realTime.isEmpty ? "—" : run.realTime)
                        .frame(width: timeColWidth, alignment: .trailing)
                }
                Text(col1Value(run))
                    .frame(width: metricColWidth, alignment: .trailing)
                Text(col2Value(run))
                    .frame(width: metricColWidth, alignment: .trailing)
                if section.hasChallenge {
                    Text(run.challenge)
                        .frame(width: challengeColWidth, alignment: .trailing)
                }
                if section.hasTachyonParticles {
                    Text(run.tachyonParticles.isEmpty ? "—" : run.tachyonParticles)
                        .frame(width: metricColWidth, alignment: .trailing)
                }
                if section.hasGlyphLevel {
                    Text(run.glyphLevel.isEmpty ? "—" : run.glyphLevel)
                        .frame(width: glyphLevelColWidth, alignment: .trailing)
                }
                if section.hasRelicShards {
                    Text(relicShardValue(run).isEmpty ? "—" : relicShardValue(run))
                        .frame(width: metricColWidth, alignment: .trailing)
                }
            }
            .lineLimit(1)
            .font(.caption)
            .monospacedDigit()
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private func emptyRow(run: RecentRunRow) -> some View {
        VStack(spacing: 0) {
            if run.id > 0 {
                Divider().padding(.horizontal, 14)
            }
            Text("You have not done \(run.id + 1) \(section.plural) yet.")
                .font(.caption)
                .italic()
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
    }
}
