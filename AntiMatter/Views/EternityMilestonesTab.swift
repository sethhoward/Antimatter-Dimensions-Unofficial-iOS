//
//  EternityMilestonesTab.swift
//  AntiMatter
//
//  Eternity Milestones — progressive unlocks based on total Eternities.
//  Layout: header with eternity count, 3-column grid of milestones.
//

import SwiftUI

struct EternityMilestonesTab: View {
    let engine: GameEngine

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if engine.pelleDoomed {
                    PelleSimpleDisabledBanner(
                        text: "Eternity Milestone rewards are disabled while Doomed."
                    )
                    .padding(.horizontal, 12)
                }
                EternityMilestonesHeader(engine: engine)
                EternityMilestonesGrid(engine: engine)
                PhoneTabBarSpacer()
            }
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Header (eternity count)

private struct EternityMilestonesHeader: View {
    let engine: GameEngine

    var body: some View {
        EternityMilestonesHeaderInner(
            count: engine.gameState.eternity.eternityCount
        ).equatable()
    }
}

/// Equatable on the eternity count string. Only changes on Eternity, so
/// this body skips every other tick.
private struct EternityMilestonesHeaderInner: View, Equatable {
    let count: String

    var body: some View {
        Text("You have \(Text(count).foregroundStyle(GameColor.eternity))\(count == "1" ? " Eternity." : " Eternities.")")
            .foregroundStyle(.secondary)
            .font(.title3.weight(.medium).monospacedDigit())
            .padding(.top, 8)
    }
}

// MARK: - Milestone grid

private struct EternityMilestonesGrid: View {
    let engine: GameEngine
    @Environment(\.layoutMetrics) private var metrics

    private static let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    /// Tallest measured card height — applied uniformly so the grid is a
    /// clean rectangle instead of a ragged staircase.
    @State private var maxCardHeight: CGFloat = 90

    /// Milestone whose "active condition" explainer sheet is open, if any.
    /// Lifted here (rather than per-card `@State`) so there's a single `.sheet`
    /// modifier instead of one per card.
    @State private var infoMilestone: EternityMilestoneInfo?

    var body: some View {
        let milestones = engine.gameState.eternity.milestones
        LazyVGrid(columns: Self.columns, spacing: 8) {
            ForEach(milestones) { milestone in
                MilestoneCard(
                    milestone: milestone,
                    isPelleDoomed: engine.pelleDoomed,
                    uniformHeight: maxCardHeight,
                    onInfo: { infoMilestone = $0 }
                )
                .equatable()
            }
        }
        .padding(.horizontal, metrics.contentHPadding)
        .onPreferenceChange(EqualHeightKey.self) { newMax in
            if newMax > maxCardHeight { maxCardHeight = newMax }
        }
        .sheet(item: $infoMilestone) { milestone in
            MilestoneActiveConditionSheet(milestone: milestone)
        }
    }
}

// MARK: - Individual milestone card

private struct MilestoneCard: View, Equatable {
    let milestone: EternityMilestoneInfo
    var isPelleDoomed: Bool = false
    /// Height to apply uniformly across every card so the grid is rectangular.
    /// 0 falls back to natural sizing on the first layout pass; subsequent
    /// passes use the measured max from the shared `EqualHeightKey` (see
    /// `Helpers/EqualHeightGrid.swift`).
    var uniformHeight: CGFloat = 0
    /// Tapping the info button (shown only when `milestone.activeCondition` is
    /// non-empty) requests the explainer sheet. Excluded from `==` — it captures
    /// a stable parent reference, same convention as other Equatable views.
    var onInfo: (EternityMilestoneInfo) -> Void = { _ in }

