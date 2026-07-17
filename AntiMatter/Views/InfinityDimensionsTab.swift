//
//  InfinityDimensionsTab.swift
//  AntiMatter
//
//  Infinity Dimensions — 8 tiers that cost Infinity Points and produce
//  Infinity Power, which multiplies all Antimatter Dimensions.
//  Layout mirrors AntimatterDimensionsTab / DimensionRow for visual parity.
//

import SwiftUI

struct InfinityDimensionsTab: View {
    let engine: GameEngine

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    InfinityDimensionsHeaderRow(engine: engine)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)

                    InfinityDimensionsTesseractCard(engine: engine)

                    InfinityDimensionsInfoSection(engine: engine)
                        .padding(.horizontal)
                        .padding(.bottom, 6)

                    InfinityDimensionsRowsSection(engine: engine)

                    InfinityDimensionsLongPressHint(engine: engine)

                    PhoneTabBarSpacer()
                }
            }
        }
    }
}

// MARK: - Header row: [Toggle all autobuyers] [Spacer] [Max All]

/// Thin reader: pulls the two stable bools out of `gameState.infinityDimensions`
/// and hands them to an Equatable inner. Per-tick body work is trivial struct
/// initialization; the inner's `HStack` + two `GameButton` modifier chains are
/// preserved across ticks via `.equatable()`.
private struct InfinityDimensionsHeaderRow: View {
    let engine: GameEngine

    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        let info = engine.gameState.infinityDimensions
        InfinityDimensionsHeaderRowInner(
            isCompact: metrics.isCompact,
            headerButtonWidth: metrics.headerButtonWidth,
            showAutoButton: info.isAnyAutobuyerUnlocked && !info.isEC8Running,
            engine: engine
        ).equatable()
    }
}

