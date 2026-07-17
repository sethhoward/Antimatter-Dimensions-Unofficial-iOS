//
//  GalaxyRow.swift
//  AntiMatter
//
//  Antimatter Galaxy row — mirrors ClassicAntimatterGalaxyRow.vue.
//

import SwiftUI

struct GalaxyRow: View {
    let galaxy: GalaxyState
    let onBuy: () -> Void

    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        let isCompact = metrics.isCompact
        VStack(spacing: isCompact ? 0 : 8) {
            GalaxyHeader(galaxy: galaxy)
                .equatable()
            GalaxyActionButton(galaxy: galaxy, onBuy: onBuy)
                .equatable()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, isCompact ? 2 : 4)
    }
}

/// Title + requirement label for Galaxy. Equatable on the three
/// primitives it displays so it can skip body when the parent re-evals
/// for unrelated GalaxyState changes (e.g. `isSatisfied` flickering at
/// the antimatter requirement threshold).
struct GalaxyHeader: View, Equatable {
    let typeName: String
    let countDisplay: String
    let requirementText: String
    @Environment(\.layoutMetrics) private var metrics

    /// Convenience for callers holding a `GalaxyState`.
    init(galaxy: GalaxyState) {
        self.typeName = galaxy.typeName
        self.countDisplay = galaxy.countDisplay
        self.requirementText = galaxy.requirementText
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.typeName == rhs.typeName
            && lhs.countDisplay == rhs.countDisplay
            && lhs.requirementText == rhs.requirementText
    }

    var body: some View {
        if metrics.isCompact {
            // iPhone: count breakdown ("100 + 40 = 140") gets its own line below
            // the title — gets long once Replicanti / Tachyon galaxies join in,
            // and the type name itself grows to "Distant Antimatter Galaxies".
            // Strip "Antimatter" on iPhone to keep the title narrow ("Galaxies"
            // / "Distant Galaxies" / "Remote Galaxies"). The leading-space form
            // covers "Distant Antimatter Galaxies" / "Remote Antimatter Galaxies";
            // the trailing-space form covers the bare "Antimatter Galaxies".
            PrestigeActionHeaderRenderer(
                title: typeName
                    .replacingOccurrences(of: " Antimatter", with: ""),
                subtitle: countDisplay,
                requirement: requirementText
            )
        } else {
            VStack(spacing: 4) {
                Text("\(typeName) (\(countDisplay))")
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

/// Galaxy action button — paired with GalaxyHeader so iPhone can split
/// the prestige row into a header row (with quick-reset between) and a
/// 50/50 button row below. Equatable on the full `GalaxyState` (the
/// closure is excluded — `engine` is a stable reference).
struct GalaxyActionButton: View, Equatable {
    let galaxy: GalaxyState
    let onBuy: () -> Void
    @Environment(\.layoutMetrics) private var metrics

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.galaxy == rhs.galaxy
    }

    private var canBuy: Bool { galaxy.canBeBought && galaxy.isSatisfied }

    var body: some View {
        let isCompact = metrics.isCompact
        GameButton(borderColor: .green, isEnabled: canBuy) {
            onBuy()
        } label: {
            Group {
                if let lockText = galaxy.lockText {
                    Text(lockText)
                } else {
                    Text(isCompact ? "Reset Dimensions and Boosts to increase the power of Tickspeed upgrades" : "Reset your Dimensions and Dimension Boosts to increase the power of Tickspeed upgrades")
                }
            }
            .font(isCompact ? .caption : .subheadline)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, isCompact ? 8 : 12)
            .padding(.vertical, isCompact ? 7 : 10)
            // HIG-minimum 44pt tap target on iPhone — match
            // DimBoostActionButton so the two side-by-side buttons have
            // a consistent baseline height even when one's label
            // happens to be single-line.
            .frame(minHeight: isCompact ? 44 : 0)
        }
    }
}
