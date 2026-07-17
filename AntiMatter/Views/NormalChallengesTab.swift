//
//  NormalChallengesTab.swift
//  AntiMatter
//
//  Grid of 12 Normal Challenges with status-based coloring,
//  descriptions, rewards, and start/exit controls.
//

import SwiftUI

struct NormalChallengesTab: View {
    let engine: GameEngine
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                NormalChallengesHeaderSection(engine: engine)
                NormalChallengesGrid(engine: engine)
                PhoneTabBarSpacer()
            }
            .padding(.vertical, 16)
            .padding(.horizontal, metrics.contentHPadding)
        }
        .preserveScrollPosition(key: "normalChallenges")
    }
}

// MARK: - Header

private struct NormalChallengesHeaderSection: View {
    let engine: GameEngine

    var body: some View {
        let challenges = engine.gameState.normalChallenges
        NormalChallengesHeaderSectionInner(
            isRetrying: challenges.retryChallenge,
            isAnyRunning: challenges.isAnyRunning,
            engine: engine
        ).equatable()
    }
}

/// Equatable on the two transition-only bools. Body skips except on
/// retry-toggle taps and challenge enter/exit.
private struct NormalChallengesHeaderSectionInner: View, Equatable {
    let isRetrying: Bool
    let isAnyRunning: Bool
    let engine: GameEngine

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isRetrying == rhs.isRetrying && lhs.isAnyRunning == rhs.isAnyRunning
    }

    var body: some View {
        VStack(spacing: 10) {
            Text("Normal Challenges")
                .font(.title3.weight(.medium))

            Text("Challenges are special runs with different modifiers that give you a reward upon completion.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            ChallengeRetryToggle(
                isRetrying: isRetrying,
                accentColor: GameColor.antimatter
            ) { engine.setRetryChallenge(!isRetrying) }

            if isAnyRunning {
                ChallengeActionButtons(engine: engine)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Grid

private struct NormalChallengesGrid: View {
    let engine: GameEngine
    @Environment(\.sidebarState) private var sidebar
    @Environment(\.layoutMetrics) private var metrics

    @State private var maxCardHeight: CGFloat = 90

    var body: some View {
        let challenges = engine.gameState.normalChallenges
        let spacing: CGFloat = metrics.isCompact ? 8 : 12
        let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: metrics.challengeColumns)
        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(challenges.challenges) { challenge in
                ChallengeCard(challenge: challenge, currentInfinities: challenges.currentInfinities, uniformHeight: maxCardHeight, engine: engine) {
                    engine.startNormalChallenge(challenge.id) { [weak sidebar] in
                        sidebar?.selectSubtabIfAuto(.antimatterDimensions, in: .dimensions, engine: engine)
                    }
                }
                .equatable()
            }
        }
        .onPreferenceChange(EqualHeightKey.self) { if $0 > maxCardHeight { maxCardHeight = $0 } }
    }
}

// MARK: - Challenge Card

private struct ChallengeCard: View, Equatable {
    let challenge: NormalChallengeInfo
    let currentInfinities: Int
    let uniformHeight: CGFloat
    let engine: GameEngine
    let onStart: () -> Void

    /// Closure excluded; `engine` reference-stable but its `pelleDoomed`
    /// is read for the reward strikethrough so we factor that in. All NC
    /// fields are transition-only (no per-tick churn — Normal Challenges
    /// have no live reward effect). `currentInfinities` updates only on
    /// crunch, so once you've stabilized at a stage it's effectively
    /// stable. Body skips most ticks.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.challenge == rhs.challenge
            && lhs.currentInfinities == rhs.currentInfinities
            && lhs.uniformHeight == rhs.uniformHeight
            && lhs.engine.pelleDoomed == rhs.engine.pelleDoomed
    }

    private var statusColor: Color {
        if challenge.isBroken { return GameColor.enslaved }
        if challenge.isRunning { return .blue }
        if challenge.isCompleted { return .green }
        if !challenge.isUnlocked { return .gray }
        return GameColor.sidebarBackground
    }

    private var borderColor: Color {
        if challenge.isBroken { return GameColor.enslaved }
        if challenge.isRunning { return .blue }
        if challenge.isCompleted { return .green }
        if !challenge.isUnlocked { return .gray.opacity(0.5) }
        return GameColor.antimatter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Challenge ID header
            HStack {
                Text("C\(challenge.id)")
                    .font(.headline.weight(.bold))
                Spacer()
                statusBadge
            }

            // Name
            Text(challenge.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))

            // Description — no line limit so long / localized text never
            // truncates; the card grows and the grid equalizes height.
            Text(challenge.capitalizedDescription)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            // Reward
            ChallengeRewardSection(reward: challenge.reward, pelleDoomed: engine.pelleDoomed)
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
                    engine.devCommand("NormalChallenge(\(challenge.id)).complete()")
                } label: {
                    Label("Complete Challenge", systemImage: "checkmark.circle")
                }
            }
        }
        #endif
    }

    @ViewBuilder
    private var statusBadge: some View {
        if challenge.isBroken {
            // Inside the Nameless Reality, `Enslaved.BROKEN_CHALLENGES` raises
            // the goal to `DC.E1E15` (unreachable). Web `NormalChallengeBox.vue`
            // swaps the Running/Completed badge for a "Broken" label; mirror
            // here with the Enslaved tan.
            Text("Broken")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(GameColor.enslaved, in: Capsule())
        } else {
            ChallengeStatusBadge(isRunning: challenge.isRunning, isCompleted: challenge.isCompleted)
                .equatable()
        }
    }

    // MARK: - Action button

    @ViewBuilder
    private var actionButton: some View {
        if challenge.isRunning {
            // No start button when running
            EmptyView()
        } else if !challenge.isUnlocked {
            Text("Locked (\(currentInfinities)/\(challenge.lockedAt))")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.gray.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 6))
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
        } else {
            Button {
                onStart()
            } label: {
                Text("Start")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(GameColor.antimatter)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
    }
}
