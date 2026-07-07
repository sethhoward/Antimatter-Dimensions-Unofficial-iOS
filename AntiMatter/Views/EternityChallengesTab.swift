//
//  EternityChallengesTab.swift
//  AntiMatter
//
//  Grid of 12 Eternity Challenges with completion tracking (up to 5 each),
//  descriptions, goals, rewards, and start/exit controls.
//  Visual states match web EternityChallengeBoxWrapper.vue (dark theme).
//

import SwiftUI

struct EternityChallengesTab: View {
    let engine: GameEngine
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                EternityChallengesHeaderSection(engine: engine)
                EternityChallengesGrid(engine: engine)
                PhoneTabBarSpacer()
            }
            .padding(.vertical, 16)
            .padding(.horizontal, metrics.contentHPadding)
        }
        .preserveScrollPosition(key: "eternityChallenges")
    }
}

// MARK: - Header

private struct EternityChallengesHeaderSection: View {
    let engine: GameEngine

    var body: some View {
        let ec = engine.gameState.eternityChallenges
        EternityChallengesHeaderSectionInner(
            isAnyRunning: ec.isAnyRunning,
            autoECVisible: ec.autoECVisible,
            autoECActive: ec.autoECActive,
            showAllVisible: engine.eternityUnlocked,
            showAllActive: ec.showAllChallenges,
            engine: engine
        ).equatable()
    }
}

/// Equatable on transition-only bools. Two static labels + optional
/// action-button row + optional Auto EC / Show all toggles; body skips
/// every tick except on challenge enter/exit, autocomplete-perk
/// purchase, or eternity unlock.
private struct EternityChallengesHeaderSectionInner: View, Equatable {
    let isAnyRunning: Bool
    let autoECVisible: Bool
    let autoECActive: Bool
    let showAllVisible: Bool
    let showAllActive: Bool
    let engine: GameEngine

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isAnyRunning == rhs.isAnyRunning
            && lhs.autoECVisible == rhs.autoECVisible
            && lhs.autoECActive == rhs.autoECActive
            && lhs.showAllVisible == rhs.showAllVisible
            && lhs.showAllActive == rhs.showAllActive
    }

    var body: some View {
        VStack(spacing: 10) {
            Text("Eternity Challenges")
                .font(.title3.weight(.medium))

            Text("Eternity Challenges can be completed up to 5 times, with the goal increasing each time. Rewards scale with completions.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if autoECVisible {
                Toggle("Auto Eternity Challenges", isOn: Binding(
                    get: { autoECActive },
                    set: { engine.setAutoEC($0) }
                ))
                .toggleStyle(.switch)
                .font(.caption)
                .padding(.horizontal, 12)
            }

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

private struct EternityChallengesGrid: View {
    let engine: GameEngine
    @Environment(\.layoutMetrics) private var metrics

    @State private var maxCardHeight: CGFloat = 90

    var body: some View {
        let challenges = engine.gameState.eternityChallenges
        // Web `EternityChallengesTab.vue` `isChallengeVisible`: base set + the
        // "Show all known" override only takes effect once Reality is unlocked.
        let showAll = challenges.showAllChallenges && engine.realityUnlocked
        let spacing: CGFloat = metrics.isCompact ? 8 : 12
        let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: metrics.challengeColumns)
        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(challenges.challenges.filter { Self.isVisible($0, showAll: showAll) }) { challenge in
                ECCard(challenge: challenge, uniformHeight: maxCardHeight, engine: engine)
                    .equatable()
            }
        }
        .onPreferenceChange(EqualHeightKey.self) { if $0 > maxCardHeight { maxCardHeight = $0 } }
    }

    private static func isVisible(_ ec: EternityChallengeInfo, showAll: Bool) -> Bool {
        ec.completions > 0 || ec.isUnlocked || ec.hasUnlocked || ec.canBeUnlocked || showAll
    }
}

// MARK: - EC Card

private struct ECCard: View, Equatable {
    let challenge: EternityChallengeInfo
    let uniformHeight: CGFloat
    let engine: GameEngine

