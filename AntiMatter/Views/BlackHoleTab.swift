//
//  BlackHoleTab.swift
//  AntiMatter
//
//  Black Hole — game speed multiplier with active/inactive cycle.
//  Two black holes, each with interval/power/duration upgrades.
//  Layout follows web BlackHoleTab.vue.
//

import SwiftUI

struct BlackHoleTab: View {
    let engine: GameEngine

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Banner stays at full opacity — explains why the rest is dim.
                if engine.pelleDoomed {
                    BlackHolePelleDoomedBanner()
                }
                BlackHoleContent(engine: engine)
                    .opacity(engine.pelleDoomed ? 0.45 : 1)
                    .allowsHitTesting(!engine.pelleDoomed)
                PhoneTabBarSpacer()
            }
            .padding()
        }
    }
}

// MARK: - Pelle banner

/// Shown above all BH controls during Doom — Black Holes are disabled
/// outright by Pelle (web `BlackHoles.areUnlocked` returns false). Renders
/// at full opacity (the parent VStack dims everything else).
private struct BlackHolePelleDoomedBanner: View {
    var body: some View {
        Text("The physics of this Reality do not allow the existence of Black Holes.")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(GameColor.pelle.readableOnDark())
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10).padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.5))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(GameColor.pelle, lineWidth: 1))
            )
    }
}

// MARK: - Content (unlock / unlocked branch)

private struct BlackHoleContent: View {
    let engine: GameEngine
    @Environment(\.sidebarState) private var sidebarState
    @Environment(\.scenePhase) private var scenePhase

    /// True only when this subtab is the visible one AND the scene is active.
    /// `SubtabPager` (iPhone) keeps adjacent pages in cached hosting controllers,
    /// and SwiftUI's `TimelineView(.animation)` schedule is not guaranteed to
    /// pause the instant the scene backgrounds — so we gate explicitly on both.
    private var isVisible: Bool {
        sidebarState?.activeSubtab == .blackHole && scenePhase == .active
    }

    var body: some View {
        let state = engine.gameState.blackHoleState
        if !state.isUnlocked {
            BlackHoleUnlockSection(engine: engine)
        } else {
            VStack(spacing: 16) {
                BlackHoleControlsSection(engine: engine)

                BlackHoleAnimationView(state: state, isActive: isVisible)
                    .frame(width: 300, height: 300)

                BlackHoleStateSection(engine: engine)
                BlackHoleUpgradesSection(engine: engine)
                BlackHoleInversionSliderSection(engine: engine)
            }
        }
    }
}

// MARK: - Pre-unlock

private struct BlackHoleUnlockSection: View {
    let engine: GameEngine

