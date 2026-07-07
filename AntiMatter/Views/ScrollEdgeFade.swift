//
//  ScrollEdgeFade.swift
//  AntiMatter
//
//  Adds a horizontal fade mask to a ScrollView's leading/trailing edges,
//  signaling that more content exists off-screen. Edges fade in/out based
//  on the scroll position so a swiped-to-end view fades only the leading
//  edge, and a fits-on-screen view fades nothing.
//

import SwiftUI

extension View {
    /// Apply to a horizontal `ScrollView` to fade its leading/trailing edges
    /// based on scroll position. No-op when content fits the container.
    func scrollEdgeFade(width: CGFloat = 20) -> some View {
        modifier(ScrollEdgeFadeModifier(edgeWidth: width))
    }
}

private struct ScrollEdgeFadeModifier: ViewModifier {
    let edgeWidth: CGFloat
    @State private var leading: CGFloat = 0
    @State private var trailing: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .mask(
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        LinearGradient(
                            stops: [
                                .init(color: .black.opacity(1 - leading), location: 0),
                                .init(color: .black, location: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: edgeWidth)
                        Rectangle().fill(.black)
                            .frame(width: max(0, geo.size.width - edgeWidth * 2))
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black.opacity(1 - trailing), location: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: edgeWidth)
                    }
                }
            )
            .onScrollGeometryChange(for: EdgeFades.self) { geo in
                let maxOffset = max(0, geo.contentSize.width - geo.containerSize.width)
                guard maxOffset > 0.5 else { return EdgeFades(leading: 0, trailing: 0) }
                let x = geo.contentOffset.x
                let leading = min(1, max(0, x / edgeWidth))
                let trailing = min(1, max(0, (maxOffset - x) / edgeWidth))
                return EdgeFades(leading: leading, trailing: trailing)
            } action: { _, new in
                leading = new.leading
                trailing = new.trailing
            }
    }
}

private struct EdgeFades: Equatable {
    var leading: CGFloat
    var trailing: CGFloat
}
