//
//  EnslavedTab.swift
//  AntiMatter
//
//  The Nameless Ones — stored-game-time charging, stored-real-time storage,
//  unlock shop priced in years of stored game time, and the start-reality
//  confirmation sheet. Mirrors src/components/tabs/celestial-enslaved/EnslavedTab.vue.
//

import SwiftUI

struct EnslavedTab: View {
    let engine: GameEngine

    var body: some View {
        EnslavedTabContent(engine: engine)
    }
}

private struct EnslavedTabContent: View {
    let engine: GameEngine

    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.sidebarState) private var sidebarState
    @Environment(\.scenePhase) private var scenePhase
    @State private var showHistory = false
    @State private var showHints = false

    private var e: EnslavedState { engine.gameState.celestials.enslaved }

    /// True only when The Nameless Ones is the visible subtab AND the scene
    /// is active. Drives `EnslavedRunButton.isActive` so cached SubtabPager
    /// pages and backgrounded scenes don't keep the chain rotation scheduled.
    private var isVisible: Bool {
        sidebarState?.activeSubtab == .namelessOnes && scenePhase == .active
    }

    /// Gate for the "Examine the Reality more closely..." hints button.
    /// Poll `_nativeEnslavedHintsState()` once when the tab appears so we
    /// can decide whether to render the button — the same loader backs the
    /// sheet so the data is ready instantly when the user taps in.
    private var canShowHintsButton: Bool {
        engine.enslavedHints?.canShowHintsButton ?? false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if canShowHintsButton {
                    hintsButton
                }
                if e.hasRunUnlock {
                    EnslavedRunSection(
                        engine: engine,
                        isRunning: e.isRunning,
                        isCompleted: e.isCompleted,
                        runDescription: e.runDescription,
                        isActive: isVisible,
                        isPelleDoomed: engine.pelleDoomed
                    )
                    .equatable()
                }
                // Vue EnslavedTab.vue:207 gates this row on
                // `hasAutoRelease && canAutoRelease` — iOS now matches.
                if e.hasAutoPulse && e.canAutoPulse {
                    pulseBlackHoleRow
                }
                mechanicsRow
                if e.isNegativeBHUnlocked {
                    BlackHoleInversionSliderView(
                        negativeSlider: e.negativeSlider,
                        negativeBHDivisor: e.negativeBHDivisor,
                        isActive: e.isBHInverted,
                        sliderDisabled: e.sliderDisabled,
                        sliderLockText: e.sliderLockText,
                        accent: GameColor.enslaved,
                        onCommit: { engine.setEnslavedNegativeSlider($0) }
                    )
                }
                unlockShopSection
                #if DEBUG
                debugRow
                #endif
                PhoneTabBarSpacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .sheet(isPresented: $showHistory) {
            CelestialQuoteHistoryView(celestialKey: "enslaved", engine: engine)
        }
        .sheet(isPresented: $showHints) {
            EnslavedHintsSheet(engine: engine)
        }
        .onAppear { engine.loadEnslavedHints() }
    }

    private var hintsButton: some View {
        GameButton(theme: .enslaved, isEnabled: true) {
            engine.loadEnslavedHints()
            showHints = true
        } label: {
            Label("Examine the Reality more closely…", systemImage: "magnifyingglass")
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            Image(systemName: "link")
                .font(.title.weight(.semibold))
                .foregroundStyle(GameColor.enslaved)
            Text("The Nameless Ones")
                .font(.headline)
                .foregroundStyle(GameColor.enslaved.readableOnDark())
            Spacer()
            Button {
                engine.loadQuoteHistory(for: "enslaved")
                showHistory = true
            } label: {
                Label("Quote History", systemImage: "quote.bubble")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(GameColor.enslaved)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(GameColor.enslaved.opacity(0.15), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Mechanics row

    @ViewBuilder
    /// Pulse Black Hole toggle (Ra.unlocks.autoPulseTime — Enslaved pet lv 10).
    /// Auto-discharges 1% of stored game time every 5 ticks.
    private var pulseBlackHoleRow: some View {
        HStack(spacing: 10) {
            Text("Pulse Black Hole:")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(GameColor.enslaved)
            Toggle(isOn: Binding(
                get: { e.isAutoPulsing },
                set: { _ in engine.toggleEnslavedAutoPulse() }
            )) { EmptyView() }
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(GameColor.enslaved)
            if e.isAutoPulsing, !e.autoPulseSpeedText.isEmpty {
                Text("(avg \(e.autoPulseSpeedText) speed)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(GameColor.enslaved.opacity(0.6), lineWidth: 1)
                )
        )
        .allowsHitTesting(e.canAutoPulse || e.isAutoPulsing)
        .opacity((e.canAutoPulse || e.isAutoPulsing) ? 1 : 0.5)
    }

    @ViewBuilder
    private var mechanicsRow: some View {
        if metrics.isCompact {
            VStack(spacing: 12) {
                gameTimeColumn
                realTimeColumn
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                gameTimeColumn
                realTimeColumn
            }
        }
    }

    private var gameTimeColumn: some View {
        // Web EnslavedTab.vue:265 — "decreased" when Ra's autoPulseTime is
        // unlocked (because the pulse trickle keeps production partially
        // running), otherwise "disabled".
        let speedAdjective = e.hasAutoPulse ? "decreased" : "disabled"
        return VStack(alignment: .leading, spacing: 10) {
            Text("While charging, game speed multipliers are \(speedAdjective), and the lost speed is converted into stored game time. Discharging the Black Hole allows you to skip forward in time. Stored game time is also used to unlock certain upgrades.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            EnslavedMechanicButton(
                isHighlighted: e.isStoringBlackHole,
                isFixed: !e.canModifyGameTimeStorage,
                isDoomed: e.isDoomed,
                topText: e.storedBlackHoleText,
                bottomText: e.isStoringBlackHole ? "Charging Black Hole" : "Charge Black Hole",
                action: { engine.toggleEnslavedStoreBlackHole() }
            )

            EnslavedMechanicButton(
                isHighlighted: false,
                isFixed: !e.canDischarge || e.hasNoCharge,
                isDoomed: e.isDoomed,
                topText: "Discharge Black Hole",
                bottomText: e.isRunning && !e.nerfedInRealityText.isEmpty
                    ? "\(e.nerfedInRealityText) in this Reality"
                    : nil,
                action: { engine.dischargeEnslavedBlackHole() }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .modifier(RoundedBorderModifier(color: GameColor.enslaved.opacity(0.3), cornerRadius: 10, lineWidth: 1))
    }

    private var realTimeColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Storing real time completely halts all production, setting game speed to 0. You can use stored real time to \u{201C}amplify\u{201D} a Reality, simulating repeated runs of it. Amplified Realities give all the rewards that normal Realities do.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            EnslavedMechanicButton(
                isHighlighted: e.isStoringReal,
                isFixed: !e.canChangeStoreRealTime || e.hasReachedCurrentCap,
                isDoomed: e.isDoomed,
                topText: e.storedRealText,
                bottomText: e.isStoringReal ? "Storing real time" : "Store real time",
                action: { engine.toggleEnslavedStoreReal() }
            )

            let autoText: String = {
                if !e.offlineProgressEnabled { return "Offline Progress is disabled" }
                if e.autoStoreReal { return "Offline time stored" }
                return "Offline time used for production"
            }()
            EnslavedMechanicButton(
                isHighlighted: e.autoStoreReal && e.offlineProgressEnabled,
                isFixed: !e.canChangeStoreRealTime || !e.offlineProgressEnabled,
                isDoomed: e.isDoomed,
                topText: autoText,
                bottomText: nil,
                action: { engine.toggleEnslavedAutoStoreReal() }
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("Efficiency: \(e.storedRealEfficiencyPct)")
                Text("Maximum stored real time: \(e.storedRealCapText)")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .modifier(RoundedBorderModifier(color: GameColor.enslaved.opacity(0.3), cornerRadius: 10, lineWidth: 1))
    }

    // MARK: - Unlock shop

    private var unlockShopSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Unlocks")
                .font(.headline)
                .foregroundStyle(GameColor.enslaved.readableOnDark())

            ForEach(e.unlocks) { info in
                EnslavedUnlockCard(
                    info: info,
                    onBuy: { engine.buyEnslavedUnlock(id: info.id) }
                )
                .equatable()
            }
        }
        .padding(14)
        .modifier(RoundedBorderModifier(color: GameColor.enslaved.opacity(0.4), cornerRadius: 12, lineWidth: 1))
    }

    // MARK: - Debug cheat row

    #if DEBUG
    private var debugRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DEBUG — Stored game time cheats")
                .font(.caption.weight(.bold))
                .foregroundStyle(.yellow.opacity(0.8))
            HStack(spacing: 8) {
                GameButton(theme: .enslaved, isEnabled: true) {
                    engine.devAddEnslavedStoredYears(1e35)
                } label: {
                    Text("+1e35 yr")
                        .font(.caption.weight(.semibold))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                }
                GameButton(theme: .enslaved, isEnabled: true) {
                    engine.devAddEnslavedStoredYears(1e40)
                } label: {
                    Text("+1e40 yr")
                        .font(.caption.weight(.semibold))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                }
                GameButton(theme: .enslaved, isEnabled: true) {
                    engine.devAddEnslavedStoredYears(1e45)
                } label: {
                    Text("+1e45 yr")
                        .font(.caption.weight(.semibold))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                }
                GameButton(theme: .enslaved, isEnabled: true) {
                    engine.devResetEnslavedStoredTime()
                } label: {
                    Text("Reset")
                        .font(.caption.weight(.semibold))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                }
            }
        }
        .padding(10)
        .modifier(RoundedBorderModifier(color: .yellow.opacity(0.4), cornerRadius: 10, lineWidth: 1))
    }
    #endif
}

// MARK: - Run Section (Equatable)

/// Extracted run card so the per-tick parent body doesn't rebuild the
/// modifier chain. All inputs are transition-only: isRunning toggles on
/// run start/stop, isCompleted only flips at end of run, runDescription
/// is static, isActive flips on tab focus + scenePhase, isPelleDoomed
/// rarely toggles. Body skips most ticks.
private struct EnslavedRunSection: View, Equatable {
    let engine: GameEngine
    let isRunning: Bool
    let isCompleted: Bool
    let runDescription: [String]
    let isActive: Bool
    let isPelleDoomed: Bool

    static func == (lhs: EnslavedRunSection, rhs: EnslavedRunSection) -> Bool {
        lhs.isRunning == rhs.isRunning
            && lhs.isCompleted == rhs.isCompleted
            && lhs.runDescription == rhs.runDescription
            && lhs.isActive == rhs.isActive
            && lhs.isPelleDoomed == rhs.isPelleDoomed
        // engine excluded (identity-stable).
    }

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            Text(isRunning ? "You are inside The Nameless Ones' Reality"
                           : "Start The Nameless Ones' Reality")
                .font(.headline)
                .foregroundStyle(GameColor.enslaved.readableOnDark())
                .multilineTextAlignment(.center)
                .strikethrough(isPelleDoomed)

            if isCompleted {
                Text("(Completed)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
            }

            // Animated chain sigil. Uses SF Symbol `link` because the web's
            // Font Awesome chain glyph renders as tofu on iOS without the
            // font bundled. See `EnslavedRunButton.swift` for keyframes.
            EnslavedRunButton(isRunning: isRunning,
                              isActive: isActive,
                              isEnabled: !isPelleDoomed) {
                guard !isPelleDoomed else { return }
                engine.requestEnslavedRun()
            }
            if isPelleDoomed {
                Text("Other Celestial Realities are sealed by Doom.")
                    .font(.caption)
                    .foregroundStyle(GameColor.pelle.readableOnDark())
                    .multilineTextAlignment(.center)
            }

            ForEach(Array(runDescription.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 2)
                    .strikethrough(isPelleDoomed)
            }

            Text("Reward: Unlock Tesseracts, which let you increase Infinity Dimension caps (see Infinity Dimension tab).")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .strikethrough(isPelleDoomed)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .modifier(RoundedBorderModifier(color: GameColor.enslaved.opacity(0.4), cornerRadius: 12, lineWidth: 1))
    }
}

// MARK: - Mechanic button (Charge/Discharge/Store/Auto-store)

/// Shared tile — large two-line button styled like `.o-enslaved-mechanic-button`
/// from `EnslavedTab.vue`. Highlights when storing (tan bg + black text),
/// fixed-grey when the action is disabled/locked.
private struct EnslavedMechanicButton: View {
    let isHighlighted: Bool
    let isFixed: Bool
    let isDoomed: Bool
    let topText: String
    let bottomText: String?
    let action: () -> Void

    private var interactable: Bool { !isFixed && !isDoomed }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(topText)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(foregroundColor)
                    .strikethrough(isDoomed)
                if let bottom = bottomText {
                    Text(bottom)
                        .font(.caption)
                        .foregroundStyle(foregroundColor.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .strikethrough(isDoomed)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(GameColor.enslaved.opacity(interactable ? 0.9 : 0.4), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(isFixed ? 0.7 : 1.0)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(interactable)
    }

    private var backgroundColor: Color {
        if isHighlighted { return GameColor.enslaved }
        return Color.black.opacity(0.4)
    }

    private var foregroundColor: Color {
        isHighlighted ? .black : GameColor.enslaved
    }
}

// MARK: - Unlock card

private struct EnslavedUnlockCard: View, Equatable {
    let info: EnslavedUnlockInfo
    let onBuy: () -> Void

    static func == (lhs: EnslavedUnlockCard, rhs: EnslavedUnlockCard) -> Bool {
        lhs.info == rhs.info
        // onBuy excluded (closure captures engine; identity-stable).
    }

    /// `timeToObtainText` is the JS-computed time-to-afford string; we just
    /// render it. The previous storedMs/ratePerMs/isCharging let properties
    /// were dead — the body never read them.
    private var isBought: Bool { info.hasBought }

    var body: some View {
        Button(action: {
            guard info.canBuy else { return }
            Haptics.tap()
            onBuy()
        }) {
            VStack(alignment: .leading, spacing: 6) {
                Text(info.description)
                    .font(.subheadline)
                    .foregroundStyle(textColor)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if !isBought {
                    Text("Costs: \(info.priceYears)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(textColor.opacity(0.85))
                    if !info.timeToObtainText.isEmpty {
                        Text("Time to obtain: \(info.timeToObtainText)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(textColor.opacity(0.7))
                    }
                }

                if isBought {
                    Text("Unlocked")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(GameColor.boughtBorderGreen, in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!isBought && info.canBuy)
    }

    private var backgroundColor: Color {
        if isBought { return GameColor.enslaved.opacity(0.35) }
        if info.canBuy { return Color.black.opacity(0.5) }
        return GameColor.unavailableBg.opacity(0.65)
    }

    private var borderColor: Color {
        if isBought { return GameColor.enslaved }
        if info.canBuy { return GameColor.enslaved }
        return GameColor.enslaved.opacity(0.3)
    }

    private var textColor: Color {
        if isBought { return .black }
        if info.canBuy { return .white }
        return GameColor.unavailableText
    }
}

// Black Hole inversion slider lives in `BlackHoleTab.swift` as
// `BlackHoleInversionSliderView` — shared across the BH tab and this tab.
