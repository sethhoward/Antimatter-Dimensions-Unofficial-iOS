//
//  PhoneShell.swift
//  AntiMatter
//
//  iPhone shell — custom paging tab bar with compact header overlay.
//  Shares ContentSwitcher, SidebarState, and all tab views with iPad.
//  Tap active tab bar icon to cycle subtabs (same as iPad sidebar).
//  "More" button pages through sets of 4 tabs.
//

import SwiftUI
import UniformTypeIdentifiers

struct PhoneShell: View {
    let engine: GameEngine
    @State private var sidebar = SidebarState()

    /// Tracks which tab was last selected so we can detect re-taps for subtab cycling.
    @State private var previousTab: SidebarTab = .dimensions

    /// Wall-clock time of the last tab-bar tap that actually fired a navigation.
    /// Used to debounce rapid taps — UIPageViewController's `_UIQueuingScrollView`
    /// crashes ("Don't know about flushed view" / "Duplicate states in queue")
    /// when `setViewControllers` is called faster than its internal flush can
    /// settle. We coalesce taps that come within `tabTapDebounceInterval` so
    /// only the last target survives.
    @State private var lastTabTapTime: TimeInterval = 0
    @State private var pendingTabTap: DispatchWorkItem?
    /// Matches UIPageViewController's scroll-style transition (~320–360ms,
    /// undocumented). Anything shorter lets a follow-up tap fire
    /// `setViewControllers` while the prior animation is still in flight,
    /// which is what trips `_UIQueuingScrollView`'s assertions.
    private static let tabTapDebounceInterval: TimeInterval = 0.35

    /// Current page of the tab bar (0-indexed). Only used when paging is needed.
    @State private var tabPage: Int = 0

    /// Top safe area inset — read once, used to pull header up into safe area.
    @State private var topSafeArea: CGFloat = 59

    /// Measured height of the floating tab bar overlay (for content bottom padding).
    @State private var tabBarHeight: CGFloat = 0

    /// Shared paging gesture coordinator — created once by PhoneShell so we
    /// can observe it here (to freeze the pager's top padding while the user
    /// swipes) AND pass it into SubtabPager.
    @State private var pagingCoordinator = PagingGestureCoordinator()

    /// Header height used for the PhoneContentArea's top padding. Mirrors
    /// `compactHeaderHeight` when the pager is idle; frozen while the user
    /// is actively swiping so the pager's frame doesn't change mid-gesture
    /// (which would cancel the swipe and snap it back).
    @State private var stableHeaderHeight: CGFloat = 110

    /// Set when compactHeaderHeight changes during a swipe; flushed as soon
    /// as the pager's gesture ends.
    @State private var pendingHeaderHeight: CGFloat?

    /// Pending shrink — only fired when `compactHeaderHeight` has been
    /// strictly lower than `stableHeaderHeight` for `compactHeaderShrinkDelay`
    /// seconds. Asymmetric debounce: header grows immediately, shrinks only
    /// after the state settles. Absorbs rapid flicker (automated challenge
    /// cycling, BH pulse toggling, banner enter/exit) without permanent
    /// dead space and without an "always reserve" rule. See the design notes →
    /// "Compact header sizing invariants".
    @State private var shrinkWorkItem: DispatchWorkItem?

    #if DEBUG
    /// Drives the DEBUG overlay's `↓Ns` countdown. Updated by a Timer while
    /// a shrink is pending; nil otherwise.
    @State private var shrinkCountdownTimer: Timer?
    @State private var shrinkFireDate: Date?
    #endif

    /// Default 6s — long enough to span typical autobuyer challenge-cycle
    /// latency (~1-2s per restart) with margin, without making manual exit
    /// transitions feel sluggish. Tune here if a longer settle becomes
    /// necessary for some new gameplay pattern.
    private static let compactHeaderShrinkDelay: TimeInterval = 3.0

