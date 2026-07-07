// game-end-helpers.js — JS bridge for the post-Pelle finale.
//
// Mirrors `src/core/celestials/pelle/game-end.js` END_STATE_MARKERS:
//   GAME_END        = 1     (zalgoification + tab/save tracking begin)
//   TAB_START_HIDE  = 1.5
//   FADE_AWAY / INTERACTIVITY_DISABLED = 2.5
//   SAVE_DISABLED   = 4
//   END_NUMBERS     = 4.2
//   CREDITS_START   = 4.5
//   SHOW_NEW_GAME   = 13.5
//   SPECTATE_GAME   = 13.9
//   SONG_END        = 13.7
//   CREDITS_END     = 14.5
//
// Injected from `GameEngine.setupGameEndHelpers()` and idempotently
// re-injected from `finishStartup` / `importSave` / `hardReset`.

(function () {
    "use strict";

    function gameEndAvailable() {
        return typeof GameEnd !== "undefined" && GameEnd && typeof GameEnd.endState === "number";
    }

    // Lightweight per-tick read — surfaces the single endState number and
    // a few derived flags. Pulled in `pollDirect()`'s always-on block.
    globalThis._nativeGameEndQuick = function () {
        try {
            if (!gameEndAvailable()) return JSON.stringify({ es: 0, ce: false });
            return JSON.stringify({
                es: GameEnd.endState || 0,
                ce: !!GameEnd.creditsClosed
            });
        } catch (e) { return JSON.stringify({ es: 0, ce: false }); }
    };

    // Full state for the credits overlay. Only called when the overlay is
    // presented (endState >= CREDITS_START).
    globalThis._nativeGameEndState = function () {
        try {
            if (!gameEndAvailable()) return JSON.stringify({ ready: false });
            var es = GameEnd.endState || 0;
            return JSON.stringify({
                ready: true,
                endState: es,
                creditsClosed: !!GameEnd.creditsClosed,
                removeAdditionalEnd: !!GameEnd.removeAdditionalEnd,
                canShowNewGame: es >= 13.5 && !GameEnd.creditsClosed,
                canSpectate: es >= 13.9
            });
        } catch (e) { return JSON.stringify({ ready: false }); }
    };

    // Spectate — rewinds endState back to 0 over time (game-end.js gameLoop).
    globalThis._nativeGameEndSpectate = function () {
        try {
            if (!gameEndAvailable()) return false;
            GameEnd.removeAdditionalEnd = true;
            return true;
        } catch (e) { return false; }
    };

    // Mark the credits as closed (analogous to the web's "X" out of credits).
    globalThis._nativeGameEndCloseCredits = function () {
        try {
            if (!gameEndAvailable()) return false;
            GameEnd.creditsClosed = true;
            GameEnd.creditsEverClosed = true;
            return true;
        } catch (e) { return false; }
    };

    // DEBUG-only: jump the run to a specific endState by setting
    // `additionalEnd`. Wraps the `player.isGameEnd` flag so the additionalEnd
    // setter actually writes (it gates internally).
    globalThis._nativeGameEndJumpTo = function (target) {
        try {
            if (!gameEndAvailable()) return false;
            if (typeof target !== "number" || !isFinite(target)) return false;
            // Force the gate so additionalEnd's setter accepts our write.
            player.isGameEnd = true;
            // Compute the offset needed to reach `target` from the natural
            // (antimatter-driven) endState. additionalEnd stacks ON TOP of
            // the natural value, so we subtract.
            GameEnd.removeAdditionalEnd = false;
            // Read the antimatter-driven baseline by temporarily clearing
            // additionalEnd, computing endState, then restoring.
            var prevAdd = GameEnd._additionalEnd || 0;
            GameEnd._additionalEnd = 0;
            var baseline = 0;
            try { baseline = GameEnd.endState || 0; } catch (e) {}
            var delta = Math.max(0, target - baseline);
            GameEnd._additionalEnd = delta;
            return true;
        } catch (e) { return false; }
    };

    // DEBUG-only: clear the GameEnd state (back to pre-finale).
    globalThis._nativeGameEndReset = function () {
        try {
            if (!gameEndAvailable()) return false;
            GameEnd._additionalEnd = 0;
            GameEnd.removeAdditionalEnd = false;
            GameEnd.creditsClosed = false;
            player.isGameEnd = false;
            return true;
        } catch (e) { return false; }
    };
})();
