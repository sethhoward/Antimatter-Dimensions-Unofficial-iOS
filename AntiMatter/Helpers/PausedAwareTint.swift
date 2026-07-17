//
//  PausedAwareTint.swift
//  AntiMatter
//
//  Shared "autobuyers globally paused" environment + Toggle tint modifier.
//
//  Many tabs (Autobuyers, Infinity Dimensions, Time Dimensions, Replicanti,
//  Black Hole) host inline autobuyer toggles. When the user globally pauses
//  autobuyers (`player.auto.autobuyersOn = false`), we want every active
//  toggle in the app to flip from its normal-state color to yellow
//  (`GameColor.pausedActive` / web's `--color-good-paused`), signalling
//  "would be running but paused." Off toggles stay grey natively — never
//  apply a tint to them, since iOS bleeds the configured tint hue onto the
//  off-track in some renderings (scaled toggles, `.controlSize(.small)`).
//
//  iOS divergence from web: web only shows toggles on the Autobuyers tab;
//  iOS exposes them inline across multiple tabs as a tablet-layout
//  optimization (see the design notes "Known iPad Layout Divergences"). The
//  paused tint applies uniformly so users get the same paused signal
//  regardless of which tab they're looking at.
//
//  The env value is set once at the app shell (ContentView) from
//  `engine.gameState.autobuyers.allOn`; every Toggle site reads it via
//  the `.pausedAwareTint(isActive:normalColor:)` modifier.
//

import SwiftUI

struct AutobuyersPausedKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var autobuyersGloballyPaused: Bool {
        get { self[AutobuyersPausedKey.self] }
        set { self[AutobuyersPausedKey.self] = newValue }
    }
}

/// Swaps a Toggle's on-state tint to yellow when autobuyers are globally
/// paused. When the toggle is OFF, applies no tint at all so the system
/// default grey off-track renders cleanly (avoids the iOS quirk where
/// scaled / small-control Toggles bleed the tint hue onto the off-track
/// at first paint). When ON and not paused, applies the supplied
/// `normalColor` (or system default if none).
struct PausedAwareTint: ViewModifier {
    let isActive: Bool
    let normalColor: Color?
    @Environment(\.autobuyersGloballyPaused) private var isPaused: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if !isActive {
            content
        } else if isPaused {
            content.tint(GameColor.pausedActive)
        } else if let normalColor {
            content.tint(normalColor)
        } else {
            content
        }
    }
}

extension View {
    func pausedAwareTint(isActive: Bool, normalColor: Color? = nil) -> some View {
        modifier(PausedAwareTint(isActive: isActive, normalColor: normalColor))
    }
}
