//
//  CompactHeaderView.swift
//  AntiMatter
//
//  Single-column header for iPhone. Prestige buttons share a row (side-by-side)
//  above the antimatter counter, full-width when only one is visible.
//

import SwiftUI

/// Single source of truth for compact-header row heights. `pinnedHeight(...)`
/// and the individual leaf views' `.frame(height:)` calls both reference these
/// constants so a change to one is mechanically reflected in the other. See
/// the design notes → "Compact header sizing invariants" for the full contract.
///
/// Order matches the visual top-to-bottom layout of the header so reading the
/// formula reads like reading the body. Comments cite the leaf the constant
/// governs; CATextLayer-backed leaves (`CompactRMDisplay`, `CompactGameSpeedLabel`,
/// `CompactChallengeLabel` sub-rows) deliberately do NOT pin their frames to
/// these values — they use intrinsic sizing so Dynamic Type still works — but
/// the constant must remain ≥ their measured intrinsic height in every state.
enum CompactRowHeight {
    /// `CompactPrestigeRow.frame(height:)` — fixed envelope so every prestige
    /// button variant (Reality, Eternity, Crunch, UnlockID, Armageddon) lands
    /// at the same size regardless of inner line count.
    static let prestige: CGFloat = 80
    /// `CompactAntimatterDisplay.compactHeight` — default 3-line layout
    /// (amount + AM/sec + tickspeed).
    static let antimatterFull: CGFloat = 62
    /// `CompactAntimatterDisplay.compactHeight` — stripped to amount-only once
    /// the Reality button shows (web `HeaderCenterContainer` strips AM/sec +
    /// `HeaderTickspeedInfo` at the same threshold).
    static let antimatterPostReality: CGFloat = 24
    /// `CompactRMDisplay` / `CompactRealityShardsDisplay` — single line of
    /// 10pt monospaced text.
    static let rmLine: CGFloat = 12
    /// `CompactChallengeLabel.mainLine` — text-only banner used during
    /// Pelle's Doomed Reality (no Exit button).
    static let challengeBannerNoExit: CGFloat = 16
    /// `CompactChallengeLabel.mainLine` + Exit button — challenge active or
    /// celestial Reality.
    static let challengeBannerWithExit: CGFloat = 28
    /// `CompactChallengeLabel` sub-row — challenge power text
    /// ("Production: X%" / "First Dimension: Xx").
    static let challengePowerLine: CGFloat = 14
    /// `CompactGameSpeedLabel` — "The game is running…" line.
    static let gameSpeedLine: CGFloat = 12
    /// `CompactBlackHoleRow` — full envelope (30pt button height + 2pt
    /// internal padding). Leaf clamps to `.frame(maxHeight: bhRow)` so the
    /// 2pt is part of the constant, not a stray `.padding` modifier.
    static let bhRow: CGFloat = 32
    /// `SpeedrunStatusView(layout: .compact)` — single-line row: 12pt
    /// monospaced timer + 12pt milestone label, 1pt vertical padding each
    /// side.
    static let speedrunStatus: CGFloat = 16
    /// `VStack(spacing: 0).padding(.bottom, 3)` — the only outer padding on
    /// the header body. No other implicit buffers.
    static let outerPaddingBottom: CGFloat = 3
}

struct CompactHeaderView: View {
    let engine: GameEngine

