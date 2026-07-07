//
//  ContentView.swift
//  AntiMatter
//
//  App shell — custom game sidebar on iPad, content area to the right.
//

import SwiftUI

struct ContentView: View {
    @State private var engine = GameEngine()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ZStack {
            Group {
                if engine.isInitialized {
                    if sizeClass == .compact {
                        PhoneShell(engine: engine)
                    } else {
                        GameShell(engine: engine)
                            .environment(\.layoutMetrics, .regular)
                    }
                } else {
                    ProgressView("Loading game engine…")
                }
            }
            // Single source of truth for the app-wide "autobuyers paused"
            // signal. Read by `\.autobuyersGloballyPaused` from every inline
            // autobuyer Toggle (Autobuyers / ID / TD / Replicanti / BH tabs)
            // via `.pausedAwareTint(isActive:)` so the yellow paused tint
            // applies uniformly regardless of which tab the user is on.
            //
            // Sourced from `engine.autobuyersGloballyOn` (always-polled) NOT
            // `gameState.autobuyers.allOn` (Autobuyers-tab-gated) — otherwise
            // toggles on other tabs wouldn't pick up pause-state changes
            // until the user visits the Autobuyers tab.
            .environment(\.autobuyersGloballyPaused, !engine.autobuyersGloballyOn)

            if let progress = engine.offlineSimProgress {
                OfflineProgressView(progress: progress, engine: engine)
                    .transition(.opacity)
            }
        }
        .onTouchDownGesture { engine.recordInteraction() }
        .onAppear {
            engine.start()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background, .inactive:
                engine.recordBackgroundEntry()
                engine.save()
                // Push the just-saved blob to iCloud synchronously. The
                // debounced upload path relies on DispatchQueue.main.asyncAfter
                // which won't fire once iOS suspends us — so opening a second
                // device right after backgrounding would otherwise pull stale
                // cloud state. No-ops when sync is disabled.
                engine.cloudSaveService?.uploadCurrentSlotSynchronouslyForBackground()
            case .active:
                engine.handleForegroundReturn()
                // Cloud sync check happens unconditionally on foreground
                // (service itself no-ops when sync is disabled). Fires
                // alongside the offline-progress path so returning after
                // a long break reconciles with iCloud the same moment we
                // finish the offline simulation.
                engine.cloudSaveService?.handleForegroundReturn()
            default:
                break
            }
        }
        .alert("JS Error", isPresented: Binding(
            get: { engine.jsError != nil },
            set: { if !$0 { engine.jsError = nil } }
        )) {
            Button("OK", role: .cancel) { engine.jsError = nil }
        } message: {
            Text(engine.jsError ?? "")
        }
        .alert("Challenge", isPresented: Binding(
            get: { engine.gameMessage != nil },
            set: { if !$0 { engine.gameMessage = nil } }
        )) {
            Button("OK", role: .cancel) { engine.gameMessage = nil }
        } message: {
            Text(engine.gameMessage ?? "")
        }
        // Reality/Imaginary Upgrade requirement-lock warning — the game blocked an
        // action (e.g. Eternity with a locked "Existentially Prolong") because it would
        // fail the upgrade's unlock condition. Mirrors web's UpgradeMechanicLockModal.
        // At the root so it appears from any tab (the trigger fires from the header).
        .alert(
            engine.activeUpgradeLock?.title ?? "",
            isPresented: Binding(
                get: { engine.activeUpgradeLock != nil },
                set: { if !$0 { engine.activeUpgradeLock = nil } }
            ),
            presenting: engine.activeUpgradeLock
        ) { prompt in
            Button("Disable Lock", role: .destructive) { engine.disableUpgradeLock(prompt) }
            Button("Cancel", role: .cancel) { engine.activeUpgradeLock = nil }
        } message: { prompt in
            Text(prompt.message)
        }
        // iCloud conflict — presented here (not in Options) so it appears
        // regardless of which tab the user is on when the trigger fires
        // (foreground return, KVS external change, or manual Sync now).
        .sheet(item: Binding(
            get: { engine.cloudSaveService?.pendingConflict },
            set: { _ in engine.cloudSaveService?.dismissConflict() }
        )) { conflict in
            CloudConflictSheet(engine: engine, conflict: conflict)
        }
        // First-enable flow — only shown when both local and cloud have
        // data and the user has to choose a canonical version.
        .sheet(item: Binding(
            get: { engine.cloudSaveService?.pendingFirstEnable },
            set: { _ in /* dismissed via sheet's own actions */ }
        )) { prompt in
            CloudFirstEnableSheet(engine: engine, prompt: prompt)
        }
        // New-player welcome modal (page 1 = opt-in ask). Surfaces on a truly
        // fresh save that hasn't seen onboarding. Presented at the root so it
        // covers both iPad and iPhone shells.
        .sheet(item: Binding(
            get: { engine.onboarding?.phase == .welcome ? engine.onboarding : nil },
            set: { newValue in
                // The sheet dismisses both when the user swipes it away AND when
                // we programmatically move to the .callouts phase. Only the
                // former should count as "declined" — guard on the phase still
                // being .welcome so tapping "Show me the ropes" doesn't tear
                // down the just-started callout sequence.
                if newValue == nil, engine.onboarding?.phase == .welcome {
                    engine.markOnboardingSeen()
                    engine.onboarding = nil
                }
            }
        )) { _ in
            OnboardingWelcomeSheet(engine: engine)
        }
    }
}