    /// Pull header up into the safe area to reclaim vertical space.
    /// 30% of the safe area gives ~18pt on Dynamic Island devices while
    /// keeping content clear of the notch/island hardware.
    private var headerPullUp: CGFloat { topSafeArea * 0.3 }

    private var availableTabs: [SidebarTab] {
        SidebarTab.allCases.filter {
            $0.isAvailable(engine: engine) && !$0.isHidden(engine: engine)
        }
    }

    /// Subtabs the user can actually reach (unlocked AND not hidden via
    /// Modify Visible Tabs). Drives `SubtabPager`, tab cycling, and the
    /// subtab-index binding. The Modify Visible Tabs sheet itself uses
    /// `availableSubtabs(engine:)` to surface ALL unlocked subtabs (even
    /// hidden ones, so the user can toggle them back on).
    private var currentAvailableSubtabs: [Subtab] {
        sidebar.activeTab.availableVisibleSubtabs(engine: engine)
    }

    /// Single source of truth binding: reads index from sidebar state, writes swipe changes back.
    /// Eliminates the dual @State / @Observable sync that caused intermittent desync.
    private var subtabIndexBinding: Binding<Int> {
        Binding(
            get: {
                let subtabs = currentAvailableSubtabs
                return subtabs.firstIndex(of: currentSubtab) ?? 0
            },
            set: { newIndex in
                let subtabs = currentAvailableSubtabs
                guard newIndex >= 0, newIndex < subtabs.count else { return }
                let subtab = subtabs[newIndex]
                guard subtab != currentSubtab else { return }
                sidebar.selectSubtab(subtab, in: sidebar.activeTab, engine: engine)
            }
        )
    }

    // MARK: - Paging

    private let tabsPerPage = 5

