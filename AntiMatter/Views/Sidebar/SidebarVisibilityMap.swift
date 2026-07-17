//
//  SidebarVisibilityMap.swift
//  AntiMatter
//
//  iOS ↔ web ID mapping for the "Modify Visible Tabs" feature.
//
//  Web stores tab/subtab visibility in `player.options.hiddenTabBits` (Int bitfield
//  over the 11 web tab IDs, 0..10) and `player.options.hiddenSubtabBits` (Int[11],
//  one bitfield per parent tab). iOS reuses those fields verbatim so a save with
//  hidden tabs round-trips between web and iOS. This file is the single source
//  of truth for the iOS-enum ↔ web-id mapping.
//
//  Reference: src/core/secret-formula/tabs.js
//
//  Rules:
//  - `webId` is the web's tab/subtab id. nil means "not represented on web"
//    (the iOS-only Debug tab + its sole subtab — never hideable).
//  - `isWebHideable` mirrors web's `hidable` flag. Options + its subtabs are
//    `false` (must always be visible — the "Modify Visible Tabs" UI itself
//    lives under Options → Gameplay).
//  - iOS subtab declaration order in `SidebarTab.subtabs` matches web's id
//    sequence in `tabs.js`, so the positional mapping below is exact.
//

import Foundation

// MARK: - Tab mapping

extension SidebarTab {
    /// Web tab id (from `src/core/secret-formula/tabs.js`). nil for the
    /// iOS-only Debug tab.
    var webId: Int? {
        switch self {
        case .dimensions:   0
        case .options:      1
        case .statistics:   2
        case .achievements: 3
        case .automation:   4
        case .challenges:   5
        case .infinity:     6
        case .eternity:     7
        case .reality:      8
        case .celestials:   9
        case .debug:        nil
        // Web id 10 is the Shop tab, which iOS doesn't port.
        }
    }

    /// Mirrors web's `tabs.js` `hidable` flag. Options is `false` on web; iOS
    /// Debug is also `false` because we never want to hide our DEBUG-only tab.
    var isWebHideable: Bool {
        switch self {
        case .options, .debug: false
        default:               true
        }
    }
}

// MARK: - Subtab mapping

extension Subtab {
    /// Web subtab id within its parent tab (from `src/core/secret-formula/tabs.js`).
    /// nil for iOS-only subtabs (`.optionsHelp`, `.debug`).
    var webId: Int? {
        switch self {
        // Dimensions
        case .antimatterDimensions: 0
        case .infinityDimensions:   1
        case .timeDimensions:       2

        // Options — non-hideable, but mapped for completeness.
        case .options:              0  // "saving"
        // Web id 1 is "visual" — iOS doesn't have a visual subtab.
        case .optionsGameplay:      2  // "gameplay"
        case .optionsHelp:          nil // iOS-only

        // Statistics
        case .statistics:           0
        case .challengeRecords:     1
        case .pastPrestigeRuns:     2
        case .multiplierBreakdown:  3
        case .glyphSetRecords:      4
        case .speedrunMilestones:   5
        case .speedrunRecords:      6

        // Achievements
        case .normalAchievements:   0
        case .secretAchievements:   1

        // Automation
        case .autobuyers:           0
        case .automator:            1

        // Challenges
        case .normalChallenges:     0
        case .infinityChallenges:   1
        case .eternityChallenges:   2

        // Infinity
        case .infinityUpgrades:     0
        case .breakInfinity:        1
        case .replicanti:           2

        // Eternity
        case .timeStudies:          0
        case .eternityUpgrades:     1
        case .eternityMilestones:   2
        case .timeDilation:         3

        // Reality
        case .glyphs:               0
        case .realityUpgrades:      1
        case .imaginaryUpgrades:    2
        case .perks:                3
        case .blackHole:            4
        case .glyphAlchemy:         5

        // Celestials
        case .celestialNavigation:  0
        case .teresa:               1
        case .effarig:              2
        case .namelessOnes:         3
        case .v:                    4
        case .ra:                   5
        case .laitela:              6
        case .pelle:                7

        // iOS-only
        case .debug:                nil
        }
    }

    /// Mirrors web's `tabs.js` per-subtab `hidable` flag. Options subtabs are
    /// non-hideable on web; iOS-only subtabs (optionsHelp, debug) are
    /// non-hideable because they have no web id.
    var isWebHideable: Bool {
        switch self {
        case .options, .optionsGameplay, .optionsHelp, .debug: false
        default:                                                true
        }
    }
}
