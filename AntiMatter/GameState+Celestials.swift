//
//  GameState+Celestials.swift
//  AntiMatter
//
//  State structs for the Celestials subtree (Navigation map, Teresa, and
//  the shared quote modal system). Populated by GameEngine+Celestials
//  via bulk JSON polls when .celestials poll category is active.
//

import Foundation

// MARK: - Teresa

struct TeresaUnlockInfo: Identifiable, Equatable {
    let id: Int
    let key: String            // "run", "epGen", "effarig", "shop", "undo", "startEU"
    let price: Double          // poured-RM price threshold
    let description: String
    let isUnlocked: Bool
    let canBeUnlocked: Bool    // pouredAmount >= price && !isUnlocked
    let pelleDisabled: Bool
}

struct PerkShopUpgradeInfo: Identifiable, Equatable {
    let id: Int                // 0..5
    let key: String            // "glyphLevel", "rmMult", "bulkDilation", "autoSpeed", "musicGlyph", "fillMusicGlyph"
    let description: String
    let cost: String           // already-formatted ("1" "1,024" etc.)
    let effectText: String     // e.g. "x1.05" current effect
    let bought: Int
    let capText: String?       // nil if uncapped
    let isCapped: Bool
    let isAffordable: Bool
}

/// Lightweight glyph record for Teresa's best-AM glyph set display.
/// Distinct from `GlyphInfo` which carries inventory-specific fields (id, idx, sacrificeGain).
struct TeresaGlyphRecord: Identifiable, Equatable {
    let id: Int              // index in array (for ForEach)
    let type: String         // "power", "infinity", "time", "dilation", "replication", "reality", "effarig", "cursed", "companion"
    let symbol: String       // Unicode symbol (Ω, ∞, Δ, etc.)
    let level: Int
    let effectCount: Int
    let typeColor: String    // hex color from GlyphAppearanceHandler.getBorderColor
    let rarityColor: String  // hex color from getRarity().darkColor
    let rarityPercent: String // formatted rarity (e.g. "73.2%")
    let rarityPercentNum: Double // numeric rarity 0..100 (for GlyphRichCard)
    let rarityName: String   // e.g. "Common", "Diamond" — for GlyphRichCard description line
    let effects: [String]    // pre-formatted effect descriptions (shortDesc with values)
}

extension TeresaGlyphRecord {
    /// Adapter to render via `GlyphComponent` / shared `GlyphRichCard`,
    /// both of which expect `GlyphInfo`. Lacks fields irrelevant to the
    /// "set used" preview (sacrifice/refine/score/chaos all empty).
    var asGlyphInfo: GlyphInfo {
        GlyphInfo(
            id: id, type: type, symbol: symbol, level: level,
            rarityPercent: rarityPercentNum, rarityName: rarityName,
            effects: effects, shortEffects: [],
            effectBoostColors: [], effectAdditionColors: [],
            effectCount: effectCount, typeColor: typeColor, rarityColor: rarityColor,
            idx: id, sacrificeGain: "",
            refineReward: "", uncappedRefineReward: "", filterScore: "", chaosDescription: ""
        )
    }
}

struct TeresaState: Equatable {
    var pouredAmount: String = "0"
    var pouredAmountRaw: Double = 0      // for milestone tick positioning
    var pouredAmountCap: String = "1.00e24"
    var pouredAmountCapRaw: Double = 1e24
    var fillFraction: Double = 0         // 0..1 log-scale
    var possibleFillFraction: Double = 0 // 0..1 log-scale including unpour'd RM
    var rmMultiplier: String = "x1.00"
    var realityMachines: String = "0"
    var perkPoints: Int = 0
    var hasRun: Bool = false            // TeresaUnlocks.run.isUnlocked
    var hasEPGen: Bool = false
    var hasShop: Bool = false
    var raisedPerkShop: Bool = false
    var isRunning: Bool = false
    var runCompleted: Bool = false
    var bestRunAM: String = "0"
    var bestAMSet: [TeresaGlyphRecord] = []
    var lastRepeatedMachines: String = ""
    /// Pre-quantified label ("N Reality Machines" / "N Imaginary Machines") matching
    /// Vue `TeresaTab.vue` `lastMachinesString`. Prefer this over `lastRepeatedMachines`.
    var lastRepeatedMachinesLabel: String = ""
    var runReward: String = "x1.00"
    /// Run effects description from `GameDatabase.celestials.descriptions[0].effects()`,
    /// e.g. "Glyph Time Theorem generation is disabled. You gain less Infinity
    /// Points and Eternity Points (x^0.55)."
    var runDescription: String = ""
    var unlocks: [TeresaUnlockInfo] = []
    var perkShop: [PerkShopUpgradeInfo] = []
}

// MARK: - Quote modal

struct QuoteLineInfo: Equatable {
    let text: String
    /// Primary celestial color used as the modal background for this line.
    let celestialKey: String   // "teresa" / "effarig" / ...
    let showCelestialName: Bool
}

struct QuoteState: Identifiable, Equatable {
    /// Unique per celestial+id so .sheet(item:) re-presents when a new quote
    /// arrives while one is already showing.
    var id: String { "\(celestialKey)/\(quoteId)" }
    let celestialKey: String
    let celestialDisplayName: String
    let celestialSymbol: String
    let quoteId: Int
    let lines: [QuoteLineInfo]
    let queueSize: Int
}

struct QuoteHistoryEntry: Identifiable, Equatable {
    var id: Int { quoteId }
    let quoteId: Int
    let firstLine: String
    let totalLines: Int
}

// MARK: - Celestial Navigation (dynamic poll state)

/// Per-node runtime state (static geometry lives in CelestialNavigationData.swift).
struct CelestialNavNodeState: Identifiable, Equatable {
    let id: String              // navigation key ("teresa-reality-unlock", etc.)
    let completeFraction: Double  // 0..1
    let isVisible: Bool
    let legendText: String      // "" if hidden
}

