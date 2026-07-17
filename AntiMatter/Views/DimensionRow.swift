//
//  DimensionRow.swift
//  AntiMatter
//
//  Single antimatter dimension row — mirrors ModernAntimatterDimensionRow.vue.
//  Single buy button per row with progress fill showing boughtBefore10 and howManyCanBuy.
//

import SwiftUI

struct DimensionRow: View {
    let dimension: DimensionState
    let buyUntil10: Bool
    let isEvenRow: Bool
    /// When true, the buy button renders "Continuum: X,XXX.XX" instead of
    /// the regular "Buy N / Cost" progress button. Driven by
    /// `engine.continuumUnlocked && !engine.continuumDisabled` — pushed in by
    /// the parent so DimensionRow doesn't need to observe GameEngine directly.
    var continuumActive: Bool = false
    let onBuy: () -> Void

    @Environment(\.layoutMetrics) private var metrics

    // Locked = not available for purchase (matches web's isUnlocked = isAvailableForPurchase)
    private var isLocked: Bool { !dimension.isAvailableForPurchase }

    // Even rows get the alternating reddish tint (#df50504d — web uses 30% opacity)
    private var rowBackground: Color {
        isEvenRow ? GameColor.antimatter.opacity(0.3) : Color.clear
    }

    var body: some View {
        HStack(spacing: 12) {
            // Tier name + multiplier — left column
            DimensionLabel(name: metrics.isCompact ? dimension.shortDisplayName : dimension.displayName,
                          multiplier: dimension.multiplier)

            // Amount + rate of change — immediately after title.
            DimensionReadout(amount: dimension.amount, rateOfChange: dimension.rateOfChange)

            Spacer()

            // Buy button — fixed width right column. Swaps to a Continuum
            // readout when Lai'tela's Continuum is active.
            if continuumActive {
                ContinuumReadoutButton(value: dimension.continuumValue)
                    .frame(width: metrics.dimensionBuyButtonWidth)
            } else {
                DimensionBuyButton(
                    isLocked: isLocked,
                    isAffordable: dimension.isAffordable,
                    isAvailableForPurchase: dimension.isAvailableForPurchase,
                    boughtBefore10: dimension.boughtBefore10,
                    howManyCanBuy: dimension.howManyCanBuy,
                    singleCost: dimension.singleCost,
                    until10Cost: dimension.until10Cost,
                    costSuffix: dimension.costSuffix,
                    buyUntil10: buyUntil10,
                    isCompact: metrics.isCompact,
                    onBuy: onBuy
                )
                .frame(width: metrics.dimensionBuyButtonWidth)
            }
        }
        .padding(.horizontal, metrics.isCompact ? 6 : 12)
        .padding(.vertical, metrics.isCompact ? 4 : 8)
        .background(rowBackground)
        .opacity(isLocked ? 0.5 : 1.0)
    }
}

// MARK: - Subviews (isolate high-frequency redraws)

/// Static label — only redraws when tier name or multiplier changes.
private struct DimensionLabel: View {
    let name: String
    let multiplier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(multiplier)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

/// Amount + rate readout — isolated so text formatting doesn't trigger parent layout.
/// Shared across AD, ID, and TD row views.
struct DimensionReadout: View {
    let amount: String
    let rateOfChange: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(amount)
                .font(.system(.subheadline, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let roc = rateOfChange {
                Text("(+\(roc)%/s)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
    }
}

/// Buy button with progress fill — isolated so GeometryReader only re-evaluates
/// when buy-relevant state changes, not on every amount/rate tick.
private struct DimensionBuyButton: View {
    let isLocked: Bool
    let isAffordable: Bool
    let isAvailableForPurchase: Bool
    let boughtBefore10: Int
    let howManyCanBuy: Int
    let singleCost: String
    let until10Cost: String
    let costSuffix: String
    let buyUntil10: Bool
    var isCompact: Bool = false
    let onBuy: () -> Void

    private var canAfford: Bool { isAffordable && !isLocked }

    private var borderColor: Color {
        canAfford ? GameColor.good : GameColor.disabledBorder
    }

    var body: some View {
        let cost = buyUntil10 ? until10Cost : singleCost

        Button {
            onBuy()
        } label: {
            Canvas { ctx, size in
                let rect = CGRect(origin: .zero, size: size)

                // Background
                if canAfford {
                    ctx.fill(Path(rect), with: .color(.black))
                    let canBuyFrac = min(CGFloat(boughtBefore10 + howManyCanBuy), 10) / 10
                    let boughtFrac = CGFloat(boughtBefore10) / 10
                    // Dark green: bought + can buy range
                    ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width * canBuyFrac, height: size.height)),
                             with: .color(GameColor.goodDark))
                    // Bright green: already bought range
                    if boughtFrac > 0 {
                        ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width * boughtFrac, height: size.height)),
                                 with: .color(GameColor.good))
                    }
                } else if isLocked {
                    ctx.fill(Path(rect), with: .color(GameColor.sidebarBackground))
                } else {
                    ctx.fill(Path(rect), with: .color(GameColor.disabled))
                }

                // Text
                let topText: Text
                let bottomText: Text
                if isLocked {
                    topText = Text("Locked").font(.caption.weight(.semibold)).foregroundStyle(.white)
                    bottomText = Text("Cost: \(singleCost) \(costSuffix)").font(.caption2.monospacedDigit()).foregroundStyle(.white)
                } else {
                    topText = Text("Buy \(howManyCanBuy)").font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.white)
                    bottomText = Text("Cost: \(cost) \(costSuffix)").font(.caption2.monospacedDigit()).foregroundStyle(.white)
                }
                let spacing: CGFloat = isCompact ? 1 : 2
                let resolvedTop = ctx.resolve(topText)
                let resolvedBottom = ctx.resolve(bottomText)
                let topSize = resolvedTop.measure(in: size)
                let bottomSize = resolvedBottom.measure(in: size)
                let totalH = topSize.height + spacing + bottomSize.height
                let startY = (size.height - totalH) / 2
                ctx.draw(resolvedTop, at: CGPoint(x: size.width / 2, y: startY + topSize.height / 2), anchor: .center)
                ctx.draw(resolvedBottom, at: CGPoint(x: size.width / 2, y: startY + topSize.height + spacing + bottomSize.height / 2), anchor: .center)
            }
            .frame(height: isCompact ? 36 : 48)
            .roundedBorder(borderColor)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(isAffordable && isAvailableForPurchase && !isLocked)
    }
}

/// Replacement for `DimensionBuyButton` shown while Lai'tela's Continuum is
/// active: a non-interactive "Continuum: X,XXX.XX" tile. Matches web
/// `ModernAntimatterDimensionRow.vue` — the continuum count replaces the
/// buy button entirely.
struct ContinuumReadoutButton: View {
    let value: Double
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        VStack(spacing: 2) {
            Text("Continuum:")
                .font(metrics.isCompact ? .caption2.weight(.medium) : .caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.75))
            Text(ContinuumReadoutButton.formatter.string(from: NSNumber(value: value)) ?? "0")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: metrics.isCompact ? 36 : 48)
        .background(.black, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(GameColor.good, lineWidth: 1)
        )
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
