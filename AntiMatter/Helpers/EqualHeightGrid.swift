//
//  EqualHeightGrid.swift
//  AntiMatter
//
//  Shared "measure the tallest card, apply it to all" height-equalization for
//  grids of cards. Lets card text grow to its full natural height (never
//  truncate / never shrink — localization-safe) while keeping every card in a
//  grid the same height. Extracted from the original EternityMilestonesTab
//  implementation so challenge tabs and any future uniform-card grid share one
//  source of truth.
//
//  Usage (per grid):
//    @State private var cardHeight: CGFloat = <floor>
//    LazyVGrid(...) {
//        ForEach(items) { item in
//            Card(item: item, uniformHeight: cardHeight)   // pass into the card
//        }
//    }
//    .onPreferenceChange(EqualHeightKey.self) { if $0 > cardHeight { cardHeight = $0 } }
//
//  Inside the card body (order matters — frame first, visible bg, then publish):
//    content
//        .padding(...)
//        .equalHeightFrame(uniformHeight, min: <floor>, alignment: .topLeading)
//        .background(cardBackground)
//        .roundedBorder(...)
//        .publishEqualHeight()
//
//  The card MUST include `uniformHeight` in its `Equatable ==` so it both
//  applies the settled height and still skips body on stable input.
//
//  Why it converges: `minHeight` only PADS — a card whose natural content is
//  taller than `uniformHeight` still measures its true height, so the parent's
//  monotonic-max `onPreferenceChange` climbs to the tallest card's natural
//  height and then stops (1–2 frames). No per-tick cost: the GeometryReader +
//  onPreferenceChange fire only on layout/content change, not at 30 Hz.
//

import SwiftUI

/// Collects the tallest measured card height across a grid subtree.
/// Each grid has its own `onPreferenceChange`, so a single shared key type is
/// safe across multiple grids on screen at once (preferences scope per subtree).
struct EqualHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// Apply a uniform minimum height (the measured tallest sibling). `minHeight`
    /// only pads, so taller content is never clipped. Apply BEFORE the visible
    /// `.background`/`.roundedBorder` so the decoration fills the equalized height.
    func equalHeightFrame(_ uniform: CGFloat, min floor: CGFloat = 0, alignment: Alignment = .top) -> some View {
        frame(maxWidth: .infinity, minHeight: Swift.max(uniform, floor), alignment: alignment)
    }

    /// Publish this view's laid-out height up via `EqualHeightKey`. Apply as the
    /// LAST modifier on the card so it measures the fully-decorated frame.
    func publishEqualHeight() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: EqualHeightKey.self, value: proxy.size.height)
            }
        )
    }
}