struct CelestialNavigationState: Equatable {
    var nodes: [CelestialNavNodeState] = []
}

// MARK: - Effarig

enum EffarigStage: Int, Equatable {
    case infinity = 1
    case eternity = 2
    case reality = 3
    case completed = 4
}

struct EffarigShopUpgrade: Identifiable, Equatable {
    /// Web EffarigUnlock ids: 0=adjuster, 1=glyphFilter, 2=setSaves, 3=run.
    let id: Int
    let key: String
    let description: String
    let cost: String
    let isUnlocked: Bool
    let canAfford: Bool
}

struct EffarigRunUnlock: Identifiable, Equatable {
    /// Web EffarigUnlock ids: 4=infinity, 5=eternity, 6=reality.
    let id: Int
    let key: String
    let label: String
    let description: String       // legacy single-string (kept for back-compat)
    /// Per-line description split on the source `\n` separators so iOS
    /// can render each line with the Ξ bullet, matching web
    /// `EffarigRunUnlockReward.vue` `descriptionLines`.
    let descriptionLines: [String]
    let isUnlocked: Bool
}

struct EffarigState: Equatable {
    var relicShards: String = "0"
    var shardRarityBoostPct: String = "0%"
    /// Ra "shard sacrifice boost" power. Empty string when effect == 1.
    var shardPower: String = ""
    var relicShardRarityAlwaysMax: Bool = false
    var shardsGained: String = "0"
    var currentShardsRate: String = "0"
    var amplification: Int = 0
    var amplifiedShards: String = "0"
    var amplifiedShardsRate: String = "0"
    var runUnlocked: Bool = false
    var isRunning: Bool = false
    var currentStage: EffarigStage = .infinity
    var currentStageName: String = "Infinity"
    var glyphLevelCap: Int = 100
    var vIsFlipped: Bool = false
    var runDescription: String = ""
    var shopUpgrades: [EffarigShopUpgrade] = []   // ids 0..3
    var runUnlocks: [EffarigRunUnlock] = []       // ids 4..6
}

// MARK: - Effarig glyph sub-features (lazy-loaded; live on GameEngine, NOT in gameState)

struct EffarigGlyphWeightsState: Equatable {
    var ep: Int = 25
    var repl: Int = 25
    var dt: Int = 25
    var eternities: Int = 25
    var autoAdjust: Bool = false
    var autoAdjustUnlocked: Bool = false
}

struct GlyphFilterTypeConfig: Identifiable, Equatable {
    var id: String { type }
    let type: String                  // "power"/"infinity"/"time"/"dilation"/"replication"/"effarig"
    let typeDisplayName: String       // "Power" / "Effarig"…
    let typeSymbol: String            // Unicode glyph symbol (Ω/∞/Ξ/Δ/Ψ)
    let typeColor: String             // hex color from GlyphTypes[type].color
    var rarity: Int                   // 0..100
    var score: Int
    var effectCount: Int              // 0..7
    var specifiedMask: Int
    var effectScores: [Int]           // one per effect bit in this type
    let effectIds: [String]           // matched positionally with effectScores/mask bits
    let effectNames: [String]         // display labels (genericDesc)
    /// Absolute bitmask index per effect (from `GameDatabase.reality.glyphEffects`),
    /// in the same order as `effectNames`/`effectIds`. Used to toggle `specifiedMask`
    /// via `1 << bitmaskIndex` — power/effarig/etc. effects do NOT start at bit 0, so
    /// the enumeration index must not be used as the bit position.
    let effectBitmaskIndices: [Int]
}

/// Parsed preview of a Glyph Filter import string, surfaced by the import sheet
/// so the user can see what will change before committing. Mirrors web
/// `ImportFilterModal.parsedSettings` + its `changedValue` diff helpers.
struct GlyphFilterImportPreview: Equatable {
    var valid: Bool
    var selectName: String          // "(No change)" or "Old ➜ New"
    var simpleDiff: String
    var trashLabel: String
    var currentTrashLabel: String
    var newSelect: Int
    var newSimple: Int
    var newTrash: Int
    var currentSelect: Int
    var currentSimple: Int
    var currentTrash: Int
    /// Raw types JSON kept for the preview UI; not enumerated here for brevity.
    var typeSummary: String

    static let invalid = GlyphFilterImportPreview(
        valid: false, selectName: "", simpleDiff: "", trashLabel: "", currentTrashLabel: "",
        newSelect: 0, newSimple: 0, newTrash: 0,
        currentSelect: 0, currentSimple: 0, currentTrash: 0,
        typeSummary: ""
    )
}

struct GlyphFilterState: Equatable {
    /// AUTO_GLYPH_SCORE: 0=LOWEST_SACRIFICE, 1=EFFECT_COUNT, 2=RARITY_THRESHOLD,
    /// 3=SPECIFIED_EFFECT, 4=EFFECT_SCORE, 5=LOWEST_ALCHEMY, 6=ALCHEMY_VALUE.
    var selectMode: Int = 0
    /// AUTO_GLYPH_REJECT: 0=SACRIFICE, 1=REFINE, 2=REFINE_TO_CAP.
    var trashMode: Int = 0
    /// Used by EFFECT_COUNT mode only.
    var simpleThreshold: Int = 0
    /// Ra.unlocks.unlockGlyphAlchemy.canBeApplied — gates the last two modes
    /// (LOWEST_ALCHEMY + ALCHEMY_VALUE). When false, those buttons are hidden
    /// to match web.
    var alchemyUnlocked: Bool = false
    /// Web's `player.options.autoRealityForFilter`. When true, the Reality
    /// Autobuyer instantly Realitys if the best upcoming Glyph wouldn't be
    /// kept under the current filter. Effective only when the Effarig Glyph
    /// Filter unlock is owned and the Reality Autobuyer is unlocked.
    var autoRealityForFilter: Bool = false
    var types: [GlyphFilterTypeConfig] = []
}

