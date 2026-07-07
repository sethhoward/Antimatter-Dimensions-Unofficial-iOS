//
//  SubtabPager.swift
//  AntiMatter
//
//  UIPageViewController wrapper for horizontal swipe between subtabs (iPhone only).
//  Provides native paging with lazy page instantiation and gesture conflict
//  resolution with inner ZoomableScrollViews.
//
//  Crash-stability notes (rapid taps + swipes):
//  UIPageViewController's internal `_UIQueuingScrollView` flushes asynchronously
//  past the public completion handler (it fires ~100ms BEFORE the flush finishes).
//  Calling `setViewControllers` again before the queue settles trips assertions:
//  "Don't know about flushed view", "Duplicate states in queue", or
//  `_flushViewController:animated:` failures.
//  Mitigations live in four places, in priority order:
//    1. PhoneShell.handleTabSelection — 350ms input debounce (load-bearing).
//    2. Post-completion settle — `transitionCompleted` (shared by the
//       programmatic completion AND swipe `didFinishAnimating`) holds
//       `isTransitioning` true across ONE ~100ms settle instead of clearing it
//       synchronously, so a real change (subtab unlock/hide, tab switch, cycle,
//       swipe-then-tap) landing in the flush window defers instead of firing
//       `setViewControllers` into the unsettled queue. A generation token keeps
//       a stale settle from clearing a newer transition's flag.
//    3. Coordinator.pendingTargetIndex — coalesces the tap-during-swipe case
//       where the swipe path bypasses the input debounce. Drained by the settle.
//    4. transitionTimeoutTimer — 600ms fallback for dropped completions.
//  Approaches that look reasonable but DO NOT WORK: `pageVC.dataSource = nil`
//  toggle (assertion-fires on the assignment), a hard blanket post-transition
//  cooldown gate in updateUIViewController (felt sluggish — the settle in #2 is
//  narrow and reuses the defer path instead), polling-based pending-apply (fires
//  too soon), and a SECOND stacked settle on the drain (doubles latency, feels
//  like the cooldown). See the design notes → "SubtabPager Known Issues".
//

import SwiftUI

// MARK: - Paging gesture coordinator (environment-injectable)

/// Holds a reference to the UIPageViewController's internal pan gesture recognizer
/// so that inner ZoomableScrollViews can set up failure dependencies.
/// On iPad (or when no pager exists), this is nil in the environment.
@Observable
final class PagingGestureCoordinator {
    weak var pagingPanGesture: UIGestureRecognizer?
    weak var pagingScrollView: UIScrollView?
    weak var pageViewController: UIPageViewController?

    /// True while the user's finger is on the pager (pan began, not yet ended)
    /// OR the pager is mid-transition animation. Consumers (e.g. PhoneShell)
    /// can use this to defer parent-frame changes that would otherwise cancel
    /// the in-flight pan gesture and reset the swipe.
    var isUserInteracting: Bool = false

    /// Set by SubtabPager's delegate while a swipe/animated transition is
    /// in progress. Combined with live pan state into `isUserInteracting`.
    fileprivate var isTransitioning: Bool = false {
        didSet { recomputeInteraction() }
    }

    /// Latest live pan-gesture state. Updated via a UIKit target attached to
    /// the pager's internal pan gesture when the pager is built.
    private var panActive: Bool = false {
        didSet { recomputeInteraction() }
    }

    /// Tracks the post-release deceleration / settle animation on the
    /// underlying scroll view. Observed via KVO so we can keep frame-
    /// changing parent views stable until the pager has fully landed.
    private var scrollViewDecelerating: Bool = false {
        didSet { recomputeInteraction() }
    }

    private var decelerationObservation: NSKeyValueObservation?

    private func recomputeInteraction() {
        let newValue = panActive || scrollViewDecelerating || isTransitioning
        if isUserInteracting != newValue { isUserInteracting = newValue }
    }

