// perks-helper.js — cached + event-invalidated `_nativePerksState`.
//
// The previous inline IIFE in `pollPerks` rebuilt the entire 48-perk payload
// every tick the Perks tab was active — 48 × (label/desc/family/x/y/conn/...)
// reads + JSON.stringify of the result array. Profiling showed this as part of
// the ~167 ms/s `-[JSValue callWithArguments:]` budget.
//
// Strategy: cache the stringified perks array; rebuild only on events that
// actually change the data. `pp` (perk points) is appended live each call
// because automator can earn PP outside of events.
//
// Invalidation:
//   - PERK_BOUGHT          — flips one perk's isBought; may unlock canBeBought
//                            for any perk whose prereq just got bought
//   - REALITY_RESET_AFTER  — resets all perks; pp may change drastically
//   - GAME_LOAD            — fresh save loaded
//   - 0→≥1 PP transition   — `canBeBought` depends on pp ≥ 1; if PP wasn't
//                            covered by an event (e.g. odd save migration),
//                            this catches it
//
// DEBUG validation:
//   - When `globalThis._nativePerksValidateEvery` is set (e.g. to 30 for
//     once-per-second at 30Hz polling), every Nth call rebuilds fresh and
//     compares; logs `_nativeLog` on drift. Off in Release.
//
// Lifecycle: injected from `GameEngine.setupPerksHelper()`. The helper is
// re-injected on every save-lifecycle entry point (finishStartup, importSave,
// hardReset, slot-switch, backup-restore — 5 sites). To survive re-injection
// without losing the old event listeners' invalidation semantics, the cache
// object lives on `globalThis` rather than in the IIFE closure. Re-injection
// attaches MORE listeners (one extra per setup call, bounded ≤ 5 per session
// and reset on hardReset when EventHub.logic itself is rebuilt), each writing
// to the same shared cache — harmless duplication, never stale data.

(function () {
    "use strict";

    // Module-level cache survives re-injection of this script. Old event
    // listeners (attached by prior injections) close over the SAME cache via
    // its globalThis identity, so they keep invalidating correctly even after
    // a fresh `setupPerksHelper()` call. Starts `disabled` until we
    // successfully bind to EventHub — disabled means "rebuild every call",
    // which is byte-identical to the pre-cache behaviour (safety net).
    if (!globalThis._nativePerksCache) {
        globalThis._nativePerksCache = {
            valid: false,
            perksJSON: "",
            lastPP: -1,
            callCount: 0,
            disabled: true
        };
    }
    var cache = globalThis._nativePerksCache;

    function invalidate() { cache.valid = false; }

    try {
        if (typeof EventHub !== "undefined" && EventHub.logic && EventHub.logic.on &&
            typeof GAME_EVENT !== "undefined") {
            EventHub.logic.on(GAME_EVENT.PERK_BOUGHT, invalidate);
            EventHub.logic.on(GAME_EVENT.REALITY_RESET_AFTER, invalidate);
            EventHub.logic.on(GAME_EVENT.GAME_LOAD, invalidate);
            cache.disabled = false;
            // Also bust the cache right now — game state may have changed
            // since the last injection (slot switch, save import, etc.).
            invalidate();
        }
    } catch (e) {
        // Leave cache.disabled = true; helper will rebuild every call.
    }

    function decodePos(num) {
        var xPart = num % 400;
        var yPart = Math.floor(num / 400);
        var x = 5 * (xPart - 200);
        var y = 5 * (yPart - 200);
        return { x: 30 * x, y: 20 * y + 120 };
    }

    function buildPerksJSON() {
        var result = [];
        var allPerks = Perks.all;
        var connections = GameDatabase.reality.perkConnections;
        for (var i = 0; i < allPerks.length; i++) {
            var p = allPerks[i];
            var c = p.config;
            var pos = decodePos(c.layoutPosList[1]);
            var desc = typeof c.description === 'function' ? c.description() : c.description;
            if (typeof desc === 'object' && desc !== null) desc = String(desc);
            desc = String(desc || '').replace(/\s+/g, ' ').trim();
            var ap = c.automatorPoints || 0;
            result.push({
                id: p.id, label: c.label || '', desc: desc || '',
                family: c.family || '', bought: !!p.isBought,
                canBuy: !!p.canBeBought, ap: ap,
                x: pos.x, y: pos.y,
                conn: connections[p.id] || []
            });
        }
        return JSON.stringify(result);
    }

    function currentPP() {
        try { return Currency.perkPoints.value; }
        catch (e) { return 0; }
    }

    globalThis._nativePerksState = function () {
        var pp = currentPP();

        // 0→≥1 PP transition: canBuy may now be true for available perks
        // even though no event fired. Bust the cache.
        if (cache.valid && cache.lastPP === 0 && pp >= 1) {
            cache.valid = false;
        }

        if (cache.disabled || !cache.valid) {
            cache.perksJSON = buildPerksJSON();
            cache.valid = true;
        }
        cache.lastPP = pp;

        // DEBUG validator — periodically rebuild fresh and diff against the
        // cached string. Logs (via _nativeLog) when they differ. Off unless
        // Swift sets the validate-every cadence.
        var validateEvery = globalThis._nativePerksValidateEvery | 0;
        if (validateEvery > 0) {
            cache.callCount = (cache.callCount + 1) | 0;
            if ((cache.callCount % validateEvery) === 0) {
                var fresh = buildPerksJSON();
                if (fresh !== cache.perksJSON) {
                    try {
                        var msg = "🔴 _nativePerksState drift @call " + cache.callCount +
                                  " (cached " + cache.perksJSON.length + "B, fresh " +
                                  fresh.length + "B)";
                        if (typeof _nativeLog !== "undefined") _nativeLog(msg);
                    } catch (e) {}
                    // Recover transparently — adopt fresh as the new cache.
                    cache.perksJSON = fresh;
                }
            }
        }

        return '{"perks":' + cache.perksJSON + ',"pp":' + pp + '}';
    };

    // Manual invalidator — exposed for Swift to call from special-case paths
    // (e.g. tests, or future events not yet covered above).
    globalThis._nativePerksInvalidate = invalidate;
})();