    /// All inputs are transition-only — `milestone` only changes when its
    /// `isReached` flips on a new Eternity, `isPelleDoomed` only on Doom
    /// transitions, `uniformHeight` only on layout pass. `onInfo` is a stable
    /// closure and deliberately not compared.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.milestone == rhs.milestone
            && lhs.isPelleDoomed == rhs.isPelleDoomed
            && lhs.uniformHeight == rhs.uniformHeight
    }

    /// Whether this milestone exposes a web `activeCondition` tooltip — i.e. one
    /// of the three offline milestones whose reward can read "(Inactive)".
    private var hasInfo: Bool { !milestone.activeCondition.isEmpty }

    /// True only when the player is doomed AND this specific milestone is
    /// `pelleUseless` per its JS config. ~17 of 25 milestones are flagged
    /// useless (autobuyer unlocks, replicanti milestones, infinity-related);
    /// the rest (`keepAutobuyers`, `bigCrunchModes`, `autoEP`,
    /// `autobuyMaxGalaxies`, `autoUnlockID`, `unlockAllND`,
    /// `autobuyerEternity`) still apply in doom and stay un-struck.
    /// Mirrors web `EternityMilestoneButton.vue:43`'s `isUseless`.
    private var isUselessInDoom: Bool { isPelleDoomed && milestone.pelleUseless }

    private var borderColor: Color {
        if isUselessInDoom { return GameColor.pelle }
        return milestone.isReached ? GameColor.eternity : GameColor.disabledBorder
    }

    private var bgColor: Color {
        milestone.isReached ? GameColor.eternity.opacity(0.15) : GameColor.sidebarBackground
    }

    var body: some View {
        VStack(spacing: 6) {
            // Strikethrough only on milestones marked `pelleUseless` in the
            // JS config — milestones that remain useful in doom keep normal
            // styling. Pre-doom: `isUselessInDoom == false` → no change.
            Text("\(milestone.eternities) \(milestone.eternities == 1 ? "Eternity" : "Eternities"):")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(milestone.isReached ? GameColor.eternity : .secondary)
                .strikethrough(isUselessInDoom)

            // Reward text — let it wrap freely so iPhone-narrow cards don't
            // truncate the descriptions. minHeight keeps short rewards from
            // collapsing the card.
            Text(milestone.reward)
                .font(.caption2)
                .foregroundStyle(milestone.isReached ? .white : .secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .strikethrough(isUselessInDoom)
        }
        .padding(8)
        .equalHeightFrame(uniformHeight, min: 90)
        .background(bgColor)
        .roundedBorder(borderColor)
        .overlay(alignment: .bottomTrailing) {
            // Non-interactive cue — the whole card is the tap target (below).
            if hasInfo {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(GameColor.eternity)
                    .padding(6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if hasInfo { onInfo(milestone) }
        }
        .accessibilityAddTraits(hasInfo ? .isButton : [])
        .accessibilityHint(hasInfo ? "Explains what Inactive means" : "")
        // Height equalization uses the shared EqualHeightGrid helper
        // (`.publishEqualHeight()`), which supersedes main's older
        // `MilestoneMaxHeightKey` GeometryReader. Keep this last so it
        // measures the card after the overlay/tap modifiers are applied.
        .publishEqualHeight()
    }
}

// MARK: - "Active condition" explainer sheet

/// Surfaces the web `activeCondition` tooltip for the three offline milestones,
/// prefaced with a plain-language explanation of the "(Inactive)" label. The
/// reward text on these cards is a live preview of what you'd gain if you went
/// offline right now — it reads "(Inactive)" when the conditions below aren't
/// currently met. The condition string itself is `config.activeCondition()`
/// from `eternity-milestones.js`, polled into `EternityMilestoneInfo`.
private struct MilestoneActiveConditionSheet: View {
    let milestone: EternityMilestoneInfo
    @Environment(\.dismiss) private var dismiss

    private var title: String {
        "\(milestone.eternities) \(milestone.eternities == 1 ? "Eternity" : "Eternities")"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("The amount shown on this milestone is a live preview of what you'd gain if you went offline right now. It reads **(Inactive)** when the conditions below aren't currently met — so closing the game in your current state would gain nothing from this milestone.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("To be active")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(GameColor.eternity)
                        Text(milestone.activeCondition)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .adaptiveSheetTitle(title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
