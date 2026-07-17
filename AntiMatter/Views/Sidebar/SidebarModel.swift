//
//  SidebarModel.swift
//  AntiMatter
//
//  Two-level tab hierarchy for the custom game sidebar.
//  SidebarTab = parent (Dimensions, Infinity, …)
//  Subtab = leaf (Antimatter Dims, Infinity Upgrades, …)
//

import SwiftUI

// MARK: - Subtab symbol (text glyph vs SF Symbol)

enum SubtabSymbol {
    case text(String)
    case sfSymbol(String)
}

// MARK: - Poll categories (used by GameEngine for tab-gated polling)

enum PollCategory: Int {
    case dimensions
    case achievements
    case autobuyers
    case infinity
    case challenges
    case statistics
    case eternity
    case reality
    case automator
    case celestials
    case none
}

// MARK: - Parent tabs

enum SidebarTab: String, CaseIterable, Hashable, Identifiable {
    var id: String { rawValue }

    case dimensions
    case automation
    case challenges
    case infinity
    case eternity
    case reality
    case celestials
    case achievements
    case statistics
    case options
    case debug

    var displayName: String {
        switch self {
        case .dimensions:   "Dimensions"
        case .achievements: "Achievements"
        case .automation:   "Automation"
        case .challenges:   "Challenges"
        case .infinity:     "Infinity"
        case .eternity:     "Eternity"
        case .reality:      "Reality"
        case .celestials:   "Celestials"
        case .statistics:   "Statistics"
        case .options:      "Options"
        case .debug:        "Debug"
        }
    }

    var accentColor: Color {
        switch self {
        case .infinity:    GameColor.infinity
        case .eternity:    GameColor.eternity
        case .reality:     GameColor.reality
        case .celestials:  GameColor.celestials
        default:           GameColor.antimatter
        }
    }

    /// Text color when this tab is NOT selected.
    /// Most tabs use white; themed tabs (Infinity, Eternity, …) keep their accent color.
    var inactiveTextColor: Color {
        switch self {
        case .infinity, .eternity, .reality, .celestials: accentColor.opacity(0.7)
        default:                   .white.opacity(0.7)
        }
    }

    /// All possible subtabs for this parent (static list).
    var subtabs: [Subtab] {
        switch self {
        case .dimensions:   [.antimatterDimensions, .infinityDimensions, .timeDimensions]
        case .achievements: [.normalAchievements, .secretAchievements]
        case .automation:   [.autobuyers, .automator]
        case .challenges:   [.normalChallenges, .infinityChallenges, .eternityChallenges]
        case .infinity:     [.infinityUpgrades, .breakInfinity, .replicanti]
        case .eternity:     [.timeStudies, .eternityUpgrades, .eternityMilestones, .timeDilation]
        case .reality:      [.glyphs, .realityUpgrades, .imaginaryUpgrades, .perks, .blackHole, .glyphAlchemy]
        case .celestials:   [.celestialNavigation, .teresa, .effarig, .namelessOnes, .v, .ra, .laitela, .pelle]
        case .statistics:   [.statistics, .challengeRecords, .pastPrestigeRuns,
                             .multiplierBreakdown, .glyphSetRecords,
                             .speedrunMilestones, .speedrunRecords]
        case .options:      [.options, .optionsGameplay, .optionsHelp]
        case .debug:        [.debug]
        }
    }

    /// Default subtab when first navigating to this tab.
    var defaultSubtab: Subtab { subtabs[0] }

    /// Whether the entire tab is visible given current game state.
    func isAvailable(engine: GameEngine) -> Bool {
        switch self {
        case .automation:  engine.autobuyersUnlocked
        case .challenges:  engine.infinityUnlocked
        case .infinity:    engine.infinityUnlocked
        case .eternity:    engine.eternityUnlocked
        case .reality:     engine.realityUnlocked || engine.realityStudyBought
        case .celestials:  engine.teresaUnlocked
        #if DEBUG
        case .debug:       true
        #else
        case .debug:       false
        #endif
        default:           true
        }
    }

    /// Subtabs that are unlocked (shown in flyout even if view isn't built yet — placeholder handles it).
    func availableSubtabs(engine: GameEngine) -> [Subtab] {
        subtabs.filter { $0.isAvailable(engine: engine) }
    }