    /// Move the tab bar to the page containing the given tab.
    private func navigateToPage(containing tab: SidebarTab) {
        guard availableTabs.count > tabsPerPage + 1,
              let idx = availableTabs.firstIndex(of: tab) else {
            // Paging not needed — reset to page 0 so the tab bar doesn't
            // stay stranded on a stale page (e.g. after hard reset).
            if tabPage != 0 { tabPage = 0 }
            return
        }
        let totalPages = (availableTabs.count + tabsPerPage - 1) / tabsPerPage
        tabPage = min(idx / tabsPerPage, totalPages - 1)
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // Content area — always shows the active tab's content
            tabContent

            // EP/IP currency row — sits at the absolute screen top
            // in the status bar zone flanking the Dynamic Island
            if engine.eternityUnlocked || engine.infinityUnlocked {
                NotchCurrencyRow(engine: engine)
                    .ignoresSafeArea(edges: .top)
            }
        }
        .overlay(alignment: .bottom) {
            PhoneTabBar(
                allTabs: availableTabs,
                activeTab: sidebar.activeTab,
                tabsPerPage: tabsPerPage,
                tabPage: $tabPage,
                activeSubtabs: sidebar.lastSubtab,
                notifiedSubtabs: engine.notifiedSubtabs,
                onSelectTab: { tab in handleTabSelection(tab) },
                // `availableVisibleSubtabs` skips user-hidden subtabs so
                // long-press context menus + the badge-on-hidden-subtab
                // filter inside PhoneTabBar both match what the user can
                // actually navigate to.
                availableSubtabsFor: { tab in tab.availableVisibleSubtabs(engine: engine) },
                onSelectSubtab: { tab, subtab in
                    if sidebar.activeTab != tab {
                        sidebar.selectTab(tab, engine: engine)
                    }
                    sidebar.selectSubtab(subtab, in: tab, engine: engine)
                },
                engine: engine,
                isOnADSubtab: sidebar.activeSubtab == .antimatterDimensions
            )
            // GameEnd TAB_START_HIDE — fade tabs from 1.5 → 2.5 over the
            // 1-unit window. Stays at 0 above 2.5 (matches web v-if).
            .opacity(tabBarOpacityForGameEnd)
            .background {
                GeometryReader { geo in
                    Color.clear.preference(key: TabBarHeightKey.self, value: geo.size.height)
                }
            }
            .onPreferenceChange(TabBarHeightKey.self) { tabBarHeight = $0 }
            .onboardingAnchor(.tabNav, active: engine.onboarding != nil)
        }
        // New-player onboarding callouts. The dimension buy button lives inside
        // the SubtabPager (CALayer rows) and can't take an anchorPreference, so
        // its callout degrades to a centered card; the header counter + tab bar
        // anchor normally. No-op unless onboarding.phase == .callouts.
        .onboardingCalloutOverlay(engine: engine)
        .statusBarHidden()
        .background {
            GeometryReader { geo in
                Color.clear.onAppear { topSafeArea = geo.safeAreaInsets.top }
            }
            .frame(height: 0)
        }
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
        .environment(\.layoutMetrics, .compact)
        .onAppear {
            // Give the engine a weak handle to this shell's SidebarState so
            // hidden-tab recovery / SA47 / future helpers can drive sidebar
            // changes from engine-side callbacks without each call site
            // plumbing sidebar through.
            engine.sidebarStateRef = sidebar
        }
        .sheet(item: Binding(
            get: { engine.pendingModal },
            set: { engine.pendingModal = $0 }
        )) { modal in
            PrestigeConfirmation(modal: modal, engine: engine)
                .environment(\.sidebarState, sidebar)
                .environment(\.layoutMetrics, .compact)
        }
        .sheet(isPresented: Binding(
            get: { engine.showGlyphSelection },
            set: { engine.showGlyphSelection = $0 }
        )) {
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
        // GameEnd credits roll. Presented post-CREDITS_START (4.5) until
        // the user closes it via gameEndCloseCredits() — survives a relaunch
        // because GameEnd.creditsClosed is persisted on the JS side.
        //
        // Re-inject `.sidebarState` across the fullScreenCover boundary so
        // the credits → New Game flow lands on the REAL SidebarState (not a
        // phantom fresh one). Without this, the `SpeedrunStartModal`
        // presented from CreditsOverlay sees a nil env value and falls back
        // to a fresh `SidebarState()`, leaving the user stuck on whatever
        // subtab was active pre-reset (e.g. Time Dimensions) while the tab
        // bar correctly hides the Eternity tab.
        .fullScreenCover(isPresented: Binding(
            get: { engine.gameEndCreditsActive },
            set: { _ in /* dismissal goes through engine.gameEndCloseCredits() */ }
        )) {
            CreditsOverlay(engine: engine)
                .environment(\.sidebarState, sidebar)
        }
        // GameEnd FADE_AWAY + INTERACTIVITY_DISABLED (endState >= 2.5).
        // Dim the underlying game UI and block taps until the credits
        // overlay covers everything at CREDITS_START (4.5).
        .opacity(engine.gameEndInteractivityDisabled ? 0.4 : 1)
        .allowsHitTesting(!engine.gameEndInteractivityDisabled)
        // Only validate/navigate when flags turn ON (new unlock). During
        // Reality resets, flags momentarily go false then restore within a
        // tick or two — validating on the false transition would redirect the
        // user away from their current tab and back to Dimensions.
        .onChange(of: engine.infinityUnlocked) { _, newVal in
            guard newVal else { return }
            sidebar.validateSelection(engine: engine)
            navigateToPage(containing: sidebar.activeTab)
        }
        // Explicit reset paths (hardReset, switchSaveSlot, importSave,
        // restoreBackup, startSpeedrun) bump `unlockFlagsGen` and may turn
        // flags OFF. The `infinityUnlocked` watcher above intentionally
        // skips false transitions to avoid Reality/Eternity prestige
        // flicker, so it doesn't catch these. Hook the gen counter
        // instead — it only mutates on resetUnlockFlags(), never on normal
        // play. Without this, switching from a mid-game slot to an empty
        // one leaves `sidebar.activeTab` stuck on .challenges/.eternity/
        // etc. while the tab bar correctly hides them — the content area
        // still renders C1-C9 from the previous slot.
        .onChange(of: engine.unlockFlagsGen) { _, _ in
            sidebar.validateSelection(engine: engine)
            navigateToPage(containing: sidebar.activeTab)
        }
        .onChange(of: engine.pendingECNavigation) { _, navigate in
            if navigate {
                engine.pendingECNavigation = false
                sidebar.selectSubtab(.timeStudies, in: .eternity, engine: engine)
                navigateToPage(containing: .eternity)
            }
        }
        .onChange(of: engine.autobuyersUnlocked) { _, newVal in
            guard newVal else { return }
            sidebar.validateSelection(engine: engine)
            navigateToPage(containing: sidebar.activeTab)
        }
        .onChange(of: engine.infinityDimsUnlocked) { _, newVal in
            guard newVal else { return }
            sidebar.validateSelection(engine: engine)
            navigateToPage(containing: sidebar.activeTab)
        }
        .onChange(of: engine.eternityUnlocked) { _, newVal in
            guard newVal else { return }
            sidebar.validateSelection(engine: engine)
            navigateToPage(containing: sidebar.activeTab)
        }
        .onChange(of: engine.realityUnlocked) { _, newVal in
            guard newVal else { return }
            sidebar.validateSelection(engine: engine)
            navigateToPage(containing: sidebar.activeTab)
        }
        .onChange(of: engine.realityStudyBought) { _, newVal in
            guard newVal else { return }
            sidebar.validateSelection(engine: engine)
            navigateToPage(containing: sidebar.activeTab)
        }
        .onChange(of: engine.teresaUnlocked) { _, newVal in
            guard newVal else { return }
            sidebar.validateSelection(engine: engine)
            navigateToPage(containing: sidebar.activeTab)
        }
        .onChange(of: engine.dilationUnlocked) { _, newVal in
            guard newVal else { return }
            sidebar.validateSelection(engine: engine)
            navigateToPage(containing: sidebar.activeTab)
        }
        // Alerts (JS Error, Challenge) are handled by ContentView at the outer level.
    }

