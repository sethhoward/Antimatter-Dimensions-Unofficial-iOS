//
//  GameState.swift
//  AntiMatter
//
//  Plain structs matching game state read via JSValue.forProperty().
//  All display strings are formatted in Swift using DecimalFormat.swift.
//

import Foundation
import UIKit

// MARK: - Game State

struct DimensionState: Identifiable, Equatable {
    let tier: Int
    var isVisible: Bool
    var isAvailableForPurchase: Bool
    var amount: String
    let multiplier: String
    let boughtBefore10: Int
    let bought: Int
    var howManyCanBuy: Int
    let singleCost: String
    let until10Cost: String
    /// Currency name appended after the cost number — "AM" normally, or
    /// e.g. "1st AD" during Challenge 6 (where ADs cost the dimension two
    /// tiers below them). Mirrors `ModernAntimatterDimensionRow.vue` `costUnit`.
    var costSuffix: String = "AM"
    var isAffordable: Bool
    var isAffordableUntil10: Bool
    var rateOfChange: String?
    /// `AntimatterDimension(tier).continuumValue` — fractional "owned" count
    /// surfaced only when `engine.continuumUnlocked && !continuumDisabled`.
    /// Replaces the buy button in AD rows with "Continuum: N,NNN.NN".
    var continuumValue: Double = 0

    var id: Int { tier }

    static let tierNames = ["1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th"]

    static func safeTierName(_ tier: Int) -> String {
        let idx = tier - 1
        guard tierNames.indices.contains(idx) else { return "\(tier)th" }
        return tierNames[idx]
    }

    var displayName: String { "\(Self.safeTierName(tier)) Antimatter Dimension" }
    /// Shortened name for iPhone: "1st Dimension" instead of "1st Antimatter Dimension"
    var shortDisplayName: String { "\(Self.safeTierName(tier)) Dimension" }
}

struct TickspeedState: Equatable {
    var isUnlocked: Bool
    let cost: String
    let multiplier: String
    let perSecond: String
    var isAffordable: Bool
    let purchasedCount: Int
    let freeCount: Int
    /// `Tickspeed.continuumValue` — fractional "tickspeed upgrades purchased"
    /// in continuum mode. Surfaced as "Tickspeed Continuum: N,NNN.NN" when
    /// Lai'tela's continuum is active.
    var continuumValue: Double = 0
}

/// Shared formatting for dimension tier requirements (DimBoost, Galaxy).
private func dimensionRequirementText(amount: Int, tier: Int) -> String {
    "Requires: \(amount) \(DimensionState.safeTierName(tier)) \(UIDevice.current.userInterfaceIdiom == .phone ? "AD" : "Antimatter Dimensions")"
}

struct DimBoostState: Equatable {
    let purchasedBoosts: Int
    let requirementTier: Int
    let requirementAmount: Int
    var isSatisfied: Bool
    var canBeBought: Bool
    let unlockedByBoost: String?
    let lockText: String?

    var requirementText: String {
        dimensionRequirementText(amount: requirementAmount, tier: requirementTier)
    }
}

struct GalaxyState: Equatable {
    let count: Int
    /// "Antimatter Galaxies" / "Distant Antimatter Galaxies" / "Remote Antimatter Galaxies"
    /// — mirrors `ModernAntimatterGalaxyRow.vue:typeName`.
    let typeName: String
    /// Web `sumText`: "100" alone, or "100 + 40 = 140" once Replicanti / Tachyon
    /// galaxies contribute. Formatted JS-side via `formatInt`.
    let countDisplay: String
    let requirementTier: Int
    let requirementAmount: Int
    var isSatisfied: Bool
    var canBeBought: Bool
    let lockText: String?

    var requirementText: String {
        dimensionRequirementText(amount: requirementAmount, tier: requirementTier)
    }
}

struct ToastMessage: Identifiable {
    let id = UUID()
    let type: String   // "success", "error", "info", "infinity", "eternity", "reality", etc.
    let text: String
    let timestamp = Date()
}

struct AchievementState: Identifiable, Equatable {
    let id: Int
    let name: String
    let description: String
    let isUnlocked: Bool
    let hasReward: Bool
    let reward: String?
    let row: Int
    let column: Int
    let isWaiting: Bool   // post-Reality: pre-Reality ach (row<=13) not yet re-earned
    let isObscured: Bool  // row 18: hidden until unlocked (Pelle row)
}

/// Surfaces `player.reality.achTimer` + the auto-achieve toggle.
///
/// Mirrors `NormalAchievementsTab.vue:72-89,158-176`. The timer accumulates
/// game-tick time once `PlayerProgress.realityUnlocked()` is true; with auto
/// off it caps at `Achievements.period`, with auto on it consumes a period
/// to unlock one waiting achievement (left-to-right, top-to-bottom). The
/// section is hidden once Perk 205 (`achievementGroup5`) is bought — that
/// perk grants the rows immediately and removes the timer system.
/// One Secret Achievement tile. 32 total (4 rows × 8 cols, IDs 11–18, 21–28, …, 41–48).
///
/// Web reference: `src/core/secret-formula/achievements/secret-achievements.js`
/// + `src/core/achievements/secret-achievement.js` (the `SecretAchievements.allRows`
/// grouping). Locked tiles render as "S{id}" (`SecretAchievement.vue`); unlocked
/// tiles show `name`. Tapping any tile opens a detail sheet — except #11, which
/// is the "click the tile" easter-egg unlock.
///
/// Per the design notes "Normalize web-source text whitespace": `description` is piped
/// through the JS helper's `normText` before serialisation.
struct SecretAchievementInfo: Identifiable, Equatable {
    let id: Int
    let name: String
    let description: String
    let isUnlocked: Bool
    let row: Int      // 1..4
    let column: Int   // 1..8
}

struct SecretAchievementsState: Equatable {
    var rows: [[SecretAchievementInfo]] = []
    var unlockedCount: Int = 0
    var totalCount: Int = 0

    static let empty = SecretAchievementsState()
}

struct AchievementTimerState: Equatable {
    var isVisible: Bool = false
    var isAutoActive: Bool = false
    var missingCount: Int = 0
    /// `Achievements.timeToNextAutoAchieve / gameSpeedupFactor` in seconds.
    var nextSeconds: Double = 0
    /// `((missing - 1) * period + timeToNext) / gameSpeedupFactor` in seconds.
    var totalSeconds: Double = 0
    /// Pre-formatted via `timeDisplayNoDecimals`. Empty when `nextSeconds <= 0`.
    var nextCountdownText: String = ""
    var totalCountdownText: String = ""
}

// MARK: - Infinity

struct InfinityUpgradeInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let cost: String
    let isBought: Bool
    let canBeBought: Bool
    let effectText: String?
    let column: Int
    let row: Int
    let isAvailableForPurchase: Bool  // meets prerequisite (column order)
    let isRebuyable: Bool
    /// Ra.unlocks.chargedInfinityUpgrades — this upgrade is currently charged
    /// (replaces its regular effect with `chargedEffect`).
    let isCharged: Bool
    /// Charged effect description (shown in shift mode when charge is unlocked).
    let chargedEffectText: String?
}

struct IPMultState: Equatable {
    let cost: String
    let multiplier: String
    let purchases: Int
    let isCapped: Bool
    let canBeBought: Bool
    /// Soft cap above which `Multiply IP by 2` cost scales faster.
    /// `GameDatabase.infinity.upgrades.ipMult.costIncreaseThreshold`.
    let softCap: String
    /// Hard cap above which `Multiply IP by 2` can't be purchased at all.
    /// `GameDatabase.infinity.upgrades.ipMult.costCap`.
    let hardCap: String
    /// `Autobuyer.ipMult.isUnlocked` — drives inline "Autobuy IP mult"
    /// toggle visibility on the Infinity Upgrades tab. Mirrors web
    /// `IpMultiplierButton.vue isAutoUnlocked`.
    let autobuyerUnlocked: Bool
    /// `Autobuyer.ipMult.isActive`.
    let autobuyerActive: Bool
}

struct InfinityState: Equatable {
    var canCrunch: Bool
    var isBroken: Bool
    /// `PlayerProgress.infinityUnlocked()` — true once any Big Crunch
    /// has ever happened in this save. Used by the iPhone-only
    /// `showBigCrunchTakeoverFirstOnly` gate so the full-screen takeover
    /// only fires for the first crunch; after that the header hosts a
    /// compact crunch button via `CompactPrestigeRow`.
    var infinityUnlocked: Bool
    var bestInfinityMs: Double
    var gainedIP: String
    var currentIP: String
    var hasIP: Bool
    var infinityGoal: String
    var upgrades: [InfinityUpgradeInfo]
    var ipMult: IPMultState
    var ipOfflineBought: Bool
    var ipOfflineUpgrade: InfinityUpgradeInfo?
    var ipMultUnlocked: Bool  // Achievement 41
    var bigCrunchAutobuyerActive: Bool
    var bigCrunchAutobuyerUnlocked: Bool
    var autobuyersGloballyOn: Bool  // player.auto.autobuyersOn
    var inAntimatterChallenge: Bool

    /// Ra.unlocks.chargedInfinityUpgrades.canBeApplied && !Pelle.isDoomed.
    /// When true, the Infinity Upgrades tab shows the charge/respec UI.
    var chargeInfinityUpgradesUnlocked: Bool
    /// Total allowed charges (`Ra.totalCharges`).
    var totalInfinityCharges: Int
    /// Currently-used charges (`Ra.totalCharges - Ra.chargesLeft`).
    var usedInfinityCharges: Int
    /// `player.celestials.ra.disCharge` — when true, all charged upgrades
    /// will be un-charged on next Reality.
    var disChargeOnReality: Bool

    // Big Crunch modal starting resources
    var gainedInfinities: String
    var startingAM: String?          // nil if <= 10 (default, not worth showing)
    var startingBoosts: Int
    var startWithGalaxy: Bool

    // Big Crunch button IP rate display (shown when peakIPRate <= 5e11)
    var showIPRate: Bool
    var currentIPRate: String
    var peakIPRate: String
    var peakIPRateVal: String

    // Unlock next Infinity Dimension button (header, post-break)
    var nextIDVisible: Bool
    var nextIDCanUnlock: Bool
    var nextIDHasIPUnlock: Bool
    var nextIDAmRequirement: String
    var nextIDIPRequirement: String

    // Eternity button (header, post-ID8-unlock)
    var showEternityButton: Bool
    var canEternity: Bool
    var eternityGoal: String
    var eternityUnlocked: Bool       // has eternitied at least once
    var gainedEP: String             // EP to be gained on eternity
    var showEPRate: Bool             // peakEPRate <= 1e40
    var currentEPRate: String        // EP/min this eternity
    var peakEPRate: String           // best EP/min this eternity
    var peakEPRateVal: String        // EP amount at peak rate
    var isInEternityChallenge: Bool  // in an EC

    // EC completion status (only meaningful when isInEternityChallenge && canEternity)
    var ecGainedCompletions: Int
    var ecFailedRestriction: String   // empty if no restriction failed
    var ecNextGoalAt: String          // formatted IP for next completion threshold
    var ecHasMoreCompletions: Bool
    var ecFullyCompleted: Bool

    // Dilation eternity button (header, when dilation active)
    var isDilationActive: Bool
    var dilationTachyonGain: String   // formatted gain, empty when N/A

