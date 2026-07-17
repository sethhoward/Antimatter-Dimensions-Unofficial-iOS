//
//  MultiplierBreakdownTab.swift
//  AntiMatter
//
//  Multiplier Breakdown subtab under Statistics. Mirrors
//  `MultiplierBreakdownTab.vue` + `MultiplierBreakdownEntry.vue`.
//
//  Architecture:
//   - Thin Swift; the heavy lifting (entry-tree walk, percent math, icon
//     resolution, persisted prefs) lives in `multiplier-breakdown-helper.js`.
//   - Per-tick refresh (500ms) of the current resource while the subtab is
//     active.
//   - Static stacked bars (no rolling average, no animated transitions).
//   - Tap a bar segment OR tap a text row → toggles selection + expand/collapse
//     of that entry's drill-down. Same affordance as web's `@click` on the bar
//     div + the +/- icon on the text row. Selected entry's bar segment gets a
//     highlight; matching row gets a colored border. Tapping a bar scrolls the
//     matching row into view via `ScrollViewReader`.
//   - Inline DisclosureGroup-style drill-down. Each expanded child renders its
//     OWN mini stacked-bars column beside its own entries list (recursive).
//   - Adaptive layout: iPad HStack (bars left, entries right); iPhone VStack.
//   - Entries list is wrapped in a horizontal `ScrollView` so long monospaced
//     entry lines ("  10.0%: Achievement 75 (×2.34, ^1.05)") extend rightward
//     instead of wrapping.
//
//  Selection lifecycle:
//   - Persists across the 500ms refresh (entries keyed by stable `key`).
//   - Cleared when the user picks a different resource.
//   - Cleared when the selected entry disappears from the list (rare).
//   - Tap-twice toggles (collapse + deselect).
//

import SwiftUI

// MARK: - Shared selection/expansion store

/// Shared state for the breakdown view at all depths. Bars + rows read from
/// the same store so tapping either affordance updates the same selection +
/// expansion set. Child-cache also lives here so the breakdown survives the
/// 500ms refresh without re-fetching every expansion.
@Observable
final class MultiplierBreakdownStore {
    /// Currently-selected entry key (e.g. `"AD_achievement"`). nil = nothing
    /// selected.
    var selectedKey: String? = nil
    /// Keys of currently-expanded entries (any depth). Selection toggles
    /// expansion: selecting a hasChildren entry adds it; deselecting removes.
    var expandedKeys: Set<String> = []
    /// Lazily-fetched child resources, keyed by parent entry key.
    var childResources: [String: MultiplierBreakdownResource] = [:]
    /// Keys currently being fetched (so we can show a "Loading…" line).
    var loadingKeys: Set<String> = []

    /// Tap on a bar or a row: select the entry, expand if it has children.
    /// Tapping the same entry again deselects + collapses.
    func tap(entry: MultiplierBreakdownEntryNode, engine: GameEngine) {
        if selectedKey == entry.key {
            selectedKey = nil
            expandedKeys.remove(entry.key)
            return
        }
        selectedKey = entry.key
        guard entry.hasChildren else { return }
        if expandedKeys.contains(entry.key) { return }   // already expanded
        expandedKeys.insert(entry.key)
        ensureChildLoaded(key: entry.key, engine: engine)
    }

    /// Slide-scrub enter: fired as the finger crosses INTO a segment during
    /// a hold-and-drag scrub. Sets selectedKey (so the row highlight + auto-
    /// scroll follow the finger) and expands the entry if not already open.
    /// Never closes an already-expanded segment — reverse slides don't undo
    /// work.
    func scrubEnter(entry: MultiplierBreakdownEntryNode, engine: GameEngine) {
        selectedKey = entry.key
        guard entry.hasChildren else { return }
        if expandedKeys.contains(entry.key) { return }
        expandedKeys.insert(entry.key)
        ensureChildLoaded(key: entry.key, engine: engine)
    }

    private func ensureChildLoaded(key: String, engine: GameEngine) {
        if childResources[key] != nil { return }
        if loadingKeys.contains(key) { return }
        loadingKeys.insert(key)
        engine.loadMultiplierBreakdownResource(key: key) { [weak self] res in
            guard let self else { return }
            self.loadingKeys.remove(key)
            if let res { self.childResources[key] = res }
        }
    }