struct GlyphPresetSlot: Identifiable, Equatable {
    let id: Int                       // 0..6
    var name: String
    var glyphs: [TeresaGlyphRecord]   // reuse existing adapter for GlyphComponent
    var isEmpty: Bool
}

struct EffarigPresetsState: Equatable {
    var slots: [GlyphPresetSlot] = []
    var hasEquipped: Bool = false
    /// Player preset-loading "leniency" settings from `player.options`.
    var ignoreEffects: Bool = true
    var ignoreRarity: Bool = true
    var ignoreLevel: Bool = true
}

// MARK: - Enslaved (The Nameless Ones)

/// ENSLAVED_UNLOCKS entry — two entries (FREE_TICKSPEED_SOFTCAP id=0, RUN id=1).
/// Price is surfaced as preformatted years text (`timeDisplayShort`).
struct EnslavedUnlockInfo: Equatable, Identifiable {
    let id: Int
    var description: String
    var priceYears: String         // already formatted via timeDisplayShort on the JS side
    var hasBought: Bool
    var canBuy: Bool
    /// Preformatted "time to obtain" string from `timeDisplayShort((price - stored) / rate)`.
    /// Empty when bought, not charging, or rate is 0. Mirrors web EnslavedTab.vue `timeUntilBuy(price)`.
    var timeToObtainText: String = ""
}

/// One entry in `EnslavedProgress.all` (8 total at time of writing). Each
/// "crack" in the Nameless Ones' Reality is discovered by meeting a specific
/// condition (e.g. "Click the secret Time Study", "Feel Eternity"). The
/// hints modal surfaces them with progressive reveal — you see the hint
/// after spending stored time, then the condition text once you actually
/// solve it.
struct EnslavedProgressEntry: Equatable, Identifiable {
    let id: Int                 // 0..7
    let hint: String            // hintInfo text
    let condition: String       // completedInfo text
    var hasHint: Bool           // unlocked (shown but maybe not solved)
    var hasProgress: Bool       // solved
}

/// Lazy snapshot of Enslaved hints state. Lives on `GameEngine` (NOT in
/// `gameState`) since the modal is only open occasionally — no need to
/// pay the serialize/parse cost every tick.
struct EnslavedHintsState: Equatable {
    /// Gate for the "Examine the Reality more closely..." button on the
    /// Enslaved tab. True when: has RUN unlock, not completed, and the
    /// `hintsUnlocked` progress bit is set.
    var canShowHintsButton: Bool = false
    var realityHintsUnlocked: Int = 0
    var realityHintsTotal: Int = 8
    var glyphHintsGiven: Int = 0
    var glyphHintsTotal: Int = 3
    var realityEntries: [EnslavedProgressEntry] = []
    /// Prefix of the glyph-hints config array matching `glyphHintsGiven`.
    var glyphHints: [String] = []
    var allRealityHintsShown: Bool = false
    var allGlyphHintsShown: Bool = false
    /// `timeDisplayShort(Enslaved.nextHintCost)` — preformatted on JS side.
    var nextHintCostText: String = ""
    var canAffordHint: Bool = false
    /// Lambert-W-based estimate of time-to-afford next hint at current
    /// charging rate. Empty when already affordable.
    var timeToNextHintText: String = ""
    var hintCostIncreases: Int = 0
}

struct EnslavedState: Equatable {
    var isUnlocked: Bool = false
    var isRunning: Bool = false
    var isCompleted: Bool = false
    var isDoomed: Bool = false

    /// Speedrun-path flags (web `player.celestials.enslaved.*`). Exposed
    /// on the state struct so the Enslaved tab can render them, but the
    /// cross-tab reads (secret study in Time Studies, Feel Eternity button
    /// in Break Infinity) go through the always-polled mirrors on
    /// `GameEngine` — those update even when the user isn't on the
    /// Celestials tab.
    var hasSecretStudy: Bool = false
    var feltEternity: Bool = false

    // Game-time storage (Black Hole charging)
    var isStoringBlackHole: Bool = false
    var canModifyGameTimeStorage: Bool = false
    var canDischarge: Bool = false
    var hasNoCharge: Bool = true
    var storedBlackHoleText: String = "0s"            // timeDisplayShort(player.celestials.enslaved.stored)
    var storedBlackHoleMs: Double = 0                  // raw — for "time to obtain" math and debug display
    var currentBHStoreAmountPerMs: Double = 0          // Enslaved.currentBlackHoleStoreAmountPerMs
    var nerfedInRealityText: String = ""               // timeDisplayShort(storedTimeInsideEnslaved(stored)); blank when !isRunning

    // Real-time storage
    var isStoringReal: Bool = false
    var autoStoreReal: Bool = false
    var offlineProgressEnabled: Bool = false
    var canChangeStoreRealTime: Bool = false
    var hasReachedCurrentCap: Bool = false
    var storedRealText: String = "0s"
    var storedRealEfficiencyPct: String = "70%"
    var storedRealCapText: String = "8h"

    // Black Hole inversion (sliders — only visible post-V-flipped & BHs permanent)
    var isNegativeBHUnlocked: Bool = false
    var isBHInverted: Bool = false
    var negativeSlider: Double = 0                     // -log10(player.blackHoleNegative)
    var negativeBHDivisor: String = "1.00"             // format(Math.pow(10, negativeSlider), 2, 2)
    var sliderDisabled: Bool = false
    var sliderLockText: String = ""