    /// `challenge` is `Equatable` (synthesized) — most fields are stable
    /// except `rewardEffect`, which only churns when the EC is fully
    /// completed and the reward applies a live effect. Pre-completion (or
    /// for ECs whose reward is a static count), `==` returns true and body
    /// skips. Big win for early/mid game where most ECs are uncompleted.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.challenge == rhs.challenge
            && lhs.uniformHeight == rhs.uniformHeight
    }

    // Web dark theme colors for EC button states
    // Locked: bg #23292a, border #b84b5f
    private static let lockedBg = Color(red: 0.137, green: 0.161, blue: 0.165)
    private static let lockedBorder = Color(red: 0.722, green: 0.294, blue: 0.373)
    // Unlocked/Can Unlock: bg #546e7a
    private static let unlockedBg = Color(red: 0.329, green: 0.431, blue: 0.478)
    // Completed: bg #43a047, border #388e3c
    private static let completedBg = Color(red: 0.263, green: 0.627, blue: 0.278)
    private static let completedBorder = Color(red: 0.220, green: 0.557, blue: 0.235)
    // Running: bg #263238
    private static let runningBg = Color(red: 0.149, green: 0.196, blue: 0.220)
    // Redo: bg #58da5e, border #b84b5f
    private static let redoBg = Color(red: 0.345, green: 0.855, blue: 0.369)

    /// Derived state matching web's EternityChallengeBoxWrapper logic
    private var isCompleted: Bool { challenge.isFullyCompleted }
    private var isDone: Bool { isCompleted && !challenge.isUnlocked }
    private var isRedo: Bool { isCompleted && challenge.isUnlocked && !challenge.isRunning }
    private var isLocked: Bool { !isCompleted && !challenge.isUnlocked && !challenge.isRunning && !challenge.canBeUnlocked }
    private var isClickable: Bool { !challenge.isRunning && ((!isCompleted && challenge.canBeUnlocked) || challenge.isUnlocked) }

    private var buttonBg: Color {
        if challenge.isRunning { return Self.runningBg }
        if isRedo { return Self.redoBg }
        if isDone { return Self.completedBg }
        if challenge.isUnlocked || challenge.canBeUnlocked { return Self.unlockedBg }
        return Self.lockedBg
    }

    private var buttonBorder: Color {
        if isDone { return Self.completedBorder }
        if isLocked || isRedo { return Self.lockedBorder }
        return buttonBg.opacity(0.8)
    }

    private var buttonText: String {
        if challenge.isRunning { return "Running" }
        if isRedo { return "Redo (\(challenge.completions)/\(challenge.maxCompletions))" }
        if isDone { return "Completed" }
        if challenge.isUnlocked { return "Start" }
        if challenge.canBeUnlocked { return "Unlock" }
        return "Locked"
    }

    private var buttonTextColor: Color {
        if challenge.isRunning || isDone || isRedo { return .white }
        if isLocked { return .gray }
        return .black
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // EC header
            HStack {
                Text("EC\(challenge.id)")
                    .font(.headline.weight(.bold))
                Spacer()
                Text("\(challenge.completions)/\(challenge.maxCompletions)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(isCompleted ? Self.completedBg : .white.opacity(0.6))
            }

            // Description — no line limit so long / localized text never
            // truncates; the card grows and the grid equalizes height.
            Text(challenge.description)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            // Goal
            Text("Goal: \(challenge.goal) IP")
                .font(.caption2.weight(.medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // Reward — never struck through in doom: web keeps EC rewards
            // fully applied while Doomed (ECs are a deliberately-harder doom
            // activity), unlike Normal Challenges whose rewards are disabled.
            ChallengeRewardSection(reward: challenge.reward, rewardEffect: challenge.rewardEffect)
                .equatable()

            // Action button with completion progress fill
            actionButton
        }
        .padding(10)
        .equalHeightFrame(uniformHeight, min: 90, alignment: .topLeading)
        .background(Color(red: 0.1, green: 0.1, blue: 0.1))
        .roundedBorder(isCompleted ? Self.completedBorder : GameColor.eternity.opacity(0.4), cornerRadius: 8, lineWidth: 1.5)
        .publishEqualHeight()
        #if DEBUG
        .contextMenu {
            if !isCompleted {
                Button {
                    engine.devCommand("EternityChallenge(\(challenge.id)).addCompletion(true)")
                } label: {
                    Label("Add Completion", systemImage: "plus.circle")
                }
                Button {
                    engine.devCommand("for(var i=0;i<5;i++) EternityChallenge(\(challenge.id)).addCompletion(true)")
                } label: {
                    Label("Complete All (5/5)", systemImage: "checkmark.circle")
                }
            }
        }
        #endif
    }

    // MARK: - Action button

    private var actionButton: some View {
        Button {
            if challenge.canBeUnlocked {
                engine.buyECStudy(challenge.id)
            } else if challenge.isUnlocked {
                engine.startEternityChallenge(challenge.id)
            }
        } label: {
            ZStack(alignment: .leading) {
                // Completion progress bar (0-5 fill, hidden when fully complete)
                if challenge.completions > 0 && !isCompleted {
                    let fraction = CGFloat(challenge.completions) / CGFloat(challenge.maxCompletions)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Self.completedBg.opacity(0.3))
                            .frame(width: geo.size.width * fraction)
                    }
                }

                Text(buttonText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(buttonTextColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(buttonBg)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(buttonBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .allowsHitTesting(isClickable)
    }
}