    /// Tab-bar opacity during the GameEnd fade-out window.
    /// Linear from 1.0 at endState 1.5 to 0.0 at endState 2.5; clamped 0..1.
    private var tabBarOpacityForGameEnd: Double {
        let es = engine.endStateValue
        if es < GameEndMarker.tabStartHide { return 1 }
        if es >= GameEndMarker.interactDisabled { return 0 }
        return 1 - (es - GameEndMarker.tabStartHide)
            / (GameEndMarker.interactDisabled - GameEndMarker.tabStartHide)
    }

    // MARK: - Tab selection (detects re-taps for subtab cycling)

    private func handleTabSelection(_ newTab: SidebarTab) {
        // Debounce: if the user is hammering the tab bar, only the latest
        // tap survives. Without this, each tap fires a setViewControllers
        // before the previous one's internal queue settles, crashing
        // UIPageViewController's _UIQueuingScrollView.
        let now = Date.timeIntervalSinceReferenceDate
        let elapsed = now - lastTabTapTime
        if elapsed < Self.tabTapDebounceInterval {
            // Cancel any prior pending tap and replace with this one.
            pendingTabTap?.cancel()
            let work = DispatchWorkItem { performTabSelection(newTab) }
            pendingTabTap = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + (Self.tabTapDebounceInterval - elapsed),
                execute: work
            )
            return
        }
        performTabSelection(newTab)
    }

    private func performTabSelection(_ newTab: SidebarTab) {
        lastTabTapTime = Date.timeIntervalSinceReferenceDate
        pendingTabTap = nil
        if newTab == previousTab && newTab == sidebar.activeTab {
            // Re-tap on the active tab on iPhone — cycle to next subtab.
            // (iPad's accordion-toggle behavior in `selectTab` is a no-op
            // here since there's no accordion to expand on iPhone.)
            // Use the visible (non-hidden) subtab list so cycling matches
            // what's reachable via swipe + long-press menu.
            let available = newTab.availableVisibleSubtabs(engine: engine)
            guard available.count > 1 else { return }
            let current = sidebar.lastSubtab[newTab] ?? newTab.defaultSubtab
            let nextIndex: Int = {
                if let idx = available.firstIndex(of: current) {
                    return (idx + 1) % available.count
                }
                return 0
            }()
            sidebar.selectSubtab(available[nextIndex], in: newTab, engine: engine)
        } else {
            // Switch to new tab — sidebar.selectTab updates lastSubtab,
            // which the computed subtabIndexBinding reads automatically.
            sidebar.selectTab(newTab, engine: engine)
            previousTab = newTab
        }
    }

    // MARK: - Subtab for the active tab

    private var currentSubtab: Subtab {
        sidebar.lastSubtab[sidebar.activeTab] ?? sidebar.activeTab.defaultSubtab
    }

    // MARK: - Content (header overlay + content + toast)

    private var tickerHeight: CGFloat { engine.newsEnabled ? 22 : 0 }

    /// Dynamic header height based on which persistent elements are visible.
    /// Dynamic header height — only reserves challenge space when actually in a challenge.
    /// The .animation on the header VStack smooths the grow/shrink transition.
    private var compactHeaderHeight: CGFloat {
        // Header reserves a "challenge label" row whenever any banner is
        // shown — challenge OR celestial reality — so layout doesn't jitter
        // when the player enters/exits a celestial run. Pelle's Doomed
        // Reality is permanent and shows the banner WITHOUT an Exit button
        // (smaller row); pass the distinction so reserved height matches.
        //
        // All inputs are diff-checked @Observable bool flags on `engine` —
        // none of them go through `engine.gameState` (which gets reassigned
        // every tick by pollDirect). PhoneShell.body's observation of these
        // properties invalidates only when a transition actually flips a
        // flag, not on every tick where the underlying infinity struct
        // happens to be rebuilt.
        let hasBanner = engine.compactBannerVisible
        // `compactBannerHasExit` mirrors whether CompactChallengeLabel renders
        // an Exit button — true in any challenge (even while Doomed, since the
        // EC can be exited), so doom + EC reserves the taller 28pt banner row.
        // NOT `hasBanner && !pelleDoomed`, which under-reserved doom + EC.
        let bannerHasExit = engine.compactBannerHasExit
        let rateMode = engine.compactShowEPRate || engine.compactShowIPRate
        return CompactHeaderView.pinnedHeight(
            bhVisible: engine.blackHolesHeaderVisible,
            hasChallenge: hasBanner,
            bannerHasExit: bannerHasExit,
            hasChallengePower: engine.compactChallengePowerVisible,
            hasGameSpeed: engine.compactGameSpeedVisible,
            hasRM: engine.realityUnlocked,
            prestigeRateMode: rateMode,
            hasBroken: engine.compactIsBroken,
            postRealityStudy: engine.compactShowRealityButton,
            hasSpeedrun: engine.speedrunQuick.isActive,
            showPreBreakCrunch: engine.compactShowPreBreakCrunch
        )
    }

    private var tabContent: some View {
        ZStack(alignment: .top) {
            // Main content fills entire area, padded below header + ticker
            // PhoneContentArea isolates engine.gameState observation so PhoneShell
            // body doesn't re-evaluate every tick when gameState changes.
            PhoneContentArea(
                engine: engine,
                sidebar: sidebar,
                currentAvailableSubtabs: currentAvailableSubtabs,
                currentSubtab: currentSubtab,
                subtabIndexBinding: subtabIndexBinding,
                tabBarHeight: tabBarHeight,
                pagingCoordinator: pagingCoordinator
            )
            // Use the frozen height so the pager's frame doesn't change while
            // the user is swiping (which would cancel the gesture).
            .padding(.top, stableHeaderHeight - headerPullUp + tickerHeight + 1)

            // Header + news ticker overlay pinned to top — offset up into safe area
            VStack(spacing: 0) {
                CompactHeaderView(engine: engine)
                    .frame(height: stableHeaderHeight, alignment: .top)
                    .onboardingAnchor(.antimatterCounter, active: engine.onboarding != nil)
                    .clipped()
                    #if DEBUG
                    .overlay(alignment: .bottomLeading) {
                        if engine.showCompactHeaderHeightOverlay {
                            HeaderHeightOverlay(
                                reserved: compactHeaderHeight,
                                stable: stableHeaderHeight,
                                actual: engine.compactHeaderActualHeight,
                                shrinkSecondsRemaining: engine.compactHeaderShrinkPendingSeconds
                            )
                            .padding(2)
                        }
                    }
                    #endif

                if engine.newsEnabled {
                    NewsTickerView(engine: engine, height: 22)
                }

                GameColor.antimatter.frame(height: 1)
            }
            .offset(y: -headerPullUp)
            .background(GameColor.baseBackground)
            .animation(.easeInOut(duration: 0.25), value: engine.newsEnabled)
            // Animate the debounced height, not the raw formula output —
            // otherwise grows would animate via the formula change but
            // shrinks would jump instantly to the formula's new low
            // (the debounce only delays `stableHeaderHeight`, not the
            // formula). Animating on `stableHeaderHeight` keeps both
            // directions visually smooth and aligned with the
            // `tabContent` padding offset above (which also tracks
            // `stableHeaderHeight`).
            .animation(.easeInOut(duration: 0.25), value: stableHeaderHeight)

            // Toast overlay — top center on iPhone
            VStack {
                HStack {
                    Spacer()
                    ToastOverlay(engine: engine)
                    Spacer()
                }
                Spacer()
            }
        }
        .onChange(of: compactHeaderHeight) { _, newHeight in
            // Defer padding changes while the pager is actively swiping or
            // decelerating. Applying them immediately would resize the
            // pager's UIPageViewController frame, which cancels the in-flight
            // pan gesture and snaps the swipe back to the origin page.
            if pagingCoordinator.isUserInteracting {
                pendingHeaderHeight = newHeight
                return
            }
            applyHeaderHeightChange(newHeight)
        }
        .onChange(of: pagingCoordinator.isUserInteracting) { _, interacting in
            if !interacting, let pending = pendingHeaderHeight {
                pendingHeaderHeight = nil
                applyHeaderHeightChange(pending)
            }
        }
        .onAppear {
            // Initialize stable height on first render. Grow path takes
            // over on the first real change.
            stableHeaderHeight = compactHeaderHeight
        }
        .onDisappear {
            // Avoid lingering timers / work items if the shell is torn down
            // while a shrink is pending (defensive — PhoneShell is the app
            // root on iPhone, so this shouldn't fire in practice).
            cancelPendingShrink()
        }
        .onChange(of: sidebar.activeTab) { _, _ in
            engine.selectSubtab(currentSubtab)
            // Programmatic tab changes (hard reset, validateSelection,
            // confirmation flows) need to drag the paging tab bar with
            // them. Without this, after a hard reset the active tab can
            // become .dimensions while `tabPage` is stranded on whichever
            // page the user was viewing pre-reset — Options disappears,
            // Eternity stays visible. Cheap to call when paging isn't
            // needed (returns early inside navigateToPage).
            navigateToPage(containing: sidebar.activeTab)
        }
        // When the available tab list shrinks (hard reset, slot switch,
        // backup restore that drops progress) reset the tab page to 0 so
        // we don't leave the user staring at empty space where page 1 used
        // to be. The unlock-flag .onChange handlers above only fire on
        // TRUE transitions, so they don't catch the "tabs going away" path.
        .onChange(of: availableTabs) { oldVal, newVal in
            guard newVal.count < oldVal.count else { return }
            if tabPage != 0 { tabPage = 0 }
            navigateToPage(containing: sidebar.activeTab)
        }
        .onChange(of: currentSubtab) { _, newSubtab in
            engine.selectSubtab(newSubtab)
        }
    }

    // MARK: - Asymmetric header-height debounce
    //
    // The compact header reserves space additively per visible row (BH,
    // game-speed line, RM, challenge banner, etc.). When a row turns off,
    // the formula's output drops immediately — but if we mirrored every
    // shrink into `stableHeaderHeight` instantly, automated play patterns
    // (autobuyer cycling NCs, BH pulse toggling) would bounce the header
    // visibly every fraction of a second. Instead we apply grows
    // immediately and debounce shrinks by `compactHeaderShrinkDelay`. If
    // the formula climbs back above the pending target during the wait,
    // the shrink cancels and we re-anchor to the new high-water mark.
    //
    // Composition with pager-swipe freeze: the swipe-freeze path in
    // `.onChange(of: compactHeaderHeight)` short-circuits before we get
    // here; on swipe-release the deferred height is replayed through this
    // same path so the grow/shrink discriminator applies uniformly.

    /// Routes a new `compactHeaderHeight` value through the grow/shrink
    /// discriminator. Caller has already cleared the pager-swipe gate.
    private func applyHeaderHeightChange(_ newHeight: CGFloat) {
        if newHeight >= stableHeaderHeight {
            // Growing or unchanged at the high-water mark — snap up and
            // cancel any in-flight shrink targeting the old low.
            cancelPendingShrink()
            if stableHeaderHeight != newHeight {
                stableHeaderHeight = newHeight
            }
        } else {
            scheduleShrink()
        }
    }

    /// Schedules a delayed shrink to `compactHeaderHeight`. Replaces any
    /// prior pending shrink so the timer always reflects the most recent
    /// low value. The work item re-reads `compactHeaderHeight` at fire
    /// time to handle the case where the formula climbed back above
    /// `stableHeaderHeight` during the wait (in which case the grow path
    /// has already updated us and we bail out).
    private func scheduleShrink() {
        cancelPendingShrink()
        let work = DispatchWorkItem {
            #if DEBUG
            // Clear countdown state regardless of whether we apply the
            // shrink — the timer has finished its job.
            self.shrinkCountdownTimer?.invalidate()
            self.shrinkCountdownTimer = nil
            self.shrinkFireDate = nil
            self.engine.compactHeaderShrinkPendingSeconds = nil
            #endif
            // Re-read at fire time. If the formula has recovered above
            // stable during the delay, the grow path already snapped us
            // back up; nothing to do.
            let current = self.compactHeaderHeight
            guard current < self.stableHeaderHeight else {
                self.shrinkWorkItem = nil
                return
            }
            self.stableHeaderHeight = current
            self.shrinkWorkItem = nil
        }
        shrinkWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.compactHeaderShrinkDelay,
            execute: work
        )
        #if DEBUG
        shrinkFireDate = Date().addingTimeInterval(Self.compactHeaderShrinkDelay)
        engine.compactHeaderShrinkPendingSeconds = Self.compactHeaderShrinkDelay
        // Tick the countdown 10x/s so the overlay reads naturally.
        shrinkCountdownTimer?.invalidate()
        shrinkCountdownTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard let fire = self.shrinkFireDate else { return }
            let remaining = fire.timeIntervalSinceNow
            if remaining <= 0 {
                self.engine.compactHeaderShrinkPendingSeconds = nil
            } else {
                self.engine.compactHeaderShrinkPendingSeconds = remaining
            }
        }
        #endif
    }

    /// Cancels any pending shrink + countdown. Safe to call repeatedly;
    /// no-op when nothing is pending.
    private func cancelPendingShrink() {
        shrinkWorkItem?.cancel()
        shrinkWorkItem = nil
        #if DEBUG
        shrinkCountdownTimer?.invalidate()
        shrinkCountdownTimer = nil
        shrinkFireDate = nil
        engine.compactHeaderShrinkPendingSeconds = nil
        #endif
    }
}