    // Run + unlocks
    var hasRunUnlock: Bool = false                     // Enslaved.has(ENSLAVED_UNLOCKS.RUN)
    var runDescription: [String] = []                  // split lines from GameDatabase.celestials.descriptions[2]
    var unlocks: [EnslavedUnlockInfo] = []             // ENSLAVED_UNLOCKS (2 entries)

    // Pulse Black Hole (Ra.unlocks.autoPulseTime — Enslaved pet lv 10).
    // When unlocked, a toggle appears at the top of the Enslaved tab that
    // auto-discharges 1% of stored game time every 5 ticks. Powered by
    // `player.celestials.enslaved.isAutoReleasing`.
    var hasAutoPulse: Bool = false
    var canAutoPulse: Bool = false
    var isAutoPulsing: Bool = false
    var autoPulseSpeedText: String = ""                // formatX(autoReleaseSpeed) when active

    // Reality Amplify — `Enslaved.boostReality` toggle. Surfaces the button
    // in `GlyphsTab` near "Start this Reality over". Mirrors web
    // `RealityAmplifyButton.vue`. Polled both from `pollEnslaved` and from
    // the Glyphs poll so it stays live regardless of which tab the player
    // is viewing the button on.
    var amplifyCanAmplify: Bool = false
    var amplifyIsActive: Bool = false
    var amplifyRatio: Int = 0
    var amplifyIsInCelestialReality: Bool = false
}

// MARK: - V

struct VUnlockRequirement: Identifiable, Equatable {
    let id: Int
    var name: String = ""
    var current: String = ""
    var goal: String = ""
    var progress: Double = 0  // 0..1
    var isMet: Bool = false
}

struct VAchievementInfo: Identifiable, Equatable {
    let id: Int
    var name: String = ""
    var description: String = ""
    var completions: Int = 0
    var maxCompletions: Int = 0
    var isHard: Bool = false
    var rewardPerCompletion: Int = 1  // 1 normal, 2 hard
    var record: String = ""
    var canReduce: Bool = false
    var reductionCost: String = ""
    var reductionMode: String = ""    // "reduced" or "divided"
    var reductionValue: String = ""
    /// True when `player.celestials.v.goalReductionSteps[id] > 0`. Drives the
    /// "Goal has been reduced/divided by X" line below the description.
    var isReduced: Bool = false
    var isFullyCompleted: Bool = false
    var hexColor: String = ""         // css color for dynamic border
    /// Glyph set used to achieve this achievement's best run record.
    /// Mirrors `player.celestials.v.runGlyphs[id]`. Empty until the
    /// achievement has at least one completion. Surfaced via long-press.
    var glyphSet: [TeresaGlyphRecord] = []
}

struct VMilestoneInfo: Identifiable, Equatable {
    let id: Int
    var description: String = ""
    var reward: String = ""
    /// "Currently: X" line for milestones whose effect has a numeric readout
    /// (e.g. shardReduction's active goal discount). Empty when no effect.
    var formattedEffect: String = ""
    var stRequired: Int = 0
    var isReached: Bool = false
}

struct VState: Equatable {
    var isUnlocked: Bool = false
    var isRunning: Bool = false
    var canUnlockCelestial: Bool = false
    var unlockRequirements: [VUnlockRequirement] = []
    var spaceTheorems: Int = 0
    var ppAvailable: String = "0"
    var showReduction: Bool = false
    var achievements: [VAchievementInfo] = []
    var milestones: [VMilestoneInfo] = []
    var isFlipped: Bool = false
    var wantsFlipped: Bool = false
    var runDescription: String = ""
    var hasAlchemy: Bool = false
    /// Pre-unlock button copy pulled from `VUnlocks.vAchievementUnlock`
    /// config (web VTab.vue:179-180). Avoids hardcoding English on iOS.
    var unlockButtonDescription: String = ""
    var unlockButtonReward: String = ""
}

// MARK: - Ra

/// One of Ra's four pet upgrades (Memory Recollection / Memory Fragmentation).
/// Cost is in memories; `currentMult` is the existing multiplier (1.3^n or 1.5^n).
struct RaPetUpgradeInfo: Equatable {
    var cost: String = "0"
    var costRaw: Double = 0
    var canAfford: Bool = false
    var isCapped: Bool = false
    var currentMult: String = "1.0x"
    var nextMult: String = "1.3x"
    var effectDescription: String = ""
    /// Pre-formatted estimate "in X minutes" — blank when unaffordable or 0 production.
    var timeToAfford: String = ""
}

/// One of Ra's 20 per-pet unlock milestones. `level` gates display.
struct RaUnlockInfo: Identifiable, Equatable {
    let id: Int
    let pet: String           // "teresa" / "effarig" / "enslaved" / "v"
    let level: Int
    let reward: String
    /// "sf:atom", "sf:infinity", "unicode:Ϟ", "unicode:Ϙ", etc.
    /// See CelestialPalette-style mapping in _nativeRaState.
    let iconToken: String
    let isUnlocked: Bool
    let disabledByPelle: Bool
}