    /// Dynamic height based on which persistent header elements are visible.
    /// `bannerHasExit` distinguishes the banner-with-Exit-button height (28pt)
    /// from the text-only banner used during Pelle's permanent Doomed Reality
    /// (16pt). Rapid banner enter/exit jitter is absorbed by the asymmetric
    /// shrink-debounce in `PhoneShell.compactHeaderHeight`'s `onChange`
    /// handler, NOT by reserving an "always-present" banner slot — see
    /// the design notes → "Compact header sizing invariants" for the contract.
    ///
    /// The hard invariant: for every reachable game state, the return value
    /// must be ≥ the actual rendered VStack height. The DEBUG overlay
    /// (enable in Debug tab → "Show compact header height overlay") plots
    /// `Reserved / Stable / Actual` so any drift is immediately visible.
    static func pinnedHeight(bhVisible: Bool, hasChallenge: Bool, bannerHasExit: Bool,
                             hasChallengePower: Bool = false,
                             hasGameSpeed: Bool,
                             hasRM: Bool, prestigeRateMode: Bool,
                             hasBroken: Bool = true,
                             postRealityStudy: Bool = false,
                             hasSpeedrun: Bool = false,
                             showPreBreakCrunch: Bool = false) -> CGFloat {
        var h: CGFloat = CompactRowHeight.prestige
                       + CompactRowHeight.antimatterFull
                       + CompactRowHeight.outerPaddingBottom
        // Pre-Break-Infinity, the header has no prestige button to host:
        // the post-break Crunch button needs `player.break`, the Eternity
        // button needs Eternity unlocked (which requires Break first), and
        // the Reality button needs the Reality study. Pre-break, the
        // pre-Break Crunch UI is rendered by BigCrunchTakeover as a full
        // content overlay — never inside the header. Reclaim the prestige
        // slot until the player breaks Infinity.
        //
        // `player.break` resets on Reality, so once the player has reached
        // Reality (`postRealityStudy` is monotonic via `realityReached`),
        // the Reality button is always rendered into the prestige row even
        // when `hasBroken` is false — keep the prestige allocation in that
        // case.
        // iPhone hosts a Big Crunch button in the prestige row after the
        // player's first crunch (pre-break). Keep the 80pt slot reserved
        // in that window even though `hasBroken` is still false.
        if !hasBroken && !postRealityStudy && !showPreBreakCrunch {
            h -= CompactRowHeight.prestige
        }
        // Rate-mode prestige buttons render their content in 3 visual
        // lines, which fits the base 80pt slot — see the Crunch + Eternity
        // renderer call sites for the line layouts.
        _ = prestigeRateMode
        // Web HeaderCenterContainer strips AM/sec + HeaderTickspeedInfo once
        // the Reality button shows — antimatter block shrinks from full to
        // post-Reality (the delta = the two stripped lines).
        if postRealityStudy { h -= (CompactRowHeight.antimatterFull - CompactRowHeight.antimatterPostReality) }
        if hasRM { h += CompactRowHeight.rmLine }
        if hasChallenge {
            h += bannerHasExit ? CompactRowHeight.challengeBannerWithExit
                               : CompactRowHeight.challengeBannerNoExit
        }
        if hasChallengePower { h += CompactRowHeight.challengePowerLine }
        if hasGameSpeed { h += CompactRowHeight.gameSpeedLine }
        if bhVisible { h += CompactRowHeight.bhRow }
        // Speedrun status: 2-line subtitle (timer + last-milestone label).
        // Hidden entirely when no run is active — no slot reserved.
        if hasSpeedrun { h += CompactRowHeight.speedrunStatus }
        return h
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Prestige buttons row — extracted into its own View so the
                // parent body doesn't read `engine.gameState.infinity`. That
                // struct is reassigned every tick (dimension amounts change),
                // so reads from this body would invalidate the entire header
                // every poll.
                CompactPrestigeRow(engine: engine)

                // Antimatter display — isolated subview to prevent prestige row re-eval on tick
                CompactAntimatterDisplay(engine: engine)

                // Reality Machines currency (post-Reality) — swapped for the
                // Reality Shards readout when Doomed, matching the web header.
                if engine.pelleDoomed {
                    CompactRealityShardsDisplay(engine: engine)
                } else if engine.realityUnlocked {
                    CompactRMDisplay(engine: engine)
                }

                // Challenge / celestial-reality banner centered below antimatter.
                // Gated on `compactBannerVisible` (stable bool, only flips on
                // transition) so the banner's text updates don't redraw the
                // parent body.
                if engine.compactBannerVisible {
                    CompactChallengeLabel(engine: engine)
                }

                // Game speed text — gated on `compactGameSpeedVisible` (stable
                // bool) so per-tick speed text updates land in the leaf, not
                // the parent body.
                if engine.compactGameSpeedVisible {
                    CompactGameSpeedLabel(engine: engine)
                }

                // Black Hole status — only when BH unlocked. Now contains just
                // the BH controls (game speed line moved out above).
                if engine.blackHolesHeaderVisible {
                    CompactBlackHoleRow(engine: engine)
                }

                // Speedrun status subtitle — only when a speedrun is
                // active. Pre-start shows frozen 00:00:00; clock auto-
                // ticks on first purchase. Height reserved via
                // `hasSpeedrun` in `pinnedHeight`.
                if engine.speedrunQuick.isActive {
                    SpeedrunStatusView(engine: engine, layout: .compact)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, CompactRowHeight.outerPaddingBottom)
            .padding(.horizontal, 4)
            #if DEBUG
            // Measure actual rendered content height for the DEBUG overlay.
            // PreferenceKey only fires when the measured height changes, so
            // this is free on stable ticks. Engine field is updated via
            // onPreferenceChange and surfaced by PhoneShell's overlay.
            .background(GeometryReader { geom in
                Color.clear.preference(
                    key: CompactHeaderActualHeightKey.self,
                    value: geom.size.height
                )
            })
            .onPreferenceChange(CompactHeaderActualHeightKey.self) { newValue in
                if engine.compactHeaderActualHeight != newValue {
                    engine.compactHeaderActualHeight = newValue
                }
            }
            #endif
        }
    }
}

#if DEBUG
/// Reports the rendered height of `CompactHeaderView`'s inner VStack so the
/// Debug-tab overlay can compare against `pinnedHeight(...)`. Reduces via
/// `max` so any nested GeometryReader can only ever inflate, never shrink,
/// the measurement.
struct CompactHeaderActualHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
#endif

// MARK: - Compact prestige row (isolates `gameState.infinity` reads)