    /// Attach pan-state tracking once we have the scroll view's pan recognizer.
    /// Called by SubtabPager after it extracts the recognizer from the
    /// UIPageViewController's internal scroll view.
    func beginTrackingPanState() {
        guard let pan = pagingPanGesture else { return }
        pan.removeTarget(self, action: nil)
        pan.addTarget(self, action: #selector(handlePan(_:)))

        decelerationObservation?.invalidate()
        decelerationObservation = pagingScrollView?.observe(\.isDecelerating, options: [.new]) { [weak self] sv, _ in
            self?.scrollViewDecelerating = sv.isDecelerating
        }
    }

    @objc private func handlePan(_ g: UIGestureRecognizer) {
        switch g.state {
        case .began, .changed:
            panActive = true
        case .ended, .cancelled, .failed, .recognized:
            panActive = false
        default:
            break
        }
    }

    /// KVO observation that snaps `contentOffset` back while paging is
    /// suspended. UIKit's drag auto-scroll (triggered when a UIDragSession's
    /// preview nears scroll-view edges) can change `contentOffset`
    /// programmatically, bypassing `isScrollEnabled` and `isEnabled`.
    private var offsetObservation: NSKeyValueObservation?
    private var isSnapping = false

    /// Temporarily disable paging (e.g. while a drag session is active).
    /// Re-enables automatically — callers must set back to `true` when done.
    ///
    /// Disabling:
    ///   1. `isScrollEnabled = false` blocks future user-initiated scrolls.
    ///   2. `isEnabled = false` on the pan recognizer cancels any in-progress
    ///      gesture (transitions it to `.cancelled`) — `isScrollEnabled`
    ///      alone does NOT cancel a pan that has already started tracking.
    ///   3. Snap the scroll view's `contentOffset` back to the current page's
    ///      x-origin. Cancelling mid-pan leaves `contentOffset` at an
    ///      in-between value; for index 0 that's inside the "before" slot
    ///      (which `viewControllerBefore` returned nil for), showing blank.
    ///   4. Observe `contentOffset` via KVO and snap back on every change.
    ///      Needed because UIKit's drag auto-scroll programmatically sets
    ///      `contentOffset` when the drag preview nears a scroll-view edge,
    ///      bypassing our gesture-level guards.
    var isPagingEnabled: Bool = true {
        didSet {
            guard oldValue != isPagingEnabled else { return }
            pagingScrollView?.isScrollEnabled = isPagingEnabled
            pagingPanGesture?.isEnabled = isPagingEnabled
            if !isPagingEnabled {
                snapToCurrentPage()
            }
        }
    }

    /// Install a permanent KVO on the pager's internal scroll view that
    /// snaps contentOffset back to the current page ONLY when the change
    /// is programmatic and not our own animation — i.e. iOS drag
    /// auto-scroll. Heuristic:
    ///   • `isDragging` / `isDecelerating` true → user swipe, let it through
    ///   • `isTransitioning` true → our own `setViewControllers(animated:)`,
    ///     let it through
    ///   • otherwise → unaccounted programmatic change = drag auto-scroll,
    ///     snap back
    ///
    /// This replaces the earlier on-demand `beginOffsetFreeze` /
    /// `endOffsetFreeze` + `isPagingEnabled` disable approach, which
    /// required a reliable glyph-drag-end callback SwiftUI doesn't
    /// provide. The old approach would leave paging silently locked
    /// if `.onDrop` never fired (cancelled drag), causing the Reality
    /// tab to go blank and subtab swipe to stop working.
    ///
    /// This observer always runs; it's effectively a no-op except
    /// during active drag auto-scroll. User swipes and programmatic
    /// tab navigation pass through untouched.
    func installDragAutoScrollGuard() {
        offsetObservation?.invalidate()
        offsetObservation = pagingScrollView?.observe(\.contentOffset, options: [.new]) { [weak self] sv, _ in
            guard let self else { return }
            if self.isSnapping { return }
            if sv.isDragging || sv.isDecelerating { return }
            if self.isTransitioning { return }
            // Programmatic change that isn't ours or a deceleration.
            // iOS drag auto-scroll is the only expected source.
            self.snapToCurrentPage()
        }
    }

    /// Snap the internal scroll view to the currently-visible view controller's
    /// x-origin. Works for both 2-page (edge) and 3-page (middle) layouts
    /// because we derive the offset from the visible VC's frame.
    private func snapToCurrentPage() {
        guard !isSnapping,
              let sv = pagingScrollView,
              let pvc = pageViewController,
              let visibleVC = pvc.viewControllers?.first else { return }
        let frameInScroll = visibleVC.view.superview?.convert(visibleVC.view.frame, to: sv) ?? visibleVC.view.frame
        let targetX = frameInScroll.origin.x
        if abs(sv.contentOffset.x - targetX) > 0.5 {
            isSnapping = true
            sv.setContentOffset(CGPoint(x: targetX, y: sv.contentOffset.y), animated: false)
            isSnapping = false
        }
    }

    /// Call on touch-down within a drag source (e.g. glyph tile) to pre-emptively
    /// block the pager from recognizing a horizontal pan before `.onDrag` fires
    /// (which has a ~0.5s long-press threshold).
    func suspendForDragSource() { isPagingEnabled = false }
    func resumeAfterDragSource() { isPagingEnabled = true }
}

private struct PagingGestureCoordinatorKey: EnvironmentKey {
    static let defaultValue: PagingGestureCoordinator? = nil
}

extension EnvironmentValues {
    var pagingGestureCoordinator: PagingGestureCoordinator? {
        get { self[PagingGestureCoordinatorKey.self] }
        set { self[PagingGestureCoordinatorKey.self] = newValue }
    }
}

// MARK: - SubtabPager

struct SubtabPager<Content: View>: UIViewControllerRepresentable {
    let availableSubtabs: [Subtab]
    @Binding var activeSubtabIndex: Int
    let engine: GameEngine
    /// Bottom safe area inset applied via UIKit's additionalSafeAreaInsets
    /// on each page's UIHostingController. More reliable than SwiftUI's
    /// .safeAreaPadding inside a UIHostingController boundary.
    var bottomSafeArea: CGFloat = 0
    /// Owned by the enclosing shell (PhoneShell) so its `isUserInteracting`
    /// state can be read to defer parent-frame changes while the user is
    /// swiping. A default is provided for callers that don't need the hook.
    var gestureCoordinator: PagingGestureCoordinator = PagingGestureCoordinator()
    @ViewBuilder let content: (Subtab) -> Content

