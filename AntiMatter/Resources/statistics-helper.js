// statistics-helper.js — JS bridge for the Statistics > Statistics subtab.
//
// `_nativeStatisticsGeneral()` returns one JSON blob with every field the
// Vue StatisticsTab.vue reads in its `update()` method, formatted JS-side
// so Swift doesn't have to TimeSpan / format / pluralize / strengthToRarity.
// Replaces the ~125 lines of inline forProperty + evaluateScript that used
// to live in `pollStatistics`. Single bridge crossing per tick.
//
// Injected from `GameEngine.setupStatisticsHelpers()`. Same lifecycle as
// the other helper scripts — re-injected at every save-lifecycle entry
// point (finishStartup / importSave / hardReset / slot-switch / backup-
// restore / startSpeedrun / cloud adopt).

(function () {
    "use strict";

    function safeBool(fn) { try { return !!fn(); } catch (e) { return false; } }
    function safeNum(fn) { try { var v = fn(); return typeof v === "number" ? v : 0; } catch (e) { return 0; } }
    function safeStr(fn) { try { var v = fn(); return typeof v === "string" ? v : ""; } catch (e) { return ""; } }

    // Plain TimeSpan.fromMilliseconds → toString() (full form for "real time
    // played" lines). Returns "0 seconds" on bad input so the UI never shows
    // empty / NaN.
    function fmtFull(ms) {
        try {
            if (!isFinite(ms) || ms < 0) return "0 seconds";
            return TimeSpan.fromMilliseconds(ms).toString();
        } catch (e) { return "0 seconds"; }
    }
    // Short form for prestige time records ("12.3 minutes" / "1d 2h").
    function fmtShort(ms) {
        try {
            if (!isFinite(ms) || ms < 0) return null;
            return TimeSpan.fromMilliseconds(ms).toStringShort();
        } catch (e) { return null; }
    }

    function fmtDecimal(value, places, placesUnder1000) {
        try { return format(value, places, placesUnder1000); } catch (e) { return "0"; }
    }

    // Mirrors Vue's formatDecimalAmount(num) — > 1e9 uses scientific format,
    // otherwise floor() to integer + formatInt.
    function fmtCount(value) {
        try {
            var dec = (typeof value === "object" && value && typeof value.gt === "function")
                ? value : new Decimal(value || 0);
            if (dec.gt(1e9)) return format(dec, 3);
            return formatInt(Math.floor(dec.toNumber()));
        } catch (e) { return "0"; }
    }

    // Inline web's pluralize("Infinity", count.floor()) helper.
    function plural(word, count) {
        try { return pluralize(word, count); } catch (e) { return word; }
    }

    globalThis._nativeStatisticsGeneral = function () {
        try {
            var records = (player && player.records) || {};
            var bestInf = records.bestInfinity || {};
            var bestEt = records.bestEternity || {};
            var bestRe = records.bestReality || {};

            // Progress gates
            var progress = (typeof PlayerProgress !== "undefined" && PlayerProgress.current) || {};
            var isInfUnlocked = safeBool(function () { return progress.isInfinityUnlocked; });
            var isEtUnlocked = safeBool(function () { return progress.isEternityUnlocked; });
            var isReUnlocked = safeBool(function () { return progress.isRealityUnlocked; });

            // General
            var totalAM = records.totalAntimatter;
            var realTimePlayed = records.realTimePlayed || 0;
            var saveCreatedTime = records.gameCreatedTime || Date.now();
            var saveAgeMs = Date.now() - saveCreatedTime;
            var fullGameCompletions = records.fullGameCompletions || 0;
            var fullTimePlayedMs = (records.previousRunRealTime || 0) + (records.realTimePlayed || 0);

            // News / Achievements
            var uniqueNews = safeNum(function () { return NewsHandler.uniqueTickersSeen; });
            var totalNews = safeNum(function () { return player.news.totalSeen; });
            var paperclips = safeNum(function () { return player.news.specialTickerData.paperclips; });
            var secretCount = safeNum(function () {
                return SecretAchievements.all.filter(function (a) { return a.isUnlocked; }).length;
            });

            // Matter scale (web throttles to once/sec for jitter — iOS polls
            // at 30Hz but the underlying log10 changes so slowly that the
            // recompute cost is dominated by the array build, not the math.
            // Keep simple here; revisit if it shows up in profiling).
            var matterScale = [];
            try {
                var arr = MatterScale.estimate(Currency.antimatter.value);
                if (arr && arr.length) {
                    for (var i = 0; i < arr.length; ++i) matterScale.push(String(arr[i]));
                }
            } catch (e) {}
            if (matterScale.length === 0) matterScale.push("There is no antimatter yet.");

            // Doom
            var isDoomed = safeBool(function () { return Pelle.isDoomed; });
            var realTimeDoomedMs = isDoomed ? (records.realTimeDoomed || 0) : 0;

            // Infinity block
            var infinityCount = null, bankedInfinities = null, bestInfTime = null,
                thisInfTime = null, thisInfReal = null, bestIPmin = null,
                projectedBanked = null, projectedBankedRate = null;
            if (isInfUnlocked) {
                var infCount = Currency.infinities.value;
                infinityCount = fmtCount(infCount) + " " + plural("Infinity", infCount.floor ? infCount.floor() : Math.floor(Number(infCount)));
                var banked = Currency.infinitiesBanked.value;
                var bankedCmp = (banked && typeof banked.gt === "function") ? banked.gt(0) : Number(banked) > 0;
                if (bankedCmp) {
                    bankedInfinities = fmtCount(banked.floor ? banked.floor() : Math.floor(Number(banked)))
                        + " " + plural("Banked Infinity", banked.floor ? banked.floor() : Math.floor(Number(banked)));
                }
                var biTime = (bestInf.time !== undefined) ? bestInf.time : 1e15;
                if (biTime < 999999999999) bestInfTime = fmtShort(biTime);
                thisInfTime = fmtShort(records.thisInfinity && records.thisInfinity.time);

                // bestIPminEternity is a Decimal.
                try { bestIPmin = format(bestInf.bestIPminEternity, 2, 2); } catch (e) {}

                // Projected banked (web computes this in the eternity block; iOS
                // surfaces it as part of the same payload so the eternity-section
                // wording can show "You will gain X Banked Infinities on Eternity").
                if (isEtUnlocked) {
                    try {
                        var proj = new Decimal(0).plusEffectsOf(
                            Achievement(131).effects.bankedInfinitiesGain,
                            TimeStudy(191)
                        );
                        if (proj.gt(0)) {
                            projectedBanked = fmtCount(proj.floor()) + " " + plural("Banked Infinity", proj.floor());
                            // bankRate = proj / max(33ms, thisEternity.realTime|.time) * 60000
                            var denomMs = Math.max(33, isReUnlocked
                                ? ((records.thisEternity && records.thisEternity.realTime) || 33)
                                : ((records.thisEternity && records.thisEternity.time) || 33));
                            var perMin = proj.div(denomMs).times(60000);
                            projectedBankedRate = fmtCount(perMin);
                        }
                    } catch (e) {}
                }
            }

            // Eternity block
            var eternityCount = null, bestEtTime = null, thisEtTime = null,
                thisEtReal = null, bestEPmin = null;
            if (isEtUnlocked) {
                var etCount = Currency.eternities.value;
                eternityCount = fmtCount(etCount) + " " + plural("Eternity", etCount.floor ? etCount.floor() : Math.floor(Number(etCount)));
                var beTime = (bestEt.time !== undefined) ? bestEt.time : 1e15;
                if (beTime < 999999999999) bestEtTime = fmtShort(beTime);
                thisEtTime = fmtShort(records.thisEternity && records.thisEternity.time);
                try { bestEPmin = format(bestEt.bestEPminReality, 2, 2); } catch (e) {}
            }

            // Reality block
            var realityCount = null, bestReTime = null, bestReReal = null,
                thisReTime = null, thisReReal = null, totalTimePlayedGame = null,
                bestRMmin = null, bestRarity = null;
            if (isReUnlocked) {
                // Uncountability (Glyph Alchemy resource) adds fractional
                // amounts per tick. Mirror the Decimal-or-Number defensive
                // pattern the Infinity/Eternity siblings use a few lines up
                // — bare `Math.floor(value)` was fine pre-Uncountability
                // (player.realities was always an integer) but post-unlock
                // any helper that mis-typecasts the fractional value can
                // collapse to 0.
                var reVal = Currency.realities.value;
                var reFloored = (reVal && typeof reVal.floor === "function")
                    ? reVal.floor()
                    : Math.floor(Number(reVal) || 0);
                realityCount = String(reFloored);
                bestReTime = fmtShort(bestRe.time);
                bestReReal = fmtShort(bestRe.realTime);
                thisReTime = fmtShort(records.thisReality && records.thisReality.time);
                thisReReal = fmtShort(records.thisReality && records.thisReality.realTime);
                totalTimePlayedGame = fmtShort(records.totalTimePlayed);
                // Also fill in the post-Reality real-time fields for Infinity/Eternity
                thisInfReal = fmtShort(records.thisInfinity && records.thisInfinity.realTime);
                thisEtReal  = fmtShort(records.thisEternity && records.thisEternity.realTime);
                try { bestRMmin = format(bestRe.RMmin, 2, 2); } catch (e) {}
                try {
                    var rar = Math.max(strengthToRarity(bestRe.glyphStrength), 0);
                    bestRarity = formatRarity(rar);
                } catch (e) {}
            }

            return JSON.stringify({
                totalAntimatter: fmtDecimal(totalAM, 2, 1),
                realTimePlayed: fmtFull(realTimePlayed),
                saveCreatedTime: saveCreatedTime,
                saveAge: fmtFull(saveAgeMs),
                matterScale: matterScale,
                totalNews: totalNews,
                uniqueNews: uniqueNews,
                secretAchievementCount: secretCount,
                paperclips: paperclips,
                fullGameCompletions: fullGameCompletions,
                fullTimePlayed: fullGameCompletions > 0 ? fmtFull(fullTimePlayedMs) : null,
                isDoomed: isDoomed,
                realTimeDoomed: isDoomed ? fmtShort(realTimeDoomedMs) : null,
                infinityUnlocked: isInfUnlocked,
                infinityCount: infinityCount,
                bankedInfinities: bankedInfinities,
                bestInfinityTime: bestInfTime,
                thisInfinityTime: thisInfTime,
                thisInfinityRealTime: thisInfReal,
                bestIPPerMin: bestIPmin,
                projectedBankedOnEternity: projectedBanked,
                projectedBankedRatePerMin: projectedBankedRate,
                eternityUnlocked: isEtUnlocked,
                eternityCount: eternityCount,
                bestEternityTime: bestEtTime,
                thisEternityTime: thisEtTime,
                thisEternityRealTime: thisEtReal,
                bestEPPerMin: bestEPmin,
                realityUnlocked: isReUnlocked,
                realityCount: realityCount,
                bestRealityTime: bestReTime,
                bestRealityRealTime: bestReReal,
                thisRealityTime: thisReTime,
                thisRealityRealTime: thisReReal,
                totalTimePlayedGameTime: totalTimePlayedGame,
                bestRMPerMin: bestRMmin,
                bestGlyphRarity: bestRarity
            });
        } catch (e) {
            try { _nativeLog && _nativeLog("[stats] _nativeStatisticsGeneral failed: " + e); } catch (_e) {}
            return JSON.stringify({ totalAntimatter: "0", realTimePlayed: "0 seconds",
                saveCreatedTime: Date.now(), saveAge: "0 seconds",
                matterScale: ["There is no antimatter yet."],
                totalNews: 0, uniqueNews: 0, secretAchievementCount: 0,
                paperclips: 0, fullGameCompletions: 0, fullTimePlayed: null,
                isDoomed: false, realTimeDoomed: null,
                infinityUnlocked: false, eternityUnlocked: false, realityUnlocked: false });
        }
    };

    // Lightweight per-tick flag block for subtab visibility — populated into
    // the @Observable engine flags so Subtab.isAvailable() doesn't re-eval
    // pollStatistics' big payload just to gate the sidebar.
    globalThis._nativeStatisticsVisibilityFlags = function () {
        try {
            var prog = (typeof PlayerProgress !== "undefined" && PlayerProgress.current) || {};
            var hasInf = !!prog.isInfinityUnlocked;
            var hasReal = !!prog.isRealityUnlocked;
            var speedrunActive = safeBool(function () { return player.speedrun.isActive; });
            var hasPrevRuns = safeBool(function () {
                return player.speedrun && player.speedrun.previousRuns
                    && Object.keys(player.speedrun.previousRuns).length > 0;
            });
            return JSON.stringify({
                multiplierBreakdown: hasInf,
                glyphSetRecords: hasReal,
                speedrunMilestones: speedrunActive,
                speedrunRecords: hasPrevRuns
            });
        } catch (e) {
            return JSON.stringify({
                multiplierBreakdown: false, glyphSetRecords: false,
                speedrunMilestones: false, speedrunRecords: false
            });
        }
    };
})();
