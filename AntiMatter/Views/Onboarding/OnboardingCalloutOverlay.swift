//
//  OnboardingCalloutOverlay.swift
//  AntiMatter
//
//  One-time new-player onboarding: shared model + anchored callout overlay.
//
//  Flow: a fresh save surfaces `OnboardingWelcomeSheet` (welcome phase). If the
//  player opts in, `engine.onboarding.phase` flips to `.callouts` and this
//  overlay walks them through a short sequence of dismissible callouts, each
//  anchored (where possible) to a real UI element with an arrow.
//
//  Per-platform: iPad anchors all three element callouts. iPhone anchors the
//  header antimatter counter + tab bar (both outside the SubtabPager boundary)
//  but the dimension buy button — a CALayer row inside the pager — can't take a
//  SwiftUI anchorPreference, so its callout degrades to a centered fixed card.
//  Any callout whose target anchor is missing renders as a centered card.
//

import SwiftUI

// MARK: - Model

enum OnboardingPhase: Equatable {
    case welcome
    case callouts
}

/// One-shot onboarding session state. `nil` on `GameEngine` = inactive.
struct OnboardingState: Identifiable, Equatable {
    /// Stable identity for `.sheet(item:)` — one session per launch.
    let id = UUID()
    var phase: OnboardingPhase
    var calloutStep: Int = 0

    /// Number of callout steps (3 anchored + 1 floating goal pointer).
    static var calloutCount: Int { OnboardingCallout.sequence.count }
}

/// Which UI element a callout points at. Absent target → floating centered card.
enum OnboardingTarget: Hashable {
    case dimensionBuyButton
    case antimatterCounter
    case tabNav
}

struct OnboardingCallout {
    let target: OnboardingTarget?   // nil = floating goal pointer
    let title: LocalizedStringKey
    let body: LocalizedStringKey

    static let sequence: [OnboardingCallout] = [
        .init(target: .dimensionBuyButton,
              title: "Buy a Dimension",
              body: "Tap here to buy your first Antimatter Dimension. Dimensions generate antimatter — and each higher tier produces the tier below it."),
        .init(target: .antimatterCounter,
              title: "Your Antimatter",
              body: "This is your antimatter — the core currency. Spend it on more Dimensions to grow faster and faster."),
        .init(target: .tabNav,
              title: "Finding Your Way",
              body: "This is your menu — tap an item to switch tabs, and swipe to flip through more pages of them. New tabs and features appear here as you progress, so check back as you grow."),
        .init(target: nil,
              title: "Your First Goal",
              body: "Keep buying Dimensions until you can reach Infinity — your first big milestone. Good luck!"),
    ]
}

// MARK: - Anchor preference plumbing