    /// Subtabs that are both unlocked AND not hidden by the user. Use this for
    /// any user-facing surface (sidebar, tab bar, swipe pager, cycle target).
    /// Use `availableSubtabs(engine:)` only for the "Modify Visible Tabs" sheet
    /// where the user needs to see + toggle every unlocked subtab regardless
    /// of its hidden state.
    func availableVisibleSubtabs(engine: GameEngine) -> [Subtab] {
        availableSubtabs(engine: engine).filter { !$0.isHidden(engine: engine) }
    }

    /// User has hidden this tab via "Modify Visible Tabs". Mirrors web
    /// `TabState.isHidden` (tabs.js):
    ///   - Non-hideable tabs (Options, Debug) are never hidden.
    ///   - During Enslaved Reality, all tabs are force-visible (web also
    ///     force-shows after Galaxy Generator unlocks, but iOS doesn't port
    ///     Galaxy Generator yet).
    ///   - The tab's own bit in `hiddenTabBits` flips this on.
    ///   - Auto-hide: a tab whose every subtab has its bit set is also
    ///     treated as hidden. This matches web's `subtabs.every(s => s.isHidden)`
    ///     check — a single non-hideable subtab (e.g. iOS `.optionsHelp` /
    ///     `.debug`) returns false here and blocks the auto-hide, so iOS
    ///     Options can never auto-hide.
    func isHidden(engine: GameEngine) -> Bool {
        guard isWebHideable, let id = webId else { return false }
        // Force-visible during Enslaved Reality (mirrors web pelle.js
        // / tabs.js force-show during The Nameless Ones' run).
        if engine.currentCelestialReality == "enslaved" { return false }
        let bits = engine.hiddenTabBits
        if (bits & (1 << id)) != 0 { return true }
        // Auto-hide when every subtab is hidden. Non-hideable subtabs return
        // false from their own isHidden, so they correctly block auto-hide.
        let subs = subtabs
        if subs.isEmpty { return false }
        return subs.allSatisfy { $0.isHidden(engine: engine) }
    }

    /// SF Symbol name for tab bar display (iPhone).
    var sfSymbol: String {
        switch self {
        case .dimensions:   "cube"
        case .automation:   "gearshape.2"
        case .challenges:   "flame"
        case .infinity:     "infinity"
        case .eternity:     "hourglass"
        case .reality:      "globe.americas"
        case .celestials:   "sparkles"
        case .achievements: "trophy"
        case .statistics:   "list.clipboard"
        case .options:      "document.badge.gearshape"
        case .debug:        "ladybug"
        }
    }
}

// MARK: - Leaf subtabs

enum Subtab: String, Hashable {
    // Dimensions
    case antimatterDimensions
    case infinityDimensions
    case timeDimensions

    // Achievements
    case normalAchievements
    case secretAchievements

    // Automation
    case autobuyers
    case automator

    // Challenges
    case normalChallenges
    case infinityChallenges
    case eternityChallenges

    // Infinity
    case infinityUpgrades
    case breakInfinity
    case replicanti

    // Eternity
    case eternityUpgrades
    case eternityMilestones
    case timeStudies
    case timeDilation

    // Reality
    case glyphs
    case realityUpgrades
    case imaginaryUpgrades
    case perks
    case blackHole
    case glyphAlchemy

    // Celestials
    case celestialNavigation
    case teresa
    case effarig
    case namelessOnes
    case v
    case ra
    case laitela
    case pelle

    // Statistics
    case statistics
    case challengeRecords
    case pastPrestigeRuns
    case multiplierBreakdown
    case glyphSetRecords
    case speedrunMilestones
    case speedrunRecords

    // Standalone
    case options
    case optionsGameplay
    case optionsHelp
    case debug

