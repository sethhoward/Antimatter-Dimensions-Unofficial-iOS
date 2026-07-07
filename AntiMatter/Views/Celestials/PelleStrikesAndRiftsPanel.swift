//
//  PelleStrikesAndRiftsPanel.swift
//  AntiMatter
//
//  Phase 3 of the Pelle port. 5 strikes (Infinity / Power Galaxies / Eternity
//  / 115 TT / Dilation), each gating one of 5 rifts (Vacuum / Decay / Chaos
//  / Recursion / Paradox). Mirrors:
//    src/components/tabs/celestial-pelle/PelleBarPanel.vue
//    src/components/tabs/celestial-pelle/PelleStrike.vue
//    src/components/tabs/celestial-pelle/PelleRift.vue
//    src/components/tabs/celestial-pelle/PelleRiftBar.vue
//
//  Pre-strike, the row shows just the strike's requirement / penalty / reward
//  text. Once the strike triggers, the rift bar appears with milestone markers
//  + an Active toggle. Tap a rift to open the milestone detail sheet.
//

import SwiftUI

struct PelleStrikesAndRiftsPanel: View {
    let engine: GameEngine
    @Environment(\.layoutMetrics) private var metrics

    private var pelle: PelleState { engine.gameState.celestials.pelle }

    /// Pair each strike with its corresponding rift (matched by `riftId`).
    private var rows: [(strike: PelleStrikeInfo, rift: PelleRiftInfo?)] {
        let riftMap: [String: PelleRiftInfo] = Dictionary(uniqueKeysWithValues: pelle.rifts.map { ($0.id, $0) })
        return pelle.strikes.map { ($0, riftMap[$0.riftId]) }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Pelle Strikes and Rifts")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GameColor.pelle.readableOnDark())
                Spacer()
                Text("\(pelle.strikes.filter(\.hasStrike).count) of \(pelle.strikes.count) triggered")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // Flavor text — mirrors web `PelleBarPanel.vue:51-57`. Centered
            // multi-line block above the rift cards. The final warning line
            // is rendered in Pelle red + bold to match the web `o-strike-warning`
            // class. The drain percent is sourced from `Pelle.riftDrainPercent`
            // (currently a literal 0.03) via `pelle.riftDrainPercentText` so any
            // upstream change carries through.
            VStack(spacing: 2) {
                Text("Rifts can be activated by clicking on their bars.")
                Text("You cannot activate more than two Rifts at once.")
                Text("When active, Rifts consume \(pelle.riftDrainPercentText) of another resource per second.")
                Text("Rift effects apply even when not activated, and are based on the total amount drained.")
                Text("Pelle Strike penalties are permanent and remain active even after Armageddon!")
                    .fontWeight(.bold)
                    .foregroundStyle(GameColor.pelle.readableOnDark())
                    .padding(.top, 2)
            }
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.85))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

            VStack(spacing: 10) {
                ForEach(rows, id: \.strike.id) { row in
                    PelleStrikeRow(engine: engine, strike: row.strike, rift: row.rift)
                }
            }
        }
        .padding(12)
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
}

// MARK: - One strike row + its rift bar

private struct PelleStrikeRow: View {
    let engine: GameEngine
    let strike: PelleStrikeInfo
    let rift: PelleRiftInfo?

    @State private var showMilestones = false

