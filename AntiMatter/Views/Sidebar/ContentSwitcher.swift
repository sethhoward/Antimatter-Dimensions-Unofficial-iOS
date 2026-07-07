//
//  ContentSwitcher.swift
//  AntiMatter
//
//  Maps the active Subtab to the corresponding SwiftUI view.
//  Zero changes needed to existing tab views — they plug in as-is.
//

import SwiftUI

struct ContentSwitcher: View {
    let subtab: Subtab
    let engine: GameEngine
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        // Pre-Break Infinity takeover — replaces content with Big Crunch screen.
        // iPhone gates additionally on `!infinityUnlocked` so the takeover fires
        // for the first crunch only; subsequent pre-break crunches use the
        // header button in `CompactPrestigeRow`. iPad keeps the original
        // every-tick behavior.
        let showTakeover = metrics.isCompact
            ? engine.gameState.infinity.showBigCrunchTakeoverFirstOnly
            : engine.gameState.infinity.showBigCrunchTakeover
        if showTakeover {
            BigCrunchTakeover(engine: engine)
        } else {
            subtabContent
        }
    }

    @ViewBuilder
    private var subtabContent: some View {
        switch subtab {
        case .antimatterDimensions:
            AntimatterDimensionsTab(engine: engine)
        case .infinityDimensions:
            InfinityDimensionsTab(engine: engine)
        case .normalAchievements:
            AchievementsTab(engine: engine)
        case .secretAchievements:
            SecretAchievementsTab(engine: engine)
        case .autobuyers:
            AutobuyersTab(engine: engine)
        case .normalChallenges:
            NormalChallengesTab(engine: engine)
        case .infinityChallenges:
            InfinityChallengesTab(engine: engine)
        case .infinityUpgrades:
            InfinityUpgradesTab(engine: engine)
        case .breakInfinity:
            BreakInfinityTab(engine: engine)
        case .replicanti:
            ReplicantiTab(engine: engine)
        case .statistics:
            StatisticsTab(engine: engine)
        case .challengeRecords:
            ChallengeRecordsTab(engine: engine)
        case .pastPrestigeRuns:
            PastPrestigeRunsTab(engine: engine)
        case .multiplierBreakdown:
            MultiplierBreakdownTab(engine: engine)
        case .glyphSetRecords:
            GlyphSetRecordsTab(engine: engine)
        case .speedrunMilestones:
            SpeedrunMilestonesTab(engine: engine)
        case .speedrunRecords:
            SpeedrunRecordsTab(engine: engine)
        case .options:
            OptionsTab(engine: engine)
        case .optionsGameplay:
            OptionsGameplayTab(engine: engine)
        case .optionsHelp:
            HelpIndexView(engine: engine)
        case .debug:
            DebugTab(engine: engine)
        case .timeDimensions:
            TimeDimensionsTab(engine: engine)
        case .eternityUpgrades:
            EternityUpgradesTab(engine: engine)
        case .eternityMilestones:
            EternityMilestonesTab(engine: engine)
        case .eternityChallenges:
            EternityChallengesTab(engine: engine)
        case .timeStudies:
            TimeStudiesTab(engine: engine)
        case .timeDilation:
            TimeDilationTab(engine: engine)
        // Reality
        case .glyphs:
            GlyphsTab(engine: engine)
        case .realityUpgrades:
            RealityUpgradesTab(engine: engine)
        case .imaginaryUpgrades:
            ImaginaryUpgradesTab(engine: engine)
        case .perks:
            PerksTab(engine: engine)
        case .blackHole:
            BlackHoleTab(engine: engine)
        case .glyphAlchemy:
            AlchemyTab(engine: engine)
        // Celestials
        case .celestialNavigation:
            CelestialNavigationTab(engine: engine)
        case .teresa:
            TeresaTab(engine: engine)
        case .effarig:
            EffarigTab(engine: engine)
        case .namelessOnes:
            EnslavedTab(engine: engine)
        case .v:
            VTab(engine: engine)
        case .ra:
            RaTab(engine: engine)
        case .laitela:
            LaitelaTab(engine: engine)
        case .pelle:
            PelleTab(engine: engine)
        // Automation
        case .automator:
            AutomatorTab(engine: engine)
        }
    }
}