    var displayName: String {
        switch self {
        case .antimatterDimensions: "Antimatter Dimensions"
        case .infinityDimensions:   "Infinity Dimensions"
        case .timeDimensions:       "Time Dimensions"
        case .normalAchievements:   "Achievements"
        case .secretAchievements:   "Secret Achievements"
        case .autobuyers:           "Autobuyers"
        case .automator:            "Automator"
        case .normalChallenges:     "Normal Challenges"
        case .infinityChallenges:   "Infinity Challenges"
        case .eternityChallenges:   "Eternity Challenges"
        case .infinityUpgrades:     "Infinity Upgrades"
        case .breakInfinity:        "Break Infinity"
        case .replicanti:           "Replicanti"
        case .eternityUpgrades:     "Eternity Upgrades"
        case .eternityMilestones:   "Eternity Milestones"
        case .timeStudies:          "Time Studies"
        case .timeDilation:         "Time Dilation"
        case .glyphs:               "Glyphs"
        case .realityUpgrades:      "Reality Upgrades"
        case .imaginaryUpgrades:    "Imaginary Upgrades"
        case .perks:                "Perks"
        case .blackHole:            "Black Hole"
        case .glyphAlchemy:         "Glyph Alchemy"
        case .celestialNavigation:  "Celestial Navigation"
        case .teresa:               "Teresa"
        case .effarig:              "Effarig"
        case .namelessOnes:         "The Nameless Ones"
        case .v:                    "V"
        case .ra:                   "Ra"
        case .laitela:              "Lai'tela"
        case .pelle:                "Pelle"
        case .statistics:           "Statistics"
        case .challengeRecords:    "Challenge Records"
        case .pastPrestigeRuns:    "Past Prestige Runs"
        case .multiplierBreakdown: "Multiplier Breakdown"
        case .glyphSetRecords:     "Glyph Set Records"
        case .speedrunMilestones:  "Speedrun Milestones"
        case .speedrunRecords:     "Speedrun Records"
        case .options:              "Options"
        case .optionsGameplay:      "Gameplay"
        case .optionsHelp:          "Help"
        case .debug:                "Debug"
        }
    }

    /// Symbol type matching the web Modern UI (FontAwesome → SF Symbol, Unicode stays as-is).
    var symbolType: SubtabSymbol {
        switch self {
        case .antimatterDimensions: .text("Ω")
        case .infinityDimensions:   .text("∞")
        case .timeDimensions:       .text("Δ")
        case .normalAchievements:   .sfSymbol("trophy")
        case .secretAchievements:   .sfSymbol("questionmark.circle")
        case .autobuyers:           .sfSymbol("gearshape")
        case .automator:            .sfSymbol("chevron.left.forwardslash.chevron.right")
        case .normalChallenges:     .text("Ω")
        case .infinityChallenges:   .text("∞")
        case .eternityChallenges:   .text("Δ")
        case .infinityUpgrades:     .sfSymbol("arrow.up")
        case .breakInfinity:        .text("∝")
        case .replicanti:           .text("Ξ")
        case .eternityUpgrades:     .sfSymbol("arrow.up")
        case .eternityMilestones:   .sfSymbol("star")
        case .timeStudies:          .sfSymbol("book")
        case .timeDilation:         .text("Ψ")
        case .glyphs:               .sfSymbol("square.on.square")
        case .realityUpgrades:      .sfSymbol("arrow.up")
        case .imaginaryUpgrades:    .sfSymbol("arrow.up.forward")
        case .perks:                .sfSymbol("point.3.connected.trianglepath.dotted")
        case .blackHole:            .sfSymbol("circle.fill")
        case .glyphAlchemy:         .sfSymbol("flask")
        case .celestialNavigation:  .sfSymbol("map")
        case .teresa:               .text("Ϟ")
        case .effarig:              .text("Ϙ")
        case .namelessOnes:         .sfSymbol("link")
        case .v:                    .text("⌬")
        case .ra:                   .sfSymbol("sun.max")
        case .laitela:              .text("ᛝ")
        case .pelle:                .text("♅")
        case .statistics:           .sfSymbol("clipboard")
        case .challengeRecords:     .sfSymbol("stopwatch")
        case .pastPrestigeRuns:     .sfSymbol("list.number")
        case .multiplierBreakdown:  .sfSymbol("function")
        case .glyphSetRecords:      .sfSymbol("circle.grid.3x3")
        case .speedrunMilestones:   .sfSymbol("flag.checkered")
        case .speedrunRecords:      .sfSymbol("medal")
        case .options:              .sfSymbol("document.badge.gearshape")
        case .optionsGameplay:      .sfSymbol("wrench.and.screwdriver")
        case .optionsHelp:          .sfSymbol("questionmark.circle")
        case .debug:                .sfSymbol("ladybug")
        }
    }

    /// Whether a real SwiftUI view exists for this subtab.
    var hasView: Bool {
        switch self {
        case .breakInfinity, .replicanti: true
        case .challengeRecords, .pastPrestigeRuns: true
        default: true
        }
    }

