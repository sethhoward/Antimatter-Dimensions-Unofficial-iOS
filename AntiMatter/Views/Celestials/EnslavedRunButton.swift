//
//  EnslavedRunButton.swift
//  AntiMatter
//
//  Animated 96-pt circular "Start The Nameless Ones' Reality" button. Mirrors
//  the web's c-enslaved-run-button__icon spin animation:
//   - `a-enslaved-run-button--spin` 120s linear (idle) — slow, ~3°/s.
//   - `a-enslaved-run-button--spin` 15s linear (running) — 8× faster, ~24°/s.
//
//  Web's running state also overlays 25 procedurally-generated glitch lines.
//  We skip the glitch lines (out of scope; can be added as a follow-up).
//
//  Uses SF Symbol `link` because the web's `` Font Awesome glyph renders
//  as tofu on iOS.
//

import SwiftUI

struct EnslavedRunButton: View {
    let isRunning: Bool
    /// Off-screen cached SubtabPager pages pass `false` to tear down the
    /// CAAnimation timeline (otherwise the 120s rotation keeps interpolating
    /// on the render server).
    let isActive: Bool
    /// Pelle-doomed sites set this to false to gray out + block hits.
    let isEnabled: Bool
    let action: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    private var isAnimating: Bool { isActive && scenePhase == .active }

    /// 120s idle, 15s running — matches web CSS.
    private var spinPeriod: Double { isRunning ? 15 : 120 }

    var body: some View {
        Button(action: action) {
            // Two layers — the constant chain icon, and the spinning rotation
            // wrapper. Pulled out so the inner Button receives full taps even
            // mid-spin (rotationEffect doesn't change hit-test geometry, but
            // the explicit `.contentShape(Circle())` makes the disc fully
            // tappable rather than the SF Symbol's tight bounds — same fix
            // as the original inline button).
            Group {
                if isAnimating {
                    // KeyframeAnimator drives a CA keyframe sequence (linear
                    // 0..360° over `spinPeriod`). The `id(spinPeriod)` is what
                    // flips the schedule from 120s → 15s when the run starts.
                    KeyframeAnimator(initialValue: 0.0, repeating: true) { angle in
                        chainIcon
                            .rotationEffect(.degrees(angle))
                    } keyframes: { _ in
                        LinearKeyframe(360.0, duration: spinPeriod)
                    }
                    .id(spinPeriod)
                } else {
                    // Snapped-to-rest variant for off-screen / backgrounded
                    // pages so no animation is scheduled.
                    chainIcon
                }
            }
            .frame(width: 96, height: 96)
            .background(Color.black.opacity(0.5), in: Circle())
            .overlay(Circle().stroke(GameColor.enslaved, lineWidth: 2))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .allowsHitTesting(isEnabled)
    }

    private var chainIcon: some View {
        Image(systemName: "link")
            .font(.system(size: 48, weight: .regular))
            .foregroundStyle(GameColor.enslaved)
    }
}
