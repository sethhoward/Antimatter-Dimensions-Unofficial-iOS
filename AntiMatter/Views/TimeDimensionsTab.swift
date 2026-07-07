//
//  TimeDimensionsTab.swift
//  AntiMatter
//
//  Time Dimensions — 8 tiers that cost Eternity Points and produce
//  Time Shards, which grant free Tickspeed upgrades.
//  Layout mirrors InfinityDimensionsTab for visual parity.
//

import SwiftUI

struct TimeDimensionsTab: View {
    let engine: GameEngine

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    TimeDimensionsHeaderRow(engine: engine)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)

                    TimeDimensionsInfoSection(engine: engine)
                        .padding(.horizontal)
                        .padding(.bottom, 6)

                    TimeDimensionsRowsSection(engine: engine)

                    PhoneTabBarSpacer()
                }
            }
        }
    }
}

// MARK: - Header row: [Toggle all autobuyers] [Spacer] [Max All]

/// Thin reader / Equatable inner — same pattern as `InfinityDimensionsHeaderRow`.
/// `areAutobuyersUnlocked` is a once-only transition; `headerButtonWidth` is
/// env-driven. Inner body skip preserves both `GameButton` modifier chains.
private struct TimeDimensionsHeaderRow: View {
    let engine: GameEngine

    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        TimeDimensionsHeaderRowInner(
            headerButtonWidth: metrics.headerButtonWidth,
            showAutoButton: engine.gameState.timeDimensions.areAutobuyersUnlocked,
            engine: engine
        ).equatable()
    }
}

private struct TimeDimensionsHeaderRowInner: View, Equatable {
    let headerButtonWidth: CGFloat
    let showAutoButton: Bool
    let engine: GameEngine

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.headerButtonWidth == rhs.headerButtonWidth
            && lhs.showAutoButton == rhs.showAutoButton
    }

    var body: some View {
        HStack {
            if showAutoButton {
                GameButton(borderColor: .green) {
                    engine.toggleAllTimeDimensionAutobuyers()
                } label: {
                    Text("Toggle all autobuyers")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                }
                .frame(height: 30)
            }

            Spacer()

            GameButton(borderColor: .green) {
                engine.maxAllTimeDimensions()
            } label: {
                Text("Max All")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
            }
            .frame(width: headerButtonWidth, height: 30)
        }
    }
}

// MARK: - Info text section (matches web ModernTimeDimensionsTab.vue)

private struct TimeDimensionsInfoSection: View {
    let engine: GameEngine

    @AppStorage("tdInfoExpanded") private var infoExpanded = true