    /// Called when the resource picker changes. Wipes all selection + caches
    /// so we don't carry stale state into a different resource's tree.
    func resetForResourceChange() {
        selectedKey = nil
        expandedKeys.removeAll()
        childResources.removeAll()
        loadingKeys.removeAll()
    }
}

// MARK: - Tab root

struct MultiplierBreakdownTab: View {
    let engine: GameEngine

    @State private var state: MultiplierBreakdownState = .empty
    @State private var refreshTrigger: Int = 0
    @State private var store = MultiplierBreakdownStore()
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    resourcePicker
                    if let res = state.resource {
                        breakdownBody(for: res)
                    } else {
                        Text(verbatim: "Loading multiplier breakdown…")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    }
                    PhoneTabBarSpacer()
                }
                .padding()
            }
            // Bar taps trigger a programmatic scroll to keep the matching
            // row visible. We observe `selectedKey` for changes and dispatch
            // a scroll-to. Anchor `.center` keeps the row mid-screen so its
            // children (if expanded) are also visible.
            .onChange(of: store.selectedKey) { _, newKey in
                guard let newKey else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newKey, anchor: .center)
                }
            }
        }
        .task(id: refreshTrigger) {
            await fetchOnce()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Task.isCancelled { break }
                await fetchOnce()
                pruneSelectionIfMissing()
            }
        }
    }

    // MARK: - Resource picker

    @ViewBuilder
    private var resourcePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(state.availableResources) { opt in
                    let isActive = opt.id == state.currentResourceId
                    Button {
                        selectResource(opt)
                    } label: {
                        Text(verbatim: opt.label)
                            .font(.subheadline.weight(isActive ? .semibold : .regular))
                            .foregroundStyle(isActive ? .black : .white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isActive ? Color.white : Color.black.opacity(0.5))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(.white.opacity(0.6), lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
    }

    private func selectResource(_ opt: MultiplierBreakdownResourceOption) {
        engine.setMultiplierBreakdownPref(field: "currTab", value: opt.id)
        store.resetForResourceChange()
        state = MultiplierBreakdownState(
            availableResources: state.availableResources,
            currentResourceId: opt.id,
            replacePowers: state.replacePowers,
            showAltGroup: state.showAltGroup,
            resource: state.resource
        )
        refreshTrigger &+= 1
    }

    // MARK: - Breakdown body

    @ViewBuilder
    private func breakdownBody(for res: MultiplierBreakdownResource) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(verbatim: res.totalString)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if res.hasSeenPowers && res.allowPowerToggle {
                    Button {
                        engine.setMultiplierBreakdownPref(field: "replacePowers", value: !state.replacePowers)
                        refreshTrigger &+= 1
                    } label: {
                        Text(verbatim: state.replacePowers ? "×N" : "^N")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(.white.opacity(0.5)))
                    }
                    .buttonStyle(.plain)
                }
                if res.hasAltGroup {
                    Button {
                        engine.setMultiplierBreakdownPref(field: "showAltGroup", value: !state.showAltGroup)
                        refreshTrigger &+= 1
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(.white.opacity(0.5)))
                    }
                    .buttonStyle(.plain)
                }
            }

            if res.isEmpty {
                Text(verbatim: "No Active Effects")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(verbatim: res.disabledText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                BarsAndEntriesPair(
                    entries: res.entries,
                    barsHeight: metrics.isCompact ? 200 : 320,
                    barsWidth: metrics.isCompact ? nil : 70,
                    isWide: !metrics.isCompact,
                    depth: 0,
                    engine: engine,
                    store: store
                )
            }

            if res.isDilated, let dilation = res.dilationString {
                Text(verbatim: dilation)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GameColor.dilationGreen)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(GameColor.dilationBorder)
                    )
            }

            if res.isADTotal {
                Text(verbatim: """
                "Base AD Production" is the amount of Antimatter that you would be producing with your current AD upgrades \
                as if you had waited 10-40 seconds (depending on your AD count) after a Sacrifice. This may misrepresent \
                your actual production if your ADs have been producing for a while.
                """)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if res.inNC12Notice {
                    Text(verbatim: "The breakdown in Normal Challenge 12 may be inaccurate for some entries.")
                        .font(.caption2)
                        .foregroundStyle(GameColor.badPink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Refresh helpers

    private func fetchOnce() async {
        await withCheckedContinuation { cont in
            engine.loadMultiplierBreakdownTopOptions { newState in
                self.state = newState
                cont.resume()
            }
        }
    }

    /// Drop selection for keys that have disappeared from the current
    /// resource's entire visible tree (rare; happens when an effect becomes
    /// inactive between refreshes). Expansion state is preserved — the user
    /// explicitly tapped to drill down, and tearing it out from under them
    /// on the next 500ms refresh feels like the view closing itself.
    /// Resource picker change wipes everything via `resetForResourceChange`.
    private func pruneSelectionIfMissing() {
        guard let topEntries = state.resource?.entries else { return }
        // Universe of currently-visible keys: top-level + every cached
        // child resource's entries (recursively walked by drilling into
        // store.childResources, which holds every depth we've fetched).
        var visible = Set(topEntries.map(\.key))
        for (_, child) in store.childResources {
            for e in child.entries { visible.insert(e.key) }
        }
        if let sel = store.selectedKey, !visible.contains(sel) {
            store.selectedKey = nil
        }
        // Deliberately do NOT prune expandedKeys — see comment above.
    }
}

// MARK: - Bars + entries pair (used at every depth)

/// One bar column + its matching entry list. Recursive — each expanded child
/// renders another `BarsAndEntriesPair` for its own children. Wide variant
/// (iPad) renders bars + entries side-by-side; compact (iPhone, or deep
/// children) renders them stacked.
struct BarsAndEntriesPair: View {
    let entries: [MultiplierBreakdownEntryNode]
    let barsHeight: CGFloat
    /// Fixed width for the bars column in HStack layout. nil = bars span
    /// full width (VStack layout).
    let barsWidth: CGFloat?
    let isWide: Bool
    let depth: Int
    let engine: GameEngine
    @Bindable var store: MultiplierBreakdownStore

    var body: some View {
        if isWide {
            HStack(alignment: .top, spacing: 12) {
                bars
                    .frame(width: barsWidth)
                entriesScroll
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                bars
                entriesScroll
            }
        }
    }

    @ViewBuilder
    private var bars: some View {
        MultiplierStackedBars(
            entries: entries,
            height: barsHeight,
            selectedKey: store.selectedKey,
            onTap: { entry in store.tap(entry: entry, engine: engine) },
            onScrubEnter: { entry in store.scrubEnter(entry: entry, engine: engine) }
        )
    }

    @ViewBuilder
    private var entriesScroll: some View {
        // Entries extend rightward into a horizontal scroll so long
        // monospaced rows don't wrap. The bars stay pinned (they're a
        // sibling in the surrounding HStack/VStack, not inside this
        // ScrollView), preserving the bar↔row visual link.
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(entries) { entry in
                    MultiplierEntryRow(
                        entry: entry,
                        depth: depth,
                        engine: engine,
                        store: store
                    )
                }
            }
        }
    }
}

