// speedrun-records-helper.js — JS bridge for Statistics > Speedrun Records
// subtab. Mirrors `PreviousSpeedrunTab.vue`.
//
// `_nativePreviousSpeedruns()` returns the full list of `player.speedrun
// .previousRuns` entries with milestone records, current-run records, and
// per-milestone best times across all prior runs (used for fast/slow/fastest
// colouring on the compare view).
//
// On-demand only — NOT per-tick polled. Refreshed when the subtab opens.

(function () {
    "use strict";

    function safeNum(v, fallback) {
        if (typeof v === "number" && isFinite(v)) return v;
        return fallback || 0;
    }

    function fmtShort(ms) {
        try {
            if (!isFinite(ms) || ms <= 0) return "—";
            return TimeSpan.fromMilliseconds(ms).toStringShort();
        } catch (e) { return "—"; }
    }

    globalThis._nativePreviousSpeedruns = function () {
        try {
            var sr = (player && player.speedrun) || {};
            var prev = sr.previousRuns || {};
            var keys = Object.keys(prev);
            var db = (typeof GameDatabase !== "undefined" && GameDatabase.speedrunMilestones)
                ? GameDatabase.speedrunMilestones : [];
            var recLength = db.length + 1;

            // Compute best per-milestone across all previous runs.
            var bestTimes = [];
            var bestRunKeys = [];
            for (var i = 0; i < recLength; ++i) { bestTimes.push(0); bestRunKeys.push(null); }
            for (var k = 0; k < keys.length; ++k) {
                var rec = (prev[keys[k]] && prev[keys[k]].records) || [];
                for (var r = 0; r < recLength; ++r) {
                    var t = safeNum(rec[r], 0);
                    if (t !== 0 && (t < bestTimes[r] || bestTimes[r] === 0)) {
                        bestTimes[r] = t;
                        bestRunKeys[r] = keys[k];
                    }
                }
            }

            // Serialize the runs.
            var runs = [];
            for (var j = 0; j < keys.length; ++j) {
                var key = keys[j];
                var entry = prev[key] || {};
                var records = entry.records || [];
                var milestones = [];
                for (var m = 0; m < db.length; ++m) {
                    var id = db[m].id;
                    milestones.push({
                        id: id,
                        name: db[m].name,
                        timeMs: safeNum(records[id], 0)
                    });
                }
                runs.push({
                    id: String(key),
                    name: entry.name || ("Run #" + key),
                    isSegmented: !!entry.isSegmented,
                    totalTimeMs: safeNum(records[records.length - 1] || 0, 0),
                    dateFinishedMs: safeNum(entry.dateCompleted || entry.dateEnd || 0, 0),
                    milestones: milestones
                });
            }

            // Sort by run id ascending (run number) for stable display.
            runs.sort(function (a, b) {
                var na = Number(a.id), nb = Number(b.id);
                if (isNaN(na) || isNaN(nb)) return 0;
                return na - nb;
            });

            // Current-run records, for milestones comparison.
            var currentRecords = [];
            for (var c = 0; c < db.length; ++c) {
                currentRecords.push({
                    id: db[c].id,
                    name: db[c].name,
                    timeMs: safeNum((sr.records || [])[db[c].id], 0)
                });
            }

            var bestPerMilestone = [];
            for (var bm = 0; bm < db.length; ++bm) {
                var id2 = db[bm].id;
                bestPerMilestone.push({
                    id: id2,
                    timeMs: safeNum(bestTimes[id2], 0),
                    bestRunId: bestRunKeys[id2]
                });
            }

            return JSON.stringify({
                runCount: runs.length,
                runs: runs,
                currentRecords: currentRecords,
                bestPerMilestone: bestPerMilestone
            });
        } catch (e) {
            try { _nativeLog && _nativeLog("[speedrun-records] failed: " + e); } catch (_e) {}
            return JSON.stringify({ runCount: 0, runs: [], currentRecords: [], bestPerMilestone: [] });
        }
    };

    // For the SpeedrunMilestonesTab — surfaces the "Describe all milestones"
    // persisted toggle plus the start-date string.
    globalThis._nativeSpeedrunMilestonesMeta = function () {
        try {
            var sr = (player && player.speedrun) || {};
            var displayAll = !!sr.displayAllMilestones;
            var startDate = sr.startDate || 0;
            var startStr = startDate === 0
                ? "Speedrun not started yet."
                : "Speedrun started at " + Time.toDateTimeString(startDate);
            return JSON.stringify({
                displayAll: displayAll,
                startTimeStr: startStr,
                hasStarted: !!sr.hasStarted
            });
        } catch (e) {
            return JSON.stringify({
                displayAll: false, startTimeStr: "Speedrun not started yet.", hasStarted: false
            });
        }
    };

    globalThis._nativeSpeedrunSetDisplayAll = function (val) {
        try {
            if (player && player.speedrun) player.speedrun.displayAllMilestones = !!val;
            return true;
        } catch (e) { return false; }
    };
})();
