//
//  OfflineProgressView.swift
//  AntiMatter
//
//  Full-screen overlay shown during offline progress simulation.
//  Displays a progress bar with Speed up / SKIP controls,
//  matching the web's ModalProgressBar.vue behavior.
//

import SwiftUI

struct OfflineProgressView: View {
    let progress: OfflineSimProgress
    let engine: GameEngine

    private var fraction: Double {
        guard progress.total > 0 else { return 0 }
        return Double(progress.current) / Double(progress.total)
    }

    private var remaining: Int {
        max(progress.total - progress.current, 0)
    }

    private var estimatedTimeRemaining: String {
        let elapsed = Date().timeIntervalSince(progress.startTime)
        guard progress.current > 0, elapsed > 0 else { return "Calculating..." }
        let rate = Double(progress.current) / elapsed
        let secondsLeft = Double(remaining) / rate
        if secondsLeft < 60 {
            return "\(Int(secondsLeft))s"
        } else {
            return "\(Int(secondsLeft / 60))m \(Int(secondsLeft) % 60)s"
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Offline Progress Simulation")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)

                Text("The game is being simulated at a lower accuracy in order to quickly calculate the resources you gained while you were away.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                VStack(spacing: 8) {
                    HStack {
                        Text("Ticks: \(formatInt(progress.current)) / \(formatInt(progress.total))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.white)
                        Spacer()
                        Text("Remaining: \(estimatedTimeRemaining)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.1))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.green)
                                .frame(width: geo.size.width * fraction)
                                .animation(.linear(duration: 0.15), value: fraction)
                        }
                    }
                    .frame(height: 12)
                }
                .padding(.horizontal, 40)

                HStack(spacing: 16) {
                    if remaining > 500 {
                        GameButton(borderColor: .green, isEnabled: true, action: {
                            engine.offlineSimSpeedUp()
                        }) {
                            Text("Speed up")
                                .font(.subheadline.weight(.medium))
                        }
                    }
                    if remaining > 10 {
                        GameButton(borderColor: .orange, isEnabled: true, action: {
                            engine.offlineSimSkip()
                        }) {
                            Text("SKIP")
                                .font(.subheadline.weight(.bold))
                        }
                    }
                }
            }
            .frame(maxWidth: 500)
        }
    }

    private func formatInt(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
