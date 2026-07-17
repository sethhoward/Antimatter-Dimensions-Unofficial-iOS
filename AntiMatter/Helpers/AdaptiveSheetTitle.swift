//
//  AdaptiveSheetTitle.swift
//  AntiMatter
//
//  `.navigationBarTitleDisplayMode(.inline)` truncates long titles on iPhone
//  whenever toolbar items exist on both sides — Cancel/Confirm buttons or
//  Done + leading button pairs eat width, and the inline title gets ellipsis
//  clipped. This modifier swaps the title into a `.principal` ToolbarItem on
//  iPhone with `lineLimit(2)` + `minimumScaleFactor(0.7)` so it wraps or
//  shrinks instead of truncating. iPad uses the normal inline title (plenty
//  of width, single-line renders fine).
//
//  Usage on any `NavigationStack` / `NavigationView` root content:
//    .adaptiveSheetTitle("The Nameless Ones — History")
//
//  Drop-in replacement for:
//    .navigationTitle("…")
//    .navigationBarTitleDisplayMode(.inline)
//

import SwiftUI

extension View {
    /// Applies a sheet title that wraps to two lines on iPhone (via a
    /// principal toolbar item with scaling) and renders as a normal inline
    /// nav title on iPad. Call on the content INSIDE a `NavigationStack`.
    func adaptiveSheetTitle(_ title: String) -> some View {
        modifier(AdaptiveSheetTitleModifier(title: title))
    }
}

private struct AdaptiveSheetTitleModifier: ViewModifier {
    let title: String
    @Environment(\.layoutMetrics) private var metrics

    func body(content: Content) -> some View {
        content
            .navigationTitle(metrics.isCompact ? "" : title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if metrics.isCompact {
                    ToolbarItem(placement: .principal) {
                        Text(title)
                            .font(.headline)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.7)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
    }
}
