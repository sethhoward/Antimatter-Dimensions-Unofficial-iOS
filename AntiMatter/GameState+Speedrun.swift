//
//  GameState+Speedrun.swift
//  AntiMatter
//
//  State for Speedrun Mode. Mirrors `player.speedrun.*` from the JS save.
//
//  Lightweight per-tick reads live on `GameEngine.speedrunQuick`. The richer
//  history struct is fetched on demand by the Statistics tab and the
//  sidebar/header status display.
//

import Foundation

/// Per-tick speedrun state. Cheap — populated every poll via the always-on
/// `_nativeSpeedrunQuick()` JS bridge. Drives the live status display and
/// gates the Options entry point.
struct SpeedrunQuickState: Equatable {
    var isUnlocked: Bool = false
    var isActive: Bool = false
    var hasStarted: Bool = false
    /// Web parity: `fullGameCompletions > 0` (mirrors `options.js`'s gate).
    /// True once the player has reached end-game at least once.
    var canShowOptionsEntry: Bool = false
    var fullGameCompletions: Int = 0
    var name: String = ""
    /// Real-time-played in milliseconds. 0 when the run hasn't started yet
    /// (web pauses the clock until the first purchase auto-fires
    /// `Speedrun.startTimer`).
    var elapsedMs: Double = 0
    /// 0 = no milestones reached yet. Otherwise the speedrun-milestones.js
    /// id of the highest-time milestone.
    var mostRecentId: Int = 0
    var mostRecentMs: Double = 0
    /// Display name of the highest-time milestone, resolved JS-side from
    /// `GameDatabase.speedrunMilestones` (single source of truth — see
    /// `_nativeSpeedrunQuick`). Empty when no milestone reached yet.
    var mostRecentName: String = ""
}

/// On-demand history view of every milestone — populated when the player
/// navigates to Statistics → Speedrun history. Not part of the per-tick
/// `gameState` blob.
struct SpeedrunHistoryState: Equatable {
    var ready: Bool = false
    var isActive: Bool = false
    var hasStarted: Bool = false
    var isSegmented: Bool = false
    var usedSTD: Bool = false
    var name: String = ""
    /// Unix epoch ms of run start. 0 if not started.
    var startDate: Double = 0
    var offlineTimeUsedMs: Double = 0
    var realTimePlayedMs: Double = 0
    var milestones: [SpeedrunMilestoneInfo] = []
}

struct SpeedrunMilestoneInfo: Identifiable, Equatable {
    let id: Int
    let name: String
    /// Real-time-played at completion, in ms. 0 = not reached this run.
    let timeMs: Double
}