    // Reality button (header, post-Reality study purchase or post-Reality unlock)
    var showRealityButton: Bool
    var hasRealityStudy: Bool      // study purchased (false after Reality reset until re-bought)
    var hasEnoughEPForReality: Bool // EP >= 1e4000 (study prerequisite)
    var canReality: Bool
    var gainedRM: String           // "Machines gained: 74" or "No Machines gained"
    var machineStats: String       // "(Capped this Reality!)" or "(Next at X EP)" or "(X RM/min)"
    var gainedGlyphLevel: String   // "Glyph level: 37 (53.1% to next)"
    var realityGainSummary: String // "You will gain 1 Reality, 1 Perk Point, and 96.59 K Reality Machines."
    var realityLevelStats: String  // "You will get a level 4 Glyph on Reality, which is 32 levels lower than your best."
    var realityPPGained: String    // "2 Perk Points" (popover tooltip)
    var realityShardsInfo: String  // "123 Relic Shards (45.67/min)\nPeak: 78.90/min at 12.34 RS" or "" if none
    var realityCelestialInfo: String // Teresa/celestial run reward text or ""

    /// Pre-Break Infinity takeover: replaces content area and header with Big Crunch screen.
    /// Mirrors web `BigCrunchButton.vue`: `!player.break && Player.canCrunch`.
    /// Used unconditionally on iPad (every pre-break can-crunch tick).
    var showBigCrunchTakeover: Bool {
        !isBroken && canCrunch
    }

    /// iPhone-only variant: takeover dismisses permanently after the first
    /// Big Crunch. After that, the header's `CompactPrestigeRow` hosts a
    /// `CompactCrunchButton` whenever `canCrunch` is true. Keeps the
    /// tutorial / "I broke physics" moment for the very first crunch but
    /// stops blocking taps and `SubtabPager` swipes during the rapid
    /// auto-crunch window between first crunch and Break Infinity.
    var showBigCrunchTakeoverFirstOnly: Bool {
        !isBroken && canCrunch && !infinityUnlocked
    }

    static let empty = InfinityState(
        canCrunch: false, isBroken: false, infinityUnlocked: false, bestInfinityMs: 1e12,
        gainedIP: "0", currentIP: "0", hasIP: false,
        infinityGoal: "1.80e308", upgrades: [], ipMult: IPMultState(
            cost: "10", multiplier: "x1.00", purchases: 0,
            isCapped: false, canBeBought: false,
            softCap: "1.00e3000000", hardCap: "1.00e6000000",
            autobuyerUnlocked: false, autobuyerActive: false
        ), ipOfflineBought: false, ipOfflineUpgrade: nil,
        ipMultUnlocked: false, bigCrunchAutobuyerActive: false, bigCrunchAutobuyerUnlocked: false,
        autobuyersGloballyOn: true,
        inAntimatterChallenge: false,
        chargeInfinityUpgradesUnlocked: false, totalInfinityCharges: 0,
        usedInfinityCharges: 0, disChargeOnReality: false,
        gainedInfinities: "1", startingAM: nil, startingBoosts: 0, startWithGalaxy: false,
        showIPRate: true, currentIPRate: "0", peakIPRate: "0", peakIPRateVal: "0",
        nextIDVisible: false, nextIDCanUnlock: false, nextIDHasIPUnlock: true,
        nextIDAmRequirement: "0", nextIDIPRequirement: "0",
        showEternityButton: false, canEternity: false, eternityGoal: "1.80e308",
        eternityUnlocked: false, gainedEP: "0", showEPRate: false,
        currentEPRate: "0", peakEPRate: "0", peakEPRateVal: "0",
        isInEternityChallenge: false,
        ecGainedCompletions: 0, ecFailedRestriction: "", ecNextGoalAt: "",
        ecHasMoreCompletions: false, ecFullyCompleted: false,
        isDilationActive: false, dilationTachyonGain: "",
        showRealityButton: false, hasRealityStudy: false, hasEnoughEPForReality: false, canReality: false, gainedRM: "", machineStats: "", gainedGlyphLevel: "", realityGainSummary: "", realityLevelStats: "", realityPPGained: "", realityShardsInfo: "", realityCelestialInfo: ""
    )
}

// MARK: - Break Infinity

struct BreakInfinityState: Equatable {
    var hasMaxedInterval: Bool   // Big Crunch autobuyer at 0.1s — unlocks break
    var isBroken: Bool           // player.break
    var upgrades: [InfinityUpgradeInfo]

    static let empty = BreakInfinityState(hasMaxedInterval: false, isBroken: false, upgrades: [])
}

// MARK: - Replicanti

struct ReplicantiUpgradeInfo: Equatable {
    let description: String
    let costDescription: String  // e.g. "+1% Costs: 1e97 IP"
    let cost: String
    let isCapped: Bool
    let canBeBought: Bool
}

struct ReplicantiState: Equatable {
    var isUnlocked: Bool
    var isUnlockAffordable: Bool
    var amount: String
    var mult: String
    var chance: String           // e.g. "1%"
    var interval: String         // e.g. "1000ms"
    var chanceUpgrade: ReplicantiUpgradeInfo
    var intervalUpgrade: ReplicantiUpgradeInfo
    var galaxyUpgrade: ReplicantiUpgradeInfo
    var galaxiesBought: Int
    var galaxiesExtra: Int
    var galaxiesMax: Int
    var canBuyGalaxy: Bool
    var unlockCost: String
    var distantRG: String
    var remoteRG: String
    var remainingTimeText: String
    var galaxyText: String
    var galaxyResetText: String  // "Reset Replicanti amount" or "Divide Replicanti by 1.80e308"
    var canSeeGalaxyButton: Bool

    // Autobuyer toggles (shown on Replicanti tab next to upgrade/galaxy buttons)
    var chanceAutoUnlocked: Bool
    var chanceAutoActive: Bool
    var intervalAutoUnlocked: Bool
    var intervalAutoActive: Bool
    var galaxiesAutoUnlocked: Bool
    var galaxiesAutoActive: Bool
    var galaxyAutoUnlocked: Bool   // Replicanti Galaxy autobuyer (3 eternities)
    var galaxyAutoActive: Bool
    var galaxyAutoEnabled: Bool    // false when TS131 bought and Ach138 not unlocked
    var isEC8Running: Bool          // Hide upgrade autobuyers during EC8

    static let empty = ReplicantiState(
        isUnlocked: false, isUnlockAffordable: false, amount: "0", mult: "x1.00",
        chance: "1%", interval: "1000ms",
        chanceUpgrade: ReplicantiUpgradeInfo(description: "", costDescription: "", cost: "0", isCapped: false, canBeBought: false),
        intervalUpgrade: ReplicantiUpgradeInfo(description: "", costDescription: "", cost: "0", isCapped: false, canBeBought: false),
        galaxyUpgrade: ReplicantiUpgradeInfo(description: "", costDescription: "", cost: "0", isCapped: false, canBeBought: false),
        galaxiesBought: 0, galaxiesExtra: 0, galaxiesMax: 0, canBuyGalaxy: false, unlockCost: "1e140",
        distantRG: "50", remoteRG: "250",
        remainingTimeText: "", galaxyText: "",
        galaxyResetText: "Reset Replicanti amount",
        canSeeGalaxyButton: false,
        chanceAutoUnlocked: false, chanceAutoActive: false,
        intervalAutoUnlocked: false, intervalAutoActive: false,
        galaxiesAutoUnlocked: false, galaxiesAutoActive: false,
        galaxyAutoUnlocked: false, galaxyAutoActive: false, galaxyAutoEnabled: true,
        isEC8Running: false
    )
}

// MARK: - Autobuyers

struct AutobuyerDimInfo: Identifiable, Equatable {
    let tier: Int
    /// Mirror of web `Autobuyer.antimatterDimension(tier).isUnlocked` — already
    /// factors in `Pelle.isDisabled` so this goes false during Doom until the
    /// matching Pelle Upgrade is bought.
    let isUnlocked: Bool
    let isBought: Bool
    let canBeBought: Bool       // total AM >= threshold
    let isActive: Bool
    let interval: Int            // ms
    let cost: String             // IP cost to upgrade interval
    let canUpgrade: Bool         // challenge completed + can afford
    let canBeUpgraded: Bool      // challenge completed (regardless of afford)
    let hasMaxedInterval: Bool
    let bulk: Int                // current bulk buy amount
    let hasMaxedBulk: Bool
    let canUpgradeBulk: Bool     // hasMaxedInterval && !hasMaxedBulk && can afford
    let mode: String             // "BUY_SINGLE" or "BUY_10"
    let antimatterCost: String   // total AM threshold to unlock

    var id: Int { tier }
}

struct AutobuyerSingleInfo: Equatable {
    let name: String
    /// Mirror of web `Autobuyer.X.isUnlocked` — false during Doom for any
    /// Pelle-gated autobuyer (tickspeed, dimboost, galaxy, AD per-tier).
    let isUnlocked: Bool
    let isBought: Bool
    let canBeBought: Bool
    let isActive: Bool
    let interval: Int
    let cost: String
    let canUpgrade: Bool
    let canBeUpgraded: Bool
    let hasMaxedInterval: Bool
    let antimatterCost: String
    let isBuyMax: Bool          // tickspeed: BUY_MAX vs BUY_SINGLE mode
    let isModeLocked: Bool      // true if challenge not completed to unlock mode toggle
}

struct DimBoostAutobuyerInfo: Equatable {
    let isUnlocked: Bool         // NormalChallenge(10).isCompleted
    let isActive: Bool
    let hasMaxedInterval: Bool
    let interval: Int
    let cost: String
    let canUpgrade: Bool
    let isBuyMaxUnlocked: Bool   // BreakInfinityUpgrade.autobuyMaxDimboosts
    let buyMaxInterval: String   // seconds (float) when buy-max mode active
    let bulk: Int                // bulk purchase amount
    let limitDimBoosts: Bool
    let maxDimBoosts: Int
    let limitUntilGalaxies: Bool
    let galaxies: Int
}

struct GalaxyAutobuyerInfo: Equatable {
    let isUnlocked: Bool         // NormalChallenge(11).isCompleted
    let isActive: Bool
    let hasMaxedInterval: Bool
    let interval: Int
    let cost: String
    let canUpgrade: Bool
    let isBuyMaxUnlocked: Bool   // EternityMilestone.autobuyMaxGalaxies (9 eternities)
    let buyMaxInterval: String   // seconds (float) when buy-max mode active
    let limitGalaxies: Bool
    let maxGalaxies: Int
}

struct BigCrunchAutobuyerInfo: Equatable {
    let isUnlocked: Bool         // NormalChallenge(12).isCompleted
    let isActive: Bool
    let hasMaxedInterval: Bool
    let interval: Int
    let cost: String
    let canUpgrade: Bool
    let mode: Int                // 0=AMOUNT, 1=TIME, 2=X_HIGHEST
    let hasAdditionalModes: Bool // EternityMilestone.bigCrunchModes
    let amount: String           // formatted IP threshold (AMOUNT mode)
    let time: String             // seconds between crunches (TIME mode)
    let xHighest: String         // multiplier of highest IP (X_HIGHEST mode)
    let isDynamic: Bool          // increaseWithMult — auto-scale threshold (AMOUNT only)

    var modeLabel: String {
        switch mode {
        case 0: "Big Crunch at X IP"
        case 1: "Seconds between Crunches"
        case 2: "X times highest IP"
        default: "Big Crunch at X IP"
        }
    }