// MARK: - Stacked bars

/// Right-side stacked-bar column. Each entry gets a segment proportional to
/// its positive `percent` (relative to the sum of positive percents);
/// negative-percent entries (nerfs) draw below at the bottom of the column.
///
/// **Minimum segment size**: any visible entry's segment is clamped to a 12pt
/// floor so tiny percentages stay legible + tappable. The deficit is funded
/// by shrinking above-floor segments proportionally; if the floor times count
/// exceeds the column height, layout falls back to equal distribution.
///
/// **Tap + hold-and-scrub interaction model**:
/// - Quick tap on a segment → `onTap(entry)` (toggles selection/expansion).
/// - Hold for 300ms, then drag → "scrub mode": each NEW segment crossed fires
///   `onScrubEnter(entry)`. A light haptic fires when scrub activates. Scrub
///   is non-toggling — already-expanded segments are no-ops, so reverse
///   slides don't undo work.
/// - Quick swipe (any direction) → falls through to the outer vertical
///   ScrollView / SubtabPager for normal scrolling.
///
/// **Why UIKit-bridged**: SwiftUI's `LongPressGesture.sequenced(before: DragGesture)`
/// claims the touch from touch-down for the entire hold duration, blocking
/// the outer scroll views from receiving movement events. UIKit's
/// `UILongPressGestureRecognizer` cooperates natively with `UIScrollView`'s
/// pan gesture via iOS's standard touch-delay system + `allowableMovement` —
/// movement before the duration elapses lets the scroll take over, and
/// stillness past the duration activates the hold. No explicit `require(toFail:)`
/// dance needed.
struct MultiplierStackedBars: View {
    let entries: [MultiplierBreakdownEntryNode]
    let height: CGFloat
    let selectedKey: String?
    let onTap: (MultiplierBreakdownEntryNode) -> Void
    let onScrubEnter: (MultiplierBreakdownEntryNode) -> Void

