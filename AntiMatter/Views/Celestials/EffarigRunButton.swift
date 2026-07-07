//
//  EffarigRunButton.swift
//  AntiMatter
//
//  Animated rectangular "Begin Effarig's Reality" button. Mirrors the web's
//  c-effarig-run-button CSS animations:
//   - `a-effarig-run-button--not-running-glow` (2s ease-in-out alternate) —
//     pulsing red text + box shadow, always running pre-run-start.
//   - `a-effarig-run-button--running-glow` (2s alternate) — brighter inset+outset
//     glow when the user is currently inside Effarig's Reality.
//   - `a-effarig-run-button--running-noise` (15s alternate) — SVG noise mask
//     that flickers the inner sigil opacity. We don't have the noise PNG +
//     `background-clip: text`, so we substitute a slow opacity flicker on the
//     sigil text only (1.0 → 0.55) for the same "unstable" feeling.
//
//  Animation lifecycle is enforced **structurally** — the parent picks one of
//  three child views (`StaticLabel`, `IdleAnimatedLabel`, `RunningAnimatedLabel`)
//  based on `(isAnimating, isRunning)`. When the state flips, SwiftUI destroys
//  the prior child and creates a fresh one, taking all `.repeatForever`
//  CAAnimations with it. This is the only reliable way to cancel a repeating
//  schedule on iOS — `withAnimation(.linear(duration: 0))` doesn't always
//  detach the prior CAAnimation, so the running-state glow can continue
//  ticking after the user exits the reality.
//

import SwiftUI

struct EffarigRunButton: View {
    let isRunning: Bool
    /// Off-screen pages pass `false` so cached SubtabPager pages don't keep
    /// any CAAnimation scheduled.
    let isActive: Bool
    let action: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    private var isAnimating: Bool { isActive && scenePhase == .active }

    var body: some View {
        Button(action: action) {
            content
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!isRunning)
    }

    @ViewBuilder
    private var content: some View {
        if !isAnimating {
            // No animations — view tree contains zero `.repeatForever`.
            EffarigStaticLabel(isRunning: isRunning)
        } else if isRunning {
            // Running palette + flicker. `.id("running")` is intentional —
            // pairs with `.id("idle")` below so SwiftUI rebuilds the subtree
            // when isRunning flips and the prior repeating CAAnimation is
            // torn down with the destroyed view.
            EffarigRunningLabel().id("running")
        } else {
            EffarigIdleLabel().id("idle")
        }
    }
}

// MARK: - Static rest variant (no animations)

private struct EffarigStaticLabel: View {
    let isRunning: Bool

    var body: some View {
        EffarigLabelStack(isRunning: isRunning, sigilOpacity: 1)
    }
}

// MARK: - Idle (pre-run) animated variant — pulsing red glow only

private struct EffarigIdleLabel: View {
    @State private var glowPulse: Double = 0

    private static let from = Color(hex: "#cb1a1a")
    private static let to   = Color(hex: "#bf0404")

    var body: some View {
        let color = lerp(Self.from, Self.to, t: glowPulse)
        let outer: CGFloat = 4 + 12 * glowPulse
        let inner: CGFloat = 2 + 4 * glowPulse

        EffarigLabelStack(isRunning: false, sigilOpacity: 1)
            .shadow(color: color.opacity(0.85), radius: outer)
            .shadow(color: color.opacity(0.95), radius: inner)
            .onAppear {
                // Web period 2s alternate → 1s half-cycle each direction.
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    glowPulse = 1
                }
            }
    }
}

// MARK: - Running variant — brighter glow + slow opacity flicker

private struct EffarigRunningLabel: View {
    @State private var glowPulse: Double = 0
    /// Sigil opacity flicker (1.0 .. 0.55, 15s round-trip — slow enough to
    /// feel uncanny without strobing). Substitutes for the web's noise PNG
    /// mask, which we don't bundle.
    @State private var sigilFlicker: Double = 1

    private static let from = Color(hex: "#c20707")
    private static let to   = Color(hex: "#e21717")

    var body: some View {
        let color = lerp(Self.from, Self.to, t: glowPulse)
        let outer: CGFloat = 8 + 14 * glowPulse
        let inner: CGFloat = 3 + 6 * glowPulse

        EffarigLabelStack(isRunning: true, sigilOpacity: sigilFlicker)
            .shadow(color: color.opacity(0.85), radius: outer)
            .shadow(color: color.opacity(0.95), radius: inner)
            .onAppear {
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    glowPulse = 1
                }
                withAnimation(.easeInOut(duration: 7.5).repeatForever(autoreverses: true)) {
                    sigilFlicker = 0.55
                }
            }
    }
}

// MARK: - Shared label content

/// The actual button face — sigil + caption + rounded-rect background. All
/// three animated variants share this so visual styling stays consistent.
private struct EffarigLabelStack: View {
    let isRunning: Bool
    let sigilOpacity: Double

    var body: some View {
        VStack(spacing: 4) {
            Text("Ϙ")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(isRunning ? GameColor.effarig : GameColor.effarig.readableOnDark())
                .opacity(sigilOpacity)
            Text(isRunning ? "Currently Running" : "Begin Effarig's Reality")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: 220)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(isRunning ? 0.5 : 0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(GameColor.effarig, lineWidth: 2)
                )
        )
    }
}

// MARK: - Color interpolation helper

/// Linear interpolation between two SwiftUI Colors. For our 3-channel CSS
/// reds this is good enough — no need for HSL/Oklab.
private func lerp(_ a: Color, _ b: Color, t: Double) -> Color {
    let ra = a.resolveSRGB(), rb = b.resolveSRGB()
    let tt = max(0, min(1, t))
    return Color(red: ra.r + (rb.r - ra.r) * tt,
                 green: ra.g + (rb.g - ra.g) * tt,
                 blue: ra.b + (rb.b - ra.b) * tt)
}

private extension Color {
    /// Best-effort resolve to sRGB components. Falls back to (1, 0, 0) if
    /// UIKit can't decompose the color (shouldn't happen for our hex shades).
    func resolveSRGB() -> (r: Double, g: Double, b: Double) {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return (1, 0, 0)
        }
        return (Double(r), Double(g), Double(b))
    }
}