    /// Wraps content with the paging gesture coordinator environment value
    /// and forces it to fill the page. UIHostingController creates a new environment
    /// boundary, so we must re-inject environment values explicitly.
    private func wrappedContent(for subtab: Subtab) -> some View {
        content(subtab)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.pagingGestureCoordinator, gestureCoordinator)
            // Until proper accessibility support lands, clamp Dynamic Type
            // at `.large` (system default) so paged content matches what we
            // developed against. The App-level modifier doesn't cross the
            // UIHostingController boundary.
            .dynamicTypeSize(...DynamicTypeSize.large)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pageVC = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: 0]
        )
        pageVC.dataSource = context.coordinator
        pageVC.delegate = context.coordinator
        pageVC.view.backgroundColor = .clear
        gestureCoordinator.pageViewController = pageVC

        // Find the internal UIScrollView and extract its pan gesture
        for subview in pageVC.view.subviews {
            if let scrollView = subview as? UIScrollView {
                gestureCoordinator.pagingPanGesture = scrollView.panGestureRecognizer
                gestureCoordinator.pagingScrollView = scrollView
                break
            }
        }
        // Start tracking live pan state for callers (e.g. PhoneShell) that
        // need to defer parent-frame changes until the swipe finishes.
        gestureCoordinator.beginTrackingPanState()
        // Permanent guard against iOS drag auto-scroll flipping pages
        // during glyph drag. Filters programmatic contentOffset mutations
        // that aren't user swipes or our own animations.
        gestureCoordinator.installDragAutoScrollGuard()

        // Set the initial page
        let clampedIndex = min(activeSubtabIndex, availableSubtabs.count - 1)
        let initialIndex = max(0, clampedIndex)
        if !availableSubtabs.isEmpty {
            let subtab = availableSubtabs[initialIndex]
            let vc = context.coordinator.hostingController(for: subtab) { s in
                AnyView(wrappedContent(for: s))
            }
            pageVC.setViewControllers([vc], direction: .forward, animated: false)
            context.coordinator.currentIndex = initialIndex
        }

        return pageVC
    }

    func updateUIViewController(_ pageVC: UIPageViewController, context: Context) {
        let coord = context.coordinator
        let subtabsChanged = coord.previousSubtabs != availableSubtabs
        coord.previousSubtabs = availableSubtabs
        coord.availableSubtabs = availableSubtabs
        coord.bottomSafeArea = bottomSafeArea
        coord.wrappedContentBuilder = { subtab in
            AnyView(self.wrappedContent(for: subtab))
        }

        // Update bottom safe area on all cached hosting controllers
        coord.updateSafeAreaInsets()

        guard !availableSubtabs.isEmpty else { return }

        // Keep cached hosting controllers across parent-tab switches so each
        // subtab's `UIScrollView.contentOffset` (and any inner scroll state)
        // is preserved when the user returns. Previously this called
        // `coord.clearCache()` on subtabsChanged, which reset every ScrollView.

        let clampedIndex = min(activeSubtabIndex, availableSubtabs.count - 1)
        let targetIndex = max(0, clampedIndex)

        // Update when the index changed, subtabs changed (tab switch), or a reset is pending
        guard targetIndex != coord.currentIndex || subtabsChanged || coord.needsReset else { return }
        coord.needsReset = false

        let direction: UIPageViewController.NavigationDirection =
            targetIndex >= coord.currentIndex ? .forward : .reverse
        let subtab = availableSubtabs[targetIndex]
        let vc = coord.hostingController(for: subtab, content: coord.wrappedContentBuilder)

        // If the target VC is already what's displayed, just sync the index
        // and skip the call entirely. The synchronous completion would race
        // against a real in-flight animation by flipping `isTransitioning`
        // back to false too early.
        if pageVC.viewControllers?.first === vc {
            coord.currentIndex = targetIndex
            return
        }

        // Defer when UIPageViewController's internal _UIQueuingScrollView is
        // mid-flush — calling setViewControllers during that window trips
        // `-[UIPageViewController _flushViewController:animated:]`'s
        // assertion. Possible busy states:
        //   • user is actively dragging (pan in flight)
        //   • scroll view is decelerating after release
        //   • a previous animated setViewControllers is still flushing
        //     (`coord.isTransitioning`)
        // We poll on the runloop until the queue settles, then apply the
        // pending target. Without the polling loop, a tap during a
        // transition would get silently dropped — SwiftUI doesn't re-invoke
        // updateUIViewController unless state changes again.
        let scrollBusy = coord.gestureCoordinator?.pagingScrollView.map {
            $0.isDragging || $0.isDecelerating
        } ?? false
        if scrollBusy || coord.isTransitioning {
            coord.pendingTargetIndex = targetIndex
            coord.schedulePendingApply(pageVC: pageVC)
            return
        }

        // Don't animate on tab switch or when a transition is already in flight
        // (animated setViewControllers during an active transition crashes UIPageViewController)
        let shouldAnimate = !subtabsChanged && coord.availableSubtabs.count > 1

        coord.currentIndex = targetIndex
        coord.weakPageVC = pageVC
        // Always mark in-flight, even for animated: false. The internal
        // `_UIQueuingScrollView` flushes regardless, and rapid follow-up
        // taps during that flush window are what trip "Don't know about
        // flushed view".
        coord.markTransitionStart()

        pageVC.setViewControllers([vc], direction: direction, animated: shouldAnimate) { [weak coord] _ in
            guard let coord else { return }
            coord.transitionCompleted(pageVC: pageVC)
        }
    }

    func makeCoordinator() -> Coordinator {
        let coord = Coordinator(
            availableSubtabs: availableSubtabs,
            activeSubtabIndex: $activeSubtabIndex,
            wrappedContentBuilder: { subtab in
                AnyView(self.wrappedContent(for: subtab))
            }
        )
        coord.gestureCoordinator = gestureCoordinator
        return coord
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var availableSubtabs: [Subtab]
        var previousSubtabs: [Subtab] = []
        @Binding var activeSubtabIndex: Int
        var wrappedContentBuilder: (Subtab) -> AnyView
        var currentIndex: Int = 0
        var needsReset = false
        var isTransitioning = false {
            didSet { gestureCoordinator?.isTransitioning = isTransitioning }
        }
        var bottomSafeArea: CGFloat = 0
        /// Set by SubtabPager.makeCoordinator — mirrors transition state so
        /// PhoneShell can observe it via `gestureCoordinator.isUserInteracting`.
        weak var gestureCoordinator: PagingGestureCoordinator?

        // MARK: - Rapid-tap coalescing + post-completion settle
        //
        // UIPageViewController is fragile when `setViewControllers` is chained
        // faster than its internal `_UIQueuingScrollView` can finish a flush.
        // Its completion handler fires ~100ms BEFORE the queuing scroll view
        // finishes flushing, so clearing `isTransitioning` synchronously in the
        // completion leaves a window where the re-entry guards read "idle" while
        // the queue is still mid-flush. A real change (subtab unlock/hide, tab
        // switch, ⌘]/re-tap cycle, or swipe-then-tab-tap) landing in that window
        // fires `setViewControllers` into the unsettled queue and trips
        // `-[UIPageViewController _flushViewController:animated:]` (also the
        // "Don't know about flushed view" / "Duplicate states in queue" family).
        //
        // Strategy: hold `isTransitioning` across ONE ~100ms settle after every
        // completion (see `transitionCompleted`), so a change arriving in the
        // flush window defers through `pendingTargetIndex` instead of calling
        // `setViewControllers` directly. Rapid taps still collapse to one
        // transition + a "snap to latest" follow-up, driven off the completion
        // handler + a single fixed settle — never a polling loop, and never a
        // second stacked delay (that would double a deferred transition's
        // latency and feel like the rejected 400ms cooldown).

        /// Fixed settle after a transition completes, covering the
        /// `_UIQueuingScrollView` flush window. Empirically ~100ms is enough.
        private let settleDelay: TimeInterval = 0.1
        /// Cap on the busy-retry chain so a sustained drag / churning tab can't
        /// spin the settle reschedule forever.
        private let maxSettleRetries = 20

        /// Latest target the user wants to land on. Overwritten by every
        /// rapid tap so we always end up at the most recent target.
        fileprivate var pendingTargetIndex: Int?
        /// Weak ref to the current pageVC so completion-driven applies can
        /// find it without re-plumbing through closures.
        fileprivate weak var weakPageVC: UIPageViewController?
        /// Defensive fallback: if the completion handler is dropped (UIKit
        /// known issue when transitions are interrupted), this timer
        /// force-clears `isTransitioning` so we don't get permanently stuck.
        private var transitionTimeoutTimer: Timer?
        /// The single post-completion settle work item (clears `isTransitioning`
        /// + drains any pending target). Held so `markTransitionStart` can cancel
        /// a superseded settle when a new transition begins first.
        private var settleWorkItem: DispatchWorkItem?
        /// Monotonic transition id, bumped on every `markTransitionStart`.
        /// Captured by the settle work item + fallback timer so a stale one can't
        /// clear a newer transition's `isTransitioning` flag.
        private var transitionGeneration = 0
        /// Busy-retry counter for the settle reschedule (reset per transition).
        private var settleRetryCount = 0

        /// Called from `updateUIViewController` when the page is busy. Just
        /// stashes the latest target — the in-flight transition's completion
        /// (or the fallback timer) drains it via the settle.
        fileprivate func schedulePendingApply(pageVC: UIPageViewController) {
            weakPageVC = pageVC
            // Nothing else to do: `transitionCompleted` → `scheduleSettle` (or
            // the fallback timer) will drain the pending target after the settle.
        }

        /// Mark a transition as in-flight. Bumps the generation, cancels any
        /// superseded settle from the previous transition, resets the retry
        /// budget, and arms the dropped-completion fallback.
        fileprivate func markTransitionStart() {
            transitionGeneration &+= 1
            let generation = transitionGeneration
            // A new transition supersedes any settle scheduled by the previous one.
            settleWorkItem?.cancel()
            settleWorkItem = nil
            settleRetryCount = 0
            isTransitioning = true
            transitionTimeoutTimer?.invalidate()
            transitionTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
                // Completion handler was dropped — recover, unless a newer
                // transition already owns the flag. At 0.6s the queue is settled,
                // so drain immediately via `runSettle` (no extra settle needed).
                guard let self, self.isTransitioning,
                      self.transitionGeneration == generation else { return }
                if let pageVC = self.weakPageVC {
                    self.runSettle(pageVC: pageVC, generation: generation)
                } else {
                    self.isTransitioning = false
                }
            }
        }

        /// Called from a `setViewControllers` completion — BOTH the programmatic
        /// path (`updateUIViewController` / `applyPendingNow`) and user swipes
        /// (via `didFinishAnimating`). The internal `_UIQueuingScrollView` is
        /// still flushing here, so we do NOT clear `isTransitioning` synchronously
        /// (that opens the `_flushViewController` crash window). Kill the fallback
        /// first to preserve the single-clearer invariant, then hold the flag
        /// across one settle before clearing + draining.
        fileprivate func transitionCompleted(pageVC: UIPageViewController) {
            transitionTimeoutTimer?.invalidate()
            transitionTimeoutTimer = nil
            scheduleSettle(pageVC: pageVC)
        }

        /// Schedule the single post-completion settle. After `settleDelay`, clear
        /// `isTransitioning` and drain any pending target immediately — one hop,
        /// no second stacked delay.
        private func scheduleSettle(pageVC: UIPageViewController) {
            settleWorkItem?.cancel()
            weakPageVC = pageVC
            let generation = transitionGeneration
            let work = DispatchWorkItem { [weak self, weak pageVC] in
                guard let self, let pageVC else { return }
                self.runSettle(pageVC: pageVC, generation: generation)
            }
            settleWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay, execute: work)
        }

        /// Settle body: clear the in-flight flag (only if this settle still owns
        /// the current transition) and apply any pending target now. Reused by
        /// the 600ms fallback when a completion handler is dropped.
        private func runSettle(pageVC: UIPageViewController, generation: Int) {
            // A newer transition started since this settle was scheduled — it
            // owns the flag now; don't clear it out from under the new one.
            guard generation == transitionGeneration else { return }
            settleWorkItem = nil
            isTransitioning = false
            applyPendingNow(pageVC: pageVC)
        }

        /// Apply the latest pending target immediately — the caller (`runSettle`)
        /// guarantees the settle window already elapsed, so this hands the pager
        /// `setViewControllers` with `animated: false` right away (no extra
        /// delay). If the queue is still busy (user re-grabbed the pager), retry
        /// after another settle — capped so it can't spin forever.
        private func applyPendingNow(pageVC: UIPageViewController) {
            guard let target = pendingTargetIndex else { settleRetryCount = 0; return }
            let busy = (gestureCoordinator?.pagingScrollView?.isDragging ?? false)
                || (gestureCoordinator?.pagingScrollView?.isDecelerating ?? false)
                || isTransitioning
            if busy {
                guard settleRetryCount < maxSettleRetries else {
                    // Give up gracefully rather than spinning — drop the target.
                    settleRetryCount = 0
                    pendingTargetIndex = nil
                    return
                }
                settleRetryCount += 1
                let generation = transitionGeneration
                settleWorkItem?.cancel()
                let work = DispatchWorkItem { [weak self, weak pageVC] in
                    guard let self, let pageVC else { return }
                    self.runSettle(pageVC: pageVC, generation: generation)
                }
                settleWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay, execute: work)
                return
            }
            settleRetryCount = 0

            let clamped = max(0, min(target, availableSubtabs.count - 1))
            pendingTargetIndex = nil
            guard clamped < availableSubtabs.count else { return }
            let subtab = availableSubtabs[clamped]
            let vc = hostingController(for: subtab, content: wrappedContentBuilder)
            if pageVC.viewControllers?.first === vc {
                currentIndex = clamped
                return
            }
            let direction: UIPageViewController.NavigationDirection =
                clamped >= currentIndex ? .forward : .reverse
            currentIndex = clamped
            markTransitionStart()
            pageVC.setViewControllers([vc], direction: direction, animated: false) { [weak self, weak pageVC] _ in
                guard let self, let pageVC else { return }
                self.transitionCompleted(pageVC: pageVC)
            }
        }

        /// Cache hosting controllers keyed by Subtab. Persists for the lifetime
        /// of the coordinator so each subtab's scroll position survives both
        /// within-tab swipes and parent-tab switches.
        private var vcCache: [Subtab: UIHostingController<AnyView>] = [:]

        /// Persistent VC→Subtab mapping. Survives cache clears so
        /// `didFinishAnimating` can always identify the visible page.
        private var vcSubtabMap: [ObjectIdentifier: Subtab] = [:]

        func clearCache() {
            vcCache.removeAll()
            // Don't clear vcSubtabMap — VCs may still be displayed by UIPageViewController
        }

        init(
            availableSubtabs: [Subtab],
            activeSubtabIndex: Binding<Int>,
            wrappedContentBuilder: @escaping (Subtab) -> AnyView
        ) {
            self.availableSubtabs = availableSubtabs
            self._activeSubtabIndex = activeSubtabIndex
            self.wrappedContentBuilder = wrappedContentBuilder
        }

        func hostingController(
            for subtab: Subtab,
            content: (Subtab) -> AnyView
        ) -> UIHostingController<AnyView> {
            if let cached = vcCache[subtab] {
                cached.rootView = content(subtab)
                return cached
            }
            let vc = UIHostingController(rootView: content(subtab))
            vc.view.backgroundColor = .clear
            // Prevent UIHostingController from sizing itself to content —
            // let UIPageViewController control the frame instead.
            vc.sizingOptions = []
            vc.additionalSafeAreaInsets.bottom = bottomSafeArea
            vcCache[subtab] = vc
            vcSubtabMap[ObjectIdentifier(vc)] = subtab
            return vc
        }

        /// Update bottom safe area insets on all cached hosting controllers.
        /// Called from updateUIViewController when tabBarHeight changes.
        func updateSafeAreaInsets() {
            for vc in vcCache.values {
                if vc.additionalSafeAreaInsets.bottom != bottomSafeArea {
                    vc.additionalSafeAreaInsets.bottom = bottomSafeArea
                }
            }
        }

        /// Look up which subtab a view controller represents.
        private func subtab(for viewController: UIViewController) -> Subtab? {
            vcSubtabMap[ObjectIdentifier(viewController)]
        }

        /// Look up the index of a view controller in the current subtab list.
        private func index(of viewController: UIViewController) -> Int? {
            guard let subtab = subtab(for: viewController) else { return nil }
            return availableSubtabs.firstIndex(of: subtab)
        }

        // MARK: - UIPageViewControllerDataSource

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            // Use the reference VC's position, not currentIndex — the pager may
            // ask about a VC that isn't at currentIndex (pre-fetching, rapid swipe).
            guard let refIndex = index(of: viewController), refIndex > 0 else { return nil }
            let subtab = availableSubtabs[refIndex - 1]
            return hostingController(for: subtab, content: wrappedContentBuilder)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let refIndex = index(of: viewController),
                  refIndex < availableSubtabs.count - 1 else { return nil }
            let subtab = availableSubtabs[refIndex + 1]
            return hostingController(for: subtab, content: wrappedContentBuilder)
        }

        // MARK: - UIPageViewControllerDelegate

        func pageViewController(
            _ pageViewController: UIPageViewController,
            willTransitionTo pendingViewControllers: [UIViewController]
        ) {
            // Track via the same lifecycle as programmatic transitions so
            // the fallback timer / pending-apply chain works for swipes.
            weakPageVC = pageViewController
            markTransitionStart()
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            if completed, let visibleVC = pageViewController.viewControllers?.first,
               let idx = index(of: visibleVC) {
                currentIndex = idx
                activeSubtabIndex = idx
            }
            // Drain pending taps + clear isTransitioning + cancel fallback.
            transitionCompleted(pageVC: pageViewController)
        }
    }
}