    @State private var scrubLastKey: String? = nil

    var body: some View {
        Canvas { ctx, size in
            let layout = computeLayout(in: size)
            for seg in layout {
                let color = Color(hex: seg.entry.iconColor)
                if seg.entry.isNerf {
                    drawNerfStripe(ctx: ctx, rect: seg.rect, baseColor: color)
                } else {
                    ctx.fill(Path(seg.rect), with: .color(color))
                }
                ctx.stroke(Path(seg.rect), with: .color(.white), lineWidth: 1)
                drawSegmentSymbol(ctx: ctx, rect: seg.rect, entry: seg.entry)
                if seg.entry.key == selectedKey {
                    drawSelectionHighlight(ctx: ctx, rect: seg.rect)
                }
            }
        }
        .frame(height: height)
        .overlay(
            BarsGestureOverlay(
                onTap: { location in
                    if let entry = entryAt(y: location.y) {
                        onTap(entry)
                    }
                },
                onScrubStart: { location in
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if let entry = entryAt(y: location.y) {
                        scrubLastKey = entry.key
                        onScrubEnter(entry)
                    }
                },
                onScrubMove: { location in
                    if let entry = entryAt(y: location.y), entry.key != scrubLastKey {
                        scrubLastKey = entry.key
                        onScrubEnter(entry)
                    }
                },
                onScrubEnd: {
                    scrubLastKey = nil
                }
            )
        )
    }

    // MARK: Geometry

    private struct Segment {
        let entry: MultiplierBreakdownEntryNode
        let rect: CGRect
    }

    /// Computes segment rectangles with a 12pt minimum-height floor. Funds
    /// the deficit by shrinking above-floor segments proportionally so the
    /// total column height is unchanged.
    private func computeLayout(in size: CGSize) -> [Segment] {
        let visible = entries.filter { $0.isVisible }
        let posSum = visible.filter { $0.percent > 0 }.map(\.percent).reduce(0, +)
        let negSum = visible.filter { $0.percent < 0 }.map { abs($0.percent) }.reduce(0, +)
        let total = posSum + negSum
        guard total > 0 else { return [] }

        // Build the visible list in display order (positives top, negatives
        // bottom — mirrors the web flow) plus initial proportional heights.
        var heights: [(entry: MultiplierBreakdownEntryNode, h: CGFloat)] = []
        for entry in visible where entry.percent > 0 {
            heights.append((entry, size.height * (entry.percent / total)))
        }
        for entry in visible where entry.percent < 0 {
            heights.append((entry, size.height * (abs(entry.percent) / total)))
        }

        let minH: CGFloat = 12
        // Pathological case: bar column too short to give everyone the
        // minimum — distribute evenly.
        if minH * CGFloat(heights.count) > size.height {
            let even = size.height / CGFloat(max(heights.count, 1))
            heights = heights.map { ($0.entry, even) }
        } else {
            let belowFloor = heights.filter { $0.h < minH }
            let aboveFloor = heights.filter { $0.h >= minH }
            if !belowFloor.isEmpty && !aboveFloor.isEmpty {
                let deficit = belowFloor.map { minH - $0.h }.reduce(0, +)
                let aboveTotal = aboveFloor.map(\.h).reduce(0, +)
                let scale = max(0, (aboveTotal - deficit) / aboveTotal)
                heights = heights.map { item in
                    item.h < minH ? (item.entry, minH) : (item.entry, item.h * scale)
                }
            }
        }

        var out: [Segment] = []
        var y: CGFloat = 0
        for item in heights {
            out.append(.init(entry: item.entry,
                             rect: CGRect(x: 0, y: y, width: size.width, height: item.h)))
            y += item.h
        }
        return out
    }

    /// Maps a y-coordinate inside the bars column to the entry whose segment
    /// contains it. Strict containment first; nearest-by-midY fallback for
    /// taps slightly outside any segment's bounds (rare, but covers floating-
    /// point edges between the floored segments).
    private func entryAt(y: CGFloat) -> MultiplierBreakdownEntryNode? {
        // Width doesn't matter for vertical hit-testing.
        let layout = computeLayout(in: CGSize(width: 100, height: height))
        guard !layout.isEmpty else { return nil }
        for seg in layout where seg.rect.minY <= y && y < seg.rect.maxY {
            return seg.entry
        }
        return layout.min(by: { abs($0.rect.midY - y) < abs($1.rect.midY - y) })?.entry
    }