struct OnboardingAnchorKey: PreferenceKey {
    static let defaultValue: [OnboardingTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [OnboardingTarget: Anchor<CGRect>],
                       nextValue: () -> [OnboardingTarget: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    /// Tag this view as an onboarding callout target. Only writes the preference
    /// while onboarding is active so there's zero per-tick preference churn in
    /// the normal (no-onboarding) case.
    @ViewBuilder
    func onboardingAnchor(_ target: OnboardingTarget, active: Bool) -> some View {
        if active {
            anchorPreference(key: OnboardingAnchorKey.self, value: .bounds) { [target: $0] }
        } else {
            self
        }
    }

    /// Attach at a shell root that contains the tagged targets. Renders the
    /// callout overlay only during the `.callouts` phase; otherwise free.
    func onboardingCalloutOverlay(engine: GameEngine) -> some View {
        overlayPreferenceValue(OnboardingAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if let state = engine.onboarding, state.phase == .callouts {
                    OnboardingCalloutOverlay(
                        engine: engine,
                        step: state.calloutStep,
                        anchors: anchors,
                        proxy: proxy
                    )
                    .transition(.opacity)
                }
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - Overlay

struct OnboardingCalloutOverlay: View {
    let engine: GameEngine
    let step: Int
    let anchors: [OnboardingTarget: Anchor<CGRect>]
    let proxy: GeometryProxy

    @State private var cardSize: CGSize = CGSize(width: 280, height: 150)

    private var callout: OnboardingCallout {
        let seq = OnboardingCallout.sequence
        return seq[min(max(step, 0), seq.count - 1)]
    }

    private var isLast: Bool { step >= OnboardingState.calloutCount - 1 }

    /// Resolved target rect in the overlay's coordinate space, if anchored and present.
    private var targetRect: CGRect? {
        guard let target = callout.target, let anchor = anchors[target] else { return nil }
        return proxy[anchor]
    }

    var body: some View {
        let screen = proxy.size
        ZStack(alignment: .topLeading) {
            // Dimming scrim — captures taps so the game underneath stays inert.
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { /* swallow — advance only via the button */ }

            if let rect = targetRect {
                // Highlight ring around the anchored element.
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(GameColor.antimatter, lineWidth: 3)
                    .frame(width: rect.width + 12, height: rect.height + 12)
                    .position(x: rect.midX, y: rect.midY)
                    .shadow(color: GameColor.antimatter.opacity(0.8), radius: 8)
                    .allowsHitTesting(false)
            }

            calloutCard
                .frame(width: cardWidth(screen))
                .background(sizeReader)
                .position(cardPosition(screen: screen, rect: targetRect))

            if let rect = targetRect {
                arrow(screen: screen, rect: rect)
            }
        }
        .frame(width: screen.width, height: screen.height)
    }

    // MARK: Card

    private var calloutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(callout.title)
                .font(.headline)
                .foregroundStyle(GameColor.antimatter)
            Text(callout.body)
                .font(.subheadline)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("\(step + 1) / \(OnboardingState.calloutCount)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                GameButton(borderColor: .green, isEnabled: true) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        engine.advanceOnboardingCallout()
                    }
                } label: {
                    Text(isLast ? "Let's go!" : "Got it")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(GameColor.antimatter.opacity(0.6), lineWidth: 1)
                )
        )
    }

    private var sizeReader: some View {
        GeometryReader { g in
            Color.clear
                .onAppear { cardSize = g.size }
                .onChange(of: g.size) { _, new in cardSize = new }
        }
    }

    // MARK: Geometry

    private func cardWidth(_ screen: CGSize) -> CGFloat {
        min(320, screen.width - 32)
    }

    /// Card center. When anchored, places below the target if it sits in the
    /// top 60% of the screen, otherwise above. Clamped to stay on screen.
    private func cardPosition(screen: CGSize, rect: CGRect?) -> CGPoint {
        guard let rect else {
            // Floating / missing-anchor: centered, biased slightly downward.
            return CGPoint(x: screen.width / 2, y: screen.height * 0.5)
        }
        let gap: CGFloat = 18 // room for the arrow
        let below = rect.midY < screen.height * 0.6
        let halfH = cardSize.height / 2
        var y = below ? rect.maxY + gap + halfH : rect.minY - gap - halfH
        y = min(max(y, 16 + halfH), screen.height - 16 - halfH)

        let halfW = cardWidth(screen) / 2
        let x = min(max(rect.midX, 16 + halfW), screen.width - 16 - halfW)
        return CGPoint(x: x, y: y)
    }

    @ViewBuilder
    private func arrow(screen: CGSize, rect: CGRect) -> some View {
        let below = rect.midY < screen.height * 0.6
        let card = cardPosition(screen: screen, rect: rect)
        let halfW = cardWidth(screen) / 2
        let halfH = cardSize.height / 2
        let arrowX = min(max(rect.midX, card.x - halfW + 18), card.x + halfW - 18)
        let arrowY = below ? card.y - halfH - 5 : card.y + halfH + 5
        OnboardingArrow(pointingUp: below)
            .fill(Color.black)
            .overlay(
                OnboardingArrow(pointingUp: below)
                    .stroke(GameColor.antimatter.opacity(0.6), lineWidth: 1)
            )
            .frame(width: 20, height: 12)
            .position(x: arrowX, y: arrowY)
            .allowsHitTesting(false)
    }
}

/// Small triangle pointer for the callout card.
private struct OnboardingArrow: Shape {
    let pointingUp: Bool
    func path(in rect: CGRect) -> Path {
        var p = Path()
        if pointingUp {
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        }
        p.closeSubpath()
        return p
    }
}