    /// Whether this subtab is unlocked given current game state.
    func isAvailable(engine: GameEngine) -> Bool {
        switch self {
        case .infinityDimensions: engine.infinityDimsUnlocked
        case .timeDimensions:     engine.eternityUnlocked
        case .infinityUpgrades, .breakInfinity, .replicanti: engine.infinityUnlocked
        case .autobuyers:         engine.autobuyersUnlocked
        // Web `tabs.js:225` gates on `realityUnlocked || hasBroken || Pelle.isDoomed`.
        // `isBroken` (player.break) gets reset by Armageddon, so a doomed player
        // post-Armageddon would lose access to ICs without the doom disjunction —
        // even though `PelleUpgrade.keepInfinityChallenges` may still let them
        // play ICs. Reality unlock is the third disjunction (defensive — covers
        // any save state where reality is reached but `player.break` is somehow
        // false).
        case .infinityChallenges:
            engine.gameState.infinity.isBroken || engine.realityUnlocked || engine.pelleDoomed
        case .eternityChallenges: engine.eternityChallengesUnlocked
        case .eternityUpgrades, .eternityMilestones, .timeStudies: engine.eternityUnlocked
        case .timeDilation:       engine.dilationUnlocked || engine.realityUnlocked
        case .automator:          engine.realityUnlocked
        case .imaginaryUpgrades:  engine.imaginaryUpgradesUnlocked
        case .glyphAlchemy:       engine.glyphAlchemyUnlocked
        case .effarig:            engine.effarigUnlocked
        case .namelessOnes:       engine.effarigEternityUnlocked
        case .v:                  engine.vUnlocked
        case .ra:                 engine.raUnlocked
        case .laitela:            engine.laitelaUnlocked
        case .pelle:              engine.pelleUnlocked
        case .challengeRecords, .pastPrestigeRuns: engine.infinityUnlocked
        case .multiplierBreakdown: engine.multiplierBreakdownVisible
        case .glyphSetRecords:     engine.glyphSetRecordsVisible
        case .speedrunMilestones:  engine.speedrunMilestonesVisible
        case .speedrunRecords:     engine.speedrunRecordsVisible
        default:                  true
        }
    }

    /// Parent SidebarTab for this subtab. Computed once via reverse-scan of
    /// `SidebarTab.allCases` and cached. Used by `isHidden(engine:)` to find
    /// the correct `hiddenSubtabBits` slot.
    var parent: SidebarTab {
        Self.parentLookup[self] ?? .dimensions
    }

    private static let parentLookup: [Subtab: SidebarTab] = {
        var map: [Subtab: SidebarTab] = [:]
        for tab in SidebarTab.allCases {
            for sub in tab.subtabs {
                map[sub] = tab
            }
        }
        return map
    }()

    /// User has hidden this subtab via "Modify Visible Tabs". Mirrors web
    /// `SubtabState.isHidden` (tabs.js): non-hideable subtabs always visible;
    /// Enslaved Reality force-shows everything; otherwise check the parent
    /// tab's slot of `hiddenSubtabBits`.
    func isHidden(engine: GameEngine) -> Bool {
        guard isWebHideable,
              let subId = webId,
              let parentId = parent.webId
        else { return false }
        if engine.currentCelestialReality == "enslaved" { return false }
        let parentBits = engine.hiddenSubtabBits.indices.contains(parentId)
            ? engine.hiddenSubtabBits[parentId]
            : 0
        return (parentBits & (1 << subId)) != 0
    }

    /// JS notification key for this subtab (from player.tabNotifications Set).
    /// Keys are formed by concatenating the web tab's parent key + subtab key.
    static let jsKeyToSubtab: [String: Subtab] = [
        "infinityupgrades":                  .infinityUpgrades,
        "infinitybreak":                     .breakInfinity,
        "infinityreplicanti":                .replicanti,
        "dimensionsinfinity":                .infinityDimensions,
        "dimensionstime":                    .timeDimensions,
        "challengesnormal":                  .normalChallenges,
        "challengesinfinity":                .infinityChallenges,
        "eternitystudies":                   .timeStudies,
        "eternityupgrades":                  .eternityUpgrades,
        "eternitymilestones":                .eternityMilestones,
        "eternitydilation":                  .timeDilation,
        "automationautobuyers":              .autobuyers,
        "automationautomator":               .automator,
        "realityhole":                       .blackHole,
        "realityglyphs":                     .glyphs,
        "realityalchemy":                    .glyphAlchemy,
        "realityimag_upgrades":              .imaginaryUpgrades,
        "celestialscelestial-navigation":    .celestialNavigation,
        "celestialsteresa":                  .teresa,
        "celestialslaitela":                 .laitela,
        "celestialspelle":                   .pelle,
    ]