#if DEBUG
// MARK: - Compact header height overlay (DEBUG)

/// Renders the `R / S / A / Δ / ↓Ns` readout used to calibrate compact-header
/// row heights. `R` = `pinnedHeight(...)` (instantaneous formula output);
/// `S` = `stableHeaderHeight` (frame size after debounce); `A` = measured
/// content height via `CompactHeaderActualHeightKey`. `Δ` = `S - A`;
/// healthy values are `[0, 1]`. `↓Ns` appears only when a shrink is
/// pending and counts down to apply. Enable via Debug tab → "Show compact
/// header height overlay".
private struct HeaderHeightOverlay: View {
    let reserved: CGFloat
    let stable: CGFloat
    let actual: CGFloat
    let shrinkSecondsRemaining: Double?

    var body: some View {
        HStack(spacing: 6) {
            Text("R:\(Int(reserved.rounded()))")
            Text("S:\(Int(stable.rounded()))")
            Text("A:\(Int(actual.rounded()))")
            Text("Δ\(Int((stable - actual).rounded()))")
                .foregroundStyle(stable - actual > 1 ? .yellow : .green)
            if let secs = shrinkSecondsRemaining {
                Text("↓\(String(format: "%.1fs", secs))")
                    .foregroundStyle(.orange)
            }
        }
        .font(.system(size: 8, design: .monospaced))
        .foregroundStyle(.green)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(Color.black.opacity(0.7))
        .cornerRadius(2)
    }
}
#endif

