//
//  PhoneTabBar.swift
//  AntiMatter
//
//  Custom paging tab bar for iPhone. Floating rounded glass style for iOS 26.
//  Uses ScrollView with paging behavior for reactive finger-tracking swipes.
//  Wraps by repeating pages (e.g. [0,1,0,1,0,1]) and recentering silently.
//  Page indicator dots centered below tabs. Content stays on active tab.
//

import SwiftUI

struct PhoneTabBar: View {
    let allTabs: [SidebarTab]
    let activeTab: SidebarTab
    let tabsPerPage: Int
    @Binding var tabPage: Int
    let activeSubtabs: [SidebarTab: Subtab]
    let notifiedSubtabs: Set<Subtab>
    let onSelectTab: (SidebarTab) -> Void
    let availableSubtabsFor: (SidebarTab) -> [Subtab]
    let onSelectSubtab: (SidebarTab, Subtab) -> Void
    /// Engine reference — only read at 30Hz inside isolated leaf subviews
    /// (`TabBarFillLayer`, `TabBarPercentageOverlay`) so the rest of the
    /// tab bar root doesn't re-evaluate on `progressFill` ticks.
    let engine: GameEngine
    /// Gate for the integrated infinity progress fill + percentage. Today
    /// this is `sidebar.activeSubtab == .antimatterDimensions` — same gate
    /// the standalone `PhoneProgressBar` used to use.
    let isOnADSubtab: Bool

    private var pages: [[SidebarTab]] {
        guard allTabs.count > tabsPerPage + 1 else {
            return [allTabs]
        }
        return stride(from: 0, to: allTabs.count, by: tabsPerPage).map { start in
            Array(allTabs[start..<min(start + tabsPerPage, allTabs.count)])
        }
    }

    private var needsPaging: Bool { pages.count > 1 }

    /// How many times we repeat the page set for the illusion of infinite scroll.
    private let repeatCount = 100

    /// The scroll ID of the "home" copy of page 0 (middle of the repeated range).
    private var homeBase: Int { (repeatCount / 2) * pages.count }

    @State private var scrollID: Int?
    @State private var didAppear = false

