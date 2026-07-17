//
//  PerksTab.swift
//  AntiMatter
//
//  Perks — spatial card grid of purchasable perks (see PerksCardGrid).
//  Header + family color palette + tap → PerkDetailSheet purchase flow
//  live here; the actual canvas/layout lives in PerksCardGrid.swift,
//  shared between iPad and iPhone.
//

import SwiftUI

// Perk IDs whose effects are nullified by Pelle's Doomed Reality are now
// sourced from `engine.pelleUselessPerks` — populated once at startup from
// `Pelle.uselessPerks` (`pelle.js:201-204`) via `_nativePelleDisabledLists()`.
// The hardcoded copy that previously lived here was dropped to avoid drift
// from upstream; see the GameEngine "Pelle disabled-item registries" section
// for the canonical loader.

struct PerksTab: View {
    let engine: GameEngine

    @Environment(\.layoutMetrics) private var metrics
    @State private var selectedPerk: PerkInfo?

    private var state: PerksState { engine.gameState.perksState }

    // Family → color (from web perk CSS)
    static let familyColors: [String: Color] = [
        "REALITY":     Color(red: 0.043, green: 0.373, blue: 0.055),  // #0b600e
        "ANTIMATTER":  Color(red: 0.133, green: 0.667, blue: 0.282),  // #22aa48
        "INFINITY":    Color(red: 0.714, green: 0.498, blue: 0.200),  // #b67f33
        "ETERNITY":    Color(red: 0.698, green: 0.255, blue: 0.890),  // #b241e3
        "DILATION":    GameColor.dilationGreen,
        "AUTOMATION":  Color(red: 1.000, green: 0.000, blue: 0.000),  // #ff0000
        "ACHIEVEMENT": Color(red: 0.992, green: 0.847, blue: 0.208),  // #fdd835
    ]

    static func familyColor(_ family: String) -> Color {
        familyColors[family] ?? .gray
    }

    var body: some View {
        PerksCardGrid(
            engine: engine,
            selectedPerk: $selectedPerk,
            bottomInset: metrics.isCompact ? 80 : 0
        )
        .sheet(item: $selectedPerk) { perk in
            PerkDetailSheet(perk: perk, perkPoints: state.perkPoints, engine: engine, onDismiss: { selectedPerk = nil })
        }
    }
}

// MARK: - Perk Detail Sheet

private struct PerkDetailSheet: View {
    let perk: PerkInfo
    let perkPoints: Int
    let engine: GameEngine
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var canPurchase: Bool {
        perk.canBeBought && !perk.isBought && perkPoints >= 1
    }

    private var familyColor: Color {
        PerksTab.familyColors[perk.family] ?? .gray
    }

    /// True when this perk is bought-but-nullified by Pelle's Doomed Reality.
    private var isPelleUseless: Bool {
        engine.pelleDoomed && perk.isBought && engine.pelleUselessPerks.contains(perk.id)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Label + family badge
                Text(perk.label)
                    .font(.title.weight(.bold))
                    .foregroundStyle(familyColor)
                    .strikethrough(isPelleUseless)

                Text(perk.family.capitalized)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(familyColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))

                // Description — struck through when nullified by Doom so the
                // player sees the bought perk's intended effect with a clear
                // "but it does nothing right now" signal. Mirrors web's
                // `o-pelle-disabled` class.
                Text(perk.description)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .strikethrough(isPelleUseless)

                if perk.automatorPoints > 0 {
                    Text("+\(perk.automatorPoints) Automator Points")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.yellow)
                        .strikethrough(isPelleUseless)
                }

                // Status — explicit "Disabled by Doom" beats the generic
                // "Purchased" badge so the player knows why the perk is
                // not contributing.
                if isPelleUseless {
                    Text("Nullified by Doom")
                        .font(.headline)
                        .foregroundStyle(GameColor.pelle.readableOnDark())
                } else if perk.isBought {
                    Text("Purchased")
                        .font(.headline)
                        .foregroundStyle(.green)
                } else if !perk.canBeBought {
                    Text("Locked — purchase a connected perk first")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Actions
                HStack(spacing: 16) {
                    Button("Cancel") {
                        dismiss()
                        onDismiss()
                    }
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color(white: 0.15), in: RoundedRectangle(cornerRadius: 8))

                    if canPurchase {
                        Button("Purchase (1 PP)") {
                            engine.buyPerk(perk.id)
                            dismiss()
                            onDismiss()
                        }
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(familyColor, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.bottom, 8)

                #if DEBUG
                Button(perk.isBought ? "Unpurchase (debug)" : "Force purchase (debug)") {
                    engine.devTogglePerk(perk.id)
                    dismiss()
                    onDismiss()
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(white: 0.10), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.6), lineWidth: 1))
                .padding(.bottom, 16)
                #else
                Spacer().frame(height: 16)
                #endif
            }
            .padding(.top, 24)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