struct RaPetInfo: Identifiable, Equatable {
    var id: String { key }
    let key: String                   // "teresa", "effarig", "enslaved", "v"
    let displayName: String
    let colorHex: String              // pet config color
    let chunkGainResource: String     // "Eternity Points", etc.
    let memoryGainResource: String    // "current RM", etc.
    var isUnlocked: Bool = false
    var unlockRequirementText: String = ""  // "Get Teresa to level 8"
    var level: Int = 0
    var isCapped: Bool = false
    var memories: String = "0"
    var memoriesRaw: Double = 0
    var memoryChunks: String = "0"
    var chunksPerSecond: String = "0"
    var memoriesPerSecond: String = "0"
    var requiredMemories: String = "0"
    var requiredMemoriesRaw: Double = 0
    var progressToNextLevel: Double = 0  // 0..1
    var timeToNextLevel: String = ""
    var hasRemembrance: Bool = false
    var memoryUpgrade: RaPetUpgradeInfo = RaPetUpgradeInfo()
    var chunkUpgrade: RaPetUpgradeInfo = RaPetUpgradeInfo()
    var canLevelUp: Bool = false
    /// "You can charge X Infinity Upgrades.", etc. — pet-specific scaling text.
    var scalingUpgradeText: String = ""
    /// Next unlock at this level, if any (used by the level bar tooltip).
    var nextUnlockText: String = ""
    var unlocks: [RaUnlockInfo] = []
    /// `pet.memoryProductionMultiplier`. > 1 when other pets / global boosts
    /// are amplifying this pet's Memory production. Drives the
    /// "Multiplying all Memory production by ×N" line (RaPet.vue:265-270).
    var memoryMultiplier: Double = 1
    /// Pre-formatted display (e.g. "1.50") when `memoryMultiplier > 1`.
    var memoryMultiplierText: String = ""
}

struct RaState: Equatable {
    var isUnlocked: Bool = false     // VUnlocks.raUnlock.isUnlocked
    var isRunning: Bool = false
    var petWithRemembrance: String = ""   // "teresa" / "effarig" / "enslaved" / "v" / ""
    /// Whether the Remembrance SECTION is rendered (web gate: `Ra.unlocks.effarigUnlock.canBeApplied`).
    /// Pet buttons inside the section are only ACTIVE when `remembranceUnlocked`.
    var showRemembrance: Bool = false
    var remembranceUnlocked: Bool = false
    var remembranceMult: Double = 5
    var remembranceNerf: Double = 0.5
    var remembranceRequiredLevel: Int = 20
    var totalPetLevel: Int = 0
    var maxTotalPetLevel: Int = 100
    var levelCap: Int = 25
    var memoriesPerChunk: String = "1.0"
    var memoryBoostResources: String = ""
    var canStartRun: Bool = false
    var runDescription: String = ""
    /// "Ra's Reality" / "Exit Ra's Reality" header state.
    var exitAvailable: Bool = false
    var pets: [RaPetInfo] = []
}

// MARK: - Lai'tela

/// One Dark Matter Dimension row (tiers 1..4).
/// Mirrors `DarkMatterDimensionRow.vue`: interval / powerDM / powerDE buy
/// buttons + ascension + per-tier production.
struct DarkMatterDimensionInfo: Identifiable, Equatable {
    var id: Int { tier }
    let tier: Int                    // 1..4
    var isUnlocked: Bool = false
    var amount: String = "0"
    var interval: String = "1000ms"  // formatted via TimeSpan.fromMilliseconds
    var intervalMs: Double = 1000    // raw for timer fill
    var timerPct: Double = 0         // 0..1 — current tick progress
    var isIntervalCapped: Bool = false
    var powerDM: String = "x1.00"
    var powerDE: String = "+0.00"
    var dePerSec: String = "0.00"
    var dePerSecPct: String = "0%"
    var productionText: String = ""  // "Producing X DM/sec" / "Producing Y<tier+1>/sec"
    var intervalCost: String = "0"
    var powerDMCost: String = "0"
    var powerDECost: String = "0"
    var canBuyInterval: Bool = false
    var canBuyPowerDM: Bool = false
    var canBuyPowerDE: Bool = false
    var ascensionCount: Int = 0
    var hasAscended: Bool = false
    var nextAscensionIntervalText: String = ""   // "Interval ➜ 100ms on Ascend"
    var intervalPurchaseCap: Int = 10
    var adjustedPurchaseCap: Int = 10
    /// Continuum "ownership" — `continuumValue` from DMD; in continuum mode,
    /// purchase counts are fractional.
    var continuumValue: Double = 0
}

struct SingularityInfo: Equatable {
    var singularities: String = "0"
    var singularitiesRaw: Double = 0
    var darkEnergy: String = "0"
    var darkEnergyPerSec: String = "0"
    var cap: String = "200"
    var capRaw: Double = 200
    var capIncreases: Int = 0
    var maxCapIncreases: Int = 50
    var canPerform: Bool = false
    var singularitiesGainedPerCondense: Int = 1
    /// Vue SingularityPane.vue:24 `singularityFormText` — full button copy
    /// including multi-singularity variant and the pre-cap "Reach X to
    /// condense ..." form.
    var formText: String = ""
    /// Vue SingularityPane.vue:33 `singularityWaitText` — status line below
    /// the condense button. "(Auto-condensing in X)" / "(Will immediately
    /// auto-condense)" / "(Enough Dark Energy in X)". Empty when can perform
    /// and auto-condense is off.
    var waitText: String = ""
    var timePerCondenseText: String = "∞"
    var timePerCondenseSec: Double = 0
    var timeUntilCapText: String = ""
    /// Manual Singularity gain rate per hour (e.g. "9.444").
    var gainPerHourText: String = "0"
    /// Auto Singularity gain rate per hour (e.g. "7.265"). Only meaningful
    /// when auto-condense is unlocked & active.
    var autoGainPerHourText: String = "0"
    /// Formatted "extra time" auto-condense waits past the raw cap (e.g. "+41:55").
    var extraTimeAfterSingularityText: String = ""
    /// "×10" / "×11" info line — DE cost multiplier per cap-step + gained-
    /// singularity multiplier per cap-step.
    var darkEnergyPerCapStep: Int = 10
    var gainPerCapStep: Int = 11
    var hasBulkUnlocked: Bool = false       // singularities >= 10 (show ± cap)
    /// Auto-condense — unlocked by SingularityMilestone.autoCondense.
    var hasAutoCondense: Bool = false
    var autoCondenseActive: Bool = false
    var autoCondenseFactor: Double = 0       // multiplier the auto-trigger waits for
    var autoCondenseFactorText: String = ""
    var nextLowerStep: Int = 0              // cap before decrease
    var willCondenseOnDecrease: Bool = false
}

