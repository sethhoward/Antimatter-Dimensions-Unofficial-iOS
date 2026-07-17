//
//  InfinityChallengesTab.swift
//  AntiMatter
//
//  Grid of 8 Infinity Challenges with status-based coloring,
//  descriptions, goals, rewards, and start/exit controls.
//  Mirrors InfinityChallengesTab.vue / InfinityChallengeBox.vue.
//

import SwiftUI

struct InfinityChallengesTab: View {
    let engine: GameEngine
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                InfinityChallengesHeaderSection(engine: engine)
                InfinityChallengesGrid(engine: engine)
                PhoneTabBarSpacer()
            }
            .padding(.vertical, 16)
            .padding(.horizontal, metrics.contentHPadding)
        }
        .preserveScrollPosition(key: "infinityChallenges")
    }
}

// MARK: - Header

private struct InfinityChallengesHeaderSection: View {
    let engine: GameEngine

    var body: some View {
        let challenges = engine.gameState.infinityChallenges
        InfinityChallengesHeaderSectionInner(
            nextICUnlockAM: challenges.nextICUnlockAM,
            isRetrying: challenges.retryChallenge,
            isAnyRunning: challenges.isAnyRunning,
            showAllVisible: engine.eternityUnlocked,
            showAllActive: challenges.showAllChallenges,
            engine: engine
        ).equatable()
    }
}

/// Equatable on the header-relevant fields. `nextICUnlockAM` only
/// transitions when the player crosses an IC unlock threshold; the
/// others are transition-only bools. Body skips except on transitions.
private struct InfinityChallengesHeaderSectionInner: View, Equatable {
    let nextICUnlockAM: String?
    let isRetrying: Bool
    let isAnyRunning: Bool
    let showAllVisible: Bool
    let showAllActive: Bool
    let engine: GameEngine

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.nextICUnlockAM == rhs.nextICUnlockAM
            && lhs.isRetrying == rhs.isRetrying
            && lhs.isAnyRunning == rhs.isAnyRunning
            && lhs.showAllVisible == rhs.showAllVisible
            && lhs.showAllActive == rhs.showAllActive
    }

    var body: some View {
        VStack(spacing: 10) {
            Text("Infinity Challenges")
                .font(.title3.weight(.medium))

            Text("An active Big Crunch Autobuyer will Crunch immediately when reaching an Infinity Challenge's antimatter goal, regardless of settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let nextAM = nextICUnlockAM {
                Text("Next Infinity Challenge unlocks at \(nextAM) antimatter.")
                    .font(.subheadline)
                    .foregroundStyle(GameColor.infinity)
            } else {
                Text("All Infinity Challenges unlocked")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }

            ChallengeRetryToggle(
                isRetrying: isRetrying,
                accentColor: GameColor.infinity
            ) { engine.setRetryChallenge(!isRetrying) }

            if showAllVisible {
                Toggle("Show all known challenges", isOn: Binding(
                    get: { showAllActive },
                    set: { engine.setShowAllChallenges($0) }
                ))
                .toggleStyle(.switch)
                .font(.caption)
                .padding(.horizontal, 12)
            }

            if isAnyRunning {
                ChallengeActionButtons(engine: engine)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Grid

private struct InfinityChallengesGrid: View {
    let engine: GameEngine
    @Environment(\.sidebarState) private var sidebar
    @Environment(\.layoutMetrics) private var metrics

    @State private var maxCardHeight: CGFloat = 90

    var body: some View {
        let challenges = engine.gameState.infinityChallenges
        // Web `InfinityChallengesTab.vue` `isChallengeVisible`: locked ICs
        // only appear under the toggle once Eternity is unlocked.
        let showAll = challenges.showAllChallenges && engine.eternityUnlocked
        let spacing: CGFloat = metrics.isCompact ? 8 : 12
        let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: metrics.infinityChallengeColumns)
        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(challenges.challenges.filter { $0.isUnlocked || showAll }) { challenge in
                ICCard(challenge: challenge, uniformHeight: maxCardHeight, engine: engine) {
                    engine.startInfinityChallenge(challenge.id) { [weak sidebar] in
                        sidebar?.selectSubtabIfAuto(.antimatterDimensions, in: .dimensions, engine: engine)
                    }
                }
                .equatable()
            }
        }
        .onPreferenceChange(EqualHeightKey.self) { if $0 > maxCardHeight { maxCardHeight = $0 } }
    }
}

// MARK: - IC Card

private struct ICCard: View, Equatable {
    let challenge: InfinityChallengeInfo
    let uniformHeight: CGFloat
    let engine: GameEngine
    let onStart: () -> Void

    /// Same shape as `ECCard`'s ==. `challenge.rewardEffect` is the
    /// volatile field on completed ICs; pre-completion all challenge
    /// fields are stable, so most cards skip body each tick.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.challenge == rhs.challenge
            && lhs.uniformHeight == rhs.uniformHeight
    }

    private var statusColor: Color {
        if challenge.isRunning { return GameColor.infinity }
        if challenge.isCompleted { return .green }
        return GameColor.sidebarBackground
    }

    private var borderColor: Color {
        if challenge.isRunning { return GameColor.infinity }
        if challenge.isCompleted { return .green }
        return GameColor.infinity.opacity(0.5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // IC header
            HStack {
                Text("IC\(challenge.id)")
                    .font(.headline.weight(.bold))
                Spacer()
                statusBadge
            }

            // Description — no line limit so long / localized text never
            // truncates; the card grows and the grid equalizes height.
            Text(challenge.capitalizedDescription)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            // Goal
            Text("Goal: \(challenge.goal) antimatter")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))

            // Reward — never struck through in doom: web doesn't disable IC
            // rewards while Doomed (only the IC *unlock* path is doom-aware).
            ChallengeRewardSection(reward: challenge.reward, rewardEffect: challenge.rewardEffect)
                .equatable()

            // Action button
            actionButton
        }
        .padding(10)
        .equalHeightFrame(uniformHeight, min: 90, alignment: .topLeading)
        .background(statusColor.opacity(0.2))
        .roundedBorder(borderColor, cornerRadius: 8, lineWidth: 1.5)
        .publishEqualHeight()
        #if DEBUG
        .contextMenu {
            if !challenge.isCompleted {
                Button {
                    engine.devCommand("InfinityChallenge(\(challenge.id)).complete()")
                } label: {
                    Label("Complete Challenge", systemImage: "checkmark.circle")
                }
            }
        }
        #endif
    }

    private var statusBadge: some View {
        ChallengeStatusBadge(isRunning: challenge.isRunning, isCompleted: challenge.isCompleted, accentColor: GameColor.infinity)
            .equatable()
    }

    // MARK: - Action button

    @ViewBuilder
    private var actionButton: some View {
        if challenge.isRunning {
            EmptyView()
        } else if challenge.isCompleted {
            Button {
                onStart()
            } label: {
                Text("Completed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.15))
                    .roundedBorder(Color.green.opacity(0.4))
            }
            .buttonStyle(.plain)
        } else if !challenge.isUnlocked {
            // Surfaced by "Show all known challenges" — view-only, no tap.
            Text("Locked")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.05))
                .roundedBorder(Color.white.opacity(0.15))
        } else {
            Button {
                onStart()
            } label: {
                Text("Start")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(GameColor.infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
    }
}