private struct InfinityDimensionsHeaderRowInner: View, Equatable {
    let isCompact: Bool
    let headerButtonWidth: CGFloat
    let showAutoButton: Bool
    let engine: GameEngine

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isCompact == rhs.isCompact
            && lhs.headerButtonWidth == rhs.headerButtonWidth
            && lhs.showAutoButton == rhs.showAutoButton
    }

    var body: some View {
        HStack {
            if showAutoButton {
                GameButton(borderColor: .green) {
                    engine.toggleAllInfinityDimAutobuyers()
                } label: {
                    Text("Toggle all autobuyers")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                }
                .frame(width: isCompact ? 160 : 190, height: 30)
            }

            Spacer()

            GameButton(borderColor: .green) {
                engine.maxAllInfinityDimensions()
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

// MARK: - Tesseract card
//
// Post-completion reward for The Nameless Ones' Reality — a Tesseract
// button that raises Infinity Dimension caps. Gated on
// `engine.enslavedCompleted` (always-polled mirror of `Enslaved.isCompleted`).

private struct InfinityDimensionsTesseractCard: View {
    let engine: GameEngine

    var body: some View {
        if engine.enslavedCompleted {
            InfinityDimensionsTesseractCardInner(
                tess: engine.gameState.infinityDimensions.tesseracts,
                engine: engine
            ).equatable()
        }
    }
}

/// Equatable on the full `TesseractInfo` (synthesized field-by-field). The
/// only field that flickers per tick is `canBuy` (toggles when IP crosses
/// `nextCost`); the others change only on tesseract purchase. Body skips
/// when nothing differs.
private struct InfinityDimensionsTesseractCardInner: View, Equatable {
    let tess: TesseractInfo
    let engine: GameEngine

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.tess == rhs.tess
    }

    var body: some View {
        let extraText = tess.extra > 0 ? " + \(tess.extra) extra" : ""
        GameButton(theme: .enslaved, isEnabled: tess.canBuy) {
            engine.buyTesseract()
        } label: {
            VStack(spacing: 4) {
                Text("Buy a Tesseract (\(tess.bought)\(extraText))")
                    .font(.subheadline.weight(.semibold))
                Text("Costs: \(tess.nextCost) IP")
                    .font(.caption.weight(.medium))
                HStack(spacing: 16) {
                    Text("+\(tess.nextCapIncrease) to caps")
                        .font(.caption2)
                    Text("Current total: \(tess.totalCap)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
}

// MARK: - Info text section (matches web ModernInfinityDimensionsTab.vue)

private struct InfinityDimensionsInfoSection: View {
    let engine: GameEngine

    @AppStorage("idInfoExpanded") private var infoExpanded = true

    var body: some View {
        let info = engine.gameState.infinityDimensions
        DisclosureGroup(isExpanded: $infoExpanded) {
            VStack(spacing: 4) {
                // "You have {power} Infinity Power,"
                Text("You have \(Text(info.infinityPower).foregroundStyle(GameColor.infinity)) Infinity Power,")
                    .foregroundStyle(.secondary)
                    .font(.subheadline.monospacedDigit())

                // "increased by {^rate} to a {×mult} multiplier on all Antimatter Dimensions."
                Text("increased by \(Text("^\(info.conversionRate)").foregroundStyle(GameColor.infinity)) to a \(Text(info.powerMultiplier).foregroundStyle(GameColor.infinity)) multiplier on all ADs.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline.monospacedDigit())

                // "All Infinity Dimensions except for the 8th are limited to a maximum of {cap} purchases each."
                Text("All IDs except the 8th are limited to \(info.totalDimCap) purchases each.")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                // "You are getting {rate} Infinity Power per second."
                Text("You are getting \(info.powerPerSecond) Infinity Power per second.")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
        } label: {
            Text("Infinity Power: \(Text(info.powerMultiplier).foregroundStyle(GameColor.infinity)) multiplier on all ADs.")
                .foregroundStyle(.secondary)
                .font(.subheadline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .tint(.secondary)
    }
}

// MARK: - Dimension rows

private struct InfinityDimensionsRowsSection: View {
    let engine: GameEngine

    var body: some View {
        let info = engine.gameState.infinityDimensions
        VStack(spacing: 0) {
            ForEach(info.dimensions) { dim in
                if dim.showRow || info.eternityReached {
                    InfinityDimensionRow(
                        dim: dim,
                        isEvenRow: dim.tier % 2 == 0,
                        isEC8Running: info.isEC8Running,
                        onBuy: { engine.buyInfinityDimension(dim.tier) },
                        onBuyMax: { engine.buyMaxInfinityDimension(dim.tier) },
                        onToggleAuto: { engine.toggleInfinityDimAutobuyer(dim.tier) }
                    )
                    .equatable()
                }
            }
        }
    }
}

// MARK: - Long-press hint

private struct InfinityDimensionsLongPressHint: View {
    let engine: GameEngine

    var body: some View {
        let dims = engine.gameState.infinityDimensions.dimensions
        InfinityDimensionsLongPressHintInner(
            visible: !(dims.last?.isUnlocked ?? true)
        ).equatable()
    }
}

/// Equatable on a single bool — the hint either renders or doesn't, and the
/// transition fires once when ID8 unlocks. Skips body every other tick.
private struct InfinityDimensionsLongPressHintInner: View, Equatable {
    let visible: Bool

    var body: some View {
        if visible {
            Text("Long press a locked row to see its Infinity Point cost.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
                .padding(.horizontal)
        }
    }
}

// MARK: - Individual Row

private struct InfinityDimensionRow: View, Equatable {
    let dim: InfinityDimState
    let isEvenRow: Bool
    let isEC8Running: Bool
    let onBuy: () -> Void
    let onBuyMax: () -> Void
    let onToggleAuto: () -> Void

    @Environment(\.layoutMetrics) private var metrics

    /// Closures excluded — they capture stable engine references. `dim` is
    /// `Equatable` (synthesized); all volatile-per-tick fields (amount,
    /// multiplier, rate, cost, isAffordable) live inside it. The big win is
    /// for **locked** rows pre-IP-unlock, where every field is stable and
    /// 7 of 8 rows can skip body — the rate readout doesn't render in that
    /// branch, and the cost text isn't shown until the long-press reveal.
    /// For active unlocked rows, `dim` differs each tick and body runs.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.dim == rhs.dim
            && lhs.isEvenRow == rhs.isEvenRow
            && lhs.isEC8Running == rhs.isEC8Running
    }

    /// Whether to show the autobuyer toggle instead of Buy Max
    private var showAutoToggle: Bool {
        dim.isAutobuyerUnlocked && !isEC8Running
    }

    @State private var showCost = false

    private var isLocked: Bool {
        !dim.isUnlocked && !dim.canUnlock && !dim.amRequirementReached
    }

    /// Whether to display the IP cost instead of the AM requirement (long-press reveal)
    private var revealCost: Bool {
        showCost && !dim.isUnlocked && !dim.canUnlock
    }

    private var rowBackground: Color {
        isEvenRow ? GameColor.infinity.opacity(0.3) : Color.clear
    }

    var body: some View {
        if isLocked {
            lockedRow
        } else {
            unlockedRow
        }
    }

    // MARK: - Unlocked / visible row

    private var unlockedRow: some View {
        HStack(spacing: metrics.isCompact ? 8 : 12) {
            // Name + multiplier (isolated subview — prevents full row redraw on multiplier tick).
            // iPhone uses the full "Nth Infinity Dimension" name and lets it wrap to two lines —
            // there's enough vertical room and the natural break point is after "Infinity".
            // On iPhone the label and amount each take an EQUAL share of the row
            // (maxWidth: .infinity) so neither column starves the other — a long
            // amount no longer blows away the name/multiplier label and vice versa.
            // iPad has room, so keep intrinsic widths + the trailing Spacer.
            IDRowLabel(displayName: dim.displayName, multiplier: dim.isUnlocked ? dim.multiplier : nil)
                .equatable()
                .frame(maxWidth: metrics.isCompact ? .infinity : nil, alignment: .leading)

            // Amount + rate of change (isolated subview — prevents full row redraw on tick)
            if dim.isUnlocked {
                DimensionReadout(amount: dim.amount, rateOfChange: dim.rateOfChange)
                    .frame(maxWidth: metrics.isCompact ? .infinity : nil, alignment: .leading)
            }

            if !metrics.isCompact { Spacer() }

            // Buy button
            buyButton
                .frame(width: metrics.idBuyButtonWidth)

            // Auto toggle or Buy Max button
            if showAutoToggle {
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
    }

    // MARK: - Locked row

    private var lockedRow: some View {
        HStack {
            Text(dim.displayName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Text(revealCost ? "Cost: \(dim.cost) IP" : "Reach \(dim.amRequirement) AM")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, metrics.isCompact ? 6 : 12)
        .padding(.vertical, metrics.isCompact ? 4 : 8)
        .frame(minHeight: metrics.isCompact ? 48 : 64)
        .background(rowBackground)
        .opacity(0.5)
        .onLongPressGesture(minimumDuration: 0.3) {
            showCost.toggle()
        }
    }

    // MARK: - Buy button (ZStack style matching DimensionRow)

    /// Can purchase: unlocked, available (not blocked by EC2/EC10), affordable, and not capped
    private var canBuy: Bool {
        dim.isUnlocked && dim.isAvailableForPurchase && dim.isAffordable && !dim.isCapped
    }

    /// Can unlock: meets AM + IP requirements, but only relevant if not already unlocked
    private var canUnlock: Bool {
        !dim.isUnlocked && dim.canUnlock
    }

    /// Green (active) when the player can actually do something; disabled otherwise
    private var buyButtonBackground: Color {
        if dim.isCapped { return GameColor.sidebarBackground }
        if canBuy || canUnlock { return .black }
        return GameColor.disabled
    }

    private var buyButtonBorder: Color {
        if canBuy || canUnlock { return GameColor.good }
        return GameColor.disabledBorder
    }

    /// Cost line for the buy button. On iPhone it breaks deterministically into
    /// two lines ("Cost:" / "<value> IP") so a long cost reads cleanly in the
    /// narrow button; on iPad it stays a single line.
    @ViewBuilder
    private func costReadout(_ cost: String) -> some View {
        if metrics.isCompact {
            Text("Cost:")
                .font(.caption2.weight(.semibold))
            Text("\(cost) IP")
                .font(.caption.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        } else {
            Text("Cost: \(cost) IP")
                .font(.caption.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private var buyButton: some View {
        Button {
            Haptics.tap()
            onBuy()
        } label: {
            ZStack {
                buyButtonBackground

                VStack(spacing: 2) {
                    if dim.isCapped {
                        Text("Capped")
                            .font(.caption.weight(.semibold))
                    } else if dim.isUnlocked {
                        costReadout(dim.cost)
                    } else if dim.canUnlock {
                        Text("Unlock")
                            .font(.caption.weight(.semibold))
                        Text("Cost: \(dim.cost) IP")
                            .font(.caption2.monospacedDigit())
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                    } else if revealCost {
                        costReadout(dim.cost)
                    } else {
                        Text("Reach \(dim.amRequirement) AM")
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
        .allowsHitTesting(canBuy || canUnlock)
        .onLongPressGesture(minimumDuration: 0.3) {
            if !dim.isUnlocked && !dim.canUnlock {
                showCost.toggle()
            }
        }
    }

    // MARK: - Auto toggle

    private var autoToggle: some View {
        VStack(spacing: 2) {
            Text("Auto:")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Toggle("", isOn: Binding(
                get: { dim.isAutobuyerActive },
                set: { _ in onToggleAuto() }
            ))
            .labelsHidden()
            .scaleEffect(0.7)
            .pausedAwareTint(isActive: dim.isAutobuyerActive)
        }
    }

    // MARK: - Buy Max button

    private var buyMaxEnabled: Bool {
        dim.isUnlocked && dim.isAvailableForPurchase && !dim.isCapped && dim.isAffordable
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

// MARK: - ID Row Label (isolated to prevent parent re-eval on multiplier tick)

private struct IDRowLabel: View, Equatable {
    let displayName: String
    let multiplier: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(displayName)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            if let multiplier {
                Text(multiplier)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(GameColor.infinity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }
}