    private var riftColor: Color {
        rift.map { Color(cssColor: $0.hexColor) } ?? GameColor.pelle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header row — strike name + status badge.
            HStack(spacing: 8) {
                Text(strike.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(strike.hasStrike ? riftColor.readableOnDark() : .white.opacity(0.7))
                Spacer()
                Text(strike.hasStrike ? "Triggered" : "Locked")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(strike.hasStrike ? .black : .white.opacity(0.7))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(
                        Capsule().fill(strike.hasStrike ? riftColor : Color.white.opacity(0.15))
                    )
            }

            // Static text — requirement, penalty, reward. Always visible
            // (web shows these on the strike card whether triggered or not).
            VStack(alignment: .leading, spacing: 2) {
                strikeLabelLine(label: "Requirement", value: strike.requirementText, color: .white.opacity(0.9))
                strikeLabelLine(label: "Penalty",     value: strike.penaltyText,     color: GameColor.pelle.readableOnDark())
                strikeLabelLine(label: "Reward",      value: strike.rewardText,      color: GameColor.good.readableOnDark())
            }

            // Rift bar — only renders post-strike.
            if strike.hasStrike, let rift {
                PelleRiftBar(rift: rift)
                    .padding(.top, 4)

                // Rift reward effects — mirrors web `PelleRift.vue:88-95`
                // (the left-column `rift.effects` block). These are the rewards
                // you get from draining the rift (e.g. Vacuum/"Void" →
                // "IP gain ×X"), applied even when not actively draining.
                // Monospaced so the per-tick value digits don't reflow the row.
                if !rift.effects.isEmpty {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(rift.effects.enumerated()), id: \.offset) { _, effect in
                            Text(effect)
                                .font(.system(.caption2, design: .monospaced).weight(.medium))
                                .foregroundStyle(riftColor.readableOnDark())
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
                }

                // Per-rift flavor text — mirrors web `PelleRift.vue:107-119`.
                // "Drains X to fill" + Current Amount (when not maxed) + Total
                // Filled. Chaos rift (id "chaos") cycles its drain resource
                // name (it drains Decay's fill) — we already get the cycled
                // form via `cycledFillCurrencyName` and render in monospaced
                // so the wordCycle padding holds layout.
                let drainName = rift.id == "chaos" ? rift.cycledFillCurrencyName : rift.fillCurrencyName
                if !drainName.isEmpty || !rift.totalFillText.isEmpty {
                    VStack(alignment: .leading, spacing: 1) {
                        if !drainName.isEmpty {
                            Text("Drains \(drainName) to fill.")
                                .font(rift.id == "chaos"
                                      ? .system(.caption2, design: .monospaced)
                                      : .caption2)
                        }
                        if !rift.isMaxed && !rift.currentFillText.isEmpty {
                            Text("Current Amount: \(rift.currentFillText)")
                                .font(.caption2.monospacedDigit())
                        }
                        if !rift.totalFillText.isEmpty {
                            Text("Total Filled: \(rift.totalFillText)")
                                .font(.caption2.monospacedDigit())
                        }
                    }
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
                }

                HStack(spacing: 8) {
                    GameButton(theme: .pelle, isEnabled: !rift.isMaxed) {
                        engine.togglePelleRift(rift.id)
                    } label: {
                        Text(rift.isActive ? "Stop draining" : "Drain \(rift.fillCurrencyName)")
                            .font(.caption.weight(.medium))
                            .padding(.vertical, 6).padding(.horizontal, 10)
                    }
                    Button {
                        showMilestones = true
                    } label: {
                        Label("Milestones", systemImage: "list.bullet.rectangle")
                            .font(.caption.weight(.medium))
                            .padding(.vertical, 6).padding(.horizontal, 10)
                            .foregroundStyle(riftColor)
                            .overlay(
                                Capsule().stroke(riftColor.opacity(0.6), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    if rift.isMaxed {
                        Text("Maxed")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(GameColor.good.readableOnDark())
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke((strike.hasStrike ? riftColor : GameColor.pelle).opacity(0.3), lineWidth: 1)
                )
        )
        .sheet(isPresented: $showMilestones) {
            if let rift {
                PelleRiftMilestonesSheet(rift: rift)
            }
        }
    }

    @ViewBuilder
    private func strikeLabelLine(label: String, value: String, color: Color) -> some View {
        if !value.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                Text(label + ":")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 78, alignment: .leading)
                // Monospaced + flexible-width frame: wordShift.wordCycle
                // ticks the cycled word's letters every 250ms, but pads the
                // result to a constant character count. With monospaced
                // glyphs that constant char count translates to a constant
                // visual width, so the row no longer reflows each poll.
                Text(value)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Rift fill bar with milestone markers

private struct PelleRiftBar: View {
    let rift: PelleRiftInfo
    @Environment(\.scenePhase) private var scenePhase

    private var color: Color { Color(cssColor: rift.hexColor) }

    /// Active fill sweep + locked-milestone flash both pin to scene phase.
    /// Backgrounded ⇒ TimelineView is dropped from the hierarchy.
    private var animationsActive: Bool {
        scenePhase == .active && !rift.isMaxed && (rift.isActive || hasLockedMilestone)
    }

    private var hasLockedMilestone: Bool {
        rift.milestones.contains { !$0.isUnlocked && !$0.isDisabled }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // Cycled rift name (web: PelleRift.vue title — wordCycle).
                // Monospaced so the 250ms letter scramble doesn't reflow.
                Text(rift.cycledName.isEmpty ? rift.name : rift.cycledName)
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(color.readableOnDark())
                    .lineLimit(1)
                Spacer()
                Text(percentString(rift.percentage))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)
                if rift.realPercentage > rift.percentage {
                    Text("(real \(percentString(rift.realPercentage)))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                if animationsActive {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animationsActive)) { ctx in
                        riftBarBody(width: geo.size.width, time: ctx.date.timeIntervalSinceReferenceDate)
                    }
                } else {
                    riftBarBody(width: geo.size.width, time: 0)
                }
            }
            .frame(height: 14)
        }
    }

    @ViewBuilder
    private func riftBarBody(width: CGFloat, time: TimeInterval) -> some View {
        let pct = min(max(rift.percentage, 0), 1)
        let fillWidth = width * CGFloat(pct)
        // Reduced-to overlay sits on the right side of the fill — width is
        // (1 - reducedTo) of the full bar but only when reducedTo < 1.
        let reducedTo = min(max(rift.reducedTo, 0), 1)
        let showReducedOverlay = rift.isSpendable && reducedTo < 1
        let reducedOverlayWidth = width * CGFloat(1 - reducedTo)

        // Sweep band (web: a-pelle-bar-filling-sweep, 2s loop). Width grows
        // from 0 to ~2rem (~32pt) over the first 10%, slides across the
        // bar through 90%, then collapses back to 0. Constrained to the
        // current fill so the band never overshoots the rendered fill area.
        let sweepBandPx: CGFloat = 32
        let sweepPhase = rift.isActive && !rift.isMaxed
            ? (time.truncatingRemainder(dividingBy: 2.0)) / 2.0
            : 0
        // Mirror the web keyframes: 0..0.1 width grows 0→2rem at left=0,
        // 0.1..0.9 slides to left = (100% - 2rem), 0.9..1 width shrinks to 0.
        let sweepBand: (offset: CGFloat, width: CGFloat) = {
            if !rift.isActive || rift.isMaxed { return (0, 0) }
            let p = sweepPhase
            if p < 0.1 {
                return (0, sweepBandPx * CGFloat(p / 0.1))
            } else if p < 0.9 {
                let t = (p - 0.1) / 0.8
                let off = (fillWidth - sweepBandPx) * CGFloat(t)
                return (max(0, off), sweepBandPx)
            } else {
                let t = (p - 0.9) / 0.1
                let band = sweepBandPx * CGFloat(1 - t)
                let off = max(0, fillWidth - band)
                return (off, band)
            }
        }()

        // Locked-milestone flash (web: 1s, opacity 1 ↔ 0.3, sin-shaped).
        let flashPhase = sin(time * .pi)
        let flashOpacity = 0.65 + flashPhase * 0.35  // 0.30 ↔ 1.00

        ZStack(alignment: .leading) {
            // Track
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(color.opacity(0.5), lineWidth: 1)
                )
            // Fill
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(rift.isActive ? 0.85 : 0.6))
                .frame(width: max(fillWidth, 0))
            // Active sweep band (overlaid on the fill, clipped by it).
            if sweepBand.width > 0 {
                Rectangle()
                    .fill(color.opacity(0.3))
                    .frame(width: sweepBand.width, height: 14)
                    .offset(x: sweepBand.offset)
                    .blendMode(.plusLighter)
            }
            // Reduced-to overlay (right side, dims the unavailable region).
            if showReducedOverlay {
                Rectangle()
                    .fill(color.opacity(0.35))
                    .brightness(-0.3)
                    .frame(width: max(reducedOverlayWidth, 0), height: 14)
                    .offset(x: width - reducedOverlayWidth)
            }
            // Milestone markers
            ForEach(rift.milestones) { m in
                let pos = width * CGFloat(min(max(m.thresholdPct / 100, 0), 1))
                let baseOpacity: Double = m.isUnlocked ? 1.0 : (m.isDisabled ? 0.25 : 0.4)
                let opacity: Double = (!m.isUnlocked && !m.isDisabled && rift.isActive)
                    ? flashOpacity
                    : baseOpacity
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: 14)
                    .opacity(opacity)
                    .offset(x: pos - 1, y: 0)
            }
        }
    }

    private func percentString(_ p: Double) -> String {
        let pct = max(0, min(p, 1)) * 100
        if pct >= 99.95 { return "100%" }
        return String(format: "%.2f%%", pct)
    }
}

// MARK: - Milestone detail sheet

private struct PelleRiftMilestonesSheet: View {
    let rift: PelleRiftInfo

    private var color: Color { Color(cssColor: rift.hexColor) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(rift.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(color.readableOnDark())
                    Text("Filled by \(rift.fillCurrencyName). Each milestone unlocks at the listed % fill.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Divider().overlay(color.opacity(0.4))
                    ForEach(rift.milestones) { m in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: m.isUnlocked ? "checkmark.circle.fill" : "circle.dashed")
                                    .foregroundStyle(m.isUnlocked ? GameColor.good : color.opacity(0.5))
                                Text(m.requirementText)
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                                Spacer()
                            }
                            Text(m.effectText)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.3))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(color.opacity(m.isUnlocked ? 0.6 : 0.25), lineWidth: 1)
                                )
                        )
                    }
                }
                .padding(16)
            }
            .adaptiveSheetTitle("\(rift.name) — Milestones")
        }
    }
}