    var body: some View {
        let info = engine.gameState.timeDimensions
        DisclosureGroup(isExpanded: $infoExpanded) {
            VStack(spacing: 4) {
                // "You've gained X Tickspeed upgrades from Y Time Shards."
                Text("You've gained \(Text("\(info.totalTickspeedUpgrades)").foregroundStyle(GameColor.eternity)) Tickspeed upgrades from \(Text(info.timeShards).foregroundStyle(GameColor.eternity)) Time Shards.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline.monospacedDigit())

                // "Next upgrade at {threshold}, increasing by {mult}."
                Text("Next upgrade at \(Text(info.upgradeThreshold).foregroundStyle(GameColor.eternity)), increasing by \(Text(info.multPerTickspeed).foregroundStyle(GameColor.eternity)).")
                    .foregroundStyle(.secondary)
                    .font(.caption.monospacedDigit())

                // "You are getting {rate} Time Shards per second."
                Text("You are getting \(Text(info.shardsPerSecond).foregroundStyle(GameColor.eternity)) Time Shards per second.")
                    .foregroundStyle(.secondary)
                    .font(.caption.monospacedDigit())
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
        } label: {
            Text("You've gained \(Text("\(info.totalTickspeedUpgrades)").foregroundStyle(GameColor.eternity)) Tickspeed upgrades.")
                .foregroundStyle(.secondary)
                .font(.subheadline.monospacedDigit())
        }
        .tint(.secondary)
    }
}

// MARK: - Dimension rows

private struct TimeDimensionsRowsSection: View {
    let engine: GameEngine

    var body: some View {
        let info = engine.gameState.timeDimensions
        let realityUnlocked = engine.realityUnlocked
        VStack(spacing: 0) {
            ForEach(info.dimensions) { dim in
                if dim.isUnlocked || dim.requirementReached || dim.tier <= 4 || realityUnlocked {
                    TimeDimensionRow(
                        dim: dim,
                        isEvenRow: dim.tier % 2 == 0,
                        areAutobuyersUnlocked: info.areAutobuyersUnlocked,
                        onBuy: { engine.buyTimeDimension(dim.tier) },
                        onBuyMax: { engine.buyMaxTimeDimension(dim.tier) },
                        onTryUnlock: { engine.tryUnlockTimeDimension(dim.tier) },
                        onToggleAuto: { engine.toggleTimeDimensionAutobuyer(dim.tier) }
                    )
                    .equatable()
                }
            }
        }
    }
}

// MARK: - Individual Row

private struct TimeDimensionRow: View, Equatable {
    let dim: TimeDimensionInfo
    let isEvenRow: Bool
    let areAutobuyersUnlocked: Bool
    let onBuy: () -> Void

    @Environment(\.layoutMetrics) private var metrics
    let onBuyMax: () -> Void
    var onTryUnlock: (() -> Void)? = nil
    var onToggleAuto: (() -> Void)? = nil

    /// Same shape as `InfinityDimensionRow`'s `==`. Closures excluded; `dim`
    /// is `Equatable` and carries every visible per-tick field. Active rows
    /// re-eval each tick; locked rows (TD5-8 pre-Time-Studies) get the skip.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.dim == rhs.dim
            && lhs.isEvenRow == rhs.isEvenRow
            && lhs.areAutobuyersUnlocked == rhs.areAutobuyersUnlocked
    }

    private var rowBackground: Color {
        isEvenRow ? GameColor.eternity.opacity(0.3) : Color.clear
    }

    /// Whether this is a locked TD5-8 that shows the full row layout with TT unlock button
    private var showFullLockedRow: Bool {
        !dim.isUnlocked && dim.ttCost != nil
    }

    var body: some View {
        if dim.isUnlocked || showFullLockedRow {
            fullRow
        } else {
            lockedRow
        }
    }

    // MARK: - Full row (unlocked or locked-with-TT-cost post-Reality)

    private var fullRow: some View {
        HStack(spacing: metrics.isCompact ? 8 : 12) {
            // Name + multiplier (isolated subview — prevents full row redraw on multiplier tick).
            // iPhone uses the full "Nth Time Dimension" name and lets it wrap to two lines —
            // there's enough vertical room and the natural break point is after "Time".
            // On iPhone the label and amount each take an EQUAL share of the row
            // (maxWidth: .infinity) so neither column starves the other. iPad has
            // room, so keep intrinsic widths + the trailing Spacer.
            TDRowLabel(displayName: dim.displayName, multiplier: dim.multiplier)
                .equatable()
                .frame(maxWidth: metrics.isCompact ? .infinity : nil, alignment: .leading)

            // Amount + rate of change (isolated subview — prevents full row redraw on tick)
            DimensionReadout(amount: dim.amount, rateOfChange: dim.rateOfChange)
                .frame(maxWidth: metrics.isCompact ? .infinity : nil, alignment: .leading)

            if !metrics.isCompact { Spacer() }

            // Buy button
            buyButton
                .frame(width: metrics.idBuyButtonWidth)

            // Auto toggle or Buy Max button
            if areAutobuyersUnlocked && dim.isUnlocked {
                autoToggle
                    .frame(width: metrics.idBuyMaxWidth)
            } else {
                buyMaxButton
                    .frame(width: metrics.idBuyMaxWidth)
            }
        }
        .padding(.horizontal, metrics.isCompact ? 6 : 12)
        .padding(.vertical, metrics.isCompact ? 4 : 8)
        .background(rowBackground)
        .opacity(showFullLockedRow && !dim.requirementReached ? 0.5 : 1)
    }

    // MARK: - Locked row (TD5-8 before Reality — no TT cost available)

    private var lockedRow: some View {
        HStack {
            Text(dim.displayName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Text("Requires a Time Study")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, metrics.isCompact ? 6 : 12)
        .padding(.vertical, metrics.isCompact ? 4 : 8)
        .frame(minHeight: metrics.isCompact ? 48 : 64)
        .background(rowBackground)
        .opacity(0.5)
    }

    // MARK: - Buy button

    private var canBuy: Bool {
        if dim.isUnlocked { return dim.isAffordable }
        // Locked TD5-8: tappable when requirement (Time Study) is met
        if dim.ttCost != nil { return dim.requirementReached }
        return false
    }

    private var buyButtonBackground: Color {
        canBuy ? .black : GameColor.disabled
    }

    private var buyButtonBorder: Color {
        canBuy ? GameColor.good : GameColor.disabledBorder
    }

    private var buyButton: some View {
        Button {
            Haptics.tap()
            if dim.isUnlocked {
                onBuy()
            } else {
                onTryUnlock?()
            }
        } label: {
            ZStack {
                buyButtonBackground

                VStack(spacing: 2) {
                    if dim.isUnlocked {
                        if metrics.isCompact {
                            Text("Cost:")
                                .font(.caption2.weight(.semibold))
                            Text("\(dim.cost) EP")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        } else {
                            Text("Cost: \(dim.cost) EP")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .lineLimit(2)
                                .minimumScaleFactor(0.6)
                        }
                    } else if let ttCost = dim.ttCost {
                        Text(ttCost)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                    } else {
                        Text("Requires a Time Study")
                            .font(.caption.weight(.semibold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                    }
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            }
            .frame(height: 48)
            .roundedBorder(buyButtonBorder)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(canBuy)
    }

    // MARK: - Auto toggle (replaces Buy Max when autobuyers unlocked)

    private var autoToggle: some View {
        Toggle(isOn: Binding(
            get: { dim.isAutoActive },
            set: { _ in onToggleAuto?() }
        )) {
            Text("Auto")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white)
        }
        .toggleStyle(.switch)
        .labelsHidden()
        .pausedAwareTint(isActive: dim.isAutoActive, normalColor: GameColor.eternity)
    }

    // MARK: - Buy Max button

    private var buyMaxEnabled: Bool {
        dim.isUnlocked && dim.isAffordable
    }

    private var buyMaxButton: some View {
        Button {
            Haptics.tap()
            onBuyMax()
        } label: {
            ZStack {
                buyMaxEnabled ? Color.black : GameColor.disabled

                Text("Max")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(height: 48)
            .roundedBorder(buyMaxEnabled ? GameColor.good : GameColor.disabledBorder)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(buyMaxEnabled)
    }
}

// MARK: - TD Row Label (isolated to prevent parent re-eval on multiplier tick)

private struct TDRowLabel: View, Equatable {
    let displayName: String
    let multiplier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(displayName)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(multiplier)
                .font(.caption.monospacedDigit())
                .foregroundStyle(GameColor.eternity)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}
