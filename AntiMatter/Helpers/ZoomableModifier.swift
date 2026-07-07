//
//  ZoomableModifier.swift
//  AntiMatter
//
//  Created by Seth Howard on 4/4/26.
//

import SwiftUI

struct ZoomableScrollView<Content: View>: UIViewRepresentable {

    private var content: Content
    var minZoom: CGFloat = 0.25
    var maxZoom: CGFloat = 4.0
    var bottomInset: CGFloat = 0
    /// Optional content-space point to center in the viewport on first layout.
    /// Only applied when `contentOffset` is `.zero`. Content coordinates are
    /// the unscaled values (pre-zoom); the centering math scales internally.
    var initialFocus: CGPoint?
    /// Optional tag for diagnostic logging. When set, lifecycle events
    /// (makeUIView, updateUIView size changes, layoutSubviews initial pass,
    /// centerContent) are logged via debugLog with this prefix. nil = silent.
    var debugTag: String?
    /// When non-nil, a double-tap on the SwiftUI background (NOT on any
    /// subview that has its own tap gesture, e.g. study cards) animates
    /// the scroll view back to this zoom level and re-centers. Use 1.0
    /// for "fit at natural scale". nil disables the gesture.
    var doubleTapResetZoom: CGFloat?
    @Binding var zoomScale: CGFloat
    @Binding var contentOffset: CGPoint
    @Environment(\.pagingGestureCoordinator) private var pagingCoordinator

    init(
        minZoom: CGFloat = 0.25,
        maxZoom: CGFloat = 4.0,
        bottomInset: CGFloat = 0,
        initialFocus: CGPoint? = nil,
        debugTag: String? = nil,
        doubleTapResetZoom: CGFloat? = nil,
        zoomScale: Binding<CGFloat> = .constant(1.0),
        contentOffset: Binding<CGPoint> = .constant(.zero),
        @ViewBuilder content: () -> Content
    ) {
        self.minZoom = minZoom
        self.maxZoom = maxZoom
        self.bottomInset = bottomInset
        self.initialFocus = initialFocus
        self.debugTag = debugTag
        self.doubleTapResetZoom = doubleTapResetZoom
        self._zoomScale = zoomScale
        self._contentOffset = contentOffset
        self.content = content()
    }

    func makeUIView(context: Context) -> CenteringScrollView {
        let scrollView = CenteringScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = maxZoom
        scrollView.minimumZoomScale = minZoom
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.delaysContentTouches = true
        scrollView.canCancelContentTouches = true
        scrollView.clipsToBounds = true

        let hostedView = context.coordinator.hostingController.view!
        hostedView.backgroundColor = .clear
        hostedView.clipsToBounds = true

        // Size the hosted view to its intrinsic content size
        let size = context.coordinator.hostingController.sizeThatFits(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        hostedView.frame = CGRect(origin: .zero, size: size)
        scrollView.contentSize = size
        scrollView.lastNaturalSize = size
        scrollView.addSubview(hostedView)

        // Apply the initial zoom HERE rather than deferring to the first
        // `layoutSubviews` pass. UIScrollView clamps `contentOffset`,
        // recomputes `contentSize` (× zoom factor), and lays out the
        // contentView synchronously when `zoomScale` is set — but only if
        // the zoom is set BEFORE the scroll view becomes visible. Setting
        // it inside layoutSubviews left the first frame with the
        // unzoomed contentSize, so the user could swipe through a 1x area
        // even though the visible content was at 0.5x. Once the user
        // pinch-zoomed (or tapped to zoom), UIScrollView re-clamped and
        // the scroll bounds locked correctly.
        let initialZoomVal = zoomScale > 0 ? zoomScale : 1.0
        scrollView.zoomScale = initialZoomVal
        scrollView.initialZoom = initialZoomVal
        scrollView.initialOffset = contentOffset
        scrollView.initialFocus = initialFocus
        scrollView.coordinator = context.coordinator
        scrollView.fixedBottomInset = bottomInset
        scrollView.debugTag = debugTag
        if let tag = debugTag {
            debugLog("[\(tag)] makeUIView: sizeThatFits=\(size), zoom=\(initialZoomVal), bounds=\(scrollView.bounds.size)")
        }

        // Gesture conflict resolution: if inside a SubtabPager (iPhone),
        // make the pager's pan gesture require this scroll view's pan to fail first.
        // This ensures zoomed/panned content takes priority over page swiping.
        if let pagingPan = pagingCoordinator?.pagingPanGesture {
            pagingPan.require(toFail: scrollView.panGestureRecognizer)
        }

        // Double-tap-to-reset gesture (opt-in via doubleTapResetZoom).
        // Fires only on background (SwiftUI subviews with their own tap
        // gestures take priority via the delegate's shouldReceive logic).
        if let resetZoom = doubleTapResetZoom {
            let recognizer = UITapGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handleDoubleTapReset(_:))
            )
            recognizer.numberOfTapsRequired = 2
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = context.coordinator
            scrollView.addGestureRecognizer(recognizer)
            scrollView.doubleTapResetZoom = resetZoom
            context.coordinator.doubleTapResetRecognizer = recognizer
        }

