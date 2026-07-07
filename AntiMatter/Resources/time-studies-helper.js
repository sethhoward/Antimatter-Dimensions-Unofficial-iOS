// time-studies-helper.js — cached + event-invalidated `_nativeTimeStudiesState`.
//
// Replaces ~380 evaluateScript calls per tick (76 studies × ~5 per-study
// JS bridge crossings) with one cached call. Time Profiler trace
// `timestudies.trace` showed `pollTimeStudies` at 3.55s/22s inclusive,
// with `readStudyText` (2.44s) + `extractNormalizedString` (1.36s, NSRegex
// whitespace collapse) dominating. Moving description resolution +
// normalisation to JS-side once-per-invalidation eliminates both costs.
//
// Strategy: per-study description (the expensive part — function call into
// the bundle + whitespace collapse) is computed once and cached on
// `globalThis._nativeTimeStudiesCache.descByKey`. Each call rebuilds the
// volatile fields (isBought / canBeBought / isAffordable / effectText / EC
// completions+running / Reality + Dilation requirement text) and emits the
// full JSON array.
//
// Invalidation triggers (subscribe to whichever GAME_EVENTs exist):
//   - TIME_STUDY_BOUGHT     — triads' isUnlocked + some descriptions flip
//   - ACHIEVEMENT_UNLOCKED  — TS133 + similar branch on Achievement(N).isUnlocked
//   - PERK_BOUGHT           — Reality requirement text drops "13 rows of
//                             Achievements" when first perk bought; some
//                             study descriptions also branch
//   - REALITY_RESET_AFTER   — wipes purchases
//   - ETERNITY_RESET_AFTER  — wipes purchases
//   - GAME_LOAD             — fresh save
//   - RA_UNLOCK_PURCHASED   — Triad (301..304) `isUnlocked` flips
//
// Safety fallback: if EventHub binding fails, descByKey stays nullable
// and `buildState()` rebuilds the cache every call — byte-identical to
// the pre-cache path.
//
// DEBUG validation: when `globalThis._nativeTimeStudiesValidateEvery` is
// set (e.g. 30 for once-per-second at 30Hz polling), every Nth call
// rebuilds descByKey fresh and logs `_nativeLog` on drift. Off in Release.
//
// Lifecycle: injected from `GameEngine.setupTimeStudiesHelper()`. Mirrors
// perks-helper.js's 5-site re-injection pattern. The cache object lives
// on globalThis so old listeners attached by prior injections keep
// invalidating correctly.