    /// The display value for the current mode's input field.
    var currentModeAmount: String {
        switch mode {
        case 1: time
        case 2: xHighest
        default: amount
        }
    }
}

struct SacrificeAutobuyerInfo: Equatable {
    let isUnlocked: Bool         // IC2 completed
    let isActive: Bool
    let multiplier: String       // threshold multiplier (decimal input)
    let isAutomatic: Bool        // Achievement 118 — auto-sacrifices every tick
}

struct IPMultAutobuyerInfo: Equatable {
    let isUnlocked: Bool
    let isActive: Bool

    static let empty = IPMultAutobuyerInfo(isUnlocked: false, isActive: false)
}

struct ReplicantiGalaxyAutobuyerInfo: Equatable {
    let isUnlocked: Bool         // EternityMilestone.autobuyerReplicantiGalaxy (3 eternities)
    let isActive: Bool
    let isEnabled: Bool          // Achievement(138) || !TimeStudy(131)

    static let empty = ReplicantiGalaxyAutobuyerInfo(isUnlocked: false, isActive: false, isEnabled: true)
}

struct RealityAutobuyerInfo: Equatable {
    let isUnlocked: Bool        // RealityUpgrade(25).isBought
    let isActive: Bool
    let mode: Int               // 0=RM, 1=GLYPH, 2=EITHER, 3=BOTH, 4=TIME, 5=RELIC_SHARD
    let rm: String              // formatted Decimal threshold
    let glyph: Int              // glyph-level threshold
    let time: Double            // seconds threshold
    let shard: String           // formatted Decimal threshold (Effarig mode)
    let hasRelicMode: Bool      // TeresaUnlocks.effarig.canBeApplied — unlocks mode 5
    let glyphLevelCap: Int      // Glyphs.levelCap — for UI warning when glyph > cap

    static let empty = RealityAutobuyerInfo(
        isUnlocked: false, isActive: false, mode: 0,
        rm: "0", glyph: 0, time: 0, shard: "0",
        hasRelicMode: false, glyphLevelCap: 999_999
    )

    var modeLabel: String {
        switch mode {
        case 0: "Reality Machines"
        case 1: "Glyph level"
        case 2: "RM or Level"
        case 3: "RM and Level"
        case 4: "Real-time (seconds)"
        case 5: "Relic Shards"
        default: "Reality Machines"
        }
    }

    /// Labels for the two threshold inputs, per web's RealityAutobuyerBox.vue.
    var primaryInputLabel: String {
        switch mode {
        case 4: "Target Time (seconds)"
        case 5: "Target Relic Shards"
        default: "Target Reality Machines"
        }
    }

    var showsGlyphInput: Bool {
        // Glyph-level input shown for modes 1, 2, 3.
        mode == 1 || mode == 2 || mode == 3
    }
}

struct EternityAutobuyerInfo: Equatable {
    let isUnlocked: Bool
    let isActive: Bool
    let mode: Int               // 0=AMOUNT, 1=TIME, 2=X_HIGHEST
    let amount: String          // threshold value for current mode
    let isDynamic: Bool         // increaseWithMult (only for AMOUNT mode)
    let hasAdditionalModes: Bool

    static let empty = EternityAutobuyerInfo(
        isUnlocked: false, isActive: false, mode: 0,
        amount: "1", isDynamic: true, hasAdditionalModes: false
    )

    var modeLabel: String {
        switch mode {
        case 0: "Eternity at X EP"
        case 1: "Seconds between Eternities"
        case 2: "X times highest EP"
        default: "Eternity at X EP"
        }
    }
}

/// Per-tier TD autobuyer state for the Autobuyers tab
struct TDAutobuyerTierInfo: Identifiable, Equatable {
    let tier: Int
    let isActive: Bool
    var id: Int { tier }
}

/// TD autobuyers group for the Autobuyers tab
struct TDAutobuyersInfo: Equatable {
    let isUnlocked: Bool        // Autobuyer.timeDimension(1).isUnlocked
    let tiers: [TDAutobuyerTierInfo]

    static let empty = TDAutobuyersInfo(isUnlocked: false, tiers: [])
}

/// Per-upgrade dilation autobuyer state for the Autobuyers tab
struct DilationAutobuyerEntry: Identifiable, Equatable {
    let id: Int                 // 1, 2, 3
    let name: String
    let isActive: Bool
}

/// Dilation upgrade autobuyers group for the Autobuyers tab
struct DilationAutobuyersInfo: Equatable {
    let isUnlocked: Bool        // Perk.autobuyerDilation.isEffectActive
    let upgrades: [DilationAutobuyerEntry]

    static let empty = DilationAutobuyersInfo(isUnlocked: false, upgrades: [])
}

/// Per-rebuyable Reality Upgrade autobuyer. Ra V pet lv 1 unlocks all 5.
struct RealityUpgradeAutobuyerEntry: Identifiable, Equatable {
    let id: Int                 // 1..5
    let name: String
    let isActive: Bool
}

struct RealityUpgradeAutobuyersInfo: Equatable {
    let isUnlocked: Bool        // Ra.unlocks.instantECAndRealityUpgradeAutobuyers
    let upgrades: [RealityUpgradeAutobuyerEntry]

    static let empty = RealityUpgradeAutobuyersInfo(isUnlocked: false, upgrades: [])
}

/// Per-rebuyable Imaginary Upgrade autobuyer — 10 rows matching web
/// `MultipleAutobuyersBox` for `Autobuyer.imaginaryUpgrade`. Unlocked once
/// `ImaginaryUpgrade(20).canBeApplied` (Vacuum Acceleration).
struct ImaginaryUpgradeAutobuyerEntry: Identifiable, Equatable {
    let id: Int                 // 1..10
    let name: String
    let isActive: Bool
}

struct ImaginaryUpgradeAutobuyersInfo: Equatable {
    let isUnlocked: Bool
    let upgrades: [ImaginaryUpgradeAutobuyerEntry]

    static let empty = ImaginaryUpgradeAutobuyersInfo(isUnlocked: false, upgrades: [])
}

/// Per-BH-upgrade autobuyer. Ra Enslaved pet lv 1 unlocks; individual
/// entries track their own unlock state because BH2's upgrades come
/// online later than BH1's.
struct BlackHolePowerAutobuyerEntry: Identifiable, Equatable {
    let id: Int                 // 1..6 (matches BlackHolePowerUpgrade.id)
    let bhId: Int               // 1 or 2
    let type: String            // "interval" | "power" | "duration"
    let name: String            // e.g. "BH1 Interval"
    let isUnlocked: Bool
    let isActive: Bool
}

struct BlackHolePowerAutobuyersInfo: Equatable {
    let anyUnlocked: Bool
    let upgrades: [BlackHolePowerAutobuyerEntry]

    static let empty = BlackHolePowerAutobuyersInfo(anyUnlocked: false, upgrades: [])
}

/// EP Mult autobuyer for the Autobuyers tab
struct EPMultAutobuyerInfo: Equatable {
    let isUnlocked: Bool
    let isActive: Bool

    static let empty = EPMultAutobuyerInfo(isUnlocked: false, isActive: false)
}

/// Time Theorem autobuyer for the Autobuyers tab
struct TTAutobuyerInfo: Equatable {
    let isUnlocked: Bool        // Perk.ttBuySingle.isBought
    let isActive: Bool

    static let empty = TTAutobuyerInfo(isUnlocked: false, isActive: false)
}

struct AutobuyersState: Equatable {
    let isUnlocked: Bool         // total AM >= 1e40
    let allOn: Bool              // global toggle
    let allAutobuyersDisabled: Bool  // every unlocked autobuyer has isActive == false
    let dimensions: [AutobuyerDimInfo]
    let tickspeed: AutobuyerSingleInfo
    let sacrifice: SacrificeAutobuyerInfo
    let dimBoost: DimBoostAutobuyerInfo
    let galaxy: GalaxyAutobuyerInfo
    let bigCrunch: BigCrunchAutobuyerInfo
    let ipMult: IPMultAutobuyerInfo
    let eternityAutobuyer: EternityAutobuyerInfo
    let reality: RealityAutobuyerInfo
    let replicantiGalaxy: ReplicantiGalaxyAutobuyerInfo
    let replicantiUpgrades: ReplicantiUpgradeAutobuyersInfo
    let timeDimensions: TDAutobuyersInfo
    let dilationUpgrades: DilationAutobuyersInfo
    let epMult: EPMultAutobuyerInfo
    let timeTheorem: TTAutobuyerInfo
    let realityUpgradeRebuyables: RealityUpgradeAutobuyersInfo
    let imaginaryUpgradeRebuyables: ImaginaryUpgradeAutobuyersInfo
    let blackHolePower: BlackHolePowerAutobuyersInfo

    static let empty = AutobuyersState(
        isUnlocked: false, allOn: true, allAutobuyersDisabled: false, dimensions: [],
        tickspeed: AutobuyerSingleInfo(
            name: "Tickspeed", isUnlocked: false, isBought: false, canBeBought: false,
            isActive: false, interval: 500, cost: "1",
            canUpgrade: false, canBeUpgraded: false,
            hasMaxedInterval: false, antimatterCost: "1e140",
            isBuyMax: false, isModeLocked: true
        ),
        sacrifice: SacrificeAutobuyerInfo(
            isUnlocked: false, isActive: false, multiplier: "2", isAutomatic: false
        ),
        dimBoost: DimBoostAutobuyerInfo(
            isUnlocked: false, isActive: false, hasMaxedInterval: false,
            interval: 4000, cost: "1", canUpgrade: false,
            isBuyMaxUnlocked: false, buyMaxInterval: "0.5", bulk: 1,
            limitDimBoosts: false, maxDimBoosts: 1,
            limitUntilGalaxies: false, galaxies: 10
        ),
        galaxy: GalaxyAutobuyerInfo(
            isUnlocked: false, isActive: false, hasMaxedInterval: false,
            interval: 4000, cost: "1", canUpgrade: false,
            isBuyMaxUnlocked: false, buyMaxInterval: "0.5",
            limitGalaxies: false, maxGalaxies: 10
        ),
        bigCrunch: BigCrunchAutobuyerInfo(
            isUnlocked: false, isActive: false, hasMaxedInterval: false,
            interval: 4000, cost: "1", canUpgrade: false,
            mode: 0, hasAdditionalModes: false,
            amount: "1", time: "1", xHighest: "1",
            isDynamic: true
        ),
        ipMult: .empty,
        eternityAutobuyer: .empty,
        reality: .empty,
        replicantiGalaxy: .empty,
        replicantiUpgrades: .empty,
        timeDimensions: .empty,
        dilationUpgrades: .empty,
        epMult: .empty,
        timeTheorem: .empty,
        realityUpgradeRebuyables: .empty,
        imaginaryUpgradeRebuyables: .empty,
        blackHolePower: .empty
    )
}

struct ReplicantiUpgradeAutobuyerEntry: Identifiable, Equatable {
    let id: Int           // 1=Chance, 2=Interval, 3=Max Galaxies
    let name: String
    let isUnlocked: Bool
    let isActive: Bool
}

struct ReplicantiUpgradeAutobuyersInfo: Equatable {
    let isAnyUnlocked: Bool
    let isGroupActive: Bool  // player.auto.replicantiUpgrades.isActive
    let intervalText: String // shared interval for the group
    let entries: [ReplicantiUpgradeAutobuyerEntry]

    static let empty = ReplicantiUpgradeAutobuyersInfo(
        isAnyUnlocked: false, isGroupActive: true, intervalText: "", entries: []
    )
}