// MARK: - Game Shell

struct GameShell: View {
    let engine: GameEngine
    @State private var sidebar = SidebarState()

    static let peekWidth: CGFloat = 20

    /// Accent color matching web --color-accent: changes with highest prestige layer
    private var accentColor: Color {
        if engine.realityUnlocked || engine.realityStudyBought { return GameColor.reality }
        if engine.eternityUnlocked { return GameColor.eternity }
        if engine.infinityUnlocked { return GameColor.infinity }
        return GameColor.antimatter
    }

    /// True when `ChallengeHeaderRow` has visible content — drives the dynamic
    /// piece of `GameHeaderView.pinnedHeight`. Mirrors the `mainLine` gate
    /// inside `ChallengeHeaderRow` (challenge OR celestial reality).
    private var headerHasChallengeBanner: Bool {
        let inChallenge = !engine.challengeDisplayText.isEmpty &&
            !engine.challengeDisplayText.contains("no active challenges")
        return inChallenge || !engine.currentCelestialReality.isEmpty
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Background
            GameColor.baseBackground
                .ignoresSafeArea()

            // Main layout: sidebar (full height) + header/content column
            HStack(spacing: 0) {
                // Sidebar or peek strip
                if sidebar.isCollapsed {
                    // Peek strip with chevron — tap or swipe right to expand
                    GameColor.sidebarBackground
                        .frame(width: GameShell.peekWidth)
                        .overlay {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                sidebar.isCollapsed = false
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 20, coordinateSpace: .local)
                                .onEnded { value in
                                    if value.translation.width > 40 {
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            sidebar.isCollapsed = false
                                        }
                                    }
                                }
                        )
                } else {
                    GameSidebar(sidebar: sidebar, engine: engine)
                        .onboardingAnchor(.tabNav, active: engine.onboarding != nil)
                }

                // Content column: news ticker + header pinned to top, content below
                // Header is overlaid so its height changes don't jitter the content.
                ZStack(alignment: .top) {
                    // Content area — fills the entire column, padded below the header + ticker
                    ZStack {
                        ContentSwitcher(subtab: sidebar.activeSubtab, engine: engine)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                    }
                    .padding(.top, GameHeaderView.pinnedHeight(
                        bhVisible: engine.blackHolesHeaderVisible,
                        hasChallenge: headerHasChallengeBanner,
                        hasGameSpeed: !engine.gameSpeedText.isEmpty
                    ) + (engine.newsEnabled ? 28 : 0) + 1)

                    // News ticker + header overlay — pinned to top
                    VStack(spacing: 0) {
                        if engine.newsEnabled {
                            NewsTickerView(engine: engine, height: 28)
                            accentColor.frame(height: 1)
                        }

                        GameHeaderView(engine: engine)
                            .frame(height: GameHeaderView.pinnedHeight(
                                bhVisible: engine.blackHolesHeaderVisible,
                                hasChallenge: headerHasChallengeBanner,
                                hasGameSpeed: !engine.gameSpeedText.isEmpty
                            ), alignment: .center)
                            .clipped()

                        accentColor.frame(height: 1)
                    }
                    .background(GameColor.baseBackground)
                    .animation(.easeInOut(duration: 0.25), value: engine.newsEnabled)
                    .animation(.easeInOut(duration: 0.25), value: engine.blackHolesHeaderVisible)
                    .animation(.easeInOut(duration: 0.25), value: headerHasChallengeBanner)
                    .animation(.easeInOut(duration: 0.25), value: engine.gameSpeedText.isEmpty)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: sidebar.isCollapsed)
        }
        .overlay(alignment: .topTrailing) {
            ToastOverlay(engine: engine)
        }
        // New-player onboarding callouts (anchored to the tagged targets below).
        // No-op unless engine.onboarding.phase == .callouts.
        .onboardingCalloutOverlay(engine: engine)
        .background(alignment: .topLeading) {
            // Hardware-keyboard support. Tiny off-screen view that claims
            // first responder so UIKeyCommand bindings fire when no text
            // input has focus. Frame is 1×1 (not zero) and we DO NOT
            // apply .allowsHitTesting(false) — both would prevent the
            // view from becoming first responder, silently hiding all
            // bindings from the Cmd-Hold HUD.
            KeyCommandHost(engine: engine, sidebarState: sidebar)
                .frame(width: 1, height: 1)
        }
        .environment(\.sidebarState, sidebar)
        .onAppear {
            // Give the engine a weak handle to this shell's SidebarState so
            // it can run hidden-tab recovery / SA47 / future navigation
            // helpers without each call site plumbing sidebar through.
            engine.sidebarStateRef = sidebar
        }
        .sheet(item: Binding(
            get: { engine.pendingModal },
            set: { engine.pendingModal = $0 }
        ), onDismiss: {
            engine.cancelPrestige()
        }) { modal in
            PrestigeConfirmation(modal: modal, engine: engine)
                .environment(\.sidebarState, sidebar)
        }
        .sheet(isPresented: Binding(
            get: { engine.showGlyphSelection },
            set: { engine.showGlyphSelection = $0 }
        ), onDismiss: {
            engine.cancelGlyphSelection()
        }) {
            GlyphSelectionSheet(choices: engine.glyphChoices, engine: engine)
        }
        .fullScreenCover(item: Binding(
            get: { engine.activeQuote },
            set: { engine.activeQuote = $0 }
        ), onDismiss: {
            engine.advanceQuoteQueue()
        }) { quote in
            CelestialQuoteModal(quote: quote, engine: engine)
                .presentationBackground(.clear)
        }
        // GameEnd credits roll. See PhoneShell for the iPhone equivalent.
        // Re-inject `.sidebarState` across the fullScreenCover boundary —
        // SwiftUI doesn't propagate custom env keys into fullScreenCovers,
        // so without this the SpeedrunStartModal presented from
        // CreditsOverlay falls back to a fresh `SidebarState()` and the
        // "New Game" tab nav writes to a phantom object.
        .fullScreenCover(isPresented: Binding(
            get: { engine.gameEndCreditsActive },
            set: { _ in }
        )) {
            CreditsOverlay(engine: engine)
                .environment(\.sidebarState, sidebar)
        }
        .opacity(engine.gameEndInteractivityDisabled ? 0.4 : 1)
        .allowsHitTesting(!engine.gameEndInteractivityDisabled)
        // Only validate when flags turn ON (new unlock). During Reality
        // resets, flags momentarily go false — validating then would redirect
        // the user away from their current tab.
        .onChange(of: engine.infinityUnlocked) { _, newVal in
            guard newVal else { return }
            sidebar.validateSelection(engine: engine)
        }
        // Explicit reset paths (hardReset, switchSaveSlot, importSave,
        // restoreBackup, startSpeedrun) bump `unlockFlagsGen` and turn flags
        // OFF. The per-flag watchers above intentionally ignore false
        // transitions to avoid Reality/Eternity prestige flicker, so they
        // miss these. Hook the gen counter — it only mutates on
        // resetUnlockFlags(), never on normal play. Without this, switching
        // from a mid-game slot to an empty one leaves `sidebar.activeTab`
        // stuck on a now-hidden tab and the content keeps rendering content
        // from the previous slot.
        .onChange(of: engine.unlockFlagsGen) { _, _ in
            sidebar.validateSelection(engine: engine)
        }
        .onChange(of: engine.pendingECNavigation) { _, navigate in
            if navigate {
                engine.pendingECNavigation = false
                sidebar.selectSubtab(.timeStudies, in: .eternity, engine: engine)
            }
        }
        .onChange(of: engine.autobuyersUnlocked) { _, newVal in
            guard newVal else { return }
            sidebar.validateSelection(engine: engine)
        }
        .onChange(of: engine.infinityDimsUnlocked) { _, newVal in
            guard newVal else { return }
            sidebar.validateSelection(engine: engine)
        }
    }

}

