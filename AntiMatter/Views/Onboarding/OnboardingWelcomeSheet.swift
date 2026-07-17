//
//  OnboardingWelcomeSheet.swift
//  AntiMatter
//
//  New-player welcome modal — page 1 is the opt-in ask, pages 2–3 answer
//  "why you're here / what to do / what to expect". Surfaced from the app root
//  (ContentView / PhoneShell) via `.sheet(item:)` when `engine.onboarding.phase
//  == .welcome` on a truly fresh save.
//
//  The "seen" flag is written the moment the player answers page 1 (Show me /
//  No thanks) so the flow never re-shows. Tapping "Start playing" on the last
//  page transitions `engine.onboarding.phase` to `.callouts`, which auto-dismisses
//  this sheet and hands off to `OnboardingCalloutOverlay`.
//

import SwiftUI

struct OnboardingWelcomeSheet: View {
    let engine: GameEngine
    @State private var page = 0

    private static let pageCount = 3

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 24)

                pageDots
                    .padding(.bottom, 12)

                buttonBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GameColor.baseBackground.ignoresSafeArea())
            .adaptiveSheetTitle("Welcome")
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Page content

    @ViewBuilder
    private var content: some View {
        switch page {
        case 0:
            pageBody(
                symbol: "Ω",
                title: "Welcome to Infinity Dimensions",
                text: "An idle game about numbers that grow — slowly at first, then unimaginably fast. Want a quick tour to get you started?"
            )
        case 1:
            pageBody(
                symbol: "Ω",
                title: "What you'll do",
                text: "Buy Dimensions to produce antimatter. Spend that antimatter on more Dimensions. Every purchase compounds — the more you invest, the faster everything grows."
            )
        default:
            pageBody(
                symbol: "∞",
                title: "What to expect",
                text: "Progress unlocks whole new layers — Infinity, Eternity, Reality and beyond. Don't worry about understanding it all now; the game reveals each piece when you're ready."
            )
        }
    }

    private func pageBody(symbol: String, title: LocalizedStringKey, text: LocalizedStringKey) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            Text(symbol)
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(GameColor.antimatter)
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(text)
                .font(.body)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<Self.pageCount, id: \.self) { i in
                Circle()
                    .fill(i == page ? GameColor.antimatter : Color.white.opacity(0.25))
                    .frame(width: 7, height: 7)
            }
        }
    }

    // MARK: Buttons

    @ViewBuilder
    private var buttonBar: some View {
        switch page {
        case 0:
            VStack(spacing: 10) {
                GameButton(borderColor: .green, isEnabled: true) {
                    // Any answer to the opt-in marks onboarding as seen.
                    engine.markOnboardingSeen()
                    withAnimation { page = 1 }
                } label: {
                    barLabel("Show me the ropes")
                }
                GameButton(borderColor: GameColor.unavailableBg, isEnabled: true) {
                    engine.markOnboardingSeen()
                    engine.onboarding = nil
                } label: {
                    barLabel("No thanks, I'll explore")
                }
            }
        case 1:
            HStack(spacing: 12) {
                GameButton(borderColor: GameColor.unavailableBg, isEnabled: true) {
                    withAnimation { page = 0 }
                } label: { barLabel("Back") }
                GameButton(borderColor: .green, isEnabled: true) {
                    withAnimation { page = 2 }
                } label: { barLabel("Next") }
            }
        default:
            HStack(spacing: 12) {
                GameButton(borderColor: GameColor.unavailableBg, isEnabled: true) {
                    withAnimation { page = 1 }
                } label: { barLabel("Back") }
                GameButton(borderColor: .green, isEnabled: true) {
                    startCallouts()
                } label: { barLabel("Start playing") }
            }
        }
    }

    private func barLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
    }

    private func startCallouts() {
        if var state = engine.onboarding {
            state.phase = .callouts
            state.calloutStep = 0
            engine.onboarding = state
        }
    }
}