// MARK: - Infinity Dimensions

struct InfinityDimState: Identifiable, Equatable {
    let tier: Int
    let isUnlocked: Bool
    let canUnlock: Bool
    let amount: String
    let multiplier: String
    let cost: String
    let purchases: Int
    let rateOfChange: String?
    let isAvailableForPurchase: Bool
    let isAffordable: Bool
    let isCapped: Bool
    let amRequirement: String
    let amRequirementReached: Bool
    let hasPrevTier: Bool
    let isAutobuyerUnlocked: Bool
    let isAutobuyerActive: Bool

    var id: Int { tier }
    var displayName: String { "\(DimensionState.safeTierName(tier)) Infinity Dimension" }
    var shortDisplayName: String { "\(DimensionState.safeTierName(tier)) Infinity" }

    /// Web parity: row is visible when eternityReached || isUnlocked || canUnlock || amount > 0 || hasPrevTier
    var showRow: Bool { isUnlocked || canUnlock || amRequirementReached || hasPrevTier }
}

// MARK: - Tesseracts (Enslaved completion reward)

struct TesseractInfo: Equatable {
    var bought: Int = 0
    var extra: Int = 0
    var nextCost: String = ""
    var canBuy: Bool = false
    var nextCapIncrease: String = ""
    var totalCap: String = ""

    static let empty = TesseractInfo()
}

struct InfinityDimsInfo: Equatable {
    let isUnlocked: Bool
    let eternityReached: Bool
    var infinityPower: String
    var powerMultiplier: String
    let conversionRate: String
    let powerPerSecond: String
    let totalDimCap: String
    let isAnyAutobuyerUnlocked: Bool
    let isEC8Running: Bool
    let dimensions: [InfinityDimState]
    var tesseracts: TesseractInfo = .empty

    static let empty = InfinityDimsInfo(
        isUnlocked: false, eternityReached: false, infinityPower: "0", powerMultiplier: "x1.00",
        conversionRate: "7", powerPerSecond: "0", totalDimCap: "2.00 M",
        isAnyAutobuyerUnlocked: false, isEC8Running: false,
        dimensions: (1...8).map { tier in
            InfinityDimState(
                tier: tier, isUnlocked: false, canUnlock: false,
                amount: "0", multiplier: "x1.00", cost: "0",
                purchases: 0, rateOfChange: nil,
                isAvailableForPurchase: false, isAffordable: false, isCapped: false,
                amRequirement: "0", amRequirementReached: false,
                hasPrevTier: tier == 1,
                isAutobuyerUnlocked: false, isAutobuyerActive: false
            )
        }
    )
}

// MARK: - Normal Challenges

struct NormalChallengeInfo: Identifiable, Equatable {
    let id: Int
    let name: String
    let description: String
    let reward: String
    let isUnlocked: Bool
    let isRunning: Bool        // isOnlyActiveChallenge (avoids IC1 false positive)
    let isCompleted: Bool
    let lockedAt: String       // formatted infinity count needed, empty if 0
    /// True when inside The Nameless Ones' Reality and this challenge is in
    /// `Enslaved.BROKEN_CHALLENGES` — goal becomes unreachable (`DC.E1E15`).
    /// Web `NormalChallengeBox.vue:51` replaces the status badge with a
    /// "Broken" label and suppresses the Completed marker.
    let isBroken: Bool

    var capitalizedDescription: String {
        description.prefix(1).uppercased() + description.dropFirst()
    }
}

struct NormalChallengesState: Equatable {
    let challenges: [NormalChallengeInfo]
    let isAnyRunning: Bool
    let currentChallengeId: Int
    let currentInfinities: Int
    var retryChallenge: Bool

    static let empty = NormalChallengesState(
        challenges: [], isAnyRunning: false, currentChallengeId: 0,
        currentInfinities: 0, retryChallenge: false
    )
}

// MARK: - Infinity Challenges

struct InfinityChallengeInfo: Identifiable, Equatable {
    let id: Int
    let description: String
    let goal: String
    let reward: String
    let rewardEffect: String?
    let isUnlocked: Bool
    let isRunning: Bool
    let isCompleted: Bool

    var capitalizedDescription: String {
        description.prefix(1).uppercased() + description.dropFirst()
    }
}

struct InfinityChallengesState: Equatable {
    let challenges: [InfinityChallengeInfo]
    let isAnyRunning: Bool
    let nextICUnlockAM: String?
    var retryChallenge: Bool
    /// Mirror of `player.options.showAllChallenges`. Toggle is gated on
    /// `engine.eternityUnlocked` (web `ChallengeTabHeader` visibility).
    var showAllChallenges: Bool

    static let empty = InfinityChallengesState(
        challenges: [], isAnyRunning: false, nextICUnlockAM: nil,
        retryChallenge: false, showAllChallenges: false
    )
}

// MARK: - Eternity Challenges

struct EternityChallengeInfo: Identifiable, Equatable {
    let id: Int
    let description: String
    let goal: String
    let reward: String
    let rewardEffect: String?
    let completions: Int
    let maxCompletions: Int      // usually 5
    let isUnlocked: Bool         // Time Study purchased (can start)
    let isRunning: Bool
    let isFullyCompleted: Bool
    let canBeUnlocked: Bool      // requirements met, can purchase the EC Time Study
    let hasUnlocked: Bool        // has ever had this EC unlocked (reality bit)
}

struct EternityChallengesState: Equatable {
    let challenges: [EternityChallengeInfo]
    let isAnyRunning: Bool
    /// Mirror of `Perk.autocompleteEC1.canBeApplied` — gates the Auto EC toggle.
    let autoECVisible: Bool
    /// Mirror of `player.reality.autoEC`.
    let autoECActive: Bool
    /// Mirror of `player.options.showAllChallenges`. Toggle is gated on
    /// `engine.eternityUnlocked`; filter additionally requires
    /// `realityUnlocked` per web `EternityChallengesTab.vue`.
    let showAllChallenges: Bool

    static let empty = EternityChallengesState(
        challenges: [], isAnyRunning: false,
        autoECVisible: false, autoECActive: false,
        showAllChallenges: false
    )
}

// MARK: - Statistics

struct StatisticsState: Equatable {
    // General (always visible)
    let totalAntimatter: String
    let realTimePlayed: String
    let saveCreatedTime: Double          // epoch ms — formatted in Swift
    let saveAge: String                  // pre-formatted TimeSpan ("3 days, 2 hours, …")
    let matterScale: [String]
    let totalNews: Int
    let uniqueNews: Int
    let secretAchievementCount: Int
    let paperclips: Int                  // 0 = hide line
    let fullGameCompletions: Int         // 0 = hide block
    let fullTimePlayed: String?          // total real time across all completions (when fullGameCompletions > 0)

    // Doom (always read; banner only shows when doomed)
    let isDoomed: Bool
    let realTimeDoomed: String?          // formatted TimeSpan, nil when not doomed

    // Infinity (gated)
    let infinityUnlocked: Bool
    let infinityCount: String?
    let bankedInfinities: String?
    let bestInfinityTime: String?
    let thisInfinityTime: String?
    let thisInfinityRealTime: String?    // shown post-Reality
    let bestIPPerMin: String?
    let projectedBankedOnEternity: String?  // shown when projectedBanked > 0
    let projectedBankedRatePerMin: String?  // shown alongside projected — "X per minute"

    // Eternity (gated)
    let eternityUnlocked: Bool
    let eternityCount: String?
    let bestEternityTime: String?
    let thisEternityTime: String?
    let thisEternityRealTime: String?    // shown post-Reality
    let bestEPPerMin: String?

    // Reality (gated)
    let realityUnlocked: Bool
    let realityCount: String?
    let bestRealityTime: String?
    let bestRealityRealTime: String?
    let thisRealityTime: String?
    let thisRealityRealTime: String?
    let totalTimePlayedGameTime: String? // "Your existence has spanned X of time. (game time)"
    let bestRMPerMin: String?
    let bestGlyphRarity: String?

    static let empty = StatisticsState(
        totalAntimatter: "0", realTimePlayed: "0 seconds",
        saveCreatedTime: Date().timeIntervalSince1970 * 1000,
        saveAge: "0 seconds",
        matterScale: ["There is no antimatter yet."],
        totalNews: 0, uniqueNews: 0, secretAchievementCount: 0,
        paperclips: 0, fullGameCompletions: 0, fullTimePlayed: nil,
        isDoomed: false, realTimeDoomed: nil,
        infinityUnlocked: false, infinityCount: nil, bankedInfinities: nil,
        bestInfinityTime: nil, thisInfinityTime: nil, thisInfinityRealTime: nil,
        bestIPPerMin: nil,
        projectedBankedOnEternity: nil, projectedBankedRatePerMin: nil,
        eternityUnlocked: false, eternityCount: nil,
        bestEternityTime: nil, thisEternityTime: nil, thisEternityRealTime: nil,
        bestEPPerMin: nil,
        realityUnlocked: false, realityCount: nil,
        bestRealityTime: nil, bestRealityRealTime: nil,
        thisRealityTime: nil, thisRealityRealTime: nil,
        totalTimePlayedGameTime: nil,
        bestRMPerMin: nil, bestGlyphRarity: nil
    )
}

// MARK: - Multiplier Breakdown

struct MultiplierBreakdownResourceOption: Equatable, Identifiable, Hashable {
    /// Stable web-side ID (matches `player.options.multiplierTab.currTab`).
    let id: Int
    let key: String        // "AM" / "tickspeed" / "AD" / "IP" / …
    let label: String      // "Antimatter Production" / …
    let isActive: Bool
}

struct MultiplierBreakdownEntryNode: Equatable, Identifiable, Hashable {
    var id: String { key }
    let key: String
    let name: String
    /// Pre-formatted "  10.0%: Achievements (×2.34, ^1.05)" style string.
    let displayString: String
    /// Signed fraction of the bar — positive for boosters, negative for nerfs.
    let percent: Double
    let isNerf: Bool
    let isVisible: Bool
    let hasChildren: Bool
    /// Unicode prefix (Ω/∞/Δ/Ψ/Ϟ/etc.) — empty when none.
    let iconText: String
    /// SF Symbol fallback for FA glyphs ("trophy"/"clock"/…) — empty when none.
    let iconSFSymbol: String
    /// Background hex from `--color-X` CSS variable, resolved JS-side.
    let iconColor: String
    /// "white" or "black" — for legibility on the colored bar.
    let iconTextColor: String
}

struct MultiplierBreakdownResource: Equatable {
    let key: String
    let name: String
    let totalString: String
    let isEmpty: Bool
    let disabledText: String
    let isDilated: Bool
    let dilationString: String?        // pre-formatted "Dilation Effect: …", nil when not dilated
    let inNC12Notice: Bool             // show NC12 inaccuracy caveat for AD_total
    let isADTotal: Bool                // show base-AD-production caveat
    let hasAltGroup: Bool
    let allowPowerToggle: Bool
    let hasSeenPowers: Bool
    let entries: [MultiplierBreakdownEntryNode]
}

struct MultiplierBreakdownState: Equatable {
    let availableResources: [MultiplierBreakdownResourceOption]
    let currentResourceId: Int
    /// Persisted via `player.options.multiplierTab.replacePowers`.
    let replacePowers: Bool
    /// Persisted via `player.options.multiplierTab.showAltGroup`.
    let showAltGroup: Bool
    /// The fully-resolved entry tree for the current resource.
    let resource: MultiplierBreakdownResource?

