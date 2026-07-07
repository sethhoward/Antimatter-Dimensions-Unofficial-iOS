//
//  BigCrunchTakeover.swift
//  AntiMatter
//
//  Full-screen Big Crunch view that replaces the content area
//  pre-Break Infinity when the player can crunch and their best
//  infinity time exceeds 1 minute. Matches the web Modern UI.
//

import SwiftUI

private let colorInfinity = GameColor.infinity

struct BigCrunchTakeover: View {
    let engine: GameEngine

    @Environment(\.layoutMetrics) private var metrics

    private var state: GameState { engine.gameState }
    /// Web shows "world collapsed" text only when bestInfinity > 1 min;
    /// compact (small) crunch button when best time is fast.
    private var smallCrunch: Bool { state.infinity.bestInfinityMs <= 60_000 }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            if !smallCrunch {
                Text("The world has collapsed due to excess antimatter.")
                    .font(.system(size: metrics.isCompact ? 14 : 17))
                    .foregroundStyle(.white.opacity(0.8))
            }

            Button {
                Haptics.tap()
                engine.bigCrunch()
            } label: {
                Text("Big Crunch")
                    .font(.system(size: metrics.isCompact ? 36 : 52, weight: .medium, design: .monospaced))
                    .foregroundStyle(colorInfinity)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.black)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(colorInfinity.opacity(0.6), lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)

            if state.infinity.hasIP {
                Text("for \(state.infinity.gainedIP) Infinity Points")
                    .font(.system(size: 15).monospacedDigit())
                    .foregroundStyle(colorInfinity.opacity(0.7))
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GameColor.baseBackground)
    }
}