/// Owns every read of `engine.gameState.infinity` (`inf`) for the header's
/// prestige button row. Extracted so the parent `CompactHeaderView` body
/// doesn't depend on `gameState` — reading any field of that giant
/// `Equatable` struct invalidates the reader every tick (dimension amounts
/// change every poll, so the whole struct is reassigned), and the prestige
/// row was the only reason the parent body had a `gameState` dependency.
private struct CompactPrestigeRow: View {
    let engine: GameEngine
    @Environment(\.sidebarState) private var sidebar

    private var inf: InfinityState { engine.gameState.infinity }

    private let colorInfinity = GameColor.infinity
    private let colorEternity = GameColor.eternity
    private let colorDilation = GameColor.dilationGreen

    var body: some View {
        let showEternity = inf.showEternityButton || (inf.isDilationActive && inf.showEternityButton)
        let showCrunch = inf.isBroken
        let showReality = inf.showRealityButton
        let showUnlockID = inf.isBroken && inf.nextIDVisible && !inf.isInEternityChallenge
        // Post-first-crunch, pre-break: iPhone hosts a Big Crunch button in
        // the header instead of re-firing `BigCrunchTakeover` on every
        // canCrunch tick. The takeover still shows for the very first
        // crunch (`!infinityUnlocked`) — see
        // `InfinityState.showBigCrunchTakeoverFirstOnly` for the gate.
        // Sticky on `infinityUnlocked && !isBroken` — does NOT depend on
        // `canCrunch`, matching `engine.compactShowPreBreakCrunch`. The
        // CompactCrunchButton renders "Reach <goal>" when canCrunch is
        // false, same as the post-break crunch button. Keeping the slot
        // reservation sticky avoids 80pt header height oscillation during
        // automator-driven crunch cycling.
        let showPreBreakCrunch = !inf.isBroken && inf.infinityUnlocked
        let anyVisible = showEternity || showCrunch || showReality || showUnlockID || showPreBreakCrunch

        // Render the prestige row whenever a button is currently visible,
        // OR once `player.break` is true. Pre-break the takeover used to
        // own the entire content area, so the header had nothing to host
        // — `showPreBreakCrunch` is the post-first-crunch path that
        // keeps the row alive without flipping `isBroken`.
        if anyVisible || inf.isBroken {
            HStack(spacing: 2) {
                if showEternity {
                    CompactEternityButton(inf: inf, engine: engine).equatable()
                }
                if showUnlockID {
                    CompactUnlockIDButton(
                        canUnlock: inf.nextIDCanUnlock,
                        hasIPUnlock: inf.nextIDHasIPUnlock,
                        ipRequirement: inf.nextIDIPRequirement,
                        amRequirement: inf.nextIDAmRequirement,
                        engine: engine
                    ).equatable()
                }
                if engine.pelleDoomed {
                    // Replace Reality button with Armageddon header variant.
                    CompactArmageddonButton(engine: engine)
                } else if showReality {
                    CompactRealityButton(
                        inf: inf,
                        realityButtonSpecial: engine.realityButtonSpecial,
                        engine: engine
                    ).equatable()
                }
                if showCrunch || showPreBreakCrunch {
                    CompactCrunchButton(
                        inf: inf,
                        tessGlow: engine.tesseractAffordable && engine.enslavedCompleted,
                        engine: engine
                    ).equatable()
                }
            }
            .frame(height: CompactRowHeight.prestige)
            .opacity(anyVisible || engine.pelleDoomed ? 1 : 0)
        }
    }

    // MARK: - Compact Armageddon header button (Pelle doomed)

    // Armageddon + UnlockID buttons are extracted into top-level structs
    // (`CompactArmageddonButton`, `CompactUnlockIDButton`). Both confine
    // their state reads to themselves so this row's body doesn't re-eval
    // when the buttons' inputs change. UnlockID conforms to `Equatable`
    // and is wrapped in `.equatable()` so SwiftUI skips its body when its
    // primitive params are unchanged — its requirement/threshold strings
    // are stable except at the moment the player crosses thresholds, so
    // the skip pays off most ticks.

    // Reality / Eternity / Crunch buttons live as separate Equatable structs
    // below — see `CompactRealityButton`, `CompactEternityButton`,
    // `CompactCrunchButton`. The renderer-backed buttons read many `inf.*`
    // fields that update per tick, so Equatable will most often return false
    // (gameState reassignment implies at least one input differs). The
    // experiment is whether structural extraction + Equatable still buys us
    // *some* skipped ticks — when format strings happen to round to the same
    // text two ticks in a row, the synthesized `==` returns true.
}

// MARK: - Compact renderer-backed buttons (Equatable experiment)