    static let empty = MultiplierBreakdownState(
        availableResources: [],
        currentResourceId: 0,
        replacePowers: false,
        showAltGroup: false,
        resource: nil
    )
}

// MARK: - Glyph Set Records

struct GlyphSetRecord: Equatable, Identifiable {
    var id: String { label }
    let label: String       // "Best Reality Machines gained"
    let value: String       // "12.34 RM"
    let glyphs: [GlyphPresetGlyph]
}

struct GlyphSetRecordsState: Equatable {
    let records: [GlyphSetRecord]
    static let empty = GlyphSetRecordsState(records: [])
}

// MARK: - Speedrun Records (Previous Speedruns)

struct SpeedrunPreviousMilestone: Equatable, Identifiable {
    let id: Int             // milestone index (matches speedrun-milestones game DB)
    let name: String        // milestone name
    let timeMs: Double      // 0 if unreached
}

struct SpeedrunPreviousRun: Equatable, Identifiable {
    let id: String          // run name as the dict key (web uses name as key; we dedupe Swift-side)
    let name: String
    let isSegmented: Bool
    let totalTimeMs: Double
    let dateFinishedMs: Double  // 0 = unknown
    let milestones: [SpeedrunPreviousMilestone]
}

struct SpeedrunRecordsState: Equatable {
    let runs: [SpeedrunPreviousRun]
    static let empty = SpeedrunRecordsState(runs: [])
}

// MARK: - Challenge Records

struct ChallengeRecordsState: Equatable {
    let normalTimes: [String]           // 11 entries (C2–C12): formatted time or "Not completed"
    let normalSum: String?              // nil if not all completed
    let showInfinityChallenges: Bool
    let infinityTimes: [String]         // 8 entries (IC1–IC8)
    let infinitySum: String?

    static let empty = ChallengeRecordsState(
        normalTimes: Array(repeating: "Not completed", count: 11),
        normalSum: nil,
        showInfinityChallenges: false,
        infinityTimes: Array(repeating: "Not completed", count: 8),
        infinitySum: nil
    )
}

// MARK: - Past Prestige Runs

struct RecentRunRow: Equatable, Identifiable {
    let id: Int
    let label: String                   // "Last", "2 ago", … "10 ago", "Average"
    let isEmpty: Bool
    let gameTime: String
    let realTime: String                // pre-formatted real time (only shown when `hasRealTime`)
    let currencyGain: String
    let prestigeCount: String
    let currencyRate: String
    let prestigeCountRate: String
    let challenge: String
    /// Eternity layer: Tachyon Particles (extra[0]). Empty when not gated.
    let tachyonParticles: String
    /// Reality layer: Glyph Level (extra[0]). Empty when not Reality.
    let glyphLevel: String
    /// Reality layer: Relic Shards (extra[1]). Empty when not gated.
    let relicShards: String
    /// Reality layer: Relic Shards / minute (when displayMode == .rate).
    let relicShardRate: String
}

enum PrestigeRunDisplayMode: Int, CaseIterable {
    case absoluteGain = 0
    case rate = 1
    case currency = 2
    case prestigeCount = 3

    var label: String {
        switch self {
        case .absoluteGain:  "Showing total resource gain"
        case .rate:          "Showing resource gain rate"
        case .currency:      "Showing prestige currency"
        case .prestigeCount: "Showing prestige count"
        }
    }

    var columnHeaders: (String, String) {
        switch self {
        case .absoluteGain:  ("Gained", "Count")
        case .rate:          ("Gain Rate", "Count Rate")
        case .currency:      ("Gained", "Gain Rate")
        case .prestigeCount: ("Count", "Count Rate")
        }
    }

    var next: PrestigeRunDisplayMode {
        PrestigeRunDisplayMode(rawValue: (rawValue + 1) % 4) ?? .absoluteGain
    }
}

struct PrestigeRunsSection: Equatable {
    let name: String                    // "Infinity" / "Eternity" / "Reality"
    let plural: String                  // "Infinities" / "Eternities" / "Realities"
    let currencyLabel: String           // "IP" / "EP" / "RM"
    let isUnlocked: Bool
    let runs: [RecentRunRow]            // 11 entries (10 runs + average)
    let hasChallenge: Bool
    /// `PlayerProgress.seenAlteredSpeed()` — shows the Real Time column when true.
    var hasRealTime: Bool = false
    /// Eternity layer only: `PlayerProgress.dilationUnlocked()` — shows the
    /// Tachyon Particles column.
    var hasTachyonParticles: Bool = false
    /// Reality layer only — Glyph Level column is always shown when the
    /// section is unlocked. Bool exists for symmetry with the other extras.
    var hasGlyphLevel: Bool = false
    /// Reality layer only: `TeresaUnlocks.effarig.canBeApplied` — shows the
    /// Relic Shards column (+ rate variant when displayMode == .rate).
    var hasRelicShards: Bool = false
    /// Reality layer only: `MachineHandler.currentIMCap > 0` — when true,
    /// the RM column is replaced by "iM Cap" showing run[7] (projected iM
    /// cap at end of run). Rate column shows "N/A" because the projected
    /// cap isn't a per-minute quantity.
    var hasIMCap: Bool = false
}

struct PastPrestigeRunsState: Equatable {
    let sections: [PrestigeRunsSection]
    let displayMode: PrestigeRunDisplayMode

    static let empty = PastPrestigeRunsState(
        sections: [
            PrestigeRunsSection(name: "Infinity", plural: "Infinities", currencyLabel: "IP",
                                isUnlocked: false, runs: [], hasChallenge: false),
            PrestigeRunsSection(name: "Eternity", plural: "Eternities", currencyLabel: "EP",
                                isUnlocked: false, runs: [], hasChallenge: false),
            PrestigeRunsSection(name: "Reality", plural: "Realities", currencyLabel: "RM",
                                isUnlocked: false, runs: [], hasChallenge: false),
        ],
        displayMode: .absoluteGain
    )
}

// MARK: - Time Dimensions

struct TimeDimensionInfo: Identifiable, Equatable {
    let tier: Int
    let isUnlocked: Bool
    let amount: String
    let multiplier: String
    let bought: Int
    let cost: String
    let rateOfChange: String?
    let isAffordable: Bool
    /// For TD5-8: whether the required Time Study is bought
    let requirementReached: Bool
    /// For TD5-8 when not unlocked: the TT cost to unlock (e.g. "Unlock: 1 TT")
    let ttCost: String?
    /// Per-row autobuyer active state (only meaningful when areAutobuyersUnlocked)
    let isAutoActive: Bool

    var id: Int { tier }
    var displayName: String { "\(DimensionState.safeTierName(tier)) Time Dimension" }
    var shortDisplayName: String { "\(DimensionState.safeTierName(tier)) Time Dim" }
}

struct TimeDimensionsState: Equatable {
    let timeShards: String
    let shardsPerSecond: String
    let totalTickspeedUpgrades: Int
    let multPerTickspeed: String
    let upgradeThreshold: String
    let dimensions: [TimeDimensionInfo]
    let areAutobuyersUnlocked: Bool  // RealityUpgrade(13).isBought

    static let empty = TimeDimensionsState(
        timeShards: "0", shardsPerSecond: "0",
        totalTickspeedUpgrades: 0, multPerTickspeed: "x1.00",
        upgradeThreshold: "0",
        dimensions: (1...8).map { tier in
            TimeDimensionInfo(
                tier: tier, isUnlocked: tier <= 4,
                amount: "0", multiplier: "x1.00",
                bought: 0, cost: "0", rateOfChange: nil,
                isAffordable: false, requirementReached: tier <= 4,
                ttCost: nil, isAutoActive: false
            )
        },
        areAutobuyersUnlocked: false
    )
}

// MARK: - Eternity Upgrades

struct EternityUpgradeInfo: Identifiable, Equatable {
    let id: String          // JS key: "idMultEP", "idMultEternities", etc.
    let description: String
    let cost: String
    let effectText: String
    let isBought: Bool
    let isAffordable: Bool
    /// The upgrade's effect has reached its `config.cap` (web `EffectDisplay.vue`
    /// `reachedCap`). Only `idMultICRecords` (EU3) has a cap today. When true the
    /// card shows "Capped: …" and `effectText` is clamped to the cap value.
    let isCapped: Bool
}

struct EPMultState: Equatable {
    let currentMult: String     // e.g. "x25.00"
    let cost: String
    let isAffordable: Bool
    let isCapped: Bool
    let isAutoUnlocked: Bool    // RealityUpgrade(13).isBought
    let isAutoActive: Bool      // Autobuyer.epMult.isActive

    static let empty = EPMultState(currentMult: "x1.00", cost: "500", isAffordable: false, isCapped: false,
                                   isAutoUnlocked: false, isAutoActive: false)
}

// MARK: - Eternity Milestones

struct EternityMilestoneInfo: Identifiable, Equatable {
    let id: String              // JS key: "autobuyerIPMult", "keepAutobuyers", etc.
    let eternities: Int
    let reward: String
    let isReached: Bool
    /// Mirrors `config.pelleUseless` from `eternity-milestones.js`. When true,
    /// the milestone's reward is nullified during Pelle's Doomed Reality.
    /// Drives strikethrough in the milestone card. Most milestones (≈18) are
    /// flagged true; a handful (`keepAutobuyers`, `bigCrunchModes`, `autoEP`,
    /// `autobuyerEternity`, etc.) are still useful in doom and stay un-struck.
    let pelleUseless: Bool
    /// Mirrors `config.activeCondition()` from `eternity-milestones.js` —
    /// the web `v-tooltip` text on the milestone button. Non-empty only for the
    /// three offline milestones (autoEP, autoEternities, autoInfinities); it
    /// lists the conditions that must be met for the offline gain to be "Active"
    /// rather than "(Inactive)". Empty for every other milestone. Drives the
    /// info-button affordance in `MilestoneCard`.
    let activeCondition: String
}

// MARK: - Time Studies

struct TimeStudyInfo: Identifiable, Equatable {
    let id: Int              // normal: 11-234, EC: -1..-12, dilation: -100, TD5-8: -105..-108, reality: -200
    let isBought: Bool
    let canBeBought: Bool    // prerequisites met (tree path available)
    let isAffordable: Bool   // has enough TT to purchase
    let cost: Int            // Time Theorems
    let type: StudyType      // for coloring
    let description: String  // study effect description
    let effectText: String   // "Currently: x1.00" or empty

    // EC-only fields (empty/zero for non-EC studies)
    let completions: Int             // 0-5
    let requirementText: String      // e.g. "1,300/1,300 Tickspeed upgrades" or "Use only the Antimatter Dimension path"
    let isRunning: Bool              // currently running this EC
    let isUnlocked: Bool             // EC is unlocked (purchased from tree)

    enum StudyType: Int, Equatable {
        case normal, antimatter, infinity, time
        case active, passive, idle
        case light, dark
        case ec, dilation, timeDimension, reality
        case triad
    }

