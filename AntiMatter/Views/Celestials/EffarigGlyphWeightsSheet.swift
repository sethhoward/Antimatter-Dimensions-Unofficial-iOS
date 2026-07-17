//
//  EffarigGlyphWeightsSheet.swift
//  AntiMatter
//
//  Half-height sheet unlocked by EffarigUnlock.adjuster — lets the player
//  tune the four Glyph level factor weights (EP / Replicanti / DT /
//  Eternities) and toggle auto-adjust. Mirrors
//  src/components/tabs/celestial-effarig/AdjustableGlyphWeights.vue.
//

import SwiftUI

struct EffarigGlyphWeightsSheet: View {
    let engine: GameEngine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var showLevelFactors = true  // expanded by default in the sheet
    @State private var refreshTimer: Timer?

    private var state: EffarigGlyphWeightsState { engine.effarigGlyphWeights ?? EffarigGlyphWeightsState() }

    private var total: Int {
        state.ep + state.repl + state.dt + state.eternities
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Adjust how much each factor contributes to new Glyph levels. Auto-adjust uses the game's suggested split based on your current Reality.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)

                    if state.autoAdjustUnlocked {
                        Toggle("Auto-adjust weights", isOn: Binding(
                            get: { state.autoAdjust },
                            set: { _ in engine.toggleEffarigAutoWeights() }
                        ))
                        .tint(GameColor.effarig)
                    }

                    if !state.autoAdjust {
                        weightRow(label: "Eternity Points", key: "ep", value: state.ep)
                        weightRow(label: "Replicanti", key: "repl", value: state.repl)
                        weightRow(label: "Dilated Time", key: "dt", value: state.dt)
                        weightRow(label: "Eternities", key: "eternities", value: state.eternities)

                        HStack(spacing: 12) {
                            Text("Total")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))
                            Text("\(total)")
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(total == 100 ? GameColor.good : GameColor.effarig)
                            Spacer()
                            GameButton(borderColor: GameColor.effarig) {
                                engine.resetEffarigWeights()
                            } label: {
                                Text("Reset to 25/25/25/25")
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                            }
                        }
                        .padding(.top, 4)
                    }

                    // Live Glyph Level Factor breakdown — same disclosure panel
                    // used in the Glyphs tab. Lets the player see how their
                    // weight changes (or an auto-adjust toggle) roll up to the
                    // final Glyph level without leaving the sheet.
                    if let factors = engine.glyphLevelFactorsSnapshot {
                        GlyphLevelFactorsCard(
                            state: factors,
                            isExpanded: $showLevelFactors
                        )
                    }
                }
                .padding(20)
            }
            .adaptiveSheetTitle("Glyph Level Weights")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .tint(GameColor.effarig)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            engine.loadEffarigWeights()
            engine.loadGlyphLevelFactors()
        }
        .onAppear {
            // Keep the level factors live while the sheet is open. 1.5s cadence
            // matches roughly how long a weight change takes to settle on the
            // JS side without hammering the bridge.
            refreshTimer?.invalidate()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
                engine.loadGlyphLevelFactors()
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                refreshTimer?.invalidate()
                refreshTimer = nil
            } else {
                // Restart timer on foreground return if sheet is still visible
                guard refreshTimer == nil else { return }
                refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
                    engine.loadGlyphLevelFactors()
                }
            }
        }
    }

    @ViewBuilder
    private func weightRow(label: String, key: String, value: Int) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(width: 140, alignment: .leading)
            Stepper(
                "\(value)",
                value: Binding(
                    get: { value },
                    set: { engine.setEffarigWeight(key: key, value: $0) }
                ),
                in: 0...100
            )
            .labelsHidden()
            Text("\(value)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(GameColor.effarig)
                .frame(width: 40, alignment: .trailing)
        }
    }
}