// MARK: - Game Header (matches web Modern UI layout)

private let colorInfinity = GameColor.infinity

// MARK: - Challenge header row

private struct ChallengeHeaderRow: View {
    let engine: GameEngine
    @Environment(\.sidebarState) private var sidebar

    private var isInChallenge: Bool {
        !engine.challengeDisplayText.isEmpty &&
        !engine.challengeDisplayText.contains("no active challenges")
    }

    private var isInCelestialReality: Bool {
        !engine.currentCelestialReality.isEmpty
    }

    /// Composite label "Celestial Reality + Challenge A + Challenge B"
    /// matching web `HeaderChallengeDisplay.vue:92-101`. The per-tick poll
    /// already joins nested challenges with " + "; we just prepend the
    /// celestial name if we're inside one.
    private var combinedLabel: String {
        var parts: [String] = []
        if isInCelestialReality { parts.append(engine.currentCelestialReality) }
        if isInChallenge { parts.append(engine.challengeDisplayText) }
        return parts.joined(separator: " + ")
    }

    /// Text for the single contextual Exit button. Matches web
    /// `exitDisplay()` — Challenge > Reality precedence. Empty when Doomed
    /// (Pelle's Reality is permanent; web hides the exit affordance).
    private var exitText: String {
        if isInChallenge { return "Exit Challenge" }
        if engine.pelleDoomed { return "" }
        if isInCelestialReality { return "Exit Reality" }
        return ""
    }

    private var exitBorderColor: Color {
        isInChallenge ? GameColor.good : GameColor.celestials
    }

