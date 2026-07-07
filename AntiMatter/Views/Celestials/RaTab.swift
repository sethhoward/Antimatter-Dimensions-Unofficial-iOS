//
//  RaTab.swift
//  AntiMatter
//
//  Ra (Celestial of Memory). Four pet cards + Remembrance toggle +
//  Ra's Reality run button. Mirrors web RaTab.vue / RaPet.vue / RaPetLevelBar.vue
//  / RaPetRemembranceButton.vue / RaUpgradeIcon.vue. Web hover tooltips are
//  converted to tap-to-reveal sheets.
//

import SwiftUI

struct RaTab: View {
    let engine: GameEngine

    var body: some View {
        RaTabContent(engine: engine)
    }
}

private struct RaTabContent: View {
    let engine: GameEngine
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.sidebarState) private var sidebarState
    @Environment(\.scenePhase) private var scenePhase
    @State private var showHistory = false

    private var state: RaState { engine.gameState.celestials.ra }

    /// True only when Ra is the visible subtab AND the scene is active.
    /// Drives `RaRunButton.isActive` so the running-state scale + glow pulses
    /// tear down off-screen / on backgrounding.
    private var isVisible: Bool {
        sidebarState?.activeSubtab == .ra && scenePhase == .active
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                if !state.isUnlocked {
                    lockedBanner
                } else {
                    runControls
                    productionSummary
                    petGrid
                    if state.showRemembrance {
                        remembranceSection
                    }
                    #if DEBUG
                    debugRow
                    #endif
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showHistory) {
            CelestialQuoteHistoryView(celestialKey: "ra", engine: engine)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 4) {
            HStack {
                Spacer()
                Text("Ra, Celestial of Memory")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(GameColor.ra)
                Spacer()
                Button {
                    engine.loadQuoteHistory(for: "ra")
                    showHistory = true
                } label: {
                    Image(systemName: "quote.bubble")
                        .font(.callout)
                        .foregroundStyle(GameColor.ra)
                        .padding(8)
                        .background(GameColor.ra.opacity(0.15), in: Circle())
                }
                .buttonStyle(.plain)
            }
            Text("Total Pet Levels: \(state.totalPetLevel) / \(state.maxTotalPetLevel)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var lockedBanner: some View {
        VStack(spacing: 8) {
            Text("Ra is not yet unlocked.")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Reach 36 Space Theorems inside V to unlock Ra's Memories.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(GameColor.ra.opacity(0.4), lineWidth: 1))
    }

    // MARK: - Run controls

    private var runControls: some View {
        // Animated sun sigil — pulses scale (0.6s) + glow (3s) when inside
        // Ra's Reality, matching the web's c-ra-run-button__icon CSS. See
        // `RaRunButton.swift` for the keyframe parity.
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                RaRunButton(
                    isRunning: state.isRunning && !engine.pelleDoomed,
                    isActive: isVisible,
                    isEnabled: state.canStartRun && !engine.pelleDoomed
                ) {
                    engine.requestRaRun()
                }
            }

            // Run description lines (Vue RaTab.vue:154-158 splits on "\n").
            if !state.runDescription.isEmpty {
                let lines = state.runDescription
                    .split(separator: "\n")
                    .map { String($0).trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                VStack(spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .strikethrough(engine.pelleDoomed)
                    }
                }
            }

            // Web RaTab.vue:79-82 `memoryDescription`.
            Text("Within Ra's Reality, Memory Chunks for Celestial Memories will be generated based on certain resource amounts.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// True when total pet levels have reached the max (100). Vue
    /// `RaTab.vue:88` — at this point Memory generation is fully retired.
    private var isRaCapped: Bool {
        state.totalPetLevel >= state.maxTotalPetLevel && state.maxTotalPetLevel > 0
    }

    /// Best-effort guard against the legacy "undefined" suffix on boost list.
    private var hasRealBoostList: Bool {
        !state.memoryBoostResources.isEmpty
            && !state.memoryBoostResources.localizedCaseInsensitiveContains("undefined")
    }

    @ViewBuilder
    private var productionSummary: some View {
        // Web RaTab.vue:113-126 — three-line block, post-cap is a single line.
        if isRaCapped {
            Text("All Memories have been returned.")
                .font(.caption)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        } else {
            VStack(spacing: 4) {
                // "Each Memory Chunk generates a base of one Memory per second"
                // is always shown; only the "which has been increased to X"
                // tail appends when productionPerMemoryChunk > 1.
                let hasBoost = hasRealBoostList
                let chunkLine = hasBoost
                    ? "Each Memory Chunk generates a base of one Memory per second, which has been increased to \(state.memoriesPerChunk) Memories per second."
                    : "Each Memory Chunk generates a base of one Memory per second."
                Text(chunkLine)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .strikethrough(engine.pelleDoomed)

                Text("Storing real time prevents Memory Chunk generation, but Memories will still be gained normally.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if hasBoost {
                    Text("This is being increased due to \(state.memoryBoostResources).")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Pet grid

    /// Only render unlocked pets — matches web `v-if="isUnlocked"` on each card.
    /// Locked pets are never drawn; their unlock path is surfaced via the
    /// level-bar tooltip on the preceding pet plus the nav-map spoke.
    private var visiblePets: [RaPetInfo] { state.pets.filter { $0.isUnlocked } }

    private var petGrid: some View {
        Group {
            if metrics.isCompact {
                VStack(spacing: 12) {
                    ForEach(visiblePets) { pet in
                        RaPetCard(engine: engine, pet: pet)
                            .equatable()
                    }
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(visiblePets) { pet in
                        RaPetCard(engine: engine, pet: pet)
                            .equatable()
                    }
                }
            }
        }
    }

    // MARK: - Remembrance section

    /// Matches web `c-ra-remembrance-unlock`. Rendered when Effarig's memory
    /// pet is unlocked. Pre-20-total-levels shows a "need X more" progress
    /// line; post-unlock shows the pet picker buttons.
    @ViewBuilder private var remembranceSection: some View {
        VStack(spacing: 8) {
            Text("Remembrance")
                .font(.headline)
                .foregroundStyle(GameColor.ra)
            Text("Whichever Celestial has Remembrance gains \(formatX(state.remembranceMult)) Memory Chunk gain. The others gain \(formatX(state.remembranceNerf)) Memory Chunk gain.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if state.remembranceUnlocked {
                // Web RaPetRemembranceButton.vue: button label varies on
                // whether this pet currently holds Remembrance.
                VStack(spacing: 6) {
                    ForEach(visiblePets) { pet in
                        Button {
                            Haptics.tap()
                            engine.raSelectRemembrance(pet.key)
                        } label: {
                            Text(pet.hasRemembrance
                                 ? "Remembrance given to \(pet.displayName)"
                                 : "Give Remembrance to \(pet.displayName)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(pet.hasRemembrance ? .black : Color(hex: pet.colorHex))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    pet.hasRemembrance
                                        ? Color(hex: pet.colorHex)
                                        : Color.black.opacity(0.4),
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(hex: pet.colorHex), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                let needed = max(0, state.remembranceRequiredLevel - state.totalPetLevel)
                Text("Unlocked by getting \(state.remembranceRequiredLevel) total Celestial Memory levels (need \(needed) more).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(GameColor.ra.opacity(0.4), lineWidth: 1))
    }

    /// "×2.00" style — the web uses formatX(mult, 1, 1) / formatX(nerf, 1, 1).
    private func formatX(_ v: Double) -> String {
        let whole = floor(v)
        if abs(v - whole) < 0.001 { return String(format: "×%.0f", v) }
        return String(format: "×%.1f", v)
    }

    #if DEBUG
    private var debugRow: some View {
        VStack(spacing: 6) {
            Text("DEBUG")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(state.pets) { pet in
                    Button("Max \(pet.displayName)") {
                        engine.devMaxRaPet(pet.key)
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                }
            }
        }
    }
    #endif
}

// MARK: - Pet card

private struct RaPetCard: View, Equatable {
    let engine: GameEngine
    let pet: RaPetInfo

    @State private var tappedUnlock: RaUnlockInfo? = nil

    static func == (lhs: RaPetCard, rhs: RaPetCard) -> Bool {
        lhs.pet == rhs.pet
        // engine excluded (identity-stable). @State tappedUnlock is internal
        // to SwiftUI's storage layer and not compared by Equatable.
    }

    private var accent: Color { Color(hex: pet.colorHex) }

    var body: some View {
        VStack(spacing: 8) {
            petHeader
            if !pet.scalingUpgradeText.isEmpty {
                Text(pet.scalingUpgradeText)
                    .font(.caption2)
                    .foregroundStyle(accent)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            productionStats
            // Three action tiles replace the old button+bar split. Each tile:
            //   • fills with accent color showing memories/cost progress
            //   • surfaces all the web hover-tooltip info inline (title,
            //     effect, cost, time-to-afford, current multiplier)
            //   • tapping buys directly — no modal.
            upgradeTile(
                title: "\(pet.displayName)'s Recollection",
                effect: pet.memoryUpgrade.effectDescription,
                upgrade: pet.memoryUpgrade,
                systemIcon: "brain",
                action: { engine.raBuyMemoryUpgrade(pet.key) }
            )
            upgradeTile(
                title: "\(pet.displayName)'s Fragmentation",
                effect: pet.chunkUpgrade.effectDescription,
                upgrade: pet.chunkUpgrade,
                systemIcon: "cube",
                action: { engine.raBuyChunkUpgrade(pet.key) }
            )
            levelTile
            if !pet.unlocks.isEmpty {
                unlockRow
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(accent.opacity(pet.hasRemembrance ? 1 : 0.5), lineWidth: pet.hasRemembrance ? 2 : 1)
        )
        .sheet(item: $tappedUnlock) { u in
            RaUnlockDetailSheet(unlock: u, petName: pet.displayName, accent: accent)
                .presentationDetents([.medium])
        }
    }

    private var petHeader: some View {
        HStack {
            Text(pet.displayName)
                .font(.headline)
                .foregroundStyle(accent)
            Spacer()
            if pet.isCapped {
                Text("Max")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(accent, in: Capsule())
            } else {
                Text("Lv \(pet.level)/25")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
            }
        }
    }

    private var productionStats: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Memories: \(pet.memories)")
                .font(.caption)
                .foregroundStyle(.white)
            // `pet.memoriesPerSecond` is already formatted with a "/s"
            // suffix JS-side (celestial-helpers.js — `format(mps, 2) + "/s"`).
            // Don't append another or the line reads "+X/s / s — from …".
            Text("+\(pet.memoriesPerSecond) — from \(pet.memoryGainResource)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Chunks: \(pet.memoryChunks) (+\(pet.chunksPerSecond)) — from \(pet.chunkGainResource)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            // Web RaPet.vue:265-270 — "Multiplying all Memory production by N"
            // when memoryMultiplier > 1.
            if pet.memoryMultiplier > 1 && !pet.memoryMultiplierText.isEmpty {
                Text("Multiplying all Memory production by ×\(pet.memoryMultiplierText)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Self-filling action tile: background fills with the pet's accent color
    /// as `memories / cost` approaches 1. Content mirrors the web hover tooltip
    /// (title, effect, cost + time-to-afford, current multiplier). Tapping
    /// buys immediately when affordable; taps on unaffordable / capped tiles
    /// are ignored.
    private func upgradeTile(
        title: String,
        effect: String,
        upgrade: RaPetUpgradeInfo,
        systemIcon: String,
        action: @escaping () -> Void
    ) -> some View {
        let fraction: Double = {
            if upgrade.isCapped { return 1 }
            guard upgrade.costRaw > 0 else { return 0 }
            return min(1, pet.memoriesRaw / upgrade.costRaw)
        }()
        let enabled = upgrade.canAfford && !upgrade.isCapped

        return Button(action: action) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Unfilled base
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.35))
                    // Progress fill (memories / cost). Dimmer when capped so
                    // the "Capped" text stays legible.
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accent.opacity(upgrade.isCapped ? 0.35 : 0.55))
                        .frame(width: geo.size.width * fraction)
                    // Content on top
                    HStack(spacing: 10) {
                        Image(systemName: systemIcon)
                            .font(.title3)
                            .foregroundStyle(enabled ? accent : .white.opacity(0.7))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                            if upgrade.isCapped {
                                Text("Capped: \(upgrade.currentMult)")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.9))
                            } else {
                                Text(effect)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.85))
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    Text("Cost: \(upgrade.cost)")
                                        .font(.caption2)
                                        .foregroundStyle(.white)
                                    if !upgrade.timeToAfford.isEmpty {
                                        Text(upgrade.timeToAfford)
                                            .font(.caption2)
                                            .foregroundStyle(.white.opacity(0.75))
                                    }
                                }
                                Text("Currently: \(upgrade.currentMult)")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                }
            }
            .frame(height: 68)
            // Clip the progress fill so it can't spill past the tile's
            // rounded corners / into the next row below.
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(accent.opacity(enabled ? 1 : 0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .allowsHitTesting(enabled)
    }

    /// Level-up tile. Same self-filling treatment as the upgrade tiles.
    /// Tap levels up when memories >= required. Surfaces the next unlock
    /// reward inline instead of behind a sheet.
    private var levelTile: some View {
        let fraction = pet.progressToNextLevel
        let enabled = pet.canLevelUp

        return Button {
            if enabled { Haptics.tap() }
            engine.raLevelUp(pet.key)
        } label: {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.35))
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accent.opacity(0.55))
                        .frame(width: geo.size.width * fraction)
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(enabled ? accent : .white.opacity(0.7))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pet.isCapped
                                 ? "Maxed"
                                 : "Level \(pet.displayName) to \(pet.level + 1)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                            if !pet.isCapped {
                                HStack(spacing: 6) {
                                    Text("\(pet.memories) / \(pet.requiredMemories)")
                                        .font(.caption2)
                                        .foregroundStyle(.white)
                                    if !pet.timeToNextLevel.isEmpty {
                                        Text(pet.timeToNextLevel)
                                            .font(.caption2)
                                            .foregroundStyle(.white.opacity(0.75))
                                    }
                                }
                                if !pet.nextUnlockText.isEmpty {
                                    Text(pet.nextUnlockText)
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.85))
                                        .lineLimit(2)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
            }
            .frame(height: pet.nextUnlockText.isEmpty ? 48 : 72)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(accent.opacity(enabled ? 1 : 0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .allowsHitTesting(enabled)
    }

    private var unlockRow: some View {
        HStack(spacing: 6) {
            ForEach(pet.unlocks) { u in
                Button { tappedUnlock = u } label: {
                    RaUnlockIcon(unlock: u, accent: accent)
                        .equatable()
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Unlock icon

private struct RaUnlockIcon: View, Equatable {
    let unlock: RaUnlockInfo
    let accent: Color

    static func == (lhs: RaUnlockIcon, rhs: RaUnlockIcon) -> Bool {
        lhs.unlock == rhs.unlock && lhs.accent.description == rhs.accent.description
    }

    /// Web `RaUpgradeIcon.vue:35` swaps `displayIcon` to a ban glyph and applies
    /// `o-pelle-disabled` when `unlock.disabledByPelle` (driven by the runtime
    /// getter `Pelle.isDoomed && config.disabledByPelle`). Mirror that here.
    private var isDoomDisabled: Bool { unlock.disabledByPelle }

    var body: some View {
        ZStack {
            Circle()
                .fill(fillColor)
            Circle()
                .stroke(strokeColor, lineWidth: 1.5)
            icon
                .foregroundStyle(iconColor)
        }
        .frame(width: 40, height: 40)
    }

    private var fillColor: Color {
        if isDoomDisabled { return GameColor.lockedBgRed.opacity(0.5) }
        return unlock.isUnlocked ? accent.opacity(0.7) : Color.black.opacity(0.4)
    }

    private var strokeColor: Color {
        if isDoomDisabled { return GameColor.pelle }
        return accent.opacity(unlock.isUnlocked ? 1 : 0.5)
    }

    private var iconColor: Color {
        if isDoomDisabled { return GameColor.pelle.readableOnDark() }
        return unlock.isUnlocked ? .black : accent.opacity(0.8)
    }

    @ViewBuilder private var icon: some View {
        // When disabled-by-Pelle, replace whatever icon the unlock would
        // normally show with the ban symbol — matches web's swap to
        // `<span class="fas fa-ban"></span>` (`ra.js:30`). SF Symbol
        // `nosign` is the closest visual equivalent we ship.
        if isDoomDisabled {
            Image(systemName: "nosign")
                .font(.title3)
        } else {
            let token = unlock.iconToken
            if token.hasPrefix("sf:") {
                Image(systemName: String(token.dropFirst(3)))
                    .font(.title3)
            } else if token.hasPrefix("unicode:") {
                Text(String(token.dropFirst(8)))
                    .font(.title3)
            } else {
                Text("\(unlock.level)")
                    .font(.subheadline.weight(.bold))
            }
        }
    }
}

// MARK: - Unlock detail sheet

private struct RaUnlockDetailSheet: View {
    let unlock: RaUnlockInfo
    let petName: String
    let accent: Color
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RaUnlockIcon(unlock: unlock, accent: accent)
                    VStack(alignment: .leading) {
                        Text("\(petName) — Level \(unlock.level)")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(accent)
                        Text(unlock.isUnlocked ? "Unlocked" : "Locked")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
                Text(unlock.reward.isEmpty ? "No description available." : unlock.reward)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if unlock.disabledByPelle {
                    Text("Disabled by Pelle.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Close") { dismiss() }
                    .frame(maxWidth: .infinity)
            }
            .padding()
            .adaptiveSheetTitle("Ra Milestone")
        }
    }
}
