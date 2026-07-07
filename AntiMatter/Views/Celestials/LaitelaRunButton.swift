//
//  LaitelaRunButton.swift
//  AntiMatter
//
//  Continuously rotating SF Symbol used as the visual sigil of the
//  "Start Lai'tela's Reality" button. Mirrors the spirit of the web's
//  o-laitela-run-button__icon CSS:
//   - Idle: 15s linear scroll of a tiled SVG inside a circle
//     (`a-laitela-run-button__icon--scroll`).
//   - Running: 5s — 3× faster.
//
//  We don't have the tiled SVG asset, and our existing iOS run button is a
//  horizontal card rather than the web's circular icon. Per the design
//  decision recorded in the run-button-animation plan: keep the horizontal
//  card layout, replace the static `sparkles` SF Symbol with one that
//  rotates continuously at the same idle/running cadence as the web. Captures
//  the "ongoing motion in the void" intent without redesigning the button.
//
//  All animation is gated on scenePhase + isActive, matching every other
//  celestial run-button (TeresaRunButton / EffarigRunButton / ...).
//

import SwiftUI

struct LaitelaSparkleIcon: View {
    let isRunning: Bool
    /// Off-screen cached SubtabPager pages pass `false` so the CA spin
    /// animation tears down.
    let isActive: Bool

    @Environment(\.scenePhase) private var scenePhase

    private var isAnimating: Bool { isActive && scenePhase == .active }

    /// 15s idle, 5s running — matches the web's CSS keyframe periods.
    private var spinPeriod: Double { isRunning ? 5 : 15 }

    var body: some View {
        Group {
            if isAnimating {
                // KeyframeAnimator with `id(spinPeriod)` so the schedule is
                // restarted (not just retimed) when the user starts the run
                // and the period jumps from 15s to 5s.
                KeyframeAnimator(initialValue: 0.0, repeating: true) { angle in
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .rotationEffect(.degrees(angle))
                } keyframes: { _ in
                    LinearKeyframe(360.0, duration: spinPeriod)
                }
                .id(spinPeriod)
            } else {
                Image(systemName: "sparkles")
                    .font(.title3)
            }
        }
    }
}
