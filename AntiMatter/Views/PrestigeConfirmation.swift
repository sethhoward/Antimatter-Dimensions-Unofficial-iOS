//
//  PrestigeConfirmation.swift
//  AntiMatter
//
//  Native confirmation sheets for prestige resets — Dimension Boost,
//  Antimatter Galaxy, Big Crunch, and Dimensional Sacrifice.
//

import SwiftUI

extension PrestigeModal {
    var accentColor: Color {
        switch self {
        case .dimensionBoost: .orange
        case .galaxy: .blue
        case .bigCrunch: .cyan
        case .sacrifice: .orange
        case .replicantiGalaxy: .blue
        case .eternity: GameColor.eternity
        case .normalChallenge: .red
        case .infinityChallenge: GameColor.infinity
        case .eternityChallenge: GameColor.eternity
        case .exitChallenge: .green
        case .enterDilation, .exitDilation: GameColor.dilationGreen
        case .reality: GameColor.reality
        case .resetReality: GameColor.badPink
        case .teresaRun: GameColor.teresa
        case .effarigRun: GameColor.effarig
        case .enslavedRun: GameColor.enslaved
        case .vRun: GameColor.v
        case .raRun: GameColor.ra
        case .laitelaRun: GameColor.laitela
        case .awayProgress: .cyan
        case .glyphPurge, .deleteAllUnprotectedGlyphs, .deleteAllRejectedGlyphs: GameColor.reality
        }
    }
}

struct PrestigeConfirmation: View {
    let modal: PrestigeModal
    let engine: GameEngine
    @Environment(\.sidebarState) private var sidebar
    @State private var dontShowAgain = false

    private var state: GameState { engine.gameState }
    private var isAwayProgress: Bool {
        if case .awayProgress = modal { return true }
        return false
    }

    /// Title override for `.exitDilation` under doom. Mirrors `ExitDilationModal.vue`:
    /// "You cannot exit Dilation while Doomed" replaces the generic "Exit Time Dilation".
    private var resolvedTitle: String {
        if case .exitDilation = modal, engine.pelleDoomed {
            return "You cannot exit Dilation while Doomed"
        }
        return modal.title
    }