    var body: some View {
        // Single-line banner — "You are currently in X + Y + Z" with one
        // contextual Exit button — plus a second line when the Nameless
        // Ones hint timer is ticking. Wraps freely when narrow.
        VStack(alignment: .center, spacing: 3) {
            if isInChallenge || isInCelestialReality {
                mainLine
            }
            if !engine.challengePowerText.isEmpty {
                Text(engine.challengePowerText)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if engine.enslavedHintTimerVisible && !engine.enslavedHintTimerText.isEmpty {
                // Web `HeaderChallengeEffects.vue` — visible while
                // `Enslaved.canTickHintTimer`, counting down to the
                // 5-hour threshold that unlocks the hints system.
                Text("The Nameless Ones are helping you look for cracks in their Reality — they can give you some advice in \(engine.enslavedHintTimerText)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(GameColor.enslaved.readableOnDark())
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !engine.laitelaRunEntropyText.isEmpty {
                Text("Entropy: \(engine.laitelaRunEntropyText)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(GameColor.laitela.readableOnDark())
            }
            if !engine.laitelaRunGameSpeedText.isEmpty {
                Text(engine.laitelaRunGameSpeedText)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(GameColor.laitela.readableOnDark())
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var mainLine: some View {
        // Web `HeaderChallengeDisplay.vue` rewrites the banner to add
        // "Good luck." when in Pelle's permanent Doomed Reality.
        let bannerText: String = engine.pelleDoomed && !isInChallenge
            ? "You are currently in a Doomed Reality. Good luck."
            : "You are currently in \(combinedLabel)"
        return HStack(spacing: 8) {
            Text(bannerText)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if !exitText.isEmpty {
                Button {
                    Haptics.tap()
                    if isInChallenge {
                        engine.exitChallenge()
                    } else {
                        engine.resetReality()
                    }
                } label: {
                    Text(exitText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(GameColor.sidebarBackground)
                        .roundedBorder(exitBorderColor, cornerRadius: 4)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Black Hole header row

/// iPad-sized version of `BHStateText` — replaces the `⟦PULSE⟧` token with
/// the `arrow.up.left.and.arrow.down.right` SF Symbol inline.
private struct iPadBHState: View {
    let raw: String
    var body: some View {
        let parts = raw.components(separatedBy: "⟦PULSE⟧")
        if parts.count == 2 {
            HStack(spacing: 3) {
                Text("🌀\(parts[0])")
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                Text(parts[1])
            }
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
        } else {
            Text("🌀\(raw)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
        }
    }
}

private struct BlackHoleHeaderRow: View {
    let engine: GameEngine

    var body: some View {
        // Buttons share a 32pt min height (+6pt vs pre-bump) for easier tapping.
        HStack(spacing: 8) {
            GameButton(borderColor: .green, isEnabled: true) {
                engine.toggleBlackHolePause()
            } label: {
                Text(engine.blackHoleHeaderPauseText)
                    .font(.system(size: 12, weight: .bold))
                    .padding(.vertical, 6)
            }
            .frame(width: 140, height: 32)

            // Charge / Stop Charging — hidden entirely while pulsing, since
            // the Pulse loop owns `isStoringGameTime` and a manual toggle
            // would just fight the auto-release cycle.
            // Always show Charge when available. Earlier logic hid it
            // when `headerIsPulsing` was true, but that gate proved too
            // aggressive — Charge disappeared even at game stages where
            // pulse isn't unlocked.
            if engine.headerEnslavedChargeVisible {
                GameButton(theme: .enslaved, isEnabled: true) {
                    engine.toggleEnslavedStoreBlackHole()
                } label: {
                    Text(engine.headerEnslavedIsCharging ? "Stop Charging" : "Charge")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.vertical, 6)
                }
                .frame(width: 120, height: 32)
            }

            ForEach(Array(engine.blackHoleHeaderStates.enumerated()), id: \.offset) { _, state in
                iPadBHState(raw: state)
            }

            // Discharge — one-shot dump of stored game time.
            if engine.headerEnslavedChargeVisible {
                GameButton(theme: .enslaved, isEnabled: engine.headerCanDischarge) {
                    engine.dischargeEnslavedBlackHole()
                } label: {
                    Text("Discharge: \(engine.headerStoredTimeText)")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .padding(.vertical, 6)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(minWidth: 120, maxWidth: 180, minHeight: 32, maxHeight: 32)
                .opacity(engine.headerCanDischarge ? 1 : 0.5)
            }

            // Pulse toggle — auto-discharge 1% every 5 ticks. Distinct
            // SF symbol (`arrow.up.left.and.arrow.down.right`) from the
            // bolt used for Charge.
            if engine.headerCanPulse {
                GameButton(theme: .enslaved, isEnabled: true) {
                    engine.toggleEnslavedAutoPulse()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                        Text("Pulse:")
                        Text(engine.headerIsPulsing ? "ON" : "OFF")
                            .foregroundStyle(engine.headerIsPulsing ? .yellow : .white.opacity(0.6))
                    }
                    .font(.system(size: 11, weight: .bold))
                    .padding(.vertical, 6)
                }
                .frame(width: 110, height: 32)
            }
        }
        .padding(.bottom, 4)
    }
}

struct GameHeaderView: View {
    let engine: GameEngine
    /// Pinned height grows with optional rows. Base 150pt fits the 3-column
    /// prestige cluster (60pt button + AM/sec/RM line + antimatter line). The
    /// challenge banner + game speed text + Black Hole row stack below; each
    /// adds its own height when present. Without this, post-Reality + active
    /// challenge (especially in Pelle's Doomed Reality where the 3-line
    /// Armageddon button replaces the single-line Reality button) overflows
    /// the clip and "The game is running at normal speed" gets cut off.
    static func pinnedHeight(bhVisible: Bool,
                             hasChallenge: Bool = false,
                             hasGameSpeed: Bool = false) -> CGFloat {
        var h: CGFloat = 150
        // Challenge banner: bold banner text + Exit button, may wrap to two
        // lines for long composite labels ("Doomed Reality + 8th AD Autobuyer
        // Challenge"). 36pt covers single + most wrapped cases.
        if hasChallenge { h += 36 }
        // Single-line "The game is running at X speed."
        if hasGameSpeed { h += 18 }
        // Black Hole row (pause + per-BH status). Same +76pt as before.
        if bhVisible { h += 76 }
        return h
    }

    private var inf: InfinityState { engine.gameState.infinity }

    @Environment(\.sidebarState) private var sidebar

    var body: some View {
        GeometryReader { geo in
            let sideWidth = geo.size.width * 0.27

            VStack(spacing: 4) {
                HStack(alignment: .top, spacing: 0) {
                    // Left column — EP display / Unlock ID / Eternity button
                    VStack(spacing: 6) {
                        if engine.eternityUnlocked {
                            Text("\(Text(engine.currentEP).foregroundStyle(GameColor.eternity).font(.system(size: 17, weight: .bold).monospacedDigit())) Eternity \(engine.currentEP == "1" ? "Point" : "Points")")
                                .foregroundStyle(.white.opacity(0.7))
                                .font(.system(size: 13).monospacedDigit())
                        }

                        if inf.isDilationActive && inf.showEternityButton {
                            EternityButtonView(engine: engine)
                        } else if inf.isBroken && inf.nextIDVisible && !inf.isInEternityChallenge {
                            Button {
                                if inf.nextIDCanUnlock {
                                    Haptics.tap()
                                    let isFirstID = inf.nextIDHasIPUnlock
                                    engine.unlockNextInfinityDimension()
                                    if isFirstID {
                                        sidebar?.selectSubtab(.infinityDimensions, in: .dimensions, engine: engine)
                                    }
                                }
                            } label: {
                                Text(nextIDText)
                                    .font(.system(size: 12, weight: .bold))
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(colorInfinity)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, minHeight: 60)
                                    .background(.black, in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(colorInfinity, lineWidth: 2)
                                    )
                                    .opacity(inf.nextIDCanUnlock ? 1 : 0.5)
                            }
                            .allowsHitTesting(inf.nextIDCanUnlock)
                        } else if inf.showEternityButton {
                            EternityButtonView(engine: engine)
                        }
                    }
                    .frame(width: sideWidth)

                    // Center column — antimatter + production + tickspeed + Reality.
                    // 30Hz-updating text is factored into leaf subviews
                    // (`AntimatterReadout`, `AntimatterRateReadout`,
                    // `TickspeedReadout`) so the outer header VStack doesn't
                    // re-evaluate every tick.
                    VStack(spacing: 4) {
                        AntimatterReadout(engine: engine)
                            .onboardingAnchor(.antimatterCounter, active: engine.onboarding != nil)

                        if engine.pelleDoomed {
                            // Web header during doom shows "You have X
                            // Reality Shards" under the antimatter line —
                            // mirrors `RealityShardsHeader` in
                            // ArmageddonButton.vue's parent.
                            PelleRealityShardsReadout(engine: engine)
                        } else if inf.showRealityButton {
                            RealityMachinesReadout(engine: engine)
                        } else {
                            AntimatterRateReadout(engine: engine)
                        }

                        if engine.pelleDoomed {
                            // Replace the Reality button when Doomed —
                            // mirrors web ArmageddonButton.vue header variant.
                            PelleArmageddonHeaderButton(engine: engine)
                        } else if inf.showRealityButton {
                            RealityButtonView(engine: engine)
                        } else {
                            TickspeedReadout(engine: engine)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // Right column — IP + Big Crunch button
                    VStack(spacing: 6) {
                        if engine.infinityUnlocked {
                            Text("\(Text(engine.currentIP).foregroundStyle(colorInfinity).font(.system(size: 17, weight: .bold).monospacedDigit())) Infinity \(engine.currentIP == "1" ? "Point" : "Points")")
                                .foregroundStyle(.white.opacity(0.7))
                                .font(.system(size: 13).monospacedDigit())
                        }

                        if inf.isBroken {
                            BigCrunchButtonView(engine: engine)
                        }
                    }
                    .frame(width: sideWidth)
                }

                // Challenge display — full width, below the 3-column header
                ChallengeHeaderRow(engine: engine)
                    .opacity(engine.challengeDisplayText.isEmpty && engine.currentCelestialReality.isEmpty ? 0 : 1)

                // Game speed display (post-Reality). When pulsing, append the
                // pulsed-speed value with the "expand arrows" SF symbol,
                // matching web GameSpeedDisplay.vue.
                if !engine.gameSpeedText.isEmpty {
                    HStack(spacing: 4) {
                        Text(engine.gameSpeedText)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                        if engine.headerIsGameSpeedPulsing, !engine.headerPulsedSpeedText.isEmpty {
                            HStack(spacing: 3) {
                                Text("(")
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                Text(engine.headerPulsedSpeedText)
                                Text(")")
                            }
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.yellow.opacity(0.85))
                        }
                    }
                }

                // Black Hole header (post-Reality, when BH unlocked)
                if engine.blackHolesHeaderVisible {
                    BlackHoleHeaderRow(engine: engine)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 12)
    }

    private var nextIDText: String {
        if inf.nextIDCanUnlock {
            return inf.nextIDHasIPUnlock
                ? "Unlock a new type of Dimension."
                : "Unlock a new Infinity Dimension."
        }
        if inf.nextIDHasIPUnlock {
            return "Reach \(inf.nextIDIPRequirement) Infinity Points and \(inf.nextIDAmRequirement) antimatter to unlock a new type of Dimension."
        }
        return "Reach \(inf.nextIDAmRequirement) antimatter to unlock a new Infinity Dimension."
    }

}

// MARK: - Prestige button leaves
//
// Each button is extracted into its own struct so the header's outer VStack
// doesn't re-evaluate every tick when button text (EP/IP/RM gain, rate lines,
// EC completion count) churns at 30Hz. Same observation-scoping trick as the
// AM/tickspeed readouts above. Parent only invalidates when structural gates
// (`showEternityButton`, `showRealityButton`, `isBroken`) flip.

/// Left-column eternity button — 7 display branches (first-time, EC goal/failed/
/// next, dilation TP gain, normal EP gain + rates). Reads 9 30Hz fields on `inf`.
private struct EternityButtonView: View {
    let engine: GameEngine
    private var inf: InfinityState { engine.gameState.infinity }

    var body: some View {
        let canEternity = inf.canEternity
        let isDilated = inf.isDilationActive && canEternity
        let buttonColor: Color = isDilated ? GameColor.dilationGreen : GameColor.eternity
        Button {
            if canEternity { Haptics.tap() }
            engine.requestEternity()
        } label: {
            VStack(spacing: 2) {
                if !canEternity {
                    // Cannot eternity — show goal
                    Text("Reach \(inf.eternityGoal)")
                        .font(.system(size: 12, weight: .bold))
                    Text("Infinity Points")
                        .font(.system(size: 11, weight: .semibold))
                } else if !inf.eternityUnlocked {
                    // First time — flavor text
                    Text("Other times await...\nI need to become Eternal")
                        .font(.system(size: 12, weight: .bold))
                        .multilineTextAlignment(.center)
                } else if inf.isInEternityChallenge {
                    // In Eternity Challenge
                    if !canEternity {
                        // Can't eternity yet — show IP goal
                        Text("Other challenges await...")
                            .font(.system(size: 12, weight: .bold))
                        Text("Reach \(inf.eternityGoal) IP")
                            .font(.system(size: 11, weight: .medium))
                    } else if inf.ecFullyCompleted {
                        Text("Other challenges await...")
                            .font(.system(size: 12, weight: .bold))
                        Text("(This challenge is already fully completed)")
                            .font(.system(size: 11, weight: .medium))
                    } else {
                        Text("Other challenges await...")
                            .font(.system(size: 12, weight: .bold))
                        Text("\(inf.ecGainedCompletions) completion\(inf.ecGainedCompletions == 1 ? "" : "s") on Eternity")
                            .font(.system(size: 11, weight: .medium))
                        if !inf.ecFailedRestriction.isEmpty {
                            Text(inf.ecFailedRestriction)
                                .font(.system(size: 10, weight: .medium))
                        } else if inf.ecHasMoreCompletions && !inf.ecNextGoalAt.isEmpty {
                            Text("Next goal at \(inf.ecNextGoalAt) IP")
                                .font(.system(size: 10, weight: .medium))
                        }
                    }
                } else if inf.isDilationActive {
                    // Dilation — show tachyon particle gain
                    Text("Eternity for \(inf.dilationTachyonGain)")
                        .font(.system(size: 12, weight: .bold))
                    Text("Tachyon Particles")
                        .font(.system(size: 11, weight: .semibold))
                } else {
                    // Normal — show EP gain and rates
                    Text("Eternity for \(inf.gainedEP) EP")
                        .font(.system(size: 12, weight: .bold))
                    if inf.showEPRate {
                        Text("Current: \(inf.currentEPRate) EP/min")
                            .font(.system(size: 10, weight: .medium))
                        Text("Peak: \(inf.peakEPRate) EP/min")
                            .font(.system(size: 10, weight: .medium))
                        Text("at \(inf.peakEPRateVal) EP")
                            .font(.system(size: 10, weight: .medium))
                    }
                }
            }
            .foregroundStyle(buttonColor)
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(.black, in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(buttonColor, lineWidth: 2)
            )
            .opacity(canEternity ? 1.0 : 0.6)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(canEternity)
    }
}

/// Center-column reality button — three states (no study, EP too low, can
/// reality). Reads `gainedRM`, `machineStats`, `gainedGlyphLevel`, and
/// `realityButtonSpecial` for the glow modifier.
private struct RealityButtonView: View {
    let engine: GameEngine
    private var inf: InfinityState { engine.gameState.infinity }

    var body: some View {
        let canReality = inf.canReality
        let hasStudy = inf.hasRealityStudy
        let special = canReality && engine.realityButtonSpecial
        VStack(spacing: 2) {
            if !hasStudy {
                // Post-Reality reset: study not yet re-bought
                Text("Purchase the study in the Eternity tab to unlock a new Reality")
                    .font(.system(size: 12, weight: .bold))
                    .multilineTextAlignment(.center)
            } else if !canReality {
                // Study bought but EP too low
                Text("Get 1e4000 Eternity Points to unlock a new Reality")
                    .font(.system(size: 12, weight: .bold))
                    .multilineTextAlignment(.center)
            } else {
                // Can reality
                Text("Make a new Reality")
                    .font(.system(size: 13, weight: .bold))
                Text("\(inf.gainedRM) \(inf.machineStats)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                Text(inf.gainedGlyphLevel)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
            }
        }
        .foregroundStyle(canReality ? GameColor.reality : .gray)
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .frame(maxWidth: 400, minHeight: 60)
        .background(canReality ? .black : Color(white: 0.15), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(canReality ? GameColor.reality : .gray, lineWidth: 2)
        )
        .modifier(RealityButtonGlow(active: special))
        .onTapGesture {
            if canReality {
                Haptics.tap()
                engine.requestReality()
            }
        }
    }
}

/// "You have X Reality Shards" — header line shown under the antimatter
/// readout while Doomed. Mirrors the web header arrangement.
private struct PelleRealityShardsReadout: View {
    let engine: GameEngine

    var body: some View {
        Text("You have \(Text(engine.pelleRealityShardsText).foregroundStyle(GameColor.pelle.readableOnDark()).fontWeight(.bold)) Reality Shards.")
            .font(.system(size: 14))
            .foregroundStyle(.white.opacity(0.85))
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// Armageddon header button — replaces RealityButtonView when
/// `engine.pelleDoomed`. 3 lines, copy matches web ArmageddonButton.vue:
///   "You cannot escape a Doomed Reality!"
///   "Armageddon for X Remnants"
///   "Reality Shards X/s ➔ Y/s"
private struct PelleArmageddonHeaderButton: View {
    let engine: GameEngine

    var body: some View {
        let canArm = engine.pelleCanArmageddon
        VStack(spacing: 2) {
            Text("You cannot escape a Doomed Reality!")
                .font(.system(size: 12, weight: .bold))
                .multilineTextAlignment(.center)
            Text("Armageddon for \(Text(engine.pelleRemnantsGainText).foregroundStyle(GameColor.pelle.readableOnDark()).fontWeight(.bold)) Remnants")
                .font(.system(size: 13, weight: .bold).monospacedDigit())
            Text("Reality Shards \(Text(engine.pelleRealityShardsPerSecText).foregroundStyle(GameColor.pelle.readableOnDark())) ➔ \(Text(engine.pelleRealityShardsRateAfterText).foregroundStyle(GameColor.pelle.readableOnDark()))")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
        }
        .foregroundStyle(canArm ? GameColor.pelle.readableOnDark() : .gray)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: 400, minHeight: 60)
        .background(canArm ? .black : Color(white: 0.15), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(canArm ? GameColor.pelle : .gray, lineWidth: 2)
        )
        .onTapGesture {
            if canArm {
                Haptics.tap()
                engine.pelleArmageddon()
            }
        }
    }
}

/// Right-column post-break Big Crunch button — swaps to a white Tesseract
/// purchase button when `tesseractAffordable && enslavedCompleted`. Reads
/// `gainedIP`, `currentIPRate`, `peakIPRate`, `peakIPRateVal`, `infinityGoal`.
private struct BigCrunchButtonView: View {
    let engine: GameEngine
    private var inf: InfinityState { engine.gameState.infinity }

    var body: some View {
        let tessGlow = engine.tesseractAffordable && engine.enslavedCompleted
        Button {
            if tessGlow {
                Haptics.tap()
                engine.buyTesseract()
            } else if inf.canCrunch {
                Haptics.tap()
                engine.bigCrunch()
            }
        } label: {
            VStack(spacing: 2) {
                if tessGlow {
                    Text("You have enough Infinity Points\nto buy a Tesseract")
                } else if inf.canCrunch {
                    if inf.inAntimatterChallenge {
                        Text("Big Crunch to\ncomplete the challenge")
                    } else if inf.showIPRate {
                        Text("Big Crunch for \(inf.gainedIP) IP")
                        Text("Current: \(inf.currentIPRate) IP/min")
                            .font(.system(size: 10, weight: .regular))
                        Text("Peak: \(inf.peakIPRate) IP/min")
                            .font(.system(size: 10, weight: .regular))
                        Text("at \(inf.peakIPRateVal) IP")
                            .font(.system(size: 10, weight: .regular))
                    } else {
                        Text("Big Crunch for\n\(inf.gainedIP) Infinity Points")
                    }
                } else {
                    Text("Reach \(inf.infinityGoal)\nantimatter")
                }
            }
            .font(.system(size: 12, weight: .bold))
            .multilineTextAlignment(.center)
            .foregroundStyle(tessGlow ? .black : colorInfinity)
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(tessGlow ? Color(hex: "#eeeeee") : .black,
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(tessGlow ? .white : colorInfinity, lineWidth: 2)
            )
            .modifier(TesseractGlow(active: tessGlow))
            .opacity(tessGlow || inf.canCrunch ? 1 : 0.5)
        }
        .allowsHitTesting(tessGlow || inf.canCrunch)
    }
}

// MARK: - Header 30Hz text leaves
//
// Each of these reads exactly the engine property it displays. Observation
// scoping means the enclosing `GameHeaderView` body does NOT re-evaluate
// when any of these values change — only the leaf view re-composes. This
// keeps the header's static layout (VStacks, side columns, prestige
// buttons) stable across ticks even though the number text churns at 30Hz.

/// Big "You have X antimatter." line in the header center column.
private struct AntimatterReadout: View {
    let engine: GameEngine
    var body: some View {
        Text("You have \(Text(engine.antimatter).foregroundStyle(GameColor.antimatter).font(.system(size: 28, weight: .bold).monospacedDigit())) antimatter.")
            .foregroundStyle(.white)
            .font(.system(size: 15).monospacedDigit())
            .multilineTextAlignment(.center)
    }
}

/// "You are getting X antimatter per second." shown pre-Reality-unlock.
private struct AntimatterRateReadout: View {
    let engine: GameEngine
    var body: some View {
        Text("You are getting \(engine.antimatterPerSec) antimatter per second.")
            .font(.system(size: 13).monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
    }
}

/// "You have X Reality Machines." shown post-Reality-unlock in the same
/// header slot as the AM/sec readout.
private struct RealityMachinesReadout: View {
    let engine: GameEngine
    var body: some View {
        Text("You have \(Text(engine.currentRMHeaderDisplay).foregroundStyle(GameColor.reality)) Reality Machines.")
            .foregroundStyle(.white.opacity(0.6))
            .font(.system(size: 13).monospacedDigit())
    }
}

/// Two-line tickspeed readout — shown pre-Reality in place of the Reality
/// button. Isolates the `tickspeedMultiplier` + `tickspeedPerSecond` 30Hz
/// reads from the header VStack.
private struct TickspeedReadout: View {
    let engine: GameEngine
    var body: some View {
        VStack(spacing: 2) {
            Text("ADs produce \(engine.tickspeedMultiplier) faster per Tickspeed upgrade")
            Text("Total Tickspeed: \(engine.tickspeedPerSecond) / sec")
        }
        .font(.system(size: 11).monospacedDigit())
        .foregroundStyle(.white.opacity(0.5))
        .opacity(engine.tickspeedUnlocked ? 1 : 0)
    }
}

// MARK: - Reality button glow

/// Pulsing green glow applied to the Reality button whenever completing
/// Reality would improve a celestial-run reward (Teresa new-best,
/// Effarig stage advance, Enslaved first completion). Mirrors the web's
/// `c-reality-button--special` animation from RealityButton.vue.
///
/// Scene-phase aware: SwiftUI's `.repeatForever` animation is implemented as
/// a Core Animation CAAnimation that keeps interpolating (and keeps the
/// render server + app active) even while the app is backgrounded. We
/// collapse `pulse` to 0 whenever the scene leaves `.active` so the CPU
/// goes quiet on lock/home. Resumes on foreground.
private struct RealityButtonGlow: ViewModifier {
    let active: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var pulse = false

    private var shouldAnimate: Bool { active && scenePhase == .active }

    func body(content: Content) -> some View {
        content
            .shadow(color: GameColor.reality.opacity(active ? (pulse ? 0.9 : 0.35) : 0),
                    radius: active ? (pulse ? 18 : 10) : 0)
            .shadow(color: GameColor.reality.opacity(active ? (pulse ? 0.6 : 0.25) : 0),
                    radius: active ? 28 : 0)
            .onAppear { updatePulse(animating: shouldAnimate) }
            .onChange(of: shouldAnimate) { _, nowAnimating in
                updatePulse(animating: nowAnimating)
            }
    }

    private func updatePulse(animating: Bool) {
        if animating {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.25)) { pulse = false }
        }
    }
}

/// White glow on the Big Crunch button when a Tesseract is affordable.
/// Scene-phase aware — tears down on background to save battery.
struct TesseractGlow: ViewModifier {
    let active: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var pulse = false

    private var shouldAnimate: Bool { active && scenePhase == .active }

    func body(content: Content) -> some View {
        content
            .shadow(color: .white.opacity(active ? (pulse ? 0.8 : 0.3) : 0),
                    radius: active ? (pulse ? 12 : 6) : 0)
            .shadow(color: .white.opacity(active ? (pulse ? 0.5 : 0.2) : 0),
                    radius: active ? 20 : 0)
            .onAppear { updatePulse(animating: shouldAnimate) }
            .onChange(of: shouldAnimate) { _, nowAnimating in
                updatePulse(animating: nowAnimating)
            }
    }

    private func updatePulse(animating: Bool) {
        if animating {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                pulse = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.25)) { pulse = false }
        }
    }
}

// MARK: - Interaction tracking (event-driven)
//
// We don't try to observe raw touches any more. Earlier attempts:
//   1. `simultaneousGesture(DragGesture(minimumDistance: 0))` — interfered
//      with UIKit Pickers / SegmentedControls and drag-and-drop.
//   2. `PassthroughTouchView` overlay with `hitTest → nil` — didn't fire
//      on iPhone content inside `UIPageViewController` (SubtabPager).
//   3. Window-level `UIGestureRecognizer` (AMInteractionObserver) — broke
//      glyph drag-and-drop → subtab swipe / tab bar navigation, even with
//      state-transition deferral and `canPrevent` overrides. UIDragInteraction
//      is too fragile around peer window recognizers.
//
// Instead, `engine.recordInteraction()` is called from discrete user
// action sites: tab bar taps (PhoneTabBar + sidebar tabs), dimension buys,
// prestige actions, and any GameButton tap. This misses pure idle
// scrolling but catches every meaningful input that should reset the idle
// clock. A dedicated toggle in Options already lets the user disable
// dynamic throttling entirely. The `onTouchDownGesture(_:)` extension is
// retained as a no-op so existing call sites keep compiling.

extension View {
    /// Deprecated no-op. Kept so existing `.onTouchDownGesture { ... }`
    /// call sites on `ContentView`/`PhoneShell` compile without changes
    /// while we migrate to discrete `recordInteraction()` call sites.
    /// Does nothing — safe to remove once all callers are updated.
    func onTouchDownGesture(perform action: @escaping () -> Void) -> some View {
        self
    }
}

#Preview {
    ContentView()
}