    /// Builds a `TimeStudyInfo` from one row of `_nativeTimeStudiesState()`'s
    /// JSON output. The `type` argument is supplied by the caller because
    /// path color is a Swift-side mapping (`GameEngine.studyPathMap`), not
    /// JS state.
    ///
    /// Numeric / bool fields are read via `NSNumber` accessors rather than
    /// `as? Bool` / `as? Int` to skip the Swift↔ObjC bridge `tryCast` chain
    /// — Time Profiler showed those casts dominating new-`pollTimeStudies`
    /// cost. `JSONSerialization` returns `NSNumber` boxes; `boolValue` /
    /// `intValue` unwrap them directly.
    init(dict d: [String: Any], type: StudyType) {
        self.id              = (d["id"]            as? NSNumber)?.intValue  ?? 0
        self.isBought        = (d["bought"]        as? NSNumber)?.boolValue ?? false
        self.canBeBought     = (d["canBuy"]        as? NSNumber)?.boolValue ?? false
        self.isAffordable    = (d["afford"]        as? NSNumber)?.boolValue ?? false
        self.cost            = (d["cost"]          as? NSNumber)?.intValue  ?? 0
        self.type            = type
        self.description     = (d["desc"]          as? String)              ?? ""
        self.effectText      = (d["effect"]        as? String)              ?? ""
        self.completions     = (d["ecCompletions"] as? NSNumber)?.intValue  ?? 0
        self.requirementText = (d["req"]           as? String)              ?? ""
        self.isRunning       = (d["ecRunning"]     as? NSNumber)?.boolValue ?? false
        self.isUnlocked      = (d["ecUnlocked"]    as? NSNumber)?.boolValue ?? false
    }
}

struct TimeTheoremShopState: Equatable {
    let theorems: String         // current TT owned
    let totalTheorems: String    // total TT ever
    let amCost: String
    let ipCost: String
    let epCost: String
    let canBuyAM: Bool
    let canBuyIP: Bool
    let canBuyEP: Bool
    /// Space Theorems currently available to spend on mutually-exclusive
    /// Time Studies. Pre-V = 0.
    let availableSpaceTheorems: Int
    /// Total ST ever earned (`V.spaceTheorems`). Used as a "has V been
    /// unlocked" gate — when 0, the ST counter line is hidden entirely.
    let totalSpaceTheorems: Int

    static let empty = TimeTheoremShopState(
        theorems: "0", totalTheorems: "0",
        amCost: "0", ipCost: "0", epCost: "0",
        canBuyAM: false, canBuyIP: false, canBuyEP: false,
        availableSpaceTheorems: 0, totalSpaceTheorems: 0
    )
}

struct StudyPresetInfo: Equatable, Identifiable {
    let id: Int        // 0-5
    let name: String   // up to 4 ASCII chars, empty = unnamed
    let studies: String // export string (empty = no preset saved)
}

/// Preview data for a study string import — computed JS-side
struct StudyPreviewInfo: Equatable {
    let isValid: Bool
    // "Into empty tree" info
    let emptyStudies: String       // e.g. "11, 22, 32, ... and EC1"
    let emptyCostTT: Int
    let emptyDimPaths: String      // e.g. "Antimatter Dims"
    let emptyPacePaths: String     // e.g. "Active"
    let emptyEC: Int               // 0 = none
    let emptyStartEC: Bool
    // "With current tree" info
    let combinedStudies: String
    let combinedCostTT: Int
    let combinedDimPaths: String
    let combinedPacePaths: String
    let combinedEC: Int
    let combinedStartEC: Bool
    // Study IDs for mini tree preview (from empty tree import)
    let previewStudyIDs: [Int]

    static let empty = StudyPreviewInfo(
        isValid: false, emptyStudies: "", emptyCostTT: 0,
        emptyDimPaths: "", emptyPacePaths: "", emptyEC: 0, emptyStartEC: false,
        combinedStudies: "", combinedCostTT: 0,
        combinedDimPaths: "", combinedPacePaths: "", combinedEC: 0, combinedStartEC: false,
        previewStudyIDs: []
    )
}

struct TimeStudiesState: Equatable {
    let studies: [TimeStudyInfo]
    let shop: TimeTheoremShopState
    let respecOnNextEternity: Bool
    let preferredDimPaths: [Int] // ordered priority list (1=Antimatter, 2=Infinity, 3=Time), up to 2 entries
    let preferredPacePath: Int   // 0=none, 4=Active, 5=Passive, 6=Idle
    let usePriority: Bool        // when true, the Dimension Split uses ordered 1st/2nd preference (web `usePriority`)
    let presets: [StudyPresetInfo]  // 6 save slots

    static let empty = TimeStudiesState(studies: [], shop: .empty, respecOnNextEternity: false,
                                        preferredDimPaths: [], preferredPacePath: 0, usePriority: false,
                                        presets: (0..<6).map { StudyPresetInfo(id: $0, name: "", studies: "") })
}

// MARK: - Glyphs

struct GlyphInfo: Identifiable, Equatable {
    let id: Int
    let type: String
    let symbol: String
    let level: Int
    /// Adjusted level after celestial effects — `getAdjustedGlyphLevel(g)`
    /// for active glyphs, `getAdjustedGlyphLevel(g, 0)` for inventory.
    /// Differs from `level` under Pelle's doom (capped to `Pelle.glyphMaxLevel`),
    /// inside Effarig's Reality (capped to `Effarig.glyphLevelCap`), or inside
    /// The Nameless Ones' Reality (boosted to `Enslaved.glyphLevelMin`).
    /// Web `GlyphTooltip.vue` shows it in red ▼ when capped, green ▲ when boosted.
    var displayLevel: Int = 0
    let rarityPercent: Double
    let rarityName: String
    let effects: [String]
    let shortEffects: [String]  // compact descriptions for equipped modal (e.g. "AD power +0.047")
    /// Hex color string per effect entry; non-empty means the effect's value
    /// is in an "altered" state (web's `alterationType` in EMPOWER/BOOST and
    /// `alteredColor()` from `GlyphAlteration`). Rendered with the `▲`
    /// prefix already baked into the corresponding `effects[i]` string.
    let effectBoostColors: [String]
    /// Hex color per effect entry for the ADDITION alteration. Non-empty when
    /// the effect's `singleDesc` contains a `[...]` bracketed text section
    /// AND the per-type addition is active (e.g. `effarigforgotten` when
    /// effarig glyphs are alteration-added). The bracketed text is rendered
    /// bold in this color by the rich card; brackets themselves are stripped.
    let effectAdditionColors: [String]
    let effectCount: Int
    /// Raw glyph effect bitmask (`glyph.effects`). Drives the positional
    /// effect dots in `GlyphComponent` (each effect occupies a fixed angular
    /// slot, matching web `GlyphComponent.vue` `effectIconPos`). 0 when the
    /// source didn't carry the bitmask (e.g. celestial run records) — the
    /// component falls back to the legacy centered-row rendering.
    var effectBitmask: Int = 0
    let typeColor: String
    let rarityColor: String
    let idx: Int
    let sacrificeGain: String   // formatted sacrifice value (empty if sacrifice not unlocked)
    /// `format(GlyphSacrificeHandler.glyphRefinementGain(g), 2, 2)` — capped refine value.
    /// Empty string when alchemy not unlocked for this type, or for companion/cursed/reality.
    let refineReward: String
    /// `format(glyphRawRefinementGain(g) / glyphRefinementEfficiency, 2, 2)` — uncapped value.
    /// Differs from `refineReward` only when the alchemy resource is at cap; web shows
    /// "Refine: X (Actual value due to cap: Y)" in that case.
    let uncappedRefineReward: String
    /// `format(AutoGlyphProcessor.filterValue(g), 1, 1)`. Empty unless score mode is
    /// SPECIFIED_EFFECT or EFFECT_SCORE, AND type is not companion/cursed/reality.
    let filterScore: String
    /// `Pelle.getSpecialGlyphEffectDescription(type)` when `Pelle.specialGlyphEffect.isUnlocked`.
    /// Rendered as the last entry in the rich card's effect list.
    let chaosDescription: String
    /// `g.cosmetic` is truthy — a per-glyph cosmetic appearance (e.g. Music Glyph)
    /// is applied. Drives the tooltip's "Reset appearance" affordance.
    var hasCustomCosmetic: Bool = false
    /// `g.fixedCosmetic` is truthy — perk-created Music Glyphs lock their cosmetic;
    /// the appearance can't be changed or reset (web `SingleGlyphAppearanceModal.setType`).
    var isFixedCosmetic: Bool = false
}

struct GlyphEffectDisplay: Identifiable, Equatable {
    let id: String
    let description: String
    let typeColor: String
    let isCapped: Bool
}

struct GlyphSacrificeInfo: Identifiable, Equatable {
    var id: String { type }
    let type: String
    let symbol: String
    let color: String
    let amount: String
    let boost: String
}

struct GlyphLevelFactor: Equatable, Identifiable {
    var id: String { name }
    let name: String       // e.g. "EP", "Replicanti", "Dilated Time"
    let formula: String    // e.g. "0.016 × EP^0.016"
    let value: String      // formatted contribution value
    let op: String         // "×" or "+" or "/"
}

struct GlyphLevelFactorsState: Equatable {
    var factors: [GlyphLevelFactor]
    var finalLevel: String
    static let empty = GlyphLevelFactorsState(factors: [], finalLevel: "")
}

struct GlyphsTabState: Equatable {
    var equippedGlyphs: [GlyphInfo?]
    /// Equipped glyphs filtered to non-nil and sorted by web's `standardOrder`
    /// (`["reality","effarig","power","infinity","replication","time","dilation","cursed","companion"]`).
    /// Used by the all-equipped summary sheet; `equippedGlyphs` (slot order, with nulls)
    /// is still consumed by the in-tab equipped-slot views.
    var equippedSortedGlyphs: [GlyphInfo]
    var activeSlotCount: Int
    var inventory: [GlyphInfo]
    var totalSlots: Int
    var protectedRows: Int
    var currentEffects: [GlyphEffectDisplay]
    var sacrificeUnlocked: Bool
    var sacrificeTotals: [GlyphSacrificeInfo]
    var respec: Bool
    /// `player.options.respecIntoProtected` — when true, glyphs unequipped on
    /// Reality (or via respec) land in the protected rows instead of main
    /// inventory. Mirrors web `EquippedGlyphs.vue` "Unequip Glyphs to:" toggle.
    var respecIntoProtected: Bool = false
    var setName: String            // flavor name e.g. "Huggable Power"
    /// Hex color for `setName` — picked JS-side by a simplified
    /// `GlyphSetName.mainGlyphName` (cursed → celestials purple, else dominant
    /// type's border color). Full web logic deferred — see
    /// `.scratch/glyph-set-name-parity.md`.
    var setNameColor: String = "#ffffff"

    // CGE-3 unique-glyph notice gates — drives the "You cannot have more than
    // one Effarig or Reality Glyph equipped each." line.
    var hasEffarig: Bool = false
    var hasReality: Bool = false

    // CGE-8 — `player.options.glyphTextColors`. When false, suppress the
    // type-color + halo treatment on effect/sacrifice text.
    var glyphTextColors: Bool = true

    // SAC-3 Altered Glyphs section (Ra-unlocked card with 3 colored thresholds).
    var alterationsUnlocked: Bool = false
    var hideAlteration: Bool = false
    var additionThresholdText: String = ""
    var additionThresholdColor: String = ""
    var empowermentThresholdText: String = ""
    var empowermentThresholdColor: String = ""
    var boostingThresholdText: String = ""
    var boostingThresholdColor: String = ""
    var maxSacrificeText: String = ""

    // SAC-4/5 Teresa multiplier line + Reality glyph note.
    var teresaMult: Double = 1
    var teresaMultText: String = ""  // Pre-formatted "×5.15e46" — Double can't render past 1e15
    var lastMachinesText: String = ""
    var realityGlyphSeen: Bool = false