    /// Confirm-button label override for `.exitDilation` under doom: "Okay" instead
    /// of "Exit". Web `ExitDilationModal.vue.confirmText` does the same.
    private var resolvedConfirmLabel: String {
        if case .exitDilation = modal, engine.pelleDoomed {
            return "Okay"
        }
        return modal.confirmButtonLabel
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    description
                    gains
                    dontShowToggle
                }
                .padding()
            }
            .adaptiveSheetTitle(resolvedTitle)
            .toolbar {
                if !isAwayProgress {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            engine.cancelPrestige()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(resolvedConfirmLabel) {
                        if dontShowAgain {
                            engine.setConfirmation(modal.confirmationKey, enabled: false)
                        }
                        let wasInEC = engine.gameState.infinity.isInEternityChallenge
                        if modal.navigatesToDimensions {
                            sidebar?.selectSubtab(.antimatterDimensions, in: .dimensions, engine: engine)
                        }
                        engine.confirmPrestige()
                        // After EC eternity, navigate to Time Studies
                        if modal.id == "eternity" && wasInEC {
                            sidebar?.selectSubtab(.timeStudies, in: .eternity, engine: engine)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(modal.accentColor)
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// The challenge info for the pending challenge, if any.
    private var challengeInfo: NormalChallengeInfo? {
        if case .normalChallenge(let id) = modal {
            return state.normalChallenges.challenges.first { $0.id == id }
        }
        return nil
    }

    private var bigCrunchStartingResources: String {
        var parts: [String] = []
        if let am = state.infinity.startingAM { parts.append("\(am) Antimatter") }
        if state.infinity.startingBoosts > 0 {
            let n = state.infinity.startingBoosts
            parts.append("\(n) Dimension \(n == 1 ? "Boost" : "Boosts")")
        }
        if state.infinity.startWithGalaxy { parts.append("1 Galaxy") }
        guard !parts.isEmpty else { return "" }
        if parts.count == 1 { return parts[0] }
        if parts.count == 2 { return "\(parts[0]) and \(parts[1])" }
        return "\(parts.dropLast().joined(separator: ", ")), and \(parts.last!)"
    }

    private var icInfo: InfinityChallengeInfo? {
        if case .infinityChallenge(let id) = modal {
            return state.infinityChallenges.challenges.first { $0.id == id }
        }
        return nil
    }

    private var ecInfo: EternityChallengeInfo? {
        if case .eternityChallenge(let id) = modal {
            return state.eternityChallenges.challenges.first { $0.id == id }
        }
        return nil
    }

    /// Verb for glyph purge/delete confirmation bodies: Refine > Sacrifice > Delete.
    private var glyphVerb: String {
        let g = state.glyphsState
        if g.isRefining { return "Refine" }
        if g.sacrificeUnlocked { return "Sacrifice" }
        return "Delete"
    }

    // MARK: - Description

    @ViewBuilder
    private var description: some View {
        switch modal {
        case .dimensionBoost:
            InfoRow(icon: "arrow.counterclockwise", color: .orange,
                    text: "This will reset your Antimatter and Antimatter Dimensions, but you will gain a multiplier boost to Dimensions 1-4.")

        case .galaxy:
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(icon: "arrow.counterclockwise", color: .blue,
                        text: "This will reset your Antimatter, Antimatter Dimensions, Tickspeed upgrades, and Dimension Boosts.")
                InfoRow(icon: "sparkles", color: .blue,
                        text: "In return, Tickspeed upgrades will become more powerful.")
            }

        case .bigCrunch:
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(icon: "infinity", color: GameColor.infinity,
                        text: "Upon Infinity, all Dimensions, Dimension Boosts, and Antimatter Galaxies are reset.")
                if !engine.infinityUnlocked {
                    InfoRow(icon: "star", color: GameColor.infinity,
                            text: "In return, you gain an Infinity Point (IP). This allows you to buy multiple upgrades that you can find in the Infinity tab.")
                    InfoRow(icon: "chart.line.uptrend.xyaxis", color: GameColor.infinity,
                            text: "You will also gain one Infinity, which is the stat shown in the Statistics tab.")
                }
            }

        case .sacrifice:
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(icon: "flame", color: .orange,
                        text: "Sacrifice all of your 1st through 7th Antimatter Dimensions for a permanent boost to the 8th Antimatter Dimension.")
            }

        case .replicantiGalaxy:
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(icon: "sparkles", color: .blue,
                        text: "A Replicanti Galaxy boosts Tickspeed the same way an Antimatter Galaxy does. However, it does not increase the cost of Antimatter Galaxies.")
                InfoRow(icon: "arrow.counterclockwise", color: .blue,
                        text: "It will \(state.replicanti.galaxyResetText.lowercased()).")
            }

        case .eternity:
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(icon: "arrow.counterclockwise", color: GameColor.eternity,
                        text: "Upon Eternity, everything is reset except Achievements, Challenge completions, and Infinity upgrades.")
                InfoRow(icon: "star", color: GameColor.eternity,
                        text: "In return, you gain Eternity Points (EP) which can be spent on powerful upgrades.")
            }

        case .reality:
            VStack(alignment: .leading, spacing: 12) {
                // Reset warning
                InfoRow(icon: "arrow.counterclockwise", color: GameColor.reality,
                        text: "Reality will reset all Eternity-layer progress (Eternities, EP, Time Studies, Time Dilation, Eternity upgrades).")
            }

        case .resetReality:
            let badPink = GameColor.badPink
            // Web `ResetRealityModal.vue:16` swaps the noun: "Armageddon"
            // when doomed, "Reality" otherwise. Pre-doom unchanged.
            let resetTerm = engine.pelleDoomed ? "Armageddon" : "Reality"
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(icon: "arrow.counterclockwise", color: badPink,
                        text: "This will reset your current \(resetTerm) without gaining any Reality Machines or Glyphs.")
                InfoRow(icon: "exclamationmark.triangle", color: badPink,
                        text: "All Eternity-layer progress will be lost (Eternities, EP, Time Studies, Time Dilation).")
            }

        case .teresaRun:
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(icon: "arrow.counterclockwise", color: GameColor.teresa,
                        text: "Start Teresa's Reality. This performs a Reality reset with Teresa's restrictions.")
                InfoRow(icon: "sparkles", color: GameColor.teresa,
                        text: "Reward: Glyph Sacrifice power increases based on antimatter gained within the run.")
                if state.celestials.teresa.runCompleted {
                    InfoRow(icon: "gift", color: GameColor.teresa,
                            text: "Current reward: Glyph Sacrifice \(state.celestials.teresa.runReward)")
                }
            }

        case .effarigRun:
            let eff = state.celestials.effarig
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(icon: "arrow.counterclockwise", color: GameColor.effarig,
                        text: "Start Effarig's Reality. This performs a Reality reset; Dimension multipliers and Tickspeed are dilated and new Glyph levels are capped.")
                if !eff.runDescription.isEmpty {
                    InfoRow(icon: "hourglass", color: GameColor.effarig, text: eff.runDescription)
                }
                InfoRow(icon: "dot.circle", color: GameColor.effarig,
                        text: "Current stage: \(eff.currentStageName) — new Glyph level cap \(eff.glyphLevelCap).")
                if !eff.isRunning {
                    let unlocked = eff.runUnlocks.filter { $0.isUnlocked }.map { $0.label }.joined(separator: ", ")
                    if !unlocked.isEmpty {
                        InfoRow(icon: "gift", color: GameColor.effarig,
                                text: "Rewards earned so far: \(unlocked).")
                    }
                }
            }

        case .enslavedRun:
            let ens = state.celestials.enslaved
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(icon: "arrow.counterclockwise", color: GameColor.enslaved,
                        text: "Perform a Reality reset and enter The Nameless Ones' Reality.")
                ForEach(Array(ens.runDescription.enumerated()), id: \.offset) { _, line in
                    InfoRow(icon: "hourglass", color: GameColor.enslaved, text: line)
                }
                InfoRow(icon: "gift", color: GameColor.enslaved,
                        text: "Reward: Unlock Tesseracts, which let you increase Infinity Dimension caps.")
                if ens.isCompleted {
                    InfoRow(icon: "checkmark.circle", color: .green,
                            text: "You have already completed this Reality once.")
                }
            }

        case .vRun:
            let v = state.celestials.v
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(icon: "arrow.counterclockwise", color: GameColor.v,
                        text: "Perform a Reality reset and enter V's Reality.")
                if !v.runDescription.isEmpty {
                    InfoRow(icon: "hourglass", color: GameColor.v, text: v.runDescription)
                }
                InfoRow(icon: "star", color: GameColor.v,
                        text: "Complete V-Achievements to earn Space Theorems.")
            }

        case .raRun:
            let r = state.celestials.ra
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(icon: "arrow.counterclockwise", color: GameColor.ra,
                        text: "Perform a Reality reset and enter Ra's Reality.")
                if !r.runDescription.isEmpty {
                    InfoRow(icon: "hourglass", color: GameColor.ra, text: r.runDescription)
                }
                InfoRow(icon: "star.fill", color: GameColor.ra,
                        text: "Earn Memory Chunks for each unlocked pet to level them up and unlock new mechanics.")
            }

        case .laitelaRun:
            let l = state.celestials.laitela
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(icon: "arrow.counterclockwise", color: GameColor.laitela,
                        text: "Perform a Reality reset and enter Lai'tela's Reality.")
                if !l.run.runDescription.isEmpty {
                    InfoRow(icon: "hourglass", color: GameColor.laitela, text: l.run.runDescription)
                }
                if l.run.difficultyTier > 0 {
                    InfoRow(icon: "flame", color: GameColor.laitela,
                            text: "Current destabilization tier: \(l.run.difficultyTier)/8 — max DMD tier available: \(l.run.maxAllowedDimension).")
                    InfoRow(icon: "gift", color: GameColor.laitela,
                            text: "Current reward: \(l.run.realityReward) (fastest completion \(l.run.fastestCompletionText)).")
                } else {
                    InfoRow(icon: "star.fill", color: GameColor.laitela,
                            text: "Complete the Reality to destabilize Lai'tela, unlocking higher Dark Matter Dimensions and reward multipliers.")
                }
            }

        case .normalChallenge:
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(icon: "exclamationmark.triangle", color: .red,
                        text: "Entering a challenge will perform a Big Crunch reset and start a new Infinity with special restrictions.")
                if let info = challengeInfo {
                    InfoRow(icon: "lock.shield", color: .red,
                            text: info.description.prefix(1).uppercased() + info.description.dropFirst())
                }
            }

        case .infinityChallenge:
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(icon: "exclamationmark.triangle", color: GameColor.infinity,
                        text: "Entering an Infinity Challenge will perform a Big Crunch reset with special restrictions.")
                if let info = icInfo {
                    InfoRow(icon: "lock.shield", color: GameColor.infinity,
                            text: info.description.prefix(1).uppercased() + info.description.dropFirst())
                    InfoRow(icon: "target", color: GameColor.infinity,
                            text: "Goal: \(info.goal) antimatter")
                    InfoRow(icon: "gift", color: .yellow,
                            text: "Reward: \(info.reward)")
                }
            }

        case .eternityChallenge:
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(icon: "exclamationmark.triangle", color: GameColor.eternity,
                        text: "Entering an Eternity Challenge will perform an Eternity reset with special restrictions.")
                if let info = ecInfo {
                    InfoRow(icon: "lock.shield", color: GameColor.eternity,
                            text: info.description)
                    InfoRow(icon: "target", color: GameColor.eternity,
                            text: "Goal: \(info.goal) IP")
                    InfoRow(icon: "gift", color: .yellow,
                            text: "Reward: \(info.reward)")
                    if info.completions > 0 {
                        InfoRow(icon: "checkmark.circle", color: .green,
                                text: "Completions: \(info.completions)/\(info.maxCompletions)")
                    }
                }
            }

        case .exitChallenge:
            InfoRow(icon: "arrow.uturn.backward", color: .green,
                    text: "This will place you back into a regular Infinity without any restrictions.")

        case .enterDilation:
            let dilationGreen = GameColor.dilationGreen
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(icon: "arrow.counterclockwise", color: dilationGreen,
                        text: "Dilating time will start a new Eternity, but all Dimension and Tickspeed multiplier exponents will be reduced to ^0.75.")
                InfoRow(icon: "sparkles", color: dilationGreen,
                        text: "If you can Eternity while Dilated, you will gain Tachyon Particles based on your highest antimatter.")
            }

        case .exitDilation(let tpGain):
            // Mirror `ExitDilationModal.vue`: under doom, lead with "Dilation is
            // permanent." plus the gain text, dropping the generic "Exiting
            // Dilation will end your current Eternity." flavor line.
            let dilationGreen = GameColor.dilationGreen
            let doomed = engine.pelleDoomed
            VStack(alignment: .leading, spacing: 8) {
                if doomed {
                    if tpGain != "0" {
                        InfoRow(icon: "lock.fill", color: GameColor.pelle,
                                text: "Dilation is permanent. You will gain \(tpGain) Tachyon Particles and reset your current Eternity.")
                    } else {
                        InfoRow(icon: "lock.fill", color: GameColor.pelle,
                                text: "Dilation is permanent. You will not gain any Tachyon Particles and reset your current Eternity.")
                    }
                } else {
                    InfoRow(icon: "arrow.uturn.backward", color: dilationGreen,
                            text: "Exiting Dilation will end your current Eternity.")
                    if tpGain != "0" {
                        InfoRow(icon: "star", color: dilationGreen,
                                text: "You will gain \(tpGain) Tachyon Particles.")
                    } else {
                        InfoRow(icon: "exclamationmark.triangle", color: .secondary,
                                text: "You will not gain any Tachyon Particles.")
                    }
                }
            }

        case .awayProgress(let data):
            VStack(alignment: .leading, spacing: 10) {
                Text("While you were away for \(data.elapsedTimeDisplay):")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(data.entries) { entry in
                    HStack {
                        Text(entry.label)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(entry.before)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .strikethrough()
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(entry.after)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }

        case .glyphPurge(let harsh, let deleted, let total):
            let explanation = harsh
                ? "Harsh Purging deletes Glyphs that are strictly worse than any other Glyph in your inventory. For example, if a Glyph has all the same effects as another Glyph, but the values of ALL of the effects are worse, then it will be deleted."
                : "Purging deletes Glyphs that are strictly worse than other Glyphs, while keeping enough to equip a full set with those effects. This behaves like Harsh Purge, except that regular Purge will not delete any given Glyph unless it finds five Glyphs which are better (instead of only one)."
            let verbAction = harsh ? "Harsh Purge" : "Purge"
            let verbING = harsh ? "Harsh Purging" : "Purging"
            let extra: String = {
                if deleted == 0 { return "This will Purge no Glyphs." }
                if deleted >= total && total > 0 { return "This will Purge all your Glyphs." }
                return "\(verbING) will delete \(deleted)/\(total) of your Glyphs."
            }()
            VStack(alignment: .leading, spacing: 12) {
                ModalHeadline(text: "You are about to \(verbAction) your Glyphs")
                InfoRow(icon: "exclamationmark.triangle", color: .orange,
                        text: "This could delete Glyphs in your inventory that are good enough that you might want to use them later. Purging will Purge Glyphs based on your Purge mode. Are you sure you want to do this?")
                InfoRow(icon: "info.circle", color: GameColor.reality, text: explanation)
                InfoRow(icon: "trash", color: GameColor.badPink, text: extra)
            }

        case .deleteAllUnprotectedGlyphs(let deleted, let total):
            let verbLower: String = {
                let g = state.glyphsState
                if g.isRefining { return "Refine" }
                if g.sacrificeUnlocked { return "Sacrifice" }
                return "delete"
            }()
            let extra: String = {
                if deleted == 0 { return "This will \(verbLower) no Glyphs." }
                if deleted >= total && total > 0 { return "This will \(verbLower) all your Glyphs." }
                return "This will \(verbLower) \(deleted)/\(total) of your Glyphs."
            }()
            VStack(alignment: .leading, spacing: 12) {
                ModalHeadline(text: "You are about to \(verbLower) all unprotected Glyphs")
                InfoRow(icon: "exclamationmark.triangle", color: .orange,
                        text: "Are you sure you want to \(verbLower) all unprotected Glyphs in your inventory?")
                InfoRow(icon: "trash", color: GameColor.badPink, text: extra)
            }

        case .deleteAllRejectedGlyphs(let deleted, let total):
            let g = state.glyphsState
            let verb = g.isRefining ? "Refine" : "Sacrifice"
            let negativeWarning = g.hasNegativeEffectScore
                ? " Note that some of your Effect Filter scores are negative, which may cause you to lose some Glyphs you normally want to keep."
                : ""
            let extra: String = {
                if deleted == 0 { return "This will remove no Glyphs." }
                if deleted >= total && total > 0 { return "This will remove all your Glyphs." }
                return "This process will remove \(deleted)/\(total) Glyphs."
            }()
            VStack(alignment: .leading, spacing: 12) {
                ModalHeadline(text: "You are about to \(verb) all rejected Glyphs")
                InfoRow(icon: "exclamationmark.triangle", color: .orange,
                        text: "Are you sure you want to \(verb) all rejected Glyphs? This will remove all Glyphs that would be rejected by your current Glyph Filter settings.\(negativeWarning)")
                InfoRow(icon: "trash", color: GameColor.badPink, text: extra)
            }
        }
    }

    // MARK: - Gains

    @ViewBuilder
    private var gains: some View {
        switch modal {
        case .dimensionBoost:
            GainRow(label: "Current Boosts", value: "\(state.dimBoost.purchasedBoosts)")

        case .galaxy:
            GainRow(label: "Current Galaxies", value: "\(state.galaxy.count)")

        case .bigCrunch:
            VStack(alignment: .leading, spacing: 8) {
                Text("You will gain \(state.infinity.gainedInfinities) \(state.infinity.gainedInfinities == "1" ? "Infinity" : "Infinities") and \(state.infinity.gainedIP) Infinity \(state.infinity.gainedIP == "1" ? "Point" : "Points").")
                    .font(.subheadline)

                let resources = bigCrunchStartingResources
                if !resources.isEmpty {
                    Text("You will start your next Infinity with \(resources).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

        case .sacrifice:
            VStack(spacing: 8) {
                if let current = state.sacrificeMultiplier {
                    GainRow(label: "Current multiplier", value: current)
                }
                if let next = state.sacrificeNextBoost {
                    GainRow(label: "Next boost", value: next)
                }
            }

        case .replicantiGalaxy:
            VStack(spacing: 8) {
                GainRow(label: "Current Replicanti Galaxies", value: "\(state.replicanti.galaxiesBought)")
            }

        case .eternity:
            EmptyView()

        case .reality:
            let inf = engine.gameState.infinity
            VStack(spacing: 8) {
                if !inf.gainedRM.isEmpty {
                    GainRow(label: "Machines", value: inf.gainedRM.replacingOccurrences(of: "Machines gained: ", with: ""))
                }
                if !inf.machineStats.isEmpty {
                    GainRow(label: "Rate", value: inf.machineStats)
                }
                if !inf.gainedGlyphLevel.isEmpty {
                    GainRow(label: "Glyph", value: inf.gainedGlyphLevel.replacingOccurrences(of: "Glyph lvl: ", with: "Lvl "))
                }
                if !inf.realityLevelStats.isEmpty {
                    GainRow(label: "vs Best", value: inf.realityLevelStats
                        .replacingOccurrences(of: "You will get a level ", with: "Lvl ")
                        .replacingOccurrences(of: " Glyph on Reality, which is ", with: ", "))
                }
                if !inf.realityPPGained.isEmpty {
                    GainRow(label: "Perk Points", value: inf.realityPPGained)
                }
                if !inf.realityShardsInfo.isEmpty {
                    let lines = inf.realityShardsInfo.components(separatedBy: "\n")
                    GainRow(label: "Relic Shards", value: lines[0])
                    if lines.count > 1 {
                        GainRow(label: "Shard Peak", value: lines[1].replacingOccurrences(of: "Peak: ", with: ""))
                    }
                }
                if !inf.realityCelestialInfo.isEmpty {
                    ForEach(inf.realityCelestialInfo.components(separatedBy: "\n").filter { !$0.isEmpty }, id: \.self) { line in
                        GainRow(label: "Celestial", value: line)
                    }
                }
            }

        case .resetReality:
            EmptyView()

        case .teresaRun:
            EmptyView()

        case .effarigRun:
            EmptyView()

        case .enslavedRun:
            EmptyView()

        case .vRun:
            EmptyView()

        case .raRun:
            EmptyView()

        case .laitelaRun:
            EmptyView()

        case .normalChallenge:
            if let info = challengeInfo {
                VStack(spacing: 8) {
                    GainRow(label: "Challenge", value: "C\(info.id)")
                    GainRow(label: "Reward", value: info.reward)
                }
            }

        case .infinityChallenge:
            if let info = icInfo {
                VStack(spacing: 8) {
                    GainRow(label: "Challenge", value: "IC\(info.id)")
                    GainRow(label: "Goal", value: "\(info.goal) antimatter")
                }
            }

        case .eternityChallenge:
            if let info = ecInfo {
                VStack(spacing: 8) {
                    GainRow(label: "Challenge", value: "EC\(info.id)")
                    GainRow(label: "Goal", value: "\(info.goal) IP")
                    GainRow(label: "Completions", value: "\(info.completions)/\(info.maxCompletions)")
                }
            }

        case .exitChallenge:
            EmptyView()

        case .enterDilation:
            EmptyView()

        case .exitDilation:
            EmptyView()

        case .awayProgress:
            EmptyView()

        case .glyphPurge, .deleteAllUnprotectedGlyphs, .deleteAllRejectedGlyphs:
            EmptyView()
        }
    }

    // MARK: - Don't show toggle

    @ViewBuilder
    private var dontShowToggle: some View {
        if case .awayProgress = modal {
            EmptyView()
        } else {
            Toggle("Don't show this again", isOn: $dontShowAgain)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }

}

// MARK: - Reusable components

private struct ModalHeadline: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InfoRow: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white)
        }
    }
}

private struct GainRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