(function () {
    "use strict";

    if (!globalThis._nativeTimeStudiesCache) {
        globalThis._nativeTimeStudiesCache = {
            descByKey: null,
            callCount: 0
        };
    }
    var cache = globalThis._nativeTimeStudiesCache;

    function invalidate() { cache.descByKey = null; }

    try {
        if (typeof EventHub !== "undefined" && EventHub.logic && EventHub.logic.on &&
            typeof GAME_EVENT !== "undefined") {
            var maybeBind = function (evt) {
                if (evt !== undefined) EventHub.logic.on(evt, invalidate);
            };
            maybeBind(GAME_EVENT.TIME_STUDY_BOUGHT);
            maybeBind(GAME_EVENT.ACHIEVEMENT_UNLOCKED);
            maybeBind(GAME_EVENT.PERK_BOUGHT);
            maybeBind(GAME_EVENT.REALITY_RESET_AFTER);
            maybeBind(GAME_EVENT.ETERNITY_RESET_AFTER);
            maybeBind(GAME_EVENT.GAME_LOAD);
            maybeBind(GAME_EVENT.RA_UNLOCK_PURCHASED);
            // Bust the cache right now — state may have changed since the
            // last injection (slot switch, save import, etc.).
            invalidate();
        }
    } catch (e) {
        // Leave descByKey nullable — helper rebuilds every call.
    }

    // Mirror Swift's `GameEngine.normalStudyIDs` (GameEngine.swift). If you
    // touch one list, touch the other.
    var NORMAL_IDS = [
        11, 21, 22, 31, 32, 33, 41, 42, 51, 61, 62,
        71, 72, 73, 81, 82, 83, 91, 92, 93, 101, 102, 103,
        111, 121, 122, 123, 131, 132, 133, 141, 142, 143, 151,
        161, 162, 171, 181,
        191, 192, 193, 201, 211, 212, 213, 214,
        221, 222, 223, 224, 225, 226, 227, 228,
        231, 232, 233, 234,
        301, 302, 303, 304
    ];

    // Studies whose `description()` inlines a live state read (e.g. TS224
    // bakes `DimBoost.totalBoosts / 2000` into the desc string). For these
    // IDs, bypass the description cache and re-resolve every call. Keep
    // this list minimal — every entry pays the per-tick resolveDesc cost.
    // Audit: as of 2026-05 only TS224 has this pattern across all
    // src/core/secret-formula/eternity/time-studies/*.js files (method-form
    // `description() { ... }` rather than arrow-form).
    var LIVE_DESC_IDS = { 224: true };

    function norm(s) {
        if (s === undefined || s === null) return "";
        return String(s).replace(/\s+/g, " ").trim();
    }

    function resolveDesc(s) {
        if (!s) return "";
        try {
            var c = s.config;
            if (!c) return "";
            var d = c.description;
            if (typeof d === "function") d = d();
            return norm(d);
        } catch (e) { return ""; }
    }

    function ecDesc(s) {
        var d = resolveDesc(s);
        if (d) return d;
        // EC studies fall back to the challenge's own config.description
        // (mirrors `readStudyText` in GameEngine.swift).
        try {
            var c = s && s.challenge && s.challenge.config;
            if (c && c.description) {
                var d2 = typeof c.description === "function" ? c.description() : c.description;
                return norm(d2);
            }
        } catch (e) {}
        return "";
    }

    function buildDescCache() {
        var byKey = {};
        for (var i = 0; i < NORMAL_IDS.length; i++) {
            var id = NORMAL_IDS[i];
            try { byKey["n" + id] = resolveDesc(TimeStudy(id)); }
            catch (e) { byKey["n" + id] = ""; }
        }
        for (var n = 1; n <= 12; n++) {
            try { byKey["e" + n] = ecDesc(TimeStudy.eternityChallenge(n)); }
            catch (e) { byKey["e" + n] = ""; }
        }
        try { byKey["dil"] = resolveDesc(TimeStudy.dilation); } catch (e) { byKey["dil"] = ""; }
        for (var t = 5; t <= 8; t++) {
            try { byKey["td" + t] = resolveDesc(TimeStudy.timeDimension(t)); }
            catch (e) { byKey["td" + t] = ""; }
        }
        try { byKey["real"] = resolveDesc(TimeStudy.reality); } catch (e) { byKey["real"] = ""; }
        return byKey;
    }

    function effectText(s) {
        if (!s) return "";
        try {
            var c = s.config;
            if (!c || typeof c.effect !== "function" || typeof c.formatEffect !== "function") return "";
            var v = c.effect();
            var out = c.formatEffect(v);
            return (out === undefined || out === null) ? "" : String(out);
        } catch (e) { return ""; }
    }

    // Mirrors the inline EC requirement-text eval that was inside
    // GameEngine.pollTimeStudies. cfg.current() can throw at certain
    // game stages (post-Armageddon, mid-strike resets) — wrap in try/catch
    // to keep the global JS exception handler quiet.
    function ecRequirementText(n) {
        try {
            var study = TimeStudy.eternityChallenge(n);
            if (Perk.studyECRequirement.isBought || study.wasRequirementPreviouslyMet) return "";
            var cfg = study.config.secondary;
            if (cfg.path) return "Use only the " + cfg.path + " path";
            if (n > 10) return "";
            var comps = EternityChallenge(n).completions;
            var total = typeof cfg.required === "function" ? cfg.required(comps) : cfg.required;
            var cur = typeof cfg.current === "function" ? cfg.current() : cfg.current;
            if (cur === undefined || cur === null) return "";
            if (typeof cur !== "number") cur = cur.min(total);
            else cur = Math.min(cur, typeof total === "number" ? total : total.toNumber());
            return cfg.formatValue(cur) + "/" + cfg.formatValue(total) + " " + cfg.resource;
        } catch (e) { return ""; }
    }

    function realityRequirementText() {
        try {
            if (TimeStudy.reality.isBought) return "";
            var achRows = (Perk.firstPerk && Perk.firstPerk.isBought) ? "" : " and 13 rows of Achievements";
            return "Requirement: 1e4000 Eternity Points" + achRows;
        } catch (e) { return ""; }
    }

    // Mirrors DilationTimeStudy.vue's `requirement` computed (id === 1) +
    // `showRequirement` gate. iOS previously emitted no requirement text for the
    // dilation node, so a player gated only by the lifetime-max-TT threshold
    // (Currency.timeTheorems.max >= 12900) saw an unexplained greyed-out card.
    // The string renders single-line (no template literal) to match the other
    // requirement-text helpers — no normText needed.
    function dilationRequirementText() {
        try {
            var d = TimeStudy.dilation;
            if (!d || d.isBought) return "";
            if (Perk.bypassECDilation && Perk.bypassECDilation.canBeApplied) return "";
            return "Requirement: " + formatInt(5) + " EC11 and EC12 completions and " +
                formatInt(Currency.timeTheorems.max) + "/" + formatInt(d.totalTimeTheoremRequirement) +
                " total Time Theorems";
        } catch (e) { return ""; }
    }

    function buildState() {
        if (!cache.descByKey) cache.descByKey = buildDescCache();
        var desc = cache.descByKey;
        var out = [];

        // Normal studies
        for (var i = 0; i < NORMAL_IDS.length; i++) {
            var id = NORMAL_IDS[i];
            var s;
            try { s = TimeStudy(id); } catch (e) { continue; }
            if (!s) continue;
            var isTriad = id >= 301 && id <= 304;
            // Triads gate individually on `Ra.unlocks.unlockHardV` tiers —
            // skip locked ones so the tree row collapses (matches the
            // Swift loop's `continue` for !isUnlocked triads).
            if (isTriad && !s.isUnlocked) continue;
            // Read the STCost getter (not config.STCost) so the V Ra-unlock
            // milestone discount (-2 ST per triad) applies.
            var cost = isTriad ? ((typeof s.STCost === "number") ? s.STCost : 12)
                               : ((s.cost || 0) | 0);
            var descText = LIVE_DESC_IDS[id] ? resolveDesc(s) : (desc["n" + id] || "");
            out.push({
                id: id,
                bought: !!s.isBought,
                canBuy: !!s.canBeBought,
                afford: !!s.isAffordable,
                cost: cost | 0,
                desc: descText,
                effect: effectText(s)
            });
        }

        // EC studies (-1..-12)
        for (var n = 1; n <= 12; n++) {
            var ecs;
            try { ecs = TimeStudy.eternityChallenge(n); } catch (e) { continue; }
            if (!ecs) continue;
            var comps = 0, isRun = false, isUnl = false;
            try {
                var ecRef = EternityChallenge(n);
                if (ecRef) {
                    comps = (ecRef.completions || 0) | 0;
                    isUnl = !!ecRef.isUnlocked;
                }
                isRun = !!(EternityChallenge.current && EternityChallenge.current.id === n);
            } catch (e) {}
            out.push({
                id: -n,
                bought: !!ecs.isBought,
                canBuy: !!ecs.canBeBought,
                afford: !!ecs.isAffordable,
                cost: (ecs.cost || 0) | 0,
                desc: desc["e" + n] || "",
                effect: effectText(ecs),
                ecCompletions: comps,
                req: ecRequirementText(n),
                ecRunning: isRun,
                ecUnlocked: isUnl
            });
        }

        // Dilation (-100)
        try {
            var d = TimeStudy.dilation;
            if (d) {
                out.push({
                    id: -100,
                    bought: !!d.isBought,
                    canBuy: !!d.canBeBought,
                    afford: !!d.isAffordable,
                    cost: (d.cost || 0) | 0,
                    desc: desc["dil"] || "",
                    effect: effectText(d),
                    req: dilationRequirementText()
                });
            }
        } catch (e) {}

        // TD studies (-105..-108 for TD5..TD8)
        for (var t = 5; t <= 8; t++) {
            var td;
            try { td = TimeStudy.timeDimension(t); } catch (e) { continue; }
            if (!td) continue;
            out.push({
                id: -(100 + t),
                bought: !!td.isBought,
                canBuy: !!td.canBeBought,
                afford: !!td.isAffordable,
                cost: (td.cost || 0) | 0,
                desc: desc["td" + t] || "",
                effect: effectText(td)
            });
        }

        // Reality (-200)
        try {
            var r = TimeStudy.reality;
            if (r) {
                out.push({
                    id: -200,
                    bought: !!r.isBought,
                    canBuy: !!r.canBeBought,
                    afford: !!r.isAffordable,
                    cost: (r.cost || 0) | 0,
                    desc: desc["real"] || "",
                    effect: effectText(r),
                    req: realityRequirementText()
                });
            }
        } catch (e) {}

        return out;
    }

    globalThis._nativeTimeStudiesState = function () {
        var data = buildState();

        var validateEvery = globalThis._nativeTimeStudiesValidateEvery | 0;
        if (validateEvery > 0) {
            cache.callCount = (cache.callCount + 1) | 0;
            if ((cache.callCount % validateEvery) === 0 && cache.descByKey) {
                var fresh = buildDescCache();
                var cachedKeys = Object.keys(cache.descByKey);
                var drifted = [];
                for (var k = 0; k < cachedKeys.length; k++) {
                    var key = cachedKeys[k];
                    if (cache.descByKey[key] !== fresh[key]) {
                        drifted.push(key + ": '" + (cache.descByKey[key] || "").slice(0, 40) +
                                     "…' → '" + (fresh[key] || "").slice(0, 40) + "…'");
                    }
                }
                if (drifted.length > 0) {
                    // Self-healing diagnostic — cache adopts fresh below, so
                    // user-visible UI is at most one validate-window stale.
                    // Worth investigating when a new drift key appears (add a
                    // GAME_EVENT listener to invalidate sooner), but not a
                    // correctness issue.
                    try {
                        if (typeof _nativeLog !== "undefined") {
                            _nativeLog("[ts-cache] healed " + drifted.length +
                                       " desc key(s) @call " + cache.callCount + ":");
                            for (var di = 0; di < drifted.length; di++) {
                                _nativeLog("    " + drifted[di]);
                            }
                        }
                    } catch (e) {}
                    cache.descByKey = fresh;
                }
            }
        }

        return JSON.stringify(data);
    };

    globalThis._nativeTimeStudiesInvalidate = invalidate;
})();
