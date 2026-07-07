//
//  RaRunButton.swift
//  AntiMatter
//
//  Animated "Start Ra's Reality" button. Mirrors the web's
//  c-ra-run-button__icon CSS treatment:
//   - Idle: static, no animations.
//   - `--running` flips colors (sigil → black, bg → Ra purple) and adds two
//     concurrent animations on the sigil:
//     - `a-c-ra-run-button__icon__sigil--undulate` (0.6s ease-in-out) —
//       scale 0.9 → 1.0 → 0.9.
//     - `a-c-ra-run-button__icon__sigil--glow` (3s ease-in-out) —
//       text-shadow 1rem → 3rem → 1rem.
//
//  Animation lifecycle is enforced **structurally** — the parent picks one of
//  two children (`StaticLabel` or `RunningAnimatedLabel`) based on
//  `(isAnimating, isRunning)`. When the run state flips, SwiftUI destroys
//  the prior child and creates a fresh one, taking all `.repeatForever`
//  CAAnimations with it. This is the only reliable way to cancel a repeating
//  schedule on iOS — `withAnimation(.linear(duration: 0))` does not
//  reliably detach the prior CAAnimation, so without view teardown the
//  pulse + glow can continue ticking after the user exits the reality.
//

import SwiftUI

struct RaRunButton: View {
    let isRunning: Bool
    /// Off-screen pages pass `false` to stop animation scheduling.
    let isActive: Bool
    /// True only when the user can actually start (or is inside) Ra's
    /// Reality and Pelle hasn't doomed.
    let isEnabled: Bool
    let action: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    private var isAnimating: Bool { isActive && scenePhase == .active }

    var body: some View {
        Button(action: action) {
            content
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .allowsHitTesting(isEnabled)
    }

    @ViewBuilder
    private var content: some View {
        // Animations only when running AND on-screen. All other branches
        // emit a static label, so no `.repeatForever` is ever scheduled.
        if isRunning && isAnimating {
            RaRunningLabel(isEnabled: isEnabled)
        } else {
            RaStaticLabel(isRunning: isRunning, isEnabled: isEnabled)
        }
    }
}

// MARK: - Static rest variant

private struct RaStaticLabel: View {
    let isRunning: Bool
    let isEnabled: Bool

    var body: some View {
        let foreground: Color = isRunning ? .black : GameColor.ra
        let bg: Color = isRunning ? GameColor.ra : Color.black.opacity(0.4)

        VStack(spacing: 4) {
            Image(systemName: "sun.max.fill")
                .font(.title2)
                .foregroundStyle(foreground)
            Text(isRunning ? "Inside Ra's Reality" : "Start Ra's Reality")
                .font(.caption.weight(.semibold))
                .foregroundStyle(foreground)
                .strikethrough(!isEnabled)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(bg)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(GameColor.ra, lineWidth: 2)
                )
        )
    }
}

// MARK: - Running variant — undulate scale + glow

private struct RaRunningLabel: View {
    let isEnabled: Bool

    /// Drives the undulate scale (0..1, 0.6s alternating).
    @State private var scalePulse: Double = 0
    /// Drives the glow shadow radius (0..1, 3s alternating).
    @State private var glowPulse: Double = 0

    var body: some View {
        let foreground: Color = .black
        let bg: Color = GameColor.ra
        // Scale 0.9 → 1.0 (matches `undulate` keyframe).
        let scale = 0.9 + 0.1 * scalePulse
        // Shadow radius 4 → 12 — chosen to read well at our SF Symbol size
        // (the web's 1rem → 3rem on a 7.5rem sigil scales to roughly the same
        // perceptual range when our title2 sun glyph is ~26pt).
        let glowRadius: CGFloat = 4 + 8 * glowPulse

        VStack(spacing: 4) {
            Image(systemName: "sun.max.fill")
                .font(.title2)
                .foregroundStyle(foreground)
                .shadow(color: GameColor.ra, radius: glowRadius)
                .scaleEffect(scale)
            Text("Inside Ra's Reality")
                .font(.caption.weight(.semibold))
                .foregroundStyle(foreground)
                .strikethrough(!isEnabled)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(bg)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(GameColor.ra, lineWidth: 2)
                )
        )
        .onAppear {
            // Undulate — 0.6s round trip → 0.3s half.
            withAnimation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true)) {
                scalePulse = 1
            }
            // Glow — 3s round trip → 1.5s half.
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                glowPulse = 1
            }
        }
    }
}
