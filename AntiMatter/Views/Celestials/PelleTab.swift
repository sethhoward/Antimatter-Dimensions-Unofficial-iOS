//
//  PelleTab.swift
//  AntiMatter
//
//  Pelle, the final celestial — the endgame "Doomed Reality" layer.
//
//  Phase 1 skeleton: renders three branches based on `pelle.isUnlocked` /
//  `pelle.canDoom` / `pelle.isDoomed`. Pre-doom requirement list and the
//  Doom-Your-Reality entry are wired up; post-doom currency header and
//  Armageddon button are visible. The strikes/rifts panel, upgrades shop,
//  and Galaxy Generator are placeholders ("Phase 3", "Phase 4", "Phase 5")
//  and will be filled in by their respective phases.
//
//  Vue references:
//    src/components/tabs/celestial-pelle/PelleTab.vue
//    src/components/tabs/celestial-pelle/PelleUpgradePanel.vue
//    src/components/tabs/celestial-pelle/PelleBarPanel.vue
//    src/components/tabs/celestial-pelle/PelleGalaxyGeneratorPanel.vue
//

import SwiftUI

struct PelleTab: View {
    let engine: GameEngine

    var body: some View {
        PelleTabContent(engine: engine)
    }
}

private struct PelleTabContent: View {
    let engine: GameEngine
    @Environment(\.layoutMetrics) private var metrics

    @State private var showQuoteHistory = false
    @State private var showDoomConfirmation = false
    @State private var showEffectsSheet = false
    /// Mirrors `RemnantGainFactor.vue`'s `ExpandingControlBox` collapsed
    /// state. Persisted in @State only — web stores in `Pelle.cel.collapsed`
    /// but this is purely cosmetic so a session-local toggle is fine.
    @State private var showRemnantBreakdown = false

    private var pelle: PelleState { engine.gameState.celestials.pelle }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !pelle.ready {
                    ProgressView().padding(.top, 40)
                }
                headerSection

                if pelle.isDoomed {
                    doomedView
                } else {
                    // Vue PelleTab.vue branches `canEnterPelle` vs unmet-
                    // requirements. iOS used a third "isUnlocked" branch for
                    // pre-Lai'tela users; that's now folded into the
                    // requirements card since the JS bridge always populates
                    // `preDoomRequirements` (0/N progress for fresh saves).
                    preDoomView
                }

                PhoneTabBarSpacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, metrics.isCompact ? 10 : 16)
        }
        .sheet(isPresented: $showQuoteHistory) {
            CelestialQuoteHistoryView(celestialKey: "pelle", engine: engine)
        }
        .sheet(isPresented: $showDoomConfirmation) {
            DoomConfirmationSheet(engine: engine, isPresented: $showDoomConfirmation)
        }
        .sheet(isPresented: $showEffectsSheet) {
            PelleEffectsSheet(engine: engine, isPresented: $showEffectsSheet)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 6) {
            HStack {
                Spacer()
                Text("Pelle, Celestial of Antimatter")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(GameColor.pelle)
                Spacer()
                Button {
                    engine.loadQuoteHistory(for: "pelle")
                    showQuoteHistory = true
                } label: {
                    Image(systemName: "quote.bubble")
                        .font(.callout)
                        .foregroundStyle(GameColor.pelle)
                        .padding(8)
                        .background(GameColor.pelle.opacity(0.15), in: Circle())
                }
                .buttonStyle(.plain)
            }
            // Pelle's distinctive symbol — ♅ renders fine on iOS without Font Awesome.
            Text("♅")
                .font(.system(size: 36))
                .foregroundStyle(GameColor.pelle.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Pre-doom branch

    private var preDoomView: some View {
        VStack(spacing: 16) {
            requirementsCard
            // Vue PelleTab.vue:82-91 — the "Doom Your Reality" button only
            // appears when all requirements are met (`canEnterPelle`).
            // Before that point, the requirements card stands alone.
            if pelle.canDoom {
                doomButton
            }
        }
    }

    private var requirementsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Vue PelleTab.vue:96-97 — single-sentence unlock requirement
            // message, parameterised by the achievement row total.
            Text("You must have \(achievementRowTotal) rows of Achievements and all of your Glyph Alchemy Resources capped to unlock Pelle, Celestial of Antimatter.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(GameColor.pelle.readableOnDark())
                .fixedSize(horizontal: false, vertical: true)
            Divider().overlay(GameColor.pelle.opacity(0.3))
            ForEach(pelle.preDoomRequirements) { req in
                PelleRequirementRow(req: req)
                    .equatable()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(GameColor.pelle.opacity(0.4), lineWidth: 1)
                )
        )
    }

    /// Pulls the "N" from the bridge's `achievements` progress text
    /// (formatted "X/N"). Falls back to a sensible default if parsing fails.
    private var achievementRowTotal: String {
        if let row = pelle.preDoomRequirements.first(where: { $0.id == "achievements" }),
           let total = row.progressText.split(separator: "/").last {
            return String(total)
        }
        return "all"
    }

    private var doomButton: some View {
        GameButton(theme: .pelle, isEnabled: pelle.canDoom) {
            showDoomConfirmation = true
        } label: {
            VStack(spacing: 4) {
                Text("Doom Your Reality")
                    .font(.title3.weight(.bold))
                Text("End everything you've built. Begin the Pelle endgame.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Doomed branch

    private var doomedView: some View {
        VStack(spacing: 16) {
            // Galaxy Generator (Phase 5) — pinned to the top of the post-doom
            // flow so the "Unlock the Galaxy Generator" button is the first
            // thing the user sees once the recursion-rift milestone is reached.
            // Gated on `panelVisible` (recursion milestone 3 OR galaxies spent).
            if pelle.galaxyGenerator.panelVisible {
                PelleGalaxyGeneratorPanel(engine: engine)
            }
            // Top — currency display + Remnant Gain Factors collapsible.
            currencyCard
            remnantGainFactorsCard
            // Armageddon entry — sits at the top of the post-doom flow next
            // to the currency, matching `PelleUpgradePanel.vue`'s position.
            armageddonCard
            // "Show effects" entry — surfaces the ~35-line PelleEffectsSheet
            // listing every disabled / nerfed mechanic. Mirrors PelleTab.vue
            // header button. Always shown post-doom.
            Button {
                showEffectsSheet = true
            } label: {
                Label("Show Doomed Reality effects", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.medium))
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(GameColor.pelle.opacity(0.18))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(GameColor.pelle.opacity(0.6), lineWidth: 1)
                            )
                    )
                    .foregroundStyle(GameColor.pelle.readableOnDark())
            }
            .buttonStyle(.plain)
            // Strikes & Rifts panel (Phase 3). Always rendered post-doom —
            // the panel itself shows each strike's requirement/penalty/reward
            // text until the strike triggers, then unfolds the rift bar.
            PelleStrikesAndRiftsPanel(engine: engine)
            // Pelle upgrades shop (Phase 4) — 5 rebuyables + 23 one-times.
            PelleUpgradesPanel(engine: engine)
            #if DEBUG
            pelleQuoteDebugRow
            gameEndDebugRow
            #endif
        }
    }

    #if DEBUG
    /// Trigger any Pelle quote on demand. Mirrors web `Pelle.quotes.<name>.show()`
    /// but routes through `_nativeReplayQuote` which calls `Quote.addToQueue`
    /// directly — bypasses the bit-upgrade idempotency so we can verify
    /// every quote reaches the iOS modal pipeline regardless of save state.
    private var pelleQuoteDebugRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DEBUG: Force-fire Pelle quote (regardless of unlock bit)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            // Quote IDs sourced from `secret-formula/celestials/quotes/pelle.js`.
            // Each tuple: (display label, JS quote id).
            let quotes: [(String, Int)] = [
                ("0: initial", 0),
                ("1: arm",     1),
                ("2: strike1", 2),
                ("3: strike2", 3),
                ("4: strike3", 4),
                ("5: strike4", 5),
                ("6: strike5", 6),
                ("7: GG unlock", 7),
                ("8: GG rifts", 8),
                ("9: GG phase1", 9),
                ("10: GG phase4 (hubris)", 10),
                ("11: end", 11),
            ]
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 4)], spacing: 4) {
                ForEach(quotes, id: \.1) { (label, id) in
                    Button(label) {
                        engine.replayQuote(celestialKey: "pelle", quoteId: id)
                    }
                    .font(.caption2.monospacedDigit())
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Skip-to-marker buttons for the GameEnd / credits / zalgo finale.
    /// Lets us walk the endState progression without grinding antimatter.
    private var gameEndDebugRow: some View {
        VStack(spacing: 6) {
            Text("DEBUG: GameEnd jumps  (current endState: \(String(format: "%.2f", engine.endStateValue)))")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Button("0.5 (zalgo)")  { engine.devGameEndJumpTo(0.5) }
                Button("1.5 (fade)")   { engine.devGameEndJumpTo(1.5) }
                Button("2.5 (block)")  { engine.devGameEndJumpTo(2.5) }
                Button("4.5 (credits)") { engine.devGameEndJumpTo(4.5) }
                Button("13.9 (spec)")  { engine.devGameEndJumpTo(13.9) }
                Button("Reset")        { engine.devGameEndReset() }
            }
            .font(.caption2.monospacedDigit())
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
    }
    #endif

    /// Collapsible RemnantGainFactor breakdown — mirrors
    /// `RemnantGainFactor.vue`'s ExpandingControlBox: a tap-to-expand box
    /// listing each input row + final amount. Hidden when the breakdown
    /// data hasn't been computed yet (pre-first-Armageddon).
    @ViewBuilder
    private var remnantGainFactorsCard: some View {
        if !pelle.remnantGainBreakdown.isEmpty {
            VStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showRemnantBreakdown.toggle()
                    }
                } label: {
                    HStack {
                        Image(systemName: showRemnantBreakdown ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.bold))
                        Text("Remnant Gain Factors")
                            .font(.caption.weight(.semibold))
                        Spacer()
                    }
                    .foregroundStyle(GameColor.pelle.readableOnDark())
                    .padding(.vertical, 8).padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                if showRemnantBreakdown {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(pelle.remnantGainBreakdown) { line in
                            HStack(alignment: .firstTextBaseline) {
                                Text(line.label)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(line.isTotal ? GameColor.pelle.readableOnDark() : .white.opacity(0.85))
                                Spacer(minLength: 12)
                                Text(line.value)
                                    .font(.caption2.weight(line.isTotal ? .bold : .regular).monospacedDigit())
                                    .foregroundStyle(line.isTotal ? GameColor.pelle.readableOnDark() : .white)
                            }
                            if line.isTotal {
                                // No-op — the bold styling already
                                // separates the total visually.
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(GameColor.pelle.opacity(0.4), lineWidth: 1)
                    )
            )
        }
    }

    private var currencyCard: some View {
        VStack(spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remnants")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(pelle.remnantsText)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(GameColor.pelle.readableOnDark())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Reality Shards")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(pelle.realityShardsText)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                    Text(pelle.realityShardsPerSecText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(GameColor.pelle.opacity(0.5), lineWidth: 1)
                )
        )
    }

    private var armageddonCard: some View {
        // Label/value pairs — long Decimals get their own line instead of
        // splitting the readout across the leading text and the value.
        GameButton(theme: .pelle, isEnabled: pelle.armageddon.canArmageddon) {
            engine.pelleArmageddon()
        } label: {
            VStack(spacing: 4) {
                Text("Armageddon for")
                    .font(.caption.weight(.semibold))
                Text("\(Text(pelle.armageddon.remnantsGainText).foregroundStyle(GameColor.pelle.readableOnDark()).fontWeight(.bold)) Remnants")
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .multilineTextAlignment(.center)
                Text("Reality Shards / sec")
                    .font(.caption2.weight(.medium))
                    .padding(.top, 2)
                Text("\(Text(pelle.armageddon.realityShardsRateText).foregroundStyle(GameColor.pelle.readableOnDark())) ➔ \(Text(pelle.armageddon.realityShardsRateAfterText).foregroundStyle(GameColor.pelle.readableOnDark()))")
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    // Placeholder panels for phases 3-5. Renders a labeled empty card so the
    // layout is visible end-to-end during scaffolding.
    @ViewBuilder
    private func placeholderPanel(title: String, phase: String) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GameColor.pelle.readableOnDark())
                Spacer()
                Text(phase)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(GameColor.pelle.opacity(0.15), in: Capsule())
            }
            Text("Coming soon.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.25))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(GameColor.pelle.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

// MARK: - Pre-doom requirement row (Equatable)

/// One row in the requirements card. Equatable on `req` so the per-tick
/// parent body doesn't rebuild the row's HStack + Image when nothing
/// visible changed. Achievement / alchemy progress only ticks forward
/// when the player actually unlocks an achievement or caps a resource.
private struct PelleRequirementRow: View, Equatable {
    let req: PelleRequirementInfo

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: req.isMet ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(req.isMet ? GameColor.good : GameColor.pelle.opacity(0.5))
            Text(req.label)
                .font(.caption)
                .foregroundStyle(.white)
            Spacer()
            Text(req.progressText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(req.isMet ? GameColor.good : .white.opacity(0.7))
        }
    }
}

// MARK: - Doom confirmation sheet

private struct DoomConfirmationSheet: View {
    let engine: GameEngine
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Are you absolutely sure?")
                        .font(.headline)
                        .foregroundStyle(GameColor.pelle.readableOnDark())
                    Text("Dooming your Reality is permanent. You will lose all upgrades, glyphs, achievements, and progression that aren't preserved by Pelle Upgrades.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.85))
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Almost every game mechanic gets disabled or nerfed", systemImage: "exclamationmark.triangle.fill")
                        Label("All Glyphs are unequipped — you'll be issued five doomed Glyphs", systemImage: "rays")
                        Label("Infinity Points reset; Big Crunch autobuyer mode resets to AMOUNT", systemImage: "arrow.uturn.backward")
                        Label("This is the endgame layer. There's no going back.", systemImage: "infinity")
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .adaptiveSheetTitle("Doom Your Reality")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { isPresented = false }
                        .tint(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        engine.doomReality()
                        isPresented = false
                    } label: {
                        Text("Doom")
                            .fontWeight(.semibold)
                    }
                    .tint(GameColor.pelle)
                }
            }
        }
    }
}