    // MARK: Drawing

    private func drawSegmentSymbol(ctx: GraphicsContext, rect: CGRect, entry: MultiplierBreakdownEntryNode) {
        guard rect.height >= 14 else { return }
        let textColor: Color = entry.iconTextColor == "black" ? .black : .white
        var textNode: Text
        if !entry.iconText.isEmpty {
            textNode = Text(verbatim: entry.iconText)
                .font(.system(size: min(rect.height * 0.6, 16), weight: .bold))
        } else if !entry.iconSFSymbol.isEmpty {
            textNode = Text(Image(systemName: entry.iconSFSymbol))
                .font(.system(size: min(rect.height * 0.5, 14), weight: .bold))
        } else {
            return
        }
        let resolved = ctx.resolve(textNode.foregroundStyle(textColor))
        let txtSize = resolved.measure(in: rect.size)
        let origin = CGPoint(x: rect.midX - txtSize.width / 2, y: rect.midY - txtSize.height / 2)
        ctx.draw(resolved, at: origin, anchor: .topLeading)
    }

    private func drawNerfStripe(ctx: GraphicsContext, rect: CGRect, baseColor: Color) {
        ctx.fill(Path(rect), with: .color(baseColor))
        let stripeWidth: CGFloat = 6
        var x: CGFloat = -rect.height
        var stripes = Path()
        while x < rect.width {
            stripes.move(to: CGPoint(x: rect.minX + x, y: rect.maxY))
            stripes.addLine(to: CGPoint(x: rect.minX + x + stripeWidth, y: rect.maxY))
            stripes.addLine(to: CGPoint(x: rect.minX + x + stripeWidth + rect.height, y: rect.minY))
            stripes.addLine(to: CGPoint(x: rect.minX + x + rect.height, y: rect.minY))
            stripes.closeSubpath()
            x += stripeWidth * 2
        }
        var clipCtx = ctx
        clipCtx.clip(to: Path(rect))
        clipCtx.fill(stripes, with: .color(GameColor.badPink.opacity(0.7)))
    }

    /// Selection highlight — a white inner border + brightness lift on the
    /// selected segment. Replicates web's `c-bar-highlight` inset-shadow look.
    private func drawSelectionHighlight(ctx: GraphicsContext, rect: CGRect) {
        // 2pt white inner stroke.
        let inset = rect.insetBy(dx: 1, dy: 1)
        ctx.stroke(Path(inset), with: .color(.white), lineWidth: 2)
        // Subtle white tint overlay (blend with the segment's color).
        ctx.fill(Path(rect), with: .color(.white.opacity(0.18)))
    }
}

// MARK: - Single entry row (with inline child drill-down)

private struct MultiplierEntryRow: View {
    let entry: MultiplierBreakdownEntryNode
    let depth: Int
    let engine: GameEngine
    @Bindable var store: MultiplierBreakdownStore
    @Environment(\.layoutMetrics) private var metrics

    private var isExpanded: Bool { store.expandedKeys.contains(entry.key) }
    private var isSelected: Bool { store.selectedKey == entry.key }
    private var isLoading: Bool { store.loadingKeys.contains(entry.key) }
    private var child: MultiplierBreakdownResource? { store.childResources[entry.key] }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                store.tap(entry: entry, engine: engine)
            } label: {
                HStack(spacing: 6) {
                    if entry.hasChildren {
                        Image(systemName: isExpanded ? "minus.square" : "plus.square")
                            .font(.caption)
                            .foregroundStyle(entry.percent < 0 ? GameColor.badPink : .white)
                    } else {
                        Image(systemName: "square")
                            .font(.caption)
                            .opacity(0)
                    }
                    Text(verbatim: entry.displayString)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(entry.percent < 0 ? GameColor.badPink : .white)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? Color.white.opacity(0.08) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(
                            isSelected ? Color(hex: entry.iconColor) : .white.opacity(0.18),
                            style: isSelected
                                ? StrokeStyle(lineWidth: 1.5)
                                : StrokeStyle(lineWidth: 1, dash: [3, 2])
                        )
                )
            }
            .buttonStyle(.plain)
            .id(entry.key)  // ScrollViewReader target

            if isExpanded {
                Group {
                    if let child, !child.isEmpty {
                        ChildBreakdownView(
                            resource: child,
                            depth: depth + 1,
                            engine: engine,
                            store: store
                        )
                    } else if isLoading {
                        Text(verbatim: "Loading…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 24)
                    }
                }
            }
        }
    }
}

