//
//  VRunButton.swift
//  AntiMatter
//
//  Hexagonal "Start V's Reality" run button. Mirrors the web's c-v-run-button
//  treatment:
//   - Idle: static (no animation, matches web).
//   - Running:
//     - Background fill flips to indianred (`#cd5c5c`) per CSS `:hover`,
//       `--running` rules (web replaces the V-yellow with red while inside
//       V's Reality). Note: the web's CSS picks indianred regardless of V's
//       yellow brand color — this divergence from `GameColor.v` is intentional
//       and faithful.
//     - 3 yellow line segments orbit around the hex over a 3s
//       `cubic-bezier(0.9, 0, 0, 0.9)` cycle (`a-c-v-run-button__line--N--move`).
//       We approximate the cubic-bezier with 5 LinearKeyframes per cycle —
//       visually within 5% of the smooth curve.
//     - Synchronized box-shadow burst on the lines (3rem black → 0 → 3rem,
//       `a-c-v-run-button__line--burst`).
//
//  All animations gated on scenePhase + isActive — the running-state
//  KeyframeAnimators are torn out of the hierarchy when off-screen or
//  backgrounded, so no CAAnimation keeps ticking on the lock screen.
//

import SwiftUI

struct VRunButton: View {
    let isRunning: Bool
    /// Off-screen pages pass `false`.
    let isActive: Bool
    /// Pelle-doomed sites pass `false` to gray out + disable.
    let isEnabled: Bool
    let hexWidth: CGFloat
    let hexHeight: CGFloat
    let isCompact: Bool
    let action: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    private var isAnimating: Bool { isActive && scenePhase == .active }

    /// Web running-state fill (`indianred`).
    private static let runningFill = Color(hex: "#cd5c5c")

    var body: some View {
        Button(action: action) {
            // Stack order (bottom → top):
            //   1. Hex fill (indianred when running, V-yellow tint when not).
            //   2. Orbit lines (only while running) — render on top of the
            //      fill but under the icon so they're visible against the bg.
            //   3. Play icon + label.
            // The whole ZStack is `.clipShape(Hexagon())` so rotating lines
            // can't bleed into adjacent honeycomb cells. Border stroke is
            // applied as an overlay AFTER the clip so the line stays sharp.
            ZStack {
                Hexagon()
                    .fill(isRunning ? Self.runningFill : GameColor.v.opacity(0.15))

                if isRunning && isAnimating {
                    ForEach(0..<3, id: \.self) { i in
                        VOrbitLine(index: i, hexWidth: hexWidth, hexHeight: hexHeight)
                    }
                }

                VStack(spacing: 4) {
                    Image(systemName: isRunning ? "pause.fill" : "play.fill")
                        .font(isCompact ? .body : .title2)
                    Text(isRunning ? "V's Reality\nis active" : "Start V's\nReality")
                        .font(isCompact ? .system(size: 10, weight: .bold)
                                       : .caption.weight(.bold))
                        .multilineTextAlignment(.center)
                        .strikethrough(!isEnabled)
                }
                .foregroundStyle(isRunning ? .black : GameColor.v)
            }
            .frame(width: hexWidth, height: hexHeight)
            .clipShape(Hexagon())
            .overlay(Hexagon().stroke(GameColor.v, lineWidth: 2))
            .contentShape(Hexagon())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .allowsHitTesting(isEnabled)
    }
}

// MARK: - Orbiting line segment

/// A single yellow line that translates + rotates around the hex on a 3s
/// cycle. Three of these are drawn at indices 0/1/2 with different start
/// positions — together they orbit the hex like the web's 3-line burst.
///
/// We're rendering against a hex of size `hexWidth × hexHeight` centered at
/// (hexWidth/2, hexHeight/2). The web uses absolute `top`/`left` in rem
/// against a fixed-size container; we scale by `hexWidth / 30` (the web
/// container is ~30rem wide based on the keyframe value range).
private struct VOrbitLine: View {
    let index: Int
    let hexWidth: CGFloat
    let hexHeight: CGFloat

