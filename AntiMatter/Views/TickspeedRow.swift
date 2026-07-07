//
//  TickspeedRow.swift
//  AntiMatter
//
//  Tickspeed upgrade row — mirrors TickspeedRow.vue.
//  Visible when Tickspeed.isUnlocked (after 2nd dimension purchased).
//

import SwiftUI

struct TickspeedRow: View {
    let tickspeed: TickspeedState
    let onBuy: () -> Void
    let onBuyMax: () -> Void
    /// Matches Vue `TickspeedRow.vue:110-115` — when the Reality button shows
    /// (i.e. the Reality time study is bought), the web moves the tickspeed
    /// info out of the header and into a labels row below these buttons.
    var showLabels: Bool = false

    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        VStack(spacing: 4) {
            // Buttons row is its own leaf so per-tick `perSecond` updates
            // (which change `TickspeedLabelsRow`) don't trigger
            // re-evaluation of the cost/Buy Max GameButtons. SwiftUI diffs
            // primitive args (cost, isAffordable, isCompact, widths) and
            // skips the body when none of them changed.
            TickspeedButtonRow(
                cost: tickspeed.cost,
                isAffordable: tickspeed.isAffordable,
                isCompact: metrics.isCompact,
                tickspeedCostWidth: metrics.tickspeedCostWidth,
                tickspeedMaxWidth: metrics.tickspeedMaxWidth,
                onBuy: onBuy,
                onBuyMax: onBuyMax
            )
            if showLabels {
                TickspeedLabelsRow(
                    tickspeedPerSecond: tickspeed.perSecond,
                    tickspeedMultiplier: tickspeed.multiplier
                )
            }
        }
    }
}

/// Buy Tickspeed + Buy Max buttons. Extracted so per-tick text in
/// `TickspeedLabelsRow` (perSecond / multiplier, both 30Hz post-Reality)
/// doesn't force these GameButtons to re-evaluate. SwiftUI diffs the
/// primitive args; closures are passed in but the leaf still skips
/// re-evaluation when `cost` and `isAffordable` are unchanged.
private struct TickspeedButtonRow: View {
    let cost: String
    let isAffordable: Bool
    let isCompact: Bool
    let tickspeedCostWidth: CGFloat
    let tickspeedMaxWidth: CGFloat
    let onBuy: () -> Void
    let onBuyMax: () -> Void

    var body: some View {
        if isCompact {
            // iPhone: single line, flexible widths, no jitter
            HStack(spacing: 8) {
                GameButton(borderColor: .green, isEnabled: isAffordable) {
                    onBuy()
                } label: {
                    Text("Tickspeed: \(cost)")
                        .font(.subheadline.monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 36)

                GameButton(borderColor: .green, isEnabled: isAffordable) {
                    onBuyMax()
                } label: {
                    Text("Buy Max")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
                .frame(width: 80)
                .frame(minHeight: 36)
            }
            .padding(.horizontal, 12)
        } else {
            // iPad: original fixed-width centered layout
            HStack(spacing: 12) {
                Spacer()
                GameButton(borderColor: .green, isEnabled: isAffordable) {
                    onBuy()
                } label: {
                    Text("Tickspeed Cost: \(cost)")
                        .font(.subheadline.monospacedDigit())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }
                .frame(width: tickspeedCostWidth)

                GameButton(borderColor: .green, isEnabled: isAffordable) {
                    onBuyMax()
                } label: {
                    Text("Buy Max")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }
                .frame(width: tickspeedMaxWidth)
                Spacer()
            }
        }
    }
}

/// Post-Reality-study labels row — matches Vue `TickspeedRow.vue:110-115`.
/// Isolated so per-tick text changes don't invalidate the button row layout.
///
/// TODO: EC3 variant not ported. When `InfinityChallenge(3).isRunning`, Vue
/// (lines 29-33) swaps the multiplier text to
/// "Multiply all Antimatter Dimensions by ×(1.05 + galaxyCount × 0.005)"
/// instead of the usual "×Y faster / upgrade." Same swap lives in
/// HeaderTickspeedInfo.vue:22-26. Would need two extra polled fields
/// (`isInIC3`, `galaxyCount`) on `InfinityState` + a branch here and in the
/// Continuum variant. Rare but real: IC3 during a post-Reality-study run.
private struct TickspeedLabelsRow: View {
    let tickspeedPerSecond: String
    let tickspeedMultiplier: String

    var body: some View {
        Text("Tickspeed: \(tickspeedPerSecond)/s | \(tickspeedMultiplier) faster/upgrade")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.75))
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 12)
    }
}

/// Drop-in replacement for `TickspeedRow` when Lai'tela's Continuum is
/// active. Renders a non-interactive "Tickspeed Continuum: X,XXX.XX" pill
/// matching the web AD tab's `ContinuumTickspeedRow.vue`.
struct TickspeedContinuumRow: View {
    let value: Double
    /// Post-Reality-study tickspeed info (see TickspeedRow.vue:110-115).
    /// When `showLabels` is true, renders the same labels row as TickspeedRow
    /// below the Continuum pill.
    var tickspeedPerSecond: String = ""
    var tickspeedMultiplier: String = ""
    var showLabels: Bool = false

    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                Spacer()
                Text("Tickspeed Continuum: \(Self.formatter.string(from: NSNumber(value: value)) ?? "0")")
                    .font(metrics.isCompact ? .caption.weight(.medium) : .subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.black, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6).stroke(GameColor.good, lineWidth: 1)
                    )
                Spacer()
            }
            .padding(.horizontal, 12)

            if showLabels {
                Text("Tickspeed: \(tickspeedPerSecond)/s | \(tickspeedMultiplier) faster/upgrade")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 12)
            }
        }
    }

    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()
}