// MARK: - Child drill-down view (recursive)

/// Renders a child resource's total string + its own BarsAndEntriesPair.
/// Bars at child depth are smaller than at top-level. Always uses the
/// horizontal HStack layout (bars next to entries) when there's room;
/// compact mode falls back to stacked.
private struct ChildBreakdownView: View {
    let resource: MultiplierBreakdownResource
    let depth: Int
    let engine: GameEngine
    @Bindable var store: MultiplierBreakdownStore
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: resource.totalString)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
            BarsAndEntriesPair(
                entries: resource.entries,
                barsHeight: barsHeight,
                barsWidth: metrics.isCompact ? nil : 40,
                // iPhone deep-drill: drop to stacked since the row width
                // can otherwise compress the bars to nothing.
                isWide: !metrics.isCompact,
                depth: depth,
                engine: engine,
                store: store
            )
        }
        .padding(.leading, 18)
        .padding(.top, 2)
    }

    /// Bars shrink with depth — at depth 1 they're 120pt tall, depth 2
    /// 90pt, depth 3+ stays at 80pt. Keeps deeply-nested drill-downs from
    /// stretching the parent vertically.
    private var barsHeight: CGFloat {
        switch depth {
        case 0: 200  // (shouldn't happen — top-level uses different path)
        case 1: 120
        case 2: 90
        default: 80
        }
    }
}

// MARK: - UIKit gesture overlay (tap + long-press)

/// Transparent UIView overlay that hosts a `UITapGestureRecognizer` + a
/// `UILongPressGestureRecognizer` for the bars. Lives in UIKit so iOS's
/// standard touch-delay system + `allowableMovement` properly cooperate
/// with outer `UIScrollView` pans — a movement-on-touch lets the scroll
/// take over, while stillness past the hold duration activates scrub.
///
/// SwiftUI-native `LongPressGesture.sequenced(before: DragGesture)` claims
/// the touch from touch-down and never releases it to outer scroll views;
/// the UIKit recognizer cooperates by default. No `require(toFail:)` dance.
private struct BarsGestureOverlay: UIViewRepresentable {
    let onTap: (CGPoint) -> Void
    let onScrubStart: (CGPoint) -> Void
    let onScrubMove: (CGPoint) -> Void
    let onScrubEnd: () -> Void

    func makeUIView(context: Context) -> GestureView {
        let v = GestureView()
        v.callbacks = (onTap, onScrubStart, onScrubMove, onScrubEnd)
        return v
    }

    func updateUIView(_ v: GestureView, context: Context) {
        v.callbacks = (onTap, onScrubStart, onScrubMove, onScrubEnd)
    }

    final class GestureView: UIView {
        typealias Callbacks = (
            tap: (CGPoint) -> Void,
            scrubStart: (CGPoint) -> Void,
            scrubMove: (CGPoint) -> Void,
            scrubEnd: () -> Void
        )
        var callbacks: Callbacks?

        override init(frame: CGRect) {
            super.init(frame: frame)
            // Transparent so the underlying SwiftUI Canvas remains fully
            // visible. The overlay only exists to host recognizers.
            backgroundColor = .clear
            isUserInteractionEnabled = true

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.cancelsTouchesInView = false
            addGestureRecognizer(tap)

            let press = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
            press.minimumPressDuration = 0.3
            // If the finger moves more than 10pt before the hold completes,
            // the long-press fails and the scroll view's pan can take over.
            press.allowableMovement = 10
            press.cancelsTouchesInView = false
            addGestureRecognizer(press)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

        @objc private func handleTap(_ gr: UITapGestureRecognizer) {
            callbacks?.tap(gr.location(in: self))
        }

        @objc private func handlePress(_ gr: UILongPressGestureRecognizer) {
            let loc = gr.location(in: self)
            switch gr.state {
            case .began:   callbacks?.scrubStart(loc)
            case .changed: callbacks?.scrubMove(loc)
            case .ended, .cancelled, .failed:
                           callbacks?.scrubEnd()
            default: break
            }
        }
    }
}
