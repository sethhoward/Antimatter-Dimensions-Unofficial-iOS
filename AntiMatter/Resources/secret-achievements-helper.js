// secret-achievements-helper.js — cached + event-invalidated
// `_nativeSecretAchievementsState`.
//
// 32 secret achievements grouped into 4 rows of 8 (IDs 11–18, 21–28, 31–38,
// 41–48). Mirrors the perks-helper.js pattern:
//   * Static fields (name, description, row, column) are computed ONCE and
//     embedded in a cached JSON string.
//   * Only `isUnlocked` per ID changes between rebuilds.
//   * Cache lives on `globalThis` so it survives re-injection.
//
// Invalidation events:
//   - ACHIEVEMENT_UNLOCKED  — fired by both `Achievement.unlock()` AND
//                             `SecretAchievement.unlock()` (web shares one
//                             event for both). Busts a touch over-eagerly
//                             on normal-ach unlocks too, but the payload
//                             is small (32 entries) so the cost is trivial.
//   - REALITY_RESET_AFTER   — Reality reset clears no secrets, but we bust
//                             defensively in case a future upstream change does
//   - GAME_LOAD             — fresh save loaded; unlock set may differ
//
// Also exposes `_nativeUnlockSecretAchievement(id)` for the #11 tap-to-unlock
// easter egg (the only secret with a direct UI trigger). All other secrets
// unlock via JS-side `checkRequirement` + `checkEvent`, keyboard sequences,
// or per-spot UI hooks — never through this bridge.
//
// Lifecycle: injected from `GameEngine.setupSecretAchievementsHelper()` at
// each save-lifecycle entry point (finishStartup, importSave, hardReset,
// slot-switch, backup-restore). Cache identity is preserved across
// re-injection via `globalThis` so old listeners keep working.

(function () {
    "use strict";

    if (!globalThis._nativeSecretAchievementsCache) {
        globalThis._nativeSecretAchievementsCache = {
            valid: false,
            payloadJSON: "",
            disabled: true
        };
    }
    var cache = globalThis._nativeSecretAchievementsCache;

    function invalidate() { cache.valid = false; }

    try {
        if (typeof EventHub !== "undefined" && EventHub.logic && EventHub.logic.on &&
            typeof GAME_EVENT !== "undefined") {
            EventHub.logic.on(GAME_EVENT.ACHIEVEMENT_UNLOCKED, invalidate);
            EventHub.logic.on(GAME_EVENT.REALITY_RESET_AFTER, invalidate);
            EventHub.logic.on(GAME_EVENT.GAME_LOAD, invalidate);
            cache.disabled = false;
            // Bust now — game state may have changed since last injection.
            invalidate();
        }
    } catch (e) {
        // Leave cache.disabled = true; helper rebuilds every call. Safety net.
    }

    function normText(v) {
        if (v == null) return "";
        var s = (typeof v === "function") ? (function () {
            try { return v(); } catch (e) { return ""; }
        })() : v;
        if (typeof s !== "string") s = String(s);
        return s.replace(/\s+/g, " ").trim();
    }

    function buildPayload() {
        var rows = [];
        var totalCount = 0;
        var unlockedCount = 0;
        try {
            // SecretAchievements.allRows = [[SecretAchievement(11)..(18)], [..28], [..38], [..48]]
            // — see src/core/achievements/secret-achievement.js.
            var allRows = SecretAchievements.allRows;
            for (var r = 0; r < allRows.length; r++) {
                var rowArr = allRows[r];
                var row = [];
                for (var c = 0; c < rowArr.length; c++) {
                    var sa = rowArr[c];
                    if (!sa) continue;
                    var name = normText(sa.name);
                    var desc = normText(sa.description);
                    var unlocked = !!sa.isUnlocked;
                    row.push({
                        id: sa.id,
                        name: name,
                        description: desc,
                        isUnlocked: unlocked,
                        row: r + 1,
                        column: c + 1
                    });
                    totalCount++;
                    if (unlocked) unlockedCount++;
                }
                rows.push(row);
            }
        } catch (e) {
            // Bundle bootstrap order shouldn't allow this, but fall back to
            // an empty payload rather than throwing — Swift will render the
            // empty grid and the next invalidation will repopulate.
            rows = [];
            totalCount = 0;
            unlockedCount = 0;
        }
        return JSON.stringify({
            rows: rows,
            totalCount: totalCount,
            unlockedCount: unlockedCount
        });
    }

    globalThis._nativeSecretAchievementsState = function () {
        if (cache.disabled || !cache.valid) {
            cache.payloadJSON = buildPayload();
            cache.valid = true;
        }
        return cache.payloadJSON;
    };

    // Tap-to-unlock for SecretAchievement(11) — "The first one's always free".
    // Returns true if the unlock fired (was previously locked), false if it
    // was already unlocked or the call failed.
    globalThis._nativeUnlockSecretAchievement = function (id) {
        try {
            var sa = SecretAchievement(id);
            if (!sa || sa.isUnlocked) return false;
            sa.unlock();
            return true;
        } catch (e) {
            return false;
        }
    };

    // Manual invalidator — exposed for Swift to call from special-case paths.
    globalThis._nativeSecretAchievementsInvalidate = invalidate;
})();
