//
//  DimBoostRow.swift
//  AntiMatter
//
//  Dimension Boost row — mirrors ClassicDimensionBoostRow.vue.
//

import SwiftUI

struct DimBoostRow: View {
    let dimBoost: DimBoostState
    let onBuy: () -> Void

    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        let isCompact = metrics.isCompact
        VStack(spacing: isCompact ? 0 : 8) {
            DimBoostHeader(dimBoost: dimBoost)
                .equatable()
            DimBoostActionButton(dimBoost: dimBoost, onBuy: onBuy)
                .equatable()
                .padding(.vertical, isCompact ? -2 : 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, isCompact ? 0 : 4)
    }
}

/// Title + requirement label for the Dim Boost row. Equatable on the
/// two primitives it actually displays — `purchasedBoosts` and
/// `requirementText` — so the body can skip when the parent re-evaluates
/// for unrelated reasons (e.g. `isSatisfied` flickering at the antimatter
/// requirement threshold).
struct DimBoostHeader: View, Equatable {
    let purchasedBoosts: Int
    let requirementText: String
    @Environment(\.layoutMetrics) private var metrics

    /// Convenience for callers holding a `DimBoostState`.
    init(dimBoost: DimBoostState) {
        self.purchasedBoosts = dimBoost.purchasedBoosts
        self.requirementText = dimBoost.requirementText
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.purchasedBoosts == rhs.purchasedBoosts
            && lhs.requirementText == rhs.requirementText
    }

    var body: some View {
        if metrics.isCompact {
            // CATextLayer renderer — bypasses SwiftUI ResolvedTextFilter
            // for the 30Hz `requirementText` churn.
            PrestigeActionHeaderRenderer(
                title: "Dimension Boost",
                subtitle: "\(purchasedBoosts)",
                requirement: requirementText
            )
        } else {
            VStack(spacing: 4) {
                Text("Dimension Boost (\(purchasedBoosts))")
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(requirementText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Action button for Dim Boost — extracted alongside DimBoostHeader so
/// iPhone's prestige layout can place buttons in their own 50/50 row,
/// keeping the quick-reset button confined to the label area above.
/// Equatable on the full `DimBoostState` (closure excluded — `engine` is a
/// stable reference). Cares about most fields (`canBeBought`,
/// `isSatisfied`, `lockText`, `unlockedByBoost`), so the synthesized-style
/// `==` is the right granularity.
struct DimBoostActionButton: View, Equatable {
    let dimBoost: DimBoostState
    let onBuy: () -> Void
    @Environment(\.layoutMetrics) private var metrics

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.dimBoost == rhs.dimBoost
    }

    private var canBuy: Bool { dimBoost.canBeBought && dimBoost.isSatisfied }

    var body: some View {
        let isCompact = metrics.isCompact
        GameButton(borderColor: .green, isEnabled: canBuy) {
            onBuy()
        } label: {
            Group {
                if let lockText = dimBoost.lockText {
                    Text(lockText)
                } else if let desc = dimBoost.unlockedByBoost {
                    Text(desc)
                } else {
                    Text(isCompact ? "Reset Dimensions" : "Reset your Dimensions for a boost")
                }
            }
            .font(isCompact ? .caption : .subheadline)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, isCompact ? 8 : 12)
            .padding(.vertical, isCompact ? 10 : 10)
            // HIG-minimum 44pt tap target on iPhone. Single-line
            // variants ("Unlock the 8th Dimension", "Reset Dimensions")
            // collapse to ~22pt without this and are awkward to hit.
            .frame(minHeight: isCompact ? 44 : 0)
        }
    }
}