    var body: some View {
        VStack(spacing: 16) {
            GameButton(borderColor: GameColor.reality, isEnabled: true) {
                engine.unlockBlackHole()
            } label: {
                VStack(spacing: 4) {
                    Text("Unlock the Black Hole")
                        .font(.headline.weight(.bold))
                    Text("Cost: 100 Reality Machines")
                        .font(.subheadline)
                }
                .foregroundStyle(GameColor.reality)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }

            VStack(spacing: 6) {
                Text("The Black Hole makes the entire game run significantly faster for a short period of time.")
                    .multilineTextAlignment(.center)
                Text("Starts at x180 faster for 10 seconds, once per hour.")
                    .multilineTextAlignment(.center)
                Text("Unlocking the Black Hole also gives 10 Automator Points.")
                    .multilineTextAlignment(.center)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Controls

private struct BlackHoleControlsSection: View {
    let engine: GameEngine
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        let state = engine.gameState.blackHoleState
        let isCompact = metrics.isCompact
        HStack(spacing: 12) {
            GameButton(borderColor: GameColor.reality, isEnabled: true) {
                engine.toggleBlackHolePause()
            } label: {
                Text(isCompact ? "\(state.stateChangeLabel) BH" : "\(state.stateChangeLabel) Black Hole")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(GameColor.reality)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }

            if state.autoPauseVisible {
                GameButton(borderColor: GameColor.reality, isEnabled: true) {
                    engine.cycleBlackHoleAutoPauseMode()
                } label: {
                    Text(isCompact ? "Auto-pause: \(state.autoPauseShortLabel)" : "Auto-pause: \(state.autoPauseLabel)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(GameColor.reality)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
            }
        }
    }
}

// MARK: - State display

private struct BlackHoleStateSection: View {
    let engine: GameEngine

    var body: some View {
        let state = engine.gameState.blackHoleState
        VStack(spacing: 12) {
            ForEach(state.blackHoles) { bh in
                VStack(spacing: 4) {
                    Text("Black Hole \(bh.id) State: \(bh.stateText)")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    if !bh.isPermanent {
                        Text("Active time: \(bh.uptime)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !state.detailedBH2.isEmpty {
                Text(state.detailedBH2)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }

            if !state.isPermanent {
                Text("Black holes become permanently active when they are active for more than 99.99% of the time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Upgrades

private struct BlackHoleUpgradesSection: View {
    let engine: GameEngine

    var body: some View {
        let state = engine.gameState.blackHoleState
        VStack(spacing: 16) {
            ForEach(state.blackHoles) { bh in
                VStack(spacing: 4) {
                    Text("Black Hole \(bh.id) Upgrades")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach(bh.upgrades) { upgrade in
                            // Hide interval + duration when permanent
                            if bh.isPermanent && (upgrade.id.contains("interval") || upgrade.id.contains("duration")) {
                                EmptyView()
                            } else {
                                BlackHoleUpgradeCard(
                                    upgrade: upgrade,
                                    onBuy: {
                                        let type = upgrade.id.components(separatedBy: "-").last ?? ""
                                        engine.buyBlackHoleUpgrade(bh.id, type: type)
                                    },
                                    onToggleAutobuyer: { on in
                                        engine.toggleBlackHoleUpgradeAutobuyer(upgradeId: upgrade.upgradeId, on: on)
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Inversion slider

private struct BlackHoleInversionSliderSection: View {
    let engine: GameEngine

    var body: some View {
        let state = engine.gameState.blackHoleState
        if state.inversionUnlocked {
            BlackHoleInversionSliderView(
                negativeSlider: state.negativeSlider,
                negativeBHDivisor: state.negativeBHDivisor,
                isActive: state.inversionActive,
                sliderDisabled: state.sliderDisabled,
                sliderLockText: state.sliderLockText,
                accent: GameColor.reality,
                onCommit: { engine.setEnslavedNegativeSlider($0) }
            )
        }
    }
}

// MARK: - Black Hole Upgrade Card

private struct BlackHoleUpgradeCard: View {
    let upgrade: BlackHoleUpgradeInfo
    let onBuy: () -> Void
    let onToggleAutobuyer: (Bool) -> Void

    private var bgColor: Color {
        if upgrade.isCapped { return GameColor.reality }
        if upgrade.isAffordable { return .black }
        return GameColor.unavailableBg
    }

    private var textColor: Color {
        if upgrade.isCapped { return .black }
        if upgrade.isAffordable { return GameColor.reality }
        return .white
    }

    var body: some View {
        VStack(spacing: 4) {
            Button {
                Haptics.tap()
                onBuy()
            } label: {
                VStack(spacing: 4) {
                    Text(upgrade.description)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(textColor)
                        .multilineTextAlignment(.center)

                    Text("\(upgrade.effectTitle): \(upgrade.effectText)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(upgrade.isCapped ? .black.opacity(0.7) : textColor.opacity(0.75))

                    if !upgrade.isCapped {
                        Text("Cost: \(upgrade.cost) RM")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(textColor.opacity(0.7))
                    } else {
                        Text("Capped")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.black)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 90)
                .background(bgColor)
                .roundedBorder(upgrade.isCapped ? .black : GameColor.reality, lineWidth: 1.5)
            }
            .buttonStyle(.plain)
            .allowsHitTesting(upgrade.isAffordable && !upgrade.isCapped)

            if upgrade.autobuyerUnlocked {
                HStack(spacing: 6) {
                    Text("Autobuyer:")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(GameColor.reality)
                    Toggle(isOn: Binding(
                        get: { upgrade.autobuyerActive },
                        set: { onToggleAutobuyer($0) }
                    )) { EmptyView() }
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .scaleEffect(0.75)
                        .pausedAwareTint(isActive: upgrade.autobuyerActive)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: 24)
            }
        }
    }
}

// MARK: - Black Hole inversion slider (shared with Enslaved tab)

/// Slider + explainer shown once V is flipped and BHs are permanent.
/// Parameterised on the raw values so it can live on both the Black Hole
/// tab (via `BlackHoleState.inversion*`) and the Nameless Ones tab (via
/// `EnslavedState.*`). Writes the commit through
/// `engine.setEnslavedNegativeSlider(_:)` — the JS helper name is a
/// historical holdover; it mutates `player.blackHoleNegative`.
struct BlackHoleInversionSliderView: View {
    let negativeSlider: Double
    let negativeBHDivisor: String
    let isActive: Bool
    let sliderDisabled: Bool
    let sliderLockText: String
    let accent: Color
    let onCommit: (Double) -> Void

    @State private var sliderValue: Double = 0
    @State private var hasInitialized = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Inverted Black Hole divides game speed by \(negativeBHDivisor). (Currently \(isActive ? "active" : "inactive"))")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            if sliderDisabled {
                Text(sliderLockText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GameColor.badPink)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Slider(value: $sliderValue, in: 0...300, step: 1) { editing in
                    if !editing { onCommit(sliderValue) }
                }
                .tint(accent)
                .onChange(of: sliderValue) { _, new in onCommit(new) }
                .onAppear {
                    if !hasInitialized {
                        sliderValue = negativeSlider
                        hasInitialized = true
                    }
                }
                .onChange(of: negativeSlider) { _, new in
                    // Pick up external updates without fighting the user
                    // during an active drag.
                    if abs(new - sliderValue) > 0.5 { sliderValue = new }
                }
            }

            Text("Inverting the Black Hole only affects its own speedup, no other upgrades or effects, although it will also indirectly affect the Effarig Game speed power effect.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(RoundedBorderModifier(color: accent.opacity(0.3), cornerRadius: 10, lineWidth: 1))
    }
}