// MARK: - Isolated progress bar (prevents PhoneShell body re-eval at 30Hz)

/// Isolates `engine.gameState` observation from PhoneShell's body.
/// Without this, gameState changing every tick (dimension amounts, etc.) caused
/// the entire PhoneShell (SubtabPager, ContentSwitcher, PhoneTabBar, overlays,
/// ~9 .onChange modifiers) to re-evaluate at 30Hz.
private struct PhoneContentArea: View {
    let engine: GameEngine
    let sidebar: SidebarState
    let currentAvailableSubtabs: [Subtab]
    let currentSubtab: Subtab
    let subtabIndexBinding: Binding<Int>
    let tabBarHeight: CGFloat
    let pagingCoordinator: PagingGestureCoordinator

    var body: some View {
        ZStack {
            GameColor.baseBackground
                .ignoresSafeArea(edges: [.horizontal, .top])

            if engine.gameState.infinity.showBigCrunchTakeoverFirstOnly {
                BigCrunchTakeover(engine: engine)
            } else if currentAvailableSubtabs.count <= 1 {
                ContentSwitcher(subtab: currentSubtab, engine: engine)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .safeAreaPadding(.bottom, tabBarHeight)
                    .ignoresSafeArea(.container, edges: .bottom)
            } else {
                SubtabPager(
                    availableSubtabs: currentAvailableSubtabs,
                    activeSubtabIndex: subtabIndexBinding,
                    engine: engine,
                    bottomSafeArea: tabBarHeight,
                    gestureCoordinator: pagingCoordinator
                ) { subtab in
                    // `UIHostingController` creates a fresh environment; re-inject
                    // sidebarState so views inside paged content can gate
                    // continuous animations on `activeSubtab`.
                    ContentSwitcher(subtab: subtab, engine: engine)
                        .environment(\.sidebarState, sidebar)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: .bottom)
            }
        }
    }
}

// MARK: - Tab bar height measurement

private struct TabBarHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