        return scrollView
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(
            hostingController: UIHostingController(rootView: self.content),
            zoomScale: _zoomScale,
            contentOffset: _contentOffset
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: CenteringScrollView, context: Context) -> CGSize? {
        // Accept the full proposed size so the scroll view expands to fill
        // available space (e.g. remaining VStack height in TimeStudiesTab).
        // Without this, SwiftUI measures the UIScrollView's intrinsic content
        // size and may give it less than the available area.
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }

    func updateUIView(_ uiView: CenteringScrollView, context: Context) {
        context.coordinator.hostingController.rootView = self.content

        // Skip layout updates while the user is actively interacting
        guard !context.coordinator.isInteracting else { return }

        // Re-measure content and only update if SwiftUI's natural size
        // genuinely changed.
        //
        // Compare against `uiView.lastNaturalSize` — NOT `contentSize` and
        // NOT `hostedView.bounds.size`. UIScrollView mutates both of those
        // during/after pinch zoom (it tracks the scaled visible area
        // there). Comparing against either treats UIScrollView's own
        // zoom-driven mutations as "content changed", and the resulting
        // revert fights the pinch gesture and locks pan after zoom-in.
        // `lastNaturalSize` is written by us only when SwiftUI's
        // `sizeThatFits` reports a new value, so it's a clean signal for
        // genuine content changes (initial population, async image loads).
        let hostedView = context.coordinator.hostingController.view!
        let size = context.coordinator.hostingController.sizeThatFits(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        if size != .zero, size != uiView.lastNaturalSize {
            if let tag = debugTag {
                debugLog("[\(tag)] updateUIView: natural \(uiView.lastNaturalSize) → \(size), contentSize=\(uiView.contentSize), zoom=\(uiView.zoomScale), didApplyInitialLayout=\(uiView.didApplyInitialLayout)")
            }
            // Content size changed. Common cases:
            //  - First navigation to a tab: tab-gated state fills in async,
            //    so the very first body() runs with empty data → ~zero
            //    contentSize. Once @Observable updates fire and the real
            //    grid renders, sizeThatFits jumps to the real value here.
            //  - Async image loads in the achievements grid: contentSize
            //    grows after the initial measurement.
            //
            // Detect a "significant" jump (≥40pt either dimension) and treat
            // it the same as a first-time sizing: reset the one-shot
            // initial-layout flag and force a fresh layoutSubviews pass on
            // the next runloop tick. SwiftUI's current update cycle hasn't
            // necessarily propagated contentSize-derived state yet, so the
            // synchronous centerContent below + a deferred layout pass
            // together ensure the inset/offset math sees coherent values.
            let prev = uiView.lastNaturalSize
            let bigJump = abs(size.width - prev.width) > 40 || abs(size.height - prev.height) > 40
            uiView.lastNaturalSize = size
            // Set hostedView.bounds.size to the unscaled natural — UIScrollView
            // treats viewForZooming.bounds.size as the unscaled reference and
            // applies zoomScale to compute the visible frame.
            hostedView.bounds.size = size
            hostedView.frame.origin = .zero
            // Set contentSize to the scaled visible (natural × zoomScale).
            // This is what UIScrollView itself converges to via its own
            // layout pass, so we're just keeping it in sync synchronously
            // for centerContent's inset math. Works at any zoomScale.
            uiView.contentSize = CGSize(
                width: size.width * uiView.zoomScale,
                height: size.height * uiView.zoomScale
            )
            // Do NOT reset `didApplyInitialLayout` here even on a big jump.
            // Resetting it causes the layoutSubviews initial block to re-run
            // and clobber `zoomScale = initialZoom`, undoing any pinch the
            // user has performed since the original initial application.
            // The async layoutIfNeeded + the centerContent call below are
            // sufficient to re-center for the new contentSize while keeping
            // the user's current zoom intact. The initial block remains
            // load-bearing for the very first sizing pass (when content
            // populates async after makeUIView): didApplyInitialLayout is
            // still false at that point, so the next layout pass applies it.
            if bigJump {
                DispatchQueue.main.async { [weak uiView] in
                    guard let uiView = uiView else { return }
                    uiView.setNeedsLayout()
                    uiView.layoutIfNeeded()
                }
            }
            // Content size changed (e.g. async image loads grew the
            // achievement grid). Re-center + clamp the existing offset to
            // the new scrollable range — without this, the user can scroll
            // the grid off-screen until they zoom (which forces a fresh
            // layoutSubviews pass).
            context.coordinator.centerContent(in: uiView)
            let scaledW = size.width * uiView.zoomScale
            let scaledH = size.height * uiView.zoomScale
            let maxX = max(0, scaledW - uiView.bounds.width)
            let maxY = max(0, scaledH - uiView.bounds.height)
            var clamped = uiView.contentOffset
            if clamped.x < -uiView.contentInset.left { clamped.x = -uiView.contentInset.left }
            if clamped.x > maxX { clamped.x = maxX }
            if clamped.y < -uiView.contentInset.top { clamped.y = -uiView.contentInset.top }
            if clamped.y > maxY { clamped.y = maxY }
            if clamped != uiView.contentOffset { uiView.contentOffset = clamped }
        }
    }

    // MARK: - CenteringScrollView

    /// UIScrollView subclass that centers content and applies initial zoom/offset
    /// in layoutSubviews — the first moment we know our own bounds.
    class CenteringScrollView: UIScrollView {
        var initialZoom: CGFloat = 1.0
        var initialOffset: CGPoint = .zero
        var initialFocus: CGPoint?  // content-space point to center on first layout
        var fixedBottomInset: CGFloat = 0
        weak var coordinator: Coordinator?
        var debugTag: String?
        /// Zoom level to animate to on a background double-tap. nil =
        /// gesture not installed.
        var doubleTapResetZoom: CGFloat?
        /// One-shot flag for the initial zoom + centering pass. Reset to
        /// `false` from `updateUIView` when content is sized for the first
        /// time, so the next `layoutSubviews` re-applies the initial state
        /// against real (non-zero) content dimensions.
        var didApplyInitialLayout = false
        /// Last natural (unscaled) size of the SwiftUI content as reported
        /// by `UIHostingController.sizeThatFits`. We track this separately
        /// from `contentSize` because UIScrollView mutates `contentSize`
        /// during/after pinch zoom (it stores the scaled visible area
        /// there, NOT the unscaled natural size). Comparing remeasure
        /// results against `contentSize` would treat UIScrollView's own
        /// zoom-driven mutations as "content changed", and reverting them
        /// fights the pinch gesture and locks pan after high zoom.
        var lastNaturalSize: CGSize = .zero

        override func layoutSubviews() {
            super.layoutSubviews()

            // Re-measure the hosted SwiftUI content every layout pass and
            // push any size change to contentSize. updateUIView does NOT
            // fire when @Observable state inside the wrapped content
            // changes — SwiftUI invalidates the inner View and re-renders
            // it directly into the existing hostingController, but the
            // representable's own properties don't change so SwiftUI
            // sees no reason to call updateUIView. Without this catch,
            // navigating to a tab whose data populates async (e.g.
            // Achievements, where pollAchievements is tab-gated) leaves
            // the scroll view stuck at the initial empty-content size of
            // ~32×32 even after 144 cells render — the visible fragment
            // is just the SwiftUI overflow into a tiny clipped region.
            // Pinching incidentally triggers a SwiftUI update cycle that
            // does refire updateUIView, which is why pinch / background
            // resume "fixed" the symptom.
            if let coord = coordinator,
               // Skip remeasure while the user is actively pinching, panning,
               // or while UIScrollView is decelerating / rubber-banding back
               // from below-minimum zoom. SwiftUI's sizeThatFits can oscillate
               // by a few cell-heights when game-tick state churn flips an
               // .equatable() child during the gesture (observed: 2644 ↔ 2753
               // alternating each layout pass at extreme min zoom). Each
               // remeasure mutates contentSize → triggers another layout →
               // re-measures into the alternate value, locking the scroll
               // view in a layout loop until the gesture is released. The
               // remeasure only exists to catch idle async size changes
               // (initial population, image loads), so skipping during
               // interaction is safe — those happen with isInteracting=false.
               !coord.isInteracting,
               !self.isDragging,
               !self.isDecelerating,
               !self.isZooming,
               !self.isZoomBouncing {
                let measured = coord.hostingController.sizeThatFits(
                    in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
                )
                if measured != .zero, measured != lastNaturalSize {
                    if let tag = debugTag {
                        debugLog("[\(tag)] layoutSubviews REMEASURE: natural \(lastNaturalSize) → \(measured) (contentSize=\(contentSize), zoom=\(zoomScale))")
                    }
                    lastNaturalSize = measured
                    let hostedView = coord.hostingController.view!
                    hostedView.bounds.size = measured
                    hostedView.frame.origin = .zero
                    // Sync contentSize to the scaled visible (natural × zoomScale).
                    // See updateUIView's matching block for the rationale.
                    contentSize = CGSize(
                        width: measured.width * zoomScale,
                        height: measured.height * zoomScale
                    )
                    // Do NOT reset `didApplyInitialLayout` here — see the
                    // matching note in updateUIView's bigJump branch. The
                    // centerContent call at the bottom of layoutSubviews
                    // re-centers against the new contentSize while keeping
                    // the user's pinch zoom intact. Resetting the flag would
                    // cause the initial block below to re-fire on the next
                    // layout pass and clobber zoomScale back to initialZoom.
                    setNeedsLayout()
                }
            }

            // Apply initial zoom + centering on the very first layout where
            // BOTH bounds and contentSize are valid. UIHostingController
            // measures its SwiftUI content asynchronously — the very first
            // layoutSubviews pass typically runs with `contentSize == .zero`,
            // and applying the initial zoom against a zero-sized content
            // leaves the grid pinned tiny in the corner until the next layout
            // pass (triggered by user pinch). Wait for real content size so
            // the centering math has something to chew on.
            if !didApplyInitialLayout && bounds.width > 0 && contentSize.width > 0 {
                didApplyInitialLayout = true
                if let tag = debugTag {
                    debugLog("[\(tag)] layoutSubviews INITIAL: bounds=\(bounds.size), contentSize=\(contentSize), zoom=\(zoomScale), initialZoom=\(initialZoom)")
                }

                zoomScale = initialZoom

                if initialOffset != .zero {
                    contentOffset = initialOffset
                } else if let focus = initialFocus {
                    // Center viewport on the focus point (content-space, at zoom=1).
                    // After zoom is applied the content coords scale, so the scroll
                    // offset = focus * zoom - viewport/2, clamped to scrollable range.
                    let scaled = CGPoint(x: focus.x * initialZoom,
                                         y: focus.y * initialZoom)
                    let target = CGPoint(
                        x: scaled.x - bounds.width / 2,
                        y: scaled.y - bounds.height / 2
                    )
                    let scaledW = contentSize.width * initialZoom
                    let scaledH = contentSize.height * initialZoom
                    contentOffset = CGPoint(
                        x: max(0, min(target.x, max(0, scaledW - bounds.width))),
                        y: max(0, min(target.y, max(0, scaledH - bounds.height)))
                    )
                } else {
                    // Center horizontally
                    let scaledWidth = contentSize.width * initialZoom
                    let viewWidth = bounds.width
                    if scaledWidth > viewWidth {
                        contentOffset = CGPoint(
                            x: (scaledWidth - viewWidth) / 2,
                            y: 0
                        )
                    }
                }
                coordinator?.centerContent(in: self)
            }

            // Always keep content centered when smaller than viewport
            coordinator?.centerContent(in: self)
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var hostingController: UIHostingController<Content>
        var isInteracting = false
        weak var doubleTapResetRecognizer: UITapGestureRecognizer?
        @Binding var zoomScale: CGFloat
        @Binding var contentOffset: CGPoint

        init(
            hostingController: UIHostingController<Content>,
            zoomScale: Binding<CGFloat>,
            contentOffset: Binding<CGPoint>
        ) {
            self.hostingController = hostingController
            self._zoomScale = zoomScale
            self._contentOffset = contentOffset
            self.hostingController.view.backgroundColor = .clear
        }

        // MARK: Double-tap reset

        @objc func handleDoubleTapReset(_ gr: UITapGestureRecognizer) {
            guard let scrollView = gr.view as? CenteringScrollView,
                  let targetZoom = scrollView.doubleTapResetZoom else { return }

            // Animate zoom only — leave contentOffset where it is so the
            // user keeps their scroll position. UIScrollView clamps offset
            // into the new (smaller) scrollable range automatically.
            UIView.animate(
                withDuration: 0.3,
                delay: 0,
                options: [.curveEaseInOut, .beginFromCurrentState]
            ) {
                scrollView.zoomScale = targetZoom
            } completion: { _ in
                self.centerContent(in: scrollView)
                self.persistState(from: scrollView)
            }
        }

        // MARK: UIGestureRecognizerDelegate

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            // Only intercept the double-tap-reset recognizer; let
            // everything else (UIScrollView's own pan/pinch/etc) through.
            guard gestureRecognizer === doubleTapResetRecognizer else { return true }

            // Walk up from the touched view toward the scroll view, looking
            // for any other UITapGestureRecognizer along the way. If we
            // find one, the touch is on a card or other tappable subview —
            // defer to it. If the chain has no tap recognizers, the touch
            // is on the SwiftUI background and we can fire the reset.
            var view = touch.view
            while view != nil, view !== gestureRecognizer.view {
                if let recognizers = view?.gestureRecognizers {
                    for r in recognizers
                    where r is UITapGestureRecognizer && r !== gestureRecognizer {
                        return false
                    }
                }
                view = view?.superview
            }
            return true
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return hostingController.view
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContent(in: scrollView)
        }

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            isInteracting = true
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            centerContent(in: scrollView)
            isInteracting = false
            persistState(from: scrollView)
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            isInteracting = true
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                isInteracting = false
                persistState(from: scrollView)
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            isInteracting = false
            persistState(from: scrollView)
        }

        fileprivate func centerContent(in scrollView: UIScrollView) {
            let boundsSize = scrollView.bounds.size
            // Compute scaled visible size as `lastNaturalSize × zoomScale`.
            //
            // Why not `scrollView.contentSize × zoomScale`: UIScrollView
            // mutates `contentSize` during/after pinch zoom — at any non-1
            // zoom it stores the already-scaled visible size there, NOT
            // the unscaled natural. Multiplying by zoomScale again
            // double-scales, producing wildly wrong insets at min/max zoom
            // (e.g. inset=174pt with content 210pt wide instead of inset=96pt).
            //
            // Why not `hostingController.view.frame.size`: that frame is
            // only updated by UIScrollView during its layoutSubviews pass,
            // so calling centerContent synchronously from updateUIView
            // reads a stale frame (often .zero on first measurement).
            //
            // `lastNaturalSize` is the SwiftUI natural size we recorded
            // when sizeThatFits last reported a new value — it's invariant
            // under zoom and always reflects what the unscaled content
            // wants to be. Multiplying by current zoomScale gives the
            // visible scaled size that's coherent at any moment in any
            // gesture state.
            let natural = (scrollView as? CenteringScrollView)?.lastNaturalSize ?? scrollView.contentSize
            let scaledContentSize = CGSize(
                width: natural.width * scrollView.zoomScale,
                height: natural.height * scrollView.zoomScale
            )
            let fixedBottom = (scrollView as? CenteringScrollView)?.fixedBottomInset ?? 0

            let xOffset = max((boundsSize.width - scaledContentSize.width) / 2, 0)
            let yOffset = max((boundsSize.height - scaledContentSize.height) / 2, 0)
            scrollView.contentInset = UIEdgeInsets(top: yOffset, left: xOffset, bottom: max(yOffset, fixedBottom), right: xOffset)
            if let tag = (scrollView as? CenteringScrollView)?.debugTag {
                debugLog("[\(tag)] centerContent: bounds=\(boundsSize), scaledContent=\(scaledContentSize), zoom=\(scrollView.zoomScale), contentSize=\(scrollView.contentSize), inset=(t:\(yOffset) l:\(xOffset))")
            }

            // When the content is smaller than the viewport along either
            // axis, snap the contentOffset to the centered rest position
            // (i.e. -contentInset). UIScrollView does NOT do this on its
            // own when contentInset changes — the user is free to drag the
            // content around in the empty space. After our snap, dragging
            // rubber-bands back to centered as expected.
            guard !isInteracting else { return }
            var rest = scrollView.contentOffset
            if scaledContentSize.width <= boundsSize.width {
                rest.x = -xOffset
            }
            if scaledContentSize.height <= boundsSize.height {
                rest.y = -yOffset
            }
            if rest != scrollView.contentOffset {
                scrollView.contentOffset = rest
            }
        }

        private func persistState(from scrollView: UIScrollView) {
            zoomScale = scrollView.zoomScale
            contentOffset = scrollView.contentOffset
        }
    }
}