    var body: some View {
        // Line dimensions: 12rem × 2.4rem in CSS → scaled to our hex.
        let scale = hexWidth / 30
        let lineWidth = 12 * scale
        let lineHeight = max(2, 2.4 * scale)

        // Each line gets its own animator instance keyed by `index` so all
        // three KeyframeAnimators are scheduled concurrently and stay in
        // phase with the burst.
        KeyframeAnimator(initialValue: VOrbitState.start(for: index), repeating: true) { state in
            Rectangle()
                .fill(Color(hex: "#e3c759"))
                .frame(width: lineWidth, height: lineHeight)
                .rotationEffect(.degrees(state.rotation))
                .offset(x: state.offsetX * scale, y: state.offsetY * scale)
                // Synchronized burst (matches `a-c-v-run-button__line--burst`).
                // 3rem black → 0 → 3rem; we mirror via state.shadow.
                .shadow(color: .black.opacity(0.85), radius: state.shadow * scale)
        } keyframes: { _ in
            // 3 keyframes — start, mid, end (== start) — over 3s. We use
            // CubicKeyframe with explicit start/end velocities to approximate
            // the web's `cubic-bezier(0.9, 0, 0, 0.9)` (slow-start, slow-end).
            let mid = VOrbitState.mid(for: index)
            let end = VOrbitState.start(for: index)
            KeyframeTrack(\.offsetX) {
                CubicKeyframe(mid.offsetX, duration: 1.5)
                CubicKeyframe(end.offsetX, duration: 1.5)
            }
            KeyframeTrack(\.offsetY) {
                CubicKeyframe(mid.offsetY, duration: 1.5)
                CubicKeyframe(end.offsetY, duration: 1.5)
            }
            KeyframeTrack(\.rotation) {
                CubicKeyframe(mid.rotation, duration: 1.5)
                CubicKeyframe(end.rotation, duration: 1.5)
            }
            KeyframeTrack(\.shadow) {
                LinearKeyframe(0, duration: 1.5)
                LinearKeyframe(3, duration: 1.5)
            }
        }
    }
}

/// Animatable orbit state for a single line. Offsets are in rem
/// (multiplied by `hexWidth / 30` at render time); rotation in degrees.
///
/// The web's `c-v-run-button` container is 30rem × 30rem (its center at
/// (15, 15)rem). The CSS positions each line via `top` / `left` of its
/// top-left corner; line size is 12rem × 2.4rem. We convert each CSS
/// position to a hex-center-relative offset of the line's centre:
///     offsetX = CSS_left + 6  − 15
///     offsetY = CSS_top  + 1.2 − 15
/// Three lines together orbit the hex on a 120° triangular pattern —
/// right-bottom (i=0), left-middle (i=1), right-top (i=2).
private struct VOrbitState {
    var offsetX: CGFloat
    var offsetY: CGFloat
    var rotation: Double
    var shadow: CGFloat

    /// Start (and end) keyframe per line index, hex-center-relative in rem.
    /// Derived from `styles.css` lines 6782–6798.
    static func start(for i: Int) -> VOrbitState {
        switch i {
        // Line 1 — top 23.4rem, left 12.6rem, rot -30°.
        case 0: return VOrbitState(offsetX: 3.6, offsetY: 9.6, rotation: -30, shadow: 3)
        // Line 2 — top 14.4rem, left -3rem, rot 90°.
        case 1: return VOrbitState(offsetX: -12.0, offsetY: 0.6, rotation: 90, shadow: 3)
        // Line 3 — top 5.4rem, left 12.6rem, rot 30°.
        default: return VOrbitState(offsetX: 3.6, offsetY: -8.4, rotation: 30, shadow: 3)
        }
    }

    /// Midpoint keyframe (50% of the cycle). Derived from `styles.css`
    /// lines 6818–6876.
    static func mid(for i: Int) -> VOrbitState {
        switch i {
        // Line 1 mid — top 23.4rem, left 1.8rem, rot 30°.
        case 0: return VOrbitState(offsetX: -7.2, offsetY: 9.6, rotation: 30, shadow: 0)
        // Line 2 mid — top 5.4rem, left 2.4rem, rot 150°.
        case 1: return VOrbitState(offsetX: -6.6, offsetY: -8.4, rotation: 150, shadow: 0)
        // Line 3 mid — top 14.4rem, left 17.4rem, rot 90°.
        default: return VOrbitState(offsetX: 8.4, offsetY: 0.6, rotation: 90, shadow: 0)
        }
    }
}
