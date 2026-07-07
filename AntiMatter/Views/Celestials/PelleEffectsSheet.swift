//
//  PelleEffectsSheet.swift
//  AntiMatter
//
//  Phase 8 of the Pelle port. Sheet listing the ~35 disabled / nerfed
//  mechanics in Doomed Reality. Direct port of PelleEffectsModal.vue —
//  the strings are built JS-side via live `format()` calls so the
//  player's notation choice is honored.
//

import SwiftUI

struct PelleEffectsSheet: View {
    let engine: GameEngine
    @Binding var isPresented: Bool

    private var entries: [PelleDisabledMechanicInfo] {
        engine.gameState.celestials.pelle.disabledMechanics
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("These are the mechanics that are disabled or weakened while you are Doomed. Some can be reacquired through Pelle Upgrades.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                    Divider().overlay(GameColor.pelle.opacity(0.4))
                    if entries.isEmpty {
                        Text("(No data — make sure you are Doomed.)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 16)
                    } else {
                        ForEach(entries) { e in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(GameColor.pelle.opacity(0.8))
                                    .padding(.top, 3)
                                Text(e.label)
                                    .font(.callout)
                                    .foregroundStyle(.white)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 2)
                        }
                    }
                }
                .padding(16)
            }
            .adaptiveSheetTitle("Doomed Reality — Effects")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { isPresented = false }
                        .tint(GameColor.pelle)
                }
            }
        }
    }
}
