//
//  GameState+GameEnd.swift
//  AntiMatter
//
//  State for the post-Pelle finale (GameEnd / credits / zalgo). Mirrors
//  `src/core/celestials/pelle/game-end.js` END_STATE_MARKERS.
//
//  Lightweight per-tick reads (`endStateValue`, `gameEndCreditsClosed`)
//  live directly on `GameEngine`. The richer `GameEndState` struct here
//  is fetched on demand by the credits overlay.
//

import Foundation

/// END_STATE_MARKERS thresholds — kept in lockstep with the web's values.
/// Comments are the web names so a `git grep END_STATE_MARKERS` lands.
enum GameEndMarker {
    static let gameEnd: Double          = 1.0    // GAME_END
    static let tabStartHide: Double     = 1.5    // TAB_START_HIDE
    static let interactDisabled: Double = 2.5    // INTERACTIVITY_DISABLED + FADE_AWAY
    static let saveDisabled: Double     = 4.0    // SAVE_DISABLED
    static let endNumbers: Double       = 4.2    // END_NUMBERS
    static let creditsStart: Double     = 4.5    // CREDITS_START
    static let songEnd: Double          = 13.7   // SONG_END
    static let showNewGame: Double      = 13.5   // SHOW_NEW_GAME
    static let spectate: Double         = 13.9   // SPECTATE_GAME
    static let creditsEnd: Double       = 14.5   // CREDITS_END
}

/// On-demand state for the credits overlay. Not part of the per-tick
/// `gameState` blob — fetched via `engine.loadGameEndState(completion:)`
/// when the overlay needs to refresh interactive-button visibility.
struct GameEndState: Equatable {
    var ready: Bool = false
    var endState: Double = 0
    var creditsClosed: Bool = false
    var removeAdditionalEnd: Bool = false
    var canShowNewGame: Bool = false
    var canSpectate: Bool = false
}