    var body: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    if needsPaging {
                        // Repeat pages many times: id 0..<(pages.count * repeatCount)
                        ForEach(0..<pages.count * repeatCount, id: \.self) { flatIndex in
                            let pageIndex = flatIndex % pages.count
                            pageView(pages[pageIndex])
                                .containerRelativeFrame(.horizontal)
                                .id(flatIndex)
                        }
                    } else {
                        // Single page, no paging needed
                        ForEach(Array(pages.enumerated()), id: \.offset) { pageIndex, pageTabs in
                            pageView(pageTabs)
                                .containerRelativeFrame(.horizontal)
                                .id(pageIndex)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrollID)
            .scrollClipDisabled()
            .frame(height: 44)
            // When the tab list shrinks/grows enough to flip the paging
            // mode (late-game multi-page → early-game single-page after a
            // slot switch / hard reset / import), SwiftUI keeps the prior
            // LazyHStack's page views in the hierarchy — scrollPosition
            // anchors to a stale flatIndex from the old 200-id range
            // while the new branch has only id=0, and the user keeps
            // seeing the old page contents (Infinity / Reality buttons
            // rendered in slots that should now be empty). Forcing
            // ScrollView teardown via `.id(allTabs)` cleanly rebuilds
            // against the new tab list. Rare event — only fires on tab
            // unlock or explicit reset paths.
            .id(allTabs)

            // Page indicator dots — strip is ALWAYS reserved (fixed
            // height) so the percentage overlay below has consistent
            // vertical room regardless of `needsPaging`. Dots themselves
            // only render when there's more than one page.
            ZStack {
                if needsPaging {
                    HStack(spacing: 5) {
                        ForEach(0..<pages.count, id: \.self) { i in
                            Circle()
                                .fill(i == tabPage ? GameColor.antimatter : Color.secondary.opacity(0.4))
                                .frame(width: 6, height: 6)
                        }
                    }
                }
            }
            .frame(height: 6)
        }
        .padding(.top, 10)
        .padding(.bottom, 5)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        // Infinity progress fill — tinted region of the glass capsule.
        // Layered as `.background` ABOVE the glass material (closer to
        // content), with `.blendMode(.plusLighter)` so the green reads as
        // a tint of the glass underneath rather than a flat overlay.
        .background {
            TabBarFillLayer(engine: engine, isOnADSubtab: isOnADSubtab)
        }
        // Percentage label — sits in the dot-row strip, z-stacked above
        // the dots (no conditional removal). Tracks fill horizontally and
        // is clipped to the bar's capsule shape so the text never spills
        // beyond the rounded ends at very low / very high fill.
        .overlay {
            if isOnADSubtab {
                TabBarPercentageOverlay(engine: engine)
                    .allowsHitTesting(false)
            }
        }
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .onAppear {
            guard !didAppear else { return }
            didAppear = true
            // Start at the middle copy so there's room to scroll in both directions
            scrollID = needsPaging ? homeBase + tabPage : tabPage
        }
        .onChange(of: scrollID) { _, newID in
            guard let newID else { return }
            if needsPaging {
                tabPage = newID % pages.count
            } else {
                tabPage = newID
            }
        }
        .onChange(of: allTabs) { _, _ in
            // Tab list changed (e.g. save import unlocked new tabs) — reset scroll
            // to the correct position for the new page structure.
            let targetPage = tabPage < pages.count ? tabPage : 0
            if needsPaging {
                scrollID = homeBase + targetPage
            } else {
                scrollID = targetPage
            }
        }
        .onChange(of: tabPage) { _, newPage in
            guard needsPaging else {
                if scrollID != newPage {
                    withAnimation(.easeInOut(duration: 0.25)) { scrollID = newPage }
                }
                return
            }
            // External page change (e.g. tab unlock) — scroll to nearest copy of that page
            if let current = scrollID {
                let currentPageIndex = current % pages.count
                if currentPageIndex != newPage {
                    let delta = newPage - currentPageIndex
                    withAnimation(.easeInOut(duration: 0.25)) { scrollID = current + delta }
                }
            }
        }
    }

    // MARK: - Page view

    private func pageView(_ tabs: [SidebarTab]) -> some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                tabItem(
                    tab: tab,
                    isActive: tab == activeTab
                )
                .onTapGesture {
                    Haptics.tap()
                    onSelectTab(tab)
                }
                .contextMenu { subtabMenu(for: tab) }
            }

            if needsPaging {
                let emptySlots = tabsPerPage - tabs.count
                ForEach(0..<emptySlots, id: \.self) { _ in
                    Color.clear
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Subtab context menu

    @ViewBuilder
    private func subtabMenu(for tab: SidebarTab) -> some View {
        let subtabs = availableSubtabsFor(tab)
        let current = activeSubtabs[tab] ?? tab.defaultSubtab
        if subtabs.count > 1 {
            ForEach(subtabs, id: \.self) { subtab in
                Button {
                    Haptics.tap()
                    onSelectSubtab(tab, subtab)
                } label: {
                    subtabMenuLabel(
                        subtab: subtab,
                        isCurrent: subtab == current && tab == activeTab
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func subtabMenuLabel(subtab: Subtab, isCurrent: Bool) -> some View {
        let title = isCurrent ? "\(subtab.displayName) ✓" : subtab.displayName
        // UIMenu reserves an icon column for `Label`-shaped rows so they
        // line up vertically. SF Symbol icons go via `Label(_, systemImage:)`
        // and render in the column as expected. Bare `Text` placed in
        // `Label`'s icon slot does not get rasterized by UIMenu's
        // SwiftUI→UIKit bridge — the column reserves space but no glyph
        // draws. For the Unicode glyph subtabs (Ω/∞/Δ for Dimensions and
        // Challenges, Ϟ/Ϙ/⌬/ᛝ/♅ for Celestials, plus Ψ/Ξ/∝) we render
        // the glyph to a UIImage via `ImageRenderer` and feed it through
        // `Label(_, image:)` so the icon slot draws the glyph.
        switch subtab.symbolType {
        case .sfSymbol(let name):
            Label(title, systemImage: name)
        case .text(let glyph):
            if let img = Self.glyphMenuIcon(for: glyph) {
                Label {
                    Text(title)
                } icon: {
                    Image(uiImage: img)
                }
            } else {
                // Fallback if rendering fails — bare Text loses the icon
                // column slot but at least surfaces the glyph in-line.
                Text("\(glyph)  \(title)")
            }
        }
    }

    /// Rasterize a single Unicode glyph to a UIMenu-sized icon. Result is
    /// cached so the renderer doesn't re-run on every menu open.
    private static let glyphIconCache = NSCache<NSString, UIImage>()

    @MainActor
    private static func glyphMenuIcon(for glyph: String) -> UIImage? {
        if let cached = glyphIconCache.object(forKey: glyph as NSString) {
            return cached
        }
        let renderer = ImageRenderer(
            content: Text(glyph)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
        )
        renderer.scale = UITraitCollection.current.displayScale
        // `template`-mode UIImage tints with the menu's foreground color so
        // the glyph picks up system Dark/Light Mode like an SF Symbol does.
        guard let raw = renderer.uiImage else { return nil }
        let templated = raw.withRenderingMode(.alwaysTemplate)
        glyphIconCache.setObject(templated, forKey: glyph as NSString)
        return templated
    }

    // MARK: - Tab item

    @ViewBuilder
    private func tabItem(tab: SidebarTab, isActive: Bool) -> some View {
        let subtab = activeSubtabs[tab] ?? tab.defaultSubtab
        let color: Color = tabContentColor(tab: tab, isActive: isActive)
        // Badge gated by the visible subtab list: a notification on a
        // user-hidden subtab would otherwise produce an un-clearable
        // dot (the user can't navigate there to clear it). The JS-side
        // Set stays intact so the prefs round-trip with web saves.
        let hasNotification = availableSubtabsFor(tab).contains(where: { notifiedSubtabs.contains($0) })
        VStack(spacing: 2) {
            ZStack(alignment: .topTrailing) {
                Group {
                    switch subtab.symbolType {
                    case .sfSymbol(let name):
                        Image(systemName: name)
                            .font(.system(size: 20))
                            .frame(height: 24)
                    case .text(let glyph):
                        Text(glyph)
                            .font(.system(size: 22, weight: .bold, design: .serif))
                            .frame(height: 24)
                    }
                }
                .frame(width: 28, height: 24)

                if hasNotification {
                    NotificationBadge()
                        .font(.system(size: 10))
                        .offset(x: 4, y: -4)
                }
            }
            Text(tab.shortName)
                .font(.caption2)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        // Selection indicator independent of color. Themed tabs (Infinity,
        // Eternity, Reality, Celestials) now keep their accent color in
        // both states — without a separate marker, both states would read
        // as "the same color, just slightly dimmer" which doesn't read as
        // "selected". A small filled pill behind the icon gives a clear
        // selected/unselected distinction at any color.
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 10)
                    .fill(tab.accentColor.opacity(0.18))
                    // Negative top padding extends the pill 5pt above the
                    // tab item's frame so it overlaps the top edge of the
                    // glass capsule. Bottom stays inset so the pill doesn't
                    // bleed into the page-dots strip below.
                    .padding(.top, -5)
                    .padding(.bottom, 0)
                    .padding(.horizontal, 4)
            }
        }
        .contentShape(Rectangle())
    }

    /// Per-tab foreground color, decoupled from the accent-vs-secondary
    /// flip. Themed tabs (Infinity / Eternity / Reality / Celestials)
    /// always render in their accent color so the player can see at a
    /// glance which tab is which without having to select it; non-themed
    /// tabs keep the original secondary-grey default and pop to accent
    /// only when active.
    private func tabContentColor(tab: SidebarTab, isActive: Bool) -> Color {
        // Themed tabs read at full strength when active. Inactive at 0.75
        // (was 0.55) — through the glass capsule, 0.55 was reading as
        // "greyed out" rather than "themed but not selected".
        switch tab {
        case .infinity, .eternity, .reality, .celestials:
            return isActive ? tab.accentColor : tab.accentColor.opacity(0.75)
        default:
            return isActive ? tab.accentColor : .secondary
        }
    }
}

// MARK: - Integrated infinity progress fill (AD subtab only)

/// Tinted-glass fill region for the tab bar capsule. Renders only when the
/// AD subtab is active; otherwise the `.background` is empty and the glass
/// capsule looks identical to non-AD tabs.
///
/// Reads `engine.progressFill` directly so the SwiftUI dependency graph
/// scopes 30Hz invalidation to this leaf, not the parent `PhoneTabBar`.
private struct TabBarFillLayer: View {
    let engine: GameEngine
    let isOnADSubtab: Bool

    /// Fraction of the capsule's height the fill rectangle occupies. The
    /// gradient renders within this band, bottom-anchored — clipping to
    /// the outer capsule shape gives a "swelling rises from the bottom"
    /// look. 1.0 = full capsule height; 0.5 = bottom half only.
    private static let fillHeightFraction: CGFloat = 0.27

    var body: some View {
        if isOnADSubtab {
            let fill = min(max(engine.progressFill, 0), 1)
            GeometryReader { geo in
                let fillHeight = geo.size.height * Self.fillHeightFraction
                // Capsule fill instead of Rectangle — gives the leading
                // (right) edge a rounded cap of radius `fillHeight / 2`,
                // matching the capsule silhouette of the tab bar instead
                // of a hard vertical line. The trailing (left) edge cap
                // gets trimmed by the outer `.clipShape(Capsule())`.
                HStack(spacing: 0) {
                    Capsule()
                        .fill(
                            // Vertical gradient — green strongest at the
                            // bottom edge, fading to transparent toward
                            // the top. Reads as light "rising into" the
                            // glass from below.
                            LinearGradient(
                                colors: [GameColor.good, GameColor.good.opacity(1)],
                                startPoint: .center,
                                endPoint: .top
                            )
                        )
                        .frame(width: geo.size.width * fill, height: fillHeight)
                    Color.clear
                        .frame(height: fillHeight)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
            }
            .clipShape(Capsule())
            // `.plusLighter` brightens against dark backgrounds but desaturates
            // the green when stacked under the .glassEffect material. Drop the
            // blend mode and run the gradient at higher alpha so the fill
            // reads vividly through the glass capsule instead of washing out.
            .opacity(0.75)
            .animation(.linear(duration: 0.1), value: engine.progressFill)
            .allowsHitTesting(false)
        }
    }
}

/// Percentage label for the integrated fill. Isolated leaf so the 30Hz
/// `progressFill` read doesn't pull `PhoneTabBar` into its dependency set.
///
/// Tracks horizontally with the fill, matching the original
/// `ProgressBarView` math: text x = max(fillW / 2, textHalfWidth + pad)
/// — slides toward center as fill grows, but never clips the left edge
/// at low fill. Uses `.animatableData` on a `Modifier` shape via
/// SwiftUI's `Animatable` View conformance so the slide interpolates
/// at display refresh between throttled JS-side `progressFill` updates.
private struct TabBarPercentageOverlay: View {
    let engine: GameEngine
    private static let estimatedTextHalfWidth: CGFloat = 22 // "100.00%" caption2 monospaced
    /// Distance from the bottom of the capsule to the vertical CENTER of
    /// the percentage text. Tuned to land the text inside the dot-row
    /// strip: `5pt` bottom padding + `6pt` strip height ÷ 2 = `8pt`.
    private static let bottomOffsetFromBaseline: CGFloat = 8

    var body: some View {
        let fill = min(max(engine.progressFill, 0), 1)
        let pct = fill * 100
        GeometryReader { geo in
            let fillW = geo.size.width * fill
            let x = max(fillW / 2, Self.estimatedTextHalfWidth + 4)
            Text(String(format: "%.2f%%", pct))
                .font(.system(.caption2, design: .monospaced).weight(.medium))
                // Match the inactive tab-icon tint (`.secondary`) so the
                // percentage reads as part of the bar's chrome, not as a
                // standalone HUD label.
                .foregroundStyle(.secondary)
                .position(x: x, y: geo.size.height - Self.bottomOffsetFromBaseline)
        }
        // Clip to the bar's capsule shape — at low fill the text would
        // otherwise spill past the rounded left cap; near 100% it would
        // spill past the rounded right cap. Capsule clip masks both.
        .clipShape(Capsule())
        .animation(.linear(duration: 0.1), value: engine.progressFill)
    }
}

// MARK: - Short tab names for compact tab bar

extension SidebarTab {
    /// Abbreviated name for the phone tab bar (saves horizontal space).
    var shortName: String {
        switch self {
        case .dimensions:   "Dims"
        case .automation:   "Auto"
        case .challenges:   "Challenge"
        case .infinity:     "Infinity"
        case .eternity:     "Eternity"
        case .reality:      "Reality"
        case .celestials:   "Celestial"
        case .achievements: "Achieve"
        case .statistics:   "Stats"
        case .options:      "Options"
        case .debug:        "Debug"
        }
    }
}
