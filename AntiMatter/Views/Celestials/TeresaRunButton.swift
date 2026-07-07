//
//  TeresaRunButton.swift
//  AntiMatter
//
//  Animated circular button for "Start Teresa's Reality". Mirrors the web's
//  c-teresa-run-button__icon CSS animations:
//   - `a-teresa-run-button__icon--glow` (3s loop) — pulsing text shadow,
//     always running.
//   - `a-teresa-run-button__icon--super-glow` (1.2s loop) — stronger pulse +
//     box shadow when the user is currently inside Teresa's Reality.
//   - `a-teresa-run-button__icon--spin` (5s loop) — chaotic rotation through
//     a fixed sequence of angles when inside the run.
//

import SwiftUI

/// Animated circular button. Previously used `TimelineView(.animation)` to
/// drive the glow and rotation each frame, forcing a CPU body re-eval + shadow
/// rasterization on every tick. Refactored to use:
///   - `withAnimation(.easeInOut.repeatForever)` on an `@State` glow pulse →
///     Core Animation interpolates `shadowRadius` on the render server.
///   - `KeyframeAnimator` for the spin → Core Animation keyframe sequence, no
///     per-frame SwiftUI body work.
/// Both animations are GPU-composited. At rest, CPU cost is zero.
struct TeresaRunButton: View {
    let isRunning: Bool
    /// When false, the animation state collapses to the resting frame so
    /// cached SubtabPager pages don't keep animations scheduled off-screen.
    let isActive: Bool
    let action: () -> Void

    /// Drives the pulsing glow. Animates between 0 and 1 via
    /// `.repeatForever(autoreverses:)` — Core Animation runs the interpolation
    /// on the render server, no SwiftUI body re-eval per frame.
    @State private var glowPulse: Double = 0

    /// Scene-phase observation so the `.repeatForever` CAAnimation is torn
    /// down when the app backgrounds — otherwise it keeps interpolating
    /// `shadowRadius` on the render server while the user's on the lock
    /// screen and burns CPU. Pairs with `isActive` (off-screen pause).
    @Environment(\.scenePhase) private var scenePhase

    /// Combined "should the glow be animating right now" — true only when
    /// on-screen AND the app is foregrounded.
    private var isAnimating: Bool { isActive && scenePhase == .active }

    var body: some View {
        let baseColor = GameColor.teresa
        let foreground: Color = isRunning ? .white : baseColor.readableOnDark()
        let fill: Color = isRunning ? baseColor : .black
        let strokeColor: Color = isRunning ? baseColor.readableOnDark() : baseColor
        let pulse = isAnimating ? glowPulse : 0

        Button(action: action) {
            iconContent(
                foreground: foreground,
                fill: fill,
                strokeColor: strokeColor,
                baseColor: baseColor,
                pulse: pulse
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start Teresa's Reality")
        .onAppear { startGlow() }
        .onChange(of: isRunning) { _, _ in startGlow() }
        .onChange(of: isAnimating) { _, animating in
            // Pause animation while off-screen OR backgrounded; resume on return.
            if animating { startGlow() } else { glowPulse = 0 }
        }
    }

    @ViewBuilder
    private func iconContent(
        foreground: Color,
        fill: Color,
        strokeColor: Color,
        baseColor: Color,
        pulse: Double
    ) -> some View {
        // Core container — glow modifiers animate via Core Animation when
        // their inputs change, so updating `pulse` via withAnimation produces
        // a GPU-driven shadow radius transition.
        let icon = Text("Ϟ")
            .font(.system(size: 64, weight: .bold))
            .foregroundStyle(foreground)
            // text-shadow pulse (GPU-composited — CALayer.shadowRadius animation)
            .shadow(color: baseColor.opacity(0.9), radius: 2 + pulse * 6)
            .frame(width: 120, height: 120)
            .background(Circle().fill(fill))
            .overlay(Circle().strokeBorder(strokeColor, lineWidth: 4))
            // box-shadow pulse — only meaningful when running (super-glow keyframe)
            .shadow(color: isRunning ? baseColor.opacity(0.7) : .clear,
                    radius: isRunning ? 4 + pulse * 12 : 0)

        if isRunning && isAnimating {
            // KeyframeAnimator schedules a Core Animation keyframe sequence.
            // Unlike TimelineView, no SwiftUI body re-eval fires per frame —
            // CA interpolates `rotationDegrees` on the render server. Gated
            // on `isAnimating` so the CA keyframe timeline is torn down when
            // the app backgrounds (otherwise it keeps ticking on the render
            // server during lock screen).
            KeyframeAnimator(
                initialValue: 61.0,
                repeating: true
            ) { rotationDegrees in
                icon.rotationEffect(.degrees(rotationDegrees))
            } keyframes: { _ in
                // 11 hand-picked angles over 5s, matching the web's
                // `a-teresa-run-button__icon--spin` @keyframes rule.
                KeyframeTrack {
                    let stepDuration = 5.0 / Double(Self.spinKeyframes.count - 1)
                    for angle in Self.spinKeyframes.dropFirst() {
                        LinearKeyframe(angle, duration: stepDuration)
                    }
                }
            }
        } else {
            icon
        }
    }

    private func startGlow() {
        guard isAnimating else {
            glowPulse = 0
            return
        }
        // Snap to starting value without animation, then schedule the
        // repeating animation. SwiftUI's repeatForever attaches a CAAnimation
        // to the underlying CALayer — after setup, no per-frame work.
        glowPulse = 0
        let period: Double = isRunning ? 1.2 : 3.0
        withAnimation(.easeInOut(duration: period / 2).repeatForever(autoreverses: true)) {
            glowPulse = 1
        }
    }

    // MARK: - Spin keyframes

    /// Web's `a-teresa-run-button__icon--spin` keyframe — 11 hand-picked
    /// angles at 0/10/20/.../100% over 5 seconds, looped.
    private static let spinKeyframes: [Double] = [
        61, 322, 235, 222, 105, 33, 103, 158, 41, 73, 61
    ]
}
