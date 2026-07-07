//
//  ChallengeControls.swift
//  AntiMatter
//
//  Shared UI components used across Normal, Infinity, and Eternity challenge tabs.
//

import SwiftUI

// MARK: - Restart / Exit Buttons

/// Restart and Exit buttons shown when a challenge is active.
struct ChallengeActionButtons: View {
    let engine: GameEngine
    @Environment(\.sidebarState) private var sidebar

    var body: some View {
        HStack(spacing: 12) {
            GameButton(borderColor: .orange) {
                engine.restartChallenge()
                sidebar?.selectSubtabIfAuto(.antimatterDimensions, in: .dimensions, engine: engine)
            } label: {
                Label("Restart", systemImage: "arrow.counterclockwise")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }

            GameButton(borderColor: .red) {
                engine.exitChallenge()
                sidebar?.selectSubtabIfAuto(.antimatterDimensions, in: .dimensions, engine: engine)
            } label: {
                Label("Exit Challenge", systemImage: "xmark.circle")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Reward Effect Label (isolated to prevent parent re-layout on tick)

/// Isolates the rapidly-changing effect value so parent card layout stays
/// stable. Synthesized `Equatable` — when an EC reward's effect text is
/// static (e.g. "+25% per Replicanti Galaxy" with a galaxy count that
/// hasn't changed this tick), `==` returns true and body is skipped.
private struct RewardEffectLabel: View, Equatable {
    let effect: String

    var body: some View {
        // No line limit / fixed height — long or localized effect text wraps
        // and grows the card (grid equalizes height) instead of truncating.
        Text("Currently: \(effect)")
            .font(.caption2.weight(.medium).monospacedDigit())
            .foregroundStyle(.yellow.opacity(0.8))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Retry Toggle

/// Checkbox toggle for "Automatically retry challenges".
struct ChallengeRetryToggle: View {
    let isRetrying: Bool
    let accentColor: Color
    let onToggle: () -> Void

    var body: some View {
        Button {
            onToggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isRetrying ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isRetrying ? accentColor : .white.opacity(0.5))
                Text("Automatically retry challenges")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Status Badge

/// Running/Completed indicator shown in challenge card headers.
/// `Equatable` (synthesized via custom ==) — both inputs are transition-only
/// bools, so this skips body whenever the parent re-evaluates without an
/// actual challenge state change. Used by NC/IC/EC tabs.
struct ChallengeStatusBadge: View, Equatable {
    let isRunning: Bool
    let isCompleted: Bool
    var accentColor: Color = .blue

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isRunning == rhs.isRunning
            && lhs.isCompleted == rhs.isCompleted
            && lhs.accentColor == rhs.accentColor
    }

    var body: some View {
        if isRunning {
            Text("Running")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(accentColor)
                .clipShape(Capsule())
        } else if isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.body)
        }
    }
}

// MARK: - Reward Section

/// Reward label + description + optional current effect.
/// While Doomed every challenge reward is nullified by Pelle — strike
/// through the entire block (label + body + effect) so the player sees
/// the reward text intact but knows it isn't applying.
struct ChallengeRewardSection: View, Equatable {
    let reward: String
    var rewardEffect: String? = nil
    var pelleDoomed: Bool = false

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.reward == rhs.reward
            && lhs.rewardEffect == rhs.rewardEffect
            && lhs.pelleDoomed == rhs.pelleDoomed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Reward:")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.yellow.opacity(0.9))
                .strikethrough(pelleDoomed)
            Text(reward)
                .font(.caption2)
                .foregroundStyle(.yellow.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
                .strikethrough(pelleDoomed)
            if let effect = rewardEffect {
                RewardEffectLabel(effect: effect)
                    .equatable()
                    .strikethrough(pelleDoomed)
            }
        }
    }
}