/// Visualization mode for the milestone progress indicator.
enum SingularityMilestoneMode: String, Equatable {
    case singularities   // progress by raw singularity count (default)
    case condenseCount
    case manualTime
    case autoTime
    case maxed
}

struct SingularityMilestoneInfo: Identifiable, Equatable {
    let id: String                   // internal key from GameDatabase (e.g. "continuumMult")
    var name: String = ""
    var description: String = ""
    var effectText: String = ""      // formatted current effect
    var nextEffectText: String = ""  // "" when unique & maxed, else formatted next effect
    var isUnique: Bool = false
    var isMaxed: Bool = false
    var isUnlocked: Bool = false
    var completions: Int = 0
    var limit: Int = 1
    var remainingSingularities: String = "0"
    var progressPct: Double = 0      // 0..1
    var mode: SingularityMilestoneMode = .singularities
}

struct LaitelaAnnihilationInfo: Equatable {
    var unlocked: Bool = false
    var isVisible: Bool = false
    var canAnnihilate: Bool = false
    var darkMatter: String = "0"
    var darkMatterMult: String = "x1.00"
    var darkMatterMultGain: String = "+0.00"
    var darkMatterMultRatio: String = "x1.00"
    var autoUnlocked: Bool = false
    var autoMultiplier: Double = 0
    var requirementText: String = "Reach 1.00e60 Dark Matter"
}

struct LaitelaAutobuyerToggle: Equatable {
    var isUnlocked: Bool = false
    var isActive: Bool = false
    var label: String = ""
    var description: String = ""
}

struct LaitelaAutobuyerPaneInfo: Equatable {
    var isVisible: Bool = false
    var dimension: LaitelaAutobuyerToggle = LaitelaAutobuyerToggle()
    var ascension: LaitelaAutobuyerToggle = LaitelaAutobuyerToggle()
    var singularity: LaitelaAutobuyerToggle = LaitelaAutobuyerToggle()
    var annihilation: LaitelaAutobuyerToggle = LaitelaAutobuyerToggle()
}

struct LaitelaRunInfo: Equatable {
    var isRunning: Bool = false
    var difficultyTier: Int = 0                // 0..8 (8 = fully destabilized)
    var maxAllowedDimension: Int = 8
    var fastestCompletionSeconds: Double = 3600
    var fastestCompletionText: String = "1 hour"
    var realityReward: String = "x1.00"
    var bestSet: [TeresaGlyphRecord] = []
    var isFullyDestabilized: Bool = false
    var tierNotCompleted: Bool = true
    var runDescription: String = ""
    /// Per-line run effects from `descriptions[5].effects()` (split on
    /// source `\n`). Mirrors Vue `LaitelaRunButton.vue` `runEffects`.
    var runEffectsLines: [String] = []
    /// Standalone description paragraph from `descriptions[5].description()`.
    var description: String = ""
    /// "All Dark Matter multipliers are ×N higher." — shown when
    /// `realityReward > 1`. Empty otherwise.
    var multiplierLine: String = ""
}

struct LaitelaState: Equatable {
    var ready: Bool = false
    var isUnlocked: Bool = false
    var isDoomed: Bool = false
    var darkMatter: String = "0"
    var darkMatterCap: String = "0"
    /// DMD1-driven "Average DM/s" — Vue LaitelaTab.vue:67. Surfaced inline
    /// next to the current DM amount when not capped.
    var darkMatterPerSecText: String = "0"
    /// Pre-formatted countdown for "Unlock Singularities in X."
    /// (LaitelaTab.vue:115). Empty when at-cap / DE/sec is zero.
    var singularityUnlockTime: String = ""
    var maxDarkMatterEver: String = "0"
    var darkMatterCapped: Bool = false
    var continuumUnlocked: Bool = false
    var continuumActive: Bool = false
    var continuumDisabled: Bool = false        // player.auto.disableContinuum
    /// Preformatted `matterExtraPurchaseFactor - 1` as a percent (e.g. "12.5%").
    var continuumBonusPct: String = "0%"
    var singularity: SingularityInfo = SingularityInfo()
    var dimensions: [DarkMatterDimensionInfo] = []
    var annihilation: LaitelaAnnihilationInfo = LaitelaAnnihilationInfo()
    var autobuyers: LaitelaAutobuyerPaneInfo = LaitelaAutobuyerPaneInfo()
    var run: LaitelaRunInfo = LaitelaRunInfo()
    /// Next 6 unlocked-or-soon milestones (carousel).
    var nextMilestones: [SingularityMilestoneInfo] = []
    /// Full roster of all milestones (for the "Show all" sheet).
    var allMilestones: [SingularityMilestoneInfo] = []
}

// MARK: - Pelle

/// One row in the pre-Doom requirement list (`prePelleRows` in
/// `PelleTab.vue`). Achievement rows + alchemy resource caps.
struct PelleRequirementInfo: Equatable, Identifiable {
    var id: String = ""               // stable key (e.g. "row1", "alchemy-cardinality")
    var label: String = ""            // display name ("Achievement Row 1")
    var progressText: String = ""     // "8/8" or formatted resource amount
    var isMet: Bool = false
}

/// Strike state — one of 5 trigger conditions that gate rifts.
/// Mirrors `PelleStrikes.all` (infinity, powerGalaxies, eternity, ECs, dilation).
struct PelleStrikeInfo: Equatable, Identifiable {
    var id: Int = 0                   // 1..5
    var name: String = ""             // "Infinity", "Power-up Galaxies", etc.
    var hasStrike: Bool = false
    var requirementText: String = ""
    var penaltyText: String = ""
    var rewardText: String = ""
    var riftId: String = ""           // matches PelleRiftInfo.id
}