/// Equatable on full `InfinityState` + the engine flag that drives the
/// pulsing-glow halo. Synthesized field-by-field equality on `InfinityState`
/// returns true only when every field — including the per-tick rate text —
/// happens to match the previous tick. Body skips on those ticks; for every
/// other tick the renderer's `update()` runs and the CATextLayer change
/// detection inside gates actual GPU work.
private struct CompactRealityButton: View, Equatable {
    let inf: InfinityState
    let realityButtonSpecial: Bool
    let engine: GameEngine
    @Environment(\.sidebarState) private var sidebar

    /// Compare only the `inf` fields the renderer + button styling actually
    /// read. Full-struct equality fails too often because unrelated fields
    /// (gainedIP, gainedEP, etc.) trip it. See `CompactRealityLabelRenderer`
    /// for the field set.
    static func == (lhs: Self, rhs: Self) -> Bool {
        if lhs.realityButtonSpecial != rhs.realityButtonSpecial { return false }
        let l = lhs.inf, r = rhs.inf
        return l.canReality == r.canReality
            && l.hasRealityStudy == r.hasRealityStudy
            && l.hasEnoughEPForReality == r.hasEnoughEPForReality
            && l.gainedRM == r.gainedRM
            && l.machineStats == r.machineStats
            && l.gainedGlyphLevel == r.gainedGlyphLevel
    }

    var body: some View {
        let canReality = inf.canReality
        let hasStudy = inf.hasRealityStudy
        let needsStudy = !hasStudy && inf.hasEnoughEPForReality
        Button {
            if needsStudy {
                Haptics.tap()
                sidebar?.selectSubtab(.timeStudies, in: .eternity, engine: engine)
            } else if canReality {
                Haptics.tap()
                engine.requestReality()
            }
        } label: {
            CompactRealityLabelRenderer(inf: inf, needsStudy: needsStudy, color: GameColor.reality)
                .padding(.horizontal, 2)
                .padding(.vertical, 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(GameColor.reality, lineWidth: 1.5)
                )
                .opacity((canReality || needsStudy) ? 1.0 : 0.6)
                .modifier(CompactRealityButtonGlow(active: canReality && realityButtonSpecial))
        }
        .buttonStyle(.plain)
        .allowsHitTesting(canReality || needsStudy)
    }
}

private struct CompactEternityButton: View, Equatable {
    let inf: InfinityState
    let engine: GameEngine

    /// Compare only the `inf` fields used by the renderer + button styling.
    /// Field set mirrors `CompactEternityLabelRenderer.updateUIView`.
    static func == (lhs: Self, rhs: Self) -> Bool {
        let l = lhs.inf, r = rhs.inf
        return l.canEternity == r.canEternity
            && l.isInEternityChallenge == r.isInEternityChallenge
            && l.eternityUnlocked == r.eternityUnlocked
            && l.isDilationActive == r.isDilationActive
            && l.eternityGoal == r.eternityGoal
            && l.dilationTachyonGain == r.dilationTachyonGain
            && l.showEPRate == r.showEPRate
            && l.gainedEP == r.gainedEP
            && l.currentEPRate == r.currentEPRate
            && l.peakEPRate == r.peakEPRate
            && l.peakEPRateVal == r.peakEPRateVal
            && l.ecFullyCompleted == r.ecFullyCompleted
            && l.ecHasMoreCompletions == r.ecHasMoreCompletions
            && l.ecNextGoalAt == r.ecNextGoalAt
            && l.ecGainedCompletions == r.ecGainedCompletions
            && l.ecFailedRestriction == r.ecFailedRestriction
    }

    var body: some View {
        let canEternity = inf.canEternity
        let isDilated = inf.isDilationActive && canEternity
        let buttonColor: Color = isDilated ? GameColor.dilationGreen : GameColor.eternity

        Button {
            if canEternity { Haptics.tap() }
            engine.requestEternity()
        } label: {
            CompactEternityLabelRenderer(inf: inf, color: buttonColor)
                .padding(.horizontal, 2)
                .padding(.vertical, 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(buttonColor, lineWidth: 1.5)
                )
                .opacity(canEternity ? 1.0 : 0.6)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(canEternity)
    }
}

private struct CompactCrunchButton: View, Equatable {
    let inf: InfinityState
    let tessGlow: Bool
    let engine: GameEngine

    /// Compare only the `inf` fields used by the renderer + button styling.
    /// Field set mirrors `CompactCrunchLabelRenderer.updateUIView`.
    static func == (lhs: Self, rhs: Self) -> Bool {
        if lhs.tessGlow != rhs.tessGlow { return false }
        let l = lhs.inf, r = rhs.inf
        return l.canCrunch == r.canCrunch
            && l.inAntimatterChallenge == r.inAntimatterChallenge
            && l.showIPRate == r.showIPRate
            && l.gainedIP == r.gainedIP
            && l.currentIPRate == r.currentIPRate
            && l.peakIPRate == r.peakIPRate
            && l.peakIPRateVal == r.peakIPRateVal
            && l.infinityGoal == r.infinityGoal
    }

