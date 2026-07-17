//
//  ScrollPositionPreserver.swift
//  AntiMatter
//
//  Persists a ScrollView's vertical offset across navigation. SwiftUI rebuilds
//  ScrollView state on every appearance, so leaving and re-entering a subtab
//  resets scroll to the top. This modifier captures `contentOffset` via
//  `onScrollGeometryChange` and restores it on appear.
//
//  Usage:
//      ScrollView { … }.preserveScrollPosition(key: "normalChallenges")
//

import SwiftUI

@MainActor
final class ScrollPositionStore {
    static let shared = ScrollPositionStore()
    private var positions: [String: CGPoint] = [:]
    func get(_ key: String) -> CGPoint { positions[key] ?? .zero }
    func set(_ key: String, _ point: CGPoint) { positions[key] = point }
}

extension View {
    func preserveScrollPosition(key: String) -> some View {
        modifier(ScrollPositionPreserver(key: key))
    }
}

private struct ScrollPositionPreserver: ViewModifier {
    let key: String
    @State private var position: ScrollPosition = ScrollPosition()
    @State private var didRestore: Bool = false

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGPoint.self) { geo in
                geo.contentOffset
            } action: { _, new in
                guard didRestore else { return }
                ScrollPositionStore.shared.set(key, new)
            }
            .onAppear {
                let saved = ScrollPositionStore.shared.get(key)
                if saved != .zero {
                    position.scrollTo(point: saved)
                }
                // Defer "armed" state to next runloop so the initial
                // onScrollGeometryChange fire (offset .zero before the
                // restore lands) doesn't overwrite the stored value.
                DispatchQueue.main.async { didRestore = true }
            }
            .onDisappear {
                didRestore = false
            }
    }
}