/// One milestone inside a rift (e.g. "1% — Unlock glyphs").
struct PelleRiftMilestoneInfo: Equatable, Identifiable {
    var id: String = ""               // stable key, "vacuum-1", "decay-3"
    var thresholdPct: Double = 0      // 0..100 — fill % at which it unlocks
    var requirementText: String = ""
    var effectText: String = ""
    var isUnlocked: Bool = false
    /// Web `m.config.requirement > rift.reducedTo`. When true, the milestone
    /// is currently capped out and ineligible for unlock until reducedTo
    /// recovers — render dimmed and skip the locked-flash animation.
    var isDisabled: Bool = false
}

/// Rift state — one of 5 currency-fed bars.
struct PelleRiftInfo: Equatable, Identifiable {
    var id: String = ""               // "vacuum" / "decay" / "chaos" / "recursion" / "paradox"
    var name: String = ""             // first synonym, static fallback
    /// Per-tick wordCycle of all 3 synonyms (web: `wordShift.wordCycle(rift.name, true)`),
    /// padded to constant character width. Render with `.system(design: .monospaced)`
    /// so the 250ms letter-scramble doesn't reflow the layout.
    var cycledName: String = ""
    var fillCurrencyName: String = "" // "Infinity Points", "Replicanti", etc.
    /// Cycled drain-resource label — populated for Chaos rift only (web's
    /// `PelleRiftBar.vue:59` cycles Decay's name when describing what
    /// Chaos drains).
    var cycledFillCurrencyName: String = ""
    var percentage: Double = 0        // 0..1 (display fill %)
    var realPercentage: Double = 0    // 0..1 (true fill before reduce)
    var reducedTo: Double = 0         // 0..1 — for spendable rifts
    var isActive: Bool = false
    var isMaxed: Bool = false
    var isSpendable: Bool = false     // decay/chaos/paradox can be drained
    var hexColor: String = "#ffffff"  // CSS hex from web rift config
    var milestones: [PelleRiftMilestoneInfo] = []
    /// Pre-formatted current value of the drain currency. Web `PelleRift.vue:116`
    /// `formatRift(rift.fillCurrency.value)` — Decimals via `format(v, 2)`,
    /// raw numbers (decay rift's percentage) via `formatInt(100*v) + "%"`.
    /// Empty when not retrievable; render only when non-empty AND not maxed.
    var currentFillText: String = ""
    /// Pre-formatted total ever filled (cumulative across drains). Web
    /// `PelleRift.vue:119` `formatRift(rift.totalFill)`. Same format helper
    /// as `currentFillText`.
    var totalFillText: String = ""
    /// Reward effects from draining this rift — web `rift.effects` getter,
    /// rendered by `PelleRift.vue:88-95`. Each entry is an already-formatted
    /// string (e.g. Vacuum/"Void" → "IP gain ×X", plus any unlocked
    /// additional-effect milestones). These describe what the rift gives you;
    /// they apply even when the rift isn't actively draining.
    var effects: [String] = []
}

/// One Pelle upgrade card (rebuyable or one-time).
///
/// `id` is a `String`: rebuyables use the config key (e.g.
/// `"antimatterDimensionMult"`), one-times use the numeric id stringified
/// (`"0"`..`"22"`). The buy actions take this string and route it to the
/// correct JS-side wrapper.
struct PelleUpgradeInfo: Equatable, Identifiable {
    var id: String = ""
    var name: String = ""              // friendly title for rebuyables; empty for one-times (description is the title)
    var description: String = ""
    var effectText: String = ""
    var nextEffectText: String = ""
    var costText: String = ""
    var costCurrencyName: String = "Reality Shards"
    var rebuyable: Bool = false
    var boughtAmount: Int = 0
    var maxAmount: Int = 0             // cap for rebuyables (44 for AD mult etc.)
    var isBought: Bool = false         // for one-time upgrades
    var isAffordable: Bool = false
    var isAvailable: Bool = true       // false when locked behind another upgrade
    var requirementText: String = ""   // for locked upgrades
    var timeToAffordText: String = ""  // peak-rate estimate
}

/// Galaxy Generator state — phases, generation rates, and 5 upgrade types.
struct PelleGalaxyGeneratorUpgradeInfo: Equatable, Identifiable {
    var id: String = ""               // "additive", "multiplicative", "antimatterMult", "ipMult", "epMult"
    var name: String = ""
    var bought: Int = 0
    var costText: String = ""
    var costCurrencyName: String = ""
    var effectText: String = ""
    var nextEffectText: String = ""
    var isAffordable: Bool = false
    /// Estimated time-to-afford for galaxy-cost upgrades (additive +
    /// multiplicative). Blank for AM/IP/EP-cost upgrades — those rates
    /// vary too widely to give a useful single estimate.
    var timeToAffordText: String = ""
}

