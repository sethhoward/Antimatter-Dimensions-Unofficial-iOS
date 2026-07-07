// speedrun-helpers.js — JS bridge for Speedrun Mode.
//
// Mirrors the web `Speedrun` static class (`src/core/speedrun.js`) plus the
// `SpeedrunModeModal` flow (`src/components/modals/SpeedrunModeModal.vue`).
// Surfaces:
//   _nativeSpeedrunQuick()         — lightweight per-tick state (always polled)
//   _nativeSpeedrunHistoryState()  — full per-run details (Statistics tab,
//                                    on-demand only — NOT per-tick)
//   _nativeSpeedrunGenerateName(s) — wraps Speedrun.generateName
//   _nativeSpeedrunPrepare(name)   — wraps Speedrun.prepareSave (HARD RESET)
//
// Injected from `GameEngine.setupSpeedrunHelpers()`. Idempotent. Same lifecycle
// as the other helper scripts — re-injected on
// finishStartup / importSave / hardReset / slot-switch / backup-restore.

(function () {
    "use strict";

    function speedrunAvailable() {
        return typeof Speedrun !== "undefined" && Speedrun;
    }

    function speedrunRecord() {
        try {
            return (player && player.speedrun) || null;
        } catch (e) { return null; }
    }

    // Per-tick lightweight read. Surfaces just enough state to drive the
    // sidebar footer / header subtitle and to gate the Options entry point.
    // Returns 0 / false / empty fields when unavailable.
    globalThis._nativeSpeedrunQuick = function () {
        try {
            if (!speedrunAvailable()) {
                return JSON.stringify({
                    isUnlocked: false, isActive: false, hasStarted: false,
                    canShowOptionsEntry: false,
                    fullGameCompletions: 0,
                    name: "",
                    elapsedMs: 0,
                    mostRecentId: 0,
                    mostRecentMs: 0,
                    mostRecentName: ""
                });
            }
            var rec = speedrunRecord() || {};
            var records = (rec.records && rec.records.length) ? rec.records : [];
            // mostRecentMilestone returns the index in `records` (0 = none).
            // Web uses player.speedrun.records.max() + indexOf, but during
            // early bootstrapping `records` may be undefined; guard with the
            // local array we just defaulted. `records[id]` is the milestone
            // time for milestone `id` (1-indexed; index 0 unused), so the
            // winning index IS the milestone id — same as web's `indexOf`.
            var mostRecentMs = 0, mostRecentId = 0;
            for (var i = 0; i < records.length; ++i) {
                if (records[i] > mostRecentMs) {
                    mostRecentMs = records[i];
                    mostRecentId = i;
                }
            }
            // Resolve the milestone NAME from GameDatabase (single source of
            // truth — same lookup the Statistics history helper uses). Swift
            // must NOT keep its own id→name table: speedrun-milestones.js has
            // 25 entries and any hardcoded Swift copy drifts (the stale copy
            // mapped id 23 to "Pelle Doom" instead of "Regain Ra's Memories").
            var mostRecentName = "";
            if (mostRecentId > 0) {
                try {
                    var db = (typeof GameDatabase !== "undefined" && GameDatabase.speedrunMilestones)
                        ? GameDatabase.speedrunMilestones : [];
                    for (var k = 0; k < db.length; ++k) {
                        if (db[k].id === mostRecentId) { mostRecentName = db[k].name || ""; break; }
                    }
                } catch (e) {}
            }
            var fullCompletions = 0;
            try {
                if (player && player.records && typeof player.records.fullGameCompletions === "number") {
                    fullCompletions = player.records.fullGameCompletions;
                }
            } catch (e) {}
            var startDate = rec.startDate || 0;
            var elapsedMs = 0;
            if (rec.isActive && rec.hasStarted && startDate > 0) {
                // Web's SpeedrunStatus.vue derives this from Time.realTimePlayed.
                // We mirror that — Time.realTimePlayed wraps a TimeSpan over
                // player.records.realTimePlayed (ms).
                try { elapsedMs = (player.records && player.records.realTimePlayed) || 0; }
                catch (e) {}
            }
            return JSON.stringify({
                isUnlocked: !!rec.isUnlocked,
                isActive: !!rec.isActive,
                hasStarted: !!rec.hasStarted,
                // Options entry visibility — web uses `fullGameCompletions > 0`
                // in `options.js`'s SPEEDRUN section. Mirrors that exactly.
                canShowOptionsEntry: fullCompletions > 0,
                fullGameCompletions: fullCompletions,
                name: rec.name || "",
                elapsedMs: elapsedMs,
                mostRecentId: mostRecentId,
                mostRecentMs: mostRecentMs,
                mostRecentName: mostRecentName
            });
        } catch (e) {
            return JSON.stringify({
                isUnlocked: false, isActive: false, hasStarted: false,
                canShowOptionsEntry: false, fullGameCompletions: 0,
                name: "", elapsedMs: 0, mostRecentId: 0, mostRecentMs: 0,
                mostRecentName: ""
            });
        }
    };

    // Statistics-tab on-demand history block. Returns the full per-milestone
    // record array + metadata. Only called when the user navigates to the
    // Statistics tab and `isUnlocked` is true.
    globalThis._nativeSpeedrunHistoryState = function () {
        try {
            if (!speedrunAvailable()) return JSON.stringify({ ready: false });
            var rec = speedrunRecord() || {};
            var records = (rec.records && rec.records.length) ? rec.records : [];
            var db = (typeof GameDatabase !== "undefined" && GameDatabase.speedrunMilestones)
                ? GameDatabase.speedrunMilestones : [];
            var byId = {};
            for (var i = 0; i < db.length; ++i) byId[db[i].id] = db[i].name;
            // records[i] is the realTimePlayed milestone time for milestone id i.
            // index 0 is unused — milestones are 1-indexed in the DB. We
            // emit one row per DB entry so the UI can show "—" for unreached.
            var rows = [];
            for (var j = 0; j < db.length; ++j) {
                var id = db[j].id;
                rows.push({
                    id: id,
                    name: db[j].name,
                    timeMs: (records[id] || 0)
                });
            }
            return JSON.stringify({
                ready: true,
                isActive: !!rec.isActive,
                hasStarted: !!rec.hasStarted,
                isSegmented: !!rec.isSegmented,
                usedSTD: !!rec.usedSTD,
                name: rec.name || "",
                startDate: rec.startDate || 0,
                offlineTimeUsedMs: rec.offlineTimeUsed || 0,
                realTimePlayedMs: ((player && player.records && player.records.realTimePlayed) || 0),
                milestones: rows
            });
        } catch (e) { return JSON.stringify({ ready: false }); }
    };

    // Run name normalisation. Web's Speedrun.generateName strips leading/
    // trailing whitespace, generates a random "AD Player #NNNNNN" when empty,
    // and truncates names > 40 chars.
    globalThis._nativeSpeedrunGenerateName = function (raw) {
        try {
            if (!speedrunAvailable()) return "";
            return Speedrun.generateName(typeof raw === "string" ? raw : "");
        } catch (e) { return ""; }
    };

    // HARD RESET. Calls Speedrun.prepareSave which:
    //   1. Calls NG.restartWithCarryover() (clears player but keeps a
    //      whitelist of post-completion variables).
    //   2. Sets player.speedrun.isUnlocked = true, isActive = true.
    //   3. Sets player.speedrun.initialSeed to the official fixed seed.
    //   4. Sets player.speedrun.name to the provided name.
    //   5. Turns off animations + most confirmations.
    //   6. Grants Achievements 22, 35, 76 for free.
    //   7. Calls GameStorage.save() at the end.
    //
    // The Swift wrapper (`engine.startSpeedrun`) is responsible for the
    // timer/refs lifecycle around this call — mirrors `hardReset`.
    globalThis._nativeSpeedrunPrepare = function (name) {
        try {
            if (!speedrunAvailable()) return false;
            Speedrun.prepareSave(typeof name === "string" ? name : "");
            return true;
        } catch (e) {
            try { _nativeLog && _nativeLog("[speedrun] prepareSave failed: " + e); } catch (_e) {}
            return false;
        }
    };

    // Force-unlock — web's Speedrun.unlock fires a Modal.message.show toast
    // and sets isUnlocked = true. Players normally hit it automatically when
    // they reach `fullGameCompletions > 0` (via `options.js`'s seed button).
    // iOS calls this explicitly when surfacing the Options entry so the flag
    // is durable even if the user never opens the seed picker.
    globalThis._nativeSpeedrunUnlock = function () {
        try {
            if (!speedrunAvailable()) return false;
            if (player && player.speedrun && !player.speedrun.isUnlocked) {
                player.speedrun.isUnlocked = true;
            }
            return true;
        } catch (e) { return false; }
    };
})();