    // GlyphPeek
    var canPeek: Bool              // Reality study is bought (show glyph preview)
    var peekGlyphs: [GlyphInfo]    // upcoming glyph choices preview
    var peekLevel: Int             // glyph level for this Reality

    // Reality Reminder
    var reminderText: String       // summary text for non-expanded state
    var reminderIsGood: Bool       // green vs red text
    var reminderSuggestions: [String]  // individual checklist items

    // Glyph Level Factors
    var levelFactors: GlyphLevelFactorsState

    // Auto Glyph Arrangement
    var autoSortMode: Int          // 0=None, 1=Level, 2=Power, 3=Effect, 4=Score
    var autoCollapse: Bool
    var autoAutoCleanUnlocked: Bool // V achievement: VUnlocks.autoAutoClean.canBeApplied
    var autoAutoClean: Bool
    var applyFilterToPurge: Bool
    var hasGlyphFilter: Bool       // EffarigUnlock.glyphFilter.isUnlocked
    var hasGlyphWeights: Bool      // EffarigUnlock.adjuster.isUnlocked — gates "Adjust Weights" button

    // Remove Weaker Glyphs
    var isRefining: Bool           // drives verb (Refine/Sacrifice/Delete)
    var hasNegativeEffectScore: Bool

    // Effarig's Reality banner state — surfaces the current run stage and glyph-level cap
    // when the player is inside an Effarig run. Populated by `_nativeEffarigRunMeta()`
    // appended to the bulk glyphs JSON poll, so it stays live while the user is on this tab.
    var effarigRunning: Bool
    var effarigStageName: String   // "Infinity" / "Eternity" / "Reality"
    var effarigGlyphLevelCap: Int

    // Undo — TeresaUnlocks.undo + undo stack non-empty + inventory has space + not doomed
    var canUndoGlyph: Bool

    /// `isInCelestialReality()` — gates the "Repeat this Celestial's Reality"
    /// auto-restart toggle (mirrors web `GlyphsTab.vue:128-146`).
    var inCelestialReality: Bool = false
    /// `player.options.retryCelestial` — current value of the auto-restart toggle.
    var retryCelestialEnabled: Bool = false
    /// `Enslaved.isRunning && any equipped glyph was level-boosted by Enslaved.glyphLevelMin`.
    /// Drives the "done... what little... I can... with Glyphs..." flavor line above
    /// the equipped glyphs (web `GlyphsTab.vue:71-75`).
    var showEnslavedHint: Bool = false

    // Glyph instability flavor — web `GlyphsTab.vue` shows the "Glyphs are
    // becoming unstable" warning once `player.records.bestReality.glyphLevel`
    // exceeds 800. Threshold values come from `Glyphs.instabilityThreshold`
    // (default 1000, +Effarig glyph + ImaginaryUpgrade(7)) and
    // `Glyphs.hyperInstabilityThreshold` (instabilityThreshold + 3000).
    var showInstability: Bool = false
    var instabilityThreshold: Int = 1000
    var hyperInstabilityThreshold: Int = 4000

    /// `GameDatabase.reality.cosmeticGlyphs.music.isUnlocked()` (= `TeresaUnlocks.shop.isUnlocked`).
    /// Gates the per-glyph "Set as Music Glyph" appearance action in the tooltip sheet.
    var musicCosmeticUnlocked: Bool = false

    static let empty = GlyphsTabState(
        equippedGlyphs: [], equippedSortedGlyphs: [], activeSlotCount: 3, inventory: [],
        totalSlots: 120, protectedRows: 2, currentEffects: [],
        sacrificeUnlocked: false, sacrificeTotals: [], respec: false,
        setName: "",
        canPeek: false, peekGlyphs: [], peekLevel: 0,
        reminderText: "", reminderIsGood: false, reminderSuggestions: [],
        levelFactors: .empty,
        autoSortMode: 0, autoCollapse: false,
        autoAutoCleanUnlocked: false, autoAutoClean: false, applyFilterToPurge: false,
        hasGlyphFilter: false, hasGlyphWeights: false,
        isRefining: false, hasNegativeEffectScore: false,
        effarigRunning: false, effarigStageName: "Infinity", effarigGlyphLevelCap: 100,
        canUndoGlyph: false
    )
}

// MARK: - Perks

struct PerkInfo: Identifiable, Equatable {
    let id: Int
    let label: String
    let description: String
    let family: String          // REALITY, ANTIMATTER, INFINITY, ETERNITY, DILATION, AUTOMATION, ACHIEVEMENT
    let isBought: Bool
    let canBeBought: Bool       // connected to a bought perk (or START)
    let automatorPoints: Int    // 0 if none; >0 → diamond shape
    let x: CGFloat              // Android layout position
    let y: CGFloat
    let connectedTo: [Int]      // IDs of connected perks
}

struct PerksState: Equatable {
    var perks: [PerkInfo]
    var perkPoints: Int

    static let empty = PerksState(perks: [], perkPoints: 0)
}

// MARK: - Automator

struct AutomatorPointSource: Identifiable, Equatable {
    var id: String { name }
    let name: String            // e.g. "SEP1", "Reality Count", "Celestial Alignment"
    let description: String     // short description of what this source does
    let points: Int             // AP this source contributes
    let isBought: Bool          // whether this source is active/purchased
    let category: AutomatorPointCategory
}

enum AutomatorPointCategory: String, Equatable {
    case perk
    case upgrade
    case other
}

struct AutomatorPointsState: Equatable {
    var totalPoints: Int
    var pointsRequired: Int         // 100
    var pointsFromPerks: Int
    var pointsFromUpgrades: Int
    var pointsFromOther: Int
    var perkSources: [AutomatorPointSource]
    var upgradeSources: [AutomatorPointSource]
    var otherSources: [AutomatorPointSource]
    var automatorSpeed: String      // e.g. "0.50" commands per second
    var isUnlocked: Bool

    static let empty = AutomatorPointsState(
        totalPoints: 0, pointsRequired: 100,
        pointsFromPerks: 0, pointsFromUpgrades: 0, pointsFromOther: 0,
        perkSources: [], upgradeSources: [], otherSources: [],
        automatorSpeed: "0", isUnlocked: false
    )
}

// MARK: - Automator Editor

struct AutomatorScriptInfo: Identifiable, Equatable {
    let id: Int
    let name: String
    let contentLength: Int
}

struct AutomatorErrorInfo: Identifiable, Equatable {
    let id: Int                 // unique index (errors can share startLine)
    let startLine: Int
    let info: String
    let tip: String
}

struct AutomatorEditorState: Equatable {
    // Execution
    var isOn: Bool              // commands on the stack
    var isRunning: Bool         // mode == RUN
    var isPaused: Bool          // isOn && mode == PAUSE
    var currentLine: Int        // -1 when not running
    var hasJustCompleted: Bool
    // Scripts
    var scripts: [AutomatorScriptInfo]
    var editingScriptID: Int
    var runningScriptID: Int
    // Toggles
    var repeatOn: Bool
    var forceRestartOn: Bool
    var followExecution: Bool
    // Errors
    var errors: [AutomatorErrorInfo]
    // Metadata
    var currentScriptChars: Int
    var totalChars: Int
    var maxScriptChars: Int     // 10000
    var maxTotalChars: Int      // 60000
    var maxScriptCount: Int     // 20
    var intervalText: String    // e.g. "2.00 commands per second"
    var statusText: String      // e.g. "Running: 'My Script'"
    /// Compact interval text for iPhone status line, e.g. "2.00 com/s".
    var intervalTextCompact: String

    static let empty = AutomatorEditorState(
        isOn: false, isRunning: false, isPaused: false,
        currentLine: -1, hasJustCompleted: false,
        scripts: [], editingScriptID: 0, runningScriptID: 0,
        repeatOn: false, forceRestartOn: false, followExecution: false,
        errors: [],
        currentScriptChars: 0, totalChars: 0,
        maxScriptChars: 10000, maxTotalChars: 60000, maxScriptCount: 20,
        intervalText: "", statusText: "",
        intervalTextCompact: ""
    )
}

struct AutomatorImportPreview {
    let isFullData: Bool       // has constants/presets (full format) vs simple script
    let name: String
    let lineCount: Int
    let hasErrors: Bool
    let constants: [String]    // constant names referenced
    let presets: [String]      // preset names/slots referenced
}

// MARK: - Black Hole

struct BlackHoleUpgradeInfo: Identifiable, Equatable {
    let id: String         // e.g. "1-interval", "2-power"
    let description: String
    let effectTitle: String
    let effectText: String
    let cost: String
    let isAffordable: Bool
    let isCapped: Bool     // value == 0 (cost scaling hit cap)
    let upgradeId: Int     // underlying BlackHolePower upgrade id (1..6)
    let autobuyerUnlocked: Bool  // Ra.unlocks.blackHolePowerAutobuyers (Enslaved pet lv 1)
    let autobuyerActive: Bool
}

struct BlackHoleInfo: Identifiable, Equatable {
    let id: Int            // 1 or 2
    let isUnlocked: Bool
    let isPermanent: Bool
    let stateText: String  // "Active (2m 30s remaining)" etc.
    let power: String      // "x180.00"
    let duration: String   // "10s"
    let interval: String   // "1h 00m"
    let uptime: String     // "12.5%"
    let upgrades: [BlackHoleUpgradeInfo]
}

struct BlackHoleState: Equatable {
    var isUnlocked: Bool
    var isPaused: Bool
    var stateChangeLabel: String  // "Pause" / "Unpause" / "Invert" / "Uninvert"
    var blackHoles: [BlackHoleInfo]
    var detailedBH2: String
    var hasBH2: Bool
    var isPermanent: Bool  // both BHs permanent

    // Animation state
    var bh1Power: Double       // e.g. 180
    var bh1Duration: Double    // seconds
    var bh1CycleLength: Double // seconds (interval + duration)
    var bh1Phase: Double       // current phase in seconds
    var bh1IsActive: Bool
    var bh2IsActive: Bool
    var areNegative: Bool

    /// Black Hole inversion slider state (V-flipped + BHs permanent).
    /// Shared with `EnslavedState` so the slider can live on both the BH
    /// tab and the Nameless Ones tab without an extra JS eval.
    var inversionUnlocked: Bool = false
    var inversionActive: Bool = false
    var negativeSlider: Double = 0         // -log10(player.blackHoleNegative)
    var negativeBHDivisor: String = "1.00"
    var sliderDisabled: Bool = false
    var sliderLockText: String = ""

    /// Auto-pause cycle button (web `BlackHoleTab.vue` `pauseModeString`).
    /// Hidden when BH1 is permanent (no activation cycle remains to pause before).
    var autoPauseVisible: Bool = false
    var autoPauseLabel: String = "Do not pause"       // iPad long form
    var autoPauseShortLabel: String = "Off"           // iPhone short form

    static let empty = BlackHoleState(
        isUnlocked: false, isPaused: false, stateChangeLabel: "Pause",
        blackHoles: [], detailedBH2: "", hasBH2: false, isPermanent: false,
        bh1Power: 180, bh1Duration: 10, bh1CycleLength: 3610, bh1Phase: 0,
        bh1IsActive: false, bh2IsActive: false, areNegative: false
    )
}

// MARK: - Reality Upgrades