struct PelleGalaxyGeneratorInfo: Equatable {
    /// Whether the Galaxy Generator panel itself should render — web
    /// `PelleTab.vue` `hasGalaxyGenerator` (recursion rift milestone 3 reached
    /// OR `GalaxyGenerator.spentGalaxies > 0`).
    var panelVisible: Bool = false
    /// Whether the user has clicked "Unlock the Galaxy Generator" inside the
    /// panel — web `Pelle.hasGalaxyGenerator` getter
    /// (= `player.celestials.pelle.galaxyGenerator.unlocked`). Drives the
    /// switch between unlock-button view and stats/upgrades view.
    var isUnlocked: Bool = false
    var spentGalaxies: Double = 0
    var generatedGalaxies: Double = 0
    var phase: Int = 0                // 0..4 (5 phases including final)
    var sacrificeActive: Bool = false
    var sacrificeProgressText: String = ""
    var galaxiesText: String = "0"
    var capText: String = "0"
    var gainPerSecText: String = "0/s"
    var isCapped: Bool = false
    /// wordCycle of the cap-rift's name list (web:
    /// `PelleGalaxyGeneratorPanel.vue:60`). Drives the sacrifice card copy.
    var capRiftCycledName: String = ""
    /// ETA until the current sacrifice phase completes — blank when not
    /// `sacrificeActive`. Bucket-formatted via `fmtPelleETA`.
    var phaseCompletionText: String = ""
    /// ETA until the next galaxy generation cap is hit — blank when
    /// already capped or generating zero.
    var timeToCapText: String = ""
    /// `format(generatedGalaxies, 2, 2)` — JS-formatted current generation
    /// count. Used in the panel's big fill-bar centre text.
    var generatedGalaxiesText: String = "0"
    /// 0..1 — width fraction of the fill bar. Web emphasised generation
    /// `(generated/cap)^0.45` when generating, `capRift.reducedTo` while
    /// capped/sacrificing.
    var barFraction: Double = 0
    var upgrades: [PelleGalaxyGeneratorUpgradeInfo] = []
}

/// Armageddon button state — gain text + visibility.
struct PelleArmageddonInfo: Equatable {
    var canArmageddon: Bool = false
    var remnantsGainText: String = "0"
    /// Current Reality Shard rate (before Armageddon).
    var realityShardsRateText: String = "0/s"
    /// Projected post-Armageddon rate — drives the "X/s ➔ Y/s" transition
    /// readout the header banner button shows.
    var realityShardsRateAfterText: String = "0/s"
    var resetSummaryText: String = "" // for confirmation modal body
}

/// Web `Pelle.cel.collapsed` — UI persistence.
struct PelleCollapsedFlags: Equatable {
    var upgrades: Bool = false
    var galaxies: Bool = false
    var rifts: Bool = false
}

struct PelleDisabledMechanicInfo: Equatable, Identifiable {
    var id: String = ""               // stable key, e.g. "achievements", "blackHole"
    var label: String = ""            // user-facing name
    var statusText: String = ""       // "Disabled" / "Reduced to ..." / "Capped at..."
    var unlockedByText: String = ""   // "Unlocked by Pelle Upgrade X" or "" for permanent
}

struct PelleState: Equatable {
    var ready: Bool = false
    /// `Pelle.isUnlocked` — ImaginaryUpgrade(25) bought.
    var isUnlocked: Bool = false
    /// All `prePelleRows` requirements + alchemy resource caps satisfied.
    var canDoom: Bool = false
    /// `player.celestials.pelle.doomed`.
    var isDoomed: Bool = false
    var preDoomRequirements: [PelleRequirementInfo] = []
    var remnantsText: String = "0"
    var realityShardsText: String = "0"
    var realityShardsPerSecText: String = "0/s"
    /// `Pelle.riftDrainPercent` formatted as a percent ("3%"). Surfaced in
    /// the Strikes & Rifts panel flavor text ("When active, Rifts consume
    /// X% of another resource per second."). Mirrors web `PelleBarPanel.vue:54`.
    var riftDrainPercentText: String = "3%"
    var armageddon: PelleArmageddonInfo = PelleArmageddonInfo()
    var rebuyableUpgrades: [PelleUpgradeInfo] = []   // 5 always
    var oneTimeUpgrades: [PelleUpgradeInfo] = []     // ~20
    var strikes: [PelleStrikeInfo] = []              // 5
    var rifts: [PelleRiftInfo] = []                  // 5
    var galaxyGenerator: PelleGalaxyGeneratorInfo = PelleGalaxyGeneratorInfo()
    var disabledMechanics: [PelleDisabledMechanicInfo] = []
    var collapsed: PelleCollapsedFlags = PelleCollapsedFlags()
    var showBought: Bool = true
    /// `Pelle.specialGlyphEffect` description text when locked-in glyph is active.
    var specialGlyphEffectText: String = ""
    /// `Pelle.specialGlyphEffect.isUnlocked` — gates when to render the
    /// "chaos rift" extra effect line below the standard glyph effects.
    /// Mirrors web `CurrentGlyphEffects.vue.showChaosText`.
    var specialGlyphEffectUnlocked: Bool = false
    /// `Pelle.glyphMaxLevel` — capped by PelleUpgrade.glyphLevels.
    var glyphMaxLevel: Int = 0
    /// Doomed-glyph rarity readout — `formatPercents(strengthToRarity(Pelle.glyphStrength))`.
    /// Always "0%" early-game; populated via `Pelle.glyphStrength`.
    var glyphRarityText: String = "0%"
    /// Per-Reality Remnant gain breakdown — mirrors `RemnantGainFactor.vue`.
    /// Each line is "Label: contribution" plus a final "Total" row. Empty
    /// when not yet doomed or when `Pelle.cel.records.totalRemnants` is 0.
    var remnantGainBreakdown: [PelleRemnantFactorLine] = []
}

/// One line of the RemnantGainFactor breakdown — mirrors `RemnantGainFactor.vue`'s
/// rows (Antimatter / Replicanti / Eternity / Reality time penalty / Total).
struct PelleRemnantFactorLine: Equatable, Identifiable {
    var id: String = ""
    var label: String = ""
    var value: String = ""
    var isTotal: Bool = false
}

// MARK: - Root

struct CelestialsState: Equatable {
    var teresa: TeresaState = TeresaState()
    var effarig: EffarigState = EffarigState()
    var enslaved: EnslavedState = EnslavedState()
    var v: VState = VState()
    var ra: RaState = RaState()
    var laitela: LaitelaState = LaitelaState()
    var pelle: PelleState = PelleState()
    var navigation: CelestialNavigationState = CelestialNavigationState()

    static let empty = CelestialsState()
}