    /// Reverse mapping: Subtab → JS key string (for clearing from player.tabNotifications).
    static let subtabToJSKey: [Subtab: String] = {
        var map: [Subtab: String] = [:]
        for (jsKey, subtab) in jsKeyToSubtab {
            map[subtab] = jsKey
        }
        return map
    }()

    /// JS (tab key, subtab key) pair for syncing state.view.tab/subtab.
    /// Must match the keys in src/core/secret-formula/tabs.js so that
    /// Tabs.current returns the correct tab on the JS side.
    static let jsViewKeys: [Subtab: (tab: String, subtab: String)] = [
        // Dimensions
        .antimatterDimensions:  ("dimensions", "antimatter"),
        .infinityDimensions:    ("dimensions", "infinity"),
        .timeDimensions:        ("dimensions", "time"),
        // Achievements
        .normalAchievements:    ("achievements", "normal"),
        .secretAchievements:    ("achievements", "secret"),
        // Automation
        .autobuyers:            ("automation", "autobuyers"),
        .automator:             ("automation", "automator"),
        // Challenges
        .normalChallenges:      ("challenges", "normal"),
        .infinityChallenges:    ("challenges", "infinity"),
        .eternityChallenges:    ("challenges", "eternity"),
        // Infinity
        .infinityUpgrades:      ("infinity", "upgrades"),
        .breakInfinity:         ("infinity", "break"),
        .replicanti:            ("infinity", "replicanti"),
        // Eternity
        .eternityUpgrades:      ("eternity", "upgrades"),
        .eternityMilestones:    ("eternity", "milestones"),
        .timeStudies:           ("eternity", "studies"),
        .timeDilation:          ("eternity", "dilation"),
        // Reality
        .glyphs:                ("reality", "glyphs"),
        .realityUpgrades:       ("reality", "upgrades"),
        .imaginaryUpgrades:     ("reality", "imag_upgrades"),
        .perks:                 ("reality", "perks"),
        .blackHole:             ("reality", "hole"),
        .glyphAlchemy:          ("reality", "alchemy"),
        // Celestials
        .celestialNavigation:   ("celestials", "celestial-navigation"),
        .teresa:                ("celestials", "teresa"),
        .effarig:               ("celestials", "effarig"),
        .namelessOnes:          ("celestials", "enslaved"),
        .v:                     ("celestials", "v"),
        .ra:                    ("celestials", "ra"),
        .laitela:               ("celestials", "laitela"),
        .pelle:                 ("celestials", "pelle"),
        // Statistics
        .statistics:            ("statistics", "statistics"),
        .challengeRecords:      ("statistics", "challenges"),
        .pastPrestigeRuns:      ("statistics", "prestige runs"),
        .multiplierBreakdown:   ("statistics", "multipliers"),
        .glyphSetRecords:       ("statistics", "glyph sets"),
        .speedrunMilestones:    ("statistics", "speedrun milestones"),
        .speedrunRecords:       ("statistics", "speedrun records"),
        // Options / Debug
        .options:               ("options", "saving"),
        .optionsGameplay:       ("options", "gameplay"),
        .optionsHelp:           ("options", "saving"),
        .debug:                 ("options", "saving"),
    ]

    var pollCategory: PollCategory {
        switch self {
        case .antimatterDimensions, .infinityDimensions, .timeDimensions: .dimensions
        case .normalAchievements, .secretAchievements: .achievements
        case .autobuyers: .autobuyers
        case .normalChallenges, .infinityChallenges, .eternityChallenges: .challenges
        case .infinityUpgrades, .breakInfinity, .replicanti: .infinity
        case .eternityUpgrades, .eternityMilestones, .timeStudies, .timeDilation: .eternity
        case .glyphs, .realityUpgrades, .imaginaryUpgrades, .perks, .blackHole, .glyphAlchemy: .reality
        case .celestialNavigation, .teresa, .effarig, .namelessOnes, .v, .ra, .laitela, .pelle: .celestials
        case .automator: .automator
        case .statistics, .challengeRecords, .pastPrestigeRuns,
             .multiplierBreakdown, .glyphSetRecords,
             .speedrunMilestones, .speedrunRecords: .statistics
        case .options, .optionsGameplay, .optionsHelp, .debug: .none
        }
    }
}