struct RealityUpgradeInfo: Identifiable, Equatable {
    let id: Int
    let name: String
    let description: String
    let cost: String
    let effectText: String
    let isBought: Bool
    let isAffordable: Bool
    let isAvailable: Bool        // requirement met
    let requirementText: String  // shown when requirement not met
    let isRebuyable: Bool
    let boughtAmount: Int        // for rebuyables (1-5)
    let canLock: Bool            // can toggle mechanic lock
    let hasLock: Bool            // currently locked
    let isPossible: Bool         // requirement still achievable this Reality
    /// Per-rebuyable autobuyer state. `autobuyerAvailable` is true once
    /// Ra.unlocks.instantECAndRealityUpgradeAutobuyers (V Ra pet lv 1) is
    /// applied — gates the Auto toggle visibility on the card.
    let isAutobuyerOn: Bool
    let autobuyerAvailable: Bool
}

// MARK: - Imaginary Upgrades

struct ImaginaryUpgradeInfo: Identifiable, Equatable {
    let id: Int
    let name: String
    let description: String
    let cost: String
    let effectText: String
    let isBought: Bool
    let isAffordable: Bool
    let isAvailable: Bool
    let requirementText: String
    let isRebuyable: Bool
    let boughtAmount: Int
    let canLock: Bool
    let hasLock: Bool
    let isPossible: Bool
    let etaText: String          // time-to-afford estimate
    let isPelleDisabled: Bool
    let isAutobuyerOn: Bool      // rebuyable-only
    let autobuyerAvailable: Bool // true once ImaginaryUpgrade(20) is bought
}

struct ImaginaryUpgradesState: Equatable {
    var iMAmount: String
    var iMCapText: String        // formatted "X / Y" from formatMachines
    var baseRMCap: String
    var capRM: String
    var scaleTimeSeconds: Int
    var upgrades: [ImaginaryUpgradeInfo]

    static let empty = ImaginaryUpgradesState(
        iMAmount: "0", iMCapText: "0", baseRMCap: "0", capRM: "0",
        scaleTimeSeconds: 0, upgrades: []
    )
}

// MARK: - Glyph Alchemy

struct AlchemyResourceInfo: Identifiable, Equatable {
    let id: Int
    let name: String
    let symbol: String
    let tier: Int
    let uiOrder: Double
    /// Position in 0...100 percent along the circle canvas (from web layout).
    let x: Double
    let y: Double
    let amount: String            // formatted display
    let cap: String
    let amountNum: Double
    let capNum: Double
    let capped: Bool
    let flow: Double
    let flowText: String
    let isUnlocked: Bool
    let isBaseResource: Bool
    let lockText: String
    let reactionActive: Bool
    let reactionText: String
    let reactionProduction: Double
    let effectText: String
    let description: String
}

struct AlchemyReactionArrow: Equatable, Identifiable {
    let reagentId: Int
    let productId: Int
    let reagentX: Double
    let reagentY: Double
    let productX: Double
    let productY: Double
    let isUnlocked: Bool
    let isCapped: Bool
    let isActive: Bool
    let isLessThanRequired: Bool
    var id: String { "\(reagentId)->\(productId)" }
}

struct GlyphAlchemyState: Equatable {
    var isUnlocked: Bool
    var isDoomed: Bool
    var realityCreationVisible: Bool
    var createdRealityGlyph: Bool
    var allReactionsDisabled: Bool
    var alchemyCap: Double
    var capFactor: Double
    var resources: [AlchemyResourceInfo]
    var arrows: [AlchemyReactionArrow]

    static let empty = GlyphAlchemyState(
        isUnlocked: false, isDoomed: false, realityCreationVisible: false,
        createdRealityGlyph: false, allReactionsDisabled: false,
        alchemyCap: 0, capFactor: 1, resources: [], arrows: []
    )
}

// MARK: - Time Dilation

struct DilationUpgradeInfo: Identifiable, Equatable {
    let id: Int
    let description: String
    let cost: String
    let effectText: String
    let isBought: Bool
    let isAffordable: Bool
    let isRebuyable: Bool
    let boughtAmount: Int
    let isCapped: Bool
    let isAutoUnlocked: Bool    // Perk.autobuyerDilation unlocked
    let isAutoActive: Bool      // Autobuyer.dilationUpgrade(id).isActive
    /// Web `pelleOnly` — upgrade only renders/applies when `Pelle.isDoomed`
    /// AND `PelleRifts.paradox.milestones[0].canBeApplied`. Ids 11–15.
    var pelleOnly: Bool = false
}

struct DilationState: Equatable {
    let isUnlocked: Bool
    let isActive: Bool
    let dilatedTime: String
    let dilatedTimePerSec: String
    let tachyonParticles: String
    let tachyonGalaxies: Int
    let nextGalaxyThreshold: String
    let galaxyTimeEstimate: String
    let upgrades: [DilationUpgradeInfo]
    let tachyonGain: String
    let hasGain: Bool
    let canEternity: Bool
    let requiredForGain: String   // antimatter needed for next TP (when !hasGain)
    let eternityGoal: String      // IP needed to eternity (when hasGain && !canEternity)
    // Pelle (Doomed) gate fields. Only populated when `engine.pelleDoomed`;
    // mirror `Pelle.canDilateInPelle` + `Pelle.remnantRequirementForDilation`.
    let pelleCanDilate: Bool
    let pelleRemnantRequirement: String
    /// Mirrors `PelleRifts.paradox.milestones[0].canBeApplied` — gates the
    /// 5 `pelleOnly` rebuyables/single-purchase upgrades (ids 11–15).
    let hasPelleDilationUpgrades: Bool

    static let empty = DilationState(
        isUnlocked: false, isActive: false,
        dilatedTime: "0", dilatedTimePerSec: "0",
        tachyonParticles: "0", tachyonGalaxies: 0,
        nextGalaxyThreshold: "0", galaxyTimeEstimate: "",
        upgrades: [],
        tachyonGain: "0", hasGain: false, canEternity: false,
        requiredForGain: "", eternityGoal: "",
        pelleCanDilate: false, pelleRemnantRequirement: "",
        hasPelleDilationUpgrades: false
    )
}

// MARK: - Eternity Tab State

struct EternityTabState: Equatable {
    var upgrades: [EternityUpgradeInfo]
    var epMult: EPMultState
    var milestones: [EternityMilestoneInfo]
    var eternityCount: String
    var timeStudies: TimeStudiesState
    var dilation: DilationState

    static let empty = EternityTabState(
        upgrades: [], epMult: .empty, milestones: [], eternityCount: "0",
        timeStudies: .empty, dilation: .empty
    )
}

struct GameState: Equatable {
    var dimensions: [DimensionState]
    var dimBoostCount: Int
    var tickspeed: TickspeedState
    var dimBoost: DimBoostState
    var galaxy: GalaxyState
    var buy10Mult: String
    var buyUntil10: Bool
    var isSacrificeUnlocked: Bool
    var sacrificeMultiplier: String?
    var sacrificeNextBoost: String?
    var canSacrifice: Bool
    var sacrificeDisabledReason: String?
    /// `Achievement(118).isUnlocked && Autobuyer.sacrifice.isActive` — when
    /// true, the manual Sacrifice button is effectively replaced by the
    /// autobuyer. Web shows "Dimensional Sacrifice is Automated (Achievement 118)".
    var sacrificeIsAutomated: Bool = false
    var achievements: [AchievementState]
    var secretAchievements: SecretAchievementsState = .empty
    var achievementPower: String
    /// `formatX(RealityUpgrade(8).config.effect())` — Tachyon Particle multiplier
    /// from achievements. Only meaningful when `achMultToTP` is true.
    var achTPMultiplier: String = ""
    /// Mirrors web `NormalAchievementsTab.vue` `achMultTo*` gates — extra
    /// multiplier lines unlocked at various game stages. See the boostText
    /// computed property in the Vue component.
    var achMultToIDS: Bool = false   // Achievement 75 → Infinity Dims
    var achMultToTDS: Bool = false   // EternityUpgrade.tdMultAchs → Time Dims
    var achMultToTP: Bool = false    // RealityUpgrade(8) → Tachyon Particles line
    var achMultToBH: Bool = false    // VUnlocks.achievementBH → Black Hole Power line
    var achMultToTT: Bool = false    // Ra.unlocks.achievementTTMult → Time Theorem line
    var achievementTimer: AchievementTimerState
    var infinity: InfinityState
    var infinityDimensions: InfinityDimsInfo
    var autobuyers: AutobuyersState
    var normalChallenges: NormalChallengesState
    var infinityChallenges: InfinityChallengesState
    var eternityChallenges: EternityChallengesState
    var statistics: StatisticsState
    var challengeRecords: ChallengeRecordsState
    var pastPrestigeRuns: PastPrestigeRunsState
    var breakInfinity: BreakInfinityState
    var replicanti: ReplicantiState
    var timeDimensions: TimeDimensionsState
    var eternity: EternityTabState
    var realityUpgrades: [RealityUpgradeInfo]
    var imaginaryUpgrades: ImaginaryUpgradesState
    var glyphAlchemy: GlyphAlchemyState
    var perksState: PerksState
    var blackHoleState: BlackHoleState
    var glyphsState: GlyphsTabState
    var automatorState: AutomatorPointsState
    var automatorEditorState: AutomatorEditorState
    var celestials: CelestialsState

    static let empty = GameState(
        dimensions: (1...8).map { tier in
            DimensionState(
                tier: tier, isVisible: tier == 1,
                isAvailableForPurchase: tier == 1,
                amount: "0", multiplier: "x1.00",
                boughtBefore10: 0, bought: 0, howManyCanBuy: 0,
                singleCost: "10", until10Cost: "100",
                isAffordable: true, isAffordableUntil10: false,
                rateOfChange: nil
            )
        },
        dimBoostCount: 0,
        tickspeed: TickspeedState(isUnlocked: false, cost: "0", multiplier: "x1", perSecond: "0", isAffordable: false, purchasedCount: 0, freeCount: 0),
        dimBoost: DimBoostState(purchasedBoosts: 0, requirementTier: 4, requirementAmount: 20, isSatisfied: false, canBeBought: false, unlockedByBoost: nil, lockText: nil),
        galaxy: GalaxyState(count: 0, typeName: "Antimatter Galaxies", countDisplay: "0", requirementTier: 8, requirementAmount: 80, isSatisfied: false, canBeBought: false, lockText: nil),
        buy10Mult: "x2.00", buyUntil10: true,
        isSacrificeUnlocked: false, sacrificeMultiplier: nil, sacrificeNextBoost: nil,
        canSacrifice: false, sacrificeDisabledReason: nil,
        achievements: [], achievementPower: "x1.00",
        achievementTimer: AchievementTimerState(),
        infinity: .empty, infinityDimensions: .empty,
        autobuyers: .empty, normalChallenges: .empty, infinityChallenges: .empty,
        eternityChallenges: .empty, statistics: .empty,
        challengeRecords: .empty, pastPrestigeRuns: .empty,
        breakInfinity: .empty, replicanti: .empty,
        timeDimensions: .empty, eternity: .empty,
        realityUpgrades: [],
        imaginaryUpgrades: .empty,
        glyphAlchemy: .empty,
        perksState: .empty,
        blackHoleState: .empty,
        glyphsState: .empty,
        automatorState: .empty,
        automatorEditorState: .empty,
        celestials: .empty
    )

}

// MARK: - Away Progress (Offline)

struct AwayProgressEntry: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let before: String
    let after: String
}

struct AwayProgressData: Equatable {
    let elapsedTimeDisplay: String
    let entries: [AwayProgressEntry]
}
