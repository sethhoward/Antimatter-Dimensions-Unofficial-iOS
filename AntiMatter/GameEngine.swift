//
//  GameEngine.swift
//  AntiMatter
//
//  Wraps JavaScriptCore to run the Antimatter Dimensions game core.
//  Swift Timers back setInterval/setTimeout. UserDefaults backs localStorage.
//  SwiftUI reads game state via @Observable properties; actions call into JS.
//

import JavaScriptCore
import UIKit
import QuartzCore
import Observation

/// Debug-only logging with timestamp — compiled out in release builds.
private let _debugLogStartTime = CFAbsoluteTimeGetCurrent()

@inline(__always)
func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    let elapsed = CFAbsoluteTimeGetCurrent() - _debugLogStartTime
    print(String(format: "[%8.3f] %@", elapsed, message()))
    #endif
}

/// Saturating Double→Int conversion. `Int(d)` traps when `d` is NaN, infinite,
/// or outside Int's range — both happen for plain JS counters at extreme
/// endgame scale (e.g. `totalTickGained` from free tickspeed becomes Infinity).
/// NaN maps to 0 (a `forProperty` read of a missing/undefined JS field yields
/// NaN, which slips past a `?? 0` fallback; 0 is the honest display). +Inf
/// saturates to Int.max, -Inf to Int.min.
func clampedInt(_ d: Double) -> Int {
    if d.isNaN { return 0 }
    if d >= Double(Int.max) { return Int.max }
    if d <= Double(Int.min) { return Int.min }
    return Int(d)
}

enum PrestigeModal: Identifiable {
    case dimensionBoost
    case galaxy
    case bigCrunch
    case sacrifice
    case replicantiGalaxy
    case eternity
    case normalChallenge(Int)
    case infinityChallenge(Int)
    case eternityChallenge(Int)
    case exitChallenge(String)  // associated value is the challenge name
    case enterDilation
    case exitDilation(tpGain: String)
    case reality
    case resetReality
    case teresaRun
    case effarigRun
    case enslavedRun
    case vRun
    case raRun
    case laitelaRun
    case awayProgress(AwayProgressData)
    case glyphPurge(harsh: Bool, deleted: Int, total: Int)
    case deleteAllUnprotectedGlyphs(deleted: Int, total: Int)
    case deleteAllRejectedGlyphs(deleted: Int, total: Int)

    var id: String {
        switch self {
        case .dimensionBoost: "dimBoost"
        case .galaxy: "galaxy"
        case .bigCrunch: "bigCrunch"
        case .sacrifice: "sacrifice"
        case .replicantiGalaxy: "replicantiGalaxy"
        case .eternity: "eternity"
        case .normalChallenge(let id): "normalChallenge\(id)"
        case .infinityChallenge(let id): "infinityChallenge\(id)"
        case .eternityChallenge(let id): "eternityChallenge\(id)"
        case .exitChallenge: "exitChallenge"
        case .enterDilation: "enterDilation"
        case .exitDilation: "exitDilation"
        case .reality: "reality"
        case .resetReality: "resetReality"
        case .teresaRun: "teresaRun"
        case .effarigRun: "effarigRun"
        case .enslavedRun: "enslavedRun"
        case .vRun: "vRun"
        case .raRun: "raRun"
        case .laitelaRun: "laitelaRun"
        case .awayProgress: "awayProgress"
        case .glyphPurge(let harsh, _, _): harsh ? "glyphPurgeHarsh" : "glyphPurge"
        case .deleteAllUnprotectedGlyphs: "deleteAllUnprotectedGlyphs"
        case .deleteAllRejectedGlyphs: "deleteAllRejectedGlyphs"
        }
    }

    var title: String {
        switch self {
        case .dimensionBoost: "Dimension Boost Reset"
        case .galaxy: "Antimatter Galaxy"
        case .bigCrunch: "You are about to Infinity"
        case .sacrifice: "Dimensional Sacrifice"
        case .replicantiGalaxy: "Replicanti Galaxy"
        case .eternity: "You are about to Eternity"
        case .normalChallenge(let id): "Enter Challenge \(id)"
        case .infinityChallenge(let id): "Enter Infinity Challenge \(id)"
        case .eternityChallenge(let id): "Enter Eternity Challenge \(id)"
        case .exitChallenge(let name): "Exit \(name)"
        case .enterDilation: "Enter Time Dilation"
        case .exitDilation: "Exit Time Dilation"
        case .reality: "You are about to Reality"
        case .resetReality: "You are about to reset your Reality"
        case .teresaRun: "Start Teresa's Reality"
        case .effarigRun: "Start Effarig's Reality"
        case .enslavedRun: "Enter The Nameless Ones' Reality"
        case .vRun: "Enter V's Reality"
        case .raRun: "Enter Ra's Reality"
        case .laitelaRun: "Enter Lai'tela's Reality"
        case .awayProgress: "Offline Progress"
        case .glyphPurge(let harsh, _, _): harsh ? "Harsh Purge Glyphs" : "Purge Glyphs"
        case .deleteAllUnprotectedGlyphs: "Remove Unprotected"
        case .deleteAllRejectedGlyphs: "Remove Rejected"
        }
    }

    var confirmationKey: String {
        switch self {
        case .dimensionBoost: "dimensionBoost"
        case .galaxy: "antimatterGalaxy"
        case .bigCrunch: "bigCrunch"
        case .sacrifice: "sacrifice"
        case .replicantiGalaxy: "replicantiGalaxy"
        case .eternity: "eternity"
        case .normalChallenge, .infinityChallenge, .eternityChallenge: "challenges"
        case .exitChallenge: "exitChallenge"
        case .enterDilation, .exitDilation: "dilation"
        case .reality: "glyphSelection"
        case .resetReality: "resetReality"
        case .teresaRun: "teresa"
        case .effarigRun: "effarig"
        case .enslavedRun: "enslaved"
        case .vRun: "v"
        case .raRun: "ra"
        case .laitelaRun: "laitela"
        case .awayProgress: ""
        case .glyphPurge: "autoClean"
        case .deleteAllUnprotectedGlyphs, .deleteAllRejectedGlyphs: "sacrificeAll"
        }
    }

    var confirmButtonLabel: String {
        switch self {
        case .normalChallenge, .infinityChallenge, .eternityChallenge: "Begin"
        case .exitChallenge: "Exit"
        case .enterDilation: "Enter"
        case .exitDilation: "Exit"
        case .awayProgress: "Close"
        case .glyphPurge: "Purge"
        case .deleteAllUnprotectedGlyphs, .deleteAllRejectedGlyphs: "Remove"
        default: "Confirm"
        }
    }

    var navigatesToDimensions: Bool {
        switch self {
        // Challenges + regular Reality always navigate to the AD tab on confirm.
        // Celestial runs (Teresa/Effarig/Enslaved/V/Ra) deliberately DO NOT —
        // the user is already on the relevant Celestials subtab and wants to
        // stay there to watch the run-specific UI (Effarig stage banner,
        // Enslaved stored-time gauges, Ra pet progress, etc.).
        case .normalChallenge, .infinityChallenge, .eternityChallenge, .reality, .resetReality: true
        default: false
        }
    }
}

struct OfflineSimProgress {
    var current: Int
    var total: Int
    let startTime: Date
}

/// A pending "you are locking yourself out of an upgrade" confirmation, surfaced when the game
/// blocks an action because a Reality/Imaginary Upgrade requirement lock is active (web
/// `Modal.upgradeLock` / `UpgradeMechanicLockModal.vue`). Presented as a native alert at the app
/// root; "Disable Lock" clears the lock so a retry succeeds. Neither choice performs the original
/// action — mirrors the web modal, which also makes the player try the action again.
struct UpgradeLockPrompt: Identifiable, Equatable {
    let upgradeId: Int
    let isImaginary: Bool
    let name: String
    let lockEvent: String
    let requirement: String

    var id: String { "\(isImaginary ? "imaginary" : "reality")-\(upgradeId)" }
    var upgradeKind: String { isImaginary ? "Imaginary Upgrade" : "Reality Upgrade" }
    var title: String { "\(upgradeKind) Condition Lock" }
    var message: String {
        var text = "Are you sure you wish to \(lockEvent)? Doing this now will cause you to fail "
            + "the requirement for the \(upgradeKind) \u{201C}\(name)\u{201D}"
        if !requirement.isEmpty { text += " (\(requirement))" }
        text += ".\n\nNeither option performs the action you just attempted \u{2014} you'll need to try again."
        return text
    }
}

@Observable
final class GameEngine {

    // MARK: - Observable state (each property tracked independently by @Observable)

    // Header — changes every tick, only GameHeaderView reads these
    var antimatter: String = "10"
    var antimatterPerSec: String = "0"
    var progressFill: Double = 0

    // Unlock flags — change very rarely, control tab visibility in GameShell
    var infinityUnlocked: Bool = false
    var autobuyersUnlocked: Bool = false
    var tickspeedUnlocked: Bool = false

    // Header display — changes every tick but only read by GameHeaderView
    var tickspeedMultiplier: String = "x1"
    var tickspeedPerSecond: String = "0"
    var currentIP: String = "0"
    var replicantiAmountHeader: String = "0"
    var replicantiUnlocked: Bool = false
    var challengeDisplayText: String = ""
    var challengePowerText: String = ""
    var quickResetAvailable: Bool = false
    var quickResetHasBoosts: Bool = false
    /// Display name of the celestial whose Reality the player is currently
    /// inside (e.g. "Teresa's Reality"). Empty when not in any celestial run.
    /// Polled from `isInCelestialReality()` + `player.celestials.<key>.run`.
    var currentCelestialReality: String = ""
    /// True when completing Reality right now would improve a celestial-run
    /// reward (higher Glyph-Sacrifice mult from Teresa, or advance an Effarig
    /// stage / complete Enslaved at >1e4000 EP). Mirrors `RealityButton.vue`
    /// `hasSpecialReward()` — drives a pulsing glow on the "Make a new
    /// Reality" button so the player notices they've hit a new best.
    var realityButtonSpecial: Bool = false

    // MARK: - Always-polled Enslaved mirrors
    //
    // `gameState.celestials.enslaved.*` is only populated when the
    // Celestials poll category is active. The speedrun-path UI lives on
    // different tabs (Time Studies for the secret study, Break Infinity
    // for Feel Eternity, Infinity Dimensions for the Tesseract stub), so
    // those views need the flags even when the user isn't on Celestials.
    // Populated in the same per-tick JS block that sets
    // `currentCelestialReality` + `realityButtonSpecial` — one eval, no
    // extra cost.

    /// `Enslaved.isRunning` — `player.celestials.enslaved.run`.
    var enslavedIsRunning: Bool = false
    /// `player.celestials.enslaved.hasSecretStudy` — hides the +100 TT
    /// secret study card after it's been claimed in the current run.
    var enslavedHasSecretStudy: Bool = false
    /// `player.secretUnlocks.viewSecretTS` — the SecretAchievement(21)
    /// reveal toggle. When `true`, the Secret Time Study tile in the
    /// Time Studies tab shows its revealed state ("Unlock a Secret
    /// Achievement"); when `false`, it renders as a hidden ghost the
    /// player can tap to reveal. Mirrors web `SecretTimeStudy.vue`.
    var secretTSVisible: Bool = false
    /// `player.celestials.enslaved.feltEternity` — unused on iOS right
    /// now (Feel Eternity's alert-text branching is already done JS-side
    /// via `_nativeMessage`) but polled for completeness / future UI.
    var enslavedFeltEternity: Bool = false
    /// `Enslaved.isCompleted` — gates the post-completion Tesseract stub
    /// card on the Infinity Dimensions tab.
    var enslavedCompleted: Bool = false
    /// `Enslaved.canTickHintTimer` — true when the player has `RUN` unlocked,
    /// hasn't completed Enslaved, and hasn't yet hit the 5-hour threshold
    /// that flips on the hints system. Drives the hint-countdown header
    /// line below the challenge banner.
    var enslavedHintTimerVisible: Bool = false
    /// Preformatted ETA for the hints unlock ("HH:MM:SS"). Updated every
    /// tick while `enslavedHintTimerVisible`; computed per web
    /// `HeaderChallengeEffects.vue:51-53` — 5h ms minus
    /// `hintUnlockProgress`, divided by 0.4 when outside the run (offline
    /// time counts at 40% of real time).
    var enslavedHintTimerText: String = ""
    /// `Tesseracts.canBuyTesseract` — drives the Big Crunch glow.
    /// Polled per-tick in the celestial-reality eval block.
    var tesseractAffordable: Bool = false

    /// Lai'tela run header extras — "Entropy: 4.83% (9.107 seconds)" and
    /// "Game speed is altered: X" surfaced under the "You are in Lai'tela's
    /// Reality" banner. Empty when not in a Lai run.
    var laitelaRunEntropyText: String = ""
    var laitelaRunGameSpeedText: String = ""

    /// Continuum state mirrored from `Laitela.*` so the Antimatter Dimensions
    /// tab can surface a 3-way buy-quantity toggle (Continuum → Until 10 →
    /// Buy 1) without waiting for the Celestials poll category.
    /// `player.auto.autobuyersOn` — global pause flag. Always polled (not
    /// gated to the Autobuyers tab) so that inline autobuyer toggles on the
    /// Dimensions / ID / TD / Replicanti / Black Hole tabs flip to the
    /// paused-yellow tint immediately when the user toggles pause on the
    /// Autobuyers tab — even before they switch tabs back. The
    /// `gameState.autobuyers.allOn` field on the deeper poll mirrors this
    /// for the Autobuyers tab's own button labels.
    var autobuyersGloballyOn: Bool = true

    /// `continuumUnlocked` implies Laitela is unlocked.
    /// `continuumDisabled` = player.auto.disableContinuum.
    var continuumUnlocked: Bool = false
    var continuumDisabled: Bool = false

    /// Lai'tela autobuyer flags mirrored from the celestial combined eval so
    /// the Autobuyers tab can render them without `.celestials` poll category
    /// being active. Each pair: `*Unlocked` → milestone reached, `*Active` →
    /// currently toggled on.
    var laiAutoDimUnlocked: Bool = false
    var laiAutoDimActive: Bool = false
    var laiAutoAscUnlocked: Bool = false
    var laiAutoAscActive: Bool = false
    var laiAutoSingUnlocked: Bool = false
    var laiAutoSingActive: Bool = false
    var laiAutoAnniUnlocked: Bool = false
    var laiAutoAnniActive: Bool = false
    /// Live `player.auto.annihilation.multiplier` (the annihilation autobuyer
    /// threshold). Surfaced in the always-on poll so the Autobuyers tab can show
    /// it — the `gameState.celestials.laitela` slice is only refreshed on the
    /// Celestials tab and reads 0 elsewhere.
    var laiAutoAnniMultiplier: Double = 0

    // Tab state — only redraws the active tab's views
    var gameState: GameState = .empty

    // UI-only view state (persists across tab switches, not saved to disk)
    var timeStudyZoom: CGFloat = 1.0
    var timeStudyOffset: CGPoint = .zero
    var perksZoom: CGFloat = 1.0
    var perksOffset: CGPoint = .zero
    /// Celestial Navigation pan/zoom — persists across tab switches within a session.
    /// 0 zoom is a sentinel meaning "not yet initialized"; CelestialNavigationTab
    /// applies a Teresa-focused default on first open.
    var celestialNavZoom: CGFloat = 0
    var celestialNavOffset: CGPoint = .zero

    // App state
    var isInitialized: Bool = false
    var jsError: String? = nil
    var toastQueue: [ToastMessage] = []
    var pendingModal: PrestigeModal? = nil
    var glyphChoices: [GlyphInfo] = []       // Glyph selection during Reality
    var showGlyphSelection: Bool = false
    /// Whether the Reality modal should offer a "Sacrifice" button for the
    /// selected glyph. Mirrors web RealityModal.vue's `canSacrifice` which
    /// reads `RealityUpgrade(19).isEffectActive`. Set alongside `glyphChoices`.
    var canSacrificeGlyphOnReality: Bool = false
    var offlineSimProgress: OfflineSimProgress? = nil
    var gameMessage: String? = nil  // Modal.message from JS (e.g. C11 failure)
    var infinityDimsUnlocked: Bool = false
    var eternityUnlocked: Bool = false
    var dilationUnlocked: Bool = false
    var eternityChallengesUnlocked: Bool = false
    var realityUnlocked: Bool = false
    var realityStudyBought: Bool = false
    /// Drives the one-time new-player onboarding (welcome modal → anchored callouts).
    /// `nil` = inactive. Set once in `finishStartup()` for a truly fresh save that
    /// hasn't yet seen/declined onboarding on this device (UserDefaults
    /// `am_hasSeenOnboarding`). See `OnboardingState` in `Views/Onboarding/`.
    var onboarding: OnboardingState? = nil
    /// Gates the Multiplier Breakdown subtab — mirrors web's `PlayerProgress.infinityUnlocked()`.
    /// Same condition as `infinityUnlocked` but driven by the statistics-helper visibility eval
    /// so the four new Statistics subtabs share one consistent code path.
    var multiplierBreakdownVisible: Bool = false
    /// Gates the Glyph Set Records subtab — web condition `PlayerProgress.realityUnlocked()`.
    var glyphSetRecordsVisible: Bool = false
    /// Gates the Speedrun Milestones subtab — web condition `player.speedrun.isActive`.
    var speedrunMilestonesVisible: Bool = false
    /// Gates the Speedrun Records subtab — web condition
    /// `Object.keys(player.speedrun.previousRuns).length > 0`.
    var speedrunRecordsVisible: Bool = false
    var teresaUnlocked: Bool = false
    var effarigUnlocked: Bool = false
    /// `EffarigUnlock.eternity.isUnlocked` — gates the Nameless Ones subtab
    /// and nav-map nodes. Polled in the same block as teresa/effarig unlocks.
    var effarigEternityUnlocked: Bool = false
    /// `Achievement(151).isUnlocked` — gates V's subtab + navigation node.
    /// Achievement 151 = "Complete The Nameless Ones' Reality."
    var vUnlocked: Bool = false
    /// `VUnlocks.raUnlock.isUnlocked` — gates Ra's subtab + navigation node.
    /// Requires 36 Space Theorems (all V-Achievements completed).
    var raUnlocked: Bool = false
    /// `MachineHandler.isIMUnlocked` — gates the Imaginary Upgrades subtab.
    /// True once RM ≥ hardcapRM(1e4000) OR iM > 0.
    var imaginaryUpgradesUnlocked: Bool = false
    /// `Ra.unlocks.unlockGlyphAlchemy.canBeApplied` — gates the Glyph Alchemy subtab.
    /// Requires Effarig pet lv 2 in Ra.
    var glyphAlchemyUnlocked: Bool = false
    /// `Laitela.isUnlocked` — gates the Lai'tela celestial subtab (and the
    /// navigation-map node). Requires all 4 Ra pets at level 25.
    var laitelaUnlocked: Bool = false
    /// `Pelle.isUnlocked` — gates the Pelle celestial subtab. Requires
    /// ImaginaryUpgrade(25) which itself requires Lai'tela difficultyTier 8 +
    /// Reality study + glyph constraints (see `imaginary-upgrades.js:312`).
    var pelleUnlocked: Bool = false
    /// `Pelle.isDoomed` — `player.celestials.pelle.doomed`. When true, gates
    /// the "Doomed Reality" header banner, the Armageddon header button (which
    /// replaces the Reality button), and the ~30 cross-cutting nerf paths.
    var pelleDoomed: Bool = false
    /// Whether the Armageddon reset would currently grant remnants. Mirrors
    /// `Pelle.canArmageddon` — drives the header Armageddon button's affordance.
    var pelleCanArmageddon: Bool = false
    /// Preformatted Remnants gain on next Armageddon (e.g. "1.23e4"). Empty when
    /// not doomed. Sourced from `format(Pelle.remnantsGain, 2)` JS-side.
    var pelleRemnantsGainText: String = ""
    /// Current Reality Shards balance — always-polled so the header can show
    /// the "You have X Reality Shards" line under antimatter without depending
    /// on the Pelle subtab being active.
    var pelleRealityShardsText: String = "0"
    /// Current Reality Shards rate ("X/s"). Always-polled.
    var pelleRealityShardsPerSecText: String = "0/s"
    /// Reality Shards rate AFTER the next Armageddon ("Y/s"). Drives the
    /// "X/s ➔ Y/s" transition inside the Armageddon header button.
    var pelleRealityShardsRateAfterText: String = "0/s"
    /// True when the player is doomed AND `PelleUpgrade.glyphEquipping` has
    /// NOT yet been bought. Mirrors `Pelle.isDisabled("glyphs")`. Used by
    /// GlyphsTab to disable the equip flow + show an explanatory banner.
    var pelleGlyphEquippingDisabled: Bool = false

    // MARK: - Pelle disabled-item registries (canonical, JS-sourced)
    //
    // Static post-init lists from `pelle.js:184-204`. Loaded once via
    // `_nativePelleDisabledLists()` after `setupCelestialHelpers()` and cached.
    // Replaces the previously hardcoded Swift sets in PerksTab / TimeStudiesTab
    // / RealityUpgradesTab, eliminating drift from upstream.
    //
    // Consumers gate on `engine.pelleDoomed && set.contains(id)` — the additive
    // idiom; the lists themselves are zero-cost outside of doom.

    /// `Pelle.uselessPerks` — perk IDs whose effects are nullified by Doom.
    /// Bought perks in this set get strikethrough + Pelle-red label.
    var pelleUselessPerks: Set<Int> = []
    /// `Pelle.uselessTimeStudies` — TS IDs whose effects are nullified by Doom.
    /// Bought studies in this set get crimson card + strikethrough.
    var pelleUselessTimeStudies: Set<Int> = []
    /// `Pelle.disabledRUPGs` — Reality Upgrade IDs disabled by Doom.
    /// Bought RUPGs in this set get the same `o-pelle-disabled` visual treatment.
    var pelleDisabledRUPGs: Set<Int> = []
    /// `Pelle.disabledAchievements` — achievement IDs whose unlock effect is
    /// nullified by Doom. Achievement tiles already render Pelle-tinted via
    /// JS-side `pelle` flag in achievement state; this list is the canonical
    /// reference for any Swift-side cross-checks (e.g. milestone gating).
    var pelleDisabledAchievements: Set<Int> = []
    /// `Pelle.uselessInfinityUpgrades` — JS config IDs (`passiveGen`, `ipMult`,
    /// `infinitiedGeneration`) whose effects are nullified by Doom. Note that
    /// the iOS port translates these to its own internal upgrade keys
    /// (`ipGen`, `infinitiedGen`) — `InfinityUpgradesTab.swift` maintains its
    /// own iOS-key set with the translation rationale documented in-place.
    var pelleUselessInfinityUpgrades: Set<String> = []

    // MARK: - GameEnd / credits / zalgo finale (post-Pelle)

    /// `GameEnd.endState` — 0..14.5, log-scaled from totalAntimatter.
    /// Drives every other GameEnd flag below. Always 0 outside the finale.
    var endStateValue: Double = 0
    /// `GameEnd.creditsClosed` — set true by tapping "Close" on the credits
    /// overlay; survives until the next visit to the finale.
    var gameEndCreditsClosed: Bool = false
    /// `endState >= GameEndMarker.gameEnd (1.0)` — zalgo corruption begins.
    var gameEndZalgoActive: Bool { endStateValue >= GameEndMarker.gameEnd }
    /// `endState >= GameEndMarker.tabStartHide (1.5)` — sidebar fade begins.
    var gameEndTabsHidden: Bool { endStateValue >= GameEndMarker.tabStartHide }
    /// `endState >= GameEndMarker.interactDisabled (2.5)` — UI taps no-op.
    var gameEndInteractivityDisabled: Bool { endStateValue >= GameEndMarker.interactDisabled }
    /// `endState >= GameEndMarker.saveDisabled (4.0)` — `save()` no-ops.
    var gameEndSavesDisabled: Bool { endStateValue >= GameEndMarker.saveDisabled }
    /// `endState >= GameEndMarker.endNumbers (4.2)` — visible numbers freeze
    /// (pollDirect skips numeric writes; structural fields keep updating).
    var gameEndNumbersFrozen: Bool { endStateValue >= GameEndMarker.endNumbers }
    /// `endState >= GameEndMarker.creditsStart (4.5)` — credits overlay shown.
    var gameEndCreditsActive: Bool {
        endStateValue >= GameEndMarker.creditsStart && !gameEndCreditsClosed
    }
    /// `endState >= GameEndMarker.creditsEnd (14.5)` — credits over.
    var gameEndCreditsFinished: Bool { endStateValue >= GameEndMarker.creditsEnd }
    /// 0..1 zalgo intensity ramp from GAME_END (1.0) to CREDITS_START (4.5).
    var gameEndZalgoIntensity: Double {
        let t = (endStateValue - GameEndMarker.gameEnd)
              / (GameEndMarker.creditsStart - GameEndMarker.gameEnd)
        return max(0, min(1, t))
    }
    /// Speedrun Mode — per-tick lightweight state. Drives the sidebar
    /// footer / header subtitle, the Options entry visibility, and the
    /// Statistics-tab gating. Populated by `pollSpeedrunQuick()` in the
    /// always-on block of `pollDirect()`.
    var speedrunQuick: SpeedrunQuickState = SpeedrunQuickState()
    var currentRM: String = "0"
    /// Header "You have X Reality Machines" value below antimatter. Mirrors web
    /// `RealityCurrencyHeader.vue` which uses `formatMachines(rm, im)` — once
    /// Imaginary Machines unlock this becomes the combined "rm + Xi" readout,
    /// otherwise it's pure RM (identical to `currentRM`). Distinct from
    /// `currentRM` (still pure RM, used by the sidebar "Reality Machines" cycle
    /// stop + Reality Upgrades header) and `currentMachinesCombined` (the always-
    /// combined sidebar "Machines" cycle stop).
    var currentRMHeaderDisplay: String = "0"
    var gameSpeedText: String = ""
    /// Stable visibility gate for `CompactGameSpeedLabel`. Mirrors
    /// `!gameSpeedText.isEmpty` but only invalidates on transitions, so the
    /// iPhone header body doesn't redraw every tick when the speed value
    /// changes (which is the text content, not the visibility).
    var compactGameSpeedVisible: Bool = false
    /// Stable visibility gate for the iPhone challenge / celestial-reality
    /// banner (`CompactChallengeLabel`). Mirrors `isInChallenge ||
    /// !currentCelestialReality.isEmpty` but only invalidates on transitions
    /// so the parent header body doesn't redraw on every text update inside
    /// the banner.
    var compactBannerVisible: Bool = false
    /// Stable mirror of whether the iPhone banner renders an Exit button —
    /// i.e. `CompactChallengeLabel.exitText` non-empty:
    /// `isInChallenge || (!pelleDoomed && inCelestialReality)`. Drives the
    /// `bannerHasExit` (28pt vs 16pt) reservation in `PhoneShell.compactHeaderHeight`.
    /// NOT `compactBannerVisible && !pelleDoomed` — a Doomed Reality that is
    /// ALSO in an Eternity Challenge shows the banner WITH an Exit button
    /// (you can exit the EC), so it needs the taller reservation.
    var compactBannerHasExit: Bool = false
    /// Stable mirrors of `gameState.infinity.{showEPRate, showIPRate,
    /// isBroken, showRealityButton}` plus `!challengePowerText.isEmpty`.
    /// Read by `PhoneShell.compactHeaderHeight` instead of going through
    /// `engine.gameState.infinity` (which gets reassigned every tick by
    /// pollDirect, invalidating PhoneShell.body even though these specific
    /// fields only flip on threshold transitions). pollDirect's main-thread
    /// commit updates each one only on diff, so SwiftUI's @Observable
    /// observation only invalidates when the visibility actually changes.
    var compactShowEPRate: Bool = false
    var compactShowIPRate: Bool = false
    var compactIsBroken: Bool = false
    var compactShowRealityButton: Bool = false
    /// iPhone-only: drives the post-first-crunch / pre-break Big Crunch
    /// button in `CompactPrestigeRow` and the matching 80pt slot
    /// reservation in `CompactHeaderView.pinnedHeight`. Diff-checked
    /// mirror of `!isBroken && canCrunch && infinityUnlocked` so
    /// `PhoneShell.compactHeaderHeight` never has to read
    /// `engine.gameState.infinity` (which reassigns every tick).
    var compactShowPreBreakCrunch: Bool = false
    var compactChallengePowerVisible: Bool = false

    /// Weak ref to the active shell's `SidebarState`. Set from
    /// `GameShell` / `PhoneShell` `.onAppear`. Used by
    /// `recoverFromHiddenActiveTab` so the recovery path can run from
    /// the engine side (pollDirect, save-lifecycle hooks) without each
    /// caller threading sidebar state through. iPad and iPhone shells
    /// each own their own SidebarState — whichever shell is currently
    /// presented wins, which matches the user's actual visible
    /// navigation. Marked `@ObservationIgnored` so SwiftUI doesn't try
    /// to track changes through the weak ref (the SidebarState is
    /// already its own `@Observable`).
    @ObservationIgnored weak var sidebarStateRef: SidebarState?

    /// User-hidden tab bitfield, mirrored from `player.options.hiddenTabBits`
    /// every tick. One bit per web tab id (see `SidebarTab.webId`). Drives
    /// `SidebarTab.isHidden(engine:)`. Polled diff-checked so the sidebar
    /// only re-evaluates when the user actually toggles visibility, not
    /// every tick.
    var hiddenTabBits: Int = 0

    /// Per-parent-tab user-hidden subtab bitfield, mirrored from
    /// `player.options.hiddenSubtabBits` every tick. 11 ints indexed by
    /// parent's web tab id (see `SidebarTab.webId`). Drives
    /// `Subtab.isHidden(engine:)`. Equatable so SwiftUI's @Observable diff
    /// path catches array-level changes.
    var hiddenSubtabBits: [Int] = Array(repeating: 0, count: 11)

    #if DEBUG
    /// Actual rendered height of the compact header's inner VStack, measured
    /// via a `PreferenceKey` in `CompactHeaderView`. Drives the DEBUG header
    /// overlay's `A:` (actual) readout. Updated only when the rendered height
    /// changes (PreferenceKey diffing). See the design notes → "Compact header
    /// sizing invariants" for the contract this overlay validates.
    var compactHeaderActualHeight: CGFloat = 0
    /// Toggled from Debug tab → "Show compact header height overlay". When
    /// true, `CompactHeaderView` renders the `R / S / A / Δ / ↓Ns` overlay
    /// so calibration drift is visible at a glance. Persisted via
    /// `UserDefaults` (`compactHeaderShowOverlay`) so it survives relaunch.
    var showCompactHeaderHeightOverlay: Bool = UserDefaults.standard.bool(forKey: "compactHeaderShowOverlay") {
        didSet { UserDefaults.standard.set(showCompactHeaderHeightOverlay, forKey: "compactHeaderShowOverlay") }
    }
    /// Seconds remaining until `PhoneShell`'s pending shrink-debounce fires.
    /// `nil` when no shrink is pending. Drives the overlay's `↓Ns` countdown
    /// so the debounce state is observable during testing.
    var compactHeaderShrinkPendingSeconds: Double? = nil
    #endif
    var blackHolesHeaderVisible: Bool = false
    var blackHoleHeaderPauseText: String = ""
    var blackHoleHeaderStates: [String] = []
    /// Whether the header should show the Enslaved Charge/Stop-Charging button.
    /// Matches web `HeaderBlackHole.vue`'s `canCharge = Enslaved.isUnlocked`.
    var headerEnslavedChargeVisible: Bool = false
    /// Pulse Black Hole toggle (Ra Enslaved pet lv 10 unlock). When true
    /// the Charge/Stop button is hidden — you can't charge while pulsing.
    var headerCanPulse: Bool = false
    var headerIsPulsing: Bool = false
    /// One-shot Discharge of stored game time. Gated on `Enslaved.canRelease(false)`.
    var headerCanDischarge: Bool = false
    /// Formatted short stored time, e.g. `5m 32s`. Shown inside the Discharge button.
    var headerStoredTimeText: String = "0s"
    /// Secondary pulsed-speed appended to the game-speed label when pulsing.
    var headerPulsedSpeedText: String = ""
    var headerIsGameSpeedPulsing: Bool = false
    /// Whether the Black Hole is currently storing game time
    /// (Enslaved.isStoringGameTime). Drives the Charge button's label.
    var headerEnslavedIsCharging: Bool = false
    var blackHolesHeaderPermanent: Bool = false
    var blackHolesHeaderPaused: Bool = false
    var currentEP: String = "0"
    var currentTT: String = "0"
    /// Always-polled sidebar/header cycle currencies (web `sidebar-resources.js`
    /// IDs 7–14). Each is gated by its corresponding `*Unlocked` flag so a
    /// fresh game pays zero JS cost.
    var currentTP: String = "0"                  // Tachyon Particles      (dilation)
    var currentDT: String = "0"                  // Dilated Time           (dilation)
    var currentRelicShards: String = "0"         // Relic Shards           (effarig)
    var currentImaginaryMachines: String = "0"   // Imaginary Machines     (iM unlocked)
    var currentMachinesCombined: String = "0"    // formatMachines(rm, im) (iM unlocked)
    var currentDarkMatter: String = "0"          // Dark Matter            (laitela)
    var currentDarkEnergy: String = "0"          // Dark Energy            (laitela)
    var currentSingularities: String = "0"       // Singularities          (laitela)
    var notifiedSubtabs: Set<Subtab> = []
    var newsEnabled: Bool = true
    var newsSpeed: Double = 1.0
    /// Web's Options → Gameplay mirrors. Polled every tick from `player.options.*`.
    /// Web parity: `automaticTabSwitching` controls whether non-manual `Tab.show()`
    /// calls navigate; iOS uses it to gate `SidebarState.selectSubtabIfAuto`.
    var automaticTabSwitching: Bool = true
    var offlineProgressEnabledOption: Bool = true
    /// Web `player.options.confirmations.glyphSelection` — when on, manual Reality
    /// shows the glyph-selection prompt; when off, a glyph is auto-picked (Effarig
    /// filter / random), matching web `reality.js`.
    var glyphSelectionConfirmation: Bool = true
    var offlineTicksValue: Int = 1000
    var automatorLogMaxEntries: Int = 100
    /// Web `player.options.glyphTextColors` — when off, suppress type-color +
    /// halo on glyph effect / sacrifice text. Polled here so the toggle in
    /// Options → Gameplay is accurate independent of the Glyphs subtab.
    var glyphTextColorsOption: Bool = true
    /// Web `player.options.hideAlterationEffects` — when true, the Altered
    /// Glyphs card on the Glyphs tab collapses to just the "Details hidden"
    /// hint. Polled here for parity with the Options toggle.
    var hideAlterationOption: Bool = false
    /// Name of the currently-selected notation (e.g. "Mixed scientific",
    /// "Letters"). Polled from `player.options.notation` each tick.
    var notationName: String = "Mixed scientific"

    /// Monotonically increasing counter bumped every time `GameStorage.save`
    /// lands (autosave, manual save, import, hard reset, slot switch, backup
    /// restore). Views that display persisted save metadata — like
    /// `SaveSlotsSection` — observe this and refresh their snapshot when it
    /// changes, avoiding a per-second polling timer. Hooked via
    /// `_nativeSaveTick` in `save-helpers.js` / `setupSaveHelpers`.
    var saveSignal: Int = 0

    /// Mirrors `GameStorage.currentSlot` — updated on every save tick (via
    /// save-helpers.js hook) and whenever slot switches complete. Read by
    /// `CloudSaveService` to know which slot to upload / compare against.
    /// Default 0 matches `GameStorage.currentSlot`'s default.
    var lastKnownCurrentSlot: Int = 0

    /// iCloud Key-Value sync. Created lazily once the engine finishes its
    /// first JS init so the service can observe saveSignal and upload
    /// whenever `GameStorage.save` fires. nil when not yet constructed
    /// (first few ms of startup).
    var cloudSaveService: CloudSaveService?

    /// Result of the most recent glyph-preset load. Drives persistent
    /// badges on equipped slots so the user can see which slots came from
    /// a non-exact fuzzy/partial match. Cleared when the user manually
    /// modifies a slot (drag/sacrifice/unequip) or when a new Reality
    /// wipes the equipped set. Not in `gameState` because pollDirect
    /// would overwrite it every tick.
    var lastLoadResult: GlyphLoadResult? = nil

    // Celestials — quote modal state (always polled so quotes can appear from any tab)
    var activeQuote: QuoteState? = nil
    /// Pending Reality/Imaginary Upgrade requirement-lock confirmation (see `UpgradeLockPrompt`).
    /// Set from the `_nativeUpgradeLock` bridge; presented as an alert at the app root.
    var activeUpgradeLock: UpgradeLockPrompt? = nil
    /// Quote history for the celestial whose "History" button was most recently tapped.
    /// Separate from `gameState` because `pollDirect` overwrites `gameState` every tick,
    /// and history is loaded lazily (not per-tick polled).
    var celestialQuoteHistory: [QuoteHistoryEntry] = []

    // Effarig glyph sub-feature state — each loaded on its sheet's appear, NOT polled
    // per-tick (and deliberately kept OFF `gameState`, which pollDirect overwrites).
    var effarigGlyphWeights: EffarigGlyphWeightsState? = nil
    var effarigGlyphFilter: GlyphFilterState? = nil
    var effarigGlyphPresets: EffarigPresetsState? = nil
    /// On-demand Glyph Level Factor breakdown — reused between the Glyphs tab
    /// DisclosureGroup and the Effarig weights sheet. Refreshed via
    /// `loadGlyphLevelFactors()` whenever either surface is visible so the
    /// values stay live while the player adjusts weights.
    var glyphLevelFactorsSnapshot: GlyphLevelFactorsState? = nil

    /// Enslaved hints modal snapshot — loaded on sheet appear + during its
    /// 1Hz refresh timer. Non-tick-polled (kept off `gameState`) because
    /// the modal is short-lived and the full EnslavedProgress serialization
    /// isn't worth per-tick cost.
    var enslavedHints: EnslavedHintsState? = nil

    /// Called by SidebarState when the active subtab changes.
    func selectSubtab(_ subtab: Subtab) {
        let cat = subtab.pollCategory
        let viewKeys = Subtab.jsViewKeys[subtab]
        jsQueue.async { [self] in
            self._jsPollCategory = cat
            self._jsActiveSubtab = subtab
            // Sync JS state.view.tab/subtab so Tabs.current is correct.
            // Without this, tab-notification triggers can't tell which tab the user
            // is viewing and will add badges for the tab already on-screen.
            if let keys = viewKeys {
                // Sync view state and dispatch TAB_CHANGED so upstream
                // handlers fire (e.g. Teresa.quotes.initial.show() on first
                // visit to her tab). dispatch() is a no-op if GAME_EVENT or
                // EventHub isn't ready yet, guarded by typeof checks.
                _ = self.context.evaluateScript("""
                    ui.view.tab = '\(keys.tab)';
                    ui.view.subtab = '\(keys.subtab)';
                    if (typeof EventHub !== 'undefined' && typeof GAME_EVENT !== 'undefined') {
                        EventHub.dispatch(GAME_EVENT.TAB_CHANGED);
                    }
                    """)
            }
        }
    }

    /// Clear a tab notification when the user navigates to a subtab.
    func clearTabNotification(for subtab: Subtab) {
        guard let jsKey = Subtab.subtabToJSKey[subtab] else { return }
        jsQueue.async { [self] in
            autoreleasepool {
                _ = context.evaluateScript("player.tabNotifications.delete('\(jsKey)')")
            }
        }
    }

#if DEBUG
    /// DEBUG: directly add one or more keys to `player.tabNotifications` so the badge surface
    /// (key → Subtab map → poll → render → clear-on-navigation) can be exercised without
    /// reaching the underlying game-state condition. Used by the Debug tab cheat row.
    func devTriggerBadge(keys: [String]) {
        let literal = keys.map { "'\($0)'" }.joined(separator: ",")
        jsQueue.async { [self] in
            autoreleasepool {
                _ = context.evaluateScript("[\(literal)].forEach(k => player.tabNotifications.add(k))")
            }
        }
    }

    /// DEBUG: clear every entry from `player.tabNotifications`.
    func devClearAllBadges() {
        jsQueue.async { [self] in
            autoreleasepool {
                _ = context.evaluateScript("player.tabNotifications.clear()")
            }
        }
    }

    /// DEBUG: most recent JIT-bench result, surfaced in the Debug tab.
    var lastJITBenchResult: JITBenchResult?
    /// DEBUG: true while a JIT bench run is in flight (to disable the
    /// trigger button + show a status spinner).
    var jitBenchRunning: Bool = false

    /// DEBUG: run the JIT microbench. Compares JSContext (no JIT) against a
    /// hidden WKWebView (which has JIT in its out-of-process WebContent
    /// service). Result + verdict surfaced via `lastJITBenchResult` and
    /// printed to the debug log.
    @MainActor
    func runJITBench(iterations: Int = 1_000_000) async {
        guard !jitBenchRunning else { return }
        jitBenchRunning = true
        defer { jitBenchRunning = false }

        guard let benchURL = Bundle.main.url(forResource: "jit-bench", withExtension: "js"),
              let benchSrc = try? String(contentsOf: benchURL, encoding: .utf8) else {
            debugLog("JIT BENCH: missing jit-bench.js")
            return
        }

        // 1) JSContext: re-inject the bench script (idempotent — defines
        //    a single global) and call into it. The existing _patchDecimalPerf
        //    + timesEffectsOf patch are already applied from `start()`.
        let jsCtxResult: (elapsedMs: Double, checksum: String) = await withCheckedContinuation { cont in
            self.jsQueue.async { [weak self] in
                guard let self else {
                    cont.resume(returning: (-1, ""))
                    return
                }
                autoreleasepool {
                    self.context.evaluateScript(benchSrc)
                    let result = self.context.evaluateScript("_runJITBench(\(iterations))")
                    let elapsed = result?.forProperty("elapsedMs")?.toDouble() ?? -1
                    let checksum = result?.forProperty("checksum")?.toString() ?? ""
                    cont.resume(returning: (elapsed, checksum))
                }
            }
        }

        // 2) WKWebView: spin up a fresh hidden WebView, load the bundle +
        //    same patches via WKUserScripts, then evaluate the bench.
        let webViewBench = JITWebViewBench(iterations: iterations)
        let webViewResult = await webViewBench.run()

        let result = JITBenchResult(
            iterations: iterations,
            jsContextMs: jsCtxResult.elapsedMs,
            webViewMs: webViewResult?.elapsedMs ?? -1,
            jsContextChecksum: jsCtxResult.checksum,
            webViewChecksum: webViewResult?.checksum ?? "",
            webViewError: webViewResult == nil ? "WebView eval failed or never finished" : nil
        )
        debugLog("JIT BENCH:\n\(result.formattedReport)")
        lastJITBenchResult = result
    }

    /// DEBUG: divergence-test status (Stage-5).
    var lastDivergenceStatus: String?
    /// DEBUG: true while a divergence test is in flight.
    var divergenceRunning: Bool = false


    /// DEBUG: Stage-5 divergence test. Runs the SAME save+elapsed
    /// through both the JSContext path and the WebView path, then
    /// compares post-sim saves. Confirms (or refutes) that the two
    /// paths produce equivalent game state for the same input —
    /// critical for trusting WebView-default with cloud sync's
    /// SHA-256-based conflict detection.
    ///
    /// Pipeline:
    ///   1. Export current slot → userSave
    ///   2. Run JSContext sim synchronously → export → jsSave
    ///   3. Restore userSave (so user's actual state is preserved)
    ///   4. Boot WebView, import userSave, run sim, export → wvSave
    ///   5. Tear down WebView
    ///   6. Compare jsSave vs wvSave (byte-identical? key fields equal?)
    ///   7. (userSave is back in JSContext from step 3)
    ///
    /// Defaults to elapsed=60s (~1200 ticks at 20Hz, fast enough that the
    /// JSContext synchronous run isn't painful — ~2-5s wall clock at endgame).
    @MainActor
    func runDivergenceTest(elapsedSeconds: Double = 60) async {
        guard !divergenceRunning else { return }
        divergenceRunning = true
        defer { divergenceRunning = false }
        lastDivergenceStatus = "Running…"

        // 1. Export current slot.
        let slotId = currentCloudSlotId
        guard let userSave = exportSlotRawSync(slotId), !userSave.isEmpty else {
            let msg = "Export failed (slot \(slotId))"
            debugLog("DIVERGENCE: \(msg)")
            lastDivergenceStatus = msg
            return
        }
        let userBytes = userSave.utf8.count

        // 2. Run JSContext sim synchronously, export.
        let jsStart = Date()
        guard let jsSave = await runJSContextSimForDivergence(elapsedSeconds: elapsedSeconds) else {
            let msg = "JSContext sim failed — attempting restore"
            debugLog("DIVERGENCE: \(msg)")
            // Try to restore user state regardless.
            _ = await applyOfflineSimSave(userSave)
            lastDivergenceStatus = msg
            return
        }
        let jsMs = Date().timeIntervalSince(jsStart) * 1000

        // 3. Restore user save into JSContext so step 4's WebView import
        // crosses the same starting state.
        let restoreStart = Date()
        guard await applyOfflineSimSave(userSave) else {
            let msg = "Restore between JS / WV runs failed — user state may be stale; relaunching the app may help"
            debugLog("DIVERGENCE: \(msg)")
            lastDivergenceStatus = msg
            return
        }
        let restoreMs = Date().timeIntervalSince(restoreStart) * 1000

        // 4. Run WebView sim.
        let wvStart = Date()
        let sim = OfflineSimWebView()
        guard (await sim.boot()).isOK else {
            sim.tearDown()
            let msg = "WebView boot failed"
            debugLog("DIVERGENCE: \(msg)")
            lastDivergenceStatus = msg
            return
        }
        guard await sim.importSave(userSave) else {
            sim.tearDown()
            let msg = "WebView import failed"
            debugLog("DIVERGENCE: \(msg)")
            lastDivergenceStatus = msg
            return
        }
        let ticksRun = await sim.runOfflineSim(elapsedSeconds: elapsedSeconds)
        guard ticksRun >= 0 else {
            sim.tearDown()
            let msg = "WebView sim failed"
            debugLog("DIVERGENCE: \(msg)")
            lastDivergenceStatus = msg
            return
        }
        guard let wvSave = await sim.exportSave() else {
            sim.tearDown()
            let msg = "WebView export failed"
            debugLog("DIVERGENCE: \(msg)")
            lastDivergenceStatus = msg
            return
        }
        sim.tearDown()
        let wvMs = Date().timeIntervalSince(wvStart) * 1000

        // 5. Compare. Byte-identical is the strict win; fall back to
        // checking key fields if not.
        let identical = jsSave == wvSave
        let jsBytes = jsSave.utf8.count
        let wvBytes = wvSave.utf8.count

        if identical {
            let msg = String(
                format: "BYTE-IDENTICAL · %d B · JS %.0fms / restore %.0fms / WV %.0fms (boot+import+sim+export) / %d ticks",
                jsBytes, jsMs, restoreMs, wvMs, ticksRun
            )
            debugLog("DIVERGENCE: \(msg)")
            lastDivergenceStatus = msg
            return
        }

        // Not byte-identical. Compute common-prefix length and decode
        // key fields from both saves to see if game state is at least
        // logically equivalent.
        let prefix = jsSave.commonPrefix(with: wvSave).utf8.count
        let lenDiff = abs(jsBytes - wvBytes)
        let keyFieldDiff = await compareKeyFields(jsSave: jsSave, wvSave: wvSave)
        let msg = String(
            format: "DIVERGE · JS %d B / WV %d B (Δ%d, common prefix %d) · keys: %@ · user save was %d B · JS %.0fms / WV %.0fms",
            jsBytes, wvBytes, lenDiff, prefix,
            keyFieldDiff, userBytes, jsMs, wvMs
        )
        debugLog("DIVERGENCE: \(msg)")
        lastDivergenceStatus = msg
    }

    /// Runs the offline-sim setup + drains all ticks synchronously in
    /// JSContext, then exports the active slot. Doesn't show progress
    /// UI. Used only by `runDivergenceTest`.
    @MainActor
    private func runJSContextSimForDivergence(elapsedSeconds: Double) async -> String? {
        let setupSource = GameEngine.offlineSimSetupSource(elapsedSeconds: elapsedSeconds)
        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            jsQueue.async { [weak self] in
                guard let self = self else { cont.resume(returning: nil); return }
                autoreleasepool {
                    // Stop game intervals so the sim isn't competing with
                    // the live tick loop.
                    self.stopAllGameTimersJS()
                    let tickCount = self.context.evaluateScript(setupSource)?.toDouble() ?? 0
                    if tickCount.isFinite, tickCount > 0 {
                        // Drain all ticks at once. No yielding — we want
                        // a single deterministic run.
                        self.context.evaluateScript("""
                            (function() {
                                var sim = _offlineSim;
                                if (!sim) return;
                                while (sim.remaining > 0) {
                                    sim.loopFn(sim.remaining);
                                    sim.remaining--;
                                }
                            })()
                        """)
                    }
                    // Finalize like finalizeOfflineSimulation would.
                    self.context.evaluateScript("""
                        if (typeof _offlineSim !== 'undefined') _offlineSim = undefined;
                        GameStorage.postLoadStuff();
                        GameUI.notify.showBlackHoles = true;
                    """)
                    self.restartAllGameTimersJS()
                    // Export the current slot.
                    let slotId = Int(self.context.evaluateScript("GameStorage.currentSlot")?.toInt32() ?? 0)
                    let exported = self.context.evaluateScript(
                        "_nativeExportSlot(\(slotId))"
                    )?.toString() ?? ""
                    cont.resume(returning: exported.isEmpty ? nil : exported)
                }
            }
        }
    }

    /// Compare a few important player fields between two save strings.
    /// Used when byte-comparison fails — surfaces whether the saves are
    /// logically equivalent or genuinely differ in game state. Returns
    /// a short summary.
    @MainActor
    private func compareKeyFields(jsSave: String, wvSave: String) async -> String {
        let escapedJS = jsSave
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        let escapedWV = wvSave
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        return await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            jsQueue.async { [weak self] in
                guard let self = self else { cont.resume(returning: "?"); return }
                let raw = self.context.evaluateScript("""
                (function() {
                    function decimalStr(d) {
                        if (d == null) return 'null';
                        if (typeof d === 'object' && 'mantissa' in d && 'exponent' in d) {
                            return d.mantissa.toFixed(6) + 'e' + d.exponent;
                        }
                        return String(d);
                    }
                    function fields(p) {
                        return {
                            am: decimalStr(p.antimatter),
                            ip: decimalStr(p.infinityPoints),
                            ep: decimalStr(p.eternityPoints),
                            etr: decimalStr(p.eternities),
                            inf: decimalStr(p.infinities),
                            real: p.realities ? String(p.realities) : '0',
                            db: String(p.dimensionBoosts || 0),
                            gx: String(p.galaxies || 0),
                            replGx: String((p.replicanti && p.replicanti.galaxies) || 0),
                            lastUpdate: String(p.lastUpdate || 0),
                            realTimePlayed: String((p.records && p.records.realTimePlayed) || 0)
                        };
                    }
                    try {
                        var a = GameSaveSerializer.deserialize(`\(escapedJS)`);
                        var b = GameSaveSerializer.deserialize(`\(escapedWV)`);
                        if (!a || !b) return JSON.stringify({err: 'deser'});
                        var fa = fields(a), fb = fields(b);
                        var diffs = [];
                        for (var k in fa) {
                            if (fa[k] !== fb[k]) diffs.push(k + ':' + fa[k] + '|' + fb[k]);
                        }
                        return JSON.stringify({same: diffs.length === 0, diffs: diffs});
                    } catch (e) {
                        return JSON.stringify({err: String(e)});
                    }
                })()
                """)?.toString() ?? "{}"
                if let data = raw.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let err = json["err"] as? String {
                        cont.resume(returning: "deser-err:\(err)")
                        return
                    }
                    if json["same"] as? Bool == true {
                        cont.resume(returning: "fields equal")
                        return
                    }
                    let diffs = (json["diffs"] as? [String]) ?? []
                    let summary = diffs.prefix(4).joined(separator: " ; ")
                    cont.resume(returning: "DIFF [\(diffs.count)]: \(summary)")
                    return
                }
                cont.resume(returning: "parse-err")
            }
        }
    }
#endif

    // MARK: - Private

    let jsQueue = DispatchQueue(
        label: "com.antimatter.jscontext",
        qos: PerformanceConfig.jsQueueQoS
    )
    var context: JSContext!  // created on jsQueue in start()
    private var jsQueueState: GameState = .empty  // shadow copy, jsQueue-confined
    private var _jsPollCategory: PollCategory = .dimensions  // jsQueue-confined mirror of visibleTab.pollCategory
    var _jsActiveSubtab: Subtab = .antimatterDimensions  // jsQueue-confined mirror of the active leaf subtab; used to split shared-category polls
    private var _jsProgressFill: Double = 0       // jsQueue-confined mirror of progressFill
    private var _jsPollTickCount: Int = 0         // jsQueue-confined, increments each pollDirect()
    /// Bumped on every resetUnlockFlags(). pollDirect() captures this on
    /// jsQueue when building its header snapshot; the commit closure on main
    /// skips the sticky-true unlock-flag writes if the captured generation no
    /// longer matches. Prevents stale pollDirect commits (in-flight when the
    /// user tapped Hard Reset / Switch Slot / etc.) from re-asserting
    /// tab-visibility flags after they were zeroed. Written from main (in
    /// resetUnlockFlags) and read from jsQueue (in pollDirect) — `Int` writes
    /// are atomic on all supported architectures and we only need the SKIP
    /// side of the race to be eventually-consistent.
    internal var unlockFlagsGen: Int = 0
    internal var _lastQuoteKey: String = ""        // jsQueue-confined, fingerprint used by pollQuoteQueue() to skip redundant JSON reads
    private var _isInitializedInternal: Bool = false // jsQueue-confined, dispatches to main once
    private var backgroundEntryDate: Date?           // set on main, read on jsQueue
    private var backgroundPaused: Bool = false       // jsQueue-confined, blocks timer callbacks
    /// Debug: backdate backgroundEntryDate by 90 minutes on every background entry,
    /// so every foreground return triggers a full offline simulation. Default off.
    var debugFakeOfflineGap: Bool = false

    // MARK: - CADisplayLink-driven polling
    /// UI state extraction is driven by CADisplayLink (synced to display refresh)
    /// instead of the JS game loop TICK. This decouples simulation from rendering,
    /// automatically pauses when backgrounded, and respects Low Power Mode.
    private var displayLink: CADisplayLink?

    private func startDisplayLink() {
        let link = CADisplayLink(target: self, selector: #selector(displayLinkFired))
        // Read persisted refresh rate. Default: 30 Hz both platforms.
        // Key "uiRefreshRate_v2" resets anyone on the old 15 Hz iPhone default to 30 Hz.
        let savedFPS = UserDefaults.standard.integer(forKey: "uiRefreshRate_v2")
        let fps = savedFPS > 0 ? savedFPS : PerformanceConfig.defaultFPS
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: Float(max(fps / 2, 10)),
            maximum: Float(fps),
            preferred: Float(fps)
        )
        link.add(to: .main, forMode: .common)
        displayLink = link
        debugLog("DISPLAY LINK: started at \(fps)fps target")
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        debugLog("DISPLAY LINK: stopped")
    }

    @objc private func displayLinkFired() {
        // Check idle timeout on the main thread (CFAbsoluteTime reads are safe)
        let steps = PerformanceConfig.idleSteps
        if idleStepIndex < steps.count && UserDefaults.standard.bool(forKey: "dynamicThrottling") {
            let elapsed = CFAbsoluteTimeGetCurrent() - lastInteractionTime
            let nextStepAt = idleTimeout * Double(idleStepIndex + 1)
            if elapsed > nextStepAt {
                let prev = idleStepIndex
                idleStepIndex += 1
                debugLog("💤 IDLE STEP-DOWN \(prev) → \(idleStepIndex) (idle for \(String(format: "%.1f", elapsed))s)")
                applyFrameRate()
            }
        }
        jsQueue.async { [self] in
            guard !backgroundPaused, jsPlayer != nil else { return }
            pollDirect()
        }
    }

    // MARK: - Idle & thermal throttling

    /// Tracks last user touch for idle-based frame rate reduction.
    private var lastInteractionTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    /// Current idle step (0 = not throttled, 1..N = progressively slower).
    private var idleStepIndex: Int = 0
    private let idleTimeout: CFTimeInterval = PerformanceConfig.idleTimeout

    /// When thermally throttled, reduce display link frame rate.
    private var thermalThrottled: Bool = false
    private var thermalObserver: NSObjectProtocol?

    private func startThermalMonitoring() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        updateThermalState(ProcessInfo.processInfo.thermalState)
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil, queue: nil
        ) { [weak self] _ in
            self?.updateThermalState(ProcessInfo.processInfo.thermalState)
        }
    }

    private func updateThermalState(_ state: ProcessInfo.ThermalState) {
        let throttle = state == .serious || state == .critical
        guard throttle != thermalThrottled else { return }
        thermalThrottled = throttle
        applyFrameRate()
        debugLog(throttle
            ? "⚠️ Thermal state \(state.rawValue) — throttled"
            : "✅ Thermal state nominal")
    }

    /// Record any user touch — resets idle timer and restores full frame rate.
    func recordInteraction() {
        lastInteractionTime = CFAbsoluteTimeGetCurrent()
        if idleStepIndex > 0 {
            let prev = idleStepIndex
            idleStepIndex = 0
            debugLog("👆 TOUCH STEP-UP \(prev) → 0 (idle throttle cleared)")
            applyFrameRate()
        }
    }

    /// Single source of truth for display link FPS.
    /// Respects user baseline, thermal cap, and idle floor — always picks the lowest.
    private func applyFrameRate() {
        guard let link = displayLink else { return }
        let userFPS = UserDefaults.standard.integer(forKey: "uiRefreshRate_v2")
        let baseFPS = userFPS > 0 ? userFPS : PerformanceConfig.defaultFPS
        let dynamicEnabled = UserDefaults.standard.bool(forKey: "dynamicThrottling")

        var targetFPS = baseFPS
        if thermalThrottled { targetFPS = min(targetFPS, PerformanceConfig.thermalCapFPS) }
        let steps = PerformanceConfig.idleSteps
        if dynamicEnabled && idleStepIndex > 0 && idleStepIndex <= steps.count {
            targetFPS = min(targetFPS, steps[idleStepIndex - 1])
        }

        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: Float(max(targetFPS / 2, 5)),
            maximum: Float(targetFPS),
            preferred: Float(targetFPS)
        )
        debugLog("DISPLAY LINK: applyFrameRate → \(targetFPS)fps (base=\(baseFPS), thermal=\(thermalThrottled), idleStep=\(idleStepIndex)/\(steps.count))")
    }

    // MARK: - Performance instrumentation
    private var perfPollCount: Int = 0
    private var perfTotalMs: Double = 0
    private var perfSectionMs: [String: Double] = [:]
    private var perfLastReport: CFAbsoluteTime = 0
    private var perfEventCount: Int = 0
    /// Master toggle for all performance logging (PERF + JS-PROF lines).
    /// Off by default — call `togglePerfLogging()` to enable. Debug-only effect.
    var _perfLoggingEnabled = false
    #if DEBUG
    private var _jsProfilerInjected = false
    #endif

    /// Maps setInterval/setTimeout IDs → GCD timers (all on jsQueue)
    private var timerMap: [Int32: DispatchSourceTimer] = [:]
    private var nextTimerID: Int32 = 1
    /// De-dupes the `⚠️` diagnostic prints from the celestial-reality and
    /// black-hole-header IIFEs' inner try/catch wraps so a repeated
    /// boot-time failure doesn't spam 30Hz.
    fileprivate var _lastCelestialEvalErr: String = ""
    // _lastBHHeaderEvalErr removed — BH header eval merged into combined celestial eval

    // MARK: - Retained JSValue references (set once in start(), read every tick)

    private var jsCurrencyAM: JSValue!
    private var jsCurrencyIP: JSValue!
    private var jsPlayer: JSValue!
    private var jsDimRefs: [JSValue] = []       // AntimatterDimension(1)...(8)
    private var jsInfDimRefs: [JSValue] = []    // InfinityDimension(1)...(8)
    private var jsTickspeed: JSValue!
    private var jsDimBoost: JSValue!
    private var jsGalaxy: JSValue!
    private var jsSacrifice: JSValue!
    private var jsPlayerProgress: JSValue!
    private var jsAchievements: JSValue!
    private var jsNCRefs: [JSValue] = []       // NormalChallenge(1)...(12)
    private var jsICRefs: [JSValue] = []       // InfinityChallenge(1)...(8)
    private var jsCurrencyEP: JSValue!          // Currency.eternityPoints
    private var jsTimeDimRefs: [JSValue] = []   // TimeDimension(1)...(8)
    private var jsECRefs: [JSValue] = []        // EternityChallenge(1)...(12)
    private var jsIDAutobuyerRefs: [JSValue] = [] // Autobuyer.infinityDimension(1)...(8)
    private var jsTDAutobuyerRefs: [JSValue] = [] // Autobuyer.timeDimension(1)...(8)
    private var jsPlayerObj: JSValue!            // Player (capital P — game's Player global)
    private var jsAntimatterDimensions: JSValue! // AntimatterDimensions
    private var jsFreeTickspeed: JSValue!        // FreeTickspeed
    private var jsAutobuyerBigCrunch: JSValue!   // Autobuyer.bigCrunch
    private var jsInfUpgradeSkipReset: JSValue!  // InfinityUpgrade.skipResetGalaxy
    private var jsEternityChallenge: JSValue!    // EternityChallenge
    private var jsCurrencyTT: JSValue!           // Currency.timeTheorems
    private var jsCurrencyRM: JSValue!           // Currency.realityMachines
    private var jsTimeStudyReality: JSValue!     // TimeStudy.reality
    private var jsTeresa: JSValue!               // Teresa
    private var jsInfinityDimensions: JSValue!   // InfinityDimensions

    /// Pre-formatted soft cap for `Multiply IP by 2`
    /// (`GameDatabase.infinity.upgrades.ipMult.costIncreaseThreshold`).
    /// Constant across the session — read once in `cacheJSRefs()`.
    private var cachedIPMultSoftCapText: String = "1.00e3000000"
    /// Pre-formatted hard cap (`...ipMult.costCap`).
    private var cachedIPMultHardCapText: String = "1.00e6000000"

    /// Sticky cache of the most recent non-empty upcoming-glyph peek.
    /// Substituted into `GlyphsTabState.peekGlyphs` / `.peekLevel` when a poll
    /// returns empty during a Reality reset's transient — automator-driven
    /// Realities reset Time Studies, briefly flipping `TimeStudy.reality.isBought`
    /// false, which clears JS-side peek for the polls between Reality completion
    /// and the automator re-buying the Reality study. Cache is reset on the
    /// save-lifecycle sites (hardReset / importSave / slot-switch / backup-restore).
    private var cachedPeekGlyphs: [GlyphInfo] = []
    private var cachedPeekLevel: Int = 0

    // MARK: - Init

    init() {
        // JSContext is created on jsQueue in start()
        //
        // CloudSaveService is constructed here so it exists by the time
        // any save-signal callback fires. It observes saveSignal (via the
        // engine's _nativeSaveTick hook) and uploads the active slot on a
        // debounce. No iCloud writes happen unless the user has explicitly
        // enabled sync in Options.
        self.cloudSaveService = CloudSaveService(engine: self)
    }

    // MARK: - Shims

    private func setupShims() {
        // 1. Console → Xcode output
        let nativeLog: @convention(block) (String) -> Void = { msg in
            debugLog("JS: \(msg)")
        }
        context.setObject(nativeLog, forKeyedSubscript: "_nativeLog" as NSString)

        // 2. Notification bridge → SwiftUI toast queue.
        //
        // Web message strings often contain `<br>` tags (e.g. the Lai'tela
        // destabilization toast). SwiftUI `Text` renders those literally, so
        // strip HTML tags and collapse `<br>` / `<br/>` into newlines before
        // enqueuing. Also trim any surrounding whitespace.
        let nativeNotify: @convention(block) (String, String) -> Void = { [weak self] type, text in
            let cleaned = GameEngine.sanitizeNotifyText(text)
            DispatchQueue.main.async {
                self?.enqueueToast(type: type, text: cleaned)
            }
        }
        context.setObject(nativeNotify, forKeyedSubscript: "_nativeNotify" as NSString)

        // 2b. Modal.message bridge → non-blocking toast (e.g. C11 matter
        //     annihilation). Shares the HTML sanitizer with `_nativeNotify`
        //     so `<br>` / tags never leak into the UI.
        //
        //     Web's `Modal.message` is a singleton in the modal queue — every
        //     `Modal.message.show()` call mutates the same instance's `.message`
        //     field, so only one message is ever visible at a time. On iOS we
        //     mirror that by tagging these as `"modalMessage"` and replacing
        //     any existing modal-message toast on each call. Without this,
        //     C11 grinding (matter > antimatter triggering once per tick) piles
        //     up identical toasts faster than the 3s auto-dismiss can clear
        //     them, taking over the screen.
        let nativeMessage: @convention(block) (String) -> Void = { [weak self] text in
            let cleaned = GameEngine.sanitizeNotifyText(text, collapseNewlines: true)
            DispatchQueue.main.async {
                self?.enqueueModalMessage(text: cleaned)
            }
        }
        context.setObject(nativeMessage, forKeyedSubscript: "_nativeMessage" as NSString)

        // 2c. Upgrade-lock warning bridge → native confirmation alert. Web's
        //     `Modal.upgradeLock` (UpgradeMechanicLockModal.vue) warns the player
        //     when an action is blocked by a Reality/Imaginary Upgrade requirement
        //     lock and offers to disable the lock. The base Modal stub renders
        //     nothing (null component), so without this the action is blocked with
        //     no feedback. `setupUpgradeLockBridge()` overrides `Modal.upgradeLock.show`
        //     to forward the upgrade's fields here as JSON.
        let nativeUpgradeLock: @convention(block) (String) -> Void = { [weak self] json in
            guard let data = json.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let upgradeId = (obj["id"] as? NSNumber)?.intValue else { return }
            let isImaginary = (obj["isImaginary"] as? Bool) ?? false
            let name = GameEngine.sanitizeNotifyText((obj["name"] as? String) ?? "")
            let lockEvent = GameEngine.sanitizeNotifyText((obj["lockEvent"] as? String) ?? "")
            let requirement = GameEngine.sanitizeNotifyText((obj["requirement"] as? String) ?? "")
            DispatchQueue.main.async {
                self?.activeUpgradeLock = UpgradeLockPrompt(
                    upgradeId: upgradeId, isImaginary: isImaginary,
                    name: name, lockEvent: lockEvent, requirement: requirement)
            }
        }
        context.setObject(nativeUpgradeLock, forKeyedSubscript: "_nativeUpgradeLock" as NSString)

        // 3. DOM / browser environment stubs
        loadJS("browser-shims")

        // 4. localStorage → UserDefaults
        registerLocalStorage()

        // 5. Timers
        registerTimers()
    }

    /// Overrides the JS `Modal.upgradeLock.show` (a null-component no-op in `modal-stub.js`) so the
    /// web's upgrade requirement-lock warning is forwarded to the native `_nativeUpgradeLock` bridge
    /// instead of vanishing. `Modal.upgradeLock` is a session-lifetime singleton, so this runs once
    /// at startup (from `finishStartup`) and survives save loads / slot switches.
    private func setupUpgradeLockBridge() {
        context.evaluateScript(#"""
        (function () {
          try {
            if (typeof Modal === "undefined" || !Modal.upgradeLock) return;
            Modal.upgradeLock.show = function (modalConfig) {
              try {
                var u = modalConfig && modalConfig.upgrade;
                if (!u || typeof _nativeUpgradeLock === "undefined") return;
                var lockEvent = (modalConfig.specialLockText != null) ? modalConfig.specialLockText : u.lockEvent;
                var name = (typeof u.name === "function") ? u.name() : u.name;
                var req = (typeof u.requirement === "function") ? u.requirement() : u.requirement;
                _nativeUpgradeLock(JSON.stringify({
                  id: u.id,
                  isImaginary: !!modalConfig.isImaginary,
                  name: name == null ? "" : String(name),
                  lockEvent: lockEvent == null ? "" : String(lockEvent),
                  requirement: req == null ? "" : String(req)
                }));
              } catch (e) {
                if (typeof _nativeLog !== "undefined") _nativeLog("[upgradeLock.show] " + e);
              }
            };
          } catch (e) {
            if (typeof _nativeLog !== "undefined") _nativeLog("[setupUpgradeLockBridge] " + e);
          }
        })();
        """#)
    }

    private func registerLocalStorage() {
        guard let ls = JSValue(newObjectIn: context) else { return }

        let getItem: @convention(block) (String) -> String? = { key in
            let val = UserDefaults.standard.string(forKey: "am_ls_\(key)")
            if key == "dimensionSave" {
                debugLog("LS GET '\(key)': \(val == nil ? "nil" : "\(val!.count) chars")")
            }
            return val
        }
        let setItem: @convention(block) (String, String) -> Void = { key, value in
            if key == "dimensionSave" {
                debugLog("LS SET '\(key)': \(value.count) chars")
            }
            UserDefaults.standard.set(value, forKey: "am_ls_\(key)")
        }
        let removeItem: @convention(block) (String) -> Void = { key in
            UserDefaults.standard.removeObject(forKey: "am_ls_\(key)")
        }
        let clear: @convention(block) () -> Void = {
            let defaults = UserDefaults.standard
            defaults.dictionaryRepresentation().keys
                .filter { $0.hasPrefix("am_ls_") }
                .forEach { defaults.removeObject(forKey: $0) }
        }

        ls.setObject(getItem,    forKeyedSubscript: "getItem")
        ls.setObject(setItem,    forKeyedSubscript: "setItem")
        ls.setObject(removeItem, forKeyedSubscript: "removeItem")
        ls.setObject(clear,      forKeyedSubscript: "clear")
        context.setObject(ls,    forKeyedSubscript: "localStorage" as NSString)
    }

    private func registerTimers() {
        // setInterval — DispatchSourceTimer on jsQueue
        let setIntervalFn: @convention(block) (JSValue, Double) -> Int32 = { [weak self] callback, ms in
            guard let self else { return -1 }
            let id = self.nextTimerID; self.nextTimerID += 1
            let intervalMs = Int(max(ms, 16))
            let timer = DispatchSource.makeTimerSource(queue: self.jsQueue)
            let leeway = PerformanceConfig.timerLeeway
            timer.schedule(deadline: .now() + .milliseconds(intervalMs),
                          repeating: .milliseconds(intervalMs),
                          leeway: .milliseconds(leeway))
            timer.setEventHandler { [weak self] in
                guard let self, !self.backgroundPaused else { return }
                autoreleasepool {
                    _ = callback.call(withArguments: [])
                }
            }
            timer.resume()
            self.timerMap[id] = timer
            return id
        }
        context.setObject(setIntervalFn, forKeyedSubscript: "setInterval" as NSString)

        let clearIntervalFn: @convention(block) (Int32) -> Void = { [weak self] id in
            self?.timerMap[id]?.cancel()
            self?.timerMap.removeValue(forKey: id)
        }
        context.setObject(clearIntervalFn, forKeyedSubscript: "clearInterval" as NSString)

        // setTimeout — one-shot DispatchSourceTimer on jsQueue
        let setTimeoutFn: @convention(block) (JSValue, Double) -> Int32 = { [weak self] callback, ms in
            guard let self else { return -1 }
            let id = self.nextTimerID; self.nextTimerID += 1
            let delayMs = Int(max(ms, 0))
            let timer = DispatchSource.makeTimerSource(queue: self.jsQueue)
            timer.schedule(deadline: .now() + .milliseconds(delayMs))
            timer.setEventHandler { [weak self] in
                guard let self, !self.backgroundPaused else { return }
                autoreleasepool {
                    _ = callback.call(withArguments: [])
                }
                self.timerMap[id]?.cancel()
                self.timerMap.removeValue(forKey: id)
            }
            timer.resume()
            self.timerMap[id] = timer
            return id
        }
        context.setObject(setTimeoutFn, forKeyedSubscript: "setTimeout" as NSString)

        let clearTimeoutFn: @convention(block) (Int32) -> Void = { [weak self] id in
            self?.timerMap[id]?.cancel()
            self?.timerMap.removeValue(forKey: id)
        }
        context.setObject(clearTimeoutFn, forKeyedSubscript: "clearTimeout" as NSString)
    }

    // MARK: - Bundle loading

    private func loadJS(_ name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            print("🔴 GameEngine: missing \(name).js in app bundle")
            return
        }
        context.evaluateScript(source)
    }

    private func loadBundle() {
        loadJS("game-core-bundle")
    }

    /// JS source for the offline-simulation setup. Computes the tick count
    /// (web's `Math.floor(seconds * 20)` with the fast-path /
    /// `maxOfflineTicks` clamps), awards offline currencies, builds the
    /// `loopFn` (standard or Black-Hole variant), stops `GameIntervals`,
    /// and stores `_offlineSim = { remaining, total, loopFn, seconds }`.
    /// The script returns the tick count.
    ///
    /// Shared between the JSContext path in `runOfflineSimulation` and the
    /// WebView path in `OfflineSimWebView.runOfflineSim` so both contexts
    /// award currencies and compute caps identically. Both paths follow
    /// the user's `player.options.offlineTicks` slider via
    /// `GameStorage.maxOfflineTicks` — no platform-specific override.
    /// Speed up + Skip remain the user's escape hatch when the
    /// JSContext fallback is engaged on a high-slider sim.
    static func offlineSimSetupSource(elapsedSeconds seconds: Double) -> String {
        return """
        (function() {
            var seconds = \(seconds);
            // A negative/NaN duration (future-dated lastUpdate from a corrupted
            // timestamp or a save written by a device with a wrong clock) must
            // not flow into tick math — Math.floor(seconds*20) would go negative
            // and a below-Int.min tick count traps the Swift Int() conversion.
            // You can't simulate backwards in time; clamp to zero (no-op sim).
            if (!isFinite(seconds) || seconds < 0) seconds = 0;

            // The Nameless Ones (Enslaved) real-time storage. iOS runs its own
            // Swift-driven offline sim instead of web's storage.js load path, so
            // the autoStoreReal capture (storage.js:499-501) and the manual
            // isStoringRealTime banking (game.js:404-410 via player.lastUpdate,
            // which iOS resets at init) both have to be reproduced here.
            try {
                if (typeof Enslaved !== 'undefined' && Enslaved.canModifyRealTimeStorage &&
                    player.celestials && player.celestials.enslaved) {
                    var ens = player.celestials.enslaved;
                    var eff = Enslaved.storedRealTimeEfficiency;   // 0.7
                    var cap = Enslaved.storedRealTimeCap;          // 8h (+Ra)
                    var diffMs = seconds * 1000;
                    if (Enslaved.isStoringRealTime) {
                        // Manual store-real left on across a background/quit. Mirror
                        // web's storeRealTime() (game.js:86): web's tick-1 greedily
                        // banks Date.now()-lastUpdate = the WHOLE gap (web never
                        // resets lastUpdate at load; iOS does at init, so the in-tick
                        // capture reads ~0 and we have to bank explicitly here).
                        // seconds is left unchanged so the sim's gameLoop ticks run
                        // DMD/Ra memory. Web's two regimes (storeRealTime cap branch):
                        //  • gap×eff ≤ cap → toggle stays on → all ticks skip
                        //    production → stored time, no production.
                        //  • gap×eff > cap → bank to cap, DISABLE storing → remaining
                        //    ticks run normal production → capped stored + production.
                        // Replicate by flipping isStoringReal off iff the cap is hit.
                        var wouldBe = ens.storedReal + diffMs * eff;
                        if (wouldBe > cap) {
                            ens.storedReal = cap;
                            ens.isStoringReal = false; // overflow → production runs
                        } else {
                            ens.storedReal = wouldBe;
                        }
                        if (ens.storedReal > (24 * 60 * 60 * 1000) && typeof SecretAchievement !== 'undefined') {
                            SecretAchievement(46).unlock();
                        }
                    } else if (diffMs > (5 * 60 * 1000) && ens.autoStoreReal) {
                        // Auto-store real time (mirrors storage.js:499-501). Bank
                        // part of the gap, shorten the simulated duration by the
                        // consumed time. Does NOT touch player.lastUpdate (web's
                        // autoStoreRealTime does, but iOS manages lastUpdate itself).
                        var maxGain = cap - ens.storedReal;
                        var used = Math.min(diffMs, Math.max(0, maxGain / eff));
                        ens.storedReal += used * eff;
                        diffMs -= used;
                        if (ens.storedReal > (24 * 60 * 60 * 1000) && typeof SecretAchievement !== 'undefined') {
                            SecretAchievement(46).unlock();
                        }
                        seconds = diffMs / 1000;
                    }
                }
            } catch (e) {
                if (typeof _nativeLog !== 'undefined') _nativeLog("🔴 offline real-time storage: " + e);
            }

            var ticks = Math.floor(seconds * 20);
            var fast = seconds < 50;
            if (fast) {
                if (ticks > 50) ticks = 50;
            } else {
                var maxTicks = GameStorage.maxOfflineTicks(1000 * seconds,
                    GameStorage.offlineTicks ?? player.options.offlineTicks);
                if (ticks > maxTicks) ticks = maxTicks;
            }

            GameUI.notify.showBlackHoles = false;

            var totalGameTime;
            if (typeof BlackHoles !== 'undefined' && BlackHoles.areUnlocked && !BlackHoles.arePaused) {
                totalGameTime = BlackHoles.calculateGameTimeFromRealTime(seconds, BlackHoles.calculateSpeedups());
            } else {
                totalGameTime = getGameSpeedupFactor() * seconds;
            }

            // Award offline currencies (mirrors simulateTime lines 924-939)
            var infinitiedMilestone = getInfinitiedMilestoneReward(totalGameTime * 1000);
            var eternitiedMilestone = getEternitiedMilestoneReward(totalGameTime * 1000);
            if (eternitiedMilestone.gt(0)) Currency.eternities.add(eternitiedMilestone);
            else if (infinitiedMilestone.gt(0)) Currency.infinities.add(infinitiedMilestone);
            else Currency.eternityPoints.add(getOfflineEPGain(seconds * 1000));

            if (InfinityUpgrade.ipOffline.isBought && player.options.offlineProgress) {
                Currency.infinityPoints.add(
                    player.records.thisEternity.bestIPMsWithoutMaxAll.times(seconds * 1000 / 2));
            }
            EventHub.dispatch(GAME_EVENT.OFFLINE_CURRENCY_GAINED);

            var remainingRealSeconds = seconds;
            var loopFn;
            if (typeof BlackHoles !== 'undefined' && BlackHoles.areUnlocked && !BlackHoles.arePaused) {
                loopFn = function(i) {
                    var result = BlackHoles.calculateOfflineTick(remainingRealSeconds, i, 0.0001);
                    remainingRealSeconds -= result[0];
                    gameLoop(1000 * result[0], { blackHoleSpeedup: result[1] });
                };
            } else {
                loopFn = function(i) {
                    var diff = remainingRealSeconds / i;
                    gameLoop(1000 * diff);
                    remainingRealSeconds -= diff;
                };
            }

            try { GameIntervals.stop(); } catch (e) {}

            _offlineSim = {
                remaining: ticks,
                total: ticks,
                loopFn: loopFn,
                seconds: seconds
            };

            return ticks;
        })()
        """
    }

    /// JS source for the `timesEffectsOf` patch — applied to JSContext in `start()`,
    /// re-applied verbatim inside the JIT bench's WKWebView so the comparison is
    /// over identical Decimal code paths. Replaces the original `new Decimal(v)`
    /// allocation in the effect loop with inline mantissa/exponent decomposition.
    static let timesEffectsOfPatchSource: String = """
    (function() {
        var _origTimesEffectsOf = Decimal.prototype.timesEffectsOf;
        if (!_origTimesEffectsOf) return;
        // Expose original to the DEBUG divergence harness (see browser-shims.js
        // _installDecimalDivergenceHarness). _origDecimalMethods is populated by
        // _patchDecimalPerf, which runs before this patch in start().
        globalThis._origDecimalMethods = globalThis._origDecimalMethods || {};
        if (globalThis._origDecimalMethods.timesEffectsOf === undefined) {
            globalThis._origDecimalMethods.timesEffectsOf = _origTimesEffectsOf;
        }
        var NUMBER_EXP_MIN = -323;
        var _p10Cache = {};
        function _p10(e) {
            if (e >= 0 && e <= 308) return _p10Cache[e] || (_p10Cache[e] = Math.pow(10, e));
            if (e >= -323 && e < 0) return _p10Cache[e] || (_p10Cache[e] = Math.pow(10, e));
            return Math.pow(10, e);
        }
        Decimal.prototype.timesEffectsOf = function() {
            var rM = this.mantissa;
            var rE = this.exponent;
            for (var i = 0; i < arguments.length; i++) {
                var src = arguments[i];
                if (src === null || src === undefined) continue;
                var v;
                if (typeof src.canBeApplied === "boolean") {
                    // Effect-style source — fast inline path.
                    if (!src.canBeApplied) continue;
                    v = src.effectValue;
                } else if (typeof src.applyEffect === "function") {
                    // GlyphEffectState (epMult / ipMult / dimBoostPower) — no
                    // canBeApplied / effectValue; must route through applyEffect
                    // so getAdjustedGlyphEffect + _adjustApply run.
                    var captured;
                    src.applyEffect(function(x) { captured = x; });
                    v = captured;
                } else {
                    continue;
                }
                if (v === undefined || v === null) continue;
                var m, e;
                if (typeof v === "number") {
                    if (v === 1 || v === 0 || !isFinite(v)) continue;
                    e = Math.floor(Math.log10(Math.abs(v)));
                    m = e === NUMBER_EXP_MIN ? v * 10 / 1e-323 : v / _p10(e);
                    if (!(m >= 1 && m < 10) && !(m <= -1 && m > -10)) {
                        var te = Math.floor(Math.log10(Math.abs(m)));
                        m = te === NUMBER_EXP_MIN ? m * 10 / 1e-323 : m / _p10(te);
                        e += te;
                    }
                } else {
                    m = v.mantissa;
                    e = v.exponent;
                }
                rM *= m;
                rE += e;
            }
            return Decimal.fromMantissaExponent(rM, rE);
        };
    })();
    """

    deinit {
        clearAllTimers()
    }

    // MARK: - Start

    func start() {
        UserDefaults.standard.register(defaults: [
            "dynamicThrottling": true,
            // WebView offline-sim is the default path — it's ~6× faster
            // than JSContext at endgame on iPhone, with crash-detection +
            // JSContext fallback. Users can flip it off in Debug if it
            // ever causes trouble.
            "offlineSimUseWebView": true,
            // Button haptic feedback on iPhone (no-op on iPad regardless).
            // Toggle lives in Options → Gameplay.
            "buttonHapticsEnabled": true,
            // GameDecimal C-API fast path. When on, GameDecimal(from:) reads
            // mantissa/exponent via JSObjectGetProperty + JSValueToNumber,
            // skipping the per-call JSValue ObjC wrapper mint. ~50% reduction
            // in init cost. DEBUG builds run both paths and log throttled
            // divergence warnings; Release runs the fast path only.
            "gameDecimalUseCAPI": false,
        ])
        // Refresh the cached flag now that defaults are registered. The flag
        // is read inside the GameDecimal init hot path so we don't want to
        // hit UserDefaults per call — but its lazy module-load initializer
        // may have fired before `register(defaults:)` ran on first launch,
        // returning false for an unset key. Re-read now to pick up the
        // registered default.
        gameDecimalUseCAPIFlag = UserDefaults.standard.bool(forKey: "gameDecimalUseCAPI")
        jsQueue.async { [self] in
            self.context = JSContext()!
            self.context.exceptionHandler = { [weak self] _, exception in
                let msg = exception?.toString() ?? "unknown JS exception"
                print("🔴 JS: \(msg)")
                DispatchQueue.main.async { self?.jsError = msg }
            }
            self.setupShims()
            self.loadBundle()

            // Cache JSStringRef globals for GameDecimal C-API fast path. Idempotent;
            // safe to call on every start() (e.g. after Hot Reload). Strings are held
            // for app lifetime — no per-call refcount churn.
            initializeGameDecimalCAPI()

            // Patch Decimal prototype with native-number fast paths (must run after bundle load,
            // before init — Decimal is provided by webpack ProvidePlugin at bundle eval time)
            self.context.evaluateScript("if (typeof _patchDecimalPerf === 'function') _patchDecimalPerf();")

            // Patch timesEffectsOf to eliminate new Decimal() allocations in the inner loop.
            // The original creates `new Decimal(v)` for every number-typed effect value just
            // to read mantissa/exponent. We decompose numbers inline instead.
            self.context.evaluateScript(GameEngine.timesEffectsOfPatchSource)

            #if DEBUG
            // Decimal divergence harness — DEBUG only. Wraps the patched
            // Decimal methods (including timesEffectsOf) so 1-in-N calls also
            // runs the original and logs any mismatch via _nativeLog. Toggled
            // from Debug tab → "Decimal divergence harness". MUST run after
            // both _patchDecimalPerf and timesEffectsOfPatchSource. Takes
            // effect on next start() (toggle isn't live-applied to avoid
            // re-wrapping already-wrapped methods).
            if UserDefaults.standard.bool(forKey: "decimalDivergenceHarnessEnabled") {
                let everyN = max(1, UserDefaults.standard.integer(forKey: "decimalDivergenceHarnessEveryN"))
                let n = everyN == 0 ? 50 : everyN
                self.context.evaluateScript("if (typeof _installDecimalDivergenceHarness === 'function') _installDecimalDivergenceHarness(\(n));")
            }
            #endif

            // ── Read lastUpdate from UserDefaults BEFORE init() ──
            // JS init() sets GameStorage.offlineEnabled=false → JS else branch →
            // player.lastUpdate = Date.now(), destroying the authentic save timestamp.
            // We persist lastUpdate separately in save() so cold-start can read it.
            let savedLastUpdateMs = UserDefaults.standard.double(forKey: "am_lastUpdate")
            debugLog("COLD START: savedLastUpdateMs from UserDefaults = \(savedLastUpdateMs)")

            // Prevent JS from running its own offline simulation during init —
            // Swift handles it via runOfflineSimulation() after init completes.
            self.context.evaluateScript("GameStorage.offlineEnabled = false;")
            self.context.evaluateScript("init()")
            self.context.evaluateScript("if (typeof GameUI !== 'undefined') GameUI.initialized = true;")
            // Initialize `lastKnownCurrentSlot` from the loaded save now,
            // BEFORE the cold-start offline-sim check. The save-tick
            // callback that normally maintains this value only fires on
            // autosave (post-startup), so without this any path that
            // reads `currentCloudSlotId` between init() and the first
            // autosave (cold-start cloud probe, cold-start offline sim,
            // etc.) sees the stale default of 0 and targets the wrong
            // slot.
            let initialSlot = Int(self.context.evaluateScript("GameStorage.currentSlot")?.toInt32() ?? 0)
            DispatchQueue.main.async { self.lastKnownCurrentSlot = initialSlot }
            self.injectMatterScale()
            self.clearAllTimers()
            self.context.evaluateScript("ui.view.modal.progressBar = undefined;")
            // Disable JS hibernation catchup — Swift handles offline progress natively
            self.context.evaluateScript("player.options.hibernationCatchup = false;")
            // Re-enable JS offline setting for future save imports
            self.context.evaluateScript("GameStorage.offlineEnabled = undefined;")

            // ── Inject helper scripts EARLY ──
            // Normally these run inside `finishStartup()`, but the offline-sim
            // path (which runs async on jsQueue for long gaps) can be
            // interrupted by the app being backgrounded. That triggers
            // `save()` → CloudSaveService → `_nativeExportSlot(...)` which
            // would otherwise ReferenceError because save-helpers.js hasn't
            // loaded yet. Same story for the quote/tesseract poll hooks that
            // fire if a display-link frame sneaks in. Helpers are just global
            // function registrations, safe to install before the simulation
            // runs — they read state when called, not at install time. Calls
            // in `finishStartup()` are kept (idempotent) so the normal path
            // still works and so import/hardReset paths refresh cleanly.
            self.setupNewsHelpers()
            self.setupCelestialHelpers()
            self.setupGameEndHelpers()
            self.setupAutomatorHelpers()
            self.setupSaveHelpers()
            self.setupGlyphPresetHelpers()
            self.setupSpeedrunHelpers()
            self.setupPerksHelper()
            self.setupTimeStudiesHelper()
            self.setupGlyphEffectFormatHelper()
            self.setupHeaderTickHelper()
            self.setupStatisticsAndRelatedHelpers()
            self.setupSecretAchievementsHelper()

            // ── Cold-start offline progress check ──
            // Use the pre-init lastUpdate (from raw save) since init() overwrites
            // player.lastUpdate to Date.now() when offlineEnabled=false.
            // Respect player.options.offlineProgress (matches web storage.js:495).
            let offlineProgressEnabled = self.context.evaluateScript(
                "player.options.offlineProgress"
            )?.toBool() ?? true
            let lastUpdateMs = savedLastUpdateMs
            let nowMs = self.context.evaluateScript("Date.now()")?.toDouble() ?? 0
            if offlineProgressEnabled && lastUpdateMs > 0 && !lastUpdateMs.isNaN && nowMs > lastUpdateMs {
                let rawDiffMs = nowMs - lastUpdateMs
                if rawDiffMs > 10_000 {
                    // Before running offline simulation against local, see
                    // if iCloud has a strictly newer save for this slot. If
                    // so, swap it in first so offline progress is computed
                    // against the right baseline. Otherwise the user plays
                    // through an offline sim on stale data and we'd have
                    // to throw it away moments later when the foreground
                    // cloud check lands.
                    let (swappedLastUpdateMs, didSwap) = self.maybeAdoptNewerCloudSaveAtStartup(
                        localLastUpdateMs: lastUpdateMs
                    )

                    let effectiveLastUpdateMs = didSwap ? swappedLastUpdateMs : lastUpdateMs
                    let nowMsAgain = self.context.evaluateScript("Date.now()")?.toDouble() ?? 0
                    let effectiveDiffMs = nowMsAgain - effectiveLastUpdateMs

                    if didSwap {
                        debugLog("COLD START: adopted newer cloud save, recomputed gap = \(String(format: "%.0f", effectiveDiffMs))ms")
                    }

                    if effectiveDiffMs > 10_000 {
                        let elapsed = effectiveDiffMs / 1000.0
                        debugLog("COLD START: offline gap = \(String(format: "%.1f", elapsed))s")
                        self.runOfflineSimulation(elapsed: elapsed, isStartup: true)
                        return  // finishStartup() called by runOfflineSimulation on completion
                    } else {
                        debugLog("COLD START: post-swap gap < 10s, skipping simulation")
                    }
                } else {
                    debugLog("COLD START: offline gap \(String(format: "%.0f", rawDiffMs))ms < 10s, skipping")
                }
            }

            self.finishStartup()
        }
    }

    /// Completes startup after optional offline simulation.
    /// Must be called on jsQueue.
    private func finishStartup() {
        self.injectDebugSpeedWrapper()
        #if DEBUG
        if _perfLoggingEnabled {
            injectGameLoopProfiler()
            _jsProfilerInjected = true
            context.evaluateScript("gameLoop._profEnabled = true")
        }
        #endif
        self.injectEventBridge()
        self.setupUpgradeLockBridge()
        // Log the save file's updateRate (user may have changed it in Options)
        let savedRate = self.context.evaluateScript("player.options.updateRate")?.toInt32() ?? 33
        debugLog("INIT: updateRate = \(savedRate)ms from save (web default is 33ms)")
        self.cacheJSRefs()
        self.setupNewsHelpers()
        self.setupCelestialHelpers()
        self.setupGameEndHelpers()
        self.setupAutomatorHelpers()
        self.setupSaveHelpers()
        self.setupGlyphPresetHelpers()
        self.setupSpeedrunHelpers()
        self.setupPerksHelper()
        self.setupTimeStudiesHelper()
        self.setupGlyphEffectFormatHelper()
        self.setupHeaderTickHelper()
        self.setupStatisticsAndRelatedHelpers()
        self.setupSecretAchievementsHelper()
        self.pollDirect()
        // One-time new-player onboarding: surface the welcome flow only for a
        // truly fresh save (default start, ~no progress) that hasn't already
        // seen or declined onboarding on this device. The UserDefaults flag is
        // set the moment the player answers the welcome prompt, so this never
        // re-fires. importSave/hardReset/slot-switch don't run finishStartup so
        // this is boot-only by construction.
        if !UserDefaults.standard.bool(forKey: "am_hasSeenOnboarding") {
            let isFresh = self.context.evaluateScript("""
                (function(){ try {
                    return player.records.totalAntimatter.lte(10)
                        && player.infinities.eq(0)
                        && player.records.realTimePlayed < 5000;
                } catch (e) { return false; } })()
                """)?.toBool() ?? false
            if isFresh {
                DispatchQueue.main.async { [weak self] in
                    self?.onboarding = OnboardingState(phase: .welcome)
                }
            }
        }
        // pollDirect dispatches isInitialized = true to main
        DispatchQueue.main.async { [self] in
            self.startDisplayLink()
            self.recordInteraction()  // launch at full user rate
            // Register with the shared interaction tracker so GameButton
            // taps, tab selections, and other discrete UI action surfaces
            // can reset the idle clock without holding an engine reference.
            InteractionTracker.shared.recordTouch = { [weak self] in
                self?.recordInteraction()
            }
            // Kick off a cloud compare now that save-helpers.js is loaded
            // and JS refs are cached. Covers the cold-start case where
            // scenePhase starts at .active and therefore `.onChange` never
            // fires — without this, a cloud state that needs the full
            // compare (different name, hash mismatch, etc.) wouldn't be
            // checked until the user backgrounds and foregrounds.
            // No-ops if sync is disabled; de-dup guards prevent duplicate
            // work if the KVS notification path also fires.
            self.cloudSaveService?.handleForegroundReturn()
        }
        self.startThermalMonitoring()
    }

    // MARK: - Onboarding

    /// Persist that the player has seen (or declined) the new-player onboarding.
    /// Called the moment they answer the welcome prompt — whether they opt in or
    /// out — so the flow never re-shows on this device. Stored in UserDefaults
    /// (not the save) so it's a per-install first-run signal; survives hard reset.
    func markOnboardingSeen() {
        UserDefaults.standard.set(true, forKey: "am_hasSeenOnboarding")
    }

    /// Advance the callout sequence by one step; clears `onboarding` once the
    /// last step is dismissed. Safe to call from the main actor (view layer).
    func advanceOnboardingCallout() {
        guard var state = onboarding else { return }
        state.calloutStep += 1
        if state.calloutStep >= OnboardingState.calloutCount {
            onboarding = nil
        } else {
            onboarding = state
        }
    }

    #if DEBUG
    /// Debug helper: clear the persistent "seen" flag and re-show the welcome
    /// flow immediately, bypassing the fresh-save check. Lets us re-test the
    /// onboarding flow without deleting the app (the flag normally survives
    /// even a Hard Reset).
    func devReArmOnboarding() {
        UserDefaults.standard.removeObject(forKey: "am_hasSeenOnboarding")
        // Navigate to Antimatter Dimensions so the welcome flow + callouts have
        // their anchor targets (dimension row, counter, tab nav) on screen.
        if let sidebar = sidebarStateRef {
            sidebar.selectTab(.dimensions, engine: self)
            sidebar.selectSubtab(.antimatterDimensions, in: .dimensions, engine: self)
        }
        onboarding = OnboardingState(phase: .welcome)
    }
    #endif

    // MARK: - JSValue reference caching

    internal func cacheJSRefs() {
        // Clear the sticky upcoming-glyph peek cache. cacheJSRefs runs at every
        // save-lifecycle boundary (boot, hardReset, importSave, slot-switch,
        // backup-restore, offline-sim apply) so this is the single chokepoint
        // for invalidating cross-save state.
        cachedPeekGlyphs = []
        cachedPeekLevel = 0

        jsCurrencyAM = context.evaluateScript("Currency.antimatter")
        jsCurrencyIP = context.evaluateScript("Currency.infinityPoints")
        jsPlayer = context.evaluateScript("player")
        jsTickspeed = context.objectForKeyedSubscript("Tickspeed")
        jsDimBoost = context.objectForKeyedSubscript("DimBoost")
        jsGalaxy = context.objectForKeyedSubscript("Galaxy")
        jsSacrifice = context.objectForKeyedSubscript("Sacrifice")
        jsPlayerProgress = context.objectForKeyedSubscript("PlayerProgress")
        jsAchievements = context.objectForKeyedSubscript("Achievements")

        jsDimRefs = (1...8).map { context.evaluateScript("AntimatterDimension(\($0))") ?? JSValue(undefinedIn: context) }
        jsInfDimRefs = (1...8).map { context.evaluateScript("InfinityDimension(\($0))") ?? JSValue(undefinedIn: context) }
        jsNCRefs = (1...12).map { context.evaluateScript("NormalChallenge(\($0))") ?? JSValue(undefinedIn: context) }
        jsICRefs = (1...8).map { context.evaluateScript("InfinityChallenge(\($0))") ?? JSValue(undefinedIn: context) }
        jsCurrencyEP = context.evaluateScript("Currency.eternityPoints")
        jsTimeDimRefs = (1...8).map { context.evaluateScript("TimeDimension(\($0))") ?? JSValue(undefinedIn: context) }
        jsECRefs = (1...12).map { context.evaluateScript("EternityChallenge(\($0))") ?? JSValue(undefinedIn: context) }
        // Autobuyer factory functions return singleton instances per tier — same
        // shape as AntimatterDimension(i) / InfinityDimension(i). Caching the
        // refs eliminates 16 evaluateScript trampolines per tick on the ID/TD
        // and Autobuyers tabs.
        jsIDAutobuyerRefs = (1...8).map { context.evaluateScript("Autobuyer.infinityDimension(\($0))") ?? JSValue(undefinedIn: context) }
        jsTDAutobuyerRefs = (1...8).map { context.evaluateScript("Autobuyer.timeDimension(\($0))") ?? JSValue(undefinedIn: context) }
        jsPlayerObj = context.objectForKeyedSubscript("Player")
        jsAntimatterDimensions = context.objectForKeyedSubscript("AntimatterDimensions")
        jsFreeTickspeed = context.objectForKeyedSubscript("FreeTickspeed")
        jsAutobuyerBigCrunch = context.evaluateScript("Autobuyer.bigCrunch")
        jsInfUpgradeSkipReset = context.evaluateScript("InfinityUpgrade.skipResetGalaxy")
        jsEternityChallenge = context.objectForKeyedSubscript("EternityChallenge")
        jsCurrencyTT = context.evaluateScript("Currency.timeTheorems")
        jsCurrencyRM = context.evaluateScript("Currency.realityMachines")
        jsTimeStudyReality = context.evaluateScript("TimeStudy.reality")
        jsTeresa = context.objectForKeyedSubscript("Teresa")
        jsInfinityDimensions = context.objectForKeyedSubscript("InfinityDimensions")

        // IP multiplier soft/hard caps — `GameDatabase` constants.
        // Used by the Infinity Upgrades tab "cap details" disclosure.
        if let ipMultDB = context.evaluateScript("GameDatabase.infinity.upgrades.ipMult") {
            let softVal = ipMultDB.forProperty("costIncreaseThreshold")
            let hardVal = ipMultDB.forProperty("costCap")
            cachedIPMultSoftCapText = formatDecimal(GameDecimal(from: softVal))
            cachedIPMultHardCapText = formatDecimal(GameDecimal(from: hardVal))
        }
    }

    /// Snapshot of header values to dispatch to main thread
    private struct HeaderSnapshot {
        let antimatter, antimatterPerSec: String
        let progressFill: Double
        let tickspeedUnlocked, infinityUnlocked, autobuyersUnlocked: Bool
        let tickspeedMultiplier, tickspeedPerSecond, currentIP: String
        let replicantiAmount: String
        let replicantiUnlocked: Bool
        let challengeDisplayText: String
        let challengePowerText: String
        let quickResetAvailable: Bool
        let quickResetHasBoosts: Bool
        let blackHolesHeaderVisible: Bool
        let blackHoleHeaderPauseText: String
        let blackHoleHeaderStates: [String]
        let blackHolesHeaderPermanent: Bool
        let blackHolesHeaderPaused: Bool
        let headerEnslavedChargeVisible: Bool
        let headerEnslavedIsCharging: Bool
    }

    /// Read all game state via direct JSValue property access, driven by JS game loop tick.
    /// Runs on jsQueue. Builds Swift value types, dispatches to main for @Observable commit.
    internal func pollDirect() {
      guard jsPlayer != nil else { return }
      autoreleasepool {
        let pollStart = CFAbsoluteTimeGetCurrent()
        var state = jsQueueState
        let cat = _jsPollCategory
        _jsPollTickCount &+= 1

        // --- Header (compute locally, dispatch to main) ---
        let amValue = jsCurrencyAM.forProperty("value")
        let am = GameDecimal(from: amValue)
        let newAM = formatDecimal(am, places: 2, placesUnder1000: 2)
        let newAMPerSec = formatDecimal(GameDecimal(from: jsCurrencyAM.forProperty("productionPerSecond")), places: 2, placesUnder1000: 2)

        // Progress bar fill — mirrors AntimatterDimensionProgressBar.vue update() logic.
        // Computed in JS to handle challenges, break infinity, and other special goals.
        // Throttled to every 3rd tick — visual change rate is slow enough that 10Hz is smooth.
        let newFill: Double
        if _jsPollTickCount % 3 == 0 {
        newFill = context.evaluateScript("""
            (function() {
                // Full port of `AntimatterDimensionProgressBar.vue.update()`.
                // Two helpers mirror web:
                //   logP(current, goal) → current.pLog10() / log10(goal)
                //   linP(current, goal) → current / goal
                function logP(current, goal) {
                    if (!current || !goal) return 0;
                    var lg = (typeof goal === 'number') ? Math.log10(goal) : Decimal.log10(goal);
                    if (!isFinite(lg) || lg <= 0) return 0;
                    var pl = (typeof current === 'number') ? (current > 0 ? Math.log10(current) : 0) : current.pLog10();
                    if (!isFinite(pl)) return 0;
                    return Math.min(Math.max(pl / lg, 0), 1);
                }
                function linP(current, goal) {
                    if (!goal) return 0;
                    var r = current / goal;
                    if (!isFinite(r)) return 0;
                    return Math.min(Math.max(r, 0), 1);
                }

                // 1. Special runs (AD challenge / EC / Dilation active / Lai'tela)
                //    — prioritised top-down so challenge-scale goals show first.
                var inSpecialRun = Player.isInAntimatterChallenge
                    || (typeof EternityChallenge !== 'undefined' && EternityChallenge.isRunning)
                    || player.dilation.active
                    || (typeof Laitela !== 'undefined' && Laitela.isRunning);
                if (inSpecialRun) {
                    if (Player.isInAntimatterChallenge) {
                        return logP(Currency.antimatter.value, Player.antimatterChallenge.goal);
                    }
                    if (typeof EternityChallenge !== 'undefined' && EternityChallenge.isRunning) {
                        if (typeof Perk !== 'undefined' && Perk.studyECBulk && Perk.studyECBulk.isBought) {
                            try {
                                var nextGoal = EternityChallenge.current.gainedCompletionStatus.nextGoalAt;
                                if (nextGoal) return logP(Currency.infinityPoints.value, nextGoal);
                                return logP(Currency.infinityPoints.value, 10); // fully complete → pin 100%
                            } catch (e) {
                                return logP(Currency.infinityPoints.value, Player.eternityGoal);
                            }
                        }
                        return logP(Currency.infinityPoints.value, Player.eternityGoal);
                    }
                    if (player.dilation.active) {
                        if (player.dilation.lastEP && player.dilation.lastEP.gt && player.dilation.lastEP.gt(0)) {
                            return logP(Currency.antimatter.value, getTachyonReq());
                        }
                        return logP(Currency.infinityPoints.value, Player.eternityGoal);
                    }
                    // Lai'tela destabilisation — log scale means pow10(entropy)/10
                    // collapses to entropy directly.
                    var e = player.celestials.laitela.entropy || 0;
                    return Math.min(Math.max(e, 0), 1);
                }

                // 2. Pelle (Doomed). Multiple strike-ordered branches.
                if (typeof Pelle !== 'undefined' && Pelle.isDoomed) {
                    try {
                        if ((typeof PelleRifts !== 'undefined' && PelleRifts.recursion
                             && PelleRifts.recursion.milestones[2]
                             && PelleRifts.recursion.milestones[2].canBeApplied)
                            || (typeof GalaxyGenerator !== 'undefined' && GalaxyGenerator.spentGalaxies > 0)) {
                            return logP(Currency.infinityPoints.value, Tesseracts.nextCost);
                        }
                        if (typeof PelleStrikes !== 'undefined') {
                            if (PelleStrikes.dilation && PelleStrikes.dilation.hasStrike) {
                                return logP(Currency.eternityPoints.value, Decimal.pow10(4000));
                            }
                            if (PelleStrikes.ECs && PelleStrikes.ECs.hasStrike) {
                                var ttPart = Math.min(Currency.timeTheorems.max.toNumber() / 12900, 1);
                                var ecPart = Math.min(EternityChallenges.completions / 60, 1);
                                return linP((ttPart + ecPart) / 2, 1);
                            }
                            if (PelleStrikes.eternity && PelleStrikes.eternity.hasStrike) {
                                return linP(Currency.timeTheorems.max.toNumber(), 115);
                            }
                            if (PelleStrikes.powerGalaxies && PelleStrikes.powerGalaxies.hasStrike) {
                                return logP(Currency.infinityPoints.value, Player.eternityGoal);
                            }
                            if (PelleStrikes.infinity && PelleStrikes.infinity.hasStrike) {
                                if (player.break) {
                                    return logP(Currency.infinityPoints.value, 5e11);
                                }
                                return logP(Currency.antimatter.value, Decimal.NUMBER_MAX_VALUE);
                            }
                        }
                        return logP(Currency.antimatter.value, Decimal.NUMBER_MAX_VALUE);
                    } catch (err) {
                        return logP(Currency.antimatter.value, Decimal.NUMBER_MAX_VALUE);
                    }
                }

                // 3. Post-Enslaved completion → next Tesseract (IP-priced).
                if (typeof Enslaved !== 'undefined' && Enslaved.isCompleted
                    && typeof Tesseracts !== 'undefined' && Tesseracts.nextCost) {
                    return logP(Currency.infinityPoints.value, Tesseracts.nextCost);
                }

                // 4. Dilation unlocked (not active) → EP to 1e4000 (Reality).
                if (typeof PlayerProgress !== 'undefined' && PlayerProgress.dilationUnlocked
                    && PlayerProgress.dilationUnlocked()) {
                    return logP(Currency.eternityPoints.value, Decimal.pow10(4000));
                }

                // 5. ID8 unlocked → IP to eternityGoal.
                if (typeof InfinityDimension !== 'undefined' && InfinityDimension(8).isUnlocked) {
                    return logP(Currency.infinityPoints.value, Player.eternityGoal);
                }

                // 6. Break Infinity → next ID unlock requirement.
                if (player.break) {
                    var nextID = InfinityDimensions.next();
                    if (nextID) {
                        if (nextID.ipRequirementReached) {
                            return logP(player.records.thisEternity.maxAM, nextID.amRequirement);
                        }
                        return logP(Currency.infinityPoints.value, new Decimal(nextID.ipRequirement));
                    }
                    return logP(Currency.antimatter.value, Decimal.NUMBER_MAX_VALUE);
                }

                // 7. Default: percentage to Infinity.
                return logP(Currency.antimatter.value, Decimal.NUMBER_MAX_VALUE);
            })()
            """)?.toDouble() ?? _jsProgressFill
        } else {
            newFill = _jsProgressFill
        }
        // Safety clamp — guard against NaN/Infinity from JS edge cases
        let newFillClamped = newFill.isFinite ? min(max(newFill, 0), 1) : _jsProgressFill

        let infUnlocked = jsPlayerProgress.invokeMethod("infinityUnlocked", withArguments: [])?.toBool() ?? false
        state.buyUntil10 = jsPlayer.forProperty("buyUntil10")?.toBool() ?? true

        let totalBoosts = clampedInt(jsDimBoost.forProperty("totalBoosts")?.toDouble() ?? 0)
        let purchasedBoosts = clampedInt(jsDimBoost.forProperty("purchasedBoosts")?.toDouble() ?? 0)
        state.dimBoostCount = totalBoosts

        // --- Dimension-tab-gated polling (buy10, dimension rows, boost/galaxy/sacrifice) ---
        // These are only displayed on the Dimensions tab. Gating saves ~120 bridge crossings/tick
        // on all other tabs. State freezes at last-polled values (jsQueueState) until user returns.
        if cat == .dimensions {

        let buy10Mult = GameDecimal(from: jsAntimatterDimensions.forProperty("buyTenMultiplier"))
        state.buy10Mult = formatX(buy10Mult, places: 2, placesUnder1000: 2)

        // C6 swaps each AD's purchase currency to the dimension two tiers below
        // it (tier ≥ 3). When C6 is running, the cost label suffix changes from
        // "AM" to e.g. "1st AD". Mirrors `ModernAntimatterDimensionRow.vue`.
        let isC6Running = jsNCRefs[5].forProperty("isRunning")?.toBool() ?? false

        let buyUntil10 = state.buyUntil10
        for i in 0..<8 {
            let d = jsDimRefs[i]
            let tier = i + 1
            let totalAmount = GameDecimal(from: d.forProperty("totalAmount"))
            let costJSVal = d.forProperty("cost")
            let cost = GameDecimal(from: costJSVal)
            let multiplier = GameDecimal(from: d.forProperty("multiplier"))
            let howMany = clampedInt(d.forProperty("howManyCanBuy")?.toDouble() ?? 0)
            let isAvailable = d.forProperty("isAvailableForPurchase")?.toBool() ?? false
            let isAffordable = d.forProperty("isAffordable")?.toBool() ?? false
            let isAffordableUntil10 = d.forProperty("isAffordableUntil10")?.toBool() ?? false
            let boughtBefore10 = clampedInt(d.forProperty("boughtBefore10")?.toDouble() ?? 0)
            let bought = clampedInt(d.forProperty("bought")?.toDouble() ?? 0)
            let continuumValue = d.forProperty("continuumValue")?.toDouble() ?? 0

            let isVisible = (totalBoosts > 0 && totalBoosts + 3 >= tier) || infUnlocked || isAvailable || totalAmount.mantissa > 0

            let effectiveHowMany = buyUntil10 ? howMany : min(howMany, 1)

            // until10Cost = cost * max(howMany, 1) — multiply via JS Decimal to avoid overflow
            let until10CostJSVal = costJSVal?.invokeMethod("times", withArguments: [max(howMany, 1)])
            let until10Cost = GameDecimal(from: until10CostJSVal)

            var rateOfChange: String? = nil
            if tier < 8 {
                let roc = GameDecimal(from: d.forProperty("rateOfChange"))
                rateOfChange = formatDecimal(roc, places: 2, placesUnder1000: 2)
            }

            let costSuffix: String = (isC6Running && tier >= 3)
                ? "\(DimensionState.safeTierName(tier - 2)) AD"
                : "AM"

            state.dimensions[i] = DimensionState(
                tier: tier,
                isVisible: isVisible,
                isAvailableForPurchase: isAvailable,
                amount: tier < 8 ? formatDecimal(totalAmount, places: 2) : formatInt(totalAmount),
                multiplier: formatX(multiplier, places: 2, placesUnder1000: 2),
                boughtBefore10: boughtBefore10,
                bought: bought,
                howManyCanBuy: effectiveHowMany,
                singleCost: formatDecimal(cost),
                until10Cost: formatDecimal(until10Cost),
                costSuffix: costSuffix,
                isAffordable: isAffordable,
                isAffordableUntil10: isAffordableUntil10,
                rateOfChange: rateOfChange,
                continuumValue: continuumValue
            )
        }

        } // end cat == .dimensions gate (buy10 + dimension rows)

        // --- Tickspeed (always-on — header shows multiplier + per-second) ---
        let tsUnlocked = jsTickspeed.forProperty("isUnlocked")?.toBool() ?? false
        let tsCost = GameDecimal(from: jsTickspeed.forProperty("cost"))
        let tsMultRecip = GameDecimal(from: jsTickspeed.forProperty("multiplier")?.invokeMethod("reciprocal", withArguments: []))
        let tsPerSec = GameDecimal(from: jsTickspeed.forProperty("perSecond"))
        let tsAvailable = jsTickspeed.forProperty("isAvailableForPurchase")?.toBool() ?? false
        let tsAffordable = jsTickspeed.forProperty("isAffordable")?.toBool() ?? false

        let tsContinuumValue = jsTickspeed.forProperty("continuumValue")?.toDouble() ?? 0
        state.tickspeed = TickspeedState(
            isUnlocked: tsUnlocked,
            cost: formatDecimal(tsCost),
            multiplier: formatX(tsMultRecip, places: 2, placesUnder1000: 3),
            perSecond: formatDecimal(tsPerSec, places: 2, placesUnder1000: 3),
            isAffordable: tsAvailable && tsAffordable,
            purchasedCount: clampedInt(jsPlayer.forProperty("totalTickBought")?.toDouble() ?? 0),
            freeCount: clampedInt(jsFreeTickspeed.forProperty("amount")?.toDouble() ?? 0),
            continuumValue: tsContinuumValue
        )

        // --- Dim Boost / Galaxy / Sacrifice (dimensions-tab-gated) ---
        if cat == .dimensions {

        let boostReq = jsDimBoost.forProperty("requirement")
        let boostReqTier = Int(boostReq?.forProperty("tier")?.toInt32() ?? 4)
        let boostReqAmount = Int(boostReq?.forProperty("amount")?.toDouble() ?? 20)
        let boostReqSatisfied = boostReq?.forProperty("isSatisfied")?.toBool() ?? false

        state.dimBoost = DimBoostState(
            purchasedBoosts: purchasedBoosts,
            requirementTier: boostReqTier,
            requirementAmount: boostReqAmount,
            isSatisfied: boostReqSatisfied,
            canBeBought: jsDimBoost.forProperty("canBeBought")?.toBool() ?? false,
            unlockedByBoost: { let s = extractNormalizedString(from: jsDimBoost.forProperty("unlockedByBoost")); return s.isEmpty ? nil : s }(),
            lockText: { let lt = jsDimBoost.forProperty("lockText"); return lt?.isNull == true ? nil : lt?.toString() }()
        )

        // --- Galaxy ---
        let galaxyReq = jsGalaxy.forProperty("requirement")
        let galaxyReqTier = Int(galaxyReq?.forProperty("tier")?.toInt32() ?? 8)
        let galaxyReqAmount = Int(galaxyReq?.forProperty("amount")?.toDouble() ?? 80)
        let galaxyReqSatisfied = galaxyReq?.forProperty("isSatisfied")?.toBool() ?? false

        // Mirrors `ModernAntimatterGalaxyRow.vue` `typeName` + `sumText`. JS-side
        // because `Galaxy.type` factors in TS302/TS223/TS224/EC5/glyph sac (Distant
        // threshold) + RU21 (Remote threshold), and `Replicanti.galaxies.total`
        // bundles `bought + extra` from TS225/226 etc.
        var galaxyTypeName = "Antimatter Galaxies"
        var galaxyCountDisplay = "0"
        if let raw = context.evaluateScript("""
        (function(){
          try {
            const t = Galaxy.type;
            let typeName = 'Antimatter Galaxies';
            if (t === GALAXY_TYPE.REMOTE) typeName = 'Remote Antimatter Galaxies';
            else if (t === GALAXY_TYPE.DISTANT) typeName = 'Distant Antimatter Galaxies';
            const normal = Math.max(player.galaxies, 0);
            const replicanti = (Replicanti.galaxies && Replicanti.galaxies.total) || 0;
            const dilation = (player.dilation && player.dilation.totalTachyonGalaxies) || 0;
            const parts = [normal];
            if (replicanti > 0) parts.push(replicanti);
            if (dilation > 0) parts.push(dilation);
            const sum = parts.map(formatInt).join(' + ');
            let countDisplay = sum;
            if (parts.length >= 2) {
              const total = parts.reduce(function(a,b){ return a+b; }, 0);
              countDisplay = sum + ' = ' + formatInt(total);
            }
            return JSON.stringify({ typeName: typeName, countDisplay: countDisplay });
          } catch(e) { return ''; }
        })()
        """)?.toString(), let data = raw.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            galaxyTypeName = obj["typeName"] ?? galaxyTypeName
            galaxyCountDisplay = obj["countDisplay"] ?? galaxyCountDisplay
        }

        state.galaxy = GalaxyState(
            count: clampedInt(jsPlayer.forProperty("galaxies")?.toDouble() ?? 0),
            typeName: galaxyTypeName,
            countDisplay: galaxyCountDisplay,
            requirementTier: galaxyReqTier,
            requirementAmount: galaxyReqAmount,
            isSatisfied: galaxyReqSatisfied,
            canBeBought: jsGalaxy.forProperty("canBeBought")?.toBool() ?? false,
            lockText: { let lt = jsGalaxy.forProperty("lockText"); return lt?.isNull == true ? nil : lt?.toString() }()
        )

        // --- Sacrifice ---
        let sacVisible = jsSacrifice.forProperty("isVisible")?.toBool() ?? false
        state.isSacrificeUnlocked = sacVisible
        state.canSacrifice = jsSacrifice.forProperty("canSacrifice")?.toBool() ?? false
        // Achievement 118: once sacrifice autobuyer is active, manual sacrifice
        // button is effectively replaced. Mirrors web `isFullyAutomated`.
        state.sacrificeIsAutomated = sacVisible
            && (context.evaluateScript("Achievement(118).isUnlocked && Autobuyer.sacrifice.isActive")?.toBool() ?? false)
        if sacVisible {
            let totalBoost = GameDecimal(from: jsSacrifice.forProperty("totalBoost"))
            state.sacrificeMultiplier = formatX(totalBoost, places: 2, placesUnder1000: 2)
            let nextBoost = GameDecimal(from: jsSacrifice.forProperty("nextBoost"))
            state.sacrificeNextBoost = formatX(nextBoost, places: 2, placesUnder1000: 2)
            if !state.canSacrifice {
                state.sacrificeDisabledReason = jsSacrifice.forProperty("disabledCondition")?.toString()
            } else {
                state.sacrificeDisabledReason = nil
            }
        } else {
            state.sacrificeMultiplier = nil
            state.sacrificeNextBoost = nil
            state.sacrificeDisabledReason = nil
        }

        } // end cat == .dimensions gate (boost + galaxy + sacrifice)

        // --- Infinity header (always needed for header IP display + Big Crunch button) ---
        let canCrunch = jsPlayerObj.forProperty("canCrunch")?.toBool() ?? false
        let gainedIP = GameDecimal(from: context.evaluateScript("gainedInfinityPoints()"))
        let currentIPVal = GameDecimal(from: jsCurrencyIP.forProperty("value"))
        let infGoal = GameDecimal(from: jsPlayerObj.forProperty("infinityGoal"))
        // Use web's `PlayerProgress.hasBroken()` rather than reading
        // `player.break` directly. The raw flag flips false after Armageddon
        // resets the post-doom Eternity layer, but the web getter stays true
        // because it OR's in `isEternityUnlocked` / `isRealityUnlocked` —
        // both permanent. Without this, every UI gate keyed on `isBroken`
        // (e.g. the IC subtab) regresses post-Armageddon. See the "Pelle
        // (Doomed Reality)" / "Subtab visibility gates that intersect with
        // doom" sections in the design notes.
        let isBroken = jsPlayerProgress.invokeMethod("hasBroken", withArguments: [])?.toBool() ?? false
        // `PlayerProgress.infinityUnlocked()` — gates the iPhone-only
        // `showBigCrunchTakeoverFirstOnly` (takeover suppresses post-first-
        // crunch) and the `CompactPrestigeRow` post-first-crunch crunch
        // button. Monotonic per-save (only ever flips false→true).
        let infinityUnlockedFlag = jsPlayerProgress.invokeMethod("infinityUnlocked", withArguments: [])?.toBool() ?? false
        let bestInfTimeMs = jsPlayer.forProperty("records")?.forProperty("bestInfinity")?.forProperty("time")?.toDouble() ?? 1e12
        state.infinity.canCrunch = canCrunch
        state.infinity.isBroken = isBroken
        state.infinity.infinityUnlocked = infinityUnlockedFlag
        state.infinity.bestInfinityMs = bestInfTimeMs
        state.infinity.gainedIP = formatDecimal(gainedIP, places: 2)
        state.infinity.currentIP = formatDecimal(currentIPVal, places: 2)
        state.infinity.hasIP = currentIPVal.mantissa > 0
        state.infinity.infinityGoal = formatDecimal(infGoal)
        state.infinity.bigCrunchAutobuyerActive = jsAutobuyerBigCrunch.forProperty("isActive")?.toBool() ?? false
        state.infinity.bigCrunchAutobuyerUnlocked = jsAutobuyerBigCrunch.forProperty("isUnlocked")?.toBool() ?? false
        let abGloballyOn = jsPlayer.forProperty("auto")?.forProperty("autobuyersOn")?.toBool() ?? true
        state.infinity.autobuyersGloballyOn = abGloballyOn
        state.infinity.inAntimatterChallenge = jsPlayerObj.forProperty("isInAntimatterChallenge")?.toBool() ?? false

        // Big Crunch modal starting resources
        let gainedInf = GameDecimal(from: context.evaluateScript("gainedInfinities()"))
        state.infinity.gainedInfinities = formatDecimal(gainedInf, places: 2)
        let startAM = GameDecimal(from: jsCurrencyAM.forProperty("startingValue"))
        state.infinity.startingAM = (startAM.exponent >= 1 || startAM.mantissa > 1) ? formatDecimal(startAM, places: 2, placesUnder1000: 1) : nil
        state.infinity.startingBoosts = Int(jsDimBoost.forProperty("startingDimensionBoosts")?.toDouble() ?? 0)
        state.infinity.startWithGalaxy = jsInfUpgradeSkipReset.forProperty("isBought")?.toBool() ?? false

        // IP rate display for Big Crunch button (shown when peakIPRate <= 5e11)
        if isBroken && canCrunch {
            let peakIPMin = GameDecimal(from: jsPlayer.forProperty("records")?.forProperty("thisInfinity")?.forProperty("bestIPmin"))
            let initialShow = peakIPMin.exponent < 12 || (peakIPMin.exponent == 11 && peakIPMin.mantissa <= 5)
            if initialShow {
                // currentIPRate = gainedIP / max(0.0005, thisInfinityRealTime in minutes)
                let realTimeMs = jsPlayer.forProperty("records")?.forProperty("thisInfinity")?.forProperty("realTime")?.toDouble() ?? 1
                let realTimeMins = max(0.0005, realTimeMs / 60_000)
                let currentRate = GameDecimal(double: gainedIP.toDouble / realTimeMins)
                let peakIPMinVal = GameDecimal(from: jsPlayer.forProperty("records")?.forProperty("thisInfinity")?.forProperty("bestIPminVal"))
                let current = formatDecimal(currentRate, places: 2)
                let peak = formatDecimal(peakIPMin, places: 2)
                let peakVal = formatDecimal(peakIPMinVal, places: 2)
                // Rate mode is only useful when the rates carry information AND
                // fit the compact button. Suppress when both current + peak
                // are zero, or when any formatted field overflows the button's
                // ~12-char budget — falls back to the 2-line "Crunch for X" view.
                let bothZero = currentRate.isZero && peakIPMin.isZero
                let anyLong = state.infinity.gainedIP.count > 12
                    || current.count > 12 || peak.count > 12 || peakVal.count > 12
                let showRate = !bothZero && !anyLong
                state.infinity.showIPRate = showRate
                if showRate {
                    state.infinity.currentIPRate = current
                    state.infinity.peakIPRate = peak
                    state.infinity.peakIPRateVal = peakVal
                }
            } else {
                state.infinity.showIPRate = false
            }
        } else {
            state.infinity.showIPRate = false
        }

        // Unlock next Infinity Dimension button (post-break header)
        let id8Unlocked = jsInfDimRefs[7].forProperty("isUnlocked")?.toBool() ?? false
        let nextIDVisible = isBroken && !id8Unlocked
        state.infinity.nextIDVisible = nextIDVisible
        if nextIDVisible {
            let nextID = jsInfinityDimensions.invokeMethod("next", withArguments: [])
            state.infinity.nextIDCanUnlock = nextID?.forProperty("canUnlock")?.toBool() ?? false
            let hasIPUnlock = nextID?.forProperty("hasIPUnlock")?.toBool() ?? true
            state.infinity.nextIDHasIPUnlock = hasIPUnlock
            // amRequirement is a break_infinity Decimal with very large exponents (e.g. 1e1100)
            // ipRequirement is a plain JS number (1e8) — not a Decimal
            // Use JS format() for reliable formatting of both
            state.infinity.nextIDAmRequirement = context.evaluateScript(
                "format(InfinityDimensions.next().amRequirement)"
            )?.toString() ?? "0"
            if hasIPUnlock {
                state.infinity.nextIDIPRequirement = context.evaluateScript(
                    "format(InfinityDimensions.next().ipRequirement)"
                )?.toString() ?? "0"
            }
        } else {
            state.infinity.nextIDCanUnlock = false
        }

        // --- Eternity button (visible once ID8 is unlocked or can eternity) ---
        let canEternity = jsPlayerObj.forProperty("canEternity")?.toBool() ?? false
        let isInEC = jsEternityChallenge.forProperty("isRunning")?.toBool() ?? false
        let showEternityBtn = canEternity || id8Unlocked || isInEC
        state.infinity.showEternityButton = showEternityBtn
        state.infinity.canEternity = canEternity
        let etUnlockedForBtn = jsPlayerProgress.invokeMethod("eternityUnlocked", withArguments: [])?.toBool() ?? false
        state.infinity.eternityUnlocked = etUnlockedForBtn
        state.infinity.isInEternityChallenge = isInEC
        if showEternityBtn {
            let goal = GameDecimal(from: jsPlayerObj.forProperty("eternityGoal"))
            state.infinity.eternityGoal = formatDecimal(goal, places: 2, placesUnder1000: 2)
        }
        // EC completion status (when in EC and can eternity)
        if canEternity && state.infinity.isInEternityChallenge {
            let ec = jsEternityChallenge.forProperty("current")
            let ecIsObj = ec?.isObject == true
            let fc = ecIsObj ? (ec?.forProperty("isFullyCompleted")?.toBool() ?? false) : false
            state.infinity.ecFullyCompleted = fc
            if ecIsObj && !fc {
                let gcs = ec?.forProperty("gainedCompletionStatus")
                state.infinity.ecGainedCompletions = Int(gcs?.forProperty("gainedCompletions")?.toDouble() ?? 0)
                let failedVal = gcs?.forProperty("failedRestriction")
                state.infinity.ecFailedRestriction = (failedVal?.isUndefined == false && failedVal?.isNull == false)
                    ? (failedVal?.toString() ?? "") : ""
                let nextGoalAt = gcs?.forProperty("nextGoalAt")
                if let ng = nextGoalAt, !ng.isUndefined, !ng.isNull {
                    let nextGoalDecimal = GameDecimal(from: ng)
                    let formatted = formatDecimal(nextGoalDecimal)
                    state.infinity.ecNextGoalAt = formatted
                } else {
                    state.infinity.ecNextGoalAt = ""
                }
                state.infinity.ecHasMoreCompletions = gcs?.forProperty("hasMoreCompletions")?.toBool() ?? false
            } else {
                state.infinity.ecGainedCompletions = 0
                state.infinity.ecFailedRestriction = ""
                state.infinity.ecNextGoalAt = ""
                state.infinity.ecHasMoreCompletions = false
            }
        }

        if canEternity && etUnlockedForBtn && !state.infinity.isInEternityChallenge {
            let gainedEP = GameDecimal(from: context.evaluateScript("gainedEternityPoints()"))
            state.infinity.gainedEP = formatDecimal(gainedEP, places: 2)

            let peakEPRate = GameDecimal(from: jsPlayer
                .forProperty("records")?.forProperty("thisEternity")?.forProperty("bestEPmin"))
            let initialShow = peakEPRate.exponent <= 40

            if initialShow {
                let currentEPRate = GameDecimal(from: context.evaluateScript("""
                    (function() {
                        var ep = gainedEternityPoints();
                        var min = TimeSpan.fromMilliseconds(player.records.thisEternity.realTime).totalMinutes;
                        return min === 0 ? new Decimal(0) : ep.dividedBy(min);
                    })()
                    """))
                let peakEPRateVal = GameDecimal(from: jsPlayer
                    .forProperty("records")?.forProperty("thisEternity")?.forProperty("bestEPminVal"))
                let current = formatDecimal(currentEPRate, places: 2, placesUnder1000: 2)
                let peak = formatDecimal(peakEPRate, places: 2, placesUnder1000: 2)
                let peakVal = formatDecimal(peakEPRateVal, places: 2, placesUnder1000: 2)
                // Zero-rate and length-overflow guards — see IP rate block
                // above for rationale. Drops to 2-line "Eternity for X".
                let bothZero = currentEPRate.isZero && peakEPRate.isZero
                let anyLong = state.infinity.gainedEP.count > 12
                    || current.count > 12 || peak.count > 12 || peakVal.count > 12
                let showRate = !bothZero && !anyLong
                state.infinity.showEPRate = showRate
                if showRate {
                    state.infinity.currentEPRate = current
                    state.infinity.peakEPRate = peak
                    state.infinity.peakEPRateVal = peakVal
                }
            } else {
                state.infinity.showEPRate = false
            }
        }

        // --- Replicanti header (always polled for sidebar currency display) ---
        let replUnlocked = jsPlayer.forProperty("replicanti")?.forProperty("unl")?.toBool() ?? false
        let replAmount = replUnlocked ? GameDecimal(from: jsPlayer.forProperty("replicanti")?.forProperty("amount")) : .zero
        let replAmountStr = replUnlocked ? formatDecimal(replAmount, places: 2) : "0"

        // SecretAchievement(21) reveal state. Single-bool per-tick read so
        // the engine mirror stays in sync after save loads and slot switches
        // without a dedicated helper. Flips only when the user taps the
        // secret study tile, so the cost is amortized across many ticks of
        // unchanged value.
        let secretTSVisibleFlag = jsPlayer.forProperty("secretUnlocks")?.forProperty("viewSecretTS")?.toBool() ?? false

        let t0 = CFAbsoluteTimeGetCurrent()

        // --- Unlock checks (always polled, not tab-gated) ---
        let totalAM = GameDecimal(from: jsPlayer.forProperty("records")?.forProperty("totalAntimatter"))
        let abUnlocked = totalAM.exponent > 40 || (totalAM.exponent == 40 && totalAM.mantissa >= 1.0)
        let eternityReached = jsPlayerProgress.invokeMethod("eternityUnlocked", withArguments: [])?.toBool() ?? false
        let epStr: String
        let ttStr: String
        if eternityReached {
            let ep = GameDecimal(from: jsCurrencyEP.forProperty("value"))
            epStr = formatDecimal(ep, places: 2)
            let tt = GameDecimal(from: jsCurrencyTT.forProperty("value"))
            ttStr = formatDecimal(tt, places: 2)
        } else {
            epStr = "0"
            ttStr = "0"
        }
        let dilationReached = eternityReached && (jsPlayerProgress.invokeMethod("dilationUnlocked", withArguments: [])?.toBool() ?? false)
        let realityReached = jsPlayerProgress.invokeMethod("realityUnlocked", withArguments: [])?.toBool() ?? false
        let realityStudyBought = jsTimeStudyReality.forProperty("isBought")?.toBool() ?? false
        let teresaReached = realityReached && (jsTeresa.forProperty("isUnlocked")?.toBool() ?? false)
        // --- Combined celestial per-tick eval ---
        // Merges 3 unlock checks + celestial reality indicator + BH header +
        // game speed into a single evaluateScript + JSON parse. Saves ~5
        // bridge crossings per tick for post-Reality saves.
        // Gated on realityReached: BlackHoles unlock for 100 RM before Teresa
        // visits, and the inner blocks each guard their own globals with
        // `typeof X !== "undefined"`, so it's safe to run earlier than Teresa.
        var effarigReached = false
        var effarigEternityReached = false
        var vReached = false
        var raReached = false
        var imReached = false
        var alchemyReached = false
        var laitelaReached = false
        var celestialRealityName = ""
        var realityButtonSpecialFlag = false
        var enslavedRunningFlag = false
        var enslavedHasSecretStudyFlag = false
        var enslavedFeltEternityFlag = false
        var enslavedCompletedFlag = false
        var enslavedHintTimerVisibleFlag = false
        var enslavedHintTimerTextStr = ""
        var laitelaRunEntropyStr = ""
        var laitelaRunGameSpeedStr = ""
        var tesseractAffordableFlag = false
        var bhHeaderVisible = false
        var bhHeaderPauseText = ""
        var bhHeaderStates: [String] = []
        var bhHeaderPermanent = false
        var bhHeaderPaused = false
        var enslavedChargeVisible = false
        var enslavedIsCharging = false
        var gameSpeedStr = ""
        var canPulseFlag = false
        var isPulsingFlag = false
        var canDischargeFlag = false
        var storedTimeStr = "0s"
        var pulsedSpeedStr = ""
        var gameSpeedIsPulsingFlag = false
        var continuumUnlockedFlag = false
        var continuumDisabledFlag = false
        var laiAutoDimUnlockedFlag = false, laiAutoDimActiveFlag = false
        var laiAutoAscUnlockedFlag = false, laiAutoAscActiveFlag = false
        var laiAutoSingUnlockedFlag = false, laiAutoSingActiveFlag = false
        var laiAutoAnniUnlockedFlag = false, laiAutoAnniActiveFlag = false
        var laiAutoAnniMultiplierFlag: Double = 0
        var pelleUnlockedFlag = false
        var pelleDoomedFlag = false
        var pelleCanArmFlag = false
        var pelleRemnantsStr = ""
        var pelleRSStr = "0"
        var pelleRSpsStr = "0/s"
        var pelleRSnextStr = "0/s"
        var pelleGlyphEqDisFlag = false
        var gameEndES: Double = 0
        var gameEndCC: Bool = false
        if realityReached {
            let json = context.evaluateScript("""
                (function() {
                    var out = {
                        efR: false, eeR: false, vR: false, raR: false,
                        imR: false, alR: false, laiR: false,
                        peleU: false, peleD: false, peleCanArm: false, peleRem: "",
                        peleRS: "0", peleRSps: "0/s", peleRSnext: "0/s",
                        peleGlyphEqDis: false,
                        geES: 0, geCC: false,
                        name: "", special: false,
                        eRunning: false, eSecret: false, eFelt: false, eComplete: false,
                        hintTimerOn: false, hintTimerText: "",
                        tessAff: false,
                        bhVisible: false, bhPaused: false, bhPauseText: "",
                        bhStates: [], bhPermanent: false,
                        canCharge: false, isCharging: false,
                        gameSpeed: 1
                    };
                    var stage = "start";
                    try {
                        stage = "unlocks";
                        if (typeof TeresaUnlocks !== "undefined" && TeresaUnlocks
                            && TeresaUnlocks.effarig && TeresaUnlocks.effarig.canBeApplied) {
                            out.efR = true;
                            if (typeof EffarigUnlock !== "undefined" && EffarigUnlock
                                && EffarigUnlock.eternity && EffarigUnlock.eternity.isUnlocked) {
                                out.eeR = true;
                                if (typeof Achievement !== "undefined" && Achievement(151)
                                    && Achievement(151).isUnlocked) {
                                    out.vR = true;
                                    if (typeof VUnlocks !== "undefined" && VUnlocks.raUnlock
                                        && VUnlocks.raUnlock.isUnlocked) {
                                        out.raR = true;
                                    }
                                }
                            }
                        }
                        stage = "imUnlock";
                        if (typeof MachineHandler !== "undefined" && MachineHandler
                            && MachineHandler.isIMUnlocked) {
                            out.imR = true;
                        }
                        stage = "alchemyUnlock";
                        if (typeof Ra !== "undefined" && Ra && Ra.unlocks
                            && Ra.unlocks.unlockGlyphAlchemy
                            && Ra.unlocks.unlockGlyphAlchemy.canBeApplied) {
                            out.alR = true;
                        }
                        stage = "laitelaUnlock";
                        if (typeof Laitela !== "undefined" && Laitela && Laitela.isUnlocked) {
                            out.laiR = true;
                        }
                        stage = "continuum";
                        if (typeof Laitela !== "undefined" && Laitela) {
                            out.cU = !!Laitela.continuumUnlocked;
                            out.cD = !!(player && player.auto && player.auto.disableContinuum);
                        }
                        stage = "laitelaAutobuyers";
                        try {
                            out.ladU = !!(SingularityMilestone && SingularityMilestone.darkDimensionAutobuyers
                                          && SingularityMilestone.darkDimensionAutobuyers.isUnlocked);
                            out.ladA = !!(player.auto && player.auto.darkMatterDims && player.auto.darkMatterDims.isActive);
                            out.laasU = !!(SingularityMilestone && SingularityMilestone.ascensionAutobuyers
                                           && SingularityMilestone.ascensionAutobuyers.isUnlocked);
                            out.laasA = !!(player.auto && player.auto.ascension && player.auto.ascension.isActive);
                            out.lasU = !!(SingularityMilestone && SingularityMilestone.autoCondense
                                          && SingularityMilestone.autoCondense.isUnlocked);
                            out.lasA = !!(player.auto && player.auto.singularity && player.auto.singularity.isActive);
                            out.lanU = !!(typeof Autobuyer !== "undefined" && Autobuyer.annihilation
                                          && Autobuyer.annihilation.isUnlocked);
                            out.lanA = !!(player.auto && player.auto.annihilation && player.auto.annihilation.isActive);
                            out.lanM = (player.auto && player.auto.annihilation) ? (Number(player.auto.annihilation.multiplier) || 0) : 0;
                        } catch (e) {}

                        stage = "pelleUnlock";
                        if (typeof Pelle !== "undefined" && Pelle) {
                            out.peleU = !!Pelle.isUnlocked;
                            out.peleD = !!Pelle.isDoomed;
                            if (out.peleD) {
                                try {
                                    var rem = Pelle.remnantsGain;
                                    out.peleCanArm = (typeof rem === "number")
                                        ? (rem > 0)
                                        : (rem && typeof rem.gt === "function" ? rem.gt(0) : false);
                                    out.peleRem = (typeof format === "function") ? format(rem, 2, 2) : String(rem);
                                } catch (e) {
                                    out.peleCanArm = false;
                                    out.peleRem = "0";
                                }
                                // Reality Shards balance + current rate + post-Armageddon
                                // rate. Drives the header "You have X Reality Shards"
                                // line and the "X/s ➔ Y/s" transition inside the
                                // Armageddon header button (web ArmageddonButton.vue).
                                try {
                                    var rs = (Pelle.cel && Pelle.cel.realityShards) || 0;
                                    out.peleRS = (typeof format === "function") ? format(rs, 2, 2) : String(rs);
                                    var rsRate = Pelle.realityShardGainPerSecond;
                                    var rsNext = Pelle.nextRealityShardGain;
                                    out.peleRSps = ((typeof format === "function") ? format(rsRate || 0, 2, 2) : String(rsRate || 0)) + "/s";
                                    out.peleRSnext = ((typeof format === "function") ? format(rsNext || 0, 2, 2) : String(rsNext || 0)) + "/s";
                                } catch (e) {
                                    out.peleRS = "0";
                                    out.peleRSps = "0/s";
                                    out.peleRSnext = "0/s";
                                }
                                // Glyph equipping gate — Pelle.isDisabled("glyphs")
                                // is true until PelleUpgrade.glyphEquipping is bought.
                                try {
                                    out.peleGlyphEqDis = !!(typeof Pelle.isDisabled === "function"
                                        && Pelle.isDisabled("glyphs"));
                                } catch (e) {
                                    out.peleGlyphEqDis = true;
                                }
                            }
                        }

                        stage = "celestials.name";
                        var c = (typeof player !== "undefined" && player) ? (player.celestials || {}) : {};
                        // Pelle takes precedence — once doomed, the player is
                        // permanently in Pelle's reality regardless of any
                        // other run flags. Header banner reads "Doomed Reality".
                        if (out.peleD) out.name = "Doomed Reality";
                        else if (c && c.teresa && c.teresa.run) out.name = "Teresa's Reality";
                        else if (c && c.effarig && c.effarig.run) out.name = "Effarig's Reality";
                        else if (c && c.enslaved && c.enslaved.run) out.name = "The Nameless Ones' Reality";
                        else if (c && c.v && c.v.run) out.name = "V's Reality";
                        else if (c && c.ra && c.ra.run) out.name = "Ra's Reality";
                        else if (c && c.laitela && c.laitela.run) out.name = "Lai'tela's Reality";

                        stage = "specialReward";
                        if (typeof Teresa !== "undefined" && Teresa && Teresa.isRunning
                            && typeof Currency !== "undefined" && Currency && Currency.antimatter
                            && typeof Teresa.rewardMultiplier === "function"
                            && Teresa.rewardMultiplier(Currency.antimatter.value) > Teresa.runRewardMultiplier) {
                            out.special = true;
                        } else if (typeof Currency !== "undefined" && Currency && Currency.eternityPoints
                            && Currency.eternityPoints.value
                            && Currency.eternityPoints.value.exponent > 4000) {
                            if (typeof Effarig !== "undefined" && Effarig && Effarig.isRunning
                                && typeof EffarigUnlock !== "undefined"
                                && EffarigUnlock.reality && !EffarigUnlock.reality.isUnlocked) out.special = true;
                            else if (typeof Enslaved !== "undefined" && Enslaved
                                && Enslaved.isRunning && !Enslaved.isCompleted) out.special = true;
                        }

                        stage = "enslavedFlags";
                        if (typeof Enslaved !== "undefined" && Enslaved) {
                            out.eRunning = !!Enslaved.isRunning;
                            out.eComplete = !!Enslaved.isCompleted;
                        }
                        if (c && c.enslaved) {
                            out.eSecret = !!c.enslaved.hasSecretStudy;
                            out.eFelt   = !!c.enslaved.feltEternity;
                        }

                        stage = "hintTimer";
                        if (typeof Enslaved !== "undefined" && Enslaved
                            && typeof EnslavedProgress !== "undefined" && EnslavedProgress
                            && EnslavedProgress.hintsUnlocked
                            && typeof ENSLAVED_UNLOCKS !== "undefined" && ENSLAVED_UNLOCKS) {
                            out.hintTimerOn = !!Enslaved.canTickHintTimer;
                        }
                        if (out.hintTimerOn && c && c.enslaved && typeof TimeSpan !== "undefined" && TimeSpan) {
                            var hintProgress = Number(c.enslaved.hintUnlockProgress || 0);
                            var rawMs = 5 * 3600 * 1000 - hintProgress;
                            var divisor = out.eRunning ? 1 : 0.4;
                            if (isFinite(rawMs) && isFinite(divisor) && divisor > 0 && rawMs > 0) {
                                out.hintTimerText = TimeSpan.fromMilliseconds(rawMs / divisor).toStringShort();
                            }
                        }

                        stage = "tesseract";
                        if (typeof Tesseracts !== "undefined" && Tesseracts) {
                            out.tessAff = !!Tesseracts.canBuyTesseract;
                        }

                        stage = "blackHoleHeader";
                        if (typeof BlackHoles !== "undefined" && BlackHoles && BlackHoles.areUnlocked
                            && !(typeof Laitela !== "undefined" && Laitela && Laitela.isRunning)) {
                            var paused = BlackHoles.arePaused;
                            var permanent = BlackHoles.arePermanent;
                            var pauseText;
                            if (paused && player.blackHoleNegative < 1) pauseText = "Uninvert BH";
                            else if (paused) pauseText = "Unpause BH";
                            else {
                                var accel = BlackHoles.unpauseAccelerationFactor;
                                if (accel !== 1) pauseText = formatPercents(accel, 1) + " speed";
                                else if (player.blackHoleNegative < 1) pauseText = "Invert BH";
                                else pauseText = "Pause BH";
                            }
                            var states = [];
                            if (permanent) {
                                var p1 = BlackHole(1);
                                if (p1) states.push(p1.displayState);
                            } else {
                                for (var i = 1; i <= 2; i++) {
                                    var bh = BlackHole(i);
                                    if (bh && bh.isUnlocked) states.push(i + ":" + bh.displayState);
                                }
                            }
                            out.bhVisible = true;
                            out.bhPaused = paused;
                            out.bhPauseText = pauseText;
                            out.bhStates = states;
                            out.bhPermanent = permanent;
                            if (typeof Enslaved !== "undefined" && Enslaved && Enslaved.isUnlocked) {
                                out.canCharge = true;
                                out.isCharging = !!Enslaved.isStoringGameTime;
                                // Pulse Black Hole (Ra.unlocks.autoPulseTime — Enslaved pet lv 10).
                                // `canPulse` drives the header "Pulse" toggle; while pulsing
                                // the Charge/Stop button is hidden.
                                out.canPulse = !!(typeof Ra !== "undefined" && Ra.unlocks
                                    && Ra.unlocks.autoPulseTime && Ra.unlocks.autoPulseTime.canBeApplied);
                                out.isAutoReleasing = !!(player && player.celestials && player.celestials.enslaved
                                    && player.celestials.enslaved.isAutoReleasing);
                                // One-shot Discharge — dumps all stored game time at once.
                                out.canDischarge = !!Enslaved.canRelease(false);
                                var storedMs = (player && player.celestials && player.celestials.enslaved)
                                    ? (player.celestials.enslaved.stored || 0) : 0;
                                out.storedTimeText = timeDisplayShort(storedMs);
                            }
                        }

                        stage = "laitelaRun";
                        if (typeof Laitela !== "undefined" && Laitela && Laitela.isRunning) {
                            try {
                                // Mirrors web HeaderChallengeEffects.vue: show entropy %
                                // plus the ELAPSED real time of the run (counts up), not
                                // time-remaining. The old `remaining = (1-entropy)/gps`
                                // tracked 1/antimatter — it counted DOWN as antimatter grew
                                // and jumped back UP on Eternity (antimatter reset shrinks gps).
                                var entropy = (player.celestials.laitela.entropy || 0);
                                out.laiRunning = true;
                                var entropyPct, timerStr;
                                if (entropy > 0) {
                                    entropyPct = formatPercents(entropy, 2, 2);
                                    timerStr = Time.thisRealityRealTime.toStringShort();
                                } else {
                                    entropyPct = formatPercents(1, 2, 2);
                                    timerStr = TimeSpan.fromSeconds(player.celestials.laitela.thisCompletion).toStringShort();
                                }
                                out.laiEntropyText = entropyPct + " (" + timerStr + ")";
                                var gs = getGameSpeedupFactor();
                                out.laiGameSpeedText = (gs !== 1)
                                    ? ("Game speed is altered: " + format(gs, 2, 3))
                                    : "";
                            } catch (e) {
                                out.laiRunning = !!Laitela.isRunning;
                                out.laiEntropyText = "";
                                out.laiGameSpeedText = "";
                            }
                        }

                        stage = "gameSpeed";
                        out.gameSpeed = getGameSpeedupFactor();
                        try {
                            if (typeof getGameSpeedupForDisplay === "function") {
                                out.pulsedSpeed = getGameSpeedupForDisplay();
                            } else {
                                out.pulsedSpeed = out.gameSpeed;
                            }
                            out.hasSeenAltered = !!(PlayerProgress && PlayerProgress.seenAlteredSpeed && PlayerProgress.seenAlteredSpeed());
                            out.isEC12 = !!(typeof EternityChallenge !== "undefined" && EternityChallenge(12).isRunning);
                            out.isStoringRealTime = !!(typeof Enslaved !== "undefined" && Enslaved.isStoringRealTime);
                        } catch (e) {
                            out.pulsedSpeed = out.gameSpeed;
                        }

                        // GameEnd quick-read. Gated on `peleD` because the
                        // `endState` getter is NOT free — it allocates a
                        // Decimal (`totalAntimatter.plus(1)`) and runs a
                        // log10 chain on every call. Pre-doom totalAntimatter
                        // is always 0, so endState is mathematically pinned
                        // at 0 — skip the work entirely. Post-doom it's a few
                        // microseconds per tick which is acceptable for a
                        // mechanic that's actively driving cross-cutting UI.
                        stage = "gameEnd";
                        try {
                            if (out.peleD && typeof GameEnd !== "undefined" && GameEnd
                                    && typeof GameEnd.endState === "number") {
                                out.geES = GameEnd.endState || 0;
                                out.geCC = !!GameEnd.creditsClosed;
                            }
                        } catch (e) { /* leave defaults */ }
                    } catch (e) {
                        out.__err = stage + ": " + (e && e.message ? e.message : String(e));
                    }
                    return JSON.stringify(out);
                })()
                """)?.toString() ?? ""
            if let data = json.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let err = obj["__err"] as? String,
                   err != _lastCelestialEvalErr {
                    _lastCelestialEvalErr = err
                    print("⚠️ celestialCombined eval caught: \(err)")
                }
                effarigReached = (obj["efR"] as? Bool) ?? false
                effarigEternityReached = (obj["eeR"] as? Bool) ?? false
                vReached = (obj["vR"] as? Bool) ?? false
                raReached = (obj["raR"] as? Bool) ?? false
                imReached = (obj["imR"] as? Bool) ?? false
                alchemyReached = (obj["alR"] as? Bool) ?? false
                laitelaReached = (obj["laiR"] as? Bool) ?? false
                pelleUnlockedFlag = (obj["peleU"] as? Bool) ?? false
                pelleDoomedFlag = (obj["peleD"] as? Bool) ?? false
                pelleCanArmFlag = (obj["peleCanArm"] as? Bool) ?? false
                pelleRemnantsStr = (obj["peleRem"] as? String) ?? ""
                pelleRSStr = (obj["peleRS"] as? String) ?? "0"
                pelleRSpsStr = (obj["peleRSps"] as? String) ?? "0/s"
                pelleRSnextStr = (obj["peleRSnext"] as? String) ?? "0/s"
                pelleGlyphEqDisFlag = (obj["peleGlyphEqDis"] as? Bool) ?? false
                gameEndES = (obj["geES"] as? Double) ?? 0
                gameEndCC = (obj["geCC"] as? Bool) ?? false
                continuumUnlockedFlag = (obj["cU"] as? Bool) ?? false
                continuumDisabledFlag = (obj["cD"] as? Bool) ?? false
                laiAutoDimUnlockedFlag  = (obj["ladU"]  as? Bool) ?? false
                laiAutoDimActiveFlag    = (obj["ladA"]  as? Bool) ?? false
                laiAutoAscUnlockedFlag  = (obj["laasU"] as? Bool) ?? false
                laiAutoAscActiveFlag    = (obj["laasA"] as? Bool) ?? false
                laiAutoSingUnlockedFlag = (obj["lasU"]  as? Bool) ?? false
                laiAutoSingActiveFlag   = (obj["lasA"]  as? Bool) ?? false
                laiAutoAnniUnlockedFlag = (obj["lanU"]  as? Bool) ?? false
                laiAutoAnniActiveFlag   = (obj["lanA"]  as? Bool) ?? false
                laiAutoAnniMultiplierFlag = (obj["lanM"] as? Double) ?? 0
                celestialRealityName = (obj["name"] as? String) ?? ""
                realityButtonSpecialFlag = (obj["special"] as? Bool) ?? false
                enslavedRunningFlag = (obj["eRunning"] as? Bool) ?? false
                enslavedHasSecretStudyFlag = (obj["eSecret"] as? Bool) ?? false
                enslavedFeltEternityFlag = (obj["eFelt"] as? Bool) ?? false
                enslavedCompletedFlag = (obj["eComplete"] as? Bool) ?? false
                enslavedHintTimerVisibleFlag = (obj["hintTimerOn"] as? Bool) ?? false
                enslavedHintTimerTextStr = (obj["hintTimerText"] as? String) ?? ""
                laitelaRunEntropyStr = (obj["laiEntropyText"] as? String) ?? ""
                laitelaRunGameSpeedStr = (obj["laiGameSpeedText"] as? String) ?? ""
                tesseractAffordableFlag = (obj["tessAff"] as? Bool) ?? false
                bhHeaderVisible = obj["bhVisible"] as? Bool ?? false
                if bhHeaderVisible {
                    bhHeaderPaused = obj["bhPaused"] as? Bool ?? false
                    bhHeaderPauseText = obj["bhPauseText"] as? String ?? "Pause BH"
                    bhHeaderPermanent = obj["bhPermanent"] as? Bool ?? false
                    if let rawStates = obj["bhStates"] as? [String] {
                        bhHeaderStates = rawStates.map { Self.stripBHDisplayHTML($0) }
                    }
                    enslavedChargeVisible = obj["canCharge"] as? Bool ?? false
                    enslavedIsCharging = obj["isCharging"] as? Bool ?? false
                    canPulseFlag = obj["canPulse"] as? Bool ?? false
                    isPulsingFlag = obj["isAutoReleasing"] as? Bool ?? false
                    canDischargeFlag = obj["canDischarge"] as? Bool ?? false
                    storedTimeStr = obj["storedTimeText"] as? String ?? "0s"
                }
                let baseSpeed = obj["gameSpeed"] as? Double ?? 1.0
                let pulsedSpeed = obj["pulsedSpeed"] as? Double ?? baseSpeed
                let hasSeenAltered = obj["hasSeenAltered"] as? Bool ?? false
                let isStoringReal = obj["isStoringRealTime"] as? Bool ?? false
                let isEC12 = obj["isEC12"] as? Bool ?? false
                // Mirrors web GameSpeedDisplay.vue:
                //   hasSeenAltered == false → no text
                //   base == 1              → "The game is running at normal speed."
                //   else                   → "Game speed is altered: Xx"
                // Pulsed: baseSpeed != pulsedSpeed && Enslaved.canRelease(true)
                // Stopped (storing real time) → "Stopped (storing real time)"
                if !hasSeenAltered {
                    gameSpeedStr = ""
                } else if abs(baseSpeed - 1.0) < 0.001 {
                    gameSpeedStr = "The game is running at normal speed."
                } else {
                    let baseText: String
                    if isStoringReal {
                        baseText = "Stopped (storing real time)"
                    } else {
                        let formatted = formatDecimal(GameDecimal(double: baseSpeed), places: 2, placesUnder1000: 2)
                        baseText = isEC12 ? "\(formatted)x (fixed)" : "\(formatted)"
                    }
                    gameSpeedStr = "Game speed is altered: \(baseText)"
                }
                // Pulsed speed append — only show when pulsing changes the effective rate.
                if abs(baseSpeed - pulsedSpeed) > 1e-9 && canPulseFlag && isPulsingFlag {
                    pulsedSpeedStr = formatDecimal(GameDecimal(double: pulsedSpeed), places: 2, placesUnder1000: 2) + "x"
                    gameSpeedIsPulsingFlag = true
                } else {
                    pulsedSpeedStr = ""
                    gameSpeedIsPulsingFlag = false
                }
            }
        }

        // --- News ticker state ---
        let newsOn = jsPlayer.forProperty("options")?.forProperty("news")?.forProperty("enabled")?.toBool() ?? true
        let newsSpd = jsPlayer.forProperty("options")?.forProperty("news")?.forProperty("speed")?.toDouble() ?? 1.0

        // --- Gameplay options mirrors (Options → Gameplay card) ---
        let autoTabSwitching = jsPlayer.forProperty("options")?.forProperty("automaticTabSwitching")?.toBool() ?? true
        let offlineProgOpt = jsPlayer.forProperty("options")?.forProperty("offlineProgress")?.toBool() ?? true
        let offlineTicksRaw = Int(jsPlayer.forProperty("options")?.forProperty("offlineTicks")?.toDouble() ?? 1000)
        let automatorLogMax = Int(jsPlayer.forProperty("options")?.forProperty("automatorEvents")?.forProperty("maxEntries")?.toDouble() ?? 100)
        let glyphTxtColors = jsPlayer.forProperty("options")?.forProperty("glyphTextColors")?.toBool() ?? true
        let hideAlterFx = jsPlayer.forProperty("options")?.forProperty("hideAlterationEffects")?.toBool() ?? false
        let glyphSelConfirm = jsPlayer.forProperty("options")?.forProperty("confirmations")?.forProperty("glyphSelection")?.toBool() ?? true

        // --- Modify Visible Tabs (`player.options.hiddenTabBits` + per-parent
        // `hiddenSubtabBits` array). Both fields are present on every save
        // via web migrations.js so we can read unconditionally.
        let hiddenTabsRaw = Int(jsPlayer.forProperty("options")?.forProperty("hiddenTabBits")?.toInt32() ?? 0)
        var hiddenSubtabsRaw = Array(repeating: 0, count: 11)
        if let subBitsJS = jsPlayer.forProperty("options")?.forProperty("hiddenSubtabBits") {
            let count = Int(subBitsJS.forProperty("length")?.toInt32() ?? 0)
            for i in 0..<min(count, 11) {
                hiddenSubtabsRaw[i] = Int(subBitsJS.atIndex(i)?.toInt32() ?? 0)
            }
        }

        // --- Notation name (for Options picker + Swift formatter dispatch) ---
        let rawNotation = jsPlayer.forProperty("options")?.forProperty("notation")?.toString() ?? "Mixed scientific"

        // --- Dilation header (tachyon gain for eternity button) ---
        let dilationActive = dilationReached
            && (jsPlayer.forProperty("dilation")?.forProperty("active")?.toBool() ?? false)

        // --- Header late-tick coalesced reads ---
        // Single helper call replaces 11 scattered evals: tachyon gain text,
        // EP-threshold check, sidebar currency cycle (TP/DT/RelicShards/iM/
        // MachinesCombined/DarkMatter/DarkEnergy/Singularities), and the
        // EC-any-completion fallback. See `header-tick-helper.js`.
        let ecUnlockedIdEarly = jsPlayer.forProperty("challenge")?.forProperty("eternity")?.forProperty("unlocked")?.toInt32() ?? 0
        let anyECNeeded = eternityReached && ecUnlockedIdEarly == 0
        // One allocation instead of six. Each `+=` previously built a fresh
        // String buffer; interpolation folds the six bool→char picks into
        // a single string literal.
        let gateFlags = "\(dilationActive ? "1" : "0")\(dilationReached ? "1" : "0")\(effarigReached ? "1" : "0")\(imReached ? "1" : "0")\(laitelaReached ? "1" : "0")\(anyECNeeded ? "1" : "0")"
        let lateReadsJSON = context.evaluateScript("_nativeHeaderLateTickReads('\(gateFlags)')")?.toString() ?? "{}"
        let lateReads: [String: Any] = {
            guard let data = lateReadsJSON.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return [:]
            }
            return obj
        }()

        var headerTachyonGain = ""
        if dilationActive {
            headerTachyonGain = (lateReads["tachyonGain"] as? String) ?? "0"
        }
        state.infinity.isDilationActive = dilationActive
        state.infinity.dilationTachyonGain = headerTachyonGain

        // --- Reality header (RM gain for reality button) ---
        state.infinity.showRealityButton = realityStudyBought || realityReached
        state.infinity.hasRealityStudy = realityStudyBought
        state.infinity.hasEnoughEPForReality = (lateReads["epGteReality"] as? Bool) ?? false
        var currentRMStr = "0"
        if realityStudyBought {
            let canRealityNow = context.evaluateScript("isRealityAvailable()")?.toBool() ?? false
            state.infinity.canReality = canRealityNow
            if canRealityNow {
              // Throttled to every 4th tick — this ~60-line IIFE is expensive and values change slowly.
              // On skipped ticks, state retains values from jsQueueState.
              if _jsPollTickCount % 4 == 0 {
                // Compute machine gained text + stats + glyph level (matching web RealityButton.vue)
                let btnInfo = context.evaluateScript("""
                    (function() {
                        var mult = simulatedRealityCount(false) + 1;
                        var projected = MachineHandler.gainedRealityMachines.times(mult).clampMax(MachineHandler.hardcapRM);
                        var gained = projected.clampMax(MachineHandler.distanceToRMCap);
                        var rmText = gained.gt(0) ? 'Machines gained: ' + format(gained, 2) : 'No Machines gained';
                        var epForNext = (function(rm) {
                            var adj = Decimal.divide(rm, MachineHandler.realityMachineMultiplier);
                            if (adj.lte(1)) return Decimal.pow10(4000);
                            if (adj.lte(10)) return Decimal.pow10(4000 / 27 * (adj.toNumber() + 26));
                            var r = Decimal.pow10(4000 * (adj.log10() / 3 + 1));
                            if (!PlayerProgress.realityUnlocked() && r.gte('1e6000')) r = r.div('1e6000').pow(4).times('1e6000');
                            return r;
                        })(gained.plus(1));
                        var statsText = '';
                        if (!PlayerProgress.realityUnlocked() && epForNext.gt('1e8000')) {
                            statsText = '(Capped this Reality!)';
                        } else if (gained.gt(0) && gained.lt(100)) {
                            statsText = '(Next ' + format(epForNext, 2) + ' EP)';
                        } else if (gained.gt(0) && gained.lt(Number.MAX_VALUE)) {
                            var mins = Time.thisRealityRealTime.totalMinutes;
                            if (mins > 0) statsText = '(' + format(gained.divide(mins), 2, 2) + ' RM/min)';
                        }
                        var gl = gainedGlyphLevel();
                        var lvl = Math.floor(gl.actualLevel);
                        var glInputs = getGlyphLevelInputs();
                        var fracLevel = glInputs.actualLevel;
                        if (!isFinite(fracLevel)) fracLevel = 0;
                        var frac = fracLevel - Math.floor(fracLevel);
                        var pct = (Math.min(frac, 0.999) * 100).toFixed(lvl > 1000 ? 0 : 1) + '%';
                        var glyphText = lvl >= 10000 ? 'Glyph lvl: ' + formatInt(lvl) : 'Glyph lvl: ' + formatInt(lvl) + ' ' + pct;
                        var summary = 'You will gain ' + quantifyInt('Reality', mult) + ', ' + quantifyInt('Perk Point', mult) + ', and ' + quantify('Reality Machine', gained, 2) + '.';
                        var bestLvl = player.records.bestReality.glyphLevel;
                        var lvlDiff = Math.abs(bestLvl - lvl);
                        var lvlComp = lvl === bestLvl ? 'equal to' : (lvl > bestLvl ? quantifyInt('level', lvlDiff) + ' higher than' : quantifyInt('level', lvlDiff) + ' lower than');
                        var levelStats = 'You will get a level ' + formatInt(lvl) + ' Glyph on Reality, which is ' + lvlComp + ' your best.';
                        var ppText = quantifyInt('Perk Point', mult);
                        var shardsGained = Effarig.shardsGained * mult;
                        var shardsInfo = '';
                        if (shardsGained > 0) {
                            var shardMins = Time.thisRealityRealTime.totalMinutes;
                            var currentRate = shardMins > 0 ? shardsGained / shardMins : 0;
                            var bestRate = player.records.thisReality.bestRSmin * mult;
                            var bestRateVal = player.records.thisReality.bestRSminVal * mult;
                            shardsInfo = quantify('Relic Shard', shardsGained, 2) + ' (' + format(currentRate, 2) + '/min)';
                            shardsInfo += '\\nPeak: ' + format(bestRate, 2) + '/min at ' + format(bestRateVal, 2) + ' RS';
                        }
                        var celestialInfo = '';
                        if (Teresa.isRunning) {
                            var before = Teresa.runRewardMultiplier;
                            var after = Math.max(before, Teresa.rewardMultiplier(Currency.antimatter.value));
                            celestialInfo = 'Glyph Sacrifice ' + formatX(before, 2, 2) + ' ➜ ' + formatX(after, 2, 2);
                            if (after <= before) {
                                celestialInfo += '\\n(' + format(player.celestials.teresa.bestRunAM, 2, 2) + ' antimatter to improve)';
                            }
                        }
                        return JSON.stringify({rm: rmText, stats: statsText, glyph: glyphText, summary: summary, levelStats: levelStats, pp: ppText, shards: shardsInfo, celestial: celestialInfo});
                    })()
                    """)?.toString() ?? "{}"
                if let data = btnInfo.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                    state.infinity.gainedRM = json["rm"] ?? ""
                    state.infinity.machineStats = json["stats"] ?? ""
                    state.infinity.gainedGlyphLevel = json["glyph"] ?? ""
                    state.infinity.realityGainSummary = json["summary"] ?? ""
                    state.infinity.realityLevelStats = json["levelStats"] ?? ""
                    state.infinity.realityPPGained = json["pp"] ?? ""
                    state.infinity.realityShardsInfo = json["shards"] ?? ""
                    state.infinity.realityCelestialInfo = json["celestial"] ?? ""
                } else {
                    state.infinity.gainedRM = ""
                    state.infinity.machineStats = ""
                    state.infinity.gainedGlyphLevel = ""
                    state.infinity.realityGainSummary = ""
                    state.infinity.realityLevelStats = ""
                    state.infinity.realityPPGained = ""
                    state.infinity.realityShardsInfo = ""
                    state.infinity.realityCelestialInfo = ""
                }
              } // end tick throttle (on skipped ticks, jsQueueState values are retained)
            } else {
                state.infinity.gainedRM = ""
                state.infinity.machineStats = ""
                state.infinity.gainedGlyphLevel = ""
                state.infinity.realityGainSummary = ""
                state.infinity.realityLevelStats = ""
                state.infinity.realityPPGained = ""
                state.infinity.realityShardsInfo = ""
                state.infinity.realityCelestialInfo = ""
            }
        } else {
            state.infinity.canReality = false
            state.infinity.gainedRM = ""
            state.infinity.machineStats = ""
            state.infinity.gainedGlyphLevel = ""
            state.infinity.realityGainSummary = ""
            state.infinity.realityLevelStats = ""
            state.infinity.realityPPGained = ""
            state.infinity.realityShardsInfo = ""
            state.infinity.realityCelestialInfo = ""
        }
        if realityReached {
            let rm = GameDecimal(from: jsCurrencyRM.forProperty("value"))
            currentRMStr = formatDecimal(rm, places: 2)
        }

        // --- Sidebar / header cycle currencies (always-polled, gated) ---
        // Mirrors web `sidebar-resources.js` IDs 7–14. Each new field reads
        // its currency only when the relevant unlock flag is true, so a fresh
        // game pays zero JS cost. Reality Shards (ID 16) is not computed here
        // because `pelleRSStr` from the celestial-combined eval above already
        // covers it.
        //
        // All eight cycle currencies + the EC-any-completion fallback came
        // through the coalesced `_nativeHeaderLateTickReads` call above —
        // read the fields off the parsed `lateReads` dict.
        let tpStr = (lateReads["tpStr"] as? String) ?? "0"
        let dtStr = (lateReads["dtStr"] as? String) ?? "0"
        let relicShardsStr = (lateReads["relicShardsStr"] as? String) ?? "0"
        let imStr = (lateReads["imStr"] as? String) ?? "0"
        let machinesCombinedStr = (lateReads["machinesCombinedStr"] as? String) ?? "0"
        // Header RM readout below antimatter: combined `formatMachines(rm, im)`
        // once iM unlocks (`imReached` == web `MachineHandler.isIMUnlocked`),
        // else pure RM. When im == 0, `formatMachines` already returns just the
        // real part, so this matches web `RealityCurrencyHeader.vue` exactly.
        let rmHeaderDisplayStr = imReached ? machinesCombinedStr : currentRMStr
        let darkMatterStr = (lateReads["darkMatterStr"] as? String) ?? "0"
        let darkEnergyStr = (lateReads["darkEnergyStr"] as? String) ?? "0"
        let singularitiesStr = (lateReads["singularitiesStr"] as? String) ?? "0"

        // Reuse `ecUnlockedIdEarly` from the gate-flags block above (avoids a
        // second `forProperty` chain for the same JS state).
        let ecUnlockedId = ecUnlockedIdEarly
        let ecAvailable = eternityReached && (ecUnlockedId != 0 ||
            ((lateReads["anyECCompleted"] as? Bool) ?? false))

        // --- Tab-gated sub-polls (write into local state) ---
        if cat == .achievements {
            pollAchievements(&state)
            pollSecretAchievements(&state)
        }
        let t1 = CFAbsoluteTimeGetCurrent()

        if cat == .infinity {
            pollInfinityUpgrades(&state)
            pollBreakInfinity(&state)
            pollReplicanti(&state)
        }
        let t2 = CFAbsoluteTimeGetCurrent()

        if cat == .dimensions || cat == .infinity { pollInfinityDimensions(&state) }
        if cat == .dimensions && eternityReached { pollTimeDimensions(&state) }
        let t3 = CFAbsoluteTimeGetCurrent()

        if cat == .autobuyers { pollAutobuyers(&state, abUnlocked: abUnlocked) }
        let t4 = CFAbsoluteTimeGetCurrent()

        if cat == .statistics {
            pollStatisticsGeneral(&state)
            pollChallengeRecords(&state)
            pollPastPrestigeRuns(&state)
        }
        let t5 = CFAbsoluteTimeGetCurrent()

        if cat == .challenges {
            pollNormalChallenges(&state)
            pollInfinityChallenges(&state)
            if eternityReached { pollEternityChallenges(&state) }
        }

        if cat == .eternity {
            pollEternityUpgrades(&state)
            pollEternityMilestones(&state)
            // pollTimeStudies is subtab-gated — the 76-study bulk-JSON
            // build is the heaviest poll in the Eternity category and
            // only the Time Studies subtab reads its output.
            if _jsActiveSubtab == .timeStudies { pollTimeStudies(&state) }
            // Subtab visibility matches web `tabs.js`: `dilationUnlocked() ||
            // realityUnlocked()` — the Time Dilation tab stays reachable post-
            // Reality even when `TimeStudy.dilation` is unbought (TP/DT show 0,
            // upgrades show locked, button gates JS-side). Without the
            // `realityReached` disjunction here, `pollDilation` would skip and
            // `state.eternity.dilation` would retain pre-Reality values from
            // `jsQueueState` — visible as stale TP/DT and a non-functional
            // button until cold launch.
            if dilationReached || realityReached { pollDilation(&state) }
        }

        if cat == .reality && realityReached {
            // Split per-subtab so each Reality subtab only pays for its own
            // poll (each of these is a multi-hundred-byte evaluateScript +
            // JSON parse; running all four at 30Hz was ~4× the necessary cost).
            let sub = _jsActiveSubtab
            if sub == .realityUpgrades { pollRealityUpgrades(&state) }
            if sub == .imaginaryUpgrades { pollImaginaryUpgrades(&state) }
            if sub == .glyphAlchemy    { pollGlyphAlchemy(&state) }
            if sub == .perks           { pollPerks(&state) }
            if sub == .blackHole       { pollBlackHoles(&state) }
            if sub == .glyphs {
                // Throttle the glyphs poll: the bulk JSON eval is the heaviest
                // in the codebase and glyph state rarely changes frame-to-frame
                // (equip/unequip/sacrifice/sort are explicit user actions that
                // also fire non-TICK EventHub events, which trigger an
                // immediate re-poll on iPad).
                if _jsPollTickCount % 3 == 0 {
                    pollGlyphs(&state)
                    // Reality Amplify button lives in GlyphsTab — keep its
                    // state struct live while the user is here.
                    pollEnslavedAmplifyState(&state)
                }
            }
        }

        if cat == .automator && realityReached {
            pollAutomatorPoints(&state)
            if state.automatorState.isUnlocked {
                pollAutomatorEditor(&state)
            }
        }

        if cat == .celestials && teresaReached {
            pollCelestialsTab(&state)
        }
        // Quote queue is polled every tick (cheap ~200-byte JSON) so modals
        // can appear even when the user is on a non-celestial tab (e.g.
        // Teresa's `initial` quote fires on TAB_CHANGED to her tab).
        if teresaReached {
            pollQuoteQueue()
        }

        // --- Update jsQueue shadow state ---
        jsQueueState = state
        _jsProgressFill = newFillClamped

        // --- Dispatch to main for @Observable commit ---
        let idUnlocked = jsInfDimRefs[0].forProperty("isUnlocked")?.toBool() ?? false || eternityReached

        // Challenge display text (always polled — cheap property reads).
        //
        // Mirrors web `HeaderChallengeDisplay.vue` exactly: challenges
        // nest (EC → IC → NC, plus a celestial Reality on top), so the
        // banner is a single line with parts joined by " + ", rendered as
        // "You are currently in <joined>". One Exit button on the right
        // always targets the innermost active layer (Challenge > Reality).
        let ncCurrent = Int(jsPlayer.forProperty("challenge")?.forProperty("normal")?.forProperty("current")?.toInt32() ?? 0)
        let icCurrent = Int(jsPlayer.forProperty("challenge")?.forProperty("infinity")?.forProperty("current")?.toInt32() ?? 0)
        let ecCurrent = Int(jsPlayer.forProperty("challenge")?.forProperty("eternity")?.forProperty("current")?.toInt32() ?? 0)
        var challengeParts: [String] = []
        var powerText = ""
        if ecCurrent > 0 {
            // Match web (HeaderChallengeDisplay.vue:68-79): show the *next*
            // completion target — "(X/???)" inside Enslaved for EC1,
            // "(already completed)" when at the 5-cap, "(X/5)" otherwise.
            //
            // Use the game's `EternityChallenge(n).completions` accessor
            // (NOT `player.challenge.eternity.completions[idx]` — that
            // array may not exist or may have a different shape depending
            // on save version). Wrapped in try/catch for boot-time safety.
            let comp = context.evaluateScript("""
                (function(){
                  try { return EternityChallenge(\(ecCurrent)).completions | 0; }
                  catch(e) { return 0; }
                })()
                """)?.toInt32() ?? 0
            let next = Int(comp) + 1
            let completionText: String
            let enslavedRunning = (self.enslavedIsRunning)
            if enslavedRunning && ecCurrent == 1 {
                completionText = "(\(next)/???)"
            } else if next == 6 {
                completionText = "(already completed)"
            } else {
                completionText = "(\(next)/5)"
            }
            challengeParts.append("Eternity Challenge \(ecCurrent) \(completionText)")
        }
        if icCurrent > 0 {
            challengeParts.append("Infinity Challenge \(icCurrent)")
        }
        if ncCurrent > 0, ncCurrent <= jsNCRefs.count {
            let ncName = jsNCRefs[ncCurrent - 1].forProperty("config")?.forProperty("name")?.toString() ?? "Challenge \(ncCurrent)"
            challengeParts.append("\(ncName) Challenge")
            // C2: production percentage, C3: 1st dimension multiplier,
            // C11: matter currency (mirrors web `HeaderChallengeEffects.vue`
            // `isInMatterChallenge` branch).
            if ncCurrent == 2 {
                let pow = jsPlayer.forProperty("chall2Pow")?.toDouble() ?? 0
                powerText = "Production: \(String(format: "%.2f%%", pow * 100))"
            } else if ncCurrent == 3 {
                let pow = GameDecimal(from: jsPlayer.forProperty("chall3Pow"))
                powerText = "First dimension: \(formatX(pow, places: 3, placesUnder1000: 4))"
            } else if ncCurrent == 11 {
                let matterText = context.evaluateScript("format(player.matter, 2, 1)")?.toString() ?? "0"
                powerText = "There is \(matterText) matter."
            }
        }
        let challengeText: String
        if !challengeParts.isEmpty {
            challengeText = challengeParts.joined(separator: " + ")
        } else if infUnlocked {
            challengeText = "the Antimatter Universe (no active challenges)"
        } else {
            challengeText = ""
        }

        // Quick reset button (visible in quick-resettable challenges like C9, C11)
        let quickReset: Bool
        if state.infinity.inAntimatterChallenge {
            quickReset = jsPlayerObj.forProperty("antimatterChallenge")?.forProperty("isQuickResettable")?.toBool() ?? false
        } else {
            quickReset = false
        }
        let hasDimBoosts = purchasedBoosts > 0

        // --- Tab notifications (lightweight — typically 0–4 items) ---
        // Guard `player.tabNotifications` — on fresh saves / pre-migration
        // it can be undefined, and `Array.from(undefined)` throws
        // "TypeError: undefined is not an object" in JavaScriptCore.
        // Wrap in try/catch so any type mismatch degrades to empty.
        var newNotifiedSubtabs = Set<Subtab>()
        if let notifKeys = context.evaluateScript(
            "(function(){ try { return player.tabNotifications ? Array.from(player.tabNotifications) : []; } catch(e) { return []; } })()"
        ) {
            let count = Int(notifKeys.forProperty("length")?.toInt32() ?? 0)
            for i in 0..<count {
                if let key = notifKeys.atIndex(i)?.toString(),
                   let subtab = Subtab.jsKeyToSubtab[key] {
                    newNotifiedSubtabs.insert(subtab)
                }
            }
        }

        // Speedrun Mode — lightweight per-tick poll. Always on. Dispatches
        // its own main commit; cheap enough to run unconditionally because
        // the JS-side helper short-circuits when the feature is unused
        // (fresh saves return all-zero in a single JSON eval).
        self.pollSpeedrunQuick()

        // Statistics subtab visibility — gates the 4 new subtabs in the
        // sidebar. Single JS eval returning 4 bools, diff-checked against
        // the engine's @Observable mirrors so non-transition ticks don't
        // invalidate SidebarView.body.
        self.pollStatisticsVisibilityFlags()

        let header = HeaderSnapshot(
            antimatter: newAM,
            antimatterPerSec: newAMPerSec,
            progressFill: newFillClamped,
            tickspeedUnlocked: state.tickspeed.isUnlocked,
            infinityUnlocked: infUnlocked,
            autobuyersUnlocked: abUnlocked,
            tickspeedMultiplier: state.tickspeed.multiplier,
            tickspeedPerSecond: state.tickspeed.perSecond,
            currentIP: state.infinity.currentIP,
            replicantiAmount: replAmountStr,
            replicantiUnlocked: replUnlocked,
            challengeDisplayText: challengeText,
            challengePowerText: powerText,
            quickResetAvailable: quickReset,
            quickResetHasBoosts: hasDimBoosts,
            blackHolesHeaderVisible: bhHeaderVisible,
            blackHoleHeaderPauseText: bhHeaderPauseText,
            blackHoleHeaderStates: bhHeaderStates,
            blackHolesHeaderPermanent: bhHeaderPermanent,
            blackHolesHeaderPaused: bhHeaderPaused,
            headerEnslavedChargeVisible: enslavedChargeVisible,
            headerEnslavedIsCharging: enslavedIsCharging
        )
        let finalState = state
        let isFirst = !self._isInitializedInternal
        if isFirst { self._isInitializedInternal = true }
        // Capture the unlock-flag generation as it was when we read JS
        // state. If main's commit sees a newer value, a resetUnlockFlags()
        // ran between the read and the commit — skip the sticky-true block
        // so this stale snapshot can't re-assert flags we just zeroed.
        let capturedUnlockFlagsGen = self.unlockFlagsGen

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Web `END_NUMBERS` (endState >= 4.2): visible numbers freeze
            // mid-finale. We commit GameEnd flags first so the freeze
            // can lift, then bail out before any of the numeric writes
            // below. Structural writes (tab unlocks, pelleDoomed) also
            // skip — their last-known value sticks for the rest of the
            // run, which is fine because the credits overlay covers the
            // whole UI by then.
            if self.endStateValue != gameEndES { self.endStateValue = gameEndES }
            if self.gameEndCreditsClosed != gameEndCC { self.gameEndCreditsClosed = gameEndCC }
            if gameEndES >= GameEndMarker.endNumbers { return }
            if self.antimatter != header.antimatter { self.antimatter = header.antimatter }
            if self.antimatterPerSec != header.antimatterPerSec { self.antimatterPerSec = header.antimatterPerSec }
            if self.progressFill != header.progressFill { self.progressFill = header.progressFill }
            if self.tickspeedUnlocked != header.tickspeedUnlocked { self.tickspeedUnlocked = header.tickspeedUnlocked }
            if self.tickspeedMultiplier != header.tickspeedMultiplier { self.tickspeedMultiplier = header.tickspeedMultiplier }
            if self.tickspeedPerSecond != header.tickspeedPerSecond { self.tickspeedPerSecond = header.tickspeedPerSecond }
            if self.currentIP != header.currentIP { self.currentIP = header.currentIP }
            if self.replicantiAmountHeader != header.replicantiAmount { self.replicantiAmountHeader = header.replicantiAmount }
            if self.replicantiUnlocked != header.replicantiUnlocked { self.replicantiUnlocked = header.replicantiUnlocked }
            // Tab-visibility unlock flags: only propagate TRUE transitions.
            // During Reality/Eternity, these flags momentarily go false then
            // restore within 1-2 ticks. Publishing the false transition causes
            // availableTabs/currentAvailableSubtabs to shrink, which destroys
            // and recreates the SubtabPager (iPhone) or hides sidebar tabs
            // (iPad), yanking the user to the Dimensions tab.
            // Explicit resets (hardReset, importSave, switchSlot, restoreBackup)
            // call resetUnlockFlags() directly. They also bump `unlockFlagsGen`,
            // and we skip the sticky-true block if our captured generation no
            // longer matches — that means a reset ran between when we read JS
            // state and now, so the captured `header.X` values are stale and
            // would otherwise re-assert flags we just zeroed.
            if capturedUnlockFlagsGen == self.unlockFlagsGen {
                if header.infinityUnlocked && !self.infinityUnlocked { self.infinityUnlocked = true }
                if header.autobuyersUnlocked && !self.autobuyersUnlocked { self.autobuyersUnlocked = true }
            }
            if self.challengeDisplayText != header.challengeDisplayText { self.challengeDisplayText = header.challengeDisplayText }
            if self.challengePowerText != header.challengePowerText { self.challengePowerText = header.challengePowerText }
            if self.quickResetAvailable != header.quickResetAvailable { self.quickResetAvailable = header.quickResetAvailable }
            if self.quickResetHasBoosts != header.quickResetHasBoosts { self.quickResetHasBoosts = header.quickResetHasBoosts }
            if capturedUnlockFlagsGen == self.unlockFlagsGen {
                if idUnlocked && !self.infinityDimsUnlocked { self.infinityDimsUnlocked = true }
                if eternityReached && !self.eternityUnlocked { self.eternityUnlocked = true }
                if dilationReached && !self.dilationUnlocked { self.dilationUnlocked = true }
                if ecAvailable && !self.eternityChallengesUnlocked { self.eternityChallengesUnlocked = true }
                if realityReached && !self.realityUnlocked { self.realityUnlocked = true }
                if realityStudyBought && !self.realityStudyBought { self.realityStudyBought = true }
                if teresaReached && !self.teresaUnlocked { self.teresaUnlocked = true }
                if effarigReached && !self.effarigUnlocked { self.effarigUnlocked = true }
                if effarigEternityReached && !self.effarigEternityUnlocked { self.effarigEternityUnlocked = true }
                if vReached && !self.vUnlocked { self.vUnlocked = true }
                if raReached && !self.raUnlocked { self.raUnlocked = true }
            }
            if self.imaginaryUpgradesUnlocked != imReached { self.imaginaryUpgradesUnlocked = imReached }
            if self.glyphAlchemyUnlocked != alchemyReached { self.glyphAlchemyUnlocked = alchemyReached }
            if self.laitelaUnlocked != laitelaReached { self.laitelaUnlocked = laitelaReached }
            if self.pelleUnlocked != pelleUnlockedFlag { self.pelleUnlocked = pelleUnlockedFlag }
            if self.pelleDoomed != pelleDoomedFlag { self.pelleDoomed = pelleDoomedFlag }
            if self.autobuyersGloballyOn != abGloballyOn { self.autobuyersGloballyOn = abGloballyOn }
            if self.pelleCanArmageddon != pelleCanArmFlag { self.pelleCanArmageddon = pelleCanArmFlag }
            if self.pelleRemnantsGainText != pelleRemnantsStr { self.pelleRemnantsGainText = pelleRemnantsStr }
            if self.pelleRealityShardsText != pelleRSStr { self.pelleRealityShardsText = pelleRSStr }
            if self.pelleRealityShardsPerSecText != pelleRSpsStr { self.pelleRealityShardsPerSecText = pelleRSpsStr }
            if self.pelleRealityShardsRateAfterText != pelleRSnextStr { self.pelleRealityShardsRateAfterText = pelleRSnextStr }
            if self.pelleGlyphEquippingDisabled != pelleGlyphEqDisFlag { self.pelleGlyphEquippingDisabled = pelleGlyphEqDisFlag }
            // GameEnd flags committed at top of this main-dispatch block
            // (before the END_NUMBERS early return) so the freeze can lift.
            if self.continuumUnlocked != continuumUnlockedFlag { self.continuumUnlocked = continuumUnlockedFlag }
            if self.continuumDisabled != continuumDisabledFlag { self.continuumDisabled = continuumDisabledFlag }
            if self.laiAutoDimUnlocked  != laiAutoDimUnlockedFlag  { self.laiAutoDimUnlocked  = laiAutoDimUnlockedFlag }
            if self.laiAutoDimActive    != laiAutoDimActiveFlag    { self.laiAutoDimActive    = laiAutoDimActiveFlag }
            if self.laiAutoAscUnlocked  != laiAutoAscUnlockedFlag  { self.laiAutoAscUnlocked  = laiAutoAscUnlockedFlag }
            if self.laiAutoAscActive    != laiAutoAscActiveFlag    { self.laiAutoAscActive    = laiAutoAscActiveFlag }
            if self.laiAutoSingUnlocked != laiAutoSingUnlockedFlag { self.laiAutoSingUnlocked = laiAutoSingUnlockedFlag }
            if self.laiAutoSingActive   != laiAutoSingActiveFlag   { self.laiAutoSingActive   = laiAutoSingActiveFlag }
            if self.laiAutoAnniUnlocked != laiAutoAnniUnlockedFlag { self.laiAutoAnniUnlocked = laiAutoAnniUnlockedFlag }
            if self.laiAutoAnniActive   != laiAutoAnniActiveFlag   { self.laiAutoAnniActive   = laiAutoAnniActiveFlag }
            if self.laiAutoAnniMultiplier != laiAutoAnniMultiplierFlag { self.laiAutoAnniMultiplier = laiAutoAnniMultiplierFlag }
            if self.currentCelestialReality != celestialRealityName { self.currentCelestialReality = celestialRealityName }
            if self.realityButtonSpecial != realityButtonSpecialFlag { self.realityButtonSpecial = realityButtonSpecialFlag }
            if self.enslavedIsRunning != enslavedRunningFlag { self.enslavedIsRunning = enslavedRunningFlag }
            if self.enslavedHasSecretStudy != enslavedHasSecretStudyFlag { self.enslavedHasSecretStudy = enslavedHasSecretStudyFlag }
            if self.secretTSVisible != secretTSVisibleFlag { self.secretTSVisible = secretTSVisibleFlag }
            if self.enslavedFeltEternity != enslavedFeltEternityFlag { self.enslavedFeltEternity = enslavedFeltEternityFlag }
            if self.enslavedCompleted != enslavedCompletedFlag { self.enslavedCompleted = enslavedCompletedFlag }
            if self.tesseractAffordable != tesseractAffordableFlag { self.tesseractAffordable = tesseractAffordableFlag }
            if self.enslavedHintTimerVisible != enslavedHintTimerVisibleFlag { self.enslavedHintTimerVisible = enslavedHintTimerVisibleFlag }
            if self.enslavedHintTimerText != enslavedHintTimerTextStr { self.enslavedHintTimerText = enslavedHintTimerTextStr }
            if self.laitelaRunEntropyText != laitelaRunEntropyStr { self.laitelaRunEntropyText = laitelaRunEntropyStr }
            if self.laitelaRunGameSpeedText != laitelaRunGameSpeedStr { self.laitelaRunGameSpeedText = laitelaRunGameSpeedStr }
            if self.currentRM != currentRMStr { self.currentRM = currentRMStr }
            if self.currentRMHeaderDisplay != rmHeaderDisplayStr { self.currentRMHeaderDisplay = rmHeaderDisplayStr }
            if self.gameSpeedText != gameSpeedStr { self.gameSpeedText = gameSpeedStr }
            // Stable visibility bools for iPhone header gating — see
            // `compactGameSpeedVisible` / `compactBannerVisible` declarations.
            let gameSpeedVisibleFlag = !gameSpeedStr.isEmpty
            if self.compactGameSpeedVisible != gameSpeedVisibleFlag { self.compactGameSpeedVisible = gameSpeedVisibleFlag }
            let isInChallengeFlag = !header.challengeDisplayText.isEmpty
                && !header.challengeDisplayText.contains("no active challenges")
            let bannerVisibleFlag = isInChallengeFlag || !celestialRealityName.isEmpty
            if self.compactBannerVisible != bannerVisibleFlag { self.compactBannerVisible = bannerVisibleFlag }
            // Mirrors `CompactChallengeLabel.exitText` non-empty: the banner
            // shows an Exit button in any challenge (even while Doomed — you
            // can exit the EC), or in a non-doomed celestial reality. Doom
            // WITHOUT a challenge is the only banner state with no Exit.
            let bannerHasExitFlag = isInChallengeFlag || (!pelleDoomedFlag && !celestialRealityName.isEmpty)
            if self.compactBannerHasExit != bannerHasExitFlag { self.compactBannerHasExit = bannerHasExitFlag }
            // Mirror the four `infinity` fields PhoneShell.compactHeaderHeight
            // reads. The struct gets reassigned every tick by pollDirect; these
            // diff-checked bools invalidate only on actual transition.
            let infForCompact = finalState.infinity
            if self.compactShowEPRate != infForCompact.showEPRate { self.compactShowEPRate = infForCompact.showEPRate }
            if self.compactShowIPRate != infForCompact.showIPRate { self.compactShowIPRate = infForCompact.showIPRate }
            if self.compactIsBroken != infForCompact.isBroken { self.compactIsBroken = infForCompact.isBroken }
            if self.compactShowRealityButton != infForCompact.showRealityButton { self.compactShowRealityButton = infForCompact.showRealityButton }
            // STICKY — only depends on `!isBroken && infinityUnlocked`, NOT
            // on `canCrunch`. During autobuyer cycling, `canCrunch` flips
            // false→true at 1–2 Hz; if we let the slot reservation flap with
            // it, `compactHeaderHeight` oscillates by 80pt every tick.
            // A long enough `canCrunch=false` window lets the shrink
            // debounce fire, and the grow-back doesn't always reach
            // `stableHeaderHeight` (e.g. pendingHeaderHeight stash during a
            // swipe). The button inside the slot stays always-visible
            // post-first-crunch — it already renders "Reach <goal>" when
            // `canCrunch=false`, matching the post-break crunch button.
            let preBreakCrunchFlag = !infForCompact.isBroken && infForCompact.infinityUnlocked
            if self.compactShowPreBreakCrunch != preBreakCrunchFlag { self.compactShowPreBreakCrunch = preBreakCrunchFlag }
            let challengePowerVisibleFlag = !header.challengePowerText.isEmpty
            if self.compactChallengePowerVisible != challengePowerVisibleFlag { self.compactChallengePowerVisible = challengePowerVisibleFlag }
            if self.blackHolesHeaderVisible != header.blackHolesHeaderVisible { self.blackHolesHeaderVisible = header.blackHolesHeaderVisible }
            if self.blackHoleHeaderPauseText != header.blackHoleHeaderPauseText { self.blackHoleHeaderPauseText = header.blackHoleHeaderPauseText }
            if self.blackHoleHeaderStates != header.blackHoleHeaderStates { self.blackHoleHeaderStates = header.blackHoleHeaderStates }
            if self.blackHolesHeaderPermanent != header.blackHolesHeaderPermanent { self.blackHolesHeaderPermanent = header.blackHolesHeaderPermanent }
            if self.blackHolesHeaderPaused != header.blackHolesHeaderPaused { self.blackHolesHeaderPaused = header.blackHolesHeaderPaused }
            if self.headerEnslavedChargeVisible != header.headerEnslavedChargeVisible { self.headerEnslavedChargeVisible = header.headerEnslavedChargeVisible }
            if self.headerEnslavedIsCharging != header.headerEnslavedIsCharging { self.headerEnslavedIsCharging = header.headerEnslavedIsCharging }
            if self.headerCanPulse != canPulseFlag { self.headerCanPulse = canPulseFlag }
            if self.headerIsPulsing != isPulsingFlag { self.headerIsPulsing = isPulsingFlag }
            if self.headerCanDischarge != canDischargeFlag { self.headerCanDischarge = canDischargeFlag }
            if self.headerStoredTimeText != storedTimeStr { self.headerStoredTimeText = storedTimeStr }
            if self.headerPulsedSpeedText != pulsedSpeedStr { self.headerPulsedSpeedText = pulsedSpeedStr }
            if self.headerIsGameSpeedPulsing != gameSpeedIsPulsingFlag { self.headerIsGameSpeedPulsing = gameSpeedIsPulsingFlag }
            if self.currentEP != epStr { self.currentEP = epStr }
            if self.currentTT != ttStr { self.currentTT = ttStr }
            if self.currentTP != tpStr { self.currentTP = tpStr }
            if self.currentDT != dtStr { self.currentDT = dtStr }
            if self.currentRelicShards != relicShardsStr { self.currentRelicShards = relicShardsStr }
            if self.currentImaginaryMachines != imStr { self.currentImaginaryMachines = imStr }
            if self.currentMachinesCombined != machinesCombinedStr { self.currentMachinesCombined = machinesCombinedStr }
            if self.currentDarkMatter != darkMatterStr { self.currentDarkMatter = darkMatterStr }
            if self.currentDarkEnergy != darkEnergyStr { self.currentDarkEnergy = darkEnergyStr }
            if self.currentSingularities != singularitiesStr { self.currentSingularities = singularitiesStr }
            if self.notifiedSubtabs != newNotifiedSubtabs { self.notifiedSubtabs = newNotifiedSubtabs }
            if self.newsEnabled != newsOn { self.newsEnabled = newsOn }
            if self.newsSpeed != newsSpd { self.newsSpeed = newsSpd }
            if self.automaticTabSwitching != autoTabSwitching { self.automaticTabSwitching = autoTabSwitching }
            if self.offlineProgressEnabledOption != offlineProgOpt { self.offlineProgressEnabledOption = offlineProgOpt }
            if self.offlineTicksValue != offlineTicksRaw { self.offlineTicksValue = offlineTicksRaw }
            if self.automatorLogMaxEntries != automatorLogMax { self.automatorLogMaxEntries = automatorLogMax }
            if self.glyphTextColorsOption != glyphTxtColors { self.glyphTextColorsOption = glyphTxtColors }
            if self.hideAlterationOption != hideAlterFx { self.hideAlterationOption = hideAlterFx }
            if self.glyphSelectionConfirmation != glyphSelConfirm { self.glyphSelectionConfirmation = glyphSelConfirm }
            if self.hiddenTabBits != hiddenTabsRaw { self.hiddenTabBits = hiddenTabsRaw }
            if self.hiddenSubtabBits != hiddenSubtabsRaw { self.hiddenSubtabBits = hiddenSubtabsRaw }
            // Update the Swift-side formatter dispatcher. Unsupported web
            // notations fall back to mixed scientific.
            let supported = GameNotation(rawValue: rawNotation) ?? .mixedScientific
            if NotationFormatter.current != supported { NotationFormatter.current = supported }
            if self.notationName != rawNotation { self.notationName = rawNotation }
            if finalState != self.gameState { self.gameState = finalState }
            if isFirst { self.isInitialized = true }

            // Defensive: if the active tab/subtab got hidden via save import,
            // cross-device sync, or a programmatic bit flip, snap to the
            // first visible-available choice. Covers all save-lifecycle
            // entry points without each one needing to call recovery
            // explicitly — the moment a new player object lands and the
            // first pollDirect commits the new bits, this self-heals.
            // No-op when no shell is mounted yet (sidebarStateRef is nil).
            self.recoverFromHiddenActiveTab()
        }

        // --- Performance reporting ---
        let totalMs = (t5 - pollStart) * 1000
        let dimsMs = (t0 - pollStart) * 1000
        let achMs = (t1 - t0) * 1000
        let infMs = (t2 - t1) * 1000
        let infDimMs = (t3 - t2) * 1000
        let autoMs = (t4 - t3) * 1000
        let statsMs = (t5 - t4) * 1000

        // Periodic GC every 5 seconds
        let perfNow = CFAbsoluteTimeGetCurrent()
        if perfLastReport == 0 { perfLastReport = perfNow }
        let perfElapsed = perfNow - perfLastReport

        #if DEBUG
        if _perfLoggingEnabled {
            perfPollCount += 1
            perfTotalMs += totalMs
            perfSectionMs["dims", default: 0] += dimsMs
            perfSectionMs["ach", default: 0] += achMs
            perfSectionMs["inf", default: 0] += infMs
            perfSectionMs["infDim", default: 0] += infDimMs
            perfSectionMs["auto", default: 0] += autoMs
            perfSectionMs["stats", default: 0] += statsMs
        }
        #endif

        if perfElapsed >= 5.0 {
            #if DEBUG
            if _perfLoggingEnabled && perfPollCount > 0 {
                let n = Double(perfPollCount)
                let avg = perfTotalMs / n
                let d = perfSectionMs["dims", default: 0] / n
                let a = perfSectionMs["ach", default: 0] / n
                let inf = perfSectionMs["inf", default: 0] / n
                let id = perfSectionMs["infDim", default: 0] / n
                let au = perfSectionMs["auto", default: 0] / n
                let st = perfSectionMs["stats", default: 0] / n
                var taskInfo = mach_task_basic_info()
                var infoCount = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
                withUnsafeMutablePointer(to: &taskInfo) { ptr in
                    ptr.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) { intPtr in
                        _ = task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPtr, &infoCount)
                    }
                }
                let memMB = Double(taskInfo.resident_size) / 1_048_576.0

                let jsLoopCount = context.evaluateScript("_gameLoopCallCount")?.toInt32() ?? 0
                let lastDiff = context.evaluateScript("_lastGameLoopDiff")?.toDouble() ?? 0
                let jsMs = context.evaluateScript("_lastGameLoopMs")?.toDouble() ?? 0
                context.evaluateScript("_gameLoopCallCount = 0")
                let wallHz = n / 5.0
                debugLog(String(format: "PERF [5s]: %d polls (%.0fHz), JS ticks:%d diff:%.0fms jsLoop:%.0fms, avg poll:%.1fms, mem:%.0fMB | dims:%.1f ach:%.1f inf:%.1f infDim:%.1f auto:%.1f stats:%.1f",
                             perfPollCount, wallHz, jsLoopCount, lastDiff, jsMs, avg, memMB, d, a, inf, id, au, st))

                // JS game loop profiler breakdown
                if _jsProfilerInjected {
                    if let profJson = context.evaluateScript("""
                        (function() {
                            var p = gameLoop._prof;
                            var s = JSON.stringify(p);
                            var keys = Object.keys(p);
                            for (var i = 0; i < keys.length; i++) p[keys[i]] = 0;
                            return s;
                        })()
                        """)?.toString(),
                       let profData = profJson.data(using: .utf8),
                       let p = try? JSONSerialization.jsonObject(with: profData) as? [String: Double],
                       let ticks = p["ticks"], ticks > 0 {
                        let t = ticks
                        let total = (p["total"] ?? 0) / t
                        let ad = (p["adTick"] ?? 0) / t
                        let idim = (p["idTick"] ?? 0) / t
                        let td = (p["tdTick"] ?? 0) / t
                        let repl = (p["replicanti"] ?? 0) / t
                        let auto = (p["autobuyers"] ?? 0) / t
                        let chal = (p["challenges"] ?? 0) / t
                        let ip = (p["ipGen"] ?? 0) / t
                        let prest = (p["prestigeGen"] ?? 0) / t
                        let aprest = (p["autoprestige"] ?? 0) / t
                        let bh = (p["blackHoles"] ?? 0) / t
                        let rt = (p["realTime"] ?? 0) / t
                        let ach = (p["achievements"] ?? 0) / t
                        let spd = (p["speedFactor"] ?? 0) / t
                        let tracked = ad + idim + td + repl + auto + chal + ip + prest + aprest + bh + rt + ach + spd
                        let misc = max(0, total - tracked)
                        // AD sub-probes
                        let adMult = (p["adMult"] ?? 0) / t
                        let adCommon = (p["adCommon"] ?? 0) / t
                        let adProd = max(0, ad - adMult)
                        // Autobuyer sub-probes
                        let autoDim = (p["autoDim"] ?? 0) / t
                        let autoOther = (p["autoOther"] ?? 0) / t
                        let autoOverhead = max(0, auto - autoDim - autoOther)

                        debugLog(String(format: "JS-PROF [5s]: %.0f ticks, avg %.2fms | AD:%.2f(mult:%.2f common:%.2f prod:%.2f) ID:%.2f TD:%.2f repl:%.2f auto:%.2f(dim:%.2f other:%.2f oh:%.2f) chal:%.2f misc:%.2f",
                                     ticks, total, ad, adMult, adCommon, adProd, idim, td, repl, auto, autoDim, autoOther, autoOverhead, chal, misc))
                    }
                }

                perfPollCount = 0; perfTotalMs = 0; perfSectionMs = [:]
                perfEventCount = 0
            }
            #endif
            perfLastReport = perfNow
            JSGarbageCollect(context.jsGlobalContextRef)
        }
      } // autoreleasepool
    }

    // MARK: - Section poll helpers

    /// Collapse multiline JS template literal whitespace into single spaces.
    private func normalizeWhitespace(_ s: String) -> String {
        s.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Extract a string from a JSValue that may be a plain string or a function,
    /// normalize whitespace, and return a clean result.
    ///
    /// Function-valued descriptions can throw at runtime — many web template
    /// literals reference globals that may not be defined at every game stage
    /// (e.g. EC9/EC10 descriptions call `specialInfinityGlyphDisabledEffectText()`
    /// which reads `PelleRifts.chaos.milestones[1].canBeApplied`; EC10 also
    /// calls `EternityChallenge(10).applyEffect(...)`). A bare `.call()` lets
    /// those exceptions reach the global JS exception handler — the user
    /// sees `🔴 JS: TypeError: undefined is not an object` per tick.
    ///
    /// We stash the function on globalThis and invoke it from inside a JS
    /// try/catch. Earlier attempts swapped the JSContext's `exceptionHandler`
    /// around a direct `.call()` — that approach was correlated with EXC_BAD_ACCESS
    /// at later JSValue reads, suggesting the swap-and-restore isn't safe under
    /// JSCore's autorelease semantics. Routing the call through `evaluateScript`
    /// keeps everything on the JS side; any thrown exception is caught by the
    /// inner `try`, never reaches the JSContext exception handler, and no
    /// JSValue lifetime is at risk.
    private func extractNormalizedString(from jsVal: JSValue?) -> String {
        guard let val = jsVal else { return "" }
        let raw: String
        if val.isObject == true, let ctx = val.context {
            let probe = "_amSafeFn"
            ctx.globalObject.setObject(val, forKeyedSubscript: probe as NSString)
            let out = ctx.evaluateScript("""
                (function() {
                    try {
                        var r = \(probe)();
                        return r === undefined || r === null ? "" : String(r);
                    } catch (e) { return ""; }
                })()
                """)?.toString() ?? ""
            // Clear the slot so the function reference doesn't pin val
            // across ticks. JS-level delete keeps everything on the JS
            // side and matches how globalThis property cleanup is normally
            // done; no JSValue lifetime dance.
            _ = ctx.evaluateScript("delete globalThis.\(probe)")
            raw = out
        } else {
            raw = val.toString() ?? ""
        }
        return raw.replacingOccurrences(
            of: "\\s+", with: " ", options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)
    }

    /// Strips HTML from web-sourced text (toast + modal messages). Converts
    /// every `<br>` variant (with/without slash, with/without space, numeric
    /// entity, encoded, uppercased) to a newline, drops any other tag, and
    /// decodes the most common named entities. Also collapses per-line
    /// whitespace without squashing the line breaks themselves.
    static func sanitizeNotifyText(_ raw: String, collapseNewlines: Bool = false) -> String {
        var s = raw
        // 1) Decode HTML-encoded angle brackets first so `&lt;br&gt;` paths
        //    fall into the same replacement as literal `<br>`.
        s = s.replacingOccurrences(of: "&lt;", with: "<", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "&gt;", with: ">", options: .caseInsensitive)
        // 2) Every `<br …>` variant → newline. Use a regex so whitespace and
        //    case differences don't matter.
        if let brRe = try? NSRegularExpression(pattern: "<\\s*br\\s*/?\\s*>", options: [.caseInsensitive]) {
            let range = NSRange(s.startIndex..., in: s)
            s = brRe.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "\n")
        }
        // 3) Paragraph / div tags → newline boundaries.
        if let blockRe = try? NSRegularExpression(pattern: "</(p|div|li)\\s*>", options: [.caseInsensitive]) {
            let range = NSRange(s.startIndex..., in: s)
            s = blockRe.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "\n")
        }
        // 4) Drop any remaining simple tags.
        if let re = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            let range = NSRange(s.startIndex..., in: s)
            s = re.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "")
        }
        // 5) Common named entities.
        let entities: [(String, String)] = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&#39;", "'"),
            ("&#160;", " "),
        ]
        for (ent, repl) in entities {
            s = s.replacingOccurrences(of: ent, with: repl, options: .caseInsensitive)
        }
        // 6) Normalise whitespace on each line (collapse runs of spaces/tabs)
        //    but preserve newline structure.
        let lines = s.components(separatedBy: "\n").map { line -> String in
            line.components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        if collapseNewlines {
            return lines.filter { !$0.isEmpty }.joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strips font-awesome HTML from BlackHole.displayState and replaces with Unicode icons
    private static func stripBHDisplayHTML(_ html: String) -> String {
        var result = html
        let iconMap: [(String, String)] = [
            ("fa-play", "▶\u{fe0e} "),
            ("fa-redo", "↻ "),
            ("fa-pause", "⏸\u{fe0e} "),
            ("fa-infinity", "∞ "),
            ("fa-caret-left", "◀\u{fe0e} "),
            // Pulse-state markers — replaced inline in the view with an SF
            // Symbol (`arrow.up.left.and.arrow.down.right`) so it matches the
            // Pulse toggle icon. The token must be a stable substring the
            // view can split on.
            ("fa-compress-arrows-alt", "⟦PULSE⟧"),
            ("fa-expand-arrows-alt", "⟦PULSE⟧"),
            ("fa-ban", "🚫 "),
        ]
        for (cls, unicode) in iconMap {
            if result.contains(cls) {
                // Replace the entire <i ...></i> tag containing this class
                result = result.replacingOccurrences(
                    of: "<i[^>]*\(cls)[^>]*></i>\\s*",
                    with: unicode,
                    options: .regularExpression
                )
            }
        }
        // Strip any remaining HTML tags
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespaces)
    }

    private func pollAchievements(_ state: inout GameState) {
        let allAch = jsAchievements.forProperty("all")
        let count = Int(allAch?.forProperty("length")?.toInt32() ?? 0)
        let realityDone = context.evaluateScript("PlayerProgress.realityUnlocked()")?.toBool() ?? false
        var achs: [AchievementState] = []
        achs.reserveCapacity(count)
        for i in 0..<count {
            let a = allAch?.atIndex(i)
            let config = a?.forProperty("config")
            let descVal = config?.forProperty("description")
            let desc: String
            if descVal?.isObject == true {
                desc = normalizeWhitespace(descVal?.call(withArguments: [])?.toString() ?? "")
            } else {
                desc = normalizeWhitespace(descVal?.toString() ?? "")
            }
            let rwdVal = config?.forProperty("reward")
            let reward: String?
            let hasReward = !(rwdVal?.isUndefined ?? true)
            if hasReward {
                if rwdVal?.isObject == true {
                    reward = normalizeWhitespace(rwdVal?.call(withArguments: [])?.toString() ?? "")
                } else {
                    reward = normalizeWhitespace(rwdVal?.toString() ?? "")
                }
            } else {
                reward = nil
            }
            let isUnlocked = a?.forProperty("isUnlocked")?.toBool() ?? false
            let row = Int(a?.forProperty("row")?.toInt32() ?? 0)
            achs.append(AchievementState(
                id: Int(a?.forProperty("id")?.toInt32() ?? 0),
                name: config?.forProperty("name")?.toString() ?? "",
                description: desc,
                isUnlocked: isUnlocked,
                hasReward: hasReward,
                reward: reward,
                row: row,
                column: Int(a?.forProperty("column")?.toInt32() ?? 0),
                isWaiting: realityDone && row <= 13 && !isUnlocked,
                isObscured: row == 18 && !isUnlocked  // Web: row 18 hidden until Pelle doomed
            ))
        }
        state.achievements = achs

        // Achievements.power is a plain JS number, not a break_infinity Decimal.
        // Use `init(double:)` so the mantissa is normalized to [1, 10) — without
        // it, large values (e.g. 1.89e20) keep mantissa unnormalized and
        // exponent=0, which makes formatDecimal hit the "under 1000" branch
        // and emit garbage like "×1.89e20" instead of respecting the user's
        // notation choice.
        let achPowerVal = jsAchievements.forProperty("power")?.toDouble() ?? 1
        let achPower = GameDecimal(double: achPowerVal)
        state.achievementPower = formatX(achPower, places: 2, placesUnder1000: 3)

        // Mirrors `NormalAchievementsTab.vue`'s update() — five conditional
        // gates that decide which extra multiplier lines render under
        // "Achievements provide a multiplier to:". Pre-Eternity / pre-V /
        // pre-Ra saves don't have the parent objects, so we defensively
        // probe each one JS-side and return JSON. Without this, naïve
        // `evaluateScript("VUnlocks.achievementBH.canBeApplied")` throws
        // every tick on early saves.
        let achGatesJSON = context.evaluateScript("""
        (function() {
          var out = { ids: false, tds: false, tp: false, bh: false, tt: false, tpMult: 1 };
          try { out.ids = !!Achievement(75).isUnlocked; } catch(e) {}
          try { out.tds = !!EternityUpgrade.tdMultAchs.isBought; } catch(e) {}
          try {
            out.tp = !!RealityUpgrade(8).isBought;
            if (out.tp) {
              var v = RealityUpgrade(8).config.effect();
              out.tpMult = (typeof v === 'number') ? v : (v && typeof v.toNumber === 'function' ? v.toNumber() : 1);
            }
          } catch(e) {}
          try { out.bh = !!VUnlocks.achievementBH.canBeApplied; } catch(e) {}
          try { out.tt = !!Ra.unlocks.achievementTTMult.canBeApplied; } catch(e) {}
          return JSON.stringify(out);
        })()
        """)?.toString() ?? "{}"
        if let data = achGatesJSON.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            state.achMultToIDS = (dict["ids"] as? Bool) ?? false
            state.achMultToTDS = (dict["tds"] as? Bool) ?? false
            state.achMultToTP = (dict["tp"] as? Bool) ?? false
            state.achMultToBH = (dict["bh"] as? Bool) ?? false
            state.achMultToTT = (dict["tt"] as? Bool) ?? false
            if state.achMultToTP {
                let tpEffectVal = (dict["tpMult"] as? Double) ?? 1
                state.achTPMultiplier = formatX(GameDecimal(double: tpEffectVal), places: 2, placesUnder1000: 3)
            } else {
                state.achTPMultiplier = ""
            }
        }

        // Auto-achieve countdown — mirrors NormalAchievementsTab.vue update().
        // Hidden pre-Reality and once Perk(205) is bought.
        let timerJSON = context.evaluateScript("""
            (function() {
              try {
                if (typeof PlayerProgress === "undefined" || !PlayerProgress.realityUnlocked()) {
                  return JSON.stringify({ visible: false });
                }
                var perkBought = false;
                try { perkBought = !!Perk.achievementGroup5.isBought; } catch (e) {}
                if (perkBought) return JSON.stringify({ visible: false });

                var speed = (typeof getGameSpeedupFactor === "function") ? getGameSpeedupFactor() : 1;
                if (!speed || !isFinite(speed) || speed <= 0) speed = 1;

                var period = Achievements.period;
                var remainMs = Achievements.timeToNextAutoAchieve;
                var missing = Achievements.preReality.countWhere(function(a) { return !a.isUnlocked; });

                // Both values stay in MILLISECONDS to match what
                // timeDisplayNoDecimals(ms) expects. Mirrors the web's
                // NormalAchievementsTab.vue update() exactly — its
                // `achCountdown` / `totalCountdown` are also ms.
                var nextMs = remainMs / speed;
                var totalMs = (missing > 0) ? (((missing - 1) * period + remainMs) / speed) : 0;

                var fmt = (typeof timeDisplayNoDecimals === "function") ? timeDisplayNoDecimals : function(ms) { return Math.round(ms / 1000) + "s"; };
                return JSON.stringify({
                  visible: true,
                  autoActive: !!player.reality.autoAchieve,
                  missing: missing,
                  nextSeconds: nextMs / 1000,
                  totalSeconds: totalMs / 1000,
                  nextText: (nextMs > 0 && missing > 0) ? fmt(nextMs) : "",
                  totalText: (totalMs > 0 && missing > 0) ? fmt(totalMs) : ""
                });
              } catch (e) {
                return JSON.stringify({ visible: false });
              }
            })();
        """)?.toString() ?? "{}"

        var timer = AchievementTimerState()
        if let data = timerJSON.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            timer.isVisible = obj["visible"] as? Bool ?? false
            if timer.isVisible {
                timer.isAutoActive = obj["autoActive"] as? Bool ?? false
                timer.missingCount = obj["missing"] as? Int ?? 0
                timer.nextSeconds = obj["nextSeconds"] as? Double ?? 0
                timer.totalSeconds = obj["totalSeconds"] as? Double ?? 0
                timer.nextCountdownText = obj["nextText"] as? String ?? ""
                timer.totalCountdownText = obj["totalText"] as? String ?? ""
            }
        }
        state.achievementTimer = timer
    }

    /// Bulk-JSON poll of the 32 Secret Achievements. Reads cached JSON from
    /// `_nativeSecretAchievementsState()` — see `secret-achievements-helper.js`.
    /// Tab-gated on `.achievements`; the helper itself caches by event so the
    /// per-tick cost on this subtab is one `evaluateScript` + one
    /// `JSONSerialization.jsonObject` against a small payload.
    private func pollSecretAchievements(_ state: inout GameState) {
        guard let json = context.evaluateScript("_nativeSecretAchievementsState()")?.toString(),
              let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            state.secretAchievements = .empty
            return
        }

        let rawRows = root["rows"] as? [[[String: Any]]] ?? []
        var rows: [[SecretAchievementInfo]] = []
        rows.reserveCapacity(rawRows.count)
        for rawRow in rawRows {
            var row: [SecretAchievementInfo] = []
            row.reserveCapacity(rawRow.count)
            for entry in rawRow {
                let id = (entry["id"] as? Int) ?? Int(entry["id"] as? Double ?? 0)
                let name = entry["name"] as? String ?? ""
                let desc = entry["description"] as? String ?? ""
                let unlocked = entry["isUnlocked"] as? Bool ?? false
                let r = (entry["row"] as? Int) ?? Int(entry["row"] as? Double ?? 0)
                let c = (entry["column"] as? Int) ?? Int(entry["column"] as? Double ?? 0)
                row.append(SecretAchievementInfo(
                    id: id,
                    name: name,
                    description: desc,
                    isUnlocked: unlocked,
                    row: r,
                    column: c
                ))
            }
            rows.append(row)
        }

        let total = (root["totalCount"] as? Int) ?? Int(root["totalCount"] as? Double ?? 0)
        let unlocked = (root["unlockedCount"] as? Int) ?? Int(root["unlockedCount"] as? Double ?? 0)

        state.secretAchievements = SecretAchievementsState(
            rows: rows,
            unlockedCount: unlocked,
            totalCount: total
        )
    }

    /// Full infinity upgrades poll — only when Infinity tab is visible.
    private func pollInfinityUpgrades(_ state: inout GameState) {
        let upgradeLayout: [(key: String, col: Int, row: Int)] = [
            ("totalTimeMult",0,0), ("dim18mult",0,1), ("dim36mult",0,2), ("resetBoost",0,3),
            ("buy10Mult",1,0), ("dim27mult",1,1), ("dim45mult",1,2), ("galaxyBoost",1,3),
            ("thisInfinityTimeMult",2,0), ("unspentIPMult",2,1), ("dimboostMult",2,2), ("ipGen",2,3),
            ("skipReset1",3,0), ("skipReset2",3,1), ("skipReset3",3,2), ("skipResetGalaxy",3,3)
        ]

        // Charge unlock state (Ra Teresa pet lv 2). Single eval covers all 4 fields.
        let chargeJSON = context.evaluateScript("""
            (function() {
                if (typeof Ra === 'undefined' || !Ra.unlocks || !Ra.unlocks.chargedInfinityUpgrades) {
                    return JSON.stringify({ unlocked: false, total: 0, used: 0, dis: false });
                }
                var unlocked = Ra.unlocks.chargedInfinityUpgrades.canBeApplied && !(typeof Pelle !== 'undefined' && Pelle.isDoomed);
                var total = Ra.totalCharges | 0;
                var used = total - (Ra.chargesLeft | 0);
                var dis = !!(player && player.celestials && player.celestials.ra && player.celestials.ra.disCharge);
                return JSON.stringify({ unlocked: !!unlocked, total: total, used: used, dis: dis });
            })()
            """)?.toString() ?? "{}"
        var chargeUnlocked = false
        var totalCharges = 0
        var usedCharges = 0
        var disCharge = false
        if let d = chargeJSON.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            chargeUnlocked = obj["unlocked"] as? Bool ?? false
            totalCharges = obj["total"] as? Int ?? 0
            usedCharges = obj["used"] as? Int ?? 0
            disCharge = obj["dis"] as? Bool ?? false
        }

        var upgrades: [InfinityUpgradeInfo] = []
        upgrades.reserveCapacity(upgradeLayout.count)
        for info in upgradeLayout {
            let u = context.evaluateScript("InfinityUpgrade.\(info.key)")
            let config = u?.forProperty("config")
            let descVal = config?.forProperty("description")
            let desc: String
            if descVal?.isObject == true {
                desc = normalizeWhitespace(descVal?.call(withArguments: [])?.toString() ?? "")
            } else {
                desc = normalizeWhitespace(descVal?.toString() ?? "")
            }

            var effText: String? = nil
            let isBought = u?.forProperty("isBought")?.toBool() ?? false
            if isBought {
                let formatEff = config?.forProperty("formatEffect")
                if formatEff?.isObject == true {
                    let effVal = u?.forProperty("effectValue")
                    effText = formatEff?.call(withArguments: [effVal as Any])?.toString()
                }
            }

            // Charged state + charged effect description.
            // Web: config.charged.{description, effect, formatEffect}.
            // Also compute the charged effect value + formatted string so the
            // "Currently: ..." line stays meaningful in shift mode.
            var isCharged = false
            var chargedEffText: String? = nil
            if chargeUnlocked {
                isCharged = u?.forProperty("isCharged")?.toBool() ?? false
                if let charged = config?.forProperty("charged"), charged.isUndefined == false {
                    let descVal = charged.forProperty("description")
                    var descStr = ""
                    if descVal?.isObject == true {
                        descStr = normalizeWhitespace(descVal?.call(withArguments: [])?.toString() ?? "")
                    } else if let s = descVal?.toString(), s != "undefined" {
                        descStr = normalizeWhitespace(s)
                    }
                    // Append formatted charged effect value when bought.
                    if isBought, let formatEff = charged.forProperty("formatEffect"), formatEff.isObject {
                        // chargedEffect is a property on the upgrade state that
                        // wraps the charged config; its `effectValue` is the
                        // current numeric value of the charged effect.
                        let chargedState = u?.forProperty("chargedEffect")
                        let effVal = chargedState?.forProperty("effectValue")
                        if let formatted = formatEff.call(withArguments: [effVal as Any])?.toString() {
                            descStr += " (Currently: \(formatted))"
                        }
                    }
                    if !descStr.isEmpty { chargedEffText = descStr }
                }
            }

            let costVal = config?.forProperty("cost")
            let costDecimal: GameDecimal
            if costVal?.isObject == true {
                // Cost is a function or Decimal object
                let resolved = costVal?.call(withArguments: [])
                if resolved?.forProperty("mantissa")?.isUndefined == false {
                    costDecimal = GameDecimal(from: resolved)
                } else {
                    costDecimal = GameDecimal(mantissa: resolved?.toDouble() ?? 0, exponent: 0)
                }
            } else {
                // Cost is a plain number
                costDecimal = GameDecimal(mantissa: costVal?.toDouble() ?? 0, exponent: 0)
            }

            upgrades.append(InfinityUpgradeInfo(
                id: info.key,
                name: config?.forProperty("id")?.toString() ?? info.key,
                description: desc,
                cost: formatDecimal(costDecimal),
                isBought: isBought,
                canBeBought: u?.forProperty("canBeBought")?.toBool() ?? false,
                effectText: effText,
                column: info.col,
                row: info.row,
                isAvailableForPurchase: u?.forProperty("isAvailableForPurchase")?.toBool() ?? false,
                isRebuyable: false,
                isCharged: isCharged,
                chargedEffectText: chargedEffText
            ))
        }

        let ipMultUpg = context.evaluateScript("InfinityUpgrade.ipMult")
        let ipMultEffVal = GameDecimal(from: ipMultUpg?.forProperty("effectValue"))
        let ipMultCost = GameDecimal(from: ipMultUpg?.forProperty("cost"))
        let ipOfflineUpg = context.evaluateScript("InfinityUpgrade.ipOffline")
        let ipOffline = ipOfflineUpg?.forProperty("isBought")?.toBool() ?? false
        let ipOfflineConfig = ipOfflineUpg?.forProperty("config")
        let ipOfflineDescVal = ipOfflineConfig?.forProperty("description")
        let ipOfflineDesc: String
        if ipOfflineDescVal?.isObject == true {
            ipOfflineDesc = ipOfflineDescVal?.call(withArguments: [])?.toString() ?? ""
        } else {
            ipOfflineDesc = ipOfflineDescVal?.toString() ?? ""
        }
        let ipOfflineCost = GameDecimal(mantissa: ipOfflineConfig?.forProperty("cost")?.toDouble() ?? 1000, exponent: 0)
        var ipOfflineEffText: String? = nil
        if ipOffline {
            let effectVal = GameDecimal(from: ipOfflineUpg?.forProperty("effectValue"))
            ipOfflineEffText = "Currently: \(formatDecimal(effectVal, places: 2)) IP/min"
        }
        let ipOfflineInfo = InfinityUpgradeInfo(
            id: "ipOffline",
            name: "ipOffline",
            description: ipOfflineDesc,
            cost: formatDecimal(ipOfflineCost),
            isBought: ipOffline,
            canBeBought: ipOfflineUpg?.forProperty("canBeBought")?.toBool() ?? false,
            effectText: ipOfflineEffText,
            column: 4, row: 0,
            isAvailableForPurchase: ipOfflineUpg?.forProperty("isAvailableForPurchase")?.toBool() ?? false,
            isRebuyable: false,
            isCharged: false,
            chargedEffectText: nil
        )

        state.infinity.upgrades = upgrades
        state.infinity.ipOfflineUpgrade = ipOfflineInfo
        let ipMultAB = context.evaluateScript("Autobuyer.ipMult")
        let ipMultABUnlocked = ipMultAB?.forProperty("isUnlocked")?.toBool() ?? false
        let ipMultABActive = ipMultABUnlocked ? (ipMultAB?.forProperty("isActive")?.toBool() ?? false) : false
        state.infinity.ipMult = IPMultState(
            cost: formatDecimal(ipMultCost),
            multiplier: formatX(ipMultEffVal, places: 2, placesUnder1000: 2),
            purchases: clampedInt(ipMultUpg?.forProperty("purchaseCount")?.toDouble() ?? 0),
            isCapped: ipMultUpg?.forProperty("isCapped")?.toBool() ?? false,
            canBeBought: ipMultUpg?.forProperty("canBeBought")?.toBool() ?? false,
            softCap: cachedIPMultSoftCapText,
            hardCap: cachedIPMultHardCapText,
            autobuyerUnlocked: ipMultABUnlocked,
            autobuyerActive: ipMultABActive
        )
        state.infinity.ipOfflineBought = ipOffline
        state.infinity.ipMultUnlocked = context.evaluateScript("Achievement(41).isUnlocked")?.toBool() ?? false
        state.infinity.chargeInfinityUpgradesUnlocked = chargeUnlocked
        state.infinity.totalInfinityCharges = totalCharges
        state.infinity.usedInfinityCharges = usedCharges
        state.infinity.disChargeOnReality = disCharge
    }

    private func pollInfinityDimensions(_ state: inout GameState) {
        let idUnlocked = jsInfDimRefs[0].forProperty("isUnlocked")?.toBool() ?? false
        let eternityReached = jsPlayerProgress.invokeMethod("eternityUnlocked", withArguments: [])?.toBool() ?? false

        var idDims: [InfinityDimState] = []
        idDims.reserveCapacity(8)
        let currentIP = GameDecimal(from: jsCurrencyIP.forProperty("value"))
        let amReqExponents = [1100, 1900, 2400, 10500, 30000, 45000, 54000, 60000]
        for i in 0..<8 {
            let d = jsInfDimRefs[i]
            let amount = GameDecimal(from: d.forProperty("amount"))
            let mult = GameDecimal(from: d.forProperty("multiplier"))
            let cost = GameDecimal(from: d.forProperty("cost"))
            let isProducing = d.forProperty("isProducing")?.toBool() ?? false

            var roc: String? = nil
            if isProducing {
                let rocVal = GameDecimal(from: d.forProperty("rateOfChange"))
                roc = formatDecimal(rocVal, places: 2, placesUnder1000: 2)
            }

            let amReqStr = "1e\(amReqExponents[i])"

            let prevUnlocked = i == 0 || (jsInfDimRefs[i - 1].forProperty("isUnlocked")?.toBool() ?? false)

            let idAB = jsIDAutobuyerRefs[i]
            let idABUnlocked = idAB.forProperty("isUnlocked")?.toBool() ?? false
            let idABActive = idAB.forProperty("isActive")?.toBool() ?? false

            idDims.append(InfinityDimState(
                tier: i + 1,
                isUnlocked: d.forProperty("isUnlocked")?.toBool() ?? false,
                canUnlock: d.forProperty("canUnlock")?.toBool() ?? false,
                amount: formatDecimal(amount, places: 2),
                multiplier: formatX(mult, places: 2, placesUnder1000: 2),
                cost: formatDecimal(cost),
                purchases: clampedInt(d.forProperty("purchases")?.toDouble() ?? 0),
                rateOfChange: roc,
                isAvailableForPurchase: d.forProperty("isAvailableForPurchase")?.toBool() ?? false,
                isAffordable: currentIP.gte(cost),
                isCapped: d.forProperty("isCapped")?.toBool() ?? false,
                amRequirement: amReqStr,
                amRequirementReached: d.forProperty("antimatterRequirementReached")?.toBool() ?? false,
                hasPrevTier: prevUnlocked,
                isAutobuyerUnlocked: idABUnlocked,
                isAutobuyerActive: idABActive
            ))
        }

        let infPower = GameDecimal(from: context.evaluateScript("Currency.infinityPower.value"))
        // powerConversionRate is a fractional plain JS number (base 7 + infinityrate glyph
        // effect + Pelle upgrade). Read as Double, NOT toInt32 — truncating 7.04 -> 7 both
        // corrupts the displayed rate and computes the wrong multiplier. Web:
        // ModernInfinityDimensionsTab.vue formats `formatPow(conversionRate, 2, 3)` and
        // computes `infinityPower.pow(conversionRate)`.
        let convRateText = context.evaluateScript("format(InfinityDimensions.powerConversionRate, 2, 3)")?.toString() ?? "7"
        // mult = infinityPower ^ powerConversionRate, clamped to min 1. Use the fractional
        // rate directly in JS to keep precision.
        let powerMult = GameDecimal(from: context.evaluateScript("Currency.infinityPower.value.pow(InfinityDimensions.powerConversionRate).max(1)"))
        let prodPerSec = GameDecimal(from: jsInfDimRefs[0].forProperty("productionPerSecond"))
        let totalDimCap = context.evaluateScript("InfinityDimensions.totalDimCap")?.toDouble() ?? 2000000

        let anyIDABUnlocked = idDims.contains { $0.isAutobuyerUnlocked }
        let ec8Running = context.evaluateScript("EternityChallenge(8).isRunning")?.toBool() ?? false

        state.infinityDimensions = InfinityDimsInfo(
            isUnlocked: idUnlocked,
            eternityReached: eternityReached,
            infinityPower: formatDecimal(infPower, places: 2, placesUnder1000: 1),
            powerMultiplier: formatX(powerMult, places: 2, placesUnder1000: 2),
            conversionRate: convRateText,
            powerPerSecond: formatDecimal(prodPerSec, places: 2),
            totalDimCap: formatPlainNumber(totalDimCap),
            isAnyAutobuyerUnlocked: anyIDABUnlocked,
            isEC8Running: ec8Running,
            dimensions: idDims
        )

        // Tesseract state (tab-gated: only when viewing ID tab, gated on Enslaved completion)
        if enslavedCompleted {
            if let json = context.evaluateScript("_nativeTesseractState()")?.toString(),
               json != "null",
               let data = json.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                state.infinityDimensions.tesseracts = TesseractInfo(
                    bought: (obj["bought"] as? Int) ?? 0,
                    extra: (obj["extra"] as? Int) ?? 0,
                    nextCost: (obj["nextCost"] as? String) ?? "",
                    canBuy: (obj["canBuy"] as? Bool) ?? false,
                    nextCapIncrease: (obj["nextCapIncrease"] as? String) ?? "",
                    totalCap: (obj["totalCap"] as? String) ?? ""
                )
            }
        }
    }

    // MARK: - Time Dimensions polling

    private func pollTimeDimensions(_ state: inout GameState) {
        let currentEP = GameDecimal(from: jsCurrencyEP.forProperty("value"))

        var tdDims: [TimeDimensionInfo] = []
        tdDims.reserveCapacity(8)
        for i in 0..<8 {
            let d = jsTimeDimRefs[i]
            let amount = GameDecimal(from: d.forProperty("amount"))
            let mult = GameDecimal(from: d.forProperty("multiplier"))
            let cost = GameDecimal(from: d.forProperty("cost"))
            let isUnlocked = d.forProperty("isUnlocked")?.toBool() ?? false

            var roc: String? = nil
            if isUnlocked && i < 7 {
                let rocVal = GameDecimal(from: d.forProperty("rateOfChange"))
                roc = formatDecimal(rocVal, places: 2, placesUnder1000: 2)
            }

            // For TD5-8: requirement is the corresponding Time Study
            let reqReached: Bool
            var ttCost: String? = nil
            if i < 4 {
                reqReached = true
            } else {
                reqReached = isUnlocked || (d.forProperty("requirementReached")?.toBool() ?? false)
                // TD5-8 when not unlocked: show the TT cost to unlock
                if !isUnlocked {
                    let tier = i + 1
                    let costVal = context.evaluateScript("TimeStudy.timeDimension(\(tier)).cost")?.toDouble() ?? 0
                    ttCost = "Unlock: \(formatInt(clampedInt(costVal))) TT"
                }
            }

            let autoActive = jsTDAutobuyerRefs[i].forProperty("isActive")?.toBool() ?? false

            tdDims.append(TimeDimensionInfo(
                tier: i + 1,
                isUnlocked: isUnlocked,
                amount: formatDecimal(amount, places: 2),
                multiplier: formatX(mult, places: 2, placesUnder1000: 2),
                bought: clampedInt(d.forProperty("bought")?.toDouble() ?? 0),
                cost: formatDecimal(cost),
                rateOfChange: roc,
                isAffordable: currentEP.gte(cost),
                requirementReached: reqReached,
                ttCost: ttCost,
                isAutoActive: autoActive
            ))
        }

        // Time Shards & tickspeed from shards
        let timeShards = GameDecimal(from: context.evaluateScript("Currency.timeShards.value"))
        let shardsPerSec = GameDecimal(from: jsTimeDimRefs[0].forProperty("productionPerSecond"))
        let totalUpgrades = clampedInt(context.evaluateScript("player.totalTickGained")?.toDouble() ?? 0)
        let multPerTickStr = context.evaluateScript("formatX(FreeTickspeed.multToNext, 2, 2)")?.toString() ?? "×0"
        let nextThreshold = GameDecimal(from: context.evaluateScript(
            "FreeTickspeed.fromShards(Currency.timeShards.value).nextShards"
        ))

        let tdAutobuyersUnlocked = jsTDAutobuyerRefs[0].forProperty("isUnlocked")?.toBool() ?? false

        state.timeDimensions = TimeDimensionsState(
            timeShards: formatDecimal(timeShards, places: 2, placesUnder1000: 2),
            shardsPerSecond: formatDecimal(shardsPerSec, places: 2, placesUnder1000: 2),
            totalTickspeedUpgrades: totalUpgrades,
            multPerTickspeed: multPerTickStr,
            upgradeThreshold: formatDecimal(nextThreshold, places: 2),
            dimensions: tdDims,
            areAutobuyersUnlocked: tdAutobuyersUnlocked
        )
    }

    // MARK: - Eternity Upgrades polling

    /// Static upgrade definitions — matches eternity-upgrades.js order
    private static let eternityUpgradeKeys = [
        ("idMultEP",         "Infinity Dimension multiplier based on unspent Eternity Points"),
        ("idMultEternities", "Infinity Dimension multiplier based on Eternities"),
        ("idMultICRecords",  "Infinity Dimension multiplier based on sum of Infinity Challenge times"),
        ("tdMultAchs",       "Your Achievement bonus affects Time Dimensions"),
        ("tdMultTheorems",   "Time Dimensions are multiplied by your unspent Time Theorems"),
        ("tdMultRealTime",   "Time Dimensions are multiplied by days played"),
    ]

    private func pollEternityUpgrades(_ state: inout GameState) {
        var upgrades: [EternityUpgradeInfo] = []
        upgrades.reserveCapacity(Self.eternityUpgradeKeys.count)
        for (key, _) in Self.eternityUpgradeKeys {
            guard let u = context.evaluateScript("EternityUpgrade.\(key)"), !u.isUndefined else { continue }
            let isBought = u.forProperty("isBought")?.toBool() ?? false
            let isAffordable = u.forProperty("isAffordable")?.toBool() ?? false
            // Cost may be a plain JS number or a Decimal — use JS format() for reliability
            let cost = context.evaluateScript("format(EternityUpgrade.\(key).config.cost)")?.toString() ?? "0"
            // `effectValue` getter can throw at certain game stages (e.g.
            // post-Armageddon for upgrades whose effect reads currently-reset
            // state). Wrap in try/catch to avoid per-tick `🔴 JS:` spam.
            //
            // Also mirror web `EffectDisplay.vue`'s cap handling: when the
            // upgrade has a `config.cap` and its effect has reached it, clamp
            // the displayed value to the cap and flag `capped` so the card
            // shows "Capped: …" instead of "Currently: …". Only EU3
            // (`idMultICRecords`) has a cap today.
            let effJSON = context.evaluateScript("""
                (function() {
                    try {
                        var u = EternityUpgrade.\(key);
                        var cfg = u.config;
                        var val = u.effectValue;
                        var cap = (typeof cfg.cap === "function") ? cfg.cap() : cfg.cap;
                        var reached = false;
                        if (cfg.reachedCap !== undefined) {
                            reached = !!cfg.reachedCap();
                        } else if (cap !== undefined) {
                            reached = (typeof val === "number") ? (val >= cap) : val.gte(cap);
                        }
                        var shown = reached ? cap : val;
                        var fmt = cfg.formatEffect ? cfg.formatEffect(shown) : formatX(shown, 2, 1);
                        return JSON.stringify({ eff: fmt || "x1.00", capped: reached });
                    } catch (e) { return JSON.stringify({ eff: "x1.00", capped: false }); }
                })()
                """)?.toString() ?? ""
            var effect = "x1.00"
            var isCapped = false
            if let d = effJSON.data(using: .utf8),
               let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                effect = (o["eff"] as? String) ?? "x1.00"
                isCapped = (o["capped"] as? Bool) ?? false
            }
            // Description may be a string or a function — evaluate via JS
            // inside a try/catch (functions can throw at edge-case states).
            let descRaw = context.evaluateScript("""
                (function() {
                    try {
                        var d = EternityUpgrade.\(key).config.description;
                        return typeof d === "function" ? (d() || "") : (d === undefined || d === null ? "" : String(d));
                    } catch (e) { return ""; }
                })()
                """)?.toString() ?? key
            let desc = normalizeWhitespace(descRaw)
            upgrades.append(EternityUpgradeInfo(
                id: key, description: desc,
                cost: cost,
                effectText: effect,
                isBought: isBought, isAffordable: isAffordable,
                isCapped: isCapped
            ))
        }

        // EP Multiplier (rebuyable) — cost is always a Decimal
        let epMultCost = context.evaluateScript("format(EternityUpgrade.epMult.cost, 2, 0)")?.toString() ?? "0"
        let epMultEffect = context.evaluateScript("formatX(EternityUpgrade.epMult.effectValue, 2, 0)")?.toString() ?? "x1.00"
        let epMultAffordable = context.evaluateScript("EternityUpgrade.epMult.isAffordable")?.toBool() ?? false
        let epMultCapped = context.evaluateScript("EternityUpgrade.epMult.isCapped")?.toBool() ?? false
        let epMultAutoUnlocked = context.evaluateScript("Autobuyer.epMult.isUnlocked")?.toBool() ?? false
        let epMultAutoActive = context.evaluateScript("Autobuyer.epMult.isActive")?.toBool() ?? false

        state.eternity.upgrades = upgrades
        state.eternity.epMult = EPMultState(
            currentMult: epMultEffect,
            cost: epMultCost,
            isAffordable: epMultAffordable,
            isCapped: epMultCapped,
            isAutoUnlocked: epMultAutoUnlocked,
            isAutoActive: epMultAutoActive
        )
    }

    // MARK: - Eternity Milestones polling

    /// Static milestone definitions — matches eternity-milestones.js, sorted by eternities
    /// Eternity milestone definitions. `reward` is nil for milestones with dynamic JS text (6, 200, 1000).
    private static let milestoneDefinitions: [(key: String, eternities: Int, reward: String?)] = [
        ("autobuyerIPMult", 1, "Unlock the Infinity Point multiplier autobuyer"),
        ("keepAutobuyers", 2, "You start Eternity with all Normal Challenges complete, all normal autobuyers, and Infinity broken"),
        ("autobuyerReplicantiGalaxy", 3, "Unlock the Replicanti Galaxy Autobuyer"),
        ("keepInfinityUpgrades", 4, "You start Eternity with all Infinity Upgrades"),
        ("bigCrunchModes", 5, "Unlock more Big Crunch Autobuyer options"),
        ("autoEP", 6, nil),  // dynamic — reads from JS
        ("autoIC", 7, "You complete Infinity Challenges as soon as you unlock them, and keep the Dimensional Sacrifice Autobuyer"),
        ("keepBreakUpgrades", 8, "You start Eternity with all Break Infinity Upgrades"),
        ("autobuyMaxGalaxies", 9, "Unlock the buy max Antimatter Galaxies Autobuyer mode"),
        ("unlockReplicanti", 10, "You start with Replicanti unlocked"),
        ("autobuyerID1", 11, "Unlock the 1st Infinity Dimension Autobuyer"),
        ("autobuyerID2", 12, "Unlock the 2nd Infinity Dimension Autobuyer"),
        ("autobuyerID3", 13, "Unlock the 3rd Infinity Dimension Autobuyer"),
        ("autobuyerID4", 14, "Unlock the 4th Infinity Dimension Autobuyer"),
        ("autobuyerID5", 15, "Unlock the 5th Infinity Dimension Autobuyer"),
        ("autobuyerID6", 16, "Unlock the 6th Infinity Dimension Autobuyer"),
        ("autobuyerID7", 17, "Unlock the 7th Infinity Dimension Autobuyer"),
        ("autobuyerID8", 18, "Unlock the 8th Infinity Dimension Autobuyer"),
        ("autoUnlockID", 25, "You automatically unlock Infinity Dimensions upon reaching them"),
        ("unlockAllND", 30, "Start with all Antimatter Dimensions available for purchase"),
        ("replicantiNoReset", 40, "Replicanti Galaxies no longer reset Antimatter, Antimatter Dimensions, Tickspeed, Dimensional Sacrifice, or Dimension Boosts"),
        ("autobuyerReplicantiChance", 50, "Unlock the Replicanti Chance Upgrade Autobuyer"),
        ("autobuyerReplicantiInterval", 60, "Unlock the Replicanti Interval Upgrade Autobuyer"),
        ("autobuyerReplicantiMaxGalaxies", 80, "Unlock the Max Replicanti Galaxy Upgrade Autobuyer"),
        ("autobuyerEternity", 100, "Unlock autobuyer for Eternities"),
        ("autoEternities", 200, nil),  // dynamic — reads from JS
        ("autoInfinities", 1000, nil),  // dynamic — reads from JS
    ]

    private func pollEternityMilestones(_ state: inout GameState) {
        var milestones: [EternityMilestoneInfo] = []
        milestones.reserveCapacity(Self.milestoneDefinitions.count)
        for def in Self.milestoneDefinitions {
            let isReached = context.evaluateScript("EternityMilestone.\(def.key).isReached")?.toBool() ?? false
            // Static config flag — `pelleUseless: true` on milestones that
            // are nullified by Pelle. Drives strikethrough Swift-side.
            // Mirrors `EternityMilestoneButton.vue:43`'s `isUseless` getter.
            let pelleUseless = context.evaluateScript("EternityMilestone.\(def.key).config.pelleUseless")?.toBool() ?? false
            let reward: String
            if let staticReward = def.reward {
                reward = staticReward
            } else {
                // Dynamic reward text — evaluate the JS function inside a
                // try/catch IIFE. The dynamic milestones (autoEP, autoEternities,
                // autoInfinities) call out to `getOfflineEPGain` /
                // `getEternitiedMilestoneReward` / `getInfinitiedMilestoneReward`
                // which read game state that can be undefined post-Armageddon.
                // Without the catch, the per-tick exception fires the global
                // JS handler (`🔴 JS: TypeError: undefined is not an object`).
                let raw = context.evaluateScript("""
                    (function() {
                        try {
                            var c = EternityMilestone.\(def.key).config;
                            if (!c) return "";
                            var r = c.reward;
                            if (typeof r === "function") return r() || "";
                            return r === undefined || r === null ? "" : String(r);
                        } catch (e) { return ""; }
                    })()
                    """)?.toString() ?? ""
                reward = raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            }
            // `config.activeCondition()` — the web tooltip text. Only the three
            // offline milestones define it; for the rest the IIFE returns "".
            // Same try/catch guarding as `reward` (the function reads game state
            // that can be undefined post-Armageddon).
            let conditionRaw = context.evaluateScript("""
                (function() {
                    try {
                        var c = EternityMilestone.\(def.key).config;
                        if (!c || typeof c.activeCondition !== "function") return "";
                        return c.activeCondition() || "";
                    } catch (e) { return ""; }
                })()
                """)?.toString() ?? ""
            let activeCondition = conditionRaw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            milestones.append(EternityMilestoneInfo(
                id: def.key,
                eternities: def.eternities,
                reward: reward,
                isReached: isReached,
                pelleUseless: pelleUseless,
                activeCondition: activeCondition
            ))
        }
        state.eternity.milestones = milestones

        // Eternity count
        let eternities = GameDecimal(from: context.evaluateScript("Currency.eternities.value"))
        state.eternity.eternityCount = formatDecimal(eternities, places: 2, placesUnder1000: 0)
    }

    // MARK: - Time Studies polling

    /// All normal study IDs in tree order
    private static let normalStudyIDs: [Int] = [
        11, 21, 22, 31, 32, 33, 41, 42, 51, 61, 62,
        71, 72, 73, 81, 82, 83, 91, 92, 93, 101, 102, 103,
        111, 121, 122, 123, 131, 132, 133, 141, 142, 143, 151,
        161, 162, 171, 181,
        191, 192, 193, 201, 211, 212, 213, 214,
        221, 222, 223, 224, 225, 226, 227, 228,
        231, 232, 233, 234,
        // Triad Studies — Ra V pet lv 6 (`Ra.unlocks.unlockHardV`). Cost 12 ST each,
        // gated individually by Hard V-Achievement tier completions.
        301, 302, 303, 304
    ]

    /// Path color assignments (from normal-time-study.js)
    static let studyPathMap: [Int: TimeStudyInfo.StudyType] = {
        var m: [Int: TimeStudyInfo.StudyType] = [:]
        for id in [71, 81, 91, 101] { m[id] = .antimatter }
        for id in [72, 82, 92, 102] { m[id] = .infinity }
        for id in [73, 83, 93, 103] { m[id] = .time }
        for id in [121, 131, 141] { m[id] = .active }
        for id in [122, 132, 142] { m[id] = .passive }
        for id in [123, 133, 143] { m[id] = .idle }
        for id in [221, 223, 225, 227, 231, 233] { m[id] = .light }
        for id in [222, 224, 226, 228, 232, 234] { m[id] = .dark }
        for id in [301, 302, 303, 304] { m[id] = .triad }
        return m
    }()

    /// Poll Time Studies state via the cached bulk-JSON helper
    /// (`time-studies-helper.js`). Replaces what was a ~380-evaluateScript-
    /// per-tick loop (76 studies × ~5 JS bridge crossings + 76 Swift-side
    /// NSRegex normalisations) with one helper call. Descriptions are
    /// cached JS-side and rebuilt only on events that mutate them
    /// (achievement unlock, perk purchase, Ra triad unlock, reality reset);
    /// volatile fields (isBought / isAffordable / effectText / EC progress)
    /// are emitted live every call. See the JS file header for the full
    /// invalidation event list.
    ///
    /// Effect computation is wrapped in a JS-side try/catch inside the
    /// helper — some studies' `effect()` functions read game state that can
    /// be undefined at certain stages (notably post-Armageddon doom for
    /// studies in `Pelle.uselessTimeStudies` whose backing state has been
    /// reset). Per-study errors return empty effect text without polluting
    /// the global JS exception handler.
    private func pollTimeStudies(_ state: inout GameState) {
        // Bulk JSON helper — one evaluateScript per tick instead of ~380.
        // Helper lives in `time-studies-helper.js`, injected via
        // `setupTimeStudiesHelper()`. Caches descriptions (the expensive
        // function-call + whitespace-collapse path) and emits volatile
        // fields fresh each call. See the JS header for the full
        // invalidation event list.
        var studies: [TimeStudyInfo] = []
        if let json = context.evaluateScript("_nativeTimeStudiesState()")?.toString(),
           let data = json.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            studies.reserveCapacity(arr.count)
            for d in arr {
                let id = (d["id"] as? Int) ?? Int((d["id"] as? Double) ?? 0)
                let type: TimeStudyInfo.StudyType
                if id >= -12 && id < 0       { type = .ec }
                else if id == -100           { type = .dilation }
                else if id <= -105 && id >= -108 { type = .timeDimension }
                else if id == -200           { type = .reality }
                else                          { type = Self.studyPathMap[id] ?? .normal }
                studies.append(TimeStudyInfo(dict: d, type: type))
            }
        }

        // Time Theorem shop
        // Web formats the TT count via `formatTimeTheoremType` (TimeTheoremShop.vue):
        // below 1e6 it uses `formatInt` — so 12889 reads as "12,889", not the
        // scientific "1.29e4" that iOS's notation-agnostic `formatDecimal` emits.
        // (Useful for gauging distance to the 13,000-TT Dilation unlock.) A
        // fractional TT generator switches to `formatFloat`; ≥ 1e6 falls back to
        // the player's notation via `format`. Formatter is chosen from the current
        // amount and applied to both current + total, mirroring web `quantify`.
        let ttFmt = context.evaluateScript("""
            (function(){
                try {
                    var cur = Currency.timeTheorems.value;
                    var tot = Currency.timeTheorems.max;
                    var fmt = formatInt;
                    if (cur.gte(1e6)) fmt = format;
                    else if (!(Teresa.isRunning || Enslaved.isRunning) &&
                             getAdjustedGlyphEffect("dilationTTgen") > 0 &&
                             !DilationUpgrade.ttGenerator.isBought) fmt = formatFloat;
                    return JSON.stringify({ cur: fmt(cur, 2, 2), tot: fmt(tot, 2, 2) });
                } catch (e) { return ""; }
            })()
            """)?.toString() ?? ""
        var ttCurStr = "0"
        var ttTotStr = "0"
        if let d = ttFmt.data(using: .utf8),
           let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            ttCurStr = (o["cur"] as? String) ?? ttCurStr
            ttTotStr = (o["tot"] as? String) ?? ttTotStr
        } else {
            // Fallback: notation-agnostic scientific (previous behavior).
            ttCurStr = formatDecimal(GameDecimal(from: context.evaluateScript("Currency.timeTheorems.value")), places: 2, placesUnder1000: 0)
            ttTotStr = formatDecimal(GameDecimal(from: context.evaluateScript("Currency.timeTheorems.max")), places: 2, placesUnder1000: 0)
        }
        let amCost = GameDecimal(from: context.evaluateScript("TimeTheoremPurchaseType.am.cost"))
        let ipCost = GameDecimal(from: context.evaluateScript("TimeTheoremPurchaseType.ip.cost"))
        let epCost = GameDecimal(from: context.evaluateScript("TimeTheoremPurchaseType.ep.cost"))
        let canAM = context.evaluateScript("TimeTheoremPurchaseType.am.canAfford")?.toBool() ?? false
        let canIP = context.evaluateScript("TimeTheoremPurchaseType.ip.canAfford")?.toBool() ?? false
        let canEP = context.evaluateScript("TimeTheoremPurchaseType.ep.canAfford")?.toBool() ?? false
        // Space Theorems (V reward) — gated on V unlock; Pelle blocks them.
        // `availableST` is V.availableST (unspent); `spaceTheorems` is total earned.
        let availableST = Int(context.evaluateScript("(typeof V !== 'undefined' && !Pelle.isDoomed) ? V.availableST : 0")?.toDouble() ?? 0)
        let totalST = Int(context.evaluateScript("(typeof V !== 'undefined' && !Pelle.isDoomed) ? V.spaceTheorems : 0")?.toDouble() ?? 0)

        let shop = TimeTheoremShopState(
            theorems: ttCurStr,
            totalTheorems: ttTotStr,
            amCost: formatDecimal(amCost),
            ipCost: formatDecimal(ipCost),
            epCost: formatDecimal(epCost),
            canBuyAM: canAM, canBuyIP: canIP, canBuyEP: canEP,
            availableSpaceTheorems: availableST,
            totalSpaceTheorems: totalST
        )

        let respec = jsPlayer.forProperty("respec")?.toBool() ?? false

        // Preferred paths: player.timestudy.preferredPaths = [[dimPaths], pacePath]
        // The dimension entry is an ordered priority list of up to 2 paths. `usePriority` mirrors
        // TimeStudy.preferredPaths.dimension.usePriority (web): a 2nd preference becomes selectable
        // once Time Study 201 / the timeStudySplit dilation upgrade / Reality is reached.
        let prefPaths = jsPlayer.forProperty("timestudy")?.forProperty("preferredPaths")
        let dimPathArr = prefPaths?.atIndex(0)
        let dimCount = Int(dimPathArr?.forProperty("length")?.toInt32() ?? 0)
        var dimPaths: [Int] = []
        dimPaths.reserveCapacity(2)
        for i in 0..<min(dimCount, 2) {
            let v = Int(dimPathArr?.atIndex(i)?.toInt32() ?? 0)
            if (1...3).contains(v) { dimPaths.append(v) }
        }
        let pacePath = Int(prefPaths?.atIndex(1)?.toInt32() ?? 0)
        let usePriority = context.evaluateScript(
            "(function(){try{return !!TimeStudy.preferredPaths.dimension.usePriority;}catch(e){return false;}})()"
        )?.toBool() ?? false

        // Study presets (6 slots)
        var presets: [StudyPresetInfo] = []
        presets.reserveCapacity(6)
        let jsPresets = jsPlayer.forProperty("timestudy")?.forProperty("presets")
        for i in 0..<6 {
            let p = jsPresets?.atIndex(i)
            let name = p?.forProperty("name")?.toString() ?? ""
            let studies = p?.forProperty("studies")?.toString() ?? ""
            presets.append(StudyPresetInfo(id: i, name: name, studies: studies))
        }

        state.eternity.timeStudies = TimeStudiesState(
            studies: studies, shop: shop, respecOnNextEternity: respec,
            preferredDimPaths: dimPaths, preferredPacePath: pacePath, usePriority: usePriority,
            presets: presets
        )
    }

    // MARK: - Time Dilation polling

    /// Dilation upgrade definitions. Ids 11–15 are `pelleOnly` per
    /// `dilation-upgrades.js` — they're filtered out unless the player is
    /// Doomed AND the `PelleRifts.paradox.milestones[0]` paradox milestone is
    /// active (matches web `TimeDilationTab.vue.hasPelleDilationUpgrades`).
    private static let dilationUpgradeDefs: [(id: Int, rebuyable: Bool, pelleOnly: Bool)] = [
        (1, true, false), (2, true, false), (3, true, false),
        (4, false, false), (5, false, false), (6, false, false), (7, false, false),
        (8, false, false), (9, false, false), (10, false, false),
        // pelleOnly rebuyables
        (11, true, true), (12, true, true), (13, true, true),
        // pelleOnly single-purchase
        (14, false, true), (15, false, true),
    ]

    private func pollDilation(_ state: inout GameState) {
        let isActive = jsPlayer.forProperty("dilation")?.forProperty("active")?.toBool() ?? false

        // `getDilationGainPerSecond()` and `getDilationTimeEstimate(...)`
        // can throw at certain game stages (post-Armageddon when state is
        // mid-reset). Wrap to keep per-tick polls clean.
        let dt = GameDecimal(from: context.evaluateScript("Currency.dilatedTime.value"))
        let dtPerSec = GameDecimal(from: context.evaluateScript("(function(){ try { return getDilationGainPerSecond(); } catch(e) { return new Decimal(0); } })()"))
        let tp = GameDecimal(from: context.evaluateScript("Currency.tachyonParticles.value"))
        let galaxies = clampedInt(jsPlayer.forProperty("dilation")?.forProperty("totalTachyonGalaxies")?.toDouble() ?? 0)
        let nextThreshold = GameDecimal(from: jsPlayer.forProperty("dilation")?.forProperty("nextThreshold"))
        // `getDilationTimeEstimate` returns JS `null` when DT gain is 0
        // (e.g. post-Reality with no dilation study bought). `JSValue.toString()`
        // converts JS null to the literal "null", which the Swift-side
        // `!isEmpty` gate then renders as `Estimated: null`. Coerce to ""
        // here so the row hides cleanly. Web never surfaces this value as
        // text — it's only used as a tooltip prop in `TimeDilationTab.vue`.
        let timeEst = context.evaluateScript("(function(){ try { var v = getDilationTimeEstimate(player.dilation.nextThreshold); return v == null ? '' : v; } catch(e) { return ''; } })()")?.toString() ?? ""

        // Pelle paradox milestone gates the 5 `pelleOnly` dilation upgrades
        // (web `TimeDilationTab.vue.hasPelleDilationUpgrades`).
        let hasPelleDilationUpgrades = context.evaluateScript(
            "(typeof PelleRifts !== 'undefined' && PelleRifts.paradox.milestones[0] && PelleRifts.paradox.milestones[0].canBeApplied)"
        )?.toBool() ?? false

        var upgrades: [DilationUpgradeInfo] = []
        upgrades.reserveCapacity(Self.dilationUpgradeDefs.count)
        for def in Self.dilationUpgradeDefs {
            // Skip pelleOnly upgrades unless the paradox milestone is unlocked,
            // matching web's `allRebuyables` / `allSingleUpgrades` filtering.
            if def.pelleOnly && !hasPelleDilationUpgrades { continue }
            guard let u = context.evaluateScript("DilationUpgrades.fromId(\(def.id))"), !u.isUndefined else { continue }
            let isBought = u.forProperty("isBought")?.toBool() ?? false
            let isAffordable = u.forProperty("isAffordable")?.toBool() ?? false
            let isCapped = def.rebuyable ? (u.forProperty("isCapped")?.toBool() ?? false) : false
            let costStr = context.evaluateScript("(function(){ try { return format(DilationUpgrades.fromId(\(def.id)).cost, 2); } catch(e) { return '0'; } })()")?.toString() ?? "0"
            let boughtAmount = def.rebuyable ? clampedInt(u.forProperty("boughtAmount")?.toDouble() ?? 0) : 0
            let desc = context.evaluateScript("""
                (function() {
                    try {
                        var u = DilationUpgrades.fromId(\(def.id));
                        var d = u.config.description;
                        return typeof d === 'function' ? (d() || '') : (d || '');
                    } catch (e) { return ''; }
                })()
                """)?.toString() ?? ""
            let rawEffect = context.evaluateScript("""
                (function() {
                    try {
                        var u = DilationUpgrades.fromId(\(def.id));
                        return u.config.formatEffect ? u.config.formatEffect(u.effectValue) : '';
                    } catch (e) { return ''; }
                })()
                """)?.toString() ?? ""
            // JS template literals embed newlines + indentation (e.g. "×2.84 ➜\n        Next: ×2.27")
            let effect = rawEffect.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            var autoUnlocked = false
            var autoActive = false
            if def.rebuyable {
                // Single safe eval rather than `evaluateScript` + chained
                // `forProperty` reads. The chained form was the crash site
                // for an EXC_BAD_ACCESS in the doom audit — JSValue lifetime
                // across two property reads was unstable under some throwing
                // states. A single eval returning a packed string keeps
                // everything on the JS side.
                let raw = context.evaluateScript("""
                    (function() {
                        try {
                            var ab = Autobuyer.dilationUpgrade(\(def.id));
                            if (!ab) return '00';
                            return (ab.isUnlocked ? '1' : '0') + (ab.isActive ? '1' : '0');
                        } catch (e) { return '00'; }
                    })()
                    """)?.toString() ?? "00"
                autoUnlocked = raw.first == "1"
                autoActive = raw.count > 1 && raw[raw.index(after: raw.startIndex)] == "1"
            }

            upgrades.append(DilationUpgradeInfo(
                id: def.id,
                description: desc,
                cost: costStr,
                effectText: effect,
                isBought: def.rebuyable ? false : isBought,
                isAffordable: isAffordable,
                isRebuyable: def.rebuyable,
                boughtAmount: boughtAmount,
                isCapped: isCapped,
                isAutoUnlocked: autoUnlocked,
                isAutoActive: autoActive,
                pelleOnly: def.pelleOnly
            ))
        }

        // Button state fields — only meaningful when dilated
        var tachyonGain = "0"
        var hasGain = false
        var canEternityDilated = false
        var requiredForGain = ""
        var eternityGoal = ""
        if isActive {
            // `getTachyonGain` / `getTachyonReq` / `Player.canEternity` /
            // `Player.eternityGoal` can each throw post-Armageddon while
            // state is mid-reset. Wrap each in a try/catch so the per-tick
            // poll stays quiet.
            hasGain = context.evaluateScript("(function(){ try { return getTachyonGain(false).gt(0); } catch(e) { return false; } })()")?.toBool() ?? false
            canEternityDilated = context.evaluateScript("(function(){ try { return Player.canEternity; } catch(e) { return false; } })()")?.toBool() ?? false
            if canEternityDilated && hasGain {
                tachyonGain = context.evaluateScript("(function(){ try { return format(getTachyonGain(false), 2, 1); } catch(e) { return '0'; } })()")?.toString() ?? "0"
            } else if hasGain {
                eternityGoal = context.evaluateScript("(function(){ try { return format(Player.eternityGoal, 1, 0); } catch(e) { return '0'; } })()")?.toString() ?? "0"
            } else {
                requiredForGain = context.evaluateScript("(function(){ try { return format(getTachyonReq(), 2, 1); } catch(e) { return '0'; } })()")?.toString() ?? "0"
            }
        }

        // Pelle gate fields — only fetch in doom (cheap evals, but no point
        // doing them otherwise). Mirrors `DilationButton.vue.update()`.
        // Read `Pelle.isDoomed` from JS directly to avoid a cross-thread read
        // of `self.pelleDoomed` (updated on main, polled on jsQueue).
        var pelleCanDilate = false
        var pelleRemnantReq = ""
        let isDoomed = context.evaluateScript("typeof Pelle !== 'undefined' && Pelle.isDoomed")?.toBool() ?? false
        if isDoomed {
            pelleCanDilate = context.evaluateScript("Pelle.canDilateInPelle")?.toBool() ?? false
            pelleRemnantReq = context.evaluateScript("format(Pelle.remnantRequirementForDilation, 2)")?.toString() ?? ""
        }

        state.eternity.dilation = DilationState(
            isUnlocked: true,
            isActive: isActive,
            dilatedTime: formatDecimal(dt, places: 2, placesUnder1000: 2),
            dilatedTimePerSec: formatDecimal(dtPerSec, places: 2, placesUnder1000: 2),
            tachyonParticles: formatDecimal(tp, places: 2, placesUnder1000: 2),
            tachyonGalaxies: galaxies,
            nextGalaxyThreshold: formatDecimal(nextThreshold, places: 2),
            galaxyTimeEstimate: timeEst,
            upgrades: upgrades,
            tachyonGain: tachyonGain,
            hasGain: hasGain,
            canEternity: canEternityDilated,
            requiredForGain: requiredForGain,
            eternityGoal: eternityGoal,
            pelleCanDilate: pelleCanDilate,
            pelleRemnantRequirement: pelleRemnantReq,
            hasPelleDilationUpgrades: hasPelleDilationUpgrades
        )
    }

    // MARK: - Perks polling

    private func pollPerks(_ state: inout GameState) {
        // Cached + event-invalidated rebuild in `perks-helper.js`. Returns the
        // same `{perks: [...], pp: N}` shape as the previous inline IIFE.
        // Falls through to "{}" if the helper hasn't loaded yet — the existing
        // guard below skips the state update in that case (stale UI for one
        // tick, never crashes).
        let json = context.evaluateScript("_nativePerksState()")?.toString() ?? "{}"

        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["perks"] as? [[String: Any]] else {
            return
        }

        // `pp` is `player.reality.perkPoints` (plain number). Apple's
        // JSONSerialization can hand it back as either Int or Double depending
        // on whether the JS engine emitted "5" vs "5.0" — the original
        // `as? Int ??  0` silently zeroed Double-backed values, which is
        // probably why "perk points significant but reading 0" was reported.
        let pp: Int = {
            if let v = obj["pp"] as? Int { return v }
            if let v = obj["pp"] as? Double { return Int(v) }
            if let v = obj["pp"] as? NSNumber { return v.intValue }
            return 0
        }()
        // 48 perks polled per tick on the Perks tab — pre-reserve to skip
        // `compactMap`'s grow-on-demand reallocs.
        var perks: [PerkInfo] = []
        perks.reserveCapacity(arr.count)
        for p in arr {
            guard let id = p["id"] as? Int else { continue }
            perks.append(PerkInfo(
                id: id,
                label: p["label"] as? String ?? "",
                description: p["desc"] as? String ?? "",
                family: p["family"] as? String ?? "",
                isBought: p["bought"] as? Bool ?? false,
                canBeBought: p["canBuy"] as? Bool ?? false,
                automatorPoints: p["ap"] as? Int ?? 0,
                x: CGFloat(p["x"] as? Double ?? 0),
                y: CGFloat(p["y"] as? Double ?? 0),
                connectedTo: (p["conn"] as? [Int]) ?? []
            ))
        }
        state.perksState = PerksState(perks: perks, perkPoints: pp)
    }

    // MARK: - Glyphs polling

    private func pollGlyphs(_ state: inout GameState) {
        let json = context.evaluateScript("""
            (function() {
                var slotCount = Glyphs.activeSlotCount;
                // Per-glyph rich-card gates, hoisted so makeGlyphObj closes over them.
                // CRITICAL: these var ASSIGNMENTS must happen BEFORE the equipped/inventory
                // loops below — only the declarations hoist in JS, not the values. A previous
                // bug placed `sacUnlocked = …` after those loops and `sacGain` came back empty
                // for every equipped/inventory glyph (peek worked because it ran later).
                var sacUnlocked = false;
                try { sacUnlocked = !!GlyphSacrificeHandler.canSacrifice; } catch(ex) {}
                var pelleChaosUnlocked = false;
                try { pelleChaosUnlocked = !!(typeof Pelle !== 'undefined' && Pelle.specialGlyphEffect && Pelle.specialGlyphEffect.isUnlocked); } catch(ex) {}
                var scoreModeShows = false;
                try {
                    var _sm = AutoGlyphProcessor.scoreMode;
                    scoreModeShows = (_sm === AUTO_GLYPH_SCORE.SPECIFIED_EFFECT || _sm === AUTO_GLYPH_SCORE.EFFECT_SCORE);
                } catch(ex) {}
                var refineEfficiency = 1;
                try { refineEfficiency = GlyphSacrificeHandler.glyphRefinementEfficiency || 1; } catch(ex) {}
                var equipped = [];
                for (var s = 0; s < slotCount; s++) {
                    var g = Glyphs.active[s];
                    if (!g) { equipped.push(null); continue; }
                    equipped.push(makeGlyphObj(g, s, 'active'));
                }

                var inv = [];
                var invArr = Glyphs.inventory;
                for (var i = 0; i < invArr.length; i++) {
                    if (!invArr[i]) continue;
                    inv.push(makeGlyphObj(invArr[i], invArr[i].idx, 'inv'));
                }

                var effects = [];
                try {
                    // Web `CurrentGlyphEffects.vue:5-15` — canonical sort order
                    // groups effects by glyph type so same-type rows render
                    // consecutively. Effects not in the list (legacy / cosmetic)
                    // fall to the end via the `-1 → 999` reorder below.
                    var glyphEffectsOrder = [
                        'powerpow','powermult','powerdimboost','powerbuy10',
                        'infinitypow','infinityinfmult','infinityIP','infinityrate',
                        'replicationpow','replicationdtgain','replicationspeed','replicationglyphlevel',
                        'timepow','timeshardpow','timeEP','timespeed','timeetermult',
                        'dilationpow','dilationTTgen','dilationDT','dilationgalaxyThreshold',
                        'effarigrm','effarigglyph','effarigblackhole','effarigachievement',
                        'effarigforgotten','effarigdimensions','effarigantimatter',
                        'cursedgalaxies','cursedtickspeed','curseddimensions','cursedEP',
                        'realityglyphlevel','realitygalaxies','realityrow1pow','realityDTglyph',
                        'companiondescription','companionEP'
                    ];
                    var active = getActiveGlyphEffects().slice();
                    active.sort(function(a, b) {
                        var ai = glyphEffectsOrder.indexOf(a.id);
                        var bi = glyphEffectsOrder.indexOf(b.id);
                        return (ai === -1 ? 999 : ai) - (bi === -1 ? 999 : bi);
                    });
                    for (var e = 0; e < active.length; e++) {
                        var eff = active[e];
                        var cfg = GlyphEffects[eff.id];
                        if (!cfg) continue;
                        var baseVal = eff.value.value;
                        var val1 = cfg.formatEffect(baseVal);
                        var val2 = '';
                        if (cfg.conversion !== undefined) {
                            val2 = cfg.formatSecondaryEffect(cfg.conversion(baseVal));
                        }
                        var desc = cfg.totalDesc || '';
                        desc = desc.replace('{value}', '§' + val1 + '§').replace('{value2}', val2 ? '§' + val2 + '§' : '');
                        var tc = '#b241e3';
                        var gt = cfg.glyphTypes;
                        if (gt) { var gtd = GameDatabase.reality.glyphTypes[gt] || GameDatabase.reality.cosmeticGlyphs[gt]; if (gtd && gtd.color) tc = gtd.color; }
                        // Cursed glyphs have type color `#000000` which is illegible on
                        // the dark panel; web `CurrentGlyphEffect.vue:37` overrides to
                        // `var(--color-celestials)`. iOS uses the celestials purple.
                        if (gt === 'cursed') tc = '#9071e0';
                        effects.push({ id: eff.id, desc: desc, color: tc, capped: !!(eff.value.capped) });
                    }
                } catch(ex) {}

                var sacTotals = [];
                if (sacUnlocked) {
                    var types = ['power','infinity','time','replication','dilation','effarig','reality'];
                    for (var ti = 0; ti < types.length; ti++) {
                        var tp = types[ti];
                        var amt = player.reality.glyphs.sac[tp] || 0;
                        // Web `TypeSacrifice.vue:92` gates `v-if="amount > 0"` so only
                        // sacrificed types render. Filter here so iOS state stays
                        // "rows worth showing"; the empty-state branch (SAC-10) then
                        // keys cleanly off `sacrificeTotals.isEmpty`.
                        if (!(amt > 0)) continue;
                        var sym = GLYPH_SYMBOLS[tp] || '?';
                        var col = (GameDatabase.reality.glyphTypes[tp] || GameDatabase.reality.cosmeticGlyphs[tp] || {}).color || '#888';
                        // Web `TypeSacrifice.description` = `sacConfig.description(effectValue)`.
                        // `config.description` is always a function taking the current
                        // computed effect amount; iOS previously read `.description`
                        // (which is undefined on the wrapper state) and got empty text.
                        var boost = '';
                        try {
                            var sacState = GlyphSacrifice[tp];
                            if (sacState && sacState.config && typeof sacState.config.description === 'function') {
                                boost = sacState.config.description(sacState.effectValue) || '';
                            }
                        } catch(ex2) {}
                        // Web `TypeSacrifice.formatAmount` uses `format(amount, 2, 2)`;
                        // matching here so iOS readouts match.
                        sacTotals.push({ type: tp, sym: sym, color: col, amount: format(amt, 2, 2), boost: boost });
                    }
                }

                // Web `CurrentGlyphEffects.vue` flags — drives the "You cannot have
                // more than one Effarig or Reality Glyph equipped" notice.
                var hasEffarig = false, hasReality = false;
                try {
                    hasEffarig = Glyphs.active.some(function(g){ return g && g.type === 'effarig'; });
                    hasReality = Glyphs.active.some(function(g){ return g && g.type === 'reality'; });
                } catch(ex) {}

                // Web option toggle — when off, halo + coloring on effect/sacrifice
                // text is suppressed. Defaults true on web.
                var glyphTextColors = true;
                try { glyphTextColors = !!(player.options && player.options.glyphTextColors); } catch(ex) {}

                // Simplified `GlyphSetName.mainGlyphName` priority: cursed > companion >
                // reality > most-common basic > effarig > first-listed. Full web logic
                // (perc-tier adjectives, basic-type case branching, Doom singleton
                // pelle, 3+-types-≤30% copper override) is a separate follow-up; see
                // `.scratch/glyph-set-name-parity.md`.
                var setNameColor = '#ffffff';
                try {
                    var actSet = Glyphs.active.filter(function(g){return g;});
                    if (actSet.length === 0) {
                        setNameColor = '#ffffff';
                    } else {
                        var counts = {};
                        for (var ai = 0; ai < actSet.length; ai++) {
                            counts[actSet[ai].type] = (counts[actSet[ai].type]||0) + 1;
                        }
                        var dom;
                        if (counts.cursed) dom = 'cursed';
                        else if (counts.companion) dom = 'companion';
                        else if (counts.reality) dom = 'reality';
                        else {
                            // Pick most-common type (ties: lexicographic).
                            var bestK = null, bestV = -1;
                            for (var k in counts) {
                                if (counts[k] > bestV) { bestK = k; bestV = counts[k]; }
                            }
                            dom = bestK;
                        }
                        if (dom === 'cursed') {
                            setNameColor = '#9071e0';
                        } else {
                            try {
                                var def = GameDatabase.reality.glyphTypes[dom] || GameDatabase.reality.cosmeticGlyphs[dom];
                                if (def && def.color) setNameColor = def.color;
                            } catch(ex) {}
                        }
                    }
                } catch(ex) {}

                // Altered Glyphs section + Teresa multiplier + Reality glyph note
                // (web `SacrificedGlyphs.vue`). All gated downstream by tab visibility.
                var alterationsUnlocked = false;
                var hideAlteration = false;
                var addThreshText = '', addThreshColor = '';
                var empowerThreshText = '', empowerThreshColor = '';
                var boostThreshText = '', boostThreshColor = '';
                var maxSacText = '';
                try {
                    alterationsUnlocked = !!(typeof Ra !== 'undefined' && Ra.unlocks && Ra.unlocks.alteredGlyphs && Ra.unlocks.alteredGlyphs.canBeApplied);
                    hideAlteration = !!(player.options && player.options.hideAlterationEffects);
                    if (typeof GlyphAlteration !== 'undefined') {
                        addThreshText = format(GlyphAlteration.additionThreshold);
                        empowerThreshText = format(GlyphAlteration.empowermentThreshold);
                        boostThreshText = format(GlyphAlteration.boostingThreshold);
                        if (typeof GlyphAlteration.baseAdditionColor === 'function') addThreshColor = GlyphAlteration.baseAdditionColor();
                        if (typeof GlyphAlteration.baseEmpowermentColor === 'function') empowerThreshColor = GlyphAlteration.baseEmpowermentColor();
                        if (typeof GlyphAlteration.baseBoostColor === 'function') boostThreshColor = GlyphAlteration.baseBoostColor();
                    }
                    if (typeof GlyphSacrificeHandler !== 'undefined' && GlyphSacrificeHandler.maxSacrificeForEffects) {
                        maxSacText = format(GlyphSacrificeHandler.maxSacrificeForEffects);
                    }
                } catch(ex) {}

                var teresaMult = 1;
                var teresaMultText = '';
                var lastMachinesText = '';
                try {
                    if (typeof Teresa !== 'undefined') teresaMult = Teresa.runRewardMultiplier || 1;
                    // Format JS-side via the game's own formatter — `formatX(v, 2, 2)`
                    // emits "5.15e46x" for huge multipliers, not the raw 47-digit
                    // string Swift's `%.2f` would produce.
                    try {
                        if (typeof formatX === 'function') teresaMultText = formatX(teresaMult, 2, 2);
                        else if (typeof format === 'function') teresaMultText = format(teresaMult, 2, 2) + 'x';
                    } catch(ex) {}
                    if (player.celestials && player.celestials.teresa) {
                        var lmRM = player.celestials.teresa.lastRepeatedMachines;
                        if (lmRM !== undefined) {
                            // Web branches on `< 1e10000` to switch RM↔iM. Use the same
                            // threshold; `quantify` handles plural-ification.
                            if (typeof DC !== 'undefined' && lmRM.lt && lmRM.lt(DC.E10000)) {
                                lastMachinesText = quantify('Reality Machine', lmRM, 2);
                            } else if (lmRM.lt && lmRM.lt(new Decimal('1e10000'))) {
                                lastMachinesText = quantify('Reality Machine', lmRM, 2);
                            } else if (lmRM.dividedBy) {
                                lastMachinesText = quantify('Imaginary Machine', lmRM.dividedBy(new Decimal('1e10000')), 2);
                            }
                        }
                    }
                } catch(ex) {}

                var realityGlyphSeen = false;
                try { realityGlyphSeen = !!(player.reality && player.reality.glyphs && player.reality.glyphs.createdRealityGlyph); } catch(ex) {}

                var setName = '';
                try {
                    var NAMES = {
                        companion: {adj:'Huggable', noun:'Companion'},
                        reality: {adj:'Real', noun:'Reality'},
                        effarig: {adj:'Meta', noun:'Effarig'},
                        cursed: {adj:'Cursed', noun:'Curse'},
                        power: {adj:['Powerful','Mastered','Potential'], noun:'Power'},
                        infinity: {adj:['Infinite','Boundless','Immense'], noun:'Infinity'},
                        replication: {adj:['Replicated','Simulated','Duplicated'], noun:'Replication'},
                        time: {adj:['Temporal','Chronal','Transient'], noun:'Time'},
                        dilation: {adj:['Dilated','Attenuated','Diluted'], noun:'Dilation'}
                    };
                    var activeGlyphs = Glyphs.active.filter(function(g){return g});
                    var isDoomed = (typeof Pelle !== 'undefined') && Pelle.isDoomed;
                    if (activeGlyphs.length === 0) { setName = 'Void'; }
                    else {
                        var typeCounts = {};
                        activeGlyphs.forEach(function(g){ typeCounts[g.type] = (typeCounts[g.type]||0)+1; });
                        var types = Object.keys(typeCounts).sort(function(a,b){ return typeCounts[b]-typeCounts[a]; });
                        // Web `GlyphSetName.singletonName` swaps the entire set name to
                        // "Doomed <noun>" when only one glyph type is active under doom.
                        if (isDoomed && types.length === 1 && NAMES[types[0]]) {
                            setName = 'Doomed ' + NAMES[types[0]].noun;
                        } else {
                            var parts = [];
                            for (var ti = 0; ti < types.length; ti++) {
                                var t = types[ti]; var n = NAMES[t];
                                if (!n) continue;
                                if (ti === types.length - 1) {
                                    parts.push(n.noun);
                                } else {
                                    var a = n.adj;
                                    parts.push(typeof a === 'string' ? a : a[0]);
                                }
                            }
                            setName = parts.join(' ');
                        }
                    }
                } catch(ex) { setName = ''; }

                // Peek glyphs (upcoming glyph choices). Web `GlyphPeek.vue:27`
                // gates on `!Pelle.isDoomed && PlayerProgress.realityUnlocked()` —
                // doomed players can't gain new glyphs so the upcoming-choices
                // preview is hidden entirely.
                var canPeek = !!TimeStudy.reality.isBought && !(typeof Pelle !== "undefined" && Pelle.isDoomed);
                var peekGlyphs = [];
                var peekLevel = 0;
                if (canPeek) {
                    try { peekLevel = gainedGlyphLevel().actualLevel; } catch(ex) {}
                    try {
                        var upcoming = GlyphSelection.upcomingGlyphs;
                        for (var pi = 0; pi < upcoming.length; pi++) {
                            peekGlyphs.push(makeGlyphObj(upcoming[pi], pi, 'peek'));
                        }
                    } catch(ex) {}
                }

                // Reality reminder suggestions (matching RealityReminder.vue)
                var suggestions = [];
                if (canPeek) {
                    try {
                        var purchTS = 0;
                        try {
                            var allTS = NormalTimeStudyState.studies;
                            if (allTS) for (var tsi = 0; tsi < allTS.length; tsi++) {
                                var ts = allTS[tsi];
                                if (ts && !ts.isBought && ts.canBeBought) purchTS++;
                            }
                        } catch(ex2) {}
                        if (purchTS > 0) suggestions.push('Purchase ' + purchTS + ' available Time Studies');

                        var ecComps = EternityChallenges.completions;
                        if (ecComps < 60) suggestions.push('Complete ECs (' + ecComps + '/60)');

                        if (!TimeStudy.dilation.isBought && TimeStudy.dilation.isAffordable)
                            suggestions.push('Unlock Time Dilation');

                        if (player.dilation.studies.length < 6) {
                            var dlUpgCount = 0;
                            try {
                                for (var dli = 1; dli <= 6; dli++) {
                                    var dlu = DilationUpgrade[dli];
                                    if (dlu && !dlu.isBought && dlu.isAffordable) dlUpgCount++;
                                }
                            } catch(ex2) {}
                            if (dlUpgCount > 0) suggestions.push('Buy ' + dlUpgCount + ' affordable Dilation Upgrades');
                        }
                    } catch(ex) {}
                }
                var reminderGood = canPeek && suggestions.length === 0;
                var reminderText = !canPeek
                    ? 'You still need to unlock Reality in the Time Study Tree.'
                    : (reminderGood ? 'Ready to Reality!' : suggestions.length + ' thing' + (suggestions.length !== 1 ? 's' : '') + ' to do before Reality');

                // Glyph level factors (matching GlyphLevelsAndWeights.vue)
                var levelFactors = [];
                var finalLevel = '';
                try {
                    var inputs = getGlyphLevelInputs();
                    var fmtCoeff = function(c) { return format(c, 2, 4); };
                    var fmtExp = function(e) { return format(e, 2, 3); };
                    var fmtVal = function(v) { return format(v, 2, 3); };
                    levelFactors.push({ name: 'EP', formula: fmtCoeff(inputs.ep.coeff) + ' \\u00d7 EP^' + fmtExp(inputs.ep.exp), value: fmtVal(inputs.ep.value), op: '\\u00d7' });
                    levelFactors.push({ name: 'Replicanti', formula: fmtCoeff(inputs.repl.coeff) + ' \\u00d7 Repl^' + fmtExp(inputs.repl.exp), value: fmtVal(inputs.repl.value), op: '\\u00d7' });
                    levelFactors.push({ name: 'Dilated Time', formula: fmtCoeff(inputs.dt.coeff) + ' \\u00d7 DT^' + fmtExp(inputs.dt.exp), value: fmtVal(inputs.dt.value), op: '\\u00d7' });
                    if (inputs.eter && RealityUpgrade(18).isBought) {
                        levelFactors.push({ name: 'Eternities', formula: fmtCoeff(inputs.eter.coeff) + ' \\u00d7 Eter^' + fmtExp(inputs.eter.exp), value: fmtVal(inputs.eter.value), op: '\\u00d7' });
                    }
                    if (inputs.perkShop !== 1) {
                        levelFactors.push({ name: 'Perk Shop', formula: '', value: formatPercents(inputs.perkShop - 1), op: '+' });
                    }
                    if (inputs.scalePenalty !== 1) {
                        levelFactors.push({ name: 'Instability', formula: '', value: format(1 / inputs.scalePenalty, 2, 3), op: '/' });
                    }
                    finalLevel = formatInt(inputs.actualLevel);
                } catch(ex) {}

                // Auto Glyph Arrangement + purge controls
                var autoSort = 0;
                var autoCollapse = false;
                var autoAutoCleanUnlocked = false;
                var autoAutoClean = false;
                var applyFilterToPurge = false;
                var hasGlyphFilter = false;
                var hasGlyphWeights = false;
                var isRefining = false;
                var hasNegativeEffectScore = false;
                try {
                    autoSort = player.reality.autoSort || 0;
                    autoCollapse = !!player.reality.autoCollapse;
                    autoAutoClean = !!player.reality.autoAutoClean;
                    applyFilterToPurge = !!player.reality.applyFilterToPurge;
                    if (typeof VUnlocks !== 'undefined' && VUnlocks.autoAutoClean) {
                        autoAutoCleanUnlocked = !!VUnlocks.autoAutoClean.canBeApplied;
                    }
                    if (typeof EffarigUnlock !== 'undefined' && EffarigUnlock.glyphFilter) {
                        hasGlyphFilter = !!EffarigUnlock.glyphFilter.isUnlocked;
                    }
                    if (typeof EffarigUnlock !== 'undefined' && EffarigUnlock.adjuster) {
                        hasGlyphWeights = !!EffarigUnlock.adjuster.isUnlocked;
                    }
                    if (typeof AutoGlyphProcessor !== 'undefined' && typeof AUTO_GLYPH_REJECT !== 'undefined') {
                        isRefining = AutoGlyphProcessor.sacMode === AUTO_GLYPH_REJECT.REFINE ||
                                     AutoGlyphProcessor.sacMode === AUTO_GLYPH_REJECT.REFINE_TO_CAP;
                        try { hasNegativeEffectScore = !!AutoGlyphProcessor.hasNegativeEffectScore(); } catch(e3) {}
                    }
                } catch(e) {}

                // Effarig run state — drives the small stage banner at the top
                // of the Glyphs tab (only shown while player.celestials.effarig.run).
                var effarigRunning = false;
                var effarigStageName = 'Infinity';
                var effarigCap = 100;
                try {
                    if (typeof Effarig !== 'undefined' && Effarig.isRunning) {
                        effarigRunning = true;
                        effarigCap = Effarig.glyphLevelCap | 0;
                        var stage = Effarig.currentStage;
                        effarigStageName = stage === 1 ? 'Infinity' : stage === 2 ? 'Eternity' : 'Reality';
                    }
                } catch(e) {}

                // Glyph instability warning — `GlyphsTab.vue.showInstability`.
                // Becomes visible once the best Reality glyph level exceeds 800;
                // thresholds default to 1000 / 4000 but Effarig + ImaginaryUpgrade(7)
                // can push them higher.
                var showInstab = false;
                var instabThr = 1000;
                var hyperInstabThr = 4000;
                try {
                    var bestLvl = (player.records && player.records.bestReality && player.records.bestReality.glyphLevel) || 0;
                    showInstab = bestLvl > 800;
                    if (typeof Glyphs !== 'undefined') {
                        if (typeof Glyphs.instabilityThreshold === 'number') instabThr = Math.floor(Glyphs.instabilityThreshold);
                        if (typeof Glyphs.hyperInstabilityThreshold === 'number') hyperInstabThr = Math.floor(Glyphs.hyperInstabilityThreshold);
                    }
                } catch(e) {}

                // Web `GlyphShowcasePanelModal.sortGlyphs` order — used for the
                // all-equipped summary sheet and the peek (upcoming) sheet. Slot
                // views still consume `equipped` (in slot order, with nulls).
                var STANDARD_ORDER = ["reality","effarig","power","infinity","replication","time","dilation","cursed","companion"];
                function _sortByStandardOrder(arr) {
                    return arr.slice().sort(function(a,b){
                        return STANDARD_ORDER.indexOf(a.type) - STANDARD_ORDER.indexOf(b.type);
                    });
                }
                var equippedSorted = _sortByStandardOrder(equipped.filter(function(g){ return g; }));
                peekGlyphs = _sortByStandardOrder(peekGlyphs);

                // Auto-restart toggle for Celestial Realities (web `GlyphsTab.vue:128-146`).
                // Only shown when inside a celestial reality; stored as `player.options.retryCelestial`.
                var retryCelestial = false;
                try { retryCelestial = !!player.options.retryCelestial; } catch(ex) {}
                var inCelestialReality = false;
                try { inCelestialReality = !!isInCelestialReality(); } catch(ex) {}

                // Enslaved hint flavor (web `GlyphsTab.vue:71-75`) — shown above equipped
                // glyphs when running Enslaved AND any non-companion glyph was level-boosted
                // by `Enslaved.glyphLevelMin`.
                var showEnslavedHint = false;
                try {
                    if (typeof Enslaved !== 'undefined' && Enslaved.isRunning) {
                        var activeNC = Glyphs.activeWithoutCompanion;
                        if (activeNC) {
                            for (var ai = 0; ai < activeNC.length; ai++) {
                                if (activeNC[ai] && activeNC[ai].level < Enslaved.glyphLevelMin) { showEnslavedHint = true; break; }
                            }
                        }
                    }
                } catch(ex) {}

                return JSON.stringify({
                    equipped: equipped, equippedSorted: equippedSorted, slotCount: slotCount,
                    inv: inv, total: Glyphs.totalSlots,
                    prot: player.reality.glyphs.protectedRows,
                    effects: effects, sacUnlocked: sacUnlocked,
                    sacTotals: sacTotals, respec: !!player.reality.respec,
                    respecIntoProtected: !!player.options.respecIntoProtected,
                    setName: setName, setNameColor: setNameColor,
                    hasEffarig: hasEffarig, hasReality: hasReality,
                    glyphTextColors: glyphTextColors,
                    alterationsUnlocked: alterationsUnlocked, hideAlteration: hideAlteration,
                    addThreshText: addThreshText, addThreshColor: addThreshColor,
                    empowerThreshText: empowerThreshText, empowerThreshColor: empowerThreshColor,
                    boostThreshText: boostThreshText, boostThreshColor: boostThreshColor,
                    maxSacText: maxSacText,
                    teresaMult: teresaMult, teresaMultText: teresaMultText, lastMachinesText: lastMachinesText,
                    realityGlyphSeen: realityGlyphSeen,
                    canPeek: canPeek, peekGlyphs: peekGlyphs, peekLevel: peekLevel,
                    reminderText: reminderText, reminderGood: reminderGood,
                    suggestions: suggestions,
                    levelFactors: levelFactors, finalLevel: finalLevel,
                    autoSort: autoSort, autoCollapse: autoCollapse,
                    autoAutoCleanUnlocked: autoAutoCleanUnlocked,
                    autoAutoClean: autoAutoClean, applyFilterToPurge: applyFilterToPurge,
                    hasGlyphFilter: hasGlyphFilter,
                    hasGlyphWeights: hasGlyphWeights,
                    isRefining: isRefining,
                    hasNegativeEffectScore: hasNegativeEffectScore,
                    effarigRunning: effarigRunning,
                    effarigStageName: effarigStageName,
                    effarigCap: effarigCap,
                    showInstability: showInstab,
                    instabilityThreshold: instabThr,
                    hyperInstabilityThreshold: hyperInstabThr,
                    retryCelestial: retryCelestial,
                    inCelestialReality: inCelestialReality,
                    showEnslavedHint: showEnslavedHint,
                    // `&& !Pelle.isDoomed` mirrors web `EquippedGlyphs.vue:125` — the Vue
                    // undo() handler refuses when doomed; JS-core `Glyphs.undo()` does NOT
                    // gate, so without this clause iOS could undo glyphs from a doomed run.
                    canUndo: (typeof TeresaUnlocks !== 'undefined' && TeresaUnlocks.undo
                        && TeresaUnlocks.undo.canBeApplied
                        && player.reality.glyphs.undo.length > 0
                        && Glyphs.findFreeIndex(player.options.respecIntoProtected) !== -1
                        && !(typeof Pelle !== 'undefined' && Pelle.isDoomed)),
                    musicCosmeticUnlocked: (function(){ try { var c = GameDatabase.reality.cosmeticGlyphs.music; return !!(c && c.isUnlocked()); } catch(e){ return false; } })()
                });

                function makeGlyphObj(g, idx, ctx) {
                    var tp = g.type || 'power';
                    var sym = GLYPH_SYMBOLS[tp] || '?';
                    var col = (GameDatabase.reality.glyphTypes[tp] || GameDatabase.reality.cosmeticGlyphs[tp] || {}).color || '#888';
                    // Cosmetic override (e.g. Music Glyph from Teresa's perk shop).
                    // Type stays the same so effect logic still works; only the
                    // displayed symbol + background/border color swap.
                    if (g.cosmetic) {
                        var cos = GameDatabase.reality.cosmeticGlyphs[g.cosmetic];
                        if (cos) {
                            if (cos.symbol) sym = cos.symbol;
                            if (cos.color) col = cos.color;
                        }
                    }
                    // Rarity display must reflect Pelle's doom nerf. Web mirrors:
                    //   GlyphComponent.vue:476 / GlyphTooltip.vue:129 →
                    //   formatRarity(strengthToRarity(Pelle.isDoomed ? Pelle.glyphStrength : glyph.strength))
                    // During doom the glyph's effective rarity is Pelle.glyphStrength
                    // (returns 1 → 0%), so Rarity % / name / color shown here must
                    // use the nerfed strength, not the raw stored value. Otherwise the
                    // tooltip shows the glyph's ORIGINAL rarity next to effect values
                    // that were already computed at 0% rarity (via
                    // getGlyphEffectValuesFromBitmask, which substitutes Pelle.glyphStrength),
                    // making the effects look like they ignore the nerf. Level is already
                    // shown nerfed via getAdjustedGlyphLevel (dispLvl below).
                    var str = g.strength || 1;
                    try {
                        if (typeof Pelle !== 'undefined' && Pelle.isDoomed) str = Pelle.glyphStrength;
                    } catch(ex) {}
                    var rarPct = Math.min(((str - 1) * 100 / 2.5), 100);
                    var rarName = 'Common';
                    var rarCol = '#888';
                    try {
                        var rar = getRarity(str);
                        rarName = rar.name || 'Common';
                        rarCol = rar.darkColor || rar.color || '#888';
                    } catch(ex) {}
                    // Per-effect formatting via the shared helper (also used by
                    // `requestReality()`). See `glyph-effect-format-helper.js`
                    // for the full contract — isGenerated filter, EMPOWER/BOOST/
                    // ADDITION alteration detection, `§…§` value markers, `[…]`
                    // brackets preserved, `{value2}` substituted via `conversion`.
                    // Effective level for active/inventory contexts mirrors web
                    // `effectiveLevel` via `getAdjustedGlyphLevel`.
                    var effLvl = g.level;
                    try {
                        if (ctx === 'active') effLvl = getAdjustedGlyphLevel(g);
                        else if (ctx === 'inv') effLvl = getAdjustedGlyphLevel(g, 0);
                    } catch(ex) {}
                    var fmt = _formatGlyphEffectBlock(g, effLvl);
                    var effs = fmt.effs;
                    var shortEffs = fmt.shortEffs;
                    var effBoostColors = fmt.effBoostColors;
                    var effAdditionColors = fmt.effAdditionColors;
                    var sacGain = '';
                    try { if (sacUnlocked) sacGain = format(GlyphSacrificeHandler.glyphSacrificeGain(g), 2); } catch(ex) {}
                    // Refine values mirror what `GlyphComponent.vue` passes to the tooltip:
                    //   uncappedRefineReward = glyphRawRefinementGain(g)            (no cap)
                    //   refineReward         = glyphRefinementGain(g)               (clamped to alchemy cap)
                    // Both gated on alchemy unlock for the type AND not companion/cursed/reality.
                    // `GlyphComponent.vue:532-537` passes the raw value directly — NOT divided by
                    // `glyphRefinementEfficiency`. Earlier iOS divided by efficiency and produced
                    // values 20× too large.
                    var refRew = '';
                    var unrefRew = '';
                    try {
                        if (tp !== 'companion' && tp !== 'cursed' && tp !== 'reality' &&
                            typeof AlchemyResource !== 'undefined' && AlchemyResource[tp] && AlchemyResource[tp].isUnlocked) {
                            refRew = format(GlyphSacrificeHandler.glyphRefinementGain(g), 2, 2);
                            unrefRew = format(GlyphSacrificeHandler.glyphRawRefinementGain(g), 2, 2);
                        }
                    } catch(ex) {}
                    // Filter score (auto-glyph filter), gated on score mode AND not companion/cursed/reality.
                    var score = '';
                    try {
                        if (scoreModeShows && tp !== 'companion' && tp !== 'cursed' && tp !== 'reality') {
                            score = format(AutoGlyphProcessor.filterValue(g), 1, 1);
                        }
                    } catch(ex) {}
                    // Per-type Pelle chaos description (web `GlyphTooltip.vue.update()` chaosDescription).
                    var chaosDesc = '';
                    try {
                        if (pelleChaosUnlocked && typeof Pelle !== 'undefined' && Pelle.getSpecialGlyphEffectDescription) {
                            chaosDesc = Pelle.getSpecialGlyphEffectDescription(tp) || '';
                        }
                    } catch(ex) {}
                    // Adjusted level for celestial caps/boosts. Web mirrors:
                    //   active   → getAdjustedGlyphLevel(g)        (default boost)
                    //   inventory → getAdjustedGlyphLevel(g, 0)    (no reality boost)
                    //   peek/upcoming → bare level (no celestial adjustment)
                    var dispLvl = g.level;
                    try {
                        if (ctx === 'active') dispLvl = getAdjustedGlyphLevel(g);
                        else if (ctx === 'inv') dispLvl = getAdjustedGlyphLevel(g, 0);
                    } catch(ex) {}
                    return {
                        id: (g.id !== undefined && g.id !== null) ? g.id : idx,
                        type: tp, sym: sym, lvl: g.level, dispLvl: dispLvl, rarPct: rarPct,
                        rarName: rarName, effs: effs, shortEffs: shortEffs, effCnt: effs.length,
                        effBits: (g.effects || 0),
                        effBoostColors: effBoostColors, effAdditionColors: effAdditionColors,
                        col: col, rarCol: rarCol, idx: idx, sacGain: sacGain,
                        refRew: refRew, unrefRew: unrefRew, score: score, chaosDesc: chaosDesc,
                        cosmetic: g.cosmetic || '', fixedCosmetic: !!g.fixedCosmetic
                    };
                }
            })()
            """)?.toString() ?? "{}"

        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let slotCount = obj["slotCount"] as? Int ?? 3
        let equippedArr = obj["equipped"] as? [Any] ?? []
        var equipped: [GlyphInfo?] = []
        for item in equippedArr {
            if let g = item as? [String: Any] {
                equipped.append(parseGlyphInfo(g))
            } else {
                equipped.append(nil)
            }
        }

        let equippedSortedArr = obj["equippedSorted"] as? [[String: Any]] ?? []
        let equippedSorted = equippedSortedArr.compactMap { parseGlyphInfo($0) }

        // Up to 120 inventory slots — the biggest bulk-poll allocation in the
        // codebase. Pre-reserve to skip grow-on-demand reallocs.
        let invArr = obj["inv"] as? [[String: Any]] ?? []
        var inventory: [GlyphInfo] = []
        inventory.reserveCapacity(invArr.count)
        for item in invArr {
            if let parsed = parseGlyphInfo(item) {
                inventory.append(parsed)
            }
        }

        let effArr = obj["effects"] as? [[String: Any]] ?? []
        var effects: [GlyphEffectDisplay] = []
        effects.reserveCapacity(effArr.count)
        for e in effArr {
            guard let id = e["id"] as? String else { continue }
            effects.append(GlyphEffectDisplay(
                id: id,
                description: e["desc"] as? String ?? "",
                typeColor: e["color"] as? String ?? "#b241e3",
                isCapped: e["capped"] as? Bool ?? false
            ))
        }

        let sacArr = obj["sacTotals"] as? [[String: Any]] ?? []
        let sacTotals: [GlyphSacrificeInfo] = sacArr.compactMap { s in
            guard let type = s["type"] as? String else { return nil }
            return GlyphSacrificeInfo(
                type: type, symbol: s["sym"] as? String ?? "?",
                color: s["color"] as? String ?? "#888",
                amount: s["amount"] as? String ?? "0",
                boost: s["boost"] as? String ?? ""
            )
        }

        // Parse peek glyphs
        let peekArr = obj["peekGlyphs"] as? [[String: Any]] ?? []
        let livePeekGlyphs = peekArr.compactMap { parseGlyphInfo($0) }
        let livePeekLevel = obj["peekLevel"] as? Int ?? 0

        // Sticky-cache substitution: during a Reality reset (automator or
        // manual), TimeStudy.reality.isBought briefly flips false, so the JS
        // returns an empty peek for a few polls. If we've ever Realityed and
        // have a previous non-empty peek cached, substitute it so the view
        // doesn't blink. Otherwise, refresh the cache from the live value.
        let peekGlyphs: [GlyphInfo]
        let peekLevel: Int
        if realityUnlocked && livePeekGlyphs.isEmpty && !cachedPeekGlyphs.isEmpty {
            peekGlyphs = cachedPeekGlyphs
            peekLevel = cachedPeekLevel
        } else {
            peekGlyphs = livePeekGlyphs
            peekLevel = livePeekLevel
            if realityUnlocked && !livePeekGlyphs.isEmpty {
                cachedPeekGlyphs = livePeekGlyphs
                cachedPeekLevel = livePeekLevel
            }
        }

        // Parse level factors
        let lfArr = obj["levelFactors"] as? [[String: Any]] ?? []
        let levelFactors: [GlyphLevelFactor] = lfArr.compactMap { f in
            guard let name = f["name"] as? String else { return nil }
            return GlyphLevelFactor(
                name: name,
                formula: f["formula"] as? String ?? "",
                value: f["value"] as? String ?? "",
                op: f["op"] as? String ?? "×"
            )
        }

        // Parse reminder suggestions
        let suggestions = obj["suggestions"] as? [String] ?? []

        state.glyphsState = GlyphsTabState(
            equippedGlyphs: equipped,
            equippedSortedGlyphs: equippedSorted,
            activeSlotCount: slotCount,
            inventory: inventory,
            totalSlots: obj["total"] as? Int ?? 120,
            protectedRows: obj["prot"] as? Int ?? 2,
            currentEffects: effects,
            sacrificeUnlocked: obj["sacUnlocked"] as? Bool ?? false,
            sacrificeTotals: sacTotals,
            respec: obj["respec"] as? Bool ?? false,
            respecIntoProtected: obj["respecIntoProtected"] as? Bool ?? false,
            setName: obj["setName"] as? String ?? "",
            canPeek: obj["canPeek"] as? Bool ?? false,
            peekGlyphs: peekGlyphs,
            peekLevel: peekLevel,
            reminderText: obj["reminderText"] as? String ?? "",
            reminderIsGood: obj["reminderGood"] as? Bool ?? false,
            reminderSuggestions: suggestions,
            levelFactors: GlyphLevelFactorsState(
                factors: levelFactors,
                finalLevel: obj["finalLevel"] as? String ?? ""
            ),
            autoSortMode: obj["autoSort"] as? Int ?? 0,
            autoCollapse: obj["autoCollapse"] as? Bool ?? false,
            autoAutoCleanUnlocked: obj["autoAutoCleanUnlocked"] as? Bool ?? false,
            autoAutoClean: obj["autoAutoClean"] as? Bool ?? false,
            applyFilterToPurge: obj["applyFilterToPurge"] as? Bool ?? false,
            hasGlyphFilter: obj["hasGlyphFilter"] as? Bool ?? false,
            hasGlyphWeights: obj["hasGlyphWeights"] as? Bool ?? false,
            isRefining: obj["isRefining"] as? Bool ?? false,
            hasNegativeEffectScore: obj["hasNegativeEffectScore"] as? Bool ?? false,
            effarigRunning: obj["effarigRunning"] as? Bool ?? false,
            effarigStageName: obj["effarigStageName"] as? String ?? "Infinity",
            effarigGlyphLevelCap: obj["effarigCap"] as? Int ?? 100,
            canUndoGlyph: obj["canUndo"] as? Bool ?? false,
            inCelestialReality: obj["inCelestialReality"] as? Bool ?? false,
            retryCelestialEnabled: obj["retryCelestial"] as? Bool ?? false,
            showEnslavedHint: obj["showEnslavedHint"] as? Bool ?? false,
            showInstability: obj["showInstability"] as? Bool ?? false,
            instabilityThreshold: obj["instabilityThreshold"] as? Int ?? 1000,
            hyperInstabilityThreshold: obj["hyperInstabilityThreshold"] as? Int ?? 4000
        )
        state.glyphsState.setNameColor = obj["setNameColor"] as? String ?? "#ffffff"
        state.glyphsState.hasEffarig = obj["hasEffarig"] as? Bool ?? false
        state.glyphsState.hasReality = obj["hasReality"] as? Bool ?? false
        state.glyphsState.glyphTextColors = obj["glyphTextColors"] as? Bool ?? true
        state.glyphsState.alterationsUnlocked = obj["alterationsUnlocked"] as? Bool ?? false
        state.glyphsState.hideAlteration = obj["hideAlteration"] as? Bool ?? false
        state.glyphsState.additionThresholdText = obj["addThreshText"] as? String ?? ""
        state.glyphsState.additionThresholdColor = obj["addThreshColor"] as? String ?? ""
        state.glyphsState.empowermentThresholdText = obj["empowerThreshText"] as? String ?? ""
        state.glyphsState.empowermentThresholdColor = obj["empowerThreshColor"] as? String ?? ""
        state.glyphsState.boostingThresholdText = obj["boostThreshText"] as? String ?? ""
        state.glyphsState.boostingThresholdColor = obj["boostThreshColor"] as? String ?? ""
        state.glyphsState.maxSacrificeText = obj["maxSacText"] as? String ?? ""
        state.glyphsState.teresaMult = obj["teresaMult"] as? Double ?? 1
        state.glyphsState.teresaMultText = obj["teresaMultText"] as? String ?? ""
        state.glyphsState.lastMachinesText = obj["lastMachinesText"] as? String ?? ""
        state.glyphsState.realityGlyphSeen = obj["realityGlyphSeen"] as? Bool ?? false
        state.glyphsState.musicCosmeticUnlocked = obj["musicCosmeticUnlocked"] as? Bool ?? false
    }

    private func parseGlyphInfo(_ g: [String: Any]) -> GlyphInfo? {
        guard let id = g["id"] as? Int else { return nil }
        let lvl = g["lvl"] as? Int ?? 0
        // Default `displayLevel` to `lvl` so call sites that read either field
        // get a sensible value when no celestial cap/boost is in play.
        let dispLvl = g["dispLvl"] as? Int ?? lvl
        return GlyphInfo(
            id: id,
            type: g["type"] as? String ?? "power",
            symbol: g["sym"] as? String ?? "?",
            level: lvl,
            displayLevel: dispLvl,
            rarityPercent: g["rarPct"] as? Double ?? 0,
            rarityName: g["rarName"] as? String ?? "Common",
            effects: g["effs"] as? [String] ?? [],
            shortEffects: g["shortEffs"] as? [String] ?? [],
            effectBoostColors: g["effBoostColors"] as? [String] ?? [],
            effectAdditionColors: g["effAdditionColors"] as? [String] ?? [],
            effectCount: g["effCnt"] as? Int ?? 0,
            effectBitmask: g["effBits"] as? Int ?? 0,
            typeColor: g["col"] as? String ?? "#888",
            rarityColor: g["rarCol"] as? String ?? "#888",
            idx: g["idx"] as? Int ?? 0,
            sacrificeGain: g["sacGain"] as? String ?? "",
            refineReward: g["refRew"] as? String ?? "",
            uncappedRefineReward: g["unrefRew"] as? String ?? "",
            filterScore: g["score"] as? String ?? "",
            chaosDescription: g["chaosDesc"] as? String ?? "",
            hasCustomCosmetic: (g["cosmetic"] as? String).map { !$0.isEmpty } ?? false,
            isFixedCosmetic: g["fixedCosmetic"] as? Bool ?? false
        )
    }

    // MARK: - Automator Points polling

    private func pollAutomatorPoints(_ state: inout GameState) {
        let json = context.evaluateScript("""
            (function() {
                var totalPts = AutomatorPoints.totalPoints;
                var required = AutomatorPoints.pointsForAutomator;
                var isUnlocked = totalPts >= required;
                var fromPerks = AutomatorPoints.pointsFromPerks;
                var fromUpgrades = AutomatorPoints.pointsFromUpgrades;
                var fromOther = AutomatorPoints.pointsFromOther;

                var perkSources = [];
                var perks = AutomatorPoints.perks;
                for (var i = 0; i < perks.length; i++) {
                    var p = perks[i];
                    perkSources.push({
                        name: p.config.label || '',
                        desc: p.config.shortDescription || '',
                        pts: p.config.automatorPoints || 0,
                        bought: p.isBought
                    });
                }

                var upgSources = [];
                var upgs = AutomatorPoints.upgrades;
                for (var i = 0; i < upgs.length; i++) {
                    var u = upgs[i];
                    upgSources.push({
                        name: u.config.name || '',
                        desc: u.config.shortDescription || '',
                        pts: u.config.automatorPoints || 0,
                        bought: u.isBought
                    });
                }

                var otherSources = [];
                var others = GameDatabase.reality.automator.otherAutomatorPoints;
                for (var i = 0; i < others.length; i++) {
                    var o = others[i];
                    otherSources.push({
                        name: o.name || '',
                        desc: typeof o.shortDescription === 'function' ? o.shortDescription() : (o.shortDescription || ''),
                        pts: typeof o.automatorPoints === 'function' ? o.automatorPoints() : (o.automatorPoints || 0),
                        bought: typeof o.automatorPoints === 'function' ? o.automatorPoints() > 0 : false
                    });
                }

                var speed = format(1000 / AutomatorBackend.currentInterval, 2, 2);

                return JSON.stringify({
                    total: totalPts, required: required, unlocked: isUnlocked,
                    fromPerks: fromPerks, fromUpgrades: fromUpgrades, fromOther: fromOther,
                    perks: perkSources, upgrades: upgSources, other: otherSources,
                    speed: speed
                });
            })()
            """)?.toString() ?? "{}"

        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // JSONSerialization bridges JS numbers as `NSNumber` — read via
        // `intValue` so a JS-side fractional Double (e.g. an `automatorPoints`
        // that returns 2.0 or a math result) doesn't trip an Int conversion
        // crash. `as? Int` is unreliable here: a Double-shaped NSNumber
        // sometimes round-trips, sometimes returns nil.
        func intVal(_ any: Any?, default def: Int = 0) -> Int {
            (any as? NSNumber)?.intValue ?? def
        }

        func parseSources(_ arr: [[String: Any]], category: AutomatorPointCategory) -> [AutomatorPointSource] {
            arr.compactMap { s in
                guard let name = s["name"] as? String else { return nil }
                return AutomatorPointSource(
                    name: name,
                    description: s["desc"] as? String ?? "",
                    points: intVal(s["pts"]),
                    isBought: s["bought"] as? Bool ?? false,
                    category: category
                )
            }
        }

        state.automatorState = AutomatorPointsState(
            totalPoints: intVal(obj["total"]),
            pointsRequired: intVal(obj["required"], default: 100),
            pointsFromPerks: intVal(obj["fromPerks"]),
            pointsFromUpgrades: intVal(obj["fromUpgrades"]),
            pointsFromOther: intVal(obj["fromOther"]),
            perkSources: parseSources(obj["perks"] as? [[String: Any]] ?? [], category: .perk),
            upgradeSources: parseSources(obj["upgrades"] as? [[String: Any]] ?? [], category: .upgrade),
            otherSources: parseSources(obj["other"] as? [[String: Any]] ?? [], category: .other),
            automatorSpeed: obj["speed"] as? String ?? "0",
            isUnlocked: obj["unlocked"] as? Bool ?? false
        )
    }

    // MARK: - Automator Editor polling

    private func pollAutomatorEditor(_ state: inout GameState) {
        let json = context.evaluateScript("""
            (function() {
                var ab = AutomatorBackend;
                var st = player.reality.automator.state;
                var scripts = Object.values(player.reality.automator.scripts);
                var scriptList = [];
                var totalLen = 0;
                for (var i = 0; i < scripts.length; i++) {
                    var s = scripts[i];
                    var len = (s.content || '').length;
                    totalLen += len;
                    scriptList.push({ id: s.id, name: s.name || '', len: len });
                }
                var editScript = ab.currentEditingScript;
                var editLen = editScript ? (editScript.content || '').length : 0;
                var errs = AutomatorData.currentErrors();
                var errList = [];
                for (var i = 0; i < errs.length; i++) {
                    var e = errs[i];
                    errList.push({ line: e.startLine || 0, info: e.info || '', tip: e.tip || '' });
                }
                var mode = st.mode;
                var isOn = ab.isOn;
                var speed = format(1000 / ab.currentInterval, 2, 2);
                var statusText = '';
                if (isOn && mode === 2) statusText = "Running: '" + ab.scriptName + "'";
                else if (isOn && mode === 1) statusText = "Paused: '" + ab.scriptName + "'";
                else if (isOn && mode === 3) statusText = "Stepping: '" + ab.scriptName + "'";
                else if (ab.hasJustCompleted) statusText = 'Script completed';
                else statusText = '';
                return JSON.stringify({
                    isOn: isOn,
                    isRunning: isOn && mode === 2,
                    isPaused: isOn && mode === 1,
                    currentLine: ab.currentLineNumber,
                    hasJustCompleted: ab.hasJustCompleted || false,
                    scripts: scriptList,
                    editingID: st.editorScript,
                    runningID: st.topLevelScript,
                    repeat: st.repeat || false,
                    forceRestart: st.forceRestart || false,
                    followExecution: st.followExecution || false,
                    errors: errList,
                    editChars: editLen,
                    totalChars: totalLen,
                    speed: speed,
                    status: statusText
                });
            })()
            """)?.toString() ?? "{}"

        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let scriptArr = (obj["scripts"] as? [[String: Any]] ?? []).compactMap { s -> AutomatorScriptInfo? in
            guard let id = s["id"] as? Int else { return nil }
            return AutomatorScriptInfo(
                id: id,
                name: s["name"] as? String ?? "",
                contentLength: s["len"] as? Int ?? 0
            )
        }

        let errorArr = (obj["errors"] as? [[String: Any]] ?? []).enumerated().compactMap { (idx, e) -> AutomatorErrorInfo? in
            AutomatorErrorInfo(
                id: idx,
                startLine: e["line"] as? Int ?? 0,
                info: e["info"] as? String ?? "",
                tip: e["tip"] as? String ?? ""
            )
        }

        state.automatorEditorState = AutomatorEditorState(
            isOn: obj["isOn"] as? Bool ?? false,
            isRunning: obj["isRunning"] as? Bool ?? false,
            isPaused: obj["isPaused"] as? Bool ?? false,
            currentLine: obj["currentLine"] as? Int ?? -1,
            hasJustCompleted: obj["hasJustCompleted"] as? Bool ?? false,
            scripts: scriptArr,
            editingScriptID: obj["editingID"] as? Int ?? 0,
            runningScriptID: obj["runningID"] as? Int ?? 0,
            repeatOn: obj["repeat"] as? Bool ?? false,
            forceRestartOn: obj["forceRestart"] as? Bool ?? false,
            followExecution: obj["followExecution"] as? Bool ?? false,
            errors: errorArr,
            currentScriptChars: obj["editChars"] as? Int ?? 0,
            totalChars: obj["totalChars"] as? Int ?? 0,
            maxScriptChars: 10000,
            maxTotalChars: 60000,
            maxScriptCount: 20,
            intervalText: (obj["speed"] as? String ?? "0") + " commands/sec",
            statusText: obj["status"] as? String ?? "",
            intervalTextCompact: (obj["speed"] as? String ?? "0") + " com/s"
        )
    }

    // MARK: - Black Hole polling

    private func pollBlackHoles(_ state: inout GameState) {
        let json = context.evaluateScript("""
            (function() {
                var unlocked = BlackHoles.areUnlocked;
                if (!unlocked) return JSON.stringify({ unlocked: false });
                var paused = BlackHoles.arePaused;
                var permanent = BlackHoles.arePermanent;
                var hasBH2 = BlackHole(2).isUnlocked;
                var isLaitela = Laitela.isRunning;

                var stateChange;
                if (player.blackHoleNegative < 1 && !isLaitela) stateChange = paused ? 'Uninvert' : 'Invert';
                else stateChange = paused ? 'Unpause' : 'Pause';

                var bhs = [];
                for (var i = 1; i <= 2; i++) {
                    var bh = BlackHole(i);
                    if (!bh.isUnlocked) continue;
                    var isPerm = bh.isPermanent;
                    var isActive = bh.isActive;
                    var isCharged = bh.isCharged;
                    var nextChange = TimeSpan.fromSeconds(bh.timeWithPreviousActiveToNextStateChange).toStringShort();
                    var st;
                    if (isPerm) st = 'Permanently Active';
                    else if (isActive) st = 'Active (' + nextChange + ' remaining)';
                    else if (i === 2 && isCharged) st = 'Charged (Activates with BH1, ' + nextChange + ' remaining)';
                    else st = 'Inactive (Activation in ' + nextChange + ')';

                    var uptime = isPerm ? '100%' : formatPercents(bh.duration / bh.cycleLength, 3);
                    var upgrades = [];
                    var types = ['interval', 'power', 'duration'];
                    var descs = [
                        'Reduce inactive time by 20%',
                        'Make ' + formatPercents(0.35) + ' stronger',
                        'Extend duration by 30%'
                    ];
                    var effectTitles = ['Current interval', 'Current power', 'Current duration'];
                    var effects = [
                        TimeSpan.fromSeconds(bh.rawInterval).toStringShort(false),
                        formatX(bh.power, 2, 2),
                        TimeSpan.fromSeconds(bh.duration).toStringShort(false)
                    ];
                    var upgs = [bh.intervalUpgrade, bh.powerUpgrade, bh.durationUpgrade];
                    for (var j = 0; j < 3; j++) {
                        var u = upgs[j];
                        var capped = u.value === 0;
                        var ab = u.hasAutobuyer ? Autobuyer.blackHolePower(u.id) : null;
                        upgrades.push({
                            id: i + '-' + types[j], desc: descs[j],
                            effectTitle: effectTitles[j], effect: effects[j],
                            cost: format(u.cost, 2, 0), affordable: !!u.isAffordable && !capped,
                            capped: capped,
                            hasAutobuyer: !!u.hasAutobuyer,
                            autoUnlocked: !!(ab && ab.isUnlocked),
                            autoActive: !!(ab && ab.isActive),
                            upgradeId: u.id
                        });
                    }
                    bhs.push({
                        id: i, unlocked: true, permanent: isPerm, state: st,
                        power: formatX(bh.power, 2, 2),
                        duration: TimeSpan.fromSeconds(bh.duration).toStringShort(false),
                        interval: TimeSpan.fromSeconds(bh.rawInterval).toStringShort(false),
                        uptime: uptime, upgrades: upgrades
                    });
                }

                var detailed = '';
                if (hasBH2 && !permanent) {
                    var bh1r = BlackHole(1).timeWithPreviousActiveToNextStateChange;
                    var bh2r = BlackHole(2).timeWithPreviousActiveToNextStateChange;
                    if (BlackHole(1).isActive && BlackHole(2).isActive) {
                        detailed = 'Black Hole 2 is active for the next ' + TimeSpan.fromSeconds(Math.min(bh1r, bh2r)).toStringShort() + '!';
                    } else if (BlackHole(1).isActive && bh2r < bh1r) {
                        detailed = 'Black Hole 2 will activate before BH1 deactivates, for ' + TimeSpan.fromSeconds(Math.min(bh1r - bh2r, BlackHole(2).duration)).toStringShort();
                    } else if (BlackHole(2).isCharged) {
                        detailed = 'Black Hole 2 will activate with Black Hole 1, for ' + TimeSpan.fromSeconds(Math.min(BlackHole(1).duration, bh2r)).toStringShort() + '.';
                    } else {
                        detailed = 'Black Hole 2 timer only advances while Black Hole 1 is active.';
                    }
                }

                var bh1 = BlackHole(1);

                // Auto-pause cycle button (web BlackHoleTab.vue `pauseModeString`).
                // Hidden when BH1 is permanent — no activation cycle to pause before.
                var autoPauseVisible = !bh1.isPermanent;
                var autoPauseLabel = "Do not pause";
                var autoPauseShort = "Off";
                var apMode = player.blackHoleAutoPauseMode | 0;
                if (apMode === BLACK_HOLE_PAUSE_MODE.PAUSE_BEFORE_BH1) {
                    autoPauseLabel = hasBH2 ? "Before BH1" : "Before activation";
                    autoPauseShort = hasBH2 ? "BH1" : "On";
                } else if (apMode === BLACK_HOLE_PAUSE_MODE.PAUSE_BEFORE_BH2) {
                    autoPauseLabel = "Before BH2";
                    autoPauseShort = "BH2";
                }

                // Inversion slider state — only visible post-V-flipped & BHs
                // permanent. Shared with the Enslaved tab.
                var invUnlocked = false, invActive = false, invSlider = 0;
                var invDivisor = "1.00", invSliderDisabled = false, invSliderLock = "";
                try {
                    if (typeof V !== "undefined") {
                        invUnlocked = !!V.isFlipped && !!BlackHoles.arePermanent;
                        invActive = !!BlackHoles.areNegative;
                        var bhNeg = player.blackHoleNegative || 1;
                        invSlider = -Math.log10(bhNeg);
                        invDivisor = format(Math.pow(10, invSlider), 2, 2);
                        var maxInversion = (player.requirementChecks && player.requirementChecks.reality
                            && player.requirementChecks.reality.slowestBH <= 1e-300);
                        if (typeof ImaginaryUpgrade !== "undefined"
                            && typeof Ra !== "undefined"
                            && ImaginaryUpgrade(24).isLockingMechanics && Ra.isRunning && maxInversion) {
                            invSliderDisabled = true;
                            invSliderLock = 'Inversion strength cannot be modified due to Lock for "' + ImaginaryUpgrade(24).name + '"';
                        }
                    }
                } catch (e) {}

                return JSON.stringify({
                    unlocked: true, paused: paused, stateChange: stateChange,
                    bhs: bhs, detailed: detailed, hasBH2: hasBH2, permanent: permanent,
                    bh1Power: bh1.power,
                    bh1Duration: bh1.duration,
                    bh1CycleLength: bh1.cycleLength,
                    bh1Phase: bh1.phase,
                    bh1IsActive: bh1.isActive,
                    bh2IsActive: BlackHole(2).isActive,
                    areNegative: BlackHoles.areNegative,
                    invUnlocked: invUnlocked,
                    invActive: invActive,
                    invSlider: invSlider,
                    invDivisor: invDivisor,
                    invSliderDisabled: invSliderDisabled,
                    invSliderLock: invSliderLock,
                    autoPauseVisible: autoPauseVisible,
                    autoPauseLabel: autoPauseLabel,
                    autoPauseShort: autoPauseShort
                });
            })()
            """)?.toString() ?? "{}"

        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let unlocked = obj["unlocked"] as? Bool ?? false
        guard unlocked else {
            state.blackHoleState = .empty
            return
        }

        let bhArr = obj["bhs"] as? [[String: Any]] ?? []
        let blackHoles: [BlackHoleInfo] = bhArr.compactMap { bh in
            guard let id = bh["id"] as? Int else { return nil }
            let upgArr = bh["upgrades"] as? [[String: Any]] ?? []
            let upgrades: [BlackHoleUpgradeInfo] = upgArr.compactMap { u in
                guard let uid = u["id"] as? String else { return nil }
                return BlackHoleUpgradeInfo(
                    id: uid,
                    description: u["desc"] as? String ?? "",
                    effectTitle: u["effectTitle"] as? String ?? "",
                    effectText: u["effect"] as? String ?? "",
                    cost: u["cost"] as? String ?? "0",
                    isAffordable: u["affordable"] as? Bool ?? false,
                    isCapped: u["capped"] as? Bool ?? false,
                    upgradeId: u["upgradeId"] as? Int ?? 0,
                    autobuyerUnlocked: u["autoUnlocked"] as? Bool ?? false,
                    autobuyerActive: u["autoActive"] as? Bool ?? false
                )
            }
            return BlackHoleInfo(
                id: id,
                isUnlocked: bh["unlocked"] as? Bool ?? false,
                isPermanent: bh["permanent"] as? Bool ?? false,
                stateText: bh["state"] as? String ?? "",
                power: bh["power"] as? String ?? "",
                duration: bh["duration"] as? String ?? "",
                interval: bh["interval"] as? String ?? "",
                uptime: bh["uptime"] as? String ?? "",
                upgrades: upgrades
            )
        }

        var bh = BlackHoleState(
            isUnlocked: true,
            isPaused: obj["paused"] as? Bool ?? false,
            stateChangeLabel: obj["stateChange"] as? String ?? "Pause",
            blackHoles: blackHoles,
            detailedBH2: obj["detailed"] as? String ?? "",
            hasBH2: obj["hasBH2"] as? Bool ?? false,
            isPermanent: obj["permanent"] as? Bool ?? false,
            bh1Power: obj["bh1Power"] as? Double ?? 180,
            bh1Duration: obj["bh1Duration"] as? Double ?? 10,
            bh1CycleLength: obj["bh1CycleLength"] as? Double ?? 3610,
            bh1Phase: obj["bh1Phase"] as? Double ?? 0,
            bh1IsActive: obj["bh1IsActive"] as? Bool ?? false,
            bh2IsActive: obj["bh2IsActive"] as? Bool ?? false,
            areNegative: obj["areNegative"] as? Bool ?? false
        )
        bh.inversionUnlocked = obj["invUnlocked"] as? Bool ?? false
        bh.inversionActive = obj["invActive"] as? Bool ?? false
        bh.negativeSlider = obj["invSlider"] as? Double ?? 0
        bh.negativeBHDivisor = obj["invDivisor"] as? String ?? "1.00"
        bh.sliderDisabled = obj["invSliderDisabled"] as? Bool ?? false
        bh.sliderLockText = obj["invSliderLock"] as? String ?? ""
        bh.autoPauseVisible = obj["autoPauseVisible"] as? Bool ?? false
        bh.autoPauseLabel = obj["autoPauseLabel"] as? String ?? "Do not pause"
        bh.autoPauseShortLabel = obj["autoPauseShort"] as? String ?? "Off"
        state.blackHoleState = bh
    }

    // MARK: - Reality Upgrades polling

    private func pollRealityUpgrades(_ state: inout GameState) {
        let json = context.evaluateScript("""
            (function() {
                var autoAvail = !!(typeof Ra !== 'undefined' && Ra.unlocks
                    && Ra.unlocks.instantECAndRealityUpgradeAutobuyers
                    && Ra.unlocks.instantECAndRealityUpgradeAutobuyers.canBeApplied);
                var result = [];
                for (var i = 1; i <= 25; i++) {
                    var u = RealityUpgrade(i);
                    var c = u.config;
                    var isRebuy = i <= 5;
                    var desc = (typeof c.description === 'function' ? c.description() : (c.description || '')).replace(/\\s+/g, ' ').trim();
                    var effect = '';
                    try { if (c.formatEffect) effect = c.formatEffect(c.effect()).replace(/\\s+/g, ' ').trim(); } catch(e) {}
                    var req = '';
                    if (!isRebuy && c.requirement) {
                        try { req = (typeof c.requirement === 'function' ? c.requirement() : c.requirement).replace(/\\s+/g, ' ').trim(); } catch(e) {}
                    }
                    var name = (c.name || '').replace(/\\s+/g, ' ').trim();
                    var autoOn = false;
                    if (isRebuy) {
                        try { autoOn = !!Autobuyer.realityUpgrade(i).isActive; } catch(e) {}
                    }
                    result.push({
                        id: i, name: name, desc: desc, cost: format(u.cost, 2),
                        effect: effect, bought: !!u.isBought, affordable: !!u.isAffordable,
                        available: isRebuy || !!u.isAvailableForPurchase,
                        req: req, rebuyable: isRebuy,
                        amount: isRebuy ? (player.reality.rebuyables[i] || 0) : 0,
                        canLock: !isRebuy && !!c.canLock && !u.isAvailableForPurchase && !u.isBought,
                        hasLock: !isRebuy && !!u.hasPlayerLock,
                        possible: isRebuy || !!u.isPossible,
                        autoOn: autoOn,
                        autoAvail: autoAvail
                    });
                }
                return JSON.stringify(result);
            })()
            """)?.toString() ?? "[]"

        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return
        }

        // 25 reality upgrades polled per tick on the Reality Upgrades tab —
        // pre-reserve to skip grow-on-demand reallocs.
        var upgrades: [RealityUpgradeInfo] = []
        upgrades.reserveCapacity(arr.count)
        for obj in arr {
            guard let id = obj["id"] as? Int else { continue }
            upgrades.append(RealityUpgradeInfo(
                id: id,
                name: obj["name"] as? String ?? "",
                description: obj["desc"] as? String ?? "",
                cost: obj["cost"] as? String ?? "0",
                effectText: obj["effect"] as? String ?? "",
                isBought: obj["bought"] as? Bool ?? false,
                isAffordable: obj["affordable"] as? Bool ?? false,
                isAvailable: obj["available"] as? Bool ?? false,
                requirementText: obj["req"] as? String ?? "",
                isRebuyable: obj["rebuyable"] as? Bool ?? false,
                boughtAmount: obj["amount"] as? Int ?? 0,
                canLock: obj["canLock"] as? Bool ?? false,
                hasLock: obj["hasLock"] as? Bool ?? false,
                isPossible: obj["possible"] as? Bool ?? true,
                isAutobuyerOn: obj["autoOn"] as? Bool ?? false,
                autobuyerAvailable: obj["autoAvail"] as? Bool ?? false
            ))
        }
        state.realityUpgrades = upgrades
    }

    // MARK: - Imaginary Upgrades polling

    /// Single bulk JSON eval. Mirrors pollRealityUpgrades but also pulls
    /// Imaginary-specific fields (ETA text, pelle-disabled, autobuyer state).
    /// Rows 1-2 (IDs 1-10) are rebuyable, 3-5 (IDs 11-25) are one-shot.
    private func pollImaginaryUpgrades(_ state: inout GameState) {
        let json = context.evaluateScript("""
            (function() {
                if (typeof ImaginaryUpgrade === "undefined") return "{}";
                var autoUnlocked = ImaginaryUpgrade(20).canBeApplied;
                var items = [];
                for (var i = 1; i <= 25; i++) {
                    var u = ImaginaryUpgrade(i);
                    var c = u.config;
                    var isRebuy = i <= 10;
                    var desc = (typeof c.description === 'function' ? c.description() : (c.description || '')).toString().replace(/\\s+/g, ' ').trim();
                    var effect = '';
                    try { if (c.formatEffect) effect = c.formatEffect(c.effect()).toString().replace(/\\s+/g, ' ').trim(); } catch(e) {}
                    var req = '';
                    if (!isRebuy && c.requirement) {
                        try {
                            var rv = (typeof c.requirement === 'function' ? c.requirement() : c.requirement);
                            req = (rv == null ? '' : rv.toString()).replace(/\\s+/g, ' ').trim();
                        } catch(e) {}
                    }
                    var name = (c.name || '').toString().replace(/\\s+/g, ' ').trim();
                    var eta = '';
                    try {
                        if (!u.canBeBought && u.isAvailableForPurchase && !u.isBought && !Pelle.isDoomed) {
                            var t = MachineHandler.estimateIMTimer(u.cost);
                            eta = isFinite(t) ? TimeSpan.fromSeconds(t).toString() : 'Never affordable';
                        }
                    } catch(e) {}
                    var autoOn = false;
                    if (isRebuy) {
                        try { autoOn = !!Autobuyer.imaginaryUpgrade(i).isActive; } catch(e) {}
                    }
                    items.push({
                        id: i, name: name, desc: desc, cost: format(u.cost, 2),
                        effect: effect, bought: !!u.isBought, affordable: !!u.canBeBought,
                        available: isRebuy || !!u.isAvailableForPurchase,
                        req: req, rebuyable: isRebuy,
                        amount: isRebuy ? (player.reality.imaginaryRebuyables[i] || 0) : 0,
                        canLock: !isRebuy && !!c.canLock && !u.isAvailableForPurchase && !u.isBought,
                        hasLock: !isRebuy && !!u.hasPlayerLock,
                        possible: isRebuy || !!u.isPossible,
                        eta: eta,
                        pelle: !!u.pelleDisabled,
                        autoOn: autoOn
                    });
                }
                return JSON.stringify({
                    iM: format(Currency.imaginaryMachines.value, 2),
                    capStr: formatMachines(MachineHandler.hardcapRM, MachineHandler.currentIMCap),
                    baseRMCap: format(MachineHandler.baseRMCap, 2),
                    capRM: format(MachineHandler.hardcapRM, 2),
                    scaleTime: Math.floor(MachineHandler.scaleTimeForIM),
                    autoAvailable: !!autoUnlocked,
                    items: items
                });
            })()
            """)?.toString() ?? "{}"

        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let autoAvail = obj["autoAvailable"] as? Bool ?? false
        let items = (obj["items"] as? [[String: Any]]) ?? []
        var s = ImaginaryUpgradesState(
            iMAmount: obj["iM"] as? String ?? "0",
            iMCapText: obj["capStr"] as? String ?? "0",
            baseRMCap: obj["baseRMCap"] as? String ?? "0",
            capRM: obj["capRM"] as? String ?? "0",
            scaleTimeSeconds: obj["scaleTime"] as? Int ?? 0,
            upgrades: []
        )
        s.upgrades = items.compactMap { d -> ImaginaryUpgradeInfo? in
            guard let id = d["id"] as? Int else { return nil }
            return ImaginaryUpgradeInfo(
                id: id,
                name: d["name"] as? String ?? "",
                description: d["desc"] as? String ?? "",
                cost: d["cost"] as? String ?? "0",
                effectText: d["effect"] as? String ?? "",
                isBought: d["bought"] as? Bool ?? false,
                isAffordable: d["affordable"] as? Bool ?? false,
                isAvailable: d["available"] as? Bool ?? false,
                requirementText: d["req"] as? String ?? "",
                isRebuyable: d["rebuyable"] as? Bool ?? false,
                boughtAmount: d["amount"] as? Int ?? 0,
                canLock: d["canLock"] as? Bool ?? false,
                hasLock: d["hasLock"] as? Bool ?? false,
                isPossible: d["possible"] as? Bool ?? true,
                etaText: d["eta"] as? String ?? "",
                isPelleDisabled: d["pelle"] as? Bool ?? false,
                isAutobuyerOn: d["autoOn"] as? Bool ?? false,
                autobuyerAvailable: autoAvail
            )
        }
        state.imaginaryUpgrades = s
    }

    // MARK: - Glyph Alchemy polling

    private func pollGlyphAlchemy(_ state: inout GameState) {
        let json = context.evaluateScript("_nativeAlchemyState()")?.toString() ?? "{}"
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        let unlocked = obj["unlocked"] as? Bool ?? false
        if !unlocked {
            state.glyphAlchemy = .empty
            return
        }
        var s = GlyphAlchemyState.empty
        s.isUnlocked = true
        s.isDoomed = obj["isDoomed"] as? Bool ?? false
        s.realityCreationVisible = obj["realityCreationVisible"] as? Bool ?? false
        s.createdRealityGlyph = obj["createdRealityGlyph"] as? Bool ?? false
        s.allReactionsDisabled = obj["allReactionsDisabled"] as? Bool ?? false
        s.alchemyCap = obj["alchemyCap"] as? Double ?? 0
        s.capFactor = obj["capFactor"] as? Double ?? 1

        if let rs = obj["resources"] as? [[String: Any]] {
            s.resources = rs.compactMap { d -> AlchemyResourceInfo? in
                guard let id = d["id"] as? Int else { return nil }
                return AlchemyResourceInfo(
                    id: id,
                    name: d["name"] as? String ?? "",
                    symbol: d["symbol"] as? String ?? "",
                    tier: d["tier"] as? Int ?? 1,
                    uiOrder: (d["uiOrder"] as? NSNumber)?.doubleValue ?? 0,
                    x: (d["x"] as? NSNumber)?.doubleValue ?? 50,
                    y: (d["y"] as? NSNumber)?.doubleValue ?? 50,
                    amount: d["amount"] as? String ?? "0",
                    cap: d["cap"] as? String ?? "0",
                    amountNum: (d["amountNum"] as? NSNumber)?.doubleValue ?? 0,
                    capNum: (d["capNum"] as? NSNumber)?.doubleValue ?? 0,
                    capped: d["capped"] as? Bool ?? false,
                    flow: (d["flow"] as? NSNumber)?.doubleValue ?? 0,
                    flowText: d["flowText"] as? String ?? "None",
                    isUnlocked: d["isUnlocked"] as? Bool ?? false,
                    isBaseResource: d["isBaseResource"] as? Bool ?? false,
                    lockText: d["lockText"] as? String ?? "",
                    reactionActive: d["reactionActive"] as? Bool ?? false,
                    reactionText: d["reactionText"] as? String ?? "",
                    reactionProduction: (d["reactionProduction"] as? NSNumber)?.doubleValue ?? 0,
                    effectText: d["effectText"] as? String ?? "",
                    description: d["description"] as? String ?? ""
                )
            }
        }
        if let ar = obj["arrows"] as? [[String: Any]] {
            s.arrows = ar.map { d in
                AlchemyReactionArrow(
                    reagentId: d["reagentId"] as? Int ?? 0,
                    productId: d["productId"] as? Int ?? 0,
                    reagentX: (d["rx"] as? NSNumber)?.doubleValue ?? 0,
                    reagentY: (d["ry"] as? NSNumber)?.doubleValue ?? 0,
                    productX: (d["px"] as? NSNumber)?.doubleValue ?? 0,
                    productY: (d["py"] as? NSNumber)?.doubleValue ?? 0,
                    isUnlocked: d["unlocked"] as? Bool ?? false,
                    isCapped: d["capped"] as? Bool ?? false,
                    isActive: d["active"] as? Bool ?? false,
                    isLessThanRequired: d["lessThan"] as? Bool ?? false
                )
            }
        }
        state.glyphAlchemy = s
    }

    // MARK: - Break Infinity polling

    private func pollBreakInfinity(_ state: inout GameState) {
        let hasMaxed = context.evaluateScript("Autobuyer.bigCrunch.hasMaxedInterval")?.toBool() ?? false
        // Use `PlayerProgress.hasBroken()` rather than `player.break` directly —
        // the raw flag resets after Armageddon while the web getter stays
        // true (it OR's in `isEternityUnlocked` / `isRealityUnlocked`).
        let isBroken = jsPlayerProgress.invokeMethod("hasBroken", withArguments: [])?.toBool() ?? false

        // Layout matches web: 4 rows × 3 columns (col = position in row, row = which row)
        let upgradeLayout: [(key: String, col: Int, row: Int)] = [
            ("totalAMMult",0,0),     ("currentAMMult",1,0),        ("galaxyBoost",2,0),
            ("infinitiedMult",0,1),  ("achievementMult",1,1),      ("slowestChallengeMult",2,1),
            ("infinitiedGen",0,2),   ("autobuyMaxDimboosts",1,2),  ("autobuyerSpeed",2,2),
            ("tickspeedCostMult",0,3), ("dimCostMult",1,3),        ("ipGen",2,3)
        ]

        var upgrades: [InfinityUpgradeInfo] = []
        upgrades.reserveCapacity(upgradeLayout.count)
        for info in upgradeLayout {
            let u = context.evaluateScript("BreakInfinityUpgrade.\(info.key)")
            let config = u?.forProperty("config")

            let descVal = config?.forProperty("description")
            let desc: String
            if descVal?.isObject == true {
                desc = normalizeWhitespace(descVal?.call(withArguments: [])?.toString() ?? "")
            } else {
                desc = normalizeWhitespace(descVal?.toString() ?? "")
            }

            let isBought = u?.forProperty("isBought")?.toBool() ?? false
            let isCapped = u?.forProperty("isCapped")?.toBool() ?? false
            let isRebuyable = u?.forProperty("isRebuyable")?.toBool() ?? false
            var effText: String? = nil
            // Show effect for bought/capped upgrades, and always for rebuyables (they show "Currently: X | Next: Y")
            if isBought || isCapped || isRebuyable {
                let formatEff = config?.forProperty("formatEffect")
                if formatEff?.isObject == true {
                    let effVal = u?.forProperty("effectValue")
                    effText = formatEff?.call(withArguments: [effVal as Any])?.toString()
                }
            }

            let costVal = u?.forProperty("cost")
            let costStr: String
            if let m = costVal?.forProperty("mantissa"), m.isUndefined == false {
                costStr = formatDecimal(GameDecimal(from: costVal))
            } else {
                let num = costVal?.toDouble() ?? 0
                costStr = formatPlainNumber(num)
            }

            upgrades.append(InfinityUpgradeInfo(
                id: info.key,
                name: config?.forProperty("id")?.toString() ?? info.key,
                description: desc,
                cost: costStr,
                isBought: isBought || isCapped,
                canBeBought: u?.forProperty("canBeBought")?.toBool() ?? false,
                effectText: effText,
                column: info.col, row: info.row,
                isAvailableForPurchase: true,
                isRebuyable: isRebuyable,
                isCharged: false,
                chargedEffectText: nil
            ))
        }

        state.breakInfinity = BreakInfinityState(
            hasMaxedInterval: hasMaxed,
            isBroken: isBroken,
            upgrades: upgrades
        )
    }

    // MARK: - Replicanti polling

    private func pollReplicanti(_ state: inout GameState) {
        let repl = jsPlayer.forProperty("replicanti")
        let isUnlocked = repl?.forProperty("unl")?.toBool() ?? false

        guard isUnlocked else {
            let result = context.evaluateScript("""
                (function() {
                    var cost = new Decimal(1e140).dividedByEffectOf(PelleRifts.vacuum.milestones[1]);
                    return { cost: cost, afford: Currency.infinityPoints.gte(cost) };
                })()
                """)
            let unlockCost = GameDecimal(from: result?.forProperty("cost"))
            let canAfford = result?.forProperty("afford")?.toBool() ?? false
            var empty = ReplicantiState.empty
            empty.isUnlockAffordable = canAfford
            empty.unlockCost = formatDecimal(unlockCost)
            state.replicanti = empty
            return
        }

        let amount = GameDecimal(from: repl?.forProperty("amount"))
        let mult = GameDecimal(from: context.evaluateScript("replicantiMult()"))

        let chance = repl?.forProperty("chance")?.toDouble() ?? 0
        let interval = repl?.forProperty("interval")?.toDouble() ?? 1000

        let chanceUpg = context.evaluateScript("ReplicantiUpgrade.chance")
        let intervalUpg = context.evaluateScript("ReplicantiUpgrade.interval")
        let galaxyUpg = context.evaluateScript("ReplicantiUpgrade.galaxies")

        let chanceCost = GameDecimal(from: chanceUpg?.forProperty("cost"))
        let intervalCost = GameDecimal(from: intervalUpg?.forProperty("cost"))
        let galCost = GameDecimal(from: galaxyUpg?.forProperty("cost"))

        let chanceIsCapped = chanceUpg?.forProperty("isCapped")?.toBool() ?? false
        let intervalIsCapped = intervalUpg?.forProperty("isCapped")?.toBool() ?? false

        // Interval: format next value for cost description
        let nextIntervalStr = context.evaluateScript("""
            (function() {
                var upg = ReplicantiUpgrade.interval;
                var next = upg.applyModifiers(upg.nextValue);
                if (next.lt(0.01)) return '< 0.01ms';
                if (next.gt(1000)) return (next.toNumber() / 1000).toFixed(2) + 's';
                return next.toNumber().toFixed(2) + 'ms';
            })()
            """)?.toString() ?? ""

        let galaxiesBought = clampedInt(repl?.forProperty("galaxies")?.toDouble() ?? 0)
        let galaxiesMax = clampedInt(galaxyUpg?.forProperty("value")?.toDouble() ?? 0)
        // Upgrade's extra (TS131 + Pelle rift) adds to the MAX cap — shown in the upgrade description.
        let galaxiesMaxBonus = clampedInt(galaxyUpg?.forProperty("extra")?.toDouble() ?? 0)
        // Replicanti.galaxies.extra (TS225/226 + Effarig × TS303) adds to CURRENT galaxies — shown next to bought count.
        let galaxiesExtra = clampedInt(context.evaluateScript("Replicanti.galaxies.extra")?.toDouble() ?? 0)
        let canBuyGalaxy = context.evaluateScript("Replicanti.galaxies.canBuyMore")?.toBool() ?? false

        // Galaxy thresholds
        let distantRG = Int(context.evaluateScript("ReplicantiUpgrade.galaxies.distantRGStart")?.toInt32() ?? 50)
        let remoteRG = Int(context.evaluateScript("ReplicantiUpgrade.galaxies.remoteRGStart")?.toInt32() ?? 250)

        // Gain text — compute in JS for accuracy
        // Gain text — computed in JS matching ReplicantiGainText.vue update() exactly
        let gainTexts = context.evaluateScript("""
            (function() {
                var updateRateMs = player.options.updateRate;
                var ticksPerSecond = 1000 / updateRateMs;
                var logGainFactorPerTick = Decimal.divide(getGameSpeedupForDisplay() * updateRateMs *
                    (Math.log(player.replicanti.chance + 1)), getReplicantiInterval());
                var log10GainFactorPerTick = logGainFactorPerTick.dividedBy(Math.LN10);
                var log10GainFactorPerTickUncapped = Decimal.divide(getGameSpeedupForDisplay() * updateRateMs *
                    (Math.log(player.replicanti.chance + 1)), getReplicantiInterval(false)).dividedBy(Math.LN10);
                var replicantiAmount = Replicanti.amount;
                var remainingText = '';
                var galaxyText = '';

                var totalTime = 308.25 / (ticksPerSecond * log10GainFactorPerTick.toNumber());
                var remainingTime = (308.25 - replicantiAmount.log10()) / (ticksPerSecond * log10GainFactorPerTick.toNumber());
                if (remainingTime < 0) remainingTime = 0;
                var galaxiesPerSecond = log10GainFactorPerTickUncapped.times(ticksPerSecond / 308.25);
                var secondsPerGalaxy = galaxiesPerSecond.reciprocal();

                if (remainingTime === 0) {
                    remainingText = 'At Infinite Replicanti (normally takes ' + TimeSpan.fromSeconds(secondsPerGalaxy.toNumber()) + ')';
                } else if (replicantiAmount.lt(100)) {
                    remainingText = 'Approximately ' + TimeSpan.fromSeconds(remainingTime) + ' remaining until Infinite Replicanti';
                } else {
                    remainingText = TimeSpan.fromSeconds(remainingTime) + ' remaining until Infinite Replicanti';
                }
                if (Replicanti.galaxies.max === 0) {
                    remainingText += ' (' + TimeSpan.fromSeconds(totalTime) + ' total)';
                }

                if (Replicanti.galaxies.max > 0) {
                    if (player.replicanti.galaxies === Replicanti.galaxies.max) {
                        galaxyText = 'You have reached the maximum amount of Replicanti Galaxies';
                    } else {
                        if (galaxiesPerSecond.gte(1)) {
                            galaxyText = 'You are gaining ' + format(galaxiesPerSecond, 2, 1) + ' Replicanti Galaxies per second';
                        } else {
                            galaxyText = 'You are gaining a Replicanti Galaxy every ' + TimeSpan.fromSeconds(secondsPerGalaxy.toNumber());
                        }
                    }
                }
                return JSON.stringify({r: remainingText, g: galaxyText});
            })()
            """)?.toString() ?? "{}"

        var remainingTimeText = ""
        var galaxyText = ""
        if let data = gainTexts.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            remainingTimeText = json["r"] ?? ""
            galaxyText = json["g"] ?? ""
        }

        // Galaxy reset text
        let isDivideUnlocked = context.evaluateScript("Achievement(126).isUnlocked")?.toBool() ?? false
        let galaxyResetText = isDivideUnlocked ? "Divide Replicanti by 1.80e308" : "Reset Replicanti amount"

        // Replicanti upgrade autobuyers (chance, interval, galaxies)
        let ec8Running = context.evaluateScript("EternityChallenge(8).isRunning")?.toBool() ?? false
        var chanceAutoUnlocked = false, chanceAutoActive = false
        var intervalAutoUnlocked = false, intervalAutoActive = false
        var galaxiesAutoUnlocked = false, galaxiesAutoActive = false
        for i in 1...3 {
            if let ab = context.evaluateScript("Autobuyer.replicantiUpgrade(\(i))"),
               !ab.isUndefined,
               ab.forProperty("isUnlocked")?.toBool() == true {
                let active = ab.forProperty("isActive")?.toBool() ?? false
                switch i {
                case 1: chanceAutoUnlocked = true; chanceAutoActive = active
                case 2: intervalAutoUnlocked = true; intervalAutoActive = active
                case 3: galaxiesAutoUnlocked = true; galaxiesAutoActive = active
                default: break
                }
            }
        }

        // Replicanti Galaxy autobuyer
        var galaxyAutoUnlocked = false, galaxyAutoActive = false, galaxyAutoEnabled = true
        if let rgAB = context.evaluateScript("Autobuyer.replicantiGalaxy"),
           !rgAB.isUndefined,
           rgAB.forProperty("isUnlocked")?.toBool() == true {
            galaxyAutoUnlocked = true
            galaxyAutoActive = rgAB.forProperty("isActive")?.toBool() ?? false
            galaxyAutoEnabled = rgAB.forProperty("isEnabled")?.toBool() ?? true
        }

        state.replicanti = ReplicantiState(
            isUnlocked: true,
            isUnlockAffordable: true,
            amount: formatDecimal(amount, places: 2),
            mult: formatX(mult, places: 2, placesUnder1000: 2),
            chance: "\(String(format: "%.0f", chance * 100))%",
            interval: formatInterval(interval),
            chanceUpgrade: ReplicantiUpgradeInfo(
                description: "Replicate chance: \(String(format: "%.0f", chance * 100))%",
                costDescription: chanceIsCapped ? "" : "+1% Costs: \(formatDecimal(chanceCost)) IP",
                cost: formatDecimal(chanceCost),
                isCapped: chanceIsCapped,
                canBeBought: chanceUpg?.forProperty("canBeBought")?.toBool() ?? false
            ),
            intervalUpgrade: ReplicantiUpgradeInfo(
                description: "Interval: \(formatInterval(interval))",
                costDescription: intervalIsCapped ? "" : "➜ \(nextIntervalStr) Costs: \(formatDecimal(intervalCost)) IP",
                cost: formatDecimal(intervalCost),
                isCapped: intervalIsCapped,
                canBeBought: intervalUpg?.forProperty("canBeBought")?.toBool() ?? false
            ),
            galaxyUpgrade: ReplicantiUpgradeInfo(
                description: galaxiesMaxBonus > 0
                    ? "Max Replicanti Galaxies:\n\(galaxiesMax) + \(galaxiesMaxBonus) = \(galaxiesMax + galaxiesMaxBonus)"
                    : "Max Replicanti Galaxies: \(galaxiesMax)",
                costDescription: "+1 Costs: \(formatDecimal(galCost)) IP",
                cost: formatDecimal(galCost),
                isCapped: false,
                canBeBought: galaxyUpg?.forProperty("canBeBought")?.toBool() ?? false
            ),
            galaxiesBought: galaxiesBought,
            galaxiesExtra: galaxiesExtra,
            galaxiesMax: galaxiesMax,
            canBuyGalaxy: canBuyGalaxy,
            unlockCost: "",
            distantRG: formatPlainNumber(Double(distantRG)),
            remoteRG: formatPlainNumber(Double(remoteRG)),
            remainingTimeText: remainingTimeText,
            galaxyText: galaxyText,
            galaxyResetText: galaxyResetText,
            canSeeGalaxyButton: galaxiesMax >= 1 || (jsPlayerProgress.invokeMethod("eternityUnlocked", withArguments: [])?.toBool() ?? false),
            chanceAutoUnlocked: chanceAutoUnlocked, chanceAutoActive: chanceAutoActive,
            intervalAutoUnlocked: intervalAutoUnlocked, intervalAutoActive: intervalAutoActive,
            galaxiesAutoUnlocked: galaxiesAutoUnlocked, galaxiesAutoActive: galaxiesAutoActive,
            galaxyAutoUnlocked: galaxyAutoUnlocked, galaxyAutoActive: galaxyAutoActive, galaxyAutoEnabled: galaxyAutoEnabled,
            isEC8Running: ec8Running
        )
    }

    /// Format a replicanti interval in ms or seconds
    private func formatInterval(_ ms: Double) -> String {
        if ms >= 1000 {
            return String(format: "%.2fs", ms / 1000)
        }
        return "\(clampedInt(ms))ms"
    }

    private func pollAutobuyers(_ state: inout GameState, abUnlocked: Bool) {
        let allOn = jsPlayer.forProperty("auto")?.forProperty("autobuyersOn")?.toBool() ?? true

        var dims: [AutobuyerDimInfo] = []
        for t in 1...8 {
            let ab = context.evaluateScript("Autobuyer.antimatterDimension(\(t))")
            let data = ab?.forProperty("data")
            let canBeUpgraded = ab?.forProperty("canBeUpgraded")?.toBool() ?? false
            let hasMaxed = ab?.forProperty("hasMaxedInterval")?.toBool() ?? false
            let costNum = data?.forProperty("cost")?.toDouble() ?? 1
            dims.append(AutobuyerDimInfo(
                tier: t,
                isUnlocked: ab?.forProperty("isUnlocked")?.toBool() ?? false,
                isBought: ab?.forProperty("isBought")?.toBool() ?? false,
                canBeBought: (ab?.forProperty("canUnlockSlowVersion")?.toBool() ?? false) && !(ab?.forProperty("isBought")?.toBool() ?? false),
                isActive: ab?.forProperty("isActive")?.toBool() ?? false,
                interval: Int(data?.forProperty("interval")?.toInt32() ?? 500),
                cost: formatPlainNumber(costNum),
                canUpgrade: canBeUpgraded && !hasMaxed
                    && (context.evaluateScript("Currency.infinityPoints.gte(Autobuyer.antimatterDimension(\(t)).cost)")?.toBool() ?? false),
                canBeUpgraded: canBeUpgraded,
                hasMaxedInterval: hasMaxed,
                bulk: Int(ab?.forProperty("bulk")?.toInt32() ?? 1),
                hasMaxedBulk: ab?.forProperty("hasMaxedBulk")?.toBool() ?? false,
                canUpgradeBulk: hasMaxed && !(ab?.forProperty("hasMaxedBulk")?.toBool() ?? false)
                    && (context.evaluateScript("Currency.infinityPoints.gte(Autobuyer.antimatterDimension(\(t)).cost)")?.toBool() ?? false),
                mode: (ab?.forProperty("mode")?.toInt32() ?? 1) == 10 ? "BUY_10" : "BUY_SINGLE",
                antimatterCost: formatDecimal(GameDecimal(from: ab?.forProperty("antimatterCost")))
            ))
        }

        let ts = context.evaluateScript("Autobuyer.tickspeed")
        let tsData = ts?.forProperty("data")
        let tsCanBeUpgraded = ts?.forProperty("canBeUpgraded")?.toBool() ?? false
        let tsHasMaxed = ts?.forProperty("hasMaxedInterval")?.toBool() ?? false
        let tsCostNum = tsData?.forProperty("cost")?.toDouble() ?? 1
        let tsMode = tsData?.forProperty("mode")?.toInt32() ?? 0
        let tsIsUnlocked = ts?.forProperty("isUnlocked")?.toBool() ?? false
        let tsAutobuyer = AutobuyerSingleInfo(
            name: "Tickspeed",
            isUnlocked: tsIsUnlocked,
            isBought: ts?.forProperty("isBought")?.toBool() ?? false,
            canBeBought: (ts?.forProperty("canUnlockSlowVersion")?.toBool() ?? false) && !(ts?.forProperty("isBought")?.toBool() ?? false),
            isActive: ts?.forProperty("isActive")?.toBool() ?? false,
            interval: Int(tsData?.forProperty("interval")?.toInt32() ?? 500),
            cost: formatPlainNumber(tsCostNum),
            canUpgrade: tsCanBeUpgraded && !tsHasMaxed
                && (context.evaluateScript("Currency.infinityPoints.gte(Autobuyer.tickspeed.cost)")?.toBool() ?? false),
            canBeUpgraded: tsCanBeUpgraded,
            hasMaxedInterval: tsHasMaxed,
            antimatterCost: formatDecimal(GameDecimal(from: ts?.forProperty("antimatterCost"))),
            isBuyMax: tsMode == 100,  // AUTOBUYER_MODE.BUY_MAX = 100, BUY_SINGLE = 1
            isModeLocked: !tsIsUnlocked
        )

        // DimBoost autobuyer (unlocked by completing C10)
        let db = context.evaluateScript("Autobuyer.dimboost")
        let dbData = db?.forProperty("data")
        let dbCostNum = dbData?.forProperty("cost")?.toDouble() ?? 1
        let dbHasMaxed = db?.forProperty("hasMaxedInterval")?.toBool() ?? false
        let dbBuyMaxUnlocked = db?.forProperty("isBuyMaxUnlocked")?.toBool() ?? false
        let dbBuyMaxInterval = db?.forProperty("buyMaxInterval")?.toDouble() ?? 0
        let dbBulk = Int(db?.forProperty("bulk")?.toInt32() ?? 1)
        let dbAutobuyer = DimBoostAutobuyerInfo(
            isUnlocked: db?.forProperty("isUnlocked")?.toBool() ?? false,
            isActive: db?.forProperty("isActive")?.toBool() ?? false,
            hasMaxedInterval: dbHasMaxed,
            interval: Int(dbData?.forProperty("interval")?.toInt32() ?? 4000),
            cost: formatPlainNumber(dbCostNum),
            canUpgrade: (db?.forProperty("canBeUpgraded")?.toBool() ?? false) && !dbHasMaxed
                && (context.evaluateScript("Currency.infinityPoints.gte(Autobuyer.dimboost.cost)")?.toBool() ?? false),
            isBuyMaxUnlocked: dbBuyMaxUnlocked,
            buyMaxInterval: formatAutobuyerInterval(dbBuyMaxInterval),
            bulk: dbBulk,
            limitDimBoosts: dbData?.forProperty("limitDimBoosts")?.toBool() ?? false,
            maxDimBoosts: Int(dbData?.forProperty("maxDimBoosts")?.toInt32() ?? 1),
            limitUntilGalaxies: dbData?.forProperty("limitUntilGalaxies")?.toBool() ?? false,
            galaxies: Int(dbData?.forProperty("galaxies")?.toInt32() ?? 10)
        )

        // Galaxy autobuyer (unlocked by completing C11)
        let gal = context.evaluateScript("Autobuyer.galaxy")
        let galData = gal?.forProperty("data")
        let galCostNum = galData?.forProperty("cost")?.toDouble() ?? 1
        let galHasMaxed = gal?.forProperty("hasMaxedInterval")?.toBool() ?? false
        let galBuyMaxUnlocked = gal?.forProperty("isBuyMaxUnlocked")?.toBool() ?? false
        let galBuyMaxInterval = gal?.forProperty("buyMaxInterval")?.toDouble() ?? 0
        let galAutobuyer = GalaxyAutobuyerInfo(
            isUnlocked: gal?.forProperty("isUnlocked")?.toBool() ?? false,
            isActive: gal?.forProperty("isActive")?.toBool() ?? false,
            hasMaxedInterval: galHasMaxed,
            interval: Int(galData?.forProperty("interval")?.toInt32() ?? 4000),
            cost: formatPlainNumber(galCostNum),
            canUpgrade: (gal?.forProperty("canBeUpgraded")?.toBool() ?? false) && !galHasMaxed
                && (context.evaluateScript("Currency.infinityPoints.gte(Autobuyer.galaxy.cost)")?.toBool() ?? false),
            isBuyMaxUnlocked: galBuyMaxUnlocked,
            buyMaxInterval: formatAutobuyerInterval(galBuyMaxInterval),
            limitGalaxies: galData?.forProperty("limitGalaxies")?.toBool() ?? false,
            maxGalaxies: Int(galData?.forProperty("maxGalaxies")?.toInt32() ?? 10)
        )

        // Big Crunch autobuyer (unlocked by completing C12)
        let bc = context.evaluateScript("Autobuyer.bigCrunch")
        let bcData = bc?.forProperty("data")
        let bcCostNum = bcData?.forProperty("cost")?.toDouble() ?? 1
        let bcHasMaxed = bc?.forProperty("hasMaxedInterval")?.toBool() ?? false
        let bcAmount = GameDecimal(from: bcData?.forProperty("amount"))
        let bcMode = Int(bc?.forProperty("mode")?.toInt32() ?? 0)
        let bcHasAdditionalModes = bc?.forProperty("hasAdditionalModes")?.toBool() ?? false
        let bcTime = bc?.forProperty("time")?.toDouble() ?? 1
        let bcXHighest = GameDecimal(from: bc?.forProperty("xHighest"))
        let bcAutobuyer = BigCrunchAutobuyerInfo(
            isUnlocked: bc?.forProperty("isUnlocked")?.toBool() ?? false,
            isActive: bc?.forProperty("isActive")?.toBool() ?? false,
            hasMaxedInterval: bcHasMaxed,
            interval: Int(bcData?.forProperty("interval")?.toInt32() ?? 4000),
            cost: formatPlainNumber(bcCostNum),
            canUpgrade: (bc?.forProperty("canBeUpgraded")?.toBool() ?? false) && !bcHasMaxed
                && (context.evaluateScript("Currency.infinityPoints.gte(Autobuyer.bigCrunch.cost)")?.toBool() ?? false),
            mode: bcMode,
            hasAdditionalModes: bcHasAdditionalModes,
            amount: formatDecimal(bcAmount, places: 2),
            time: String(format: "%.1f", bcTime),
            xHighest: formatDecimal(bcXHighest, places: 2),
            isDynamic: bcData?.forProperty("increaseWithMult")?.toBool() ?? true
        )

        // Sacrifice autobuyer (unlocked by completing IC2)
        let sac = context.evaluateScript("Autobuyer.sacrifice")
        let sacData = sac?.forProperty("data")
        let sacMultVal = GameDecimal(from: sacData?.forProperty("multiplier"))
        let sacAutobuyer = SacrificeAutobuyerInfo(
            isUnlocked: sac?.forProperty("isUnlocked")?.toBool() ?? false,
            isActive: sac?.forProperty("isActive")?.toBool() ?? false,
            multiplier: formatDecimal(sacMultVal, places: 2),
            isAutomatic: context.evaluateScript("Achievement(118).canBeApplied")?.toBool() ?? false
        )

        // IP Multiplier autobuyer (unlocked at 1 eternity)
        let ipMultAutobuyer: IPMultAutobuyerInfo
        if let ipMultAB = context.evaluateScript("Autobuyer.ipMult"), !ipMultAB.isUndefined {
            let ipMultUnlocked = ipMultAB.forProperty("isUnlocked")?.toBool() ?? false
            ipMultAutobuyer = IPMultAutobuyerInfo(
                isUnlocked: ipMultUnlocked,
                isActive: ipMultUnlocked ? (ipMultAB.forProperty("isActive")?.toBool() ?? false) : false
            )
        } else {
            ipMultAutobuyer = IPMultAutobuyerInfo(isUnlocked: false, isActive: false)
        }

        // Eternity autobuyer (unlocked at 100 eternities)
        let etAutobuyer: EternityAutobuyerInfo
        if let etAB = context.evaluateScript("Autobuyer.eternity"), !etAB.isUndefined,
           etAB.forProperty("isUnlocked")?.toBool() == true {
            let mode = Int(etAB.forProperty("mode")?.toInt32() ?? 0)
            let hasAdditional = etAB.forProperty("hasAdditionalModes")?.toBool() ?? false
            let amountStr: String
            switch mode {
            case 0: // AMOUNT
                let val = GameDecimal(from: etAB.forProperty("amount"))
                amountStr = formatDecimal(val, places: 2)
            case 1: // TIME
                let val = etAB.forProperty("time")?.toDouble() ?? 1
                amountStr = String(format: "%.1f", val)
            case 2: // X_HIGHEST
                let val = GameDecimal(from: etAB.forProperty("xHighest"))
                amountStr = formatDecimal(val, places: 2)
            default:
                amountStr = "1"
            }
            etAutobuyer = EternityAutobuyerInfo(
                isUnlocked: true,
                isActive: etAB.forProperty("isActive")?.toBool() ?? false,
                mode: mode,
                amount: amountStr,
                isDynamic: etAB.forProperty("increaseWithMult")?.toBool() ?? true,
                hasAdditionalModes: hasAdditional
            )
        } else {
            etAutobuyer = .empty
        }

        // Reality autobuyer (unlocked by RealityUpgrade(25))
        let realityAutobuyer: RealityAutobuyerInfo
        if let rAB = context.evaluateScript("Autobuyer.reality"), !rAB.isUndefined,
           rAB.forProperty("isUnlocked")?.toBool() == true {
            let mode = Int(rAB.forProperty("mode")?.toInt32() ?? 0)
            let rmStr = formatDecimal(GameDecimal(from: rAB.forProperty("rm")), places: 2)
            let shardStr = formatDecimal(GameDecimal(from: rAB.forProperty("shard")), places: 2)
            let hasRelic = context.evaluateScript(
                "typeof TeresaUnlocks !== 'undefined' && TeresaUnlocks.effarig && TeresaUnlocks.effarig.canBeApplied"
            )?.toBool() ?? false
            let capRaw = context.evaluateScript("Glyphs.levelCap")?.toDouble() ?? 999_999
            let levelCap = capRaw.isFinite && capRaw >= 0 && capRaw < Double(Int32.max) ? Int(capRaw) : 999_999
            realityAutobuyer = RealityAutobuyerInfo(
                isUnlocked: true,
                isActive: rAB.forProperty("isActive")?.toBool() ?? false,
                mode: mode,
                rm: rmStr,
                glyph: Int(rAB.forProperty("glyph")?.toInt32() ?? 1),
                time: rAB.forProperty("time")?.toDouble() ?? 0,
                shard: shardStr,
                hasRelicMode: hasRelic,
                glyphLevelCap: levelCap
            )
        } else {
            realityAutobuyer = .empty
        }

        // Replicanti Galaxy autobuyer (unlocked at 3 eternities)
        let replGalAutobuyer: ReplicantiGalaxyAutobuyerInfo
        if let rgAB = context.evaluateScript("Autobuyer.replicantiGalaxy"), !rgAB.isUndefined,
           rgAB.forProperty("isUnlocked")?.toBool() == true {
            replGalAutobuyer = ReplicantiGalaxyAutobuyerInfo(
                isUnlocked: true,
                isActive: rgAB.forProperty("isActive")?.toBool() ?? false,
                isEnabled: rgAB.forProperty("isEnabled")?.toBool() ?? true
            )
        } else {
            replGalAutobuyer = .empty
        }

        // Replicanti Upgrade autobuyers (unlocked at 50/60/80 eternities)
        let replUpgNames = ["Replicanti Chance", "Replicanti Interval", "Replicanti Max Galaxies"]
        var replUpgEntries: [ReplicantiUpgradeAutobuyerEntry] = []
        var anyReplUpgUnlocked = false
        for i in 1...3 {
            if let ab = context.evaluateScript("Autobuyer.replicantiUpgrade(\(i))"), !ab.isUndefined {
                let unlocked = ab.forProperty("isUnlocked")?.toBool() ?? false
                if unlocked { anyReplUpgUnlocked = true }
                replUpgEntries.append(ReplicantiUpgradeAutobuyerEntry(
                    id: i,
                    name: replUpgNames[i - 1],
                    isUnlocked: unlocked,
                    isActive: ab.forProperty("isActive")?.toBool() ?? false
                ))
            }
        }
        let replUpgGroupActive = jsPlayer.forProperty("auto")?.forProperty("replicantiUpgrades")?.forProperty("isActive")?.toBool() ?? true
        let replUpgInterval: String
        if anyReplUpgUnlocked,
           let firstAB = context.evaluateScript("Autobuyer.replicantiUpgrade(1)"),
           !firstAB.isUndefined {
            let intervalMs = firstAB.forProperty("interval")?.toDouble() ?? 1000
            replUpgInterval = "Current interval: \(String(format: "%.2f", intervalMs / 1000)) seconds"
        } else {
            replUpgInterval = ""
        }
        let replUpgradesInfo = ReplicantiUpgradeAutobuyersInfo(
            isAnyUnlocked: anyReplUpgUnlocked,
            isGroupActive: replUpgGroupActive,
            intervalText: replUpgInterval,
            entries: replUpgEntries.filter { $0.isUnlocked }
        )

        // Check if every unlocked autobuyer has isActive == false
        let allDisabled = context.evaluateScript(
            "Autobuyers.unlocked.every(function(a) { return !a.isActive; })"
        )?.toBool() ?? false

        // Time Dimension autobuyers (unlocked by RealityUpgrade(13))
        let tdABUnlocked = jsTDAutobuyerRefs[0].forProperty("isUnlocked")?.toBool() ?? false
        var tdABTiers: [TDAutobuyerTierInfo] = []
        if tdABUnlocked {
            for t in 1...8 {
                let active = jsTDAutobuyerRefs[t - 1].forProperty("isActive")?.toBool() ?? false
                tdABTiers.append(TDAutobuyerTierInfo(tier: t, isActive: active))
            }
        }
        let tdAutobuyersInfo = TDAutobuyersInfo(isUnlocked: tdABUnlocked, tiers: tdABTiers)

        // Dilation upgrade autobuyers (unlocked by Perk.autobuyerDilation)
        let dilABUnlocked = context.evaluateScript("Perk.autobuyerDilation.isEffectActive")?.toBool() ?? false
        var dilABEntries: [DilationAutobuyerEntry] = []
        if dilABUnlocked {
            let names = ["DT Multiplier", "Galaxy Threshold", "TP Multiplier"]
            for i in 1...3 {
                let active = context.evaluateScript("Autobuyer.dilationUpgrade(\(i)).isActive")?.toBool() ?? false
                dilABEntries.append(DilationAutobuyerEntry(id: i, name: names[i - 1], isActive: active))
            }
        }
        let dilAutobuyersInfo = DilationAutobuyersInfo(isUnlocked: dilABUnlocked, upgrades: dilABEntries)

        // EP Multiplier autobuyer (unlocked by RealityUpgrade(13))
        let epMultABUnlocked = context.evaluateScript("Autobuyer.epMult.isUnlocked")?.toBool() ?? false
        let epMultABActive = epMultABUnlocked ? (context.evaluateScript("Autobuyer.epMult.isActive")?.toBool() ?? false) : false
        let epMultABInfo = EPMultAutobuyerInfo(isUnlocked: epMultABUnlocked, isActive: epMultABActive)

        // Time Theorem autobuyer (unlocked by Perk.ttBuySingle)
        let ttABUnlocked = context.evaluateScript("Autobuyer.timeTheorem.isUnlocked")?.toBool() ?? false
        let ttABActive = ttABUnlocked ? (context.evaluateScript("Autobuyer.timeTheorem.isActive")?.toBool() ?? false) : false
        let ttABInfo = TTAutobuyerInfo(isUnlocked: ttABUnlocked, isActive: ttABActive)

        // Reality Upgrade rebuyable autobuyers (Ra V pet lv 1). One shared
        // unlock flag drives all 5.
        let ruAutoJSON = context.evaluateScript("""
            (function() {
                if (typeof Autobuyer === 'undefined' || !Autobuyer.realityUpgrade) return JSON.stringify({u:false,r:[]});
                var unlocked = false;
                try { unlocked = !!Autobuyer.realityUpgrade(1).isUnlocked; } catch(e) {}
                var arr = [];
                for (var i = 1; i <= 5; i++) {
                    try {
                        var a = Autobuyer.realityUpgrade(i);
                        arr.push({ id: i, name: RealityUpgrade(i).config.name, active: !!a.isActive });
                    } catch(e) {}
                }
                return JSON.stringify({ u: unlocked, r: arr });
            })()
            """)?.toString() ?? "{}"
        var ruAutobuyersInfo = RealityUpgradeAutobuyersInfo.empty
        if let d = ruAutoJSON.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            let unlocked = (obj["u"] as? Bool) ?? false
            let rows = (obj["r"] as? [[String: Any]]) ?? []
            let entries: [RealityUpgradeAutobuyerEntry] = rows.compactMap { r in
                guard let id = r["id"] as? Int else { return nil }
                return RealityUpgradeAutobuyerEntry(
                    id: id,
                    name: (r["name"] as? String) ?? "",
                    isActive: (r["active"] as? Bool) ?? false
                )
            }
            ruAutobuyersInfo = RealityUpgradeAutobuyersInfo(isUnlocked: unlocked, upgrades: entries)
        }

        // Imaginary Upgrade autobuyers (10 rebuyable imaginary upgrades,
        // gated on ImaginaryUpgrade(20).canBeApplied — Vacuum Acceleration).
        // Per-row toggle state lives in `player.auto.imaginaryUpgrades.all[id-1]`.
        let imAutoJSON = context.evaluateScript("""
            (function() {
                if (typeof Autobuyer === 'undefined' || !Autobuyer.imaginaryUpgrade) return JSON.stringify({u:false,r:[]});
                var unlocked = false;
                try { unlocked = !!(ImaginaryUpgrade(20) && ImaginaryUpgrade(20).canBeApplied); } catch(e) {}
                var arr = [];
                for (var i = 1; i <= 10; i++) {
                    try {
                        var a = Autobuyer.imaginaryUpgrade(i);
                        arr.push({ id: i, name: a.name || '', active: !!a.isActive });
                    } catch(e) {}
                }
                return JSON.stringify({ u: unlocked, r: arr });
            })()
            """)?.toString() ?? "{}"
        var imAutobuyersInfo = ImaginaryUpgradeAutobuyersInfo.empty
        if let d = imAutoJSON.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            let unlocked = (obj["u"] as? Bool) ?? false
            let rows = (obj["r"] as? [[String: Any]]) ?? []
            let entries: [ImaginaryUpgradeAutobuyerEntry] = rows.compactMap { r in
                guard let id = r["id"] as? Int else { return nil }
                return ImaginaryUpgradeAutobuyerEntry(
                    id: id,
                    name: (r["name"] as? String) ?? "",
                    isActive: (r["active"] as? Bool) ?? false
                )
            }
            imAutobuyersInfo = ImaginaryUpgradeAutobuyersInfo(isUnlocked: unlocked, upgrades: entries)
        }

        // Black Hole power upgrade autobuyers (Ra Enslaved pet lv 1). IDs
        // 1-3 target BH1 (interval/power/duration), 4-6 target BH2.
        let bhAutoJSON = context.evaluateScript("""
            (function() {
                if (typeof Autobuyer === 'undefined' || !Autobuyer.blackHolePower) return JSON.stringify({any:false,r:[]});
                var any = false;
                var arr = [];
                var types = ['interval','power','duration'];
                for (var i = 1; i <= 6; i++) {
                    try {
                        var a = Autobuyer.blackHolePower(i);
                        var bh = i <= 3 ? 1 : 2;
                        var t = types[(i - 1) % 3];
                        var u = !!a.isUnlocked;
                        if (u) any = true;
                        arr.push({ id: i, bh: bh, type: t,
                            name: 'BH' + bh + ' ' + t.charAt(0).toUpperCase() + t.slice(1),
                            unlocked: u, active: u && !!a.isActive });
                    } catch(e) {}
                }
                return JSON.stringify({ any: any, r: arr });
            })()
            """)?.toString() ?? "{}"
        var bhAutobuyersInfo = BlackHolePowerAutobuyersInfo.empty
        if let d = bhAutoJSON.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            let any = (obj["any"] as? Bool) ?? false
            let rows = (obj["r"] as? [[String: Any]]) ?? []
            let entries: [BlackHolePowerAutobuyerEntry] = rows.compactMap { r in
                guard let id = r["id"] as? Int else { return nil }
                return BlackHolePowerAutobuyerEntry(
                    id: id,
                    bhId: (r["bh"] as? Int) ?? 1,
                    type: (r["type"] as? String) ?? "",
                    name: (r["name"] as? String) ?? "",
                    isUnlocked: (r["unlocked"] as? Bool) ?? false,
                    isActive: (r["active"] as? Bool) ?? false
                )
            }
            bhAutobuyersInfo = BlackHolePowerAutobuyersInfo(anyUnlocked: any, upgrades: entries)
        }

        state.autobuyers = AutobuyersState(
            isUnlocked: abUnlocked,
            allOn: allOn,
            allAutobuyersDisabled: allDisabled,
            dimensions: dims,
            tickspeed: tsAutobuyer,
            sacrifice: sacAutobuyer,
            dimBoost: dbAutobuyer,
            galaxy: galAutobuyer,
            bigCrunch: bcAutobuyer,
            ipMult: ipMultAutobuyer,
            eternityAutobuyer: etAutobuyer,
            reality: realityAutobuyer,
            replicantiGalaxy: replGalAutobuyer,
            replicantiUpgrades: replUpgradesInfo,
            timeDimensions: tdAutobuyersInfo,
            dilationUpgrades: dilAutobuyersInfo,
            epMult: epMultABInfo,
            timeTheorem: ttABInfo,
            realityUpgradeRebuyables: ruAutobuyersInfo,
            imaginaryUpgradeRebuyables: imAutobuyersInfo,
            blackHolePower: bhAutobuyersInfo
        )

        // Refresh ID autobuyer unlock/active state so the autobuyers tab
        // sees changes without requiring a visit to the Infinity Dimensions tab.
        var updatedDims = state.infinityDimensions.dimensions
        var anyUnlocked = false
        for i in 0..<updatedDims.count {
            let idAB = jsIDAutobuyerRefs[i]
            let unlocked = idAB.forProperty("isUnlocked")?.toBool() ?? false
            let active = idAB.forProperty("isActive")?.toBool() ?? false
            if unlocked { anyUnlocked = true }
            if updatedDims[i].isAutobuyerUnlocked != unlocked || updatedDims[i].isAutobuyerActive != active {
                updatedDims[i] = InfinityDimState(
                    tier: updatedDims[i].tier,
                    isUnlocked: updatedDims[i].isUnlocked,
                    canUnlock: updatedDims[i].canUnlock,
                    amount: updatedDims[i].amount,
                    multiplier: updatedDims[i].multiplier,
                    cost: updatedDims[i].cost,
                    purchases: updatedDims[i].purchases,
                    rateOfChange: updatedDims[i].rateOfChange,
                    isAvailableForPurchase: updatedDims[i].isAvailableForPurchase,
                    isAffordable: updatedDims[i].isAffordable,
                    isCapped: updatedDims[i].isCapped,
                    amRequirement: updatedDims[i].amRequirement,
                    amRequirementReached: updatedDims[i].amRequirementReached,
                    hasPrevTier: updatedDims[i].hasPrevTier,
                    isAutobuyerUnlocked: unlocked,
                    isAutobuyerActive: active
                )
            }
        }
        state.infinityDimensions = InfinityDimsInfo(
            isUnlocked: state.infinityDimensions.isUnlocked,
            eternityReached: state.infinityDimensions.eternityReached,
            infinityPower: state.infinityDimensions.infinityPower,
            powerMultiplier: state.infinityDimensions.powerMultiplier,
            conversionRate: state.infinityDimensions.conversionRate,
            powerPerSecond: state.infinityDimensions.powerPerSecond,
            totalDimCap: state.infinityDimensions.totalDimCap,
            isAnyAutobuyerUnlocked: anyUnlocked,
            isEC8Running: state.infinityDimensions.isEC8Running,
            dimensions: updatedDims
        )
    }

    // Statistics general subtab polling moved to GameEngine+Statistics.swift
    // (`pollStatisticsGeneral`) — single bulk-JSON eval through
    // `statistics-helper.js`. Replaces ~125 lines of inline forProperty +
    // evaluateScript and adds the new fields (news / secret achievements /
    // paperclips / full-game completions / projected banked / doom).

    private func pollChallengeRecords(_ state: inout GameState) {
        let normalBest = jsPlayer.forProperty("challenge")?.forProperty("normal")?.forProperty("bestTimes")
        let infBest = jsPlayer.forProperty("challenge")?.forProperty("infinity")?.forProperty("bestTimes")

        // Normal Challenges: indices 0–10 → C2–C12
        var normalTimes: [String] = []
        var normalSumMs: Double = 0
        var allNormalCompleted = true
        for i in 0..<11 {
            let t = normalBest?.atIndex(i)?.toDouble() ?? Double.greatestFiniteMagnitude
            if t > 1e300 {
                normalTimes.append("Not completed")
                allNormalCompleted = false
            } else {
                let formatted = context.evaluateScript("TimeSpan.fromMilliseconds(\(t)).toStringShort()")?.toString() ?? "\(t) ms"
                normalTimes.append(formatted)
                normalSumMs += t
            }
        }
        let normalSum: String? = allNormalCompleted
            ? context.evaluateScript("TimeSpan.fromMilliseconds(\(normalSumMs)).toStringShort()")?.toString()
            : nil

        // Infinity Challenges: indices 0–7 → IC1–IC8
        let icCompleted = jsPlayerProgress.invokeMethod("infinityChallengeCompleted", withArguments: [])?.toBool() ?? false
        let etUnlocked = jsPlayerProgress.invokeMethod("eternityUnlocked", withArguments: [])?.toBool() ?? false
        let showIC = icCompleted || etUnlocked

        var infinityTimes: [String] = []
        var infSumMs: Double = 0
        var allInfCompleted = true
        for i in 0..<8 {
            let t = infBest?.atIndex(i)?.toDouble() ?? Double.greatestFiniteMagnitude
            if t > 1e300 {
                infinityTimes.append("Not completed")
                allInfCompleted = false
            } else {
                let formatted = context.evaluateScript("TimeSpan.fromMilliseconds(\(t)).toStringShort()")?.toString() ?? "\(t) ms"
                infinityTimes.append(formatted)
                infSumMs += t
            }
        }
        let infinitySum: String? = allInfCompleted
            ? context.evaluateScript("TimeSpan.fromMilliseconds(\(infSumMs)).toStringShort()")?.toString()
            : nil

        state.challengeRecords = ChallengeRecordsState(
            normalTimes: normalTimes,
            normalSum: normalSum,
            showInfinityChallenges: showIC,
            infinityTimes: infinityTimes,
            infinitySum: infinitySum
        )
    }

    private func pollPastPrestigeRuns(_ state: inout GameState) {
        let modeRaw = Int(jsPlayer.forProperty("options")?.forProperty("statTabResources")?.toInt32() ?? 0)
        let displayMode = PrestigeRunDisplayMode(rawValue: modeRaw) ?? .absoluteGain

        let infUnlocked = jsPlayerProgress.invokeMethod("infinityUnlocked", withArguments: [])?.toBool() ?? false
        let etUnlocked = jsPlayerProgress.invokeMethod("eternityUnlocked", withArguments: [])?.toBool() ?? false
        let realUnlocked = jsPlayerProgress.invokeMethod("realityUnlocked", withArguments: [])?.toBool() ?? false
        let dilationUnlocked = jsPlayerProgress.invokeMethod("dilationUnlocked", withArguments: [])?.toBool() ?? false
        let hasRealTime = jsPlayerProgress.invokeMethod("seenAlteredSpeed", withArguments: [])?.toBool() ?? false
        let canRelicShards = context.evaluateScript("TeresaUnlocks.effarig.canBeApplied")?.toBool() ?? false
        // Web's `hasIM` flag — when true, the Reality table swaps its RM
        // column for "iM Cap" (run[7]) and skips the RM rate. Note that
        // `MachineHandler.currentIMCap` is a plain JS Number (multiplies
        // `player.reality.iMCap` by an `effectOrDefault(1)`), NOT a
        // break_infinity Decimal — use `> 0` not `.gt(0)`.
        let hasIMCap = (context.evaluateScript("MachineHandler.currentIMCap > 0")?.toBool()) ?? false

        let records = jsPlayer.forProperty("records")

        // Swift renders Double.nan/.infinity as "nan"/"inf" which are
        // undefined identifiers in JS; produce a 0-Decimal fallback string
        // for those values so JS-side eval doesn't ReferenceError.
        func jsDecimalScript(mantissa: Double, exponent: Int) -> String {
            guard mantissa.isFinite else { return "new Decimal(0)" }
            return "Decimal.fromMantissaExponent(\(mantissa),\(exponent))"
        }

        // Decimal-safe rate formatter that mirrors web's `rateText`. Always
        // takes the prestige's REAL time (run[1]) as the denominator —
        // game-speed-altered runs can have near-zero game time while real
        // time is significant. Returns "X.YZ {unit}/min" when >= 1/min,
        // else "X.YZ {unit}/hr". Uses JS-side Decimal division so endgame
        // values (e.g. 1e500 EP) don't overflow Double.
        func rateString(amountScript: String, realTimeMs: Double, unit: String) -> String {
            let safeReal = (realTimeMs.isFinite && realTimeMs > 0) ? realTimeMs : 1.0
            let timeMs = max(safeReal, 1.0)  // clamp like web (ratePerMinute treats <= 0 as 0)
            // Per-minute = amount / (timeMs / 60000) = amount * 60000 / timeMs.
            let rpmScript = "(\(amountScript)).times(60000).dividedBy(\(timeMs))"
            let rpm = GameDecimal(from: context.evaluateScript(rpmScript))
            let isLT1 = context.evaluateScript("(\(rpmScript)).lt(1)")?.toBool() ?? false
            if isLT1 {
                let rpmHour = GameDecimal(from: context.evaluateScript("(\(rpmScript)).times(60)"))
                return formatDecimal(rpmHour, places: 2) + " " + unit + "/hr"
            }
            return formatDecimal(rpm, places: 2) + " " + unit + "/min"
        }

        func buildSection(key: String, name: String, plural: String, currencyLabel: String,
                          isUnlocked: Bool, countIsDecimal: Bool,
                          hasTachyon: Bool, hasGlyph: Bool, hasRelic: Bool,
                          hasIMCapCol: Bool) -> PrestigeRunsSection {
            guard isUnlocked else {
                return PrestigeRunsSection(name: name, plural: plural, currencyLabel: currencyLabel,
                                           isUnlocked: false, runs: [], hasChallenge: false,
                                           hasRealTime: false, hasTachyonParticles: false,
                                           hasGlyphLevel: false, hasRelicShards: false,
                                           hasIMCap: false)
            }

            let arr = records?.forProperty(key)
            var rows: [RecentRunRow] = []
            var hasChallenge = false

            // Accumulators for average
            var validCount = 0
            var totalGameTime: Double = 0
            var totalRealTime: Double = 0
            var totalCurrencyScript = "new Decimal(0)"
            var totalPrestigeScript = countIsDecimal ? "new Decimal(0)" : ""
            var totalPrestigeNum: Double = 0
            var totalTachyonScript = "new Decimal(0)"
            var totalGlyphLevelNum: Double = 0
            var totalRelicShardsScript = "new Decimal(0)"

            let labels = ["Last", "2 ago", "3 ago", "4 ago", "5 ago",
                           "6 ago", "7 ago", "8 ago", "9 ago", "10 ago"]

            for i in 0..<10 {
                let run = arr?.atIndex(i)
                let gameTimeMs = run?.atIndex(0)?.toDouble() ?? Double.greatestFiniteMagnitude
                let isEmpty = gameTimeMs > 1e300

                if isEmpty {
                    rows.append(RecentRunRow(
                        id: i, label: labels[i], isEmpty: true,
                        gameTime: "-", realTime: "-",
                        currencyGain: "-", prestigeCount: "-",
                        currencyRate: "-", prestigeCountRate: "-",
                        challenge: "",
                        tachyonParticles: "", glyphLevel: "",
                        relicShards: "", relicShardRate: ""
                    ))
                    continue
                }

                validCount += 1
                totalGameTime += gameTimeMs
                let realTimeMs = run?.atIndex(1)?.toDouble() ?? gameTimeMs
                totalRealTime += realTimeMs

                let gameTimeStr = context.evaluateScript("TimeSpan.fromMilliseconds(\(gameTimeMs)).toStringShort()")?.toString() ?? "-"
                let realTimeStr = hasRealTime
                    ? (context.evaluateScript("TimeSpan.fromMilliseconds(\(realTimeMs)).toStringShort()")?.toString() ?? "-")
                    : ""

                // Currency gain (index 2) — always a Decimal. When `hasIMCapCol`,
                // web swaps the display to run[7] (projected iM cap) and shows
                // "N/A" for the rate — see web's `prestigeCurrencyGain` /
                // `prestigeCurrencyRate` in PastPrestigeRunsContainer.vue.
                //
                // NOTE: run[7] is a plain JS Number (MachineHandler.projectedIMCap
                // is `baseIMCap * effectOrDefault(1)` — both numbers), not a
                // break_infinity Decimal. Read via toDouble + `format()` JS-side
                // and accumulate as `new Decimal(num)`.
                let currencyStr: String
                let currencyAddendScript: String
                if hasIMCapCol {
                    let capNum = run?.atIndex(7)?.toDouble() ?? 0
                    currencyStr = (context.evaluateScript("format(\(capNum.isFinite ? capNum : 0), 2, 2)")?.toString() ?? "0") + " iM"
                    currencyAddendScript = "new Decimal(\(capNum.isFinite ? capNum : 0))"
                } else {
                    let currencyDec = GameDecimal(from: run?.atIndex(2))
                    currencyStr = formatDecimal(currencyDec, places: 2) + " " + currencyLabel
                    currencyAddendScript = jsDecimalScript(mantissa: currencyDec.mantissa, exponent: currencyDec.exponent)
                }
                totalCurrencyScript = "(\(totalCurrencyScript)).plus(\(currencyAddendScript))"

                // Prestige count (index 3)
                let prestigeStr: String
                if countIsDecimal {
                    let countDec = GameDecimal(from: run?.atIndex(3))
                    prestigeStr = formatDecimal(countDec, places: 2)
                    let addend = jsDecimalScript(mantissa: countDec.mantissa, exponent: countDec.exponent)
                    totalPrestigeScript = "(\(totalPrestigeScript)).plus(\(addend))"
                } else {
                    let countNum = run?.atIndex(3)?.toDouble() ?? 0
                    prestigeStr = formatDecimal(GameDecimal(from: run?.atIndex(3)), places: 2)
                    totalPrestigeNum += countNum
                }

                // Rates — use REAL time (run[1]) per web's `rateText`. Decimal
                // arithmetic so endgame values don't overflow Double. iM-cap
                // mode returns "N/A" because the cap isn't a per-minute value.
                let currencyRateStr = hasIMCapCol ? "N/A" : rateString(
                    amountScript: currencyAddendScript,
                    realTimeMs: realTimeMs, unit: currencyLabel
                )

                let prestigeCountRateStr: String
                if countIsDecimal {
                    let countDec = GameDecimal(from: run?.atIndex(3))
                    let addend = jsDecimalScript(mantissa: countDec.mantissa, exponent: countDec.exponent)
                    prestigeCountRateStr = rateString(amountScript: addend, realTimeMs: realTimeMs, unit: "")
                } else {
                    let countNum = run?.atIndex(3)?.toDouble() ?? 0
                    let addend = "new Decimal(\(countNum))"
                    prestigeCountRateStr = rateString(amountScript: addend, realTimeMs: realTimeMs, unit: "")
                }

                // Challenge (index 4)
                let challengeStr = run?.atIndex(4)?.toString() ?? ""
                if !challengeStr.isEmpty { hasChallenge = true }

                // Extras
                var tachyonStr = ""
                if hasTachyon {
                    let tp = GameDecimal(from: run?.atIndex(5))
                    tachyonStr = formatDecimal(tp, places: 2)
                    let addend = jsDecimalScript(mantissa: tp.mantissa, exponent: tp.exponent)
                    totalTachyonScript = "(\(totalTachyonScript)).plus(\(addend))"
                }

                var glyphLevelStr = ""
                if hasGlyph {
                    let glvl = run?.atIndex(5)?.toDouble() ?? 0
                    glyphLevelStr = context.evaluateScript("formatInt(\(glvl))")?.toString() ?? "0"
                    totalGlyphLevelNum += glvl
                }

                var relicShardsStr = ""
                var relicShardRateStr = ""
                if hasRelic {
                    // Reality's relic shards are stored as a plain JS Number
                    // (game.js:256 `shards * ampFactor`), not a Decimal. Read
                    // via toDouble and route through `format()` JS-side so the
                    // formatting matches web exactly.
                    let rsNum = run?.atIndex(6)?.toDouble() ?? 0
                    relicShardsStr = context.evaluateScript("format(\(rsNum), 2)")?.toString() ?? "0"
                    let addend = "new Decimal(\(rsNum.isFinite ? rsNum : 0))"
                    totalRelicShardsScript = "(\(totalRelicShardsScript)).plus(\(addend))"
                    relicShardRateStr = rateString(amountScript: addend, realTimeMs: realTimeMs, unit: "Relic Shards")
                }

                rows.append(RecentRunRow(
                    id: i, label: labels[i], isEmpty: false,
                    gameTime: gameTimeStr, realTime: realTimeStr,
                    currencyGain: currencyStr,
                    prestigeCount: prestigeStr,
                    currencyRate: currencyRateStr,
                    prestigeCountRate: prestigeCountRateStr,
                    challenge: challengeStr,
                    tachyonParticles: tachyonStr,
                    glyphLevel: glyphLevelStr,
                    relicShards: relicShardsStr,
                    relicShardRate: relicShardRateStr
                ))
            }

            // Average row
            if validCount > 0 {
                let avgTime = totalGameTime / Double(validCount)
                let avgRealTime = totalRealTime / Double(validCount)
                let avgTimeStr = context.evaluateScript("TimeSpan.fromMilliseconds(\(avgTime)).toStringShort()")?.toString() ?? "-"
                let avgRealTimeStr = hasRealTime
                    ? (context.evaluateScript("TimeSpan.fromMilliseconds(\(avgRealTime)).toStringShort()")?.toString() ?? "-")
                    : ""

                let avgCurrencyScript = "(\(totalCurrencyScript)).dividedBy(\(validCount))"
                let avgCurrencyDec = GameDecimal(from: context.evaluateScript(avgCurrencyScript))
                // Currency unit suffix differs from the column header — "iM"
                // for the iM-cap case, otherwise the layer's currency label.
                let avgCurrencyUnit = hasIMCapCol ? "iM" : currencyLabel
                let avgCurrencyStr = formatDecimal(avgCurrencyDec, places: 2) + " " + avgCurrencyUnit

                let avgPrestigeStr: String
                let avgPrestigeScript: String
                if countIsDecimal {
                    avgPrestigeScript = "(\(totalPrestigeScript)).dividedBy(\(validCount))"
                    let avgP = GameDecimal(from: context.evaluateScript(avgPrestigeScript))
                    avgPrestigeStr = formatDecimal(avgP, places: 2)
                } else {
                    let avgPrestigeNum = totalPrestigeNum / Double(validCount)
                    avgPrestigeScript = "new Decimal(\(avgPrestigeNum))"
                    avgPrestigeStr = formatDecimal(GameDecimal(double: avgPrestigeNum), places: 2)
                }

                let avgCurrencyRate = hasIMCapCol ? "N/A" : rateString(
                    amountScript: avgCurrencyScript,
                    realTimeMs: avgRealTime, unit: currencyLabel
                )
                let avgPrestigeRate = rateString(
                    amountScript: avgPrestigeScript,
                    realTimeMs: avgRealTime, unit: ""
                )

                var avgTachyon = ""
                if hasTachyon {
                    let t = GameDecimal(from: context.evaluateScript("(\(totalTachyonScript)).dividedBy(\(validCount))"))
                    avgTachyon = formatDecimal(t, places: 2)
                }
                var avgGlyph = ""
                if hasGlyph {
                    let g = totalGlyphLevelNum / Double(validCount)
                    avgGlyph = context.evaluateScript("formatInt(Math.round(\(g)))")?.toString() ?? "0"
                }
                var avgRelic = ""
                var avgRelicRate = ""
                if hasRelic {
                    let avgRelicScript = "(\(totalRelicShardsScript)).dividedBy(\(validCount))"
                    let r = GameDecimal(from: context.evaluateScript(avgRelicScript))
                    avgRelic = formatDecimal(r, places: 2)
                    avgRelicRate = rateString(amountScript: avgRelicScript,
                                              realTimeMs: avgRealTime, unit: "Relic Shards")
                }

                rows.append(RecentRunRow(
                    id: 10, label: "Average", isEmpty: false,
                    gameTime: avgTimeStr, realTime: avgRealTimeStr,
                    currencyGain: avgCurrencyStr,
                    prestigeCount: avgPrestigeStr,
                    currencyRate: avgCurrencyRate,
                    prestigeCountRate: avgPrestigeRate,
                    challenge: "",
                    tachyonParticles: avgTachyon,
                    glyphLevel: avgGlyph,
                    relicShards: avgRelic,
                    relicShardRate: avgRelicRate
                ))
            }

            return PrestigeRunsSection(name: name, plural: plural, currencyLabel: currencyLabel,
                                       isUnlocked: true, runs: rows, hasChallenge: hasChallenge,
                                       hasRealTime: hasRealTime,
                                       hasTachyonParticles: hasTachyon,
                                       hasGlyphLevel: hasGlyph,
                                       hasRelicShards: hasRelic,
                                       hasIMCap: hasIMCapCol)
        }

        let infinitySection = buildSection(
            key: "recentInfinities", name: "Infinity", plural: "Infinities",
            currencyLabel: "IP", isUnlocked: infUnlocked, countIsDecimal: true,
            hasTachyon: false, hasGlyph: false, hasRelic: false, hasIMCapCol: false)
        let eternitySection = buildSection(
            key: "recentEternities", name: "Eternity", plural: "Eternities",
            currencyLabel: "EP", isUnlocked: etUnlocked, countIsDecimal: true,
            hasTachyon: dilationUnlocked, hasGlyph: false, hasRelic: false, hasIMCapCol: false)
        let realitySection = buildSection(
            key: "recentRealities", name: "Reality", plural: "Realities",
            currencyLabel: hasIMCap ? "iM Cap" : "RM",
            isUnlocked: realUnlocked, countIsDecimal: false,
            hasTachyon: false, hasGlyph: true, hasRelic: canRelicShards,
            hasIMCapCol: hasIMCap)

        state.pastPrestigeRuns = PastPrestigeRunsState(
            sections: [infinitySection, eternitySection, realitySection],
            displayMode: displayMode
        )
    }

    private func pollNormalChallenges(_ state: inout GameState) {
        let currentId = Int(jsPlayer.forProperty("challenge")?.forProperty("normal")?.forProperty("current")?.toInt32() ?? 0)
        let isAnyRunning = currentId != 0

        // Current infinity count for locked challenge display (X/16).
        // `player.infinities` is a break_infinity Decimal that can grow past
        // Int.max post-Reality — clamp before casting to avoid a fatal
        // "Double > Int.max" trap. The UI only uses this for the locked-card
        // "X/16" label, so saturating at Int.max is harmless (the challenge
        // is unlocked well before then).
        let infRaw = GameDecimal(from: jsPlayer.forProperty("infinities")).toDouble
        let infinities: Int
        if !infRaw.isFinite || infRaw >= Double(Int.max) {
            infinities = Int.max
        } else if infRaw <= Double(Int.min) {
            infinities = 0
        } else {
            infinities = Int(infRaw)
        }

        // Matches `Enslaved.BROKEN_CHALLENGES` (enslaved.js:34): C2–C5, C7,
        // C8, C10, C11, C12 get their goal raised to `DC.E1E15`
        // (unreachable) while inside The Nameless Ones' Reality. Web
        // badges these "Broken" in `NormalChallengeBox.vue:51`.
        let brokenIds: Set<Int> = [2, 3, 4, 5, 7, 8, 10, 11, 12]
        let enslavedRunning = self.enslavedIsRunning

        var challenges: [NormalChallengeInfo] = []
        challenges.reserveCapacity(12)
        for i in 0..<12 {
            let c = jsNCRefs[i]
            let config = c.forProperty("config")

            let desc = extractNormalizedString(from: config?.forProperty("description"))

            // lockedAt is a Decimal — format only if > 0
            let lockedAtVal = config?.forProperty("lockedAt")
            let lockedAtDec = GameDecimal(from: lockedAtVal)
            let lockedAt = (lockedAtDec.mantissa > 0) ? formatDecimal(lockedAtDec) : ""

            let id = i + 1
            let broken = enslavedRunning && brokenIds.contains(id)
            let rawCompleted = c.forProperty("isCompleted")?.toBool() ?? false

            challenges.append(NormalChallengeInfo(
                id: id,
                name: config?.forProperty("name")?.toString() ?? "",
                description: desc,
                reward: config?.forProperty("reward")?.toString() ?? "",
                isUnlocked: c.forProperty("isUnlocked")?.toBool() ?? false,
                isRunning: c.forProperty("isOnlyActiveChallenge")?.toBool() ?? false,
                // Mirror NormalChallengeBox.vue: `isCompleted = isCompleted && !isBroken`
                // so the Broken label takes over the status slot without also
                // showing the green Completed checkmark.
                isCompleted: rawCompleted && !broken,
                lockedAt: lockedAt,
                isBroken: broken
            ))
        }

        let retryChallenge = jsPlayer.forProperty("options")?.forProperty("retryChallenge")?.toBool() ?? false
        state.normalChallenges = NormalChallengesState(
            challenges: challenges,
            isAnyRunning: isAnyRunning,
            currentChallengeId: currentId,
            currentInfinities: infinities,
            retryChallenge: retryChallenge
        )
    }

    private func pollInfinityChallenges(_ state: inout GameState) {
        let currentId = Int(jsPlayer.forProperty("challenge")?.forProperty("infinity")?.forProperty("current")?.toInt32() ?? 0)
        let isAnyRunning = currentId != 0
        let retryChallenge = jsPlayer.forProperty("options")?.forProperty("retryChallenge")?.toBool() ?? false

        var challenges: [InfinityChallengeInfo] = []
        challenges.reserveCapacity(8)
        for i in 0..<8 {
            let c = jsICRefs[i]
            let config = c.forProperty("config")

            let desc = extractNormalizedString(from: config?.forProperty("description"))

            // Goal and reward via JS format() for reliable Decimal formatting
            let goal = context.evaluateScript("format(InfinityChallenge(\(i + 1)).config.goal)")?.toString() ?? "0"

            let rewardClean = extractNormalizedString(from: config?.forProperty("reward")?.forProperty("description"))

            // Reward effect value (if formatEffect exists)
            var rewardEffect: String? = nil
            let formatEff = config?.forProperty("reward")?.forProperty("formatEffect")
            if formatEff?.isObject == true {
                let effFn = config?.forProperty("reward")?.forProperty("effect")
                if effFn?.isObject == true {
                    let effVal = effFn?.call(withArguments: [])
                    rewardEffect = formatEff?.call(withArguments: [effVal as Any])?.toString()
                }
            }

            challenges.append(InfinityChallengeInfo(
                id: i + 1,
                description: desc,
                goal: goal,
                reward: rewardClean,
                rewardEffect: rewardEffect,
                isUnlocked: c.forProperty("isUnlocked")?.toBool() ?? false,
                isRunning: c.forProperty("isRunning")?.toBool() ?? false,
                isCompleted: c.forProperty("isCompleted")?.toBool() ?? false
            ))
        }

        let nextUnlockAM = context.evaluateScript(
            "InfinityChallenges.nextICUnlockAM !== undefined ? format(InfinityChallenges.nextICUnlockAM) : null"
        )
        let nextAMStr: String? = (nextUnlockAM?.isNull == true || nextUnlockAM?.isUndefined == true)
            ? nil : nextUnlockAM?.toString()

        let showAllChallenges = jsPlayer.forProperty("options")?.forProperty("showAllChallenges")?.toBool() ?? false

        state.infinityChallenges = InfinityChallengesState(
            challenges: challenges,
            isAnyRunning: isAnyRunning,
            nextICUnlockAM: nextAMStr,
            retryChallenge: retryChallenge,
            showAllChallenges: showAllChallenges
        )
    }

    // MARK: - Eternity Challenges polling

    /// Static EC descriptions — from eternity-challenges.js
    private static let ecDescriptions: [String] = [
        "Time Dimensions are disabled.",
        "Infinity Dimensions are disabled.",
        "Antimatter Dimensions 5-8 don't produce anything. Dimensional Sacrifice is disabled.",
        "All Infinity multipliers and generators are disabled. Must reach goal within a limited number of Infinities.",
        "Antimatter Galaxy cost increase scaling starts immediately. Dimension Boost cost scaling massively increased.",
        "Cannot gain Antimatter Galaxies normally. Replicanti Galaxy cost massively reduced.",
        "1st Time Dimension produces 8th Infinity Dimensions. 1st Infinity Dimension produces 7th Antimatter Dimensions. Tickspeed also affects Infinity and Time Dimensions.",
        "Can only upgrade Infinity Dimensions 50 times and Replicanti 40 times. Autobuyers are disabled.",
        "Cannot buy Tickspeed upgrades. Infinity Power multiplies Time Dimensions with reduced effect.",
        "Time Dimensions and Infinity Dimensions are disabled. Infinities provide a large multiplier to Antimatter Dimensions.",
        "All Dimension multipliers and powers are disabled except for Infinity Power and Boosts.",
        "The game runs 1000x slower. Must reach goal within a time limit.",
    ]

    /// Static EC reward descriptions
    private static let ecRewards: [String] = [
        "Time Dimension multiplier based on time spent this Eternity",
        "1st Infinity Dimension multiplier based on Infinity Power",
        "Increase the multiplier for buying 10 Antimatter Dimensions",
        "Infinity Dimension multiplier based on unspent IP",
        "Distant Galaxy cost scaling starts later",
        "Further reduce Antimatter Dimension cost multiplier growth",
        "1st Time Dimension produces 8th Infinity Dimensions",
        "Infinity Power strengthens Replicanti Galaxies",
        "Infinity Dimension multiplier based on Time Shards",
        "Time Dimension multiplier based on Infinities",
        "Further reduce Tickspeed cost multiplier growth",
        "Infinity Dimension cost multipliers are reduced",
    ]

    private func pollEternityChallenges(_ state: inout GameState) {
        let currentEC = Int(jsPlayer.forProperty("challenge")?.forProperty("eternity")?.forProperty("current")?.toInt32() ?? 0)
        let isAnyRunning = currentEC != 0

        var challenges: [EternityChallengeInfo] = []
        challenges.reserveCapacity(12)
        for i in 0..<12 {
            let c = jsECRefs[i]
            let completions = Int(c.forProperty("completions")?.toInt32() ?? 0)
            let maxCompletions = Int(c.forProperty("maxCompletions")?.toInt32() ?? 5)
            let isUnlocked = c.forProperty("isUnlocked")?.toBool() ?? false
            let isRunning = c.forProperty("isRunning")?.toBool() ?? false
            let isFullyCompleted = c.forProperty("isFullyCompleted")?.toBool() ?? false
            let canBeUnlocked = context.evaluateScript("TimeStudy.eternityChallenge(\(i + 1)).canBeBought")?.toBool() ?? false
            let hasUnlocked = c.forProperty("hasUnlocked")?.toBool() ?? false

            // Goal at current completions (scales with completions).
            // `EternityChallenge(N).goal` does NOT exist as a property — the
            // base goal lives on `.config.goal`. Web `EternityChallengeBox.vue`
            // reads `goalAtCompletions(this.completions)`, which is exactly
            // what the `.currentGoal` getter returns
            // (eternity-challenge.js:145-146).
            let goal = context.evaluateScript("format(EternityChallenge(\(i + 1)).currentGoal, 2, 1)")?.toString() ?? "0"

            // Reward effect — wrapped in JS-level try/catch. Each EC reward
            // `effect(completions)` reads game state that can be undefined
            // post-Armageddon (e.g. Currency / Time Dimensions / TimeStudy(31)
            // multipliers). Without the catch, every tick prints
            // `🔴 JS: TypeError: undefined is not an object` because this
            // poll is NOT tab-gated — it fires whenever `eternityReached`,
            // i.e. permanently for any post-Eternity player.
            var rewardEffect: String? = nil
            if completions > 0 {
                let raw = context.evaluateScript("""
                    (function() {
                        try {
                            var c = EternityChallenge(\(i + 1)).config;
                            if (!c || !c.reward) return null;
                            var fEff = c.reward.formatEffect;
                            var eFn = c.reward.effect;
                            if (typeof fEff !== "function" || typeof eFn !== "function") return null;
                            var v = eFn(\(completions));
                            var out = fEff(v);
                            return out === undefined || out === null ? null : String(out);
                        } catch (e) { return null; }
                    })()
                    """)?.toString()
                if let raw, raw != "null", !raw.isEmpty {
                    rewardEffect = raw
                }
            }

            challenges.append(EternityChallengeInfo(
                id: i + 1,
                description: Self.ecDescriptions[i],
                goal: goal,
                reward: Self.ecRewards[i],
                rewardEffect: rewardEffect,
                completions: completions,
                maxCompletions: maxCompletions,
                isUnlocked: isUnlocked,
                isRunning: isRunning,
                isFullyCompleted: isFullyCompleted,
                canBeUnlocked: canBeUnlocked,
                hasUnlocked: hasUnlocked
            ))
        }

        // Auto EC toggle visibility + state. Matches web `ChallengeTabHeader.vue`
        // `isAutoECVisible = Perk.autocompleteEC1.canBeApplied` / `autoEC = player.reality.autoEC`.
        let autoECVisible = context.evaluateScript("""
            (function(){ try { return !!Perk.autocompleteEC1.canBeApplied; } catch(e) { return false; } })()
            """)?.toBool() ?? false
        let autoECActive = jsPlayer.forProperty("reality")?.forProperty("autoEC")?.toBool() ?? false
        let showAllChallenges = jsPlayer.forProperty("options")?.forProperty("showAllChallenges")?.toBool() ?? false

        state.eternityChallenges = EternityChallengesState(
            challenges: challenges,
            isAnyRunning: isAnyRunning,
            autoECVisible: autoECVisible,
            autoECActive: autoECActive,
            showAllChallenges: showAllChallenges
        )
    }

    // MARK: - Bulk poll function injection

    private func injectMatterScale() {
        context.evaluateScript("""
        var MatterScale = {
          proton: new Decimal("2.82e-45"),
          estimate: function(matter) {
            if (!matter) return ["There is no antimatter yet."];
            if (matter.gt(new Decimal("1e100000"))) {
              return [
                "If you wrote " + formatInt(3) + " numbers a second, it would take you",
                TimeSpan.fromSeconds(matter.log10() / 3).toString(),
                "to write down your antimatter amount."
              ];
            }
            var planck = new Decimal("4.22419e-105");
            var planckedMatter = matter.times(planck);
            if (planckedMatter.gt(this.proton)) {
              var scale = this.macroScale(planckedMatter);
              var amount = format(planckedMatter.dividedBy(scale.amount), 2, 1);
              return ["If every antimatter were a planck volume, you would have enough to " + scale.verb + " " + amount + " " + scale.name];
            }
            var scale = this.microScale(matter);
            return ["If every antimatter were " + format(this.proton.div(scale.amount).div(matter), 2, 1) + " " + scale.name + ", you would have enough to make a proton."];
          },
          microScale: function(matter) {
            var micro = this.microObjects;
            for (var i = 0; i < micro.length; i++) {
              if (matter.times(micro[i].amount).lt(this.proton)) return micro[i];
            }
            return micro[micro.length - 1];
          },
          macroScale: function(matter) {
            var macro = this.macroObjects;
            var last = macro[macro.length - 1];
            if (matter.gte(last.amount)) return last;
            var low = 0, high = macro.length;
            while (low !== high) {
              var mid = Math.floor((low + high) / 2);
              if (macro[mid].amount.lte(matter)) { low = mid + 1; } else { high = mid; }
            }
            return macro[high - 1];
          },
          microObjects: [
            { amount: new Decimal("1e-54"), name: "attometers cubed" },
            { amount: new Decimal("1e-63"), name: "zeptometers cubed" },
            { amount: new Decimal("1e-72"), name: "yoctometers cubed" },
            { amount: new Decimal("4.22419e-105"), name: "planck volumes" }
          ],
          macroObjects: [
            { amount: new Decimal("2.82e-45"), name: "protons", verb: "make" },
            { amount: new Decimal("1e-42"), name: "nuclei", verb: "make" },
            { amount: new Decimal("7.23e-30"), name: "Hydrogen atoms", verb: "make" },
            { amount: new Decimal("5e-21"), name: "viruses", verb: "make" },
            { amount: new Decimal("9e-17"), name: "red blood cells", verb: "make" },
            { amount: new Decimal("6.2e-11"), name: "grains of sand", verb: "make" },
            { amount: new Decimal("5e-8"), name: "grains of rice", verb: "make" },
            { amount: new Decimal("3.555e-6"), name: "teaspoons", verb: "fill" },
            { amount: new Decimal("7.5e-4"), name: "wine bottles", verb: "fill" },
            { amount: new Decimal("1"), name: "fridge-freezers", verb: "fill" },
            { amount: new Decimal("2.5e3"), name: "Olympic-sized swimming pools", verb: "fill" },
            { amount: new Decimal("2.6006e6"), name: "Great Pyramids of Giza", verb: "make" },
            { amount: new Decimal("3.3e8"), name: "Great Walls of China", verb: "make" },
            { amount: new Decimal("5e12"), name: "large asteroids", verb: "make" },
            { amount: new Decimal("4.5e17"), name: "dwarf planets", verb: "make" },
            { amount: new Decimal("1.08e21"), name: "Earths", verb: "make" },
            { amount: new Decimal("1.53e24"), name: "Jupiters", verb: "make" },
            { amount: new Decimal("1.41e27"), name: "Suns", verb: "make" },
            { amount: new Decimal("5e32"), name: "red giants", verb: "make" },
            { amount: new Decimal("8e36"), name: "hypergiant stars", verb: "make" },
            { amount: new Decimal("1.7e45"), name: "nebulas", verb: "make" },
            { amount: new Decimal("1.7e48"), name: "Oort clouds", verb: "make" },
            { amount: new Decimal("3.3e55"), name: "Local Bubbles", verb: "make" },
            { amount: new Decimal("3.3e61"), name: "galaxies", verb: "make" },
            { amount: new Decimal("5e68"), name: "Local Groups", verb: "make" },
            { amount: new Decimal("1e73"), name: "Sculptor Voids", verb: "make" },
            { amount: new Decimal("3.4e80"), name: "observable universes", verb: "make" },
            { amount: new Decimal("1e113"), name: "Dimensions", verb: "make" },
            { amount: new Decimal(2).pow(1024), name: "Infinity Dimensions", verb: "make" },
            { amount: new Decimal("1e65000"), name: "Time Dimensions", verb: "make" }
          ]
        };
        """)
    }

    // MARK: - Event bridge

    private func injectEventBridge() {
        // Register Swift callback for game events
        let nativeEvent: @convention(block) (String) -> Void = { [weak self] eventName in
            guard let self else { return }
            self.perfEventCount += 1
            if eventName.contains("GAME_LOAD") {
                self.cacheJSRefs()
                self.context.evaluateScript("player.options.hibernationCatchup = false;")
                self.pollDirect()
                return
            }
            // TICK events are ignored — CADisplayLink drives pollDirect() at screen refresh rate.
            // Non-TICK game events (purchases, resets) trigger an immediate poll on iPad for
            // instant button feedback. On iPhone the next display link frame catches it.
            if eventName == "TICK" { return }
            if UIDevice.current.userInterfaceIdiom == .pad {
                self.pollDirect()
            }
        }
        context.setObject(nativeEvent, forKeyedSubscript: "_nativeEvent" as NSString)

        // Listen to key game events via EventHub
        context.evaluateScript("""
        (function() {
          var events = [
            GAME_EVENT.DIMBOOST_AFTER,
            GAME_EVENT.GALAXY_RESET_AFTER,
            GAME_EVENT.BIG_CRUNCH_AFTER,
            GAME_EVENT.SACRIFICE_RESET_AFTER,
            GAME_EVENT.INFINITY_UPGRADE_BOUGHT,
            GAME_EVENT.INFINITY_DIMENSION_UNLOCKED,
            GAME_EVENT.ACHIEVEMENT_UNLOCKED,
            GAME_EVENT.GAME_LOAD
          ];
          for (var i = 0; i < events.length; i++) {
            (function(evt) {
              EventHub.logic.on(evt, function() { typeof _nativeEvent !== "undefined" && _nativeEvent(evt.toString()); });
            })(events[i]);
          }
        })();
        """)
    }

    /// Cancel all timers (kills any stray intervals from init())
    private func clearAllTimers() {
        let count = timerMap.count
        for (_, timer) in timerMap { timer.cancel() }
        timerMap.removeAll()
        debugLog("TIMERS: cleared \(count) timers")
    }

    // MARK: - Save-load timer lifecycle

    /// Stop every JS timer + the game's built-in intervals so a save load
    /// can swap `player` without two game loops fighting for jsQueue.
    /// MUST be called on jsQueue.
    func stopAllGameTimersJS() {
        context.evaluateScript("""
            if (typeof _gameLoopTimerID !== 'undefined') {
                clearInterval(_gameLoopTimerID);
                clearInterval(_autosaveTimerID);
                clearInterval(_backupTimerID);
            }
            if (typeof GameIntervals !== 'undefined') GameIntervals.stop();
        """)
    }

    /// Restart the custom Swift-driven timer trio and ensure the game's
    /// built-in intervals stay stopped. `postLoadStuff()` inside
    /// `loadPlayerObject` restarts GameIntervals, so we re-stop them here
    /// to guarantee only our custom timers drive the game loop.
    /// MUST be called on jsQueue.
    func restartAllGameTimersJS() {
        context.evaluateScript("""
            if (typeof GameIntervals !== 'undefined') GameIntervals.stop();
            if (typeof _gameLoopTimerID !== 'undefined') {
                clearInterval(_gameLoopTimerID);
                clearInterval(_autosaveTimerID);
                clearInterval(_backupTimerID);
            }
            if (typeof _startGameLoopTimer === 'function') _startGameLoopTimer();
            _autosaveTimerID = setInterval(function() { GameStorage.save(true); }, \(PerformanceConfig.autosaveIntervalMs));
            if (typeof _startBackupPollTimer === 'function') _startBackupPollTimer();
        """)
    }

    // MARK: - Debug speed wrapper

    private func injectDebugSpeedWrapper() {
        context.evaluateScript("""
        var _debugSpeedMultiplier = 1;
        var _gameLoopCallCount = 0;
        var _lastGameLoopDiff = 0;
        var _lastGameLoopMs = 0;
        var _gameLoopTimerID = 0;
        var _autosaveTimerID = 0;
        var _backupTimerID = 0;
        var _origGameLoop = gameLoop;
        gameLoop = function(passDiff, options) {
          _gameLoopCallCount++;
          var t0 = Date.now();
          var before = player.records.realTimePlayed;
          _origGameLoop(passDiff, options);
          _lastGameLoopDiff = player.records.realTimePlayed - before;
          _lastGameLoopMs = Date.now() - t0;
        };
        function _startGameLoopTimer() {
          _gameLoopTimerID = setInterval(function() {
            if (_debugSpeedMultiplier <= 1) {
              gameLoop();
            } else {
              gameLoop(player.options.updateRate * _debugSpeedMultiplier);
            }
            typeof _nativeEvent !== "undefined" && _nativeEvent("TICK");
          }, player.options.updateRate);
        }
        // Rolling-backup poll — the JS core's `checkEverySecond` interval
        // (which calls `GameStorage.tryOnlineBackups()`) is killed by
        // `GameIntervals.stop()` below. Without this, the 1m / 5m / 20m /
        // 1h ONLINE backup slots never fire — only the OFFLINE-type
        // backups work (those run via `backupOfflineSlots()` at load time).
        // Defined as a shared helper so every site that restarts timers
        // (init, hardReset, importSave, slot switch, restore) can reuse it.
        function _startBackupPollTimer() {
          _backupTimerID = setInterval(function() {
            try {
              if (typeof GameStorage !== "undefined" && !GameStorage.ignoreBackupTimer) {
                GameStorage.tryOnlineBackups();
              }
            } catch (e) {}
          }, 1000);
        }
        (function() {
          // Stop ALL game intervals to prevent duplicate loops
          GameIntervals.stop();
          _startGameLoopTimer();
          // Autosave (GameIntervals.stop killed the built-in one)
          _autosaveTimerID = setInterval(function() {
            GameStorage.save(true);
          }, \(PerformanceConfig.autosaveIntervalMs));
          _startBackupPollTimer();
        })();
        """)
    }

    // MARK: - JS game loop profiler

    /// Toggle performance logging (PERF + JS-PROF lines). Injects the JS
    /// profiler on first enable. No-op in release builds.
    func togglePerfLogging() {
        #if DEBUG
        jsQueue.async { [self] in
            autoreleasepool {
                _perfLoggingEnabled.toggle()
                if _perfLoggingEnabled && !_jsProfilerInjected {
                    injectGameLoopProfiler()
                    _jsProfilerInjected = true
                }
                context.evaluateScript("gameLoop._profEnabled = \(_perfLoggingEnabled)")
                debugLog("PERF LOGGING: \(_perfLoggingEnabled ? "ON" : "OFF")")
            }
        }
        #endif
    }

    #if DEBUG
    /// Monkey-patches key game loop subsystems with Date.now() timing probes.
    /// Accumulates into `_jsProf`, read every 5 seconds from the PERF block.
    /// Each probe checks `_jsProfEnabled` and short-circuits when off.
    private func injectGameLoopProfiler() {
        // Attach profiler state to `gameLoop` (a known global function-object)
        // so it's accessible from any evaluateScript call via `gameLoop._prof`.
        // `var` declarations in evaluateScript don't survive across calls in JSC.
        context.evaluateScript("""
        gameLoop._profEnabled = false;
        gameLoop._prof = {
            ticks: 0, total: 0,
            adTick: 0, idTick: 0, tdTick: 0,
            replicanti: 0, autobuyers: 0,
            challenges: 0, ipGen: 0, prestigeGen: 0,
            autoprestige: 0, blackHoles: 0, realTime: 0,
            achievements: 0, speedFactor: 0,
            // AD.tick sub-probes
            adMult: 0, adCommon: 0, adProd: 0,
            // Autobuyer sub-probes
            autoDim: 0, autoOther: 0
        };

        // Utility: wrap a function with timing probe
        (function() {
            var P = gameLoop._prof;
            var E = function() { return gameLoop._profEnabled; };

            function profWrap(obj, key, profKey) {
                var orig = obj[key];
                if (typeof orig !== "function") return;
                obj[key] = function() {
                    if (!E()) return orig.apply(this, arguments);
                    var t0 = Date.now();
                    var r = orig.apply(this, arguments);
                    P[profKey] += Date.now() - t0;
                    return r;
                };
            }

            // Wrap game loop to count ticks + measure total
            var _prevGameLoop = gameLoop;
            gameLoop = function(passDiff, options) {
                if (!E()) return _prevGameLoop(passDiff, options);
                P.ticks++;
                var t0 = Date.now();
                _prevGameLoop(passDiff, options);
                P.total += Date.now() - t0;
            };
            // Carry the prof state to the new wrapper
            gameLoop._profEnabled = _prevGameLoop._profEnabled;
            gameLoop._prof = _prevGameLoop._prof;
            P = gameLoop._prof;
            E = function() { return gameLoop._profEnabled; };

            // Dimension production (expected hotspots)
            profWrap(AntimatterDimensions, "tick", "adTick");
            profWrap(InfinityDimensions, "tick", "idTick");
            profWrap(TimeDimensions, "tick", "tdTick");

            // AD.tick sub-probes: multiplier recomputation vs production math
            // The per-tier final multiplier cache is invalidated every tick,
            // forcing getDimensionFinalMultiplierUncached × 8 tiers.
            if (typeof GameCache !== "undefined" && GameCache.antimatterDimensionFinalMultipliers) {
                var adCaches = GameCache.antimatterDimensionFinalMultipliers;
                for (var ci = 0; ci < adCaches.length; ci++) {
                    (function(cache, idx) {
                        var origGetValue = cache._getValue;
                        if (typeof origGetValue !== "function") return;
                        cache._getValue = function() {
                            if (!E()) return origGetValue.call(this);
                            var t0 = Date.now();
                            var r = origGetValue.call(this);
                            P.adMult += Date.now() - t0;
                            return r;
                        };
                    })(adCaches[ci], ci);
                }
            }
            // Common multiplier (shared across all 8 AD tiers, computed once per tick)
            if (typeof GameCache !== "undefined" && GameCache.antimatterDimensionCommonMultiplier) {
                var cmc = GameCache.antimatterDimensionCommonMultiplier;
                var origCmcGetValue = cmc._getValue;
                if (typeof origCmcGetValue === "function") {
                    cmc._getValue = function() {
                        if (!E()) return origCmcGetValue.call(this);
                        var t0 = Date.now();
                        var r = origCmcGetValue.call(this);
                        P.adCommon += Date.now() - t0;
                        return r;
                    };
                }
            }

            // Autobuyer sub-probes: dimension autobuyers vs everything else
            if (typeof Autobuyers !== "undefined" && Autobuyers.all) {
                var origAutoTick = Autobuyers.tick;
                Autobuyers.tick = function() {
                    if (!E()) return origAutoTick.call(this);
                    // Reset sub-accumulators before the tick
                    var dimT = 0, otherT = 0;
                    if (!player.auto.autobuyersOn) return;
                    var all = Autobuyers.all;
                    for (var ai = 0; ai < all.length; ai++) {
                        var ab = all[ai];
                        if (!ab.canTick) continue;
                        var t0 = Date.now();
                        ab.tick();
                        var elapsed = Date.now() - t0;
                        // Dimension autobuyers have a .tier property
                        if (typeof ab.tier === "number") dimT += elapsed;
                        else otherT += elapsed;
                    }
                    P.autoDim += dimT;
                    P.autoOther += otherT;
                };
            }

            // Secondary systems
            if (typeof replicantiLoop === "function") {
                var _origRepl = replicantiLoop;
                replicantiLoop = function(diff) {
                    if (!E()) return _origRepl(diff);
                    var t0 = Date.now();
                    var r = _origRepl(diff);
                    P.replicanti += Date.now() - t0;
                    return r;
                };
            }

            profWrap(Autobuyers, "tick", "autobuyers");

            if (typeof updateNormalAndInfinityChallenges === "function") {
                var _origChal = updateNormalAndInfinityChallenges;
                updateNormalAndInfinityChallenges = function(d) {
                    if (!E()) return _origChal(d);
                    var t0 = Date.now();
                    var r = _origChal(d);
                    P.challenges += Date.now() - t0;
                    return r;
                };
            }

            if (typeof preProductionGenerateIP === "function") {
                var _origIPGen = preProductionGenerateIP;
                preProductionGenerateIP = function(d) {
                    if (!E()) return _origIPGen(d);
                    var t0 = Date.now();
                    var r = _origIPGen(d);
                    P.ipGen += Date.now() - t0;
                    return r;
                };
            }

            if (typeof passivePrestigeGen === "function") {
                var _origPrestige = passivePrestigeGen;
                passivePrestigeGen = function() {
                    if (!E()) return _origPrestige();
                    var t0 = Date.now();
                    var r = _origPrestige();
                    P.prestigeGen += Date.now() - t0;
                    return r;
                };
            }

            if (typeof applyAutoprestige === "function") {
                var _origAutoP = applyAutoprestige;
                applyAutoprestige = function(d) {
                    if (!E()) return _origAutoP(d);
                    var t0 = Date.now();
                    var r = _origAutoP(d);
                    P.autoprestige += Date.now() - t0;
                    return r;
                };
            }

            if (typeof BlackHoles !== "undefined" && BlackHoles
                && typeof BlackHoles.updatePhases === "function") {
                profWrap(BlackHoles, "updatePhases", "blackHoles");
            }

            if (typeof realTimeMechanics === "function") {
                var _origRT = realTimeMechanics;
                realTimeMechanics = function(d) {
                    if (!E()) return _origRT(d);
                    var t0 = Date.now();
                    var r = _origRT(d);
                    P.realTime += Date.now() - t0;
                    return r;
                };
            }

            if (typeof getGameSpeedupFactor === "function") {
                var _origSpd = getGameSpeedupFactor;
                getGameSpeedupFactor = function() {
                    if (!E()) return _origSpd();
                    var t0 = Date.now();
                    var r = _origSpd();
                    P.speedFactor += Date.now() - t0;
                    return r;
                };
            }
        })();
        """)
    }
    #endif

    // MARK: - Actions (all JS dispatched to jsQueue)

    func jsAsync(_ script: String) {
        jsQueue.async { [self] in autoreleasepool { _ = self.context.evaluateScript(script) } }
    }

    /// Evaluate a JS expression that returns JSON and parse it into a dictionary.
    /// Must be called on jsQueue. Returns nil on parse failure.
    private func pollJSON(_ script: String) -> [String: Any]? {
        let json = context.evaluateScript(script)?.toString() ?? "{}"
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj
    }

    func buyDimension(_ tier: Int) { jsAsync("buyOneDimension(\(tier))") }
    func buyMaxDimension(_ tier: Int) { jsAsync("buyMaxDimension(\(tier))") }
    func buyAsManyAsYouCanBuy(_ tier: Int) { jsAsync("buyAsManyAsYouCanBuy(\(tier))") }
    func buyTickSpeed() { jsAsync("buyTickSpeed()") }
    func buyMaxTickSpeed() { jsAsync("buyMaxTickSpeed()") }
    func maxAll() { jsAsync("maxAll()") }
    func toggleBuyQuantity() { jsAsync("player.buyUntil10 = !player.buyUntil10") }

    /// Three-way cycle for the AD tab header button when Continuum is
    /// unlocked (Lai'tela). Matches web:
    ///   Continuum → Until 10 → Buy 1 → Continuum
    /// When Continuum is unlocked but toggled off, tapping the button
    /// first cycles between Until 10 / Buy 1; re-enabling Continuum
    /// happens on the third state.
    func cycleBuyQuantity() {
        jsAsync("""
            (function(){
                try {
                    var contUnlocked = !!(typeof Laitela !== "undefined" && Laitela && Laitela.continuumUnlocked);
                    if (!contUnlocked) {
                        player.buyUntil10 = !player.buyUntil10;
                        return;
                    }
                    var disabled = !!player.auto.disableContinuum;
                    if (!disabled) {
                        // Continuum on → turn off, move to Until 10.
                        if (typeof Laitela.setContinuum === "function") Laitela.setContinuum(false);
                        else player.auto.disableContinuum = true;
                        player.buyUntil10 = true;
                    } else if (player.buyUntil10) {
                        // Until 10 → Buy 1.
                        player.buyUntil10 = false;
                    } else {
                        // Buy 1 → Continuum on.
                        if (typeof Laitela.setContinuum === "function") Laitela.setContinuum(true);
                        else player.auto.disableContinuum = false;
                    }
                } catch (e) { player.buyUntil10 = !player.buyUntil10; }
            })()
            """)
    }
    func cyclePrestigeRunDisplayMode() { jsAsync("player.options.statTabResources = (player.options.statTabResources + 1) % 4") }

    /// Quick reset: lose a Dimension Boost (C9 and other quick-resettable challenges)
    func quickReset() { jsAsync("softReset(-1, true, true)") }

    // Confirmation-gated prestige actions — check JS on jsQueue, show modal on main
    func buyDimensionBoost() {
        jsQueue.async { [self] in
            if self.confirmationEnabled("dimensionBoost") {
                DispatchQueue.main.async { self.pendingModal = .dimensionBoost }
            } else {
                self.context.evaluateScript("requestDimensionBoost(true)")
            }
        }
    }

    func buyGalaxy() {
        jsQueue.async { [self] in
            if self.confirmationEnabled("antimatterGalaxy") {
                DispatchQueue.main.async { self.pendingModal = .galaxy }
            } else {
                self.context.evaluateScript("requestGalaxyReset(true)")
            }
        }
    }

    func bigCrunch() {
        jsQueue.async { [self] in
            // Web logic: show modal on first infinity OR post-break; skip between first infinity and break.
            // Use `hasBroken()` not raw `player.break` — Armageddon resets
            // the raw flag, but the web getter stays true post-Armageddon
            // because `isEternityUnlocked` is permanent. Without this, doomed
            // players don't get the confirmation modal that web shows.
            let infUnlocked = self.jsPlayerProgress.invokeMethod("infinityUnlocked", withArguments: [])?.toBool() ?? false
            let isBroken = self.jsPlayerProgress.invokeMethod("hasBroken", withArguments: [])?.toBool() ?? false
            let shouldConfirm = self.confirmationEnabled("bigCrunch") && (!infUnlocked || isBroken)
            if shouldConfirm {
                DispatchQueue.main.async { self.pendingModal = .bigCrunch }
            } else {
                self.context.evaluateScript("bigCrunchReset()")
            }
        }
    }

    func sacrifice() {
        jsQueue.async { [self] in
            if self.confirmationEnabled("sacrifice") {
                DispatchQueue.main.async { self.pendingModal = .sacrifice }
            } else {
                self.context.evaluateScript("sacrificeReset()")
            }
        }
    }

    // MARK: - Modal confirmation

    func confirmPrestige() {
        guard let modal = pendingModal else { return }
        pendingModal = nil  // clear immediately on main for UI responsiveness
        jsQueue.async { [self] in
            switch modal {
            case .dimensionBoost: self.context.evaluateScript("requestDimensionBoost(true)")
            case .galaxy: self.context.evaluateScript("requestGalaxyReset(true)")
            case .bigCrunch: self.context.evaluateScript("bigCrunchReset()")
            case .sacrifice: self.context.evaluateScript("sacrificeReset()")
            case .replicantiGalaxy: self.context.evaluateScript("replicantiGalaxy(false)")
            case .eternity: self.performEternity()
            case .normalChallenge(let id): self.context.evaluateScript("NormalChallenge(\(id)).start()")
            case .infinityChallenge(let id): self.context.evaluateScript("InfinityChallenge(\(id)).start()")
            case .eternityChallenge(let id): self.context.evaluateScript("EternityChallenge(\(id)).start()")
            case .exitChallenge: self.context.evaluateScript("(function(){ var c = Player.anyChallenge; if(c) c.exit(); })()")
            case .enterDilation: self.context.evaluateScript("startDilatedEternity()")
            case .exitDilation: self.context.evaluateScript("startDilatedEternity()")
            case .reality: self.context.evaluateScript("processManualReality(false, undefined)")
            case .resetReality: self.context.evaluateScript("beginProcessReality(getRealityProps(true))")
            case .teresaRun: self.context.evaluateScript("_nativeStartTeresaRun()")
            case .effarigRun: self.context.evaluateScript("_nativeStartEffarigRun()")
            case .enslavedRun: self.context.evaluateScript("_nativeStartEnslavedRun()")
            case .vRun: self.context.evaluateScript("_nativeStartVRun()")
            case .raRun: self.context.evaluateScript("_nativeStartRaRun()")
            case .laitelaRun: self.context.evaluateScript("_nativeStartLaitelaRun()")
            case .awayProgress: break  // no JS action needed, modal is informational
            case .glyphPurge(let harsh, _, _): self.context.evaluateScript("Glyphs.autoClean(\(harsh ? 1 : 5))")
            case .deleteAllUnprotectedGlyphs: self.context.evaluateScript("Glyphs.autoClean(0)")
            case .deleteAllRejectedGlyphs: self.context.evaluateScript("Glyphs.deleteAllRejected(true)")
            }
        }
    }

    func cancelPrestige() {
        pendingModal = nil
    }

    func setConfirmation(_ key: String, enabled: Bool) {
        jsAsync("player.options.confirmations.\(key) = \(enabled)")
    }

    /// Called on jsQueue — reads JS synchronously.
    ///
    /// Returns `true` when the user has not explicitly opted out via the
    /// "Don't show again" toggle. Because new prestige modals (Teresa, Effarig,
    /// any future celestial) aren't in `Player.defaultStart.options.confirmations`,
    /// their key is `undefined` until the user toggles it — and the previous
    /// `?.toBool() ?? true` collapsed to `false` for `undefined`, silently
    /// suppressing the modal. The `!== false` form preserves the opt-out path
    /// (`false` → no modal) while defaulting unknown keys to "show".
    func confirmationEnabled(_ key: String) -> Bool {
        context.evaluateScript("player.options.confirmations.\(key) !== false")?.toBool() ?? true
    }

    /// Save must complete before app suspension — use sync.
    /// Also pauses game loop + autosave when backgrounding so no ticks leak.
    /// Persists player.lastUpdate to UserDefaults so cold-start can read it
    /// before init() overwrites it.
    func save() {
        let pausing = backgroundEntryDate != nil
        // Web `SAVE_DISABLED` (endState >= 4.0): the JS save path is meant
        // to be inert. We still want to handle background pause / timer
        // teardown, so we just skip the actual GameStorage.save call.
        let skipPersistence = gameEndSavesDisabled
        debugLog("BG SAVE: entering jsQueue.sync (pausing=\(pausing), skipPersistence=\(skipPersistence))")
        jsQueue.sync { [self] in
            autoreleasepool {
                if !skipPersistence {
                    debugLog("BG SAVE: on jsQueue, calling GameStorage.save")
                    _ = self.context.evaluateScript("GameStorage.save(true)")
                } else {
                    debugLog("BG SAVE: skipping persistence (GameEnd SAVE_DISABLED)")
                }
                // Persist lastUpdate separately so cold-start can detect offline gap
                // before init() overwrites player.lastUpdate to Date.now().
                let lastUpdate = self.context.evaluateScript("player.lastUpdate")?.toDouble() ?? 0
                if lastUpdate > 0 {
                    UserDefaults.standard.set(lastUpdate, forKey: "am_lastUpdate")
                }
                if pausing {
                    self.backgroundPaused = true
                    self.context.evaluateScript("if (typeof _gameLoopTimerID !== 'undefined') { clearInterval(_gameLoopTimerID); clearInterval(_autosaveTimerID); clearInterval(_backupTimerID); }")
                    debugLog("BG SAVE: paused game loop + autosave (backgroundPaused = true)")
                }
                debugLog("BG SAVE: done")
            }
        }
        debugLog("BG SAVE: jsQueue.sync returned")
    }

    // MARK: - Offline progress

    /// Record the moment the app enters background and pause the game loop.
    /// Called from main thread; guards against double-setting from .inactive → .background.
    func recordBackgroundEntry() {
        guard backgroundEntryDate == nil else {
            debugLog("OFFLINE: recordBackgroundEntry — already set, skipping")
            return
        }
        #if DEBUG
        if debugFakeOfflineGap {
            backgroundEntryDate = Date().addingTimeInterval(-90 * 60)
        } else {
            backgroundEntryDate = Date()
        }
        #else
        backgroundEntryDate = Date()
        #endif
        stopDisplayLink()
        debugLog("OFFLINE: recorded background entry at \(backgroundEntryDate!)")
        // Pause the JS game loop and autosave timer immediately so we don't
        // burn CPU/battery in the background. backgroundPaused flag ensures any
        // already-enqueued timer callbacks are no-ops even if clearInterval hasn't
        // taken effect yet.
        jsQueue.async { [self] in
            autoreleasepool {
                backgroundPaused = true
                context.evaluateScript("if (typeof _gameLoopTimerID !== 'undefined') { clearInterval(_gameLoopTimerID); clearInterval(_autosaveTimerID); clearInterval(_backupTimerID); }")
                debugLog("OFFLINE: game loop + autosave paused (backgroundPaused = true)")
            }
        }
    }

    // MARK: - Offline simulation driver

    /// Swift-driven batched offline simulation. Replaces JS-side Async.run for proper
    /// progress bar support. Must be called on jsQueue.
    ///
    /// - Parameters:
    ///   - elapsed: Offline duration in seconds
    ///   - isStartup: true = cold start (calls finishStartup on completion),
    ///                false = foreground return (restarts game loop + display link)
    private func runOfflineSimulation(elapsed: Double, isStartup: Bool) {
        // WebView routing: only for slow-path-eligible sims (elapsed >= 50s,
        // ~the same threshold the JS fast-path test rejects). Boot overhead
        // of ~1.1s makes WebView a regression for short sims, but at ~22×
        // tick speedup it pays for itself in any sim above ~600 ticks.
        let useWebView = UserDefaults.standard.bool(forKey: "offlineSimUseWebView")
                         && elapsed >= 50
        if useWebView {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                Task { @MainActor in
                    let success = await self.runOfflineSimulationWebViewPath(
                        elapsed: elapsed, isStartup: isStartup
                    )
                    if !success {
                        debugLog("OFFLINE SIM: WebView path failed; falling back to JSContext")
                        self.jsQueue.async {
                            self.runOfflineSimulationJSContextPath(
                                elapsed: elapsed, isStartup: isStartup
                            )
                        }
                    }
                }
            }
            return
        }

        runOfflineSimulationJSContextPath(elapsed: elapsed, isStartup: isStartup)
    }

    /// JSContext path — the original implementation. Synchronous on jsQueue;
    /// uses the inline batched execution. Shared between the always-on
    /// fast-path / short-elapsed branch and the WebView-failure fallback.
    private func runOfflineSimulationJSContextPath(elapsed: Double, isStartup: Bool) {
        // Cache refs early so captureAwaySnapshot works
        cacheJSRefs()
        let before = captureAwaySnapshot()
        debugLog("OFFLINE SIM: before — AM=\(before.antimatter), IP=\(before.infinityPoints)")

        // Set up simulation in JS — calculates ticks, awards offline currencies,
        // prepares loopFn (standard or Black Hole variant), stores state in _offlineSim.
        // Setup script is shared with the WebView path (OfflineSimWebView.runOfflineSim).
        let tickCount = context.evaluateScript(
            GameEngine.offlineSimSetupSource(elapsedSeconds: elapsed)
        )?.toDouble() ?? 0

        let totalTicks = clampedInt(tickCount)
        debugLog("OFFLINE SIM: \(totalTicks) ticks for \(String(format: "%.1f", elapsed))s offline")

        if totalTicks <= 0 {
            finalizeOfflineSimulation(elapsed: elapsed, before: before, isStartup: isStartup)
            return
        }

        // Fast path: <= 50 ticks, run synchronously with no progress bar
        if totalTicks <= 50 {
            context.evaluateScript("""
                (function() {
                    var sim = _offlineSim;
                    for (var i = sim.remaining; i > 0; i--) {
                        sim.loopFn(i);
                    }
                    sim.remaining = 0;
                })()
                """)
            debugLog("OFFLINE SIM: fast path — \(totalTicks) ticks done synchronously")
            finalizeOfflineSimulation(elapsed: elapsed, before: before, isStartup: isStartup)
            return
        }

        // Slow path: batched execution with progress bar
        let startTime = Date()
        DispatchQueue.main.async { [self] in
            self.offlineSimProgress = OfflineSimProgress(
                current: 0, total: totalTicks, startTime: startTime
            )
        }

        runOfflineSimBatch(elapsed: elapsed, before: before, isStartup: isStartup)
    }

    /// WebView path — runs the offline sim in a hidden WKWebView (which
    /// has JIT) and applies the resulting save back to JSContext. Returns
    /// false on any failure so the caller can fall back to the JSContext
    /// path. All JSContext touches go through `jsQueue.sync` continuations
    /// so the main-actor side stays serialised against live game ticks.
    @MainActor
    private func runOfflineSimulationWebViewPath(elapsed: Double, isStartup: Bool) async -> Bool {
        // 1. Capture before-snapshot from JSContext.
        guard let before = await captureAwaySnapshotAsync() else {
            debugLog("OFFLINE SIM (WV): captureAwaySnapshotAsync failed")
            return false
        }

        // 2. Export current save from JSContext. Read the slot directly
        // from `GameStorage.currentSlot` rather than `lastKnownCurrentSlot`
        // — at cold start, `lastKnownCurrentSlot` defaults to 0 because
        // it's only populated on save-tick (which hasn't fired yet). If
        // we trust the cache here we'd export slot 0's data and apply it
        // to whatever slot the user is actually on, corrupting saves.
        let slotId = await withCheckedContinuation { (cont: CheckedContinuation<Int, Never>) in
            jsQueue.async { [weak self] in
                guard let self = self else { cont.resume(returning: 0); return }
                let s = Int(self.context.evaluateScript("GameStorage.currentSlot")?.toInt32() ?? 0)
                cont.resume(returning: s)
            }
        }
        // Keep the cached value in sync so any other code path reading
        // it during this sim sees the right slot too.
        lastKnownCurrentSlot = slotId
        guard let preSave = exportSlotRawSync(slotId), !preSave.isEmpty else {
            debugLog("OFFLINE SIM (WV): export from JSContext failed (slot \(slotId))")
            return false
        }

        // 3. Boot the WebView. ~1.1s — show a progress placeholder so the
        // user sees something is happening (we don't have an exact tick
        // count yet; runOfflineSim's setup will compute it).
        let placeholderTotal = max(50, min(10_000, clampedInt(elapsed * 20)))
        offlineSimProgress = OfflineSimProgress(
            current: 0, total: placeholderTotal, startTime: Date()
        )

        let sim = OfflineSimWebView()
        let boot = await sim.boot()
        guard boot.isOK else {
            sim.tearDown()
            offlineSimProgress = nil
            if case .failure(let label, _) = boot {
                debugLog("OFFLINE SIM (WV): boot failed at '\(label)'")
            }
            return false
        }

        // 4. Import save into the WebView.
        guard await sim.importSave(preSave) else {
            sim.tearDown()
            offlineSimProgress = nil
            debugLog("OFFLINE SIM (WV): importSave into WebView failed")
            return false
        }

        // 5. Run the real offline sim. Track the active WebView so the
        // user-facing Speed up / Skip buttons can route to it instead of
        // mutating the (non-existent) JSContext _offlineSim.
        activeOfflineSimWebView = sim
        let ticksRun = await sim.runOfflineSim(
            elapsedSeconds: elapsed,
            progressCallback: { [weak self] remaining, total in
                guard let self = self else { return }
                // Mirror runOfflineSimBatch's UI update: current = total - remaining.
                let done = max(0, total - remaining)
                self.offlineSimProgress?.current = done
                self.offlineSimProgress?.total = total
            }
        )
        activeOfflineSimWebView = nil
        guard ticksRun >= 0 else {
            sim.tearDown()
            offlineSimProgress = nil
            debugLog("OFFLINE SIM (WV): runOfflineSim returned -1")
            return false
        }
        debugLog("OFFLINE SIM (WV): ran \(ticksRun) ticks for \(String(format: "%.1f", elapsed))s")

        // 6. Export post-sim save from WebView.
        guard let postSave = await sim.exportSave() else {
            sim.tearDown()
            offlineSimProgress = nil
            debugLog("OFFLINE SIM (WV): exportSave from WebView failed")
            return false
        }
        // Capture toast notifications fired during the WebView sim (the
        // WebView's `_nativeNotify` stub forwards them to a JS->Swift bridge
        // — see OfflineSimWebView). We replay them after the save is applied
        // so the user sees the same green/blue/etc. toasts they'd see from
        // a real-time unlock — most importantly the "Automatically unlocked:
        // X" achievement messages from autoAchieveUpdate.
        let capturedToasts = sim.capturedNotifications
        sim.tearDown()

        // 7. Apply post-sim save back to JSContext.
        guard await applyOfflineSimSave(postSave) else {
            offlineSimProgress = nil
            debugLog("OFFLINE SIM (WV): applyOfflineSimSave failed")
            return false
        }

        // 7b. Replay the captured toasts now that JSContext state matches.
        if !capturedToasts.isEmpty {
            debugLog("OFFLINE SIM (WV): replaying \(capturedToasts.count) toast(s)")
            for toast in capturedToasts {
                let cleaned = GameEngine.sanitizeNotifyText(toast.text, collapseNewlines: toast.type == "modalMessage")
                enqueueToast(type: toast.type, text: cleaned)
            }
        }

        // 8. Capture after-snapshot, show away modal if threshold met.
        let after = await captureAwaySnapshotAsync()
        offlineSimProgress = nil
        if let after = after {
            #if DEBUG
            let modalThreshold: Double = 120
            #else
            let modalThreshold: Double = 600
            #endif
            if elapsed >= modalThreshold {
                let entries = buildAwayEntries(before: before, after: after)
                if !entries.isEmpty {
                    let timeStr = await formatTimeSpanAsync(seconds: elapsed)
                    let data = AwayProgressData(
                        elapsedTimeDisplay: timeStr,
                        entries: entries
                    )
                    debugLog("OFFLINE SIM (WV): showing awayProgress modal")
                    pendingModal = .awayProgress(data)
                }
            }
        }

        // 9. Finalise: if cold start, finishStartup; if foreground return,
        //    timers were restarted by applyOfflineSimSave so just resume
        //    the display link.
        if isStartup {
            jsQueue.async { [weak self] in self?.finishStartup() }
        } else {
            backgroundPaused = false
            startDisplayLink()
            recordInteraction()
        }
        return true
    }

    /// Async wrapper around `captureAwaySnapshot` (which is jsQueue-only).
    @MainActor
    private func captureAwaySnapshotAsync() async -> AwaySnapshot? {
        await withCheckedContinuation { (cont: CheckedContinuation<AwaySnapshot?, Never>) in
            jsQueue.async { [weak self] in
                guard let self = self else {
                    cont.resume(returning: nil)
                    return
                }
                self.cacheJSRefs()
                let snap = self.captureAwaySnapshot()
                cont.resume(returning: snap)
            }
        }
    }

    /// Async wrapper around `TimeSpan.fromSeconds(...).toString()`.
    @MainActor
    private func formatTimeSpanAsync(seconds: Double) async -> String {
        await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            jsQueue.async { [weak self] in
                guard let self = self else {
                    cont.resume(returning: "\(clampedInt(seconds))s")
                    return
                }
                let str = self.context.evaluateScript(
                    "TimeSpan.fromSeconds(\(seconds)).toString()"
                )?.toString() ?? "\(clampedInt(seconds))s"
                cont.resume(returning: str)
            }
        }
    }

    /// Apply a post-sim save string from the WebView to the JSContext
    /// silently (no toast, no Modal.message). Mirrors the import-side of
    /// `importSave` — stop timers, deserialize+validate+import, restart
    /// timers, persist new lastUpdate, re-cache refs, re-inject helpers,
    /// pollDirect. Returns false if checkPlayerObject rejects the blob.
    @MainActor
    private func applyOfflineSimSave(_ saveData: String) async -> Bool {
        let escaped = saveData
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            jsQueue.async { [weak self] in
                guard let self = self else { cont.resume(returning: false); return }
                autoreleasepool {
                    self.stopAllGameTimersJS()
                    let result = self.context.evaluateScript("""
                        (function() {
                            var save = GameSaveSerializer.deserialize(`\(escaped)`);
                            if (!save || GameStorage.checkPlayerObject(save) !== '') return 'invalid';
                            GameStorage.offlineEnabled = false;
                            // Suppress the "Game imported" toast that
                            // GameStorage.import unconditionally fires —
                            // this is offline-sim plumbing, not a user
                            // import.
                            var __origNotify = globalThis._nativeNotify;
                            globalThis._nativeNotify = function(t, x) {
                                if (x !== "Game imported" && typeof __origNotify === "function") {
                                    __origNotify(t, x);
                                }
                            };
                            try {
                                GameStorage.import(`\(escaped)`);
                            } finally {
                                globalThis._nativeNotify = __origNotify;
                            }
                            return 'ok';
                        })()
                        """)?.toString() ?? "error"
                    if result != "ok" {
                        // Restart timers so the live game keeps ticking on failure.
                        self.restartAllGameTimersJS()
                        cont.resume(returning: false)
                        return
                    }
                    self.restartAllGameTimersJS()
                    self.context.evaluateScript("player.options.hibernationCatchup = false;")
                    let lastUpdate = self.context.evaluateScript("player.lastUpdate")?.toDouble() ?? 0
                    if lastUpdate > 0 {
                        UserDefaults.standard.set(lastUpdate, forKey: "am_lastUpdate")
                    }
                    self.cacheJSRefs()
                    self.setupNewsHelpers()
                    self.setupCelestialHelpers()
                    self.setupGameEndHelpers()
                    self.setupAutomatorHelpers()
                    self.setupSaveHelpers()
                    self.setupGlyphPresetHelpers()
                    self.setupSpeedrunHelpers()
                    self.setupPerksHelper()
                    self.setupTimeStudiesHelper()
                    self.setupGlyphEffectFormatHelper()
                    self.setupHeaderTickHelper()
                    self.setupStatisticsAndRelatedHelpers()
                    self.setupSecretAchievementsHelper()
                    self.pollDirect()
                    // NOTE: deliberately do NOT call resetUnlockFlags() here.
                    // Unlike hardReset / importSave / slot-switch (which load a
                    // potentially-LESS-unlocked save and intentionally navigate to
                    // Dimensions afterward), the offline sim re-imports the SAME
                    // save advanced in time. Unlocks are monotonic — offline
                    // progress can only ADD unlocks, never remove them — so the
                    // sticky-true flags are already correct, and pollDirect sets
                    // any newly-crossed unlock true on the next tick. Calling
                    // resetUnlockFlags() would publish false transitions on every
                    // unlock flag, and per the sticky-true contract (see the
                    // unlock-flag block in pollDirect) a false transition shrinks
                    // availableTabs / currentAvailableSubtabs and yanks the user
                    // to the Dimensions tab — the foreground-return bounce bug.
                    // The JSContext path (finalizeOfflineSimulation) never reset
                    // them either; this brings the WebView path in line.

                    // Cloud-sync byte-parity sidestep (Stage 5).
                    // Stage-5 divergence test confirmed WebView and JSContext
                    // produce different post-sim bytes due to FP-determinism
                    // gaps between JIT and interpreter (compounds at endgame
                    // scale). Re-export the freshly-applied save and pin
                    // `cloud.lastSeenHash.{slot}` to its hash. The next
                    // cloud probe sees the new bytes as "already known" so
                    // it doesn't false-positive a phantom conflict. The
                    // canonical arbiter for cross-device resolution
                    // remains `realTimePlayed` ("playtime wins") per the
                    // existing CloudSaveService policy.
                    //
                    // We're already on jsQueue inside this continuation —
                    // call _nativeExportSlot directly via evaluateScript.
                    // Don't call exportSlotRawSync (which would jsQueue.sync
                    // on a queue we're already on → self-deadlock /
                    // EXC_BREAKPOINT from libdispatch's reentrancy guard).
                    let slotId = Int(self.context.evaluateScript("GameStorage.currentSlot")?.toInt32() ?? 0)
                    let postSimSave = self.context.evaluateScript(
                        "_nativeExportSlot(\(slotId))"
                    )?.toString() ?? ""
                    if !postSimSave.isEmpty {
                        let hash = CloudSaveService.sha256(postSimSave)
                        DispatchQueue.main.async {
                            UserDefaults.standard.set(hash, forKey: "cloud.lastSeenHash.\(slotId)")
                        }
                    }

                    cont.resume(returning: true)
                }
            }
        }
    }

    /// Run ticks in time-based batches matching the web's Async.run approach:
    /// execute as many ticks as fit in a 60ms window, yield for 1ms, repeat.
    /// This is dramatically faster than fixed-count batches because it adapts
    /// to the device's JS execution speed.
    private func runOfflineSimBatch(
        elapsed: Double, before: AwaySnapshot, isStartup: Bool
    ) {
        autoreleasepool {
            // Run ticks for up to 60ms, then report progress and yield.
            // The JS side mirrors web's Async.runForTime: batchSize=1, maxTime=60ms.
            let remaining = context.evaluateScript("""
                (function() {
                    var sim = _offlineSim;
                    var t0 = Date.now();
                    while (sim.remaining > 0) {
                        sim.loopFn(sim.remaining);
                        sim.remaining--;
                        if (Date.now() - t0 >= 60) break;
                    }
                    return sim.remaining;
                })()
                """)?.toDouble() ?? 0

            let total = context.evaluateScript("_offlineSim.total")?.toDouble() ?? 1
            let safeTotal = max(1, clampedInt(total))
            let safeRemaining = clampedInt(remaining)
            let done = safeTotal - safeRemaining

            DispatchQueue.main.async { [self] in
                self.offlineSimProgress?.current = done
                self.offlineSimProgress?.total = safeTotal
            }

            if remaining > 0 {
                // Yield jsQueue briefly (1ms, matching web's sleepTime) then continue
                jsQueue.asyncAfter(deadline: .now() + .milliseconds(1)) { [self] in
                    self.runOfflineSimBatch(
                        elapsed: elapsed, before: before, isStartup: isStartup
                    )
                }
            } else {
                finalizeOfflineSimulation(elapsed: elapsed, before: before, isStartup: isStartup)
            }
        }
    }

    /// Complete offline simulation: postLoadStuff, snapshot, away modal, continue startup or resume.
    private func finalizeOfflineSimulation(elapsed: Double, before: AwaySnapshot, isStartup: Bool) {
        context.evaluateScript("""
            if (typeof _offlineSim !== 'undefined') _offlineSim = undefined;
            GameStorage.postLoadStuff();
            GameUI.notify.showBlackHoles = true;
            ui.view.modal.progressBar = undefined;
            """)
        debugLog("OFFLINE SIM: finalized")

        let after = captureAwaySnapshot()
        debugLog("OFFLINE SIM: after — AM=\(after.antimatter), IP=\(after.infinityPoints)")

        // Clear progress bar
        DispatchQueue.main.async { [self] in
            self.offlineSimProgress = nil
        }

        // Show away progress modal if threshold met
        #if DEBUG
        let modalThreshold: Double = 120  // 2 minutes in debug
        #else
        let modalThreshold: Double = 600  // 10 minutes in release
        #endif
        if elapsed >= modalThreshold {
            let entries = buildAwayEntries(before: before, after: after)
            if !entries.isEmpty {
                let timeStr = context.evaluateScript(
                    "TimeSpan.fromSeconds(\(elapsed)).toString()"
                )?.toString() ?? "\(clampedInt(elapsed))s"
                let data = AwayProgressData(
                    elapsedTimeDisplay: timeStr,
                    entries: entries
                )
                DispatchQueue.main.async { [self] in
                    debugLog("OFFLINE SIM: showing awayProgress modal")
                    self.pendingModal = .awayProgress(data)
                }
            }
        }

        if isStartup {
            finishStartup()
        } else {
            // Foreground return path: restart game loop + display link
            backgroundPaused = false
            context.evaluateScript("""
                GameIntervals.stop();
                if (typeof _gameLoopTimerID !== 'undefined') { clearInterval(_gameLoopTimerID); clearInterval(_autosaveTimerID); clearInterval(_backupTimerID); }
                if (typeof _startGameLoopTimer !== 'undefined') { _startGameLoopTimer(); }
                _autosaveTimerID = setInterval(function() { GameStorage.save(true); }, \(PerformanceConfig.autosaveIntervalMs));
                if (typeof _startBackupPollTimer === 'function') _startBackupPollTimer();
                """)
            debugLog("OFFLINE SIM: restarted game loop + autosave")
            DispatchQueue.main.async { [self] in
                self.startDisplayLink()
                self.recordInteraction()
            }
            pollDirect()
        }
    }

    /// Active OfflineSimWebView during a WebView-routed sim. Set by
    /// `runOfflineSimulationWebViewPath`; nil otherwise. Read by
    /// `offlineSimSpeedUp` / `offlineSimSkip` to route control signals
    /// to the WebView's `_offlineSim` instead of JSContext's.
    @MainActor weak var activeOfflineSimWebView: OfflineSimWebView?

    /// Speed up offline simulation — halves remaining ticks (minimum 500).
    /// Routes to the WebView when one's active, otherwise to JSContext.
    func offlineSimSpeedUp() {
        // The button is tapped on main, so synchronous main-actor read of
        // activeOfflineSimWebView is fine.
        if Thread.isMainThread, let wv = activeOfflineSimWebView {
            Task { @MainActor in await wv.speedUp() }
            debugLog("OFFLINE SIM: speed up (WV)")
            return
        }
        jsQueue.async { [self] in
            autoreleasepool {
                context.evaluateScript("""
                    if (typeof _offlineSim !== 'undefined') {
                        var newRemaining = Math.max(Math.floor(_offlineSim.remaining / 2), 500);
                        _offlineSim.total -= (_offlineSim.remaining - newRemaining);
                        _offlineSim.remaining = newRemaining;
                    }
                    """)
                debugLog("OFFLINE SIM: speed up — remaining now \(context.evaluateScript("typeof _offlineSim !== 'undefined' && _offlineSim.remaining")?.toDouble() ?? 0)")
            }
        }
    }

    /// Skip offline simulation — jumps to 10 ticks remaining.
    /// Routes to the WebView when one's active, otherwise to JSContext.
    func offlineSimSkip() {
        if Thread.isMainThread, let wv = activeOfflineSimWebView {
            Task { @MainActor in await wv.skip() }
            debugLog("OFFLINE SIM: skip (WV)")
            return
        }
        jsQueue.async { [self] in
            autoreleasepool {
                context.evaluateScript("""
                    if (typeof _offlineSim !== 'undefined' && _offlineSim.remaining > 10) {
                        _offlineSim.total -= (_offlineSim.remaining - 10);
                        _offlineSim.remaining = 10;
                    }
                    """)
                debugLog("OFFLINE SIM: skip — remaining now \(context.evaluateScript("typeof _offlineSim !== 'undefined' && _offlineSim.remaining")?.toDouble() ?? 0)")
            }
        }
    }

    /// Called when the app returns to foreground. Runs offline simulation on jsQueue
    /// and shows an away-progress modal if significant time elapsed.
    func handleForegroundReturn() {
        guard let bgDate = backgroundEntryDate else {
            debugLog("OFFLINE: handleForegroundReturn — no backgroundEntryDate, skipping")
            return
        }
        backgroundEntryDate = nil
        let elapsed = Date().timeIntervalSince(bgDate)
        debugLog("OFFLINE: foreground return, elapsed = \(String(format: "%.1f", elapsed))s")

        if elapsed < 10 {
            debugLog("OFFLINE: elapsed < 10s, just restarting timers")
            jsQueue.async { [self] in
                autoreleasepool {
                    backgroundPaused = false
                    context.evaluateScript("""
                    if (typeof _startGameLoopTimer !== 'undefined') { _startGameLoopTimer(); }
                    _autosaveTimerID = setInterval(function() { GameStorage.save(true); }, \(PerformanceConfig.autosaveIntervalMs));
                    if (typeof _startBackupPollTimer === 'function') _startBackupPollTimer();
                    """)
                    debugLog("OFFLINE: timers restarted (short background, backgroundPaused = false)")
                    DispatchQueue.main.async { [self] in
                        self.startDisplayLink()
                        self.recordInteraction()
                    }
                }
            }
            return
        }

        debugLog("OFFLINE: starting simulation")

        jsQueue.async { [self] in
            autoreleasepool {
                // Respect player.options.offlineProgress (matches web storage.js:495)
                let offlineEnabled = context.evaluateScript("player.options.offlineProgress")?.toBool() ?? true
                guard offlineEnabled else {
                    debugLog("OFFLINE: offlineProgress disabled, skipping simulation")
                    backgroundPaused = false
                    context.evaluateScript("""
                        player.lastUpdate = Date.now();
                        GameStorage.postLoadStuff();
                        if (typeof _startGameLoopTimer !== 'undefined') { _startGameLoopTimer(); }
                        _autosaveTimerID = setInterval(function() { GameStorage.save(true); }, \(PerformanceConfig.autosaveIntervalMs));
                        if (typeof _startBackupPollTimer === 'function') _startBackupPollTimer();
                        """)
                    DispatchQueue.main.async { [self] in
                        self.startDisplayLink()
                        self.recordInteraction()
                    }
                    pollDirect()
                    return
                }
                // Game loop already paused in recordBackgroundEntry
                context.evaluateScript("if (typeof _gameLoopTimerID !== 'undefined') { clearInterval(_gameLoopTimerID); clearInterval(_autosaveTimerID); clearInterval(_backupTimerID); }")
                context.evaluateScript("ui.view.modal.progressBar = undefined;")
                runOfflineSimulation(elapsed: elapsed, isStartup: false)
            }
        }
    }

    // MARK: - Away snapshot helpers

    private struct AwaySnapshot {
        let antimatter: String
        let dimensionBoosts: Int
        let galaxies: Int
        let infinities: String
        let infinityPoints: String
        let infinityUnlocked: Bool
        let replicanti: String
        let replicantiUnlocked: Bool
        let replicantiGalaxies: Int
    }

    private func captureAwaySnapshot() -> AwaySnapshot {
        let am = GameDecimal(from: jsCurrencyAM.forProperty("value"))
        let boosts = jsDimBoost.forProperty("purchasedBoosts")?.toInt32() ?? 0
        let galaxies = jsPlayer.forProperty("galaxies")?.toInt32() ?? 0
        let infUnlocked = jsPlayerProgress.invokeMethod("infinityUnlocked", withArguments: [])?.toBool() ?? false
        let infinities = GameDecimal(from: context.evaluateScript("Currency.infinities.value"))
        let ip = GameDecimal(from: jsCurrencyIP.forProperty("value"))

        // Replicanti
        let replUnl = jsPlayer.forProperty("replicanti")?.forProperty("unl")?.toBool() ?? false
        let replAmount = replUnl ? GameDecimal(from: jsPlayer.forProperty("replicanti")?.forProperty("amount")) : .zero
        let replGalaxies = Int(jsPlayer.forProperty("replicanti")?.forProperty("galaxies")?.toInt32() ?? 0)

        return AwaySnapshot(
            antimatter: formatDecimal(am, places: 2),
            dimensionBoosts: Int(boosts),
            galaxies: Int(galaxies),
            infinities: formatDecimal(infinities, places: 2),
            infinityPoints: formatDecimal(ip, places: 2),
            infinityUnlocked: infUnlocked,
            replicanti: formatDecimal(replAmount, places: 2),
            replicantiUnlocked: replUnl,
            replicantiGalaxies: replGalaxies
        )
    }

    private func buildAwayEntries(before: AwaySnapshot, after: AwaySnapshot) -> [AwayProgressEntry] {
        var entries: [AwayProgressEntry] = []

        // Compare formatted strings: if the user-visible value is the same,
        // there is nothing meaningful to surface. The earlier "raw" comparison
        // only checked the Decimal's exponent, which silently dropped any
        // change that didn't cross a power-of-10 boundary (e.g. IP going
        // 3.5e140 → 9.2e140 looks identical when only `e` is read).
        if before.antimatter != after.antimatter {
            entries.append(AwayProgressEntry(label: "Antimatter", before: before.antimatter, after: after.antimatter))
        }
        if before.dimensionBoosts != after.dimensionBoosts {
            entries.append(AwayProgressEntry(label: "Dimension Boosts", before: "\(before.dimensionBoosts)", after: "\(after.dimensionBoosts)"))
        }
        if before.galaxies != after.galaxies {
            entries.append(AwayProgressEntry(label: "Antimatter Galaxies", before: "\(before.galaxies)", after: "\(after.galaxies)"))
        }
        if after.infinityUnlocked {
            if before.infinities != after.infinities {
                entries.append(AwayProgressEntry(label: "Infinities", before: before.infinities, after: after.infinities))
            }
            if before.infinityPoints != after.infinityPoints {
                entries.append(AwayProgressEntry(label: "Infinity Points", before: before.infinityPoints, after: after.infinityPoints))
            }
        }
        if after.replicantiUnlocked {
            if before.replicanti != after.replicanti {
                entries.append(AwayProgressEntry(label: "Replicanti", before: before.replicanti, after: after.replicanti))
            }
            if before.replicantiGalaxies != after.replicantiGalaxies {
                entries.append(AwayProgressEntry(label: "Replicanti Galaxies", before: "\(before.replicantiGalaxies)", after: "\(after.replicantiGalaxies)"))
            }
        }

        return entries
    }

    // MARK: - Infinity actions
    func buyInfinityUpgrade(_ id: String) { jsAsync("InfinityUpgrade.\(id).purchase()") }
    func buyIPMult() { jsAsync("InfinityUpgrade.ipMult.purchase()") }
    func buyMaxIPMult() { jsAsync("InfinityUpgrade.ipMult.buyMax()") }

    // MARK: - Break Infinity actions
    func breakInfinity() {
        jsAsync("breakInfinity(); player.options.confirmations.bigCrunch = true;")
    }
    func buyBreakUpgrade(_ id: String) { jsAsync("BreakInfinityUpgrade.\(id).purchase()") }
    func unlockNextInfinityDimension() { jsAsync("InfinityDimensions.unlockNext()") }

    // MARK: - Replicanti actions
    func unlockReplicanti() { jsAsync("Replicanti.unlock()") }
    func buyReplicantiUpgrade(_ type: String) { jsAsync("ReplicantiUpgrade.\(type).purchase()") }
    func maxAllReplicantiUpgrades() {
        jsAsync("""
        for (const u of [ReplicantiUpgrade.chance, ReplicantiUpgrade.interval, ReplicantiUpgrade.galaxies]) {
            let g = 0;
            while (u.canBeBought && !u.isCapped && g++ < 10000) u.purchase();
        }
        """)
    }
    func replicantiGalaxy() {
        jsQueue.async { [weak self] in
            guard let self else { return }
            if self.confirmationEnabled("replicantiGalaxy") {
                DispatchQueue.main.async { self.pendingModal = .replicantiGalaxy }
            } else {
                self.context.evaluateScript("replicantiGalaxy(false)")
            }
        }
    }

    // MARK: - Eternity
    func requestEternity() {
        jsQueue.async { [weak self] in
            guard let self else { return }
            let canEternity = self.context.evaluateScript("Player.canEternity")?.toBool() ?? false
            guard canEternity else { return }

            // Mirror web `askEternityConfirmation()` (eternity.js:225):
            // an Eternity press while dilated routes through the ExitDilation
            // modal, not the standard eternity modal — confirming gains TP +
            // toggles dilation off via `eternity(..., switchingDilation: true)`.
            // Force-show under doom regardless of confirmation toggle, matching
            // the dilation-tab "Dilation is permanent" UX.
            let isDilated = self.jsPlayer.forProperty("dilation")?.forProperty("active")?.toBool() ?? false
            let isDoomed = self.context.evaluateScript("typeof Pelle !== 'undefined' && Pelle.isDoomed")?.toBool() ?? false
            if isDilated {
                if (isDoomed) || self.confirmationEnabled("dilation") {
                    let gain = self.context.evaluateScript("format(getTachyonGain(true), 2, 1)")?.toString() ?? "0"
                    DispatchQueue.main.async { self.pendingModal = .exitDilation(tpGain: gain) }
                } else if self.confirmationEnabled("eternity") {
                    DispatchQueue.main.async { self.pendingModal = .eternity }
                } else {
                    self.performEternity()
                }
                return
            }

            if self.confirmationEnabled("eternity") {
                DispatchQueue.main.async { self.pendingModal = .eternity }
            } else {
                self.performEternity()
            }
        }
    }

    /// Navigate to Time Studies after EC eternity (set from main, read from main)
    var pendingECNavigation = false

    /// Performs eternity on jsQueue; flags navigation if EC was running
    func performEternity() {
        let wasInEC = self.context.evaluateScript("EternityChallenge.isRunning")?.toBool() ?? false
        self.context.evaluateScript("eternity(false, false)")
        if wasInEC {
            DispatchQueue.main.async { [weak self] in
                self?.pendingECNavigation = true
            }
        }
    }

    // MARK: - Reality
    func requestReality() {
        jsQueue.async { [weak self] in
            guard let self else { return }
            let available = self.context.evaluateScript("isRealityAvailable()")?.toBool() ?? false
            guard available else { return }

            // First Reality: no glyph choice — auto-grants starting + companion glyphs
            let isFirstReality = (self.context.evaluateScript("player.realities")?.toDouble() ?? 0) == 0
            if isFirstReality {
                if self.confirmationEnabled("glyphSelection") {
                    DispatchQueue.main.async { self.pendingModal = .reality }
                } else {
                    self.context.evaluateScript("processManualReality(false, undefined)")
                }
                return
            }

            // Subsequent Realities: fetch glyph choices from JS
            let json = self.context.evaluateScript("""
                (function() {
                    var glyphs = GlyphSelection.upcomingGlyphs;
                    var result = [];
                    for (var i = 0; i < glyphs.length; i++) {
                        var g = glyphs[i];
                        var tp = g.type || 'power';
                        var sym = GLYPH_SYMBOLS[tp] || '?';
                        var col = (GameDatabase.reality.glyphTypes[tp] || GameDatabase.reality.cosmeticGlyphs[tp] || {}).color || '#888';
                        var str = g.strength || 1;
                        var rarPct = Math.min(((str - 1) * 100 / 2.5), 100);
                        var rarName = 'Common';
                        var rarCol = '#888';
                        try {
                            var rar = getRarity(str);
                            rarName = rar.name || 'Common';
                            rarCol = rar.darkColor || rar.color || '#888';
                        } catch(ex) {}
                        // Per-effect formatting via the shared helper (also
                        // used by `pollGlyphs()`). Returns effs / shortEffs /
                        // effBoostColors / effAdditionColors — all 4 arrays
                        // parallel, with `§…§` markers around values, `[…]`
                        // markers preserved for `glyphEffectStyledText`, and
                        // `{value2}` substituted when the effect has a
                        // `conversion` function.
                        var fmt = _formatGlyphEffectBlock(g);
                        var sacGain = '';
                        try { if (GlyphSacrificeHandler.canSacrifice) sacGain = format(GlyphSacrificeHandler.glyphSacrificeGain(g), 2); } catch(ex) {}
                        result.push({
                            id: i, type: tp, sym: sym, lvl: g.level, rarPct: rarPct,
                            rarName: rarName,
                            effs: fmt.effs, shortEffs: fmt.shortEffs, effCnt: fmt.effs.length,
                            effBits: (g.effects || 0),
                            effBoostColors: fmt.effBoostColors, effAdditionColors: fmt.effAdditionColors,
                            col: col, rarCol: rarCol, idx: i, sacGain: sacGain
                        });
                    }
                    return JSON.stringify(result);
                })()
                """)?.toString() ?? "[]"

            guard let data = json.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                // Fallback: auto-select
                self.context.evaluateScript("processManualReality(false, undefined)")
                return
            }

            let choices = arr.compactMap { self.parseGlyphInfo($0) }
            // RealityUpgrade(19).isEffectActive unlocks the "Sacrifice" button
            // on the selection modal (mirrors web RealityModal.vue).
            let canSac = self.context.evaluateScript("RealityUpgrade(19) && RealityUpgrade(19).isEffectActive")?.toBool() ?? false

            if choices.count <= 1 {
                // Only 1 choice (no START perk) — auto-select, show confirmation if enabled
                if self.confirmationEnabled("glyphSelection") {
                    DispatchQueue.main.async {
                        self.glyphChoices = choices
                        self.canSacrificeGlyphOnReality = canSac
                        self.pendingModal = .reality
                    }
                } else {
                    self.context.evaluateScript("processManualReality(false, undefined)")
                }
            } else if self.confirmationEnabled("glyphSelection") {
                // Multiple choices — show glyph selection sheet
                DispatchQueue.main.async {
                    self.glyphChoices = choices
                    self.canSacrificeGlyphOnReality = canSac
                    self.showGlyphSelection = true
                }
            } else {
                // Glyph-selection prompt disabled — auto-pick (Effarig filter /
                // random), matching web `reality.js` when the confirmation is off.
                self.context.evaluateScript("processManualReality(false, undefined)")
            }
        }
    }

    /// Called when user picks a glyph from the selection sheet
    /// Called from the Reality glyph-selection modal. `sacrifice` = true
    /// routes the chosen glyph to `GlyphSacrificeHandler` instead of the
    /// inventory (gated in JS by RealityUpgrade(19).isEffectActive, which
    /// we already mirror into `canSacrificeGlyphOnReality`).
    func confirmRealityWithGlyph(_ index: Int, sacrifice: Bool = false) {
        showGlyphSelection = false
        glyphChoices = []
        let sacFlag = sacrifice ? "true" : "false"
        jsQueue.async { [self] in
            self.context.evaluateScript("processManualReality(\(sacFlag), \(index))")
        }
    }

    /// Called when user cancels glyph selection
    func cancelGlyphSelection() {
        showGlyphSelection = false
        glyphChoices = []
    }

    func buyRealityUpgrade(_ id: Int) { jsAsync("RealityUpgrade(\(id)).purchase()") }
    /// Per-rebuyable autobuyer toggle (Reality Upgrade rebuyables 1-5).
    /// Unlocked via Ra V pet lv 1.
    func toggleRealityUpgradeAutobuyer(_ id: Int, on: Bool) {
        jsAsync("Autobuyer.realityUpgrade(\(id)).isActive = \(on ? "true" : "false")")
    }
    func buyImaginaryUpgrade(_ id: Int) { jsAsync("ImaginaryUpgrade(\(id)).purchase()") }
    func toggleImaginaryUpgradeLock(_ id: Int) { jsAsync("ImaginaryUpgrade(\(id)).toggleMechanicLock()") }
    func toggleImaginaryUpgradeAutobuyer(_ id: Int, on: Bool) {
        jsAsync("Autobuyer.imaginaryUpgrade(\(id)).isActive = \(on ? "true" : "false")")
    }
    func toggleBlackHoleUpgradeAutobuyer(upgradeId: Int, on: Bool) {
        jsAsync("Autobuyer.blackHolePower(\(upgradeId)).isActive = \(on ? "true" : "false")")
    }
    /// Toggle player.celestials.ra.disCharge — when true, all charged upgrades
    /// are discharged on next Reality.
    func toggleInfinityChargeRespec() {
        jsAsync("if(player && player.celestials && player.celestials.ra){player.celestials.ra.disCharge=!player.celestials.ra.disCharge;}")
    }
    func toggleAlchemyReaction(_ resourceId: Int) {
        jsAsync("_nativeAlchemyToggleReaction(\(resourceId))")
    }
    func toggleAllAlchemyReactions() {
        jsAsync("_nativeAlchemyToggleAllReactions()")
    }

    struct RealityGlyphEffectPreview: Equatable {
        let text: String
        let meetsLevel: Bool
    }

    struct RealityGlyphCreationPreview: Equatable {
        let glyphLevel: Int
        let effects: [RealityGlyphEffectPreview]
        let isDoomed: Bool
    }

    /// Pull the Reality Glyph Creation modal state (glyph level, per-effect
    /// descriptions with threshold gating, doomed flag) from JS. Mirrors
    /// `RealityGlyphCreationModal.vue`'s `update()`.
    func fetchRealityGlyphPreview(completion: @escaping (RealityGlyphCreationPreview?) -> Void) {
        jsQueue.async { [weak self] in
            guard let self else { return }
            let json = self.context.evaluateScript("""
                (function() {
                    try {
                        var lvl = AlchemyResource.reality.effectValue | 0;
                        var configs = GlyphEffects.all
                            .filter(function(e) { return e.glyphTypes.includes("reality"); })
                            .sort(function(a, b) { return a.bitmaskIndex - b.bitmaskIndex; });
                        var minIdx = configs.reduce(function(m, c) { return Math.min(m, c.bitmaskIndex); }, Infinity);
                        var effects = configs.map(function(cfg) {
                            var threshold = realityGlyphEffectLevelThresholds[cfg.bitmaskIndex - minIdx];
                            var text;
                            var meetsLevel = lvl >= threshold;
                            if (!meetsLevel) {
                                text = "(Requires Glyph level " + formatInt(threshold) + ")";
                            } else {
                                var value = cfg.effect(lvl, rarityToStrength(100));
                                text = cfg.singleDesc.replace("{value}", cfg.formatEffect(value));
                            }
                            return { text: text.replace(/\\s+/g, " ").trim(), meets: meetsLevel };
                        });
                        return JSON.stringify({
                            lvl: lvl,
                            doomed: !!(typeof Pelle !== "undefined" && Pelle.isDoomed),
                            effects: effects
                        });
                    } catch (e) { return ""; }
                })()
                """)?.toString() ?? ""
            var preview: RealityGlyphCreationPreview? = nil
            if let data = json.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let lvl = (obj["lvl"] as? Int) ?? 0
                let doomed = (obj["doomed"] as? Bool) ?? false
                let rawEffects = (obj["effects"] as? [[String: Any]]) ?? []
                let effects = rawEffects.map { RealityGlyphEffectPreview(
                    text: ($0["text"] as? String) ?? "",
                    meetsLevel: ($0["meets"] as? Bool) ?? false
                )}
                preview = RealityGlyphCreationPreview(
                    glyphLevel: lvl, effects: effects, isDoomed: doomed
                )
            }
            DispatchQueue.main.async { completion(preview) }
        }
    }

    /// Create a Reality Glyph using the current AlchemyResource.reality
    /// amount. Mirrors `RealityGlyphCreationModal.vue:createRealityGlyph`
    /// — consumes all Reality resource, sets the createdRealityGlyph
    /// flag, and surfaces the no-space modal message if the inventory
    /// is full (already wired to our Modal.message bridge).
    func createRealityGlyph() {
        jsAsync("""
            (function() {
                try {
                    if (GameCache.glyphInventorySpace.value === 0) {
                        Modal.message.show("No available inventory space; Sacrifice some Glyphs to free up space.",
                            { closeEvent: GAME_EVENT.GLYPHS_CHANGED });
                        return;
                    }
                    var lvl = AlchemyResource.reality.effectValue | 0;
                    Glyphs.addToInventory(GlyphGenerator.realityGlyph(lvl));
                    AlchemyResource.reality.amount = 0;
                    player.reality.glyphs.createdRealityGlyph = true;
                } catch (e) {}
            })()
            """)
    }

    /// Pull the two Glyph Alchemy h2p entries (Resources + Reactions) from
    /// `GameDatabase.h2p.tabs`, resolve their template-literal info functions
    /// against the current save (so formatted values like the refinement cap
    /// reflect runtime state), strip HTML, and return normalized text.
    /// Completion runs on main.
    func fetchAlchemyHelpText(completion: @escaping (_ resources: String, _ reactions: String) -> Void) {
        jsQueue.async { [weak self] in
            guard let self else { return }
            let json = self.context.evaluateScript("""
                (function() {
                    try {
                        var tabs = (GameDatabase && GameDatabase.h2p && GameDatabase.h2p.tabs) || [];
                        function find(name) {
                            for (var i = 0; i < tabs.length; i++) {
                                if (tabs[i] && tabs[i].name === name) {
                                    var info = tabs[i].info;
                                    var raw = typeof info === "function" ? info() : info;
                                    return String(raw || "")
                                        .replace(/<br\\s*\\/?>/gi, "\\n")
                                        .replace(/<[^>]+>/g, "")
                                        .replace(/[\\t ]+\\n/g, "\\n")
                                        .replace(/\\n{3,}/g, "\\n\\n")
                                        .replace(/[\\t ]{2,}/g, " ")
                                        .trim();
                                }
                            }
                            return "";
                        }
                        return JSON.stringify({
                            resources: find("Glyph Alchemy Resources"),
                            reactions: find("Glyph Alchemy Reactions")
                        });
                    } catch (e) {
                        return JSON.stringify({ resources: "", reactions: "" });
                    }
                })()
                """)?.toString() ?? "{}"
            var resources = ""
            var reactions = ""
            if let data = json.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                resources = (obj["resources"] as? String) ?? ""
                reactions = (obj["reactions"] as? String) ?? ""
            }
            DispatchQueue.main.async { completion(resources, reactions) }
        }
    }
    func buyPerk(_ id: Int) { jsAsync("Perks.find(\(id)).purchase()") }

    #if DEBUG
    /// Debug-only: directly flip a perk's bought state without consuming Perk
    /// Points or running `onPurchased`. Useful for testing visuals.
    func devTogglePerk(_ id: Int) {
        jsAsync("""
            (function() {
                var set = player.reality.perks;
                if (set.has(\(id))) {
                    set.delete(\(id));
                } else {
                    set.add(\(id));
                    EventHub.dispatch(GAME_EVENT.PERK_BOUGHT);
                }
            })()
        """)
    }
    #endif

    // Glyph actions
    func equipGlyph(_ glyphId: Int) {
        jsAsync("(function(){ var g = Glyphs.findById(\(glyphId)); var idx = Glyphs.active.indexOf(null); if (idx !== -1) Glyphs.equip(g, idx); })()")
    }
    func equipGlyphToSlot(_ glyphId: Int, slot: Int) {
        jsAsync("(function(){ var g = Glyphs.findById(\(glyphId)); if (g) Glyphs.equip(g, \(slot)); })()")
    }
    func unequipGlyph(_ slot: Int) { jsAsync("Glyphs.unequip(\(slot))") }
    /// Apply (or clear) a per-glyph cosmetic appearance — mirrors web
    /// `SingleGlyphAppearanceModal.setType`. Pass `"music"` to mark it as a Music
    /// Glyph, or `""`/`nil` to reset to the default appearance. Refuses on
    /// `fixedCosmetic` glyphs (perk-created Music Glyphs). Searches active + inventory.
    func setGlyphCosmetic(_ glyphId: Int, _ type: String?) {
        let typeArg = (type == nil || type!.isEmpty) ? "undefined" : "\"\(type!)\""
        jsAsync("""
        (function(){
          try {
            var g = (player.reality.glyphs.active || []).find(function(x){ return x && x.id === \(glyphId); })
                    || Glyphs.findById(\(glyphId));
            if (!g || g.fixedCosmetic) return;
            g.color = undefined;
            g.symbol = undefined;
            g.cosmetic = \(typeArg);
            if (typeof EventHub !== "undefined" && typeof GAME_EVENT !== "undefined")
              EventHub.dispatch(GAME_EVENT.GLYPH_VISUAL_CHANGE);
          } catch (e) {}
        })()
        """)
    }
    /// Undo the last equipped glyph — unequips it and resets resources to when
    /// it was equipped (calls Glyphs.undo() which triggers a Reality-like reset).
    func undoGlyph() { jsAsync("Glyphs.undo()") }
    func sacrificeGlyph(_ glyphId: Int) {
        // force=true because `Modal.glyphSacrifice.show()` is stubbed to a
        // no-op in modal-stub.js — passing false would trigger the JS
        // confirmation modal path and silently drop the sacrifice. The user
        // has already confirmed by tapping Sacrifice in the Swift tooltip
        // sheet (or dragging to the sacrifice drop zone), so skipping the
        // redundant confirmation is correct.
        jsAsync("GlyphSacrificeHandler.sacrificeGlyph(Glyphs.findById(\(glyphId)), true)")
    }
    func toggleGlyphRespec() { jsAsync("player.reality.respec = !player.reality.respec") }
    /// Mirrors web `EquippedGlyphs.vue` `toggleRespecIntoProtected()` — controls
    /// whether unequipped/respec'd glyphs land in protected rows or main inventory.
    func toggleRespecIntoProtected() { jsAsync("player.options.respecIntoProtected = !player.options.respecIntoProtected") }

    // Glyph inventory management
    func sortGlyphsByLevel() { jsAsync("Glyphs.sortByLevel()") }
    func sortGlyphsByPower() { jsAsync("Glyphs.sortByPower()") }
    func sortGlyphsByEffect() { jsAsync("Glyphs.sortByEffect()") }
    func sortGlyphsByScore() { jsAsync("Glyphs.sortByScore()") }
    func collapseEmptyGlyphSlots() { jsAsync("Glyphs.collapseEmptySlots()") }

    // Auto Glyph Arrangement setters
    func setGlyphAutoSort(_ mode: Int) { jsAsync("player.reality.autoSort = \(mode)") }
    func setGlyphAutoCollapse(_ on: Bool) { jsAsync("player.reality.autoCollapse = \(on)") }
    func setGlyphAutoAutoClean(_ on: Bool) { jsAsync("player.reality.autoAutoClean = \(on)") }
    func setGlyphApplyFilterToPurge(_ on: Bool) { jsAsync("player.reality.applyFilterToPurge = \(on)") }

    // CGE-8 — color glyph effect / sacrifice text. Web `player.options.glyphTextColors`.
    func setGlyphTextColors(_ on: Bool) { jsAsync("player.options.glyphTextColors = \(on)") }

    // SAC-3 — Altered Glyphs section visibility. Web stores INVERTED via
    // `player.options.hideAlterationEffects`; the UI toggle reads as "show
    // details", so the action takes the user-facing value and writes the
    // inverse to JS.
    func setAlteredGlyphDetailsShown(_ on: Bool) { jsAsync("player.options.hideAlterationEffects = \(!on)") }
    func toggleAlteredGlyphDetails() {
        jsAsync("player.options.hideAlterationEffects = !player.options.hideAlterationEffects")
    }

    /// Web `GlyphsTab.toggleAutoRestartCelestial` — mutates `player.options.retryCelestial`.
    /// Drives auto-restart of the current Celestial Reality on next prestige.
    func setRetryCelestial(_ on: Bool) { jsAsync("player.options.retryCelestial = \(on)") }

    // Remove weaker Glyphs — route through PrestigeModal when confirmation is enabled.
    // When opening the modal, run a JS-side dry run so the confirmation text can
    // show "will remove N/T Glyphs" exactly like the web modal.
    private func glyphInventoryTotal() -> Int {
        let v = context.evaluateScript("Glyphs.inventory.filter(function(g){return g !== null;}).length")
        return Int(v?.toInt32() ?? 0)
    }

    func purgeGlyphs() { purgeGlyphsInternal(harsh: false) }
    func harshPurgeGlyphs() { purgeGlyphsInternal(harsh: true) }

    private func purgeGlyphsInternal(harsh: Bool) {
        let threshold = harsh ? 1 : 5
        jsQueue.async { [self] in
            if self.confirmationEnabled("autoClean") {
                let deleted = Int(self.context.evaluateScript("Glyphs.autoClean(\(threshold), false)")?.toInt32() ?? 0)
                let total = self.glyphInventoryTotal()
                DispatchQueue.main.async {
                    self.pendingModal = .glyphPurge(harsh: harsh, deleted: deleted, total: total)
                }
            } else {
                self.context.evaluateScript("Glyphs.autoClean(\(threshold))")
            }
        }
    }

    func deleteAllUnprotectedGlyphs() {
        jsQueue.async { [self] in
            if self.confirmationEnabled("sacrificeAll") {
                let deleted = Int(self.context.evaluateScript("Glyphs.autoClean(0, false)")?.toInt32() ?? 0)
                let total = self.glyphInventoryTotal()
                DispatchQueue.main.async {
                    self.pendingModal = .deleteAllUnprotectedGlyphs(deleted: deleted, total: total)
                }
            } else {
                self.context.evaluateScript("Glyphs.autoClean(0)")
            }
        }
    }

    func deleteAllRejectedGlyphs() {
        jsQueue.async { [self] in
            if self.confirmationEnabled("sacrificeAll") {
                let deleted = Int(self.context.evaluateScript("Glyphs.deleteAllRejected(false)")?.toInt32() ?? 0)
                let total = self.glyphInventoryTotal()
                DispatchQueue.main.async {
                    self.pendingModal = .deleteAllRejectedGlyphs(deleted: deleted, total: total)
                }
            } else {
                self.context.evaluateScript("Glyphs.deleteAllRejected(true)")
            }
        }
    }
    func moveGlyphToSlot(_ glyphId: Int, targetSlot: Int) {
        jsAsync("(function(){ var g = Glyphs.findById(\(glyphId)); if (g) Glyphs.moveToSlot(g, \(targetSlot)); })()")
    }
    func addGlyphProtectedRow() { jsAsync("Glyphs.changeProtectedRows(1)") }
    func removeGlyphProtectedRow() { jsAsync("Glyphs.changeProtectedRows(-1)") }
    func moveGlyphToProtectedRow(_ glyphId: Int) {
        jsAsync("""
        (function(){
          var g = Glyphs.findById(\(glyphId));
          if (!g) return;
          var pSlots = player.reality.glyphs.protectedRows * 10;
          if (pSlots <= 0) return;
          var inv = player.reality.glyphs.inventory;
          for (var i = 0; i < pSlots; i++) {
            if (!inv.some(function(x){ return x && x.idx === i; })) {
              Glyphs.moveToSlot(g, i);
              return;
            }
          }
        })()
        """)
    }

    func resetReality() {
        jsQueue.async { [weak self] in
            guard let self else { return }
            if self.confirmationEnabled("resetReality") {
                DispatchQueue.main.async { self.pendingModal = .resetReality }
            } else {
                self.context.evaluateScript("beginProcessReality(getRealityProps(true))")
            }
        }
    }

    // Black Hole actions
    func unlockBlackHole() { jsAsync("BlackHoles.unlock()") }
    func toggleBlackHolePause() { jsAsync("BlackHoles.togglePause()") }
    /// Cycle `player.blackHoleAutoPauseMode` through NO_PAUSE → BH1 → BH2.
    /// Mirrors web `BlackHoleTab.vue` `changePauseMode` skip rules:
    ///  • from NO_PAUSE: jump 2 if BH1 is permanent (skip BH1 mode);
    ///  • from PAUSE_BEFORE_BH1: jump 2 if BH2 is not unlocked (skip BH2 mode);
    ///  • from PAUSE_BEFORE_BH2: always 1.
    func cycleBlackHoleAutoPauseMode() {
        jsAsync("""
            (function() {
                var mode = player.blackHoleAutoPauseMode | 0;
                var steps;
                if (mode === BLACK_HOLE_PAUSE_MODE.NO_PAUSE) {
                    steps = BlackHole(1).isPermanent ? 2 : 1;
                } else if (mode === BLACK_HOLE_PAUSE_MODE.PAUSE_BEFORE_BH1) {
                    steps = BlackHole(2).isUnlocked ? 1 : 2;
                } else {
                    steps = 1;
                }
                var n = Object.values(BLACK_HOLE_PAUSE_MODE).length;
                player.blackHoleAutoPauseMode = (mode + steps) % n;
            })()
            """)
    }
    func buyBlackHoleUpgrade(_ bhId: Int, type: String) {
        jsAsync("BlackHole(\(bhId)).\(type)Upgrade.purchase()")
    }
    func toggleRealityUpgradeLock(_ id: Int) { jsAsync("RealityUpgrade(\(id)).toggleMechanicLock()") }

    /// "Disable Lock" action from the upgrade requirement-lock alert: clears the mechanic lock so a
    /// retry of the blocked action succeeds. Mirrors `UpgradeMechanicLockModal.vue`'s confirm
    /// (`upgrade.setMechanicLock(false)`); does NOT perform the original action.
    func disableUpgradeLock(_ prompt: UpgradeLockPrompt) {
        let accessor = prompt.isImaginary ? "ImaginaryUpgrade" : "RealityUpgrade"
        jsAsync("(function(){ try { \(accessor)(\(prompt.upgradeId)).setMechanicLock(false); } catch (e) { if (typeof _nativeLog !== 'undefined') _nativeLog('[disableUpgradeLock] ' + e); } })()")
        activeUpgradeLock = nil
    }

    // MARK: - Infinity Dimensions
    func buyInfinityDimension(_ tier: Int) { jsAsync("InfinityDimension(\(tier)).buySingle()") }
    func buyMaxInfinityDimension(_ tier: Int) { jsAsync("InfinityDimension(\(tier)).buyMax(false)") }
    func maxAllInfinityDimensions() { jsAsync("InfinityDimensions.buyMax()") }
    func buyTesseract() { jsAsync("_nativeBuyTesseract()") }

    // Time Dimension actions
    func buyTimeDimension(_ tier: Int) { jsAsync("buySingleTimeDimension(\(tier))") }
    func buyMaxTimeDimension(_ tier: Int) { jsAsync("buyMaxTimeDimension(\(tier))") }
    func maxAllTimeDimensions() { jsAsync("maxAllTimeDimensions()") }
    func tryUnlockTimeDimension(_ tier: Int) { jsAsync("TimeDimension(\(tier)).tryUnlock()") }
    func toggleTimeDimensionAutobuyer(_ tier: Int) { jsAsync("Autobuyer.timeDimension(\(tier)).toggle()") }
    func toggleAllTimeDimensionAutobuyers() { jsAsync("toggleAllTimeDims()") }

    // Eternity Upgrade actions
    func buyEternityUpgrade(_ key: String) { jsAsync("EternityUpgrade.\(key).purchase()") }
    func buyEPMult() { jsAsync("EternityUpgrade.epMult.purchase()") }
    func buyMaxEPMult() { jsAsync("EternityUpgrade.epMult.buyMax(false)") }
    func toggleEPMultAutobuyer() { jsAsync("Autobuyer.epMult.toggle()") }
    func toggleTTAutobuyer() { jsAsync("Autobuyer.timeTheorem.toggle()") }

    // Auto Eternity Challenge toggle — gated on `Perk.autocompleteEC1.canBeApplied`.
    func setAutoEC(_ enabled: Bool) {
        jsAsync("player.reality.autoEC = \(enabled ? "true" : "false")")
    }

    // "Show all known challenges" — gated on Eternity unlock. Affects EC + IC
    // grid visibility (web `ChallengeTabHeader.vue` + per-tab `isChallengeVisible`).
    func setShowAllChallenges(_ enabled: Bool) {
        jsAsync("player.options.showAllChallenges = \(enabled ? "true" : "false")")
    }

    // Eternity Challenge actions
    func startEternityChallenge(_ id: Int) {
        jsQueue.async { [self] in
            autoreleasepool {
                if self.confirmationEnabled("challenges") {
                    DispatchQueue.main.async { self.pendingModal = .eternityChallenge(id) }
                } else {
                    self.context.evaluateScript("EternityChallenge(\(id)).requestStart()")
                }
            }
        }
    }

    // IP Mult autobuyer actions
    func toggleIPMultAutobuyer() { jsAsync("Autobuyer.ipMult.toggle()") }

    // Replicanti autobuyer actions
    func toggleReplicantiGalaxyAutobuyer() { jsAsync("Autobuyer.replicantiGalaxy.isActive = !Autobuyer.replicantiGalaxy.isActive") }
    func toggleReplicantiUpgradeAutobuyer(_ id: Int) { jsAsync("Autobuyer.replicantiUpgrade(\(id)).isActive = !Autobuyer.replicantiUpgrade(\(id)).isActive") }
    func toggleReplicantiUpgradeAutobuyerGroup() { jsAsync("player.auto.replicantiUpgrades.isActive = !player.auto.replicantiUpgrades.isActive") }

    // Eternity autobuyer actions
    func toggleEternityAutobuyer() { jsAsync("Autobuyer.eternity.toggle()") }
    func setEternityAutobuyerMode(_ mode: Int) { jsAsync("Autobuyer.eternity.mode = \(mode)") }
    func setEternityAutobuyerAmount(_ value: String) {
        let safe = value.replacingOccurrences(of: "'", with: "")
        jsAsync("Autobuyer.eternity.amount = new Decimal('\(safe)')")
    }
    func setEternityAutobuyerTime(_ value: Double) {
        jsAsync("Autobuyer.eternity.time = \(value)")
    }
    func setEternityAutobuyerXHighest(_ value: String) {
        let safe = value.replacingOccurrences(of: "'", with: "")
        jsAsync("Autobuyer.eternity.xHighest = new Decimal('\(safe)')")
    }

    // Reality autobuyer actions
    func toggleRealityAutobuyer()          { jsAsync("Autobuyer.reality.toggle()") }
    func setRealityAutobuyerMode(_ m: Int) { jsAsync("Autobuyer.reality.mode = \(m)") }
    func setRealityAutobuyerRM(_ value: String) {
        let safe = value.replacingOccurrences(of: "'", with: "")
        jsAsync("Autobuyer.reality.rm = new Decimal('\(safe)')")
    }
    func setRealityAutobuyerGlyph(_ value: Int)   { jsAsync("Autobuyer.reality.glyph = \(value)") }
    func setRealityAutobuyerTime(_ value: Double) { jsAsync("Autobuyer.reality.time = \(value)") }
    func setRealityAutobuyerShard(_ value: String) {
        let safe = value.replacingOccurrences(of: "'", with: "")
        jsAsync("Autobuyer.reality.shard = new Decimal('\(safe)')")
    }

    // Time Study actions
    func buyTimeStudy(_ id: Int) { jsAsync("TimeStudy(\(id)).purchase()") }
    func buyECStudy(_ id: Int) { jsAsync("TimeStudy.eternityChallenge(\(id)).purchase()") }
    func buyDilationStudy() { jsAsync("TimeStudy.dilation.purchase()") }
    func buyTDStudy(_ tier: Int) { jsAsync("TimeStudy.timeDimension(\(tier)).purchase()") }
    func buyRealityStudy() { jsAsync("TimeStudy.reality.purchase()") }
    func purchaseStudiesUntil(_ id: Int) {
        if id > 0 {
            jsAsync("TimeStudy(\(id)).purchaseUntil()")
        } else if id >= -12 && id < 0 {
            jsAsync("TimeStudy.eternityChallenge(\(-id)).purchaseUntil()")
        } else if id == -200 {
            jsAsync("TimeStudy.reality.purchase()")
        }
    }
    /// Writes the full ordered Dimension-path priority list (web stores up to 2). Values are
    /// filtered to valid path ids (1=Antimatter, 2=Infinity, 3=Time), mirroring the web setter.
    func setPreferredDimPaths(_ paths: [Int]) {
        let arr = paths.filter { (1...3).contains($0) }.map(String.init).joined(separator: ",")
        jsAsync("(function(){ player.timestudy.preferredPaths[0] = [\(arr)]; })()")
    }
    func setPreferredPacePath(_ path: Int) {
        jsAsync("(function(){ player.timestudy.preferredPaths[1] = \(path); })()")
    }
    func buyTimeTheorem(_ type: String) { jsAsync("TimeTheorems.buyOne(false, '\(type)')") }
    func buyMaxTimeTheorems() { jsAsync("TimeTheorems.buyMax(false)") }
    func respecTimeStudies() { jsAsync("player.respec = !player.respec") }
    func exportStudies() -> String {
        var result = ""
        jsQueue.sync { autoreleasepool {
            let val = self.context.evaluateScript("GameCache.currentStudyTree.value.exportString")
            if let str = val?.toString(), str != "undefined" {
                result = str
            }
        }}
        return result
    }
    func importStudies(_ input: String, respecAndEternity: Bool = false) {
        let safe = input.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\\", with: "")
        if respecAndEternity {
            jsAsync("""
                (function(){
                    if (!Player.canEternity) return;
                    player.respec = true;
                    var t = new TimeStudyTree(TimeStudyTree.truncateInput('\(safe)'));
                    eternity(false, false);
                    TimeStudyTree.commitToGameState(t.purchasedStudies, false, t.startEC);
                })()
                """)
        } else {
            jsAsync("""
                (function(){
                    var t = new TimeStudyTree();
                    t.attemptBuyArray(TimeStudyTree.currentStudies, false);
                    t.attemptBuyArray(t.parseStudyImport('\(safe)'), true);
                    TimeStudyTree.commitToGameState(t.purchasedStudies, false, t.startEC);
                })()
                """)
        }
    }

    // Study preset actions
    func saveStudyPreset(_ slot: Int) {
        jsAsync("player.timestudy.presets[\(slot)].studies = GameCache.currentStudyTree.value.exportString")
    }
    func loadStudyPreset(_ slot: Int) {
        jsAsync("""
            (function(){
                var p = player.timestudy.presets[\(slot)];
                if (!p.studies) return;
                var t = new TimeStudyTree();
                t.attemptBuyArray(TimeStudyTree.currentStudies, false);
                t.attemptBuyArray(t.parseStudyImport(p.studies), true);
                TimeStudyTree.commitToGameState(t.purchasedStudies, false, t.startEC);
            })()
            """)
    }
    func deleteStudyPreset(_ slot: Int) {
        jsAsync("(function(){ var p = player.timestudy.presets[\(slot)]; p.name = ''; p.studies = ''; })()")
    }
    func renameStudyPreset(_ slot: Int, name: String) {
        let safe = String(name.prefix(4)).filter { $0.asciiValue != nil }
        jsAsync("player.timestudy.presets[\(slot)].name = '\(safe)'")
    }
    func setStudyPresetString(_ slot: Int, studies: String) {
        let safe = studies.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\\", with: "")
        jsAsync("player.timestudy.presets[\(slot)].studies = '\(safe)'")
    }
    func exportStudyPreset(_ slot: Int) -> String {
        var result = ""
        jsQueue.sync {
            result = context.evaluateScript("player.timestudy.presets[\(slot)].studies")?.toString() ?? ""
        }
        return result
    }

    /// Evaluate a study string and return preview info (synchronous, runs on jsQueue)
    func previewStudyString(_ input: String) -> StudyPreviewInfo {
        let safe = input.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\\", with: "")
        var result = StudyPreviewInfo.empty
        jsQueue.sync { autoreleasepool {
            let raw = self.context.evaluateScript("""
                (function(){
                    var input = '\(safe)';
                    var truncated = TimeStudyTree.truncateInput(input);
                    if (!truncated || !TimeStudyTree.isValidImportString(truncated))
                        return JSON.stringify({valid:false});

                    function studyStr(s) { return s.id !== undefined ? (s.challenge ? 'EC'+s.id : ''+s.id) : ''+s; }
                    function pathNames(tree) {
                        var d = tree.dimensionPaths || [];
                        var p = tree.pacePaths || [];
                        return {dim: d.join(', '), pace: p.join(', ')};
                    }

                    // Empty tree import
                    var empty = new TimeStudyTree(truncated);
                    var eStudies = empty.purchasedStudies.map(studyStr);
                    var ePaths = pathNames(empty);
                    // Study IDs for preview (positive for normal, negative for EC)
                    var eIDs = empty.purchasedStudies.map(function(s){
                        return s.challenge ? -s.id : s.id;
                    });

                    // Combined tree import
                    var combined = new TimeStudyTree();
                    combined.attemptBuyArray(TimeStudyTree.currentStudies, false);
                    var currentSet = new Set(combined.purchasedStudies.map(function(s){ return s; }));
                    combined.attemptBuyArray(combined.parseStudyImport(truncated), true);
                    var cNew = combined.purchasedStudies.filter(function(s){ return !currentSet.has(s); }).map(studyStr);
                    var cPaths = pathNames(combined);

                    return JSON.stringify({
                        valid: true,
                        eStudies: eStudies.join(', '), eTT: empty.spentTheorems[0],
                        eDim: ePaths.dim, ePace: ePaths.pace,
                        eEC: empty.ec, eStartEC: empty.startEC,
                        cStudies: cNew.join(', '), cTT: combined.spentTheorems[0],
                        cDim: cPaths.dim, cPace: cPaths.pace,
                        cEC: combined.ec, cStartEC: combined.startEC,
                        ids: eIDs
                    });
                })()
                """)?.toString() ?? "{}"

            if let data = raw.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["valid"] as? Bool == true {
                let ids = (json["ids"] as? [Any])?.compactMap { ($0 as? NSNumber)?.intValue } ?? []
                result = StudyPreviewInfo(
                    isValid: true,
                    emptyStudies: json["eStudies"] as? String ?? "",
                    emptyCostTT: json["eTT"] as? Int ?? 0,
                    emptyDimPaths: json["eDim"] as? String ?? "",
                    emptyPacePaths: json["ePace"] as? String ?? "",
                    emptyEC: json["eEC"] as? Int ?? 0,
                    emptyStartEC: json["eStartEC"] as? Bool ?? false,
                    combinedStudies: json["cStudies"] as? String ?? "",
                    combinedCostTT: json["cTT"] as? Int ?? 0,
                    combinedDimPaths: json["cDim"] as? String ?? "",
                    combinedPacePaths: json["cPace"] as? String ?? "",
                    combinedEC: json["cEC"] as? Int ?? 0,
                    combinedStartEC: json["cStartEC"] as? Bool ?? false,
                    previewStudyIDs: ids
                )
            }
        }}
        return result
    }

    // Dilation actions
    func requestDilation() {
        jsQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                // Mirror `startDilatedEternityRequest()`: in Pelle's Doomed
                // Reality, starting dilation requires `Pelle.canDilateInPelle`
                // (≥ 3.8e7 Remnants). Toggling off / re-entering while already
                // dilated is allowed.
                let isActive = self.jsPlayer.forProperty("dilation")?.forProperty("active")?.toBool() ?? false
                let isDoomed = self.context.evaluateScript("typeof Pelle !== 'undefined' && Pelle.isDoomed")?.toBool() ?? false
                if !isActive {
                    let blocked = isDoomed && !(self.context.evaluateScript("Pelle.canDilateInPelle")?.toBool() ?? false)
                    if blocked { return }
                }
                // Gate the modal purely on `player.options.confirmations.dilation`,
                // matching web `startDilatedEternityRequest()` — which shows
                // `Modal.exitDilation` / `Modal.enterDilation` ONLY when the
                // confirmation is enabled, regardless of doom. The doomed
                // `.exitDilation` modal is just informational copy ("Dilation is
                // permanent") on the same confirmable action; when the user has
                // turned the confirmation off (via the modal's "don't show again"
                // toggle → `setConfirmation("dilation", false)`), we must skip
                // straight to the action like web does. A prior `forceModal`
                // override here ignored the preference, so the modal kept
                // reappearing while doomed and "don't show again" had no effect.
                if self.confirmationEnabled("dilation") {
                    if isActive {
                        let gain = self.context.evaluateScript("format(getTachyonGain(true), 2, 1)")?.toString() ?? "0"
                        DispatchQueue.main.async { self.pendingModal = .exitDilation(tpGain: gain) }
                    } else {
                        DispatchQueue.main.async { self.pendingModal = .enterDilation }
                    }
                } else {
                    self.context.evaluateScript("startDilatedEternity()")
                }
            }
        }
    }
    func buyDilationUpgrade(_ id: Int) { jsAsync("DilationUpgrades.fromId(\(id)).purchase()") }
    func toggleDilationUpgradeAutobuyer(_ id: Int) { jsAsync("Autobuyer.dilationUpgrade(\(id)).toggle()") }
    func buyMaxDilationUpgrade(_ id: Int) { jsAsync("DilationUpgrades.fromId(\(id)).buyMax()") }

    func toggleEternityAutobuyerDynamic() {
        jsAsync("Autobuyer.eternity.increaseWithMult = !Autobuyer.eternity.increaseWithMult")
    }

    // MARK: - Save import / export

    func exportSave() {
        jsQueue.async { [self] in
            autoreleasepool {
                let save = self.context.evaluateScript("GameStorage.exportModifiedSave()")?.toString() ?? ""
                DispatchQueue.main.async {
                    UIPasteboard.general.string = save
                    self.enqueueToast(type: "info", text: String(localized: "Save exported to clipboard"))
                }
            }
        }
    }

    func importSave(_ saveData: String) {
        let escaped = saveData.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        jsQueue.async { [self] in
            autoreleasepool {
                // Stop ALL timers before import
                self.stopAllGameTimersJS()
                let result = self.context.evaluateScript("""
                    (function() {
                        var save = GameSaveSerializer.deserialize(`\(escaped)`);
                        if (!save || GameStorage.checkPlayerObject(save) !== '') return 'invalid';
                        // Disable offline simulation — Swift handles foreground return separately
                        GameStorage.offlineEnabled = false;
                        GameStorage.import(`\(escaped)`);
                        return 'ok';
                    })()
                    """)?.toString() ?? "error"
                if result == "ok" {
                    // postLoadStuff() inside loadPlayerObject may have restarted GameIntervals;
                    // restartAllGameTimersJS stops them and restores only our custom timer trio.
                    self.restartAllGameTimersJS()
                    self.context.evaluateScript("player.options.hibernationCatchup = false;")
                    // Update persisted lastUpdate for cold-start detection
                    let lastUpdate = self.context.evaluateScript("player.lastUpdate")?.toDouble() ?? 0
                    if lastUpdate > 0 { UserDefaults.standard.set(lastUpdate, forKey: "am_lastUpdate") }
                    self.cacheJSRefs()
                    self.setupNewsHelpers()
                    self.setupCelestialHelpers()
                    self.setupGameEndHelpers()
                    self.setupAutomatorHelpers()
                    self.setupSaveHelpers()
                    self.setupGlyphPresetHelpers()
                    self.setupSpeedrunHelpers()
                    self.setupPerksHelper()
                    self.setupTimeStudiesHelper()
                    self.setupGlyphEffectFormatHelper()
                    self.setupHeaderTickHelper()
                    self.setupStatisticsAndRelatedHelpers()
                    self.setupSecretAchievementsHelper()
                    self.pollDirect()
                    // Reset unlock flags AFTER pollDirect's commit is dispatched
                    // so this runs LAST on main — matches hardReset / startSpeedrun.
                    // pollDirect's sticky-true block also skips itself when its
                    // captured `unlockFlagsGen` is stale, but ordering this last
                    // is belt-and-suspenders + self-documenting.
                    DispatchQueue.main.async {
                        self.resetUnlockFlags()
                        self.enqueueToast(type: "info", text: String(localized: "Save imported successfully"))
                    }
                } else {
                    // Import failed — restart the custom timers so the live
                    // game keeps ticking. stopAllGameTimersJS killed them
                    // pre-import; without this, the game freezes.
                    self.restartAllGameTimersJS()
                    DispatchQueue.main.async {
                        self.enqueueToast(type: "error", text: String(localized: "Could not import save (invalid format)"))
                    }
                }
            }
        }
    }

    /// Reset all tab-visibility unlock flags to false. Called from explicit
    /// reset paths (hardReset, importSave, switchSlot, restoreBackup) where
    /// the game state is being replaced wholesale. pollDirect() only propagates
    /// true transitions for these flags (to avoid flicker during Reality/Eternity),
    /// so this method is the only way to set them back to false.
    /// Must be called on main thread (or dispatched to main).
    func resetUnlockFlags() {
        // Bump the generation counter FIRST, before zeroing the flags. Any
        // pollDirect commit closure on main that was queued with a now-stale
        // capturedGen will read this updated value and skip its sticky-true
        // unlock-flag block, so it can't re-assert flags that we're about
        // to clear. See `unlockFlagsGen` for the full race explanation.
        unlockFlagsGen &+= 1
        infinityUnlocked = false
        autobuyersUnlocked = false
        tickspeedUnlocked = false
        replicantiUnlocked = false
        infinityDimsUnlocked = false
        eternityUnlocked = false
        dilationUnlocked = false
        eternityChallengesUnlocked = false
        realityUnlocked = false
        realityStudyBought = false
        teresaUnlocked = false
        effarigUnlocked = false
        effarigEternityUnlocked = false
        vUnlocked = false
        raUnlocked = false
        imaginaryUpgradesUnlocked = false
        glyphAlchemyUnlocked = false
        laitelaUnlocked = false
        pelleUnlocked = false
        pelleDoomed = false
        pelleCanArmageddon = false
        pelleRemnantsGainText = ""
        pelleRealityShardsText = "0"
        pelleRealityShardsPerSecText = "0/s"
        pelleRealityShardsRateAfterText = "0/s"
        pelleGlyphEquippingDisabled = false
        endStateValue = 0
        gameEndCreditsClosed = false
        blackHolesHeaderVisible = false
        headerEnslavedChargeVisible = false
        headerEnslavedIsCharging = false
        headerCanPulse = false
        headerIsPulsing = false
        headerCanDischarge = false
        headerStoredTimeText = "0s"
        headerPulsedSpeedText = ""
        headerIsGameSpeedPulsing = false
        enslavedIsRunning = false
        enslavedHasSecretStudy = false
        enslavedFeltEternity = false
        enslavedCompleted = false
        enslavedHintTimerVisible = false
        enslavedHintTimerText = ""
        tesseractAffordable = false
        enslavedHints = nil
        currentCelestialReality = ""
        realityButtonSpecial = false
    }

    func hardReset(sidebarState: SidebarState) {
        // Eagerly zero the derived unlock flags on the main thread so the tab
        // bar collapses immediately when the user confirms. Without this,
        // progression tabs (Automation/Challenges/Infinity/Eternity/Reality/
        // Celestials) stay visible until pollDirect's main dispatch lands,
        // and on iPhone that first visible page (Dims/Auto/Challenge/
        // Infinity/Eternity) obscures the Options tab they just left.
        // pollDirect runs right after the JS reset and will re-populate these
        // flags from the fresh player state — same final values, no extra
        // work — but the user sees the correct tab bar without a flicker.
        DispatchQueue.main.async { [self] in
            self.resetUnlockFlags()
            sidebarState.selectSubtab(.antimatterDimensions, in: .dimensions, engine: self)
        }

        jsQueue.async { [self] in
            autoreleasepool {
                // Stop all timers before reset
                self.stopAllGameTimersJS()
                // Load default player and save
                self.context.evaluateScript("GameStorage.hardReset()")
                // GameStorage.hardReset only calls loadPlayerObject — it
                // does NOT load fresh backup metadata or reset
                // player.backupTimer. So `lastBackupTimes` retains
                // whatever was loaded for the slot, with high values
                // from the pre-reset save, while the new player's
                // backupTimer is back to 0. tryOnlineBackups then
                // computes a hugely negative `timeSinceLast` and never
                // fires. Reload backup times for the slot and
                // fast-forward backupTimer past any existing entries —
                // same fix shape as _nativeSwitchSlot / import().
                self.context.evaluateScript("""
                    if (typeof GameStorage !== 'undefined') {
                        if (typeof GameStorage.loadBackupTimes === 'function') GameStorage.loadBackupTimes();
                        if (typeof GameStorage.resetBackupTimer === 'function') GameStorage.resetBackupTimer();
                    }
                """)
                UserDefaults.standard.removeObject(forKey: "am_lastUpdate")
                // Restart timers
                self.restartAllGameTimersJS()
                self.context.evaluateScript("player.options.hibernationCatchup = false;")
                self.cacheJSRefs()
                self.setupNewsHelpers()
                self.setupCelestialHelpers()
                self.setupGameEndHelpers()
                self.setupAutomatorHelpers()
                self.setupSaveHelpers()
                self.setupGlyphPresetHelpers()
                self.setupSpeedrunHelpers()
                self.setupPerksHelper()
                self.setupTimeStudiesHelper()
                self.setupGlyphEffectFormatHelper()
                self.setupHeaderTickHelper()
                self.setupStatisticsAndRelatedHelpers()
                self.setupSecretAchievementsHelper()
                self.pollDirect()
                DispatchQueue.main.async {
                    // Re-zero unlock flags HERE (not just in the eager
                    // main.async at the top). A regular CADisplayLink
                    // pollDirect that was already in flight when the user
                    // tapped Hard Reset will dispatch its commit closure to
                    // main carrying pre-reset JS state; if that closure
                    // lands AFTER the eager resetUnlockFlags, its
                    // `if header.X && !self.X { self.X = true }` line
                    // re-asserts the flag (because we just set self.X to
                    // false, and the captured header.X is still the OLD
                    // true). The user sees Eternity/Infinity/Auto tabs
                    // never disappear post-reset. By queuing this
                    // resetUnlockFlags AFTER our own post-reset pollDirect,
                    // it lands LAST on main and definitively zeros the
                    // flags. Same reasoning applies to selectSubtab —
                    // a stray commit could overwrite poll-dependent
                    // header state, but the toast + tab nav are safe to
                    // re-affirm.
                    self.resetUnlockFlags()
                    sidebarState.selectSubtab(.antimatterDimensions, in: .dimensions, engine: self)
                    self.enqueueToast(type: "info", text: String(localized: "Game has been reset"))
                }
            }
        }
    }

    // MARK: - Header late-tick helper

    /// Inject `_nativeHeaderLateTickReads()` from `header-tick-helper.js`.
    /// Coalesces 11 small per-tick evals (sidebar currency cycle, tachyon gain,
    /// EP-threshold check, EC-any-completion) into one helper call that gates
    /// each section on flags from Swift. No caching — every field is volatile;
    /// this is pure trampoline reduction. See the JS file header for details.
    internal func setupHeaderTickHelper() {
        guard let url = Bundle.main.url(forResource: "header-tick-helper", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            print("🔴 GameEngine: missing header-tick-helper.js in app bundle")
            return
        }
        _ = context.evaluateScript(source)
    }

    // MARK: - Perks helper

    /// Inject `_nativePerksState()` from `perks-helper.js`. Cached + event-
    /// invalidated rebuild of the 48-perk JSON payload — most ticks return a
    /// cached string instead of rebuilding the whole list. See the JS file
    /// header for invalidation rules. Idempotent; re-injected on every save-
    /// lifecycle entry point alongside the other helpers.
    ///
    /// DEBUG builds set `_nativePerksValidateEvery = 30` so once per second
    /// the helper rebuilds fresh and compares against its cached output,
    /// logging any drift via `_nativeLog`. Release leaves the flag unset
    /// (zero overhead).
    internal func setupPerksHelper() {
        guard let url = Bundle.main.url(forResource: "perks-helper", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            print("🔴 GameEngine: missing perks-helper.js in app bundle")
            return
        }
        _ = context.evaluateScript(source)
        #if DEBUG
        // 30 ticks ≈ 1 second at the default polling rate.
        _ = context.evaluateScript("globalThis._nativePerksValidateEvery = 30;")
        #endif
    }

    // MARK: - Secret Achievements helper

    /// Inject `_nativeSecretAchievementsState()` + `_nativeUnlockSecretAchievement(id)`
    /// from `secret-achievements-helper.js`. Cached + event-invalidated rebuild
    /// of the 32-entry secret-achievement payload. See the JS file header for
    /// the invalidation event list. Idempotent — re-injected on every save-
    /// lifecycle entry point alongside the other helpers.
    internal func setupSecretAchievementsHelper() {
        guard let url = Bundle.main.url(forResource: "secret-achievements-helper", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            print("🔴 GameEngine: missing secret-achievements-helper.js in app bundle")
            return
        }
        _ = context.evaluateScript(source)
    }

    // MARK: - Time Studies helper

    /// Inject `_nativeTimeStudiesState()` from `time-studies-helper.js`.
    /// Cached descriptions + per-call volatile fields for ~76 studies. Replaces
    /// the per-study evaluateScript + Swift-side NSRegex normalization that
    /// dominated `pollTimeStudies` in profiling. See the JS file header for
    /// the full invalidation event list. Idempotent — re-injected at every
    /// save-lifecycle entry point alongside the other helpers.
    ///
    /// DEBUG builds set `_nativeTimeStudiesValidateEvery = 30` so once per
    /// second the helper rebuilds the description cache fresh and compares
    /// against the cached one, logging any drift via `_nativeLog`. Release
    /// leaves the flag unset (zero overhead).
    internal func setupTimeStudiesHelper() {
        guard let url = Bundle.main.url(forResource: "time-studies-helper", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            print("🔴 GameEngine: missing time-studies-helper.js in app bundle")
            return
        }
        _ = context.evaluateScript(source)
        #if DEBUG
        _ = context.evaluateScript("globalThis._nativeTimeStudiesValidateEvery = 30;")
        #endif
    }

    // MARK: - Glyph effect formatting helper

    /// Inject `_formatGlyphEffectBlock(g)` from `glyph-effect-format-helper.js`.
    /// Pure JS function (no state, no event listeners) shared between
    /// `pollGlyphs()` (Glyphs tab) and `requestReality()` (Reality modal).
    /// Single source of truth for filtering bitmask-overlapping effects,
    /// formatting values, detecting EMPOWER/BOOST/ADDITION alterations,
    /// computing `{value2}`, and emitting `§…§` value markers + `[…]` bracket
    /// markers consumed by Swift's `glyphEffectStyledText` renderer.
    /// Idempotent — re-injected at every save-lifecycle entry point alongside
    /// the other helpers.
    internal func setupGlyphEffectFormatHelper() {
        guard let url = Bundle.main.url(forResource: "glyph-effect-format-helper", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            print("🔴 GameEngine: missing glyph-effect-format-helper.js in app bundle")
            return
        }
        _ = context.evaluateScript(source)
    }

    // MARK: - News ticker

    /// Inject JS helper functions for the news ticker.
    /// Must be called on jsQueue after cacheJSRefs().
    internal func setupNewsHelpers() {
        context.evaluateScript("""
            (function() {
                var recentTickers = [];

                globalThis._nativeGetNextNews = function() {
                    var news = GameDatabase.news;
                    var repeatBuffer = player.options.news.repeatBuffer || 40;

                    function canShow(msg) {
                        return (msg.unlocked === undefined || msg.unlocked) &&
                               recentTickers.indexOf(msg.id) === -1;
                    }

                    var selected;
                    var isAI = Math.random() < (player.options.news.AIChance || 0);
                    var pool = news.filter(function(m) {
                        return m.id.indexOf('ai') !== -1 === isAI && canShow(m);
                    });
                    if (pool.length === 0) {
                        pool = news.filter(function(m) { return canShow(m); });
                    }
                    if (pool.length === 0) {
                        recentTickers = [];
                        pool = news.filter(function(m) {
                            return (m.unlocked === undefined || m.unlocked);
                        });
                    }
                    selected = pool[Math.floor(Math.random() * pool.length)];

                    recentTickers.push(selected.id);
                    while (recentTickers.length > repeatBuffer) recentTickers.shift();

                    if (selected.reset) selected.reset();

                    var text = selected.text;
                    text = text.replace(/<[^>]*>/g, '');
                    text = text.replace(/\\s+/g, ' ').trim();

                    return JSON.stringify({
                        id: selected.id,
                        text: text,
                        hasOnClick: typeof selected.onClick === 'function'
                    });
                };

                globalThis._nativeNewsScrolled = function(id) {
                    NewsHandler.addSeenNews(id);
                    if (NewsHandler.uniqueTickersSeen >= 50) Achievement(22).unlock();
                };

                globalThis._nativeNewsClick = function(id) {
                    var msg = GameDatabase.news.find(function(m) { return m.id === id; });
                    if (!msg || typeof msg.onClick !== 'function') return '';
                    SecretAchievement(24).unlock();
                    var result = msg.onClick();
                    if (result !== undefined) {
                        return result.replace(/<[^>]*>/g, '');
                    }
                    return '';
                };
            })();
        """)
    }

    /// Request the next news message from the JS game core.
    /// Calls completion on main thread with (id, text, hasOnClick).
    func requestNextNewsMessage(completion: @escaping (String, String, Bool) -> Void) {
        jsQueue.async { [self] in
            autoreleasepool {
                let json = self.context.evaluateScript("_nativeGetNextNews()")?.toString() ?? "{}"
                guard let data = json.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let id = obj["id"] as? String,
                      let text = obj["text"] as? String else {
                    DispatchQueue.main.async { completion("", "Loading...", false) }
                    return
                }
                let hasOnClick = obj["hasOnClick"] as? Bool ?? false
                DispatchQueue.main.async { completion(id, text, hasOnClick) }
            }
        }
    }

    /// Mark a news message as seen (triggers Achievement 22 check in JS).
    func newsMessageScrolled(_ id: String) {
        let safe = id.replacingOccurrences(of: "'", with: "\\'")
        jsAsync("_nativeNewsScrolled('\(safe)')")
    }

    /// Handle a tap on a clickable news message.
    func newsMessageClicked(_ id: String, completion: @escaping (String?) -> Void) {
        let safe = id.replacingOccurrences(of: "'", with: "\\'")
        jsQueue.async { [self] in
            autoreleasepool {
                let result = self.context.evaluateScript("_nativeNewsClick('\(safe)')")?.toString() ?? ""
                let updated: String? = result.isEmpty ? nil : result
                DispatchQueue.main.async { completion(updated) }
            }
        }
    }

    /// Toggle news ticker visibility.
    func toggleNewsEnabled() {
        jsAsync("GameOptions.toggleNews()")
    }

    /// Writes `player.reality.autoAchieve`. While true, the achievement
    /// timer (`player.reality.achTimer`) consumes one `Achievements.period`
    /// per pre-Reality achievement to auto-unlock waiting rows. While false,
    /// the timer caps at the period and unlocks nothing.
    func setAutoAchieve(_ on: Bool) {
        jsAsync("player.reality.autoAchieve = \(on)")
    }

    /// Tap-to-unlock for SecretAchievement(11) — "The first one's always free".
    /// Mirrors web `SecretAchievement.vue` `@click="if (id===11) unlock()"`.
    /// No-op if already unlocked. JS bridge guards against missing/undefined ids.
    func unlockSecretAchievement11() {
        jsAsync("if (typeof _nativeUnlockSecretAchievement !== 'undefined') _nativeUnlockSecretAchievement(11);")
    }

    /// Try-to-buy-the-9th-dimension easter egg. Mirrors web `hotkeys.js:298`
    /// (keystroke "9" binding) — fires SecretAchievement(41) "That dimension
    /// doesn't exist". iOS surfaces this as a tap-only target rather than a
    /// hardware-keyboard hotkey because most iOS players don't have one.
    func tryPurchaseNinthDimension() {
        jsAsync("SecretAchievement(41).unlock();")
    }

    /// Reveal the secret time study (Time Studies tab) and unlock
    /// SecretAchievement(21). Mirrors `SecretTimeStudy.vue`'s click-when-
    /// invisible branch — sets `player.secretUnlocks.viewSecretTS = true`
    /// and fires the achievement. No-op if already visible.
    func revealSecretTimeStudy() {
        jsAsync("""
        if (!player.secretUnlocks.viewSecretTS) {
            player.secretUnlocks.viewSecretTS = true;
            SecretAchievement(21).unlock();
        }
        """)
    }

    /// Hide the secret time study again. Mirrors web's double-click-to-hide
    /// behavior; iOS surfaces a separate "Hide" affordance because double-
    /// tap on the same tile would conflict with the existing study-tile
    /// double-tap-to-start-EC gesture for nearby cards.
    func hideSecretTimeStudy() {
        jsAsync("player.secretUnlocks.viewSecretTS = false;")
    }

    /// SecretAchievement(13) "It pays to have respect" — hardware-keyboard
    /// F-key press. Mirrors web `hotkeys.js:250-257` (bindRepeatable "f").
    /// Also dispatches the "Paying respects" toast through the existing
    /// GameUI.notify pipeline so the side-effect surfaces identically.
    func payRespects() {
        jsAsync("""
        GameUI.notify.info("Paying respects");
        SecretAchievement(13).unlock();
        """)
    }

    /// SecretAchievement(17) "30 Lives" — full Konami code entered on a
    /// hardware keyboard. Mirrors web `hotkeys.js:564-568` exactly:
    /// unlocks the secret, bumps antimatter to a minimum of 30, and
    /// starts the speedrun timer (no-op if speedrun isn't active).
    func unlockKonamiAchievement() {
        jsAsync("""
        SecretAchievement(17).unlock();
        Currency.antimatter.bumpTo(30);
        if (typeof Speedrun !== 'undefined' && Speedrun.startTimer) {
            Speedrun.startTimer();
        }
        """)
    }

    // MARK: - Gameplay Options (Options → Gameplay card)

    /// Web parity: writes `player.options.automaticTabSwitching`. iOS-side, the
    /// `SidebarState.selectSubtabIfAuto` helper checks the mirror and no-ops
    /// non-manual nav (challenge enter/exit/restart) when this is `false`.
    func setAutomaticTabSwitching(_ on: Bool) {
        automaticTabSwitching = on
        jsAsync("player.options.automaticTabSwitching = \(on)")
    }

    /// Writes `player.options.offlineProgress`. Already honored by both the
    /// cold-start and foreground-return offline simulation paths.
    func setOfflineProgressEnabled(_ on: Bool) {
        offlineProgressEnabledOption = on
        jsAsync("player.options.offlineProgress = \(on)")
    }

    /// Writes `player.options.confirmations.glyphSelection`. When off, manual
    /// Reality auto-picks a glyph instead of prompting (see `requestReality`).
    func setGlyphSelectionConfirmation(_ on: Bool) {
        glyphSelectionConfirmation = on
        jsAsync("player.options.confirmations.glyphSelection = \(on)")
    }

    /// Writes `player.options.offlineTicks` from the raw 22–54 slider value.
    /// Web's exponential mantissa-linear formula `(1 + value % 9) * 10^floor(value / 9)`
    /// produces 500 / 600 / … / 900 / 1000 / 2000 / … / 1e6.
    func setOfflineTicks(fromSlider slider: Int) {
        let clamped = max(22, min(54, slider))
        let ticks = (1 + clamped % 9) * Int(pow(10.0, Double(clamped / 9)))
        offlineTicksValue = ticks
        jsAsync("player.options.offlineTicks = \(ticks)")
    }

    /// Inverse of the slider formula — used by Options to seat the slider from
    /// the persisted `player.options.offlineTicks`.
    static func offlineSliderValue(forTicks ticks: Int) -> Int {
        guard ticks > 0 else { return 22 }
        let exponent = Int(floor(log10(Double(ticks))))
        let mantissa = (Double(ticks) / pow(10.0, Double(exponent))) - 1.0
        return max(22, min(54, 9 * exponent + Int(mantissa.rounded())))
    }

    /// Writes `player.options.automatorEvents.maxEntries`. Range 50–500 step 50.
    func setAutomatorLogMaxEntries(_ n: Int) {
        let clamped = max(50, min(500, (n / 50) * 50))
        automatorLogMaxEntries = clamped
        jsAsync("player.options.automatorEvents.maxEntries = \(clamped)")
    }

    // MARK: - Modify Visible Tabs

    /// Toggle a parent tab's bit in `player.options.hiddenTabBits`. No-op for
    /// non-hideable tabs (Options, Debug — Options is the home of the sheet
    /// itself, so we must never let it disappear; Debug is iOS-only and
    /// DEBUG-build only). Mirrors web `TabState.toggleVisibility` + the
    /// SA47 trigger from `tabs.js`.
    ///
    /// The UI guards against toggling the *currently active* tab via a
    /// disabled `Toggle` row; this action does not re-check the active state
    /// because the engine has no canonical "current tab" reference separate
    /// from `SidebarState`. The sheet is the only entry point.
    func toggleTabVisibility(_ tab: SidebarTab) {
        guard tab.isWebHideable, let id = tab.webId else { return }
        jsAsync("""
        (function(){
            try {
                player.options.hiddenTabBits ^= (1 << \(id));
                if (typeof Tabs !== 'undefined' && typeof SecretAchievement !== 'undefined') {
                    if (Tabs.all.filter(t => t.isUnlocked && t.hidable).every(t => t.isHidden)) {
                        SecretAchievement(47).unlock();
                    }
                }
            } catch (e) {
                if (typeof _nativeLog !== 'undefined') _nativeLog("toggleTabVisibility error: " + e);
            }
        })();
        """)
    }

    /// Toggle a subtab's bit in `player.options.hiddenSubtabBits[parentId]`.
    /// Same non-hideable / current-subtab guards as `toggleTabVisibility`.
    func toggleSubtabVisibility(parent: SidebarTab, subtab: Subtab) {
        guard parent.isWebHideable,
              subtab.isWebHideable,
              let parentId = parent.webId,
              let subId = subtab.webId
        else { return }
        jsAsync("""
        (function(){
            try {
                if (!Array.isArray(player.options.hiddenSubtabBits)) return;
                player.options.hiddenSubtabBits[\(parentId)] ^= (1 << \(subId));
                if (typeof Tabs !== 'undefined' && typeof SecretAchievement !== 'undefined') {
                    if (Tabs.all.filter(t => t.isUnlocked && t.hidable).every(t => t.isHidden)) {
                        SecretAchievement(47).unlock();
                    }
                }
            } catch (e) {
                if (typeof _nativeLog !== 'undefined') _nativeLog("toggleSubtabVisibility error: " + e);
            }
        })();
        """)
    }

    /// Reset every visibility bit — mirrors web's "Show all tabs" button.
    /// Does NOT trigger SA47 (web's `unhideTab` doesn't check either).
    func showAllTabs() {
        jsAsync("""
        (function(){
            try {
                player.options.hiddenTabBits = 0;
                if (Array.isArray(player.options.hiddenSubtabBits)) {
                    for (var i = 0; i < player.options.hiddenSubtabBits.length; i++) {
                        player.options.hiddenSubtabBits[i] = 0;
                    }
                }
            } catch (e) {
                if (typeof _nativeLog !== 'undefined') _nativeLog("showAllTabs error: " + e);
            }
        })();
        """)
    }

    /// Convenience overload using `self.sidebarStateRef`. Returns immediately
    /// if no shell is currently presenting — covers pre-shell-mount
    /// startup ticks and any future detached-engine cases. Safe to call
    /// from any thread (the explicit overload handles main dispatch).
    func recoverFromHiddenActiveTab() {
        guard let ref = sidebarStateRef else { return }
        recoverFromHiddenActiveTab(sidebarState: ref)
    }

    /// If `sidebarState.activeTab` (or its active subtab) is hidden, snap to
    /// the first visible-and-available tab/subtab in declaration order.
    /// Called from every save-lifecycle entry point (finishStartup,
    /// importSave, hardReset, slot switch, backup restore, cloud adopt)
    /// after `cacheJSRefs()` and before the first user-facing `pollDirect()`.
    /// Also called defensively from `pollDirect()` so mid-session edge cases
    /// (e.g. cross-device sync writing new hidden bits) self-heal.
    ///
    /// Safe to call on any thread — it dispatches the actual `SidebarState`
    /// mutation to main, where `@Observable` writes are valid.
    func recoverFromHiddenActiveTab(sidebarState: SidebarState) {
        let activeTab = sidebarState.activeTab
        let activeSubtab = sidebarState.lastSubtab[activeTab]

        let tabHidden = activeTab.isHidden(engine: self)
        let subtabHidden: Bool = {
            guard let s = activeSubtab else { return false }
            return s.isHidden(engine: self) || !s.isAvailable(engine: self)
        }()

        guard tabHidden || subtabHidden else { return }

        // Find first visible+available tab; pick its first visible+available subtab.
        let recoveredTab = SidebarTab.allCases.first {
            $0.isAvailable(engine: self) && !$0.isHidden(engine: self)
        } ?? .options // Options is always available and never hideable.

        let recoveredSubtab = recoveredTab.availableVisibleSubtabs(engine: self).first
            ?? recoveredTab.defaultSubtab

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if tabHidden {
                sidebarState.selectTab(recoveredTab, engine: self)
                sidebarState.selectSubtab(recoveredSubtab, in: recoveredTab, engine: self)
            } else if subtabHidden {
                // Only the subtab got hidden — keep the tab, recover the subtab.
                let recoveredSub = activeTab.availableVisibleSubtabs(engine: self).first
                    ?? activeTab.defaultSubtab
                sidebarState.selectSubtab(recoveredSub, in: activeTab, engine: self)
            }
        }
    }

    /// Apply one of the supported notations. Calls `Notations.find(name).setAsCurrent()`
    /// on the JS side, mirroring the web Options → Visual dropdown.
    func setNotation(_ name: String) {
        // Escape quotes defensively even though our names are ASCII literals.
        let safe = name.replacingOccurrences(of: "\"", with: "\\\"")
        jsAsync("""
            (function(){
                if (typeof Notations === 'undefined') return;
                var n = Notations.find("\(safe)");
                if (n && typeof n.setAsCurrent === 'function') n.setAsCurrent();
            })();
        """)
    }

    // MARK: - Toast notifications

    func enqueueToast(type: String, text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let toast = ToastMessage(type: type, text: text)
            self.toastQueue.append(toast)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.dismissToast(id: toast.id)
            }
        }
    }

    /// Singleton-style toast mirroring web's `Modal.message`. Replaces any
    /// currently-queued modal-message toast in place so repeated calls (e.g.
    /// per-tick C11 matter annihilation) don't stack.
    ///
    /// Duration scales with text length. Web's `Modal.message` is a
    /// persistent modal that stays until the user dismisses it — surfacing
    /// it as a 3-second toast makes longer messages unreadable (e.g. the
    /// ~50-word "Big Crunch in under a minute" UI-change notice from
    /// `normal-achievement.js:64`). The toast itself is tap-to-dismiss
    /// (whole `ToastView` is a Button), so a generous auto-dismiss window
    /// is safe — a user who's done reading just taps.
    func enqueueModalMessage(text: String) {
        toastQueue.removeAll { $0.type == "modalMessage" }
        let toast = ToastMessage(type: "modalMessage", text: text)
        toastQueue.append(toast)
        // Reading speed: ~15 chars/sec is a comfortable rate for short
        // dialog-style prose. Clamped to [6s, 20s] — minimum is one
        // glance + ~half a beat; maximum keeps it from becoming a screen
        // squatter if a future message is unusually long.
        let duration = max(6.0, min(20.0, Double(text.count) / 15.0))
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.dismissToast(id: toast.id)
        }
    }

    func dismissToast(id: UUID) {
        toastQueue.removeAll { $0.id == id }
    }

    // MARK: - Autobuyer actions
    func purchaseAutobuyer(_ type: String, tier: Int? = nil) {
        // Invalidate cheapestAntimatterAutobuyer cache after purchase to prevent
        // stale cache from re-triggering the newAutobuyer tab notification badge.
        if let t = tier { jsAsync("Autobuyer.\(type)(\(t)).purchase(); GameCache.cheapestAntimatterAutobuyer.invalidate()") }
        else { jsAsync("Autobuyer.\(type).purchase(); GameCache.cheapestAntimatterAutobuyer.invalidate()") }
    }

    func toggleAutobuyer(_ type: String, tier: Int? = nil) {
        if let t = tier { jsAsync("Autobuyer.\(type)(\(t)).isActive = !Autobuyer.\(type)(\(t)).isActive") }
        else { jsAsync("Autobuyer.\(type).isActive = !Autobuyer.\(type).isActive") }
    }

    func toggleAllAutobuyers() { jsAsync("player.auto.autobuyersOn = !player.auto.autobuyersOn") }

    func upgradeAutobuyerInterval(_ type: String, tier: Int? = nil) {
        if let t = tier { jsAsync("Autobuyer.\(type)(\(t)).upgradeInterval()") }
        else { jsAsync("Autobuyer.\(type).upgradeInterval()") }
    }

    func upgradeAutobuyerBulk(_ tier: Int) {
        jsAsync("Autobuyer.antimatterDimension(\(tier)).upgradeBulk()")
    }

    func toggleAutobuyerMode(_ type: String, tier: Int? = nil) {
        if let t = tier { jsAsync("Autobuyer.\(type)(\(t)).toggleMode()") }
        else { jsAsync("Autobuyer.\(type).toggleMode()") }
    }

    // DimBoost autobuyer settings
    func toggleDimBoostAutobuyer() { jsAsync("Autobuyer.dimboost.isActive = !Autobuyer.dimboost.isActive") }
    func upgradeDimBoostAutobuyer() { jsAsync("Autobuyer.dimboost.upgradeInterval()") }
    func setDimBoostBuyMaxInterval(_ value: String) {
        let safe = value.replacingOccurrences(of: "'", with: "")
        // `0` is a valid value (web default — buy max every tick). Guard only NaN,
        // not falsy `0`, so an explicit 0 isn't bounced back to 0.5 (web parity).
        jsAsync("(function(){var v=Number('\(safe)');if(!isNaN(v))Autobuyer.dimboost.buyMaxInterval=v;})()")
    }
    func setDimBoostLimit(enabled: Bool, max: Int) {
        jsAsync("Autobuyer.dimboost.limitDimBoosts = \(enabled); Autobuyer.dimboost.maxDimBoosts = \(max)")
    }
    func setDimBoostGalaxyLimit(enabled: Bool, galaxies: Int) {
        jsAsync("Autobuyer.dimboost.limitUntilGalaxies = \(enabled); Autobuyer.dimboost.galaxies = \(galaxies)")
    }

    // Galaxy autobuyer settings
    func toggleGalaxyAutobuyer() { jsAsync("Autobuyer.galaxy.isActive = !Autobuyer.galaxy.isActive") }
    func upgradeGalaxyAutobuyer() { jsAsync("Autobuyer.galaxy.upgradeInterval()") }
    func setGalaxyBuyMaxInterval(_ value: String) {
        let safe = value.replacingOccurrences(of: "'", with: "")
        // `0` is a valid value (web default — buy max every tick). Guard only NaN,
        // not falsy `0`, so an explicit 0 isn't bounced back to 0.5 (web parity).
        jsAsync("(function(){var v=Number('\(safe)');if(!isNaN(v))Autobuyer.galaxy.buyMaxInterval=v;})()")
    }
    func setGalaxyLimit(enabled: Bool, max: Int) {
        jsAsync("Autobuyer.galaxy.limitGalaxies = \(enabled); Autobuyer.galaxy.maxGalaxies = \(max)")
    }

    // Big Crunch autobuyer settings
    func toggleBigCrunchAutobuyer() { jsAsync("Autobuyer.bigCrunch.isActive = !Autobuyer.bigCrunch.isActive") }
    func upgradeBigCrunchAutobuyer() { jsAsync("Autobuyer.bigCrunch.upgradeInterval()") }
    func setBigCrunchMode(_ mode: Int) { jsAsync("Autobuyer.bigCrunch.mode = \(mode)") }
    func setBigCrunchAmount(_ value: String) { jsAsync("Autobuyer.bigCrunch.data.amount = new Decimal(\"\(value)\")") }
    func setBigCrunchTime(_ value: String) {
        let safe = value.replacingOccurrences(of: "'", with: "")
        jsAsync("Autobuyer.bigCrunch.time = Number('\(safe)') || 1")
    }
    func setBigCrunchXHighest(_ value: String) { jsAsync("Autobuyer.bigCrunch.xHighest = new Decimal(\"\(value)\")") }
    func toggleBigCrunchDynamic() { jsAsync("Autobuyer.bigCrunch.data.increaseWithMult = !Autobuyer.bigCrunch.data.increaseWithMult") }
    func setSacrificeMultiplier(_ value: String) { jsAsync("Autobuyer.sacrifice.multiplier = new Decimal(\"\(value)\")") }

    // Infinity Dimension autobuyer actions
    func toggleInfinityDimAutobuyer(_ tier: Int) {
        jsAsync("Autobuyer.infinityDimension(\(tier)).isActive = !Autobuyer.infinityDimension(\(tier)).isActive")
    }
    func toggleAllInfinityDimAutobuyers() { jsAsync("toggleAllInfDims()") }

    // Enable/Disable all individual autobuyer active states
    func toggleAllAutobuyerStates() {
        jsAsync("""
            var allOff = Autobuyers.unlocked.every(function(a) { return !a.isActive; });
            Autobuyers.unlocked.forEach(function(a) { a.isActive = allOff; });
        """)
    }

    // MARK: - Challenge actions

    func startNormalChallenge(_ id: Int, navigateToDimensions: @escaping () -> Void = {}) {
        jsQueue.async { [weak self] in
            guard let self else { return }
            if self.confirmationEnabled("challenges") {
                DispatchQueue.main.async { self.pendingModal = .normalChallenge(id) }
            } else {
                self.context.evaluateScript("NormalChallenge(\(id)).start()")
                DispatchQueue.main.async { navigateToDimensions() }
            }
        }
    }

    func confirmStartNormalChallenge(_ id: Int) {
        jsAsync("NormalChallenge(\(id)).start()")
    }

    func exitChallenge() {
        jsQueue.async { [self] in
            if self.confirmationEnabled("exitChallenge") {
                let ncCurrent = Int(self.jsPlayer.forProperty("challenge")?.forProperty("normal")?.forProperty("current")?.toInt32() ?? 0)
                let icCurrent = Int(self.jsPlayer.forProperty("challenge")?.forProperty("infinity")?.forProperty("current")?.toInt32() ?? 0)
                let ecCurrent = Int(self.jsPlayer.forProperty("challenge")?.forProperty("eternity")?.forProperty("current")?.toInt32() ?? 0)
                if ncCurrent > 0 {
                    let name = self.jsNCRefs[ncCurrent - 1].forProperty("config")?.forProperty("name")?.toString() ?? "Challenge \(ncCurrent)"
                    DispatchQueue.main.async { self.pendingModal = .exitChallenge("\(name) Challenge") }
                } else if icCurrent > 0 {
                    DispatchQueue.main.async { self.pendingModal = .exitChallenge("Infinity Challenge \(icCurrent)") }
                } else if ecCurrent > 0 {
                    DispatchQueue.main.async { self.pendingModal = .exitChallenge("Eternity Challenge \(ecCurrent)") }
                }
            } else {
                self.context.evaluateScript("(function(){ var c = Player.anyChallenge; if(c) c.exit(); })()")
            }
        }
    }

    func confirmExitChallenge() {
        jsAsync("(function(){ var c = Player.anyChallenge; if(c) c.exit(); })()")
    }

    func restartChallenge() {
        jsAsync("(function(){ var c = Player.anyChallenge; if(c){ c.exit(true); c.start(); } })()")
    }

    // MARK: - Infinity Challenge actions

    func startInfinityChallenge(_ id: Int, navigateToDimensions: @escaping () -> Void = {}) {
        jsQueue.async { [weak self] in
            guard let self else { return }
            if self.confirmationEnabled("challenges") {
                DispatchQueue.main.async { self.pendingModal = .infinityChallenge(id) }
            } else {
                self.context.evaluateScript("InfinityChallenge(\(id)).start()")
                DispatchQueue.main.async { navigateToDimensions() }
            }
        }
    }

    func confirmStartInfinityChallenge(_ id: Int) {
        jsAsync("InfinityChallenge(\(id)).start()")
    }

    func setRetryChallenge(_ value: Bool) {
        jsAsync("player.options.retryChallenge = \(value)")
    }

    // MARK: - Automator actions

    /// Play/pause toggle matching AutomatorControls.vue play() logic.
    func automatorPlay() {
        jsQueue.async { [self] in
            autoreleasepool {
                let hasErrors = context.evaluateScript("AutomatorData.currentErrors().length > 0")?.toBool() ?? false
                if hasErrors {
                    // Force pause if there are errors
                    context.evaluateScript("AutomatorBackend.mode = 1") // PAUSE
                    return
                }
                let isRunning = context.evaluateScript("AutomatorBackend.isRunning")?.toBool() ?? false
                if isRunning {
                    context.evaluateScript("AutomatorBackend.pause()")
                    return
                }
                let isOn = context.evaluateScript("AutomatorBackend.isOn")?.toBool() ?? false
                if isOn {
                    // Resume from pause
                    context.evaluateScript("AutomatorBackend.mode = 2") // RUN
                } else {
                    // Start fresh
                    context.evaluateScript("AutomatorBackend.start(player.reality.automator.state.editorScript)")
                }
            }
        }
    }

    func automatorStop() { jsAsync("AutomatorBackend.stop()") }

    func automatorStep() {
        jsQueue.async { [self] in
            autoreleasepool {
                let isOn = context.evaluateScript("AutomatorBackend.isOn")?.toBool() ?? false
                if isOn {
                    context.evaluateScript("AutomatorBackend.mode = 3") // SINGLE_STEP
                } else {
                    context.evaluateScript("AutomatorBackend.start(player.reality.automator.state.editorScript, 3)")
                }
            }
        }
    }

    func automatorRewind() { jsAsync("AutomatorBackend.restart()") }

    func automatorToggleRepeat() { jsAsync("AutomatorBackend.toggleRepeat()") }
    func automatorToggleForceRestart() { jsAsync("AutomatorBackend.toggleForceRestart()") }
    func automatorToggleFollowExecution() { jsAsync("AutomatorBackend.toggleFollowExecution()") }

    func automatorSelectScript(_ id: Int) {
        jsAsync("player.reality.automator.state.editorScript = \(id); AutomatorData.clearUndoData()")
    }

    func automatorNewScript() { jsAsync("AutomatorBackend.newScript()") }

    func automatorDeleteScript(_ id: Int) { jsAsync("AutomatorBackend.deleteScript(\(id))") }

    func automatorRenameScript(_ id: Int, name: String) {
        jsQueue.async { [self] in
            autoreleasepool {
                context.setObject(name, forKeyedSubscript: "_swiftAutoName" as NSString)
                context.evaluateScript("""
                    var s = player.reality.automator.scripts[\(id)];
                    if (s) s.name = _swiftAutoName.substring(0, \(AutomatorData_MAX_NAME_LENGTH));
                """)
            }
        }
    }

    /// Save script content using context.setObject to avoid JS string escaping issues.
    func automatorSaveScript(_ id: Int, content: String) {
        jsQueue.async { [self] in
            autoreleasepool {
                context.setObject(content, forKeyedSubscript: "_swiftAutoContent" as NSString)
                context.evaluateScript("AutomatorBackend.saveScript(\(id), _swiftAutoContent)")
            }
        }
    }

    /// Load full script content (one-shot, not polled every frame).
    func loadAutomatorScriptContent(_ id: Int, completion: @escaping (String) -> Void) {
        jsQueue.async { [self] in
            autoreleasepool {
                let content = context.evaluateScript(
                    "player.reality.automator.scripts[\(id)] ? player.reality.automator.scripts[\(id)].content : ''"
                )?.toString() ?? ""
                DispatchQueue.main.async { completion(content) }
            }
        }
    }

    /// Export current automator script to clipboard (Base64-encoded).
    func automatorExportScript() {
        jsQueue.async { [self] in
            autoreleasepool {
                let encoded = context.evaluateScript(
                    "AutomatorBackend.exportCurrentScriptContents() || ''"
                )?.toString() ?? ""
                DispatchQueue.main.async {
                    if encoded.isEmpty {
                        // Notify via toast
                    } else {
                        UIPasteboard.general.string = encoded
                    }
                }
            }
        }
    }

    /// Parse an automator import string and return preview info (does NOT import).
    func automatorParseImport(_ input: String, completion: @escaping (AutomatorImportPreview?) -> Void) {
        jsQueue.async { [self] in
            autoreleasepool {
                context.setObject(input, forKeyedSubscript: "_swiftAutoImport" as NSString)
                let json = context.evaluateScript("""
                    (function() {
                        var full = AutomatorBackend.parseFullScriptData(_swiftAutoImport);
                        if (full) {
                            var lines = full.content.split('\\n').length;
                            var hasErrors = (typeof AutomatorGrammar !== 'undefined') ? AutomatorGrammar.compile(full.content).errors.length > 0 : false;
                            var constants = [];
                            for (var i = 0; i < full.constants.length; i++) {
                                constants.push(full.constants[i].key);
                            }
                            var presets = [];
                            for (var i = 0; i < full.presets.length; i++) {
                                var p = full.presets[i];
                                presets.push((p.name || 'Slot ' + (p.id + 1)));
                            }
                            return JSON.stringify({
                                type: 'full', name: full.name, lineCount: lines,
                                hasErrors: hasErrors,
                                constants: constants, presets: presets
                            });
                        }
                        var simple = AutomatorBackend.parseScriptContents(_swiftAutoImport);
                        if (simple) {
                            var lines = simple.content.split('\\n').length;
                            var hasErrors = (typeof AutomatorGrammar !== 'undefined') ? AutomatorGrammar.compile(simple.content).errors.length > 0 : false;
                            return JSON.stringify({
                                type: 'simple', name: simple.name, lineCount: lines,
                                hasErrors: hasErrors,
                                constants: [], presets: []
                            });
                        }
                        return '';
                    })()
                """)?.toString() ?? ""
                guard !json.isEmpty,
                      let data = json.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                let preview = AutomatorImportPreview(
                    isFullData: (obj["type"] as? String) == "full",
                    name: obj["name"] as? String ?? "Untitled",
                    lineCount: obj["lineCount"] as? Int ?? 0,
                    hasErrors: obj["hasErrors"] as? Bool ?? false,
                    constants: obj["constants"] as? [String] ?? [],
                    presets: obj["presets"] as? [String] ?? []
                )
                DispatchQueue.main.async { completion(preview) }
            }
        }
    }

    /// Actually import a previously validated automator script string.
    func automatorImportScript(_ input: String, importConstants: Bool, completion: @escaping (Bool) -> Void) {
        jsQueue.async { [self] in
            autoreleasepool {
                context.setObject(input, forKeyedSubscript: "_swiftAutoImport" as NSString)
                let result = context.evaluateScript("""
                    (function() {
                        var full = AutomatorBackend.parseFullScriptData(_swiftAutoImport);
                        if (full) {
                            AutomatorBackend.importFullScriptData(_swiftAutoImport, {
                                presets: false,
                                constants: \(!importConstants)
                            });
                            return true;
                        }
                        var simple = AutomatorBackend.parseScriptContents(_swiftAutoImport);
                        if (simple) {
                            AutomatorBackend.importScriptContents(_swiftAutoImport);
                            return true;
                        }
                        return false;
                    })()
                """)?.toBool() ?? false
                DispatchQueue.main.async { completion(result) }
            }
        }
    }

    /// Load command documentation for the Automator docs panel (one-shot).
    func loadAutomatorDocs(completion: @escaping ([[String: Any]]) -> Void) {
        jsQueue.async { [self] in
            autoreleasepool {
                let json = context.evaluateScript("""
                    (function() {
                        var cmds = GameDatabase.reality.automator.commands;
                        var result = [];
                        for (var i = 0; i < cmds.length; i++) {
                            var c = cmds[i];
                            var desc = typeof c.description === 'function' ? c.description() : (c.description || '');
                            result.push({
                                id: c.id || '',
                                keyword: c.keyword || '',
                                syntax: c.syntax || '',
                                desc: desc,
                                category: c.category || 0
                            });
                        }
                        return JSON.stringify(result);
                    })()
                """)?.toString() ?? "[]"
                guard let data = json.data(using: .utf8),
                      let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                    DispatchQueue.main.async { completion([]) }
                    return
                }
                DispatchQueue.main.async { completion(arr) }
            }
        }
    }

    private let AutomatorData_MAX_NAME_LENGTH = 15

    // MARK: - Debug / Dev commands
    func setDebugSpeed(_ multiplier: Double) { jsAsync("_debugSpeedMultiplier = \(multiplier)") }
    func devCommand(_ js: String) { jsAsync(js) }

    /// Set the JS game loop tick rate (ms). Lower = more frequent, lighter ticks.
    /// This is saved in the game save file via player.options.updateRate (matches web behavior).
    func setUpdateRate(_ ms: Int) {
        jsQueue.async { [self] in
            autoreleasepool {
                // Stop current game loop, change rate, restart. Mirrors web
                // `Options.refreshUpdateRate()` (options.js:43-48), including
                // the SecretAchievement(31) "You should download some more
                // RAM" trigger at 200ms — iOS doesn't call `Options.refresh-
                // UpdateRate()` itself because our restart path is custom
                // (`_startGameLoopTimer` vs web's `GameIntervals.gameLoop.
                // restart()`), so the unlock check is inlined here.
                context.evaluateScript("""
                if (typeof _gameLoopTimerID !== 'undefined') { clearInterval(_gameLoopTimerID); }
                player.options.updateRate = \(ms);
                if (player.options.updateRate === 200) { SecretAchievement(31).unlock(); }
                if (typeof _startGameLoopTimer !== 'undefined') { _startGameLoopTimer(); }
                """)
                debugLog("OPTIONS: set updateRate = \(ms)ms (\(1000/ms)Hz)")
            }
        }
    }

    /// Read the current updateRate from JS (persisted in game save).
    func readUpdateRate(completion: @escaping (Int) -> Void) {
        jsQueue.async { [self] in
            let ms = Int(context.evaluateScript("player.options.updateRate")?.toInt32() ?? 33)
            DispatchQueue.main.async { completion(ms) }
        }
    }

    /// Set the CADisplayLink preferred frame rate.
    func setDisplayLinkFPS(_ fps: Int) {
        UserDefaults.standard.set(fps, forKey: "uiRefreshRate_v2")
        applyFrameRate()
    }

    /// Toggle the Dynamic Throttling user pref. When disabling, also clear
    /// the current idle step and reapply the base frame rate immediately —
    /// otherwise the display link stays pinned at whatever low fps the last
    /// step-down applied and the UI feels permanently laggy until relaunch.
    func setDynamicThrottling(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "dynamicThrottling")
        if !enabled && idleStepIndex > 0 {
            debugLog("⚙️ DYNAMIC THROTTLING OFF — resetting idleStepIndex \(idleStepIndex) → 0")
            idleStepIndex = 0
        } else {
            debugLog("⚙️ DYNAMIC THROTTLING \(enabled ? "ON" : "OFF")")
        }
        // Refresh last-interaction clock so re-enabling doesn't instantly
        // step down again.
        lastInteractionTime = CFAbsoluteTimeGetCurrent()
        applyFrameRate()
    }

    /// Current thermal state as a string for display.
    var thermalStateDescription: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:  "Nominal"
        case .fair:     "Fair"
        case .serious:  "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }
}