    var body: some View {
        Button {
            if tessGlow {
                Haptics.tap()
                engine.buyTesseract()
            } else if inf.canCrunch {
                Haptics.tap()
                engine.bigCrunch()
            }
        } label: {
            CompactCrunchLabelRenderer(inf: inf, tessGlow: tessGlow,
                                       color: tessGlow ? .black : GameColor.infinity)
                .padding(.horizontal, 2)
                .padding(.vertical, 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(tessGlow ? Color(hex: "#eeeeee") : .black,
                            in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(tessGlow ? .white : GameColor.infinity, lineWidth: 1.5)
                )
                .modifier(TesseractGlow(active: tessGlow))
                .opacity(tessGlow || inf.canCrunch ? 1.0 : 0.5)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(tessGlow || inf.canCrunch)
    }
}

// MARK: - Compact antimatter display (30Hz isolation)

/// Isolates high-frequency antimatter text from parent layout so prestige
/// buttons and challenge row don't re-evaluate on every tick.
/// Tap to cycle through AM → IP → Replicanti → EP → TT → RM (mirrors iPad
/// `SidebarCurrencyHeader`); resources gated by current unlock state.
private struct CompactAntimatterDisplay: View {
    let engine: GameEngine
    @State private var resourceIndex: Int = 0

    /// Header alternate currency — renders inline as "value short_label" to
    /// match antimatter's "1.38 K antimatter" format. `shortName` is the
    /// abbreviation drawn on the same line; `accessibilityName` supplies the
    /// full read-aloud label for VoiceOver.
    private struct AltResource {
        let value: String
        let shortName: String
        let accessibilityName: String
        let color: Color
    }

    /// Cycle order mirrors web `sidebar-resources.js` so iOS surfaces
    /// progressively unlock the same resources the web sidebar offers.
    /// "RM" is Reality Machines only; "Machines" is the combined RM + iM
    /// readout (separate cycle stop, gated on Imaginary Machines unlock).
    private var alternates: [AltResource] {
        var list: [AltResource] = []
        if engine.infinityUnlocked {
            list.append(AltResource(value: engine.currentIP, shortName: "IP",
                                    accessibilityName: "Infinity Points", color: GameColor.infinity))
        }
        if engine.replicantiUnlocked {
            list.append(AltResource(value: engine.replicantiAmountHeader, shortName: "Replicanti",
                                    accessibilityName: "Replicanti", color: GameColor.replicanti))
        }
        if engine.eternityUnlocked {
            list.append(AltResource(value: engine.currentEP, shortName: "EP",
                                    accessibilityName: "Eternity Points", color: GameColor.eternity))
            list.append(AltResource(value: engine.currentTT, shortName: "TT",
                                    accessibilityName: "Time Theorems", color: GameColor.eternity))
        }
        if engine.dilationUnlocked {
            list.append(AltResource(value: engine.currentTP, shortName: "TP",
                                    accessibilityName: "Tachyon Particles", color: GameColor.dilationGreen))
            list.append(AltResource(value: engine.currentDT, shortName: "DT",
                                    accessibilityName: "Dilated Time", color: GameColor.dilationGreen))
        }
        if engine.realityUnlocked {
            list.append(AltResource(value: engine.currentRM, shortName: "RM",
                                    accessibilityName: "Reality Machines", color: GameColor.reality))
        }
        if engine.effarigUnlocked {
            list.append(AltResource(value: engine.currentRelicShards, shortName: "Relic",
                                    accessibilityName: "Relic Shards", color: GameColor.effarig))
        }
        if engine.imaginaryUpgradesUnlocked {
            list.append(AltResource(value: engine.currentImaginaryMachines, shortName: "iM",
                                    accessibilityName: "Imaginary Machines", color: GameColor.reality))
            list.append(AltResource(value: engine.currentMachinesCombined, shortName: "Machines",
                                    accessibilityName: "All Machines", color: GameColor.reality))
        }
        if engine.laitelaUnlocked {
            list.append(AltResource(value: engine.currentDarkMatter, shortName: "DM",
                                    accessibilityName: "Dark Matter", color: GameColor.laitela))
            list.append(AltResource(value: engine.currentDarkEnergy, shortName: "DE",
                                    accessibilityName: "Dark Energy", color: GameColor.laitela))
            list.append(AltResource(value: engine.currentSingularities, shortName: "Sing",
                                    accessibilityName: "Singularities", color: GameColor.laitela))
        }
        if engine.pelleDoomed {
            list.append(AltResource(value: engine.pelleRealityShardsText, shortName: "RS",
                                    accessibilityName: "Reality Shards", color: GameColor.pelle))
        }
        return list
    }

    /// Total slots: 0 = antimatter, 1..n = alternates. Always at least 1.
    private var slotCount: Int { 1 + alternates.count }

    var body: some View {
        let idx = resourceIndex % max(slotCount, 1)
        let alts = alternates
        let alt: (value: String, shortName: String, color: Color)? = (idx == 0 || idx - 1 >= alts.count)
            ? nil
            : (alts[idx - 1].value, alts[idx - 1].shortName, alts[idx - 1].color)

        // Alternates render inline ("0 IP") and fit the same height as the
        // antimatter line, so cycling never shifts surrounding rows.
        // Web strips AM/sec + tickspeed lines once the Reality study is
        // bought — shrink the renderer slot to match. Constants live in
        // `CompactRowHeight` so the formula in `pinnedHeight(...)` stays
        // in lock-step with the rendered height.
        let compactHeight: CGFloat = engine.gameState.infinity.showRealityButton
            ? CompactRowHeight.antimatterPostReality
            : CompactRowHeight.antimatterFull

        Button {
            resourceIndex = (resourceIndex + 1) % max(slotCount, 1)
        } label: {
            CompactAntimatterDisplayRenderer(engine: engine, alternate: alt)
                .frame(height: compactHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onChange(of: slotCount) { _, new in
            if resourceIndex >= new { resourceIndex = 0 }
        }
    }
}

// MARK: - Compact RM display (30Hz isolation)

private struct CompactRMDisplay: View {
    let engine: GameEngine
    private static let font = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)

    var body: some View {
        let rm = engine.currentRMHeaderDisplay
        TwoToneInlineLabelRenderer(
            formattedText: String(localized: "You have \(rm) Reality Machines"),
            valueSubstring: rm,
            valueColor: GameColor.reality,
            surroundColor: .white.opacity(0.5),
            font: Self.font
        )
        .fixedSize()
    }
}

private struct CompactRealityShardsDisplay: View {
    let engine: GameEngine
    private static let font = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)

    var body: some View {
        let shards = engine.pelleRealityShardsText
        TwoToneInlineLabelRenderer(
            formattedText: String(localized: "You have \(shards) Reality Shards."),
            valueSubstring: shards,
            valueColor: GameColor.pelle.readableOnDark(),
            surroundColor: .white.opacity(0.5),
            font: Self.font
        )
        .fixedSize()
    }
}

// MARK: - Compact challenge row

private struct CompactChallengeLabel: View {
    let engine: GameEngine

    private var isInChallenge: Bool {
        let raw = engine.challengeDisplayText
        return !raw.isEmpty && !raw.contains("no active challenges")
    }

    private var inCelestialReality: Bool { !engine.currentCelestialReality.isEmpty }

    /// Composite "Celestial + EC + IC + NC" label matching web.
    private var combinedLabel: String {
        var parts: [String] = []
        if inCelestialReality { parts.append(engine.currentCelestialReality) }
        if isInChallenge { parts.append(engine.challengeDisplayText) }
        return parts.joined(separator: " + ")
    }

    private var exitText: String {
        if isInChallenge { return "Exit" }
        // Pelle's Doomed Reality is permanent — no exit affordance.
        if engine.pelleDoomed { return "" }
        if inCelestialReality { return "Exit" }
        return ""
    }

    private var exitBorderColor: Color {
        isInChallenge ? GameColor.good : GameColor.celestials
    }

    private static let subRowFont = UIFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)

    var body: some View {
        // Single-line concat banner (wraps freely) + hint-timer row below.
        // Sub-row Text widgets are CATextLayer-backed to skip
        // `LocalizedTextStorage.resolve` cost — they otherwise re-resolve
        // at 30Hz during active challenges / Enslaved runs / Lai'tela runs.
        VStack(alignment: .center, spacing: 2) {
            if isInChallenge || inCelestialReality {
                mainLine
            }
            if engine.compactChallengePowerVisible {
                CATextLeaf(
                    text: engine.challengePowerText,
                    font: Self.subRowFont,
                    color: UIColor.white.withAlphaComponent(0.7),
                    alignment: .center,
                    allowsWrap: true
                )
                .fixedSize(horizontal: false, vertical: true)
            }
            if engine.enslavedHintTimerVisible && !engine.enslavedHintTimerText.isEmpty {
                CATextLeaf(
                    text: String(localized: "The Nameless Ones can give you advice in \(engine.enslavedHintTimerText)"),
                    font: Self.subRowFont,
                    color: UIColor(GameColor.enslaved.readableOnDark()),
                    alignment: .center,
                    allowsWrap: true
                )
                .fixedSize(horizontal: false, vertical: true)
            }
            if !engine.laitelaRunEntropyText.isEmpty {
                CATextLeaf(
                    text: String(localized: "Entropy: \(engine.laitelaRunEntropyText)"),
                    font: Self.subRowFont,
                    color: UIColor(GameColor.laitela.readableOnDark()),
                    alignment: .center
                )
                .fixedSize()
            }
            if !engine.laitelaRunGameSpeedText.isEmpty {
                CATextLeaf(
                    text: engine.laitelaRunGameSpeedText,
                    font: Self.subRowFont,
                    color: UIColor(GameColor.laitela.readableOnDark()),
                    alignment: .center
                )
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var mainLine: some View {
        let bannerText: String = engine.pelleDoomed && !isInChallenge
            ? "In a Doomed Reality. Good luck."
            : "In \(combinedLabel)"
        return HStack(spacing: 6) {
            Text(bannerText)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if !exitText.isEmpty {
                Button {
                    Haptics.tap()
                    if isInChallenge {
                        engine.exitChallenge()
                    } else {
                        engine.resetReality()
                    }
                } label: {
                    // "Exit" is a tiny word — give it generous horizontal
                    // breathing room + a minWidth so the tap target is
                    // forgiving even on narrow iPhones, and slightly
                    // bolder + a hair bigger than the 10pt banner text
                    // so it reads as a button, not runover copy.
                    Text(exitText)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 56)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(GameColor.sidebarBackground)
                        .roundedBorder(exitBorderColor, cornerRadius: 6)
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}

// MARK: - Compact Black Hole + game speed row

private struct CompactBlackHoleRow: View {
    let engine: GameEngine

    var body: some View {
        VStack(spacing: 2) {
            // Single-row layout: Pause + Charge + BH status + Discharge + Pulse.
            // Centered as a group via edge Spacers so pre-Enslaved states
            // (no Charge/Discharge/Pulse) don't leave buttons hugging the
            // left edge.
            HStack(spacing: 2) {
                Spacer(minLength: 0)

                GameButton(borderColor: .green, isEnabled: true) {
                    engine.toggleBlackHolePause()
                } label: {
                    Text(engine.blackHoleHeaderPauseText)
                        .padding(.vertical, 8)
                        .font(.system(size: 9, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(width: 60, height: 30)

                if engine.headerEnslavedChargeVisible {
                    GameButton(theme: .enslaved, isEnabled: true) {
                        engine.toggleEnslavedStoreBlackHole()
                    } label: {
                        Text(engine.headerEnslavedIsCharging ? "Stop" : "Charge")
                            .padding(.vertical, 8)
                            .font(.system(size: 9, weight: .bold))
                    }
                    .frame(width: 52, height: 30)
                }

                ForEach(Array(engine.blackHoleHeaderStates.enumerated()), id: \.offset) { _, state in
                    BHStateText(raw: state)
                }

                if engine.headerEnslavedChargeVisible {
                    GameButton(theme: .enslaved, isEnabled: engine.headerCanDischarge) {
                        engine.dischargeEnslavedBlackHole()
                    } label: {
                        Text("\(engine.headerStoredTimeText)")
                            .padding(.vertical, 8)
                            .padding(.horizontal, 2)
                            .font(.system(size: 9, weight: .bold).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(minHeight: 30, maxHeight: 30)
                    .opacity(engine.headerCanDischarge ? 1 : 0.5)
                }

                if engine.headerCanPulse {
                    GameButton(theme: .enslaved, isEnabled: true) {
                        engine.toggleEnslavedAutoPulse()
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 8, weight: .bold))
                            Text(engine.headerIsPulsing ? "ON" : "OFF")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(engine.headerIsPulsing ? .yellow : .white.opacity(0.85))
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 2)
                    }
                    .frame(minWidth: 44, minHeight: 30, maxHeight: 30)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 2)
    }

}

// MARK: - Standalone game speed label

/// Game speed label — shows base speed text plus, when pulsing, an
/// appended "(⤡ Yx)" where the SF symbol is `arrow.up.left.and.arrow.down.right`.
/// Mirrors web `GameSpeedDisplay.vue`. Rendered inline in the header
/// (was previously embedded inside CompactBlackHoleRow which hid it
/// during Doom when the BH row disappears entirely).
private struct CompactGameSpeedLabel: View {
    let engine: GameEngine

    var body: some View {
        HStack(spacing: 4) {
            Text(engine.gameSpeedText)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
            if engine.headerIsGameSpeedPulsing, !engine.headerPulsedSpeedText.isEmpty {
                HStack(spacing: 3) {
                    Text("(")
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                    Text(engine.headerPulsedSpeedText)
                    Text(")")
                }
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.yellow.opacity(0.85))
                .lineLimit(1)
            }
        }
    }
}

/// Renders a single BH status string like `"🌀 Active (5s)"` or
/// `"🌀 ⟦PULSE⟧ Pulsing"`, replacing the `⟦PULSE⟧` marker with the
/// SF Symbol `arrow.up.left.and.arrow.down.right` so the icon matches the
/// Pulse toggle. Tokenization is done in `stripBHDisplayHTML` on the engine
/// side.
struct BHStateText: View {
    let raw: String

    var body: some View {
        let prefix = "🌀"
        let parts = raw.components(separatedBy: "⟦PULSE⟧")
        if parts.count == 2 {
            HStack(spacing: 2) {
                Text("\(prefix)\(parts[0])")
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 9, weight: .bold))
                Text(parts[1])
            }
            .font(.system(size: 10, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        } else {
            Text("\(prefix)\(raw)")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - Compact Reality button glow

/// Compact version of `RealityButtonGlow` for the iPhone header. Smaller
/// radii so the glow fits the 36pt-tall button without bleeding into
/// adjacent prestige buttons. Active flag is driven by
/// `engine.realityButtonSpecial` — lights up when Reality would improve
/// a celestial-run reward.
///
/// Scene-phase aware: pauses the `.repeatForever` animation while
/// backgrounded/inactive so Core Animation stops interpolating and CPU goes
/// quiet on lock/home. See `RealityButtonGlow` for background on why this
/// matters.
private struct CompactRealityButtonGlow: ViewModifier {
    let active: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var pulse = false

    private var shouldAnimate: Bool { active && scenePhase == .active }

    func body(content: Content) -> some View {
        content
            .shadow(color: GameColor.reality.opacity(active ? (pulse ? 0.9 : 0.3) : 0),
                    radius: active ? (pulse ? 10 : 6) : 0)
            .shadow(color: GameColor.reality.opacity(active ? (pulse ? 0.5 : 0.2) : 0),
                    radius: active ? 16 : 0)
            .onAppear { updatePulse(animating: shouldAnimate) }
            .onChange(of: shouldAnimate) { _, nowAnimating in
                updatePulse(animating: nowAnimating)
            }
    }

    private func updatePulse(animating: Bool) {
        if animating {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.25)) { pulse = false }
        }
    }
}

// MARK: - Compact Unlock ID button (Equatable)

/// Equatable so SwiftUI skips body when its primitive inputs are unchanged.
/// Threshold strings (`ipRequirement` / `amRequirement`) are stable except
/// at the exact moment the player crosses an unlock threshold, so most
/// ticks the body is skipped entirely — the modifier chain (.padding,
/// .background, .overlay) does not get rebuilt.
private struct CompactUnlockIDButton: View, Equatable {
    let canUnlock: Bool
    let hasIPUnlock: Bool
    let ipRequirement: String
    let amRequirement: String
    /// Reference identity — same `GameEngine` instance for the lifetime of
    /// the app, so it never differs and doesn't need to factor into ==.
    let engine: GameEngine
    @Environment(\.sidebarState) private var sidebar

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.canUnlock == rhs.canUnlock
            && lhs.hasIPUnlock == rhs.hasIPUnlock
            && lhs.ipRequirement == rhs.ipRequirement
            && lhs.amRequirement == rhs.amRequirement
    }

    private var labelText: String {
        if canUnlock {
            return hasIPUnlock ? "Unlock new Dimension" : "Unlock new Infinity Dimension"
        }
        if hasIPUnlock {
            return "Reach \(ipRequirement) IP + \(amRequirement) AM"
        }
        return "Reach \(amRequirement) AM"
    }

    var body: some View {
        Button {
            if canUnlock {
                Haptics.tap()
                let isFirstID = hasIPUnlock
                engine.unlockNextInfinityDimension()
                if isFirstID {
                    sidebar?.selectSubtab(.infinityDimensions, in: .dimensions, engine: engine)
                }
            }
        } label: {
            Text(labelText)
                .font(.system(size: 10, weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .foregroundStyle(GameColor.infinity)
                .padding(.horizontal, 2)
                .padding(.vertical, 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(GameColor.infinity, lineWidth: 1.5)
                )
                .opacity(canUnlock ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(canUnlock)
    }
}

// MARK: - Compact Armageddon button (Pelle doomed)

/// Reads `pelleCanArmageddon` + the three Pelle text fields directly from
/// `engine`. Not `Equatable` because the Remnants/RS/sec values typically
/// update every tick during active doom — `==` would always return false,
/// adding compare overhead with no skip. The structural extraction still
/// helps: `CompactPrestigeRow.body` no longer reads any Pelle text, so its
/// invalidation set shrinks correspondingly.
private struct CompactArmageddonButton: View {
    let engine: GameEngine

    var body: some View {
        let canArm = engine.pelleCanArmageddon
        return Button {
            if canArm {
                Haptics.tap()
                engine.pelleArmageddon()
            }
        } label: {
            VStack(spacing: 2) {
                Text("Armageddon for")
                    .font(.system(size: 10, weight: .semibold))
                Text("\(Text(engine.pelleRemnantsGainText).foregroundStyle(GameColor.pelle.readableOnDark()).fontWeight(.bold)) Remnants")
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("Reality Shards / sec")
                    .font(.system(size: 9, weight: .medium))
                    .padding(.top, 2)
                Text("\(Text(engine.pelleRealityShardsPerSecText).foregroundStyle(GameColor.pelle.readableOnDark())) ➔ \(Text(engine.pelleRealityShardsRateAfterText).foregroundStyle(GameColor.pelle.readableOnDark()))")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(canArm ? GameColor.pelle.readableOnDark() : .gray)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black, in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(canArm ? GameColor.pelle : .gray, lineWidth: 1.5)
            )
            .opacity(canArm ? 1.0 : 0.6)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(canArm)
    }
}
