// celestial-helpers.js
//
// JS-side support for the iOS Celestials tab. Injected by
// GameEngine+Celestials.setupCelestialHelpers(). Provides three bulk-JSON
// read helpers and action wrappers that Swift calls via evaluateScript.
//
// All functions are guarded against missing symbols so they safely degrade
// on older saves or before cacheJSRefs() has run.

(function () {
    "use strict";

    // ---- Navigation ----------------------------------------------------

    // Node keys we render on iOS. Each entry: [id, completionFn].
    // completionFn returns a number in [0, 1]. pLog10 safe-clamps are used
    // for pour-RM thresholds so NaN/Infinity can't leak to Swift.
    function safeRatio(currentLog, goalLog) {
        if (!isFinite(currentLog) || !isFinite(goalLog) || goalLog <= 0) return 0;
        return Math.min(Math.max(currentLog / goalLog, 0), 1);
    }

    // Safe accessors — return false/0 if the referenced globals don't exist
    // (e.g. during early startup or for celestials whose unlock chain hasn't
    // started). Mirrors the per-node `visible:` conditions from
    // src/core/secret-formula/celestials/navigation.js.
    function has(obj) { return typeof obj !== "undefined" && obj !== null; }

    // Web descriptions / rewards are written as multi-line JS template literals
    // (e.g. `\`Reduce...by ${formatInt(2)}.\n          Unlock Ra...\``). The
    // template indentation leaks into the serialized string and shows up as a
    // line break followed by a wall of whitespace on iOS. Always run any text
    // pulled from a GameDatabase config through this helper before stringifying
    // it into the state JSON.
    //
    // Rules:
    //   • If the value is a function, call it (with an empty-args catch).
    //   • Collapse runs of whitespace (incl. tabs + newlines) into a single space.
    //   • Trim leading/trailing whitespace.
    function normText(v) {
        if (v === null || v === undefined) return "";
        var raw;
        if (typeof v === "function") {
            try { raw = v(); } catch (e) { return ""; }
        } else {
            raw = v;
        }
        if (raw === null || raw === undefined) return "";
        return String(raw).replace(/\s+/g, " ").trim();
    }

    // Like normText, but PRESERVES leading/trailing/internal ASCII space runs.
    // Pelle's strike + rift descriptions go through `wordShift.wordCycle()`
    // which buffers each cycled word with symmetric ASCII spaces so its
    // visible character count stays constant ("prevents the ui from
    // twitching", per word-shift.js). normText collapses + trims those
    // buffers and the iOS Text reflows every 30Hz poll. Collapse only
    // newlines/tabs (multi-line template indentation) so the buffer survives.
    function normPelleText(v) {
        if (v === null || v === undefined) return "";
        var raw;
        if (typeof v === "function") {
            try { raw = v(); } catch (e) { return ""; }
        } else {
            raw = v;
        }
        if (raw === null || raw === undefined) return "";
        return String(raw).replace(/[\t\n\r]+/g, " ");
    }

    // Mirror of `wordShift.wordCycle` (`src/core/word-shift.js`). The bundled
    // `wordShift` module is private to webpack output and not exposed on
    // `globalThis`, so we re-implement the 30-line cycle here for use in the
    // Pelle / nav state polls. The output preserves padding to a fixed
    // visual width (callers render with `.system(design: .monospaced)` so
    // the iOS Text doesn't reflow each tick).
    function pwcPredictableRandom(x) {
        var start = Math.pow(x % 97, 4.3) * 232344573;
        var a = 15485863, b = 521791;
        start = (start * a) % b;
        var iter = (x * x) % 90 + 90;
        for (var i = 0; i < iter; i++) start = (start * a) % b;
        return start / b;
    }
    function pwcRandomSymbol() {
        return String.fromCharCode(Math.floor(Math.random() * 50) + 192);
    }
    function pwcRandomCrossWords(str, frac) {
        if (frac === undefined) frac = 0.7;
        if (frac <= 0) return str;
        var x = String(str).split("");
        var n = x.length * frac;
        for (var i = 0; i < n; i++) {
            var idx = Math.floor(pwcPredictableRandom(Math.floor(Date.now() / 500) % 964372 + 1.618 * i) * x.length);
            x[idx] = pwcRandomSymbol();
        }
        return x.join("");
    }
    function pwcBlendWords(first, second, param) {
        if (param <= 0) return first;
        if (param >= 1) return second;
        return first.substring(0, first.length * (1 - param))
             + second.substring(second.length * (1 - param), second.length);
    }
    function pelleWordCycle(list, noBuffer) {
        if (!list) return "";
        if (!Array.isArray(list)) return String(list);
        var len = list.length;
        if (len === 0) return "";
        if (len === 1) return String(list[0]);
        var tick = Math.floor(Date.now() / 250) % (len * 5);
        var mod5 = ((Date.now() / 250) % (len * 5)) % 5;
        var largeTick = Math.floor(tick / 5);
        var v = list[largeTick];
        if (mod5 < 0.6) {
            v = pwcBlendWords(list[(largeTick + len - 1) % len], list[largeTick], (mod5 + 0.6) / 1.2);
        } else if (mod5 > 4.4) {
            v = pwcBlendWords(list[largeTick], list[(largeTick + 1) % len], (mod5 - 4.4) / 1.2);
        }
        v = pwcRandomCrossWords(v, 0.1 * Math.pow(mod5 - 2.5, 4) - 0.6);
        if (noBuffer) return v;
        var maxLen = 0;
        for (var i = 0; i < len; i++) {
            var l = String(list[i]).length;
            if (l > maxLen) maxLen = l;
        }
        var bufferSpace = (maxLen - v.length) / 2;
        var pad = function (n) { var s = ""; for (var k = 0; k < n; k++) s += " "; return s; };
        return pad(Math.ceil(bufferSpace)) + v + pad(Math.floor(bufferSpace));
    }

    function vis_teresaEffarigUnlocked() {
        return has(TeresaUnlocks) && TeresaUnlocks.effarig && TeresaUnlocks.effarig.canBeApplied;
    }
    function vis_effarigRunUnlocked() {
        return has(EffarigUnlock) && EffarigUnlock.run && EffarigUnlock.run.isUnlocked;
    }
    function vis_effarigEternityUnlocked() {
        return has(EffarigUnlock) && EffarigUnlock.eternity && EffarigUnlock.eternity.isUnlocked;
    }
    function vis_effarigRealityCompleted() {
        return has(EffarigUnlock) && EffarigUnlock.reality && EffarigUnlock.reality.isUnlocked;
    }
    function vis_raUnlocked() {
        return has(VUnlocks) && VUnlocks.raUnlock && VUnlocks.raUnlock.isUnlocked;
    }
    function vis_raVUnlocked() {
        // Lai'tela's node appears once Ra grants the V-pet unlock (web:
        // navigation.js:1425 → `Ra.unlocks.vUnlock.isUnlocked`).
        return has(Ra) && Ra.unlocks && Ra.unlocks.vUnlock && Ra.unlocks.vUnlock.isUnlocked;
    }
    function vis_pelleUnlockable() {
        // Pelle's node appears once Lai'tela's destabilization tier exceeds 4
        // (web: navigation.js:1806 → `Laitela.difficultyTier > 4`).
        return has(Laitela) && (Laitela.difficultyTier || 0) > 4;
    }

    var navNodes = [
        {
            id: "teresa-reality-unlock",
            visible: function () { return true; },
            complete: function () {
                if (!has(TeresaUnlocks)) return 0;
                if (TeresaUnlocks.run && TeresaUnlocks.run.canBeApplied) return 1;
                var pour = has(Teresa) ? Teresa.pouredAmount : 0;
                var price = TeresaUnlocks.run.price;
                return safeRatio(Decimal.pLog10(pour), Math.log10(price));
            },
            legend: function (c) {
                if (c >= 1) return "";
                if (!has(Teresa) || !has(TeresaUnlocks)) return "Teresa";
                return "Pour " + format(Teresa.pouredAmount, 2) + " / " + format(TeresaUnlocks.run.price, 2) + " RM";
            }
        },
        {
            id: "teresa-pp-shop",
            visible: function () { return true; },
            complete: function () {
                if (!has(TeresaUnlocks) || !TeresaUnlocks.shop) return 0;
                if (TeresaUnlocks.shop.canBeApplied) return 1;
                var pour = has(Teresa) ? Teresa.pouredAmount : 0;
                return safeRatio(Decimal.pLog10(pour), Math.log10(TeresaUnlocks.shop.price));
            },
            legend: function (c) {
                if (c >= 1) return "Teresa's Perk Point Shop";
                if (!has(Teresa) || !has(TeresaUnlocks)) return "";
                return "Pour " + format(Teresa.pouredAmount, 2) + " / " + format(TeresaUnlocks.shop.price, 2) + " RM";
            }
        },
        {
            id: "effarig-shop",
            // The "pour toward Effarig" milestone is always visible once Teresa's tab is.
            visible: function () { return true; },
            complete: function () {
                if (!has(TeresaUnlocks) || !TeresaUnlocks.effarig) return 0;
                if (TeresaUnlocks.effarig.canBeApplied) return 1;
                var pour = has(Teresa) ? Teresa.pouredAmount : 0;
                return safeRatio(Decimal.pLog10(pour), Math.log10(TeresaUnlocks.effarig.price));
            },
            legend: function (c) {
                if (c >= 1) return "Effarig";
                return "Pour RM to unlock Effarig";
            }
        },
        {
            // Small ring between the shop and the concentric run rings —
            // "Unlock Effarig's Reality" (web navigation.js:357).
            id: "effarig-reality-unlock",
            visible: vis_teresaEffarigUnlocked,
            complete: function () {
                if (!has(EffarigUnlock) || !EffarigUnlock.run) return 0;
                if (EffarigUnlock.run.isUnlocked) return 1;
                // Clamp at 99.9% so a player who's saved up the cost but not
                // yet bought it still sees the ring as "almost done".
                var rs = (typeof Currency !== "undefined" && Currency.relicShards)
                    ? Currency.relicShards.value : 0;
                var cost = EffarigUnlock.run.cost;
                return Math.min(0.999, safeRatio(Decimal.pLog10(rs), Math.log10(cost)));
            },
            legend: function (c) {
                if (c >= 1) return "Unlock Effarig's Reality";
                if (!has(EffarigUnlock) || !EffarigUnlock.run) return "Unlock Effarig's Reality";
                var rs = Currency.relicShards.value;
                return "Reach " + format(rs, 2) + " / " + format(EffarigUnlock.run.cost, 2) + " Relic Shards";
            }
        },
        {
            // Outer concentric ring — Effarig's Infinity stage (web navigation.js:394).
            id: "effarig-infinity",
            visible: vis_effarigRunUnlocked,
            complete: function () {
                if (!has(EffarigUnlock) || !EffarigUnlock.infinity) return 0;
                if (EffarigUnlock.infinity.isUnlocked) return 1;
                if (!has(Effarig) || !Effarig.isRunning) return 0;
                var am = Currency.antimatter.value;
                var goal = Decimal.NUMBER_MAX_VALUE.log10();
                return safeRatio(am.pLog10(), goal);
            },
            legend: function (c) {
                if (c >= 1) return "Effarig's Infinity";
                if (c === 0) return "Unlock Effarig's Reality";
                return "Reach Number.MAX_VALUE antimatter inside Effarig's Reality";
            }
        },
        {
            // Middle concentric ring — Effarig's Eternity stage (web navigation.js:435).
            id: "effarig-eternity",
            visible: function () {
                return has(EffarigUnlock) && EffarigUnlock.infinity && EffarigUnlock.infinity.isUnlocked;
            },
            complete: function () {
                if (!EffarigUnlock.eternity) return 0;
                if (EffarigUnlock.eternity.isUnlocked) return 1;
                if (!has(Effarig) || !Effarig.isRunning) return 0;
                var ip = Currency.infinityPoints.value;
                var goal = Decimal.NUMBER_MAX_VALUE.log10();
                return safeRatio(ip.pLog10(), goal);
            },
            legend: function (c) {
                if (c >= 1) return "Effarig's Eternity";
                return "Reach Number.MAX_VALUE Infinity Points inside Effarig's Reality";
            }
        },
        {
            // Filled centre — Effarig's Reality stage (web navigation.js:484).
            id: "effarig-reality",
            visible: function () {
                return has(EffarigUnlock) && EffarigUnlock.eternity && EffarigUnlock.eternity.isUnlocked;
            },
            complete: function () {
                if (!EffarigUnlock.reality) return 0;
                if (EffarigUnlock.reality.isUnlocked) return 1;
                if (!has(Effarig) || !Effarig.isRunning) return 0;
                var ep = Currency.eternityPoints.value;
                return safeRatio(ep.pLog10(), 4000);
            },
            legend: function (c) {
                if (c >= 1) return "Effarig's Reality";
                return "Reach 1e4000 Eternity Points inside Effarig's Reality";
            }
        },
        {
            id: "enslaved-reality",
            // Web: visible when EffarigUnlock.eternity is unlocked (navigation.js:537).
            visible: vis_effarigEternityUnlocked,
            complete: function () {
                if (typeof Enslaved !== "undefined") {
                    if (Enslaved.isCompleted) return 1;
                    if (Enslaved.isRunning) {
                        // Match web: progress toward 1e4000 EP inside the run.
                        try {
                            var ep = Currency.eternityPoints.value;
                            return safeRatio(ep.pLog10(), 4000);
                        } catch (e) {}
                    }
                }
                return vis_effarigEternityUnlocked() ? 1 : 0;
            },
            legend: function (c) {
                if (c >= 1) return "The Nameless Ones' Reality";
                return "The Nameless Ones";
            }
        },
        // "Break a chain" unlocks — glyph level 5000 + rarity 100 requirements
        // for the Nameless Ones' RUN unlock. Visible once Effarig Eternity is reached.
        {
            id: "enslaved-unlock-glyph-level",
            visible: vis_effarigEternityUnlocked,
            complete: function () {
                try {
                    var best = player.records.bestReality.glyphLevel || 0;
                    return Math.min(1, Math.max(0, best / 5000));
                } catch (e) { return 0; }
            },
            legend: function (c) {
                if (c >= 1) return "Glyph level chain has been broken";
                try {
                    var best = player.records.bestReality.glyphLevel || 0;
                    return "Break a chain (Glyph level " + formatInt(best) + " / " + formatInt(5000) + ")";
                } catch (e) { return "Break a chain"; }
            }
        },
        {
            id: "enslaved-unlock-glyph-rarity",
            visible: vis_effarigEternityUnlocked,
            complete: function () {
                try {
                    var r = strengthToRarity(player.records.bestReality.glyphStrength || 0);
                    return Math.min(1, Math.max(0, r / 100));
                } catch (e) { return 0; }
            },
            legend: function (c) {
                if (c >= 1) return "Glyph rarity chain has been broken";
                try {
                    var r = strengthToRarity(player.records.bestReality.glyphStrength || 0);
                    return "Break a chain (Glyph rarity " + formatRarity(r) + " / " + formatRarity(100) + ")";
                } catch (e) { return "Break a chain"; }
            }
        },
        {
            id: "v-unlock-achievement",
            // Web: visible when EffarigUnlock.reality is completed
            // (navigation.js:695). Achievement(151) is one of the V *unlock
            // conditions* — it can fire long before V is reachable, so it
            // must NOT gate visibility (that's a separate `complete()`
            // calculation in the upstream code).
            visible: vis_effarigRealityCompleted,
            complete: function () {
                if (!has(Achievement)) return 0;
                if (Achievement(151).isUnlocked) return 1;
                return 0;
            },
            legend: function () { return "V"; }
        },
        {
            id: "ra",
            // Web: visible when VUnlocks.raUnlock is unlocked (navigation.js:1127).
            visible: vis_raUnlocked,
            complete: function () {
                if (!has(Ra)) return 0;
                return Ra.totalPetLevel > 0 ? 1 : 0;
            },
            legend: function () { return "Ra"; }
        },
        {
            id: "laitela",
            // Matches web navigation.js:1425 — node appears once the V-pet
            // unlock is reached (Enslaved Ra pet lv 8), and fills in stages
            // as the player progresses toward the ImaginaryUpgrade(15)
            // requirement.
            visible: vis_raVUnlocked,
            complete: function () {
                if (!has(Laitela)) return 0;
                try {
                    if (DarkMatterDimension(1).unlockUpgrade.canBeBought || Laitela.isUnlocked) return 1;
                } catch (e) {}
                var imUnlocked = (typeof MachineHandler !== "undefined") && MachineHandler.isIMUnlocked;
                if (imUnlocked) {
                    try {
                        if (player.requirementChecks.reality.maxID1.neq(0)) return 0.5;
                    } catch (e) {}
                    try {
                        return 0.5 + 0.5 * Math.min(0.999, player.antimatter.exponent / 1.5e12);
                    } catch (e) { return 0.5; }
                }
                try {
                    var logRM = Currency.realityMachines.value.pLog10();
                    var capExp = MachineHandler.baseRMCap.exponent;
                    return Math.min(0.5, logRM / capExp);
                } catch (e) { return 0; }
            },
            // Multi-line legend mirroring web — Swift joins the array with
            // newlines for rendering.
            legend: function (c) {
                var realityName = "Lai'tela's Reality";
                if (c >= 1) return realityName;
                if ((typeof MachineHandler === "undefined") || !MachineHandler.isIMUnlocked) {
                    try {
                        var rm = Currency.realityMachines.value;
                        var cap = MachineHandler.baseRMCap;
                        return realityName + "\nThe limits of Reality Machines bind you\n" + format(rm) + " / " + format(cap);
                    } catch (e) { return realityName; }
                }
                try {
                    if (player.requirementChecks.reality.maxID1.neq(0)) {
                        return realityName + "\nThe Power of Infinity Dimensions\nblocks your path.";
                    }
                } catch (e) {}
                try {
                    var am = Currency.antimatter.value;
                    return realityName + "\n" + format(am) + " / " + format(Decimal.pow10(1.5e12));
                } catch (e) { return realityName; }
            }
        },
        {
            id: "pelle",
            // Web: navigation.js:1806 — `Laitela.difficultyTier > 4`.
            visible: vis_pelleUnlockable,
            // 3 stages: 0 (locked), 0.5 (Pelle unlocked but not doomed —
            // connector half-fills to show the path is reachable), 1 (doomed,
            // node fully active). The 0.5 stage matters because Pelle.isUnlocked
            // can be true for a long stretch before a player chooses to Doom —
            // the gray line was reading as "still locked" during that window.
            complete: function () {
                if (!has(Pelle)) return 0;
                if (Pelle.isDoomed) return 1;
                return Pelle.isUnlocked ? 0.5 : 0;
            },
            legend: function () { return "Pelle"; }
        }
    ];

    globalThis._nativeNavigationState = function () {
        var out = [];
        for (var i = 0; i < navNodes.length; i++) {
            var n = navNodes[i];
            var v = true;
            try { v = !!n.visible(); } catch (e) { v = false; }
            // Skip running complete/legend for invisible nodes — their formulas
            // often reference celestials that aren't unlocked yet.
            var c = 0, legend = "";
            if (v) {
                try { c = n.complete(); } catch (e) { c = 0; }
                try { legend = n.legend(c) || ""; } catch (e) { legend = ""; }
            }
            out.push({ id: n.id, complete: c, visible: v, legend: legend });
        }
        return JSON.stringify(out);
    };

    // ---- Teresa --------------------------------------------------------

    var PERK_SHOP_KEYS = ["glyphLevel", "rmMult", "bulkDilation", "autoSpeed", "musicGlyph", "fillMusicGlyph"];

    function perkShopEntry(key) {
        var u = PerkShopUpgrade[key];
        if (!u) return null;
        var cost = u.cost;
        // musicGlyph / fillMusicGlyph have no `effect` in their config — they
        // grant a glyph on purchase rather than a numeric multiplier. For
        // those we emit an empty effectText and let the UI fall back to the
        // description + cost.
        var effect = 0;
        var hasEffect = typeof u.config.effect === "function";
        if (hasEffect) {
            try { effect = u.config.effect(u.boughtAmount); }
            catch (e) { hasEffect = false; }
        }
        var formatEffect = u.config.formatEffect;
        var formatCost = u.config.formatCost;
        var capFn = u.config.cap;
        var cap = null;
        try { cap = capFn ? capFn() : null; } catch (e) { cap = null; }
        var effectText = hasEffect
            ? (formatEffect ? formatEffect(effect) : String(effect))
            : "";
        var capText = null;
        if (hasEffect && cap !== null && cap !== undefined && isFinite(cap) && cap < Number.MAX_VALUE) {
            capText = formatEffect ? formatEffect(cap) : String(cap);
        }
        return {
            id: u.id,
            key: key,
            description: normText(u.config.description),
            cost: formatCost ? formatCost(cost) : format(cost, 2),
            effectText: effectText,
            bought: u.boughtAmount,
            capText: capText,
            isCapped: !!u.isCapped,
            isAffordable: !!u.isAvailableForPurchase
        };
    }

    globalThis._nativeTeresaState = function () {
        if (typeof Teresa === "undefined" || typeof TeresaUnlocks === "undefined") {
            return JSON.stringify({ ready: false });
        }
        var unlocks = TeresaUnlocks.all.map(function (u) {
            var desc = normText(u.config.description);
            // Teresa's unlock ids are numeric per secret-formula. Try to find its key.
            var key = "";
            for (var k in GameDatabase.celestials.teresa.unlocks) {
                if (GameDatabase.celestials.teresa.unlocks[k] === u.config) { key = k; break; }
            }
            return {
                id: u.id,
                key: key,
                price: u.price,
                description: desc,
                isUnlocked: !!u.isUnlocked,
                canBeUnlocked: !!u.canBeUnlocked,
                pelleDisabled: !!(u.pelleDisabled)
            };
        });

        // Vue gates fillMusicGlyph on Ra.unlocks.perkShopIncrease.canBeApplied
        // (web TeresaTab.vue:54: `if (this.raisedPerkShop) upgrades.push(...fillMusicGlyph)`).
        // Without this filter, iOS shows the 6th row before Ra is leveled.
        var raisedPerkShop = (typeof Ra !== "undefined" && Ra.unlocks && Ra.unlocks.perkShopIncrease)
            ? !!Ra.unlocks.perkShopIncrease.canBeApplied : false;
        var perkShop = [];
        for (var i = 0; i < PERK_SHOP_KEYS.length; i++) {
            var key = PERK_SHOP_KEYS[i];
            if (key === "fillMusicGlyph" && !raisedPerkShop) continue;
            var e = perkShopEntry(key);
            if (e) perkShop.push(e);
        }

        var rmValue = Currency.realityMachines.value;
        var ppValue = Currency.perkPoints.value;

        var runDescription = "";
        try {
            var descs = GameDatabase && GameDatabase.celestials && GameDatabase.celestials.descriptions;
            if (descs && descs[0] && typeof descs[0].effects === "function") {
                runDescription = descs[0].effects()
                    .replace(/\s+/g, " ")
                    .trim();
            }
        } catch (e) { runDescription = ""; }

        return JSON.stringify({
            ready: true,
            runDescription: runDescription,
            pouredAmount: format(Teresa.pouredAmount, 2, 2),
            pouredAmountRaw: Teresa.pouredAmount,
            pouredAmountCap: format(Teresa.pouredAmountCap, 2, 2),
            pouredAmountCapRaw: Teresa.pouredAmountCap,
            fill: Teresa.fill,
            possibleFill: Teresa.possibleFill,
            rmMultiplier: formatX(Teresa.rmMultiplier, 2, 2),
            realityMachines: format(rmValue, 2, 2),
            perkPoints: ppValue,
            hasRun: TeresaUnlocks.run.isUnlocked,
            hasEPGen: TeresaUnlocks.epGen.isUnlocked,
            hasShop: TeresaUnlocks.shop.isUnlocked,
            raisedPerkShop: (typeof Ra !== "undefined" && Ra.unlocks && Ra.unlocks.perkShopIncrease)
                ? !!Ra.unlocks.perkShopIncrease.canBeApplied : false,
            isRunning: !!Teresa.isRunning,
            runCompleted: !!Teresa.runCompleted,
            bestRunAM: format(player.celestials.teresa.bestRunAM, 2, 2),
            lastRepeatedMachines: (player.celestials.teresa.lastRepeatedMachines && player.celestials.teresa.lastRepeatedMachines.gt
                ? format(player.celestials.teresa.lastRepeatedMachines, 2, 2) : ""),
            // Matches TeresaTab.vue `lastMachinesString`: label flips to Imaginary Machines
            // once the value crosses 1e10000 (divided out to keep a readable magnitude).
            lastRepeatedMachinesLabel: (function() {
                var lm = player.celestials.teresa.lastRepeatedMachines;
                if (!lm || typeof lm.gt !== "function" || !lm.gt(0)) return "";
                try {
                    var threshold = Decimal.pow10(10000);
                    return lm.lt(threshold)
                        ? quantify("Reality Machine", lm, 2)
                        : quantify("Imaginary Machine", lm.dividedBy(threshold), 2);
                } catch (e) { return ""; }
            })(),
            runReward: formatX(Teresa.runRewardMultiplier, 2, 2),
            unlocks: unlocks,
            perkShop: perkShop,
            bestAMSet: (function() {
                var raw = player.celestials.teresa.bestAMSet;
                if (!raw || !raw.length) return [];
                var standardOrder = ["reality", "effarig", "power", "infinity", "replication", "time", "dilation", "cursed", "companion"];
                var sorted = raw.slice().sort(function(a, b) { return standardOrder.indexOf(a.type) - standardOrder.indexOf(b.type); });
                raw = sorted;
                var generatedTypes = ["power", "infinity", "replication", "time", "dilation", "effarig"];
                return raw.map(function(g) {
                    var typeColor = "";
                    try { typeColor = GlyphAppearanceHandler.getBorderColor(g.type); } catch(e) {}
                    var rarityColor = "";
                    var rarityPct = "";
                    var rarityPctNum = 0;
                    var rarityName = "";
                    try {
                        var rarity = strengthToRarity(g.strength);
                        rarityPctNum = +rarity || 0;
                        rarityPct = formatRarity(rarity);
                        var rarityObj = getRarity(g.strength);
                        if (rarityObj) {
                            rarityColor = rarityObj.darkColor || rarityObj.color || "";
                            rarityName = rarityObj.name || "";
                        }
                    } catch(e) {}
                    var effectBits = g.effects || 0;
                    var effectCount = 0;
                    var tmp = effectBits;
                    while (tmp) { effectCount += tmp & 1; tmp >>>= 1; }
                    var effectDescs = [];
                    try {
                        var isGenerated = generatedTypes.indexOf(g.type) >= 0;
                        var vals = getGlyphEffectValuesFromBitmask(effectBits, g.level, g.strength, g.type);
                        var db = GlyphEffects;
                        for (var i = 0; i < vals.length; i++) {
                            var e = vals[i];
                            var entry = db[e.id];
                            if (!entry || (!!entry.isGenerated) !== isGenerated) continue;
                            var rawDesc = entry.shortDesc;
                            if (!rawDesc) continue;
                            var singleVal = entry.formatSingleEffect
                                ? entry.formatSingleEffect(e.value)
                                : (entry.formatEffect ? entry.formatEffect(e.value) : String(e.value));
                            var altVal = entry.conversion
                                ? (entry.formatSecondaryEffect ? entry.formatSecondaryEffect(entry.conversion(e.value)) : "")
                                : "";
                            var text = rawDesc.replace("{value}", singleVal).replace("{value2}", altVal);
                            effectDescs.push(text);
                        }
                    } catch(e) {}
                    return {
                        type: g.type || "",
                        symbol: g.symbol || CosmeticGlyphTypes[g.type].currentSymbol.symbol || "?",
                        level: g.level || 0,
                        effectCount: effectCount,
                        typeColor: typeColor,
                        rarityColor: rarityColor,
                        rarityPercent: rarityPct,
                        rarityPercentNum: rarityPctNum,
                        rarityName: rarityName,
                        effects: effectDescs
                    };
                });
            })()
        });
    };

    globalThis._nativeTeresaPour = function (diffSec) {
        if (typeof Teresa === "undefined") return;
        Teresa.pourRM(diffSec);
    };

    globalThis._nativeTeresaStopPour = function () {
        if (typeof Teresa !== "undefined") Teresa.timePoured = 0;
    };

    globalThis._nativeBuyPerkShop = function (id) {
        var entry = Object.values(PerkShopUpgrade).find(function (u) { return u.id === id; });
        if (entry && entry.isAvailableForPurchase) entry.purchase();
    };

    globalThis._nativeStartTeresaRun = function () {
        if (typeof Teresa !== "undefined" && TeresaUnlocks.run.isUnlocked) {
            beginProcessReality(getRealityProps(true));
            Teresa.initializeRun();
        }
    };

    // ---- Quote modal ---------------------------------------------------
    // ui.view.quotes is the canonical JS state:
    //   queue:    pending quotes (CelQuotes instances)
    //   current:  active quote object being displayed
    //   history:  array of all CelQuotes for a celestial (set when user opens history)

    function serializeQuote(q) {
        if (!q) return null;
        var lines = [];
        for (var i = 0; i < q.totalLines; i++) {
            var line = q.line(i);
            var cels = line.celestials;
            var primaryKey = (cels && cels[0] && cels[0][0]) || q.celestial;
            lines.push({
                text: line.line,
                celestialKey: primaryKey,
                showCelestialName: !!line.showCelestialName
            });
        }
        var cel = Celestials[q.celestial] || {};
        return {
            celestialKey: q.celestial,
            celestialDisplayName: cel.displayName || q.celestial,
            celestialSymbol: cel.symbol || "",
            quoteId: q.config ? q.config.id : 0,
            lines: lines
        };
    }

    globalThis._nativeQuoteState = function () {
        if (typeof ui === "undefined" || !ui.view || !ui.view.quotes) {
            return JSON.stringify({ current: null, queueSize: 0 });
        }
        var current = serializeQuote(ui.view.quotes.current);
        var queueSize = (ui.view.quotes.queue || []).length;
        return JSON.stringify({ current: current, queueSize: queueSize });
    };

    // Lightweight fingerprint used by pollQuoteQueue() to short-circuit the
    // expensive serialize + JSON.stringify path when nothing relevant changed.
    // Format: "<celestialKey>/<quoteId>/<queueSize>" or "/0/<queueSize>" when
    // no current quote. Returned as a plain string so Swift can read it via
    // JSValue.toString() without a JSON parse.
    globalThis._nativeQuoteKey = function () {
        if (typeof ui === "undefined" || !ui.view || !ui.view.quotes) {
            return "/0/0";
        }
        var q = ui.view.quotes.current;
        var queueSize = (ui.view.quotes.queue || []).length;
        if (!q) return "/0/" + queueSize;
        var qid = q.config ? q.config.id : 0;
        return (q.celestial || "") + "/" + qid + "/" + queueSize;
    };

    globalThis._nativeAdvanceQuote = function () {
        if (typeof Quote !== "undefined") Quote.advanceQueue();
    };

    globalThis._nativeShowQuoteHistory = function (celestial) {
        if (typeof Quote === "undefined" || !Quotes[celestial]) return "[]";
        var all = Quotes[celestial].all;
        var out = [];
        for (var i = 0; i < all.length; i++) {
            var q = all[i];
            if (!q.isUnlocked) continue;
            var firstLine = q.line(0).line;
            out.push({ quoteId: q.config.id, firstLine: firstLine, totalLines: q.totalLines });
        }
        return JSON.stringify(out);
    };

    globalThis._nativeReplayQuote = function (celestial, quoteId) {
        if (typeof Quotes === "undefined" || !Quotes[celestial]) return;
        var all = Quotes[celestial].all;
        for (var i = 0; i < all.length; i++) {
            if (all[i].config.id === quoteId) {
                Quote.addToQueue(all[i]);
                return;
            }
        }
    };

    // ---- Effarig --------------------------------------------------------

    // Shared failsafe for JSON-returning helpers. Swallows exceptions so iOS
    // never sees a thrown JS error turned into an empty JSValue.
    function effarigLog(e) {
        if (typeof _nativeLog !== "undefined") {
            _nativeLog("[effarig] " + (e && e.message ? e.message : String(e)));
        }
    }

    // Serialize a single glyph object (from player.reality.glyphs.sets[*].glyphs
    // or Glyphs.active) into the TeresaGlyphRecord shape consumed by Swift.
    // Re-used for preset rendering so we can reuse GlyphComponent.
    function serializeGlyphRecord(g, fallbackIndex) {
        if (!g) return null;
        var typeColor = "";
        try { typeColor = GlyphAppearanceHandler.getBorderColor(g.type); } catch (e) {}
        var rarityColor = "";
        var rarityPct = "";
        var rarityPctNum = 0;
        var rarityName = "";
        try {
            var rarity = strengthToRarity(g.strength);
            rarityPctNum = +rarity || 0;
            rarityPct = formatRarity(rarity);
            var rarityObj = getRarity(g.strength);
            if (rarityObj) {
                rarityColor = rarityObj.darkColor || rarityObj.color || "";
                rarityName = rarityObj.name || "";
            }
        } catch (e) {}
        var effectBits = g.effects || 0;
        var effectCount = 0;
        var tmp = effectBits;
        while (tmp) { effectCount += tmp & 1; tmp >>>= 1; }
        var generatedTypes = ["power", "infinity", "replication", "time", "dilation", "effarig"];
        var effectDescs = [];
        try {
            var isGenerated = generatedTypes.indexOf(g.type) >= 0;
            var vals = getGlyphEffectValuesFromBitmask(effectBits, g.level, g.strength, g.type);
            var db = GlyphEffects;
            for (var i = 0; i < vals.length; i++) {
                var ev = vals[i];
                var entry = db[ev.id];
                if (!entry || (!!entry.isGenerated) !== isGenerated) continue;
                var rawDesc = entry.shortDesc;
                if (!rawDesc) continue;
                var singleVal = entry.formatSingleEffect
                    ? entry.formatSingleEffect(ev.value)
                    : (entry.formatEffect ? entry.formatEffect(ev.value) : String(ev.value));
                var altVal = entry.conversion
                    ? (entry.formatSecondaryEffect ? entry.formatSecondaryEffect(entry.conversion(ev.value)) : "")
                    : "";
                effectDescs.push(rawDesc.replace("{value}", singleVal).replace("{value2}", altVal));
            }
        } catch (e) {}
        var symbol = g.symbol;
        if (!symbol) {
            try { symbol = CosmeticGlyphTypes[g.type].currentSymbol.symbol; } catch (e) { symbol = "?"; }
        }
        return {
            type: g.type || "",
            symbol: symbol || "?",
            level: g.level || 0,
            effectCount: effectCount,
            typeColor: typeColor,
            rarityColor: rarityColor,
            rarityPercent: rarityPct,
            rarityPercentNum: rarityPctNum,
            rarityName: rarityName,
            effects: effectDescs,
            // fallbackIndex is only used for ForEach identity on the Swift side;
            // actual inventory position comes from `g.idx` when relevant.
            fallbackIndex: fallbackIndex
        };
    }

    function effarigStageName(stage) {
        switch (stage) {
            case 1: return "Infinity";
            case 2: return "Eternity";
            case 3: return "Reality";
            default: return "Reality";
        }
    }

    globalThis._nativeEffarigState = function () {
        try {
            if (typeof Effarig === "undefined" || typeof EffarigUnlock === "undefined") {
                return JSON.stringify({ ready: false });
            }
            var rs = Currency.relicShards.value;
            var shardsGained = Effarig.shardsGained;
            var minutes = Math.max(Time.thisRealityRealTime.totalMinutes || 0, 1e-9);
            var rate = shardsGained / minutes;
            var ampCount = 0;
            try { ampCount = simulatedRealityCount(false) | 0; } catch (e) { ampCount = 0; }
            var amplified = shardsGained * (1 + ampCount);
            var amplifiedRate = amplified / minutes;

            var shardPowerEffect = 1;
            try {
                if (typeof Ra !== "undefined" && Ra.unlocks && Ra.unlocks.maxGlyphRarityAndShardSacrificeBoost) {
                    shardPowerEffect = Ra.unlocks.maxGlyphRarityAndShardSacrificeBoost.effectOrDefault(1);
                }
            } catch (e) {}
            var shardPowerText = (shardPowerEffect && shardPowerEffect !== 1)
                ? formatPow(shardPowerEffect, 3, 3) : "";

            var alwaysMax = false;
            try {
                if (typeof Ra !== "undefined" && Ra.unlocks && Ra.unlocks.extraGlyphChoicesAndRelicShardRarityAlwaysMax) {
                    alwaysMax = !!Ra.unlocks.extraGlyphChoicesAndRelicShardRarityAlwaysMax.canBeApplied;
                }
            } catch (e) {}

            // Shop upgrades (ids 0..3): description/cost from GameDatabase; purchased state from EffarigUnlock.
            var shopIds = ["adjuster", "glyphFilter", "setSaves", "run"];
            var shopUpgrades = [];
            var cfgSrc = GameDatabase.celestials.effarig.unlocks;
            for (var i = 0; i < shopIds.length; i++) {
                var key = shopIds[i];
                var unlock = EffarigUnlock[key];
                var cfg = cfgSrc[key];
                if (!unlock || !cfg) continue;
                var descRaw = cfg.description;
                var desc = typeof descRaw === "function" ? descRaw() : descRaw;
                shopUpgrades.push({
                    id: cfg.id,
                    key: key,
                    description: String(desc || "").replace(/\s+/g, " ").trim(),
                    cost: format(cfg.cost, 2),
                    isUnlocked: !!unlock.isUnlocked,
                    canAfford: rs >= cfg.cost
                });
            }

            // Run-stage unlocks (ids 4..6).
            var stageIds = ["infinity", "eternity", "reality"];
            var stageLabels = { infinity: "Infinity", eternity: "Eternity", reality: "Reality" };
            var runUnlocks = [];
            for (var j = 0; j < stageIds.length; j++) {
                var skey = stageIds[j];
                var su = EffarigUnlock[skey];
                var scfg = cfgSrc[skey];
                if (!su || !scfg) continue;
                var sdescRaw = scfg.description;
                var sdesc = typeof sdescRaw === "function" ? sdescRaw() : sdescRaw;
                var sdescStr = String(sdesc || "");
                // Split on "\n" BEFORE whitespace normalization so iOS can
                // render each line with the Ξ bullet (mirrors web
                // EffarigRunUnlockReward.vue:17 `description.split("\n").map(trim)`).
                var sdescLines = sdescStr.split("\n")
                    .map(function (s) { return s.replace(/\s+/g, " ").trim(); })
                    .filter(function (s) { return s.length > 0; });
                runUnlocks.push({
                    id: scfg.id,
                    key: skey,
                    label: stageLabels[skey] || skey,
                    description: sdescStr.replace(/\s+/g, " ").trim(),
                    descriptionLines: sdescLines,
                    isUnlocked: !!su.isUnlocked
                });
            }

            // Effarig's Reality effects text + dilution description.
            // EffarigTab.vue:57 concatenates `${descriptions[1].effects()}\n${descriptions[1].description()}`.
            var runDesc = "";
            try {
                var descs = GameDatabase && GameDatabase.celestials && GameDatabase.celestials.descriptions;
                // Index 1 is Effarig (index 0 is Teresa).
                if (descs && descs[1]) {
                    var parts = [];
                    if (typeof descs[1].effects === "function") parts.push(descs[1].effects());
                    if (typeof descs[1].description === "function") parts.push(descs[1].description());
                    runDesc = parts.join("\n").replace(/\s+/g, " ").trim();
                }
            } catch (e) {}

            var stage = Effarig.currentStage;

            return JSON.stringify({
                ready: true,
                relicShards: format(rs, 2),
                shardRarityBoostPct: formatPercents(Effarig.maxRarityBoost / 100, 2),
                shardPower: shardPowerText,
                relicShardRarityAlwaysMax: alwaysMax,
                shardsGained: format(shardsGained, 2),
                currentShardsRate: format(rate, 2),
                amplification: ampCount,
                amplifiedShards: format(amplified, 2),
                amplifiedShardsRate: format(amplifiedRate, 2),
                runUnlocked: !!EffarigUnlock.run.isUnlocked,
                isRunning: !!Effarig.isRunning,
                currentStage: stage,
                currentStageName: effarigStageName(stage),
                glyphLevelCap: Effarig.glyphLevelCap | 0,
                vIsFlipped: !!(typeof V !== "undefined" && V.isFlipped),
                runDescription: runDesc,
                shopUpgrades: shopUpgrades,
                runUnlocks: runUnlocks
            });
        } catch (e) {
            effarigLog(e);
            return JSON.stringify({ ready: false });
        }
    };

    /// Lightweight per-tick read — called from pollGlyphs() to drive the
    /// Effarig-run banner on the Glyphs tab. Only three plain values.
    globalThis._nativeEffarigRunMeta = function () {
        try {
            if (typeof Effarig === "undefined") return "";
            if (!Effarig.isRunning) return "0||100";  // "running|stageName|cap"
            var stage = Effarig.currentStage;
            return "1|" + effarigStageName(stage) + "|" + (Effarig.glyphLevelCap | 0);
        } catch (e) { return ""; }
    };

    globalThis._nativeStartEffarigRun = function () {
        try {
            if (typeof Effarig === "undefined") return;
            if (!EffarigUnlock.run.isUnlocked) return;
            beginProcessReality(getRealityProps(true));
            Effarig.initializeRun();
        } catch (e) { effarigLog(e); }
    };

    globalThis._nativeBuyEffarigUpgrade = function (id) {
        try {
            if (typeof EffarigUnlock === "undefined") return;
            // The upgrade's onPurchased callback writes to ui.view.tab/subtab
            // (via Tab.reality.glyphs.show() / mutation of ui.view.tabs.reality.*).
            // Snapshot + restore to keep the iOS subtab state tracking honest.
            var savedTab = "", savedSub = "";
            try {
                if (typeof ui !== "undefined" && ui.view) {
                    savedTab = ui.view.tab || "";
                    savedSub = ui.view.subtab || "";
                }
            } catch (e) {}
            var entry = null;
            // Find by id (0..3). Also accept 4..6 as no-ops (stage unlocks aren't purchaseable).
            var keys = ["adjuster", "glyphFilter", "setSaves", "run"];
            for (var i = 0; i < keys.length; i++) {
                var u = EffarigUnlock[keys[i]];
                if (u && u.id === id) { entry = u; break; }
            }
            if (entry && !entry.isUnlocked) entry.purchase();
            try {
                if (savedTab && typeof ui !== "undefined" && ui.view) {
                    ui.view.tab = savedTab;
                    ui.view.subtab = savedSub;
                }
            } catch (e) {}
        } catch (e) { effarigLog(e); }
    };

    globalThis._nativeGiveCursedGlyph = function () {
        try {
            if (typeof Glyphs === "undefined" || typeof Glyphs.giveCursedGlyph !== "function") return;
            Glyphs.giveCursedGlyph();
        } catch (e) { effarigLog(e); }
    };

    // ---- Effarig: Glyph Weights ----------------------------------------

    // Glyph level factor breakdown — identical output to the inline block in
    // pollGlyphs (GlyphLevelsAndWeights.vue on web). Callable on demand so the
    // weights sheet can show live factor values even when the Glyphs tab isn't
    // the active poll category.
    globalThis._nativeGlyphLevelFactors = function () {
        try {
            if (typeof getGlyphLevelInputs !== "function") {
                return JSON.stringify({ factors: [], finalLevel: "" });
            }
            var inputs = getGlyphLevelInputs();
            var fmtCoeff = function (c) { return format(c, 2, 4); };
            var fmtExp = function (e) { return format(e, 2, 3); };
            var fmtVal = function (v) { return format(v, 2, 3); };
            var factors = [];
            factors.push({ name: "EP", formula: fmtCoeff(inputs.ep.coeff) + " \u00d7 EP^" + fmtExp(inputs.ep.exp), value: fmtVal(inputs.ep.value), op: "\u00d7" });
            factors.push({ name: "Replicanti", formula: fmtCoeff(inputs.repl.coeff) + " \u00d7 Repl^" + fmtExp(inputs.repl.exp), value: fmtVal(inputs.repl.value), op: "\u00d7" });
            factors.push({ name: "Dilated Time", formula: fmtCoeff(inputs.dt.coeff) + " \u00d7 DT^" + fmtExp(inputs.dt.exp), value: fmtVal(inputs.dt.value), op: "\u00d7" });
            if (inputs.eter && typeof RealityUpgrade !== "undefined" && RealityUpgrade(18).isBought) {
                factors.push({ name: "Eternities", formula: fmtCoeff(inputs.eter.coeff) + " \u00d7 Eter^" + fmtExp(inputs.eter.exp), value: fmtVal(inputs.eter.value), op: "\u00d7" });
            }
            if (inputs.perkShop !== 1) {
                factors.push({ name: "Perk Shop", formula: "", value: formatPercents(inputs.perkShop - 1), op: "+" });
            }
            if (inputs.scalePenalty !== 1) {
                factors.push({ name: "Instability", formula: "", value: format(1 / inputs.scalePenalty, 2, 3), op: "/" });
            }
            return JSON.stringify({ factors: factors, finalLevel: formatInt(inputs.actualLevel) });
        } catch (e) {
            effarigLog(e);
            return JSON.stringify({ factors: [], finalLevel: "" });
        }
    };

    globalThis._nativeEffarigWeights = function () {
        try {
            var w = player.celestials.effarig.glyphWeights || { ep: 25, repl: 25, dt: 25, eternities: 25 };
            var autoAdjustUnlocked = !!(typeof Achievement === "function" && Achievement(165) && Achievement(165).isUnlocked);
            return JSON.stringify({
                ep: w.ep | 0,
                repl: w.repl | 0,
                dt: w.dt | 0,
                eternities: w.eternities | 0,
                autoAdjust: !!player.celestials.effarig.autoAdjustGlyphWeights,
                autoAdjustUnlocked: autoAdjustUnlocked
            });
        } catch (e) { effarigLog(e); return JSON.stringify({ ep: 25, repl: 25, dt: 25, eternities: 25, autoAdjust: false, autoAdjustUnlocked: false }); }
    };

    // Port of GlyphLevelsAndWeights.vue `roundPreservingSum` (lines 236-268).
    // Rounds floats to ints while preserving the original sum, by repeatedly
    // picking the value closest to an integer, rounding it, and distributing
    // the leftover error across the remaining non-integers.
    function _effarigRoundPreservingSum(data) {
        for (var idx = 0; idx < data.length; ++idx) {
            var closest = -1;
            var closestDistance = 1000;
            var nonIntegers = 0;
            for (var s = 0; s < data.length; ++s) {
                var dist = Math.abs(data[s] - Math.round(data[s]));
                if (dist !== 0) {
                    ++nonIntegers;
                    if (dist < closestDistance) {
                        closest = s;
                        closestDistance = dist;
                    }
                }
            }
            if (closest === -1) break;
            var err = data[closest] - Math.round(data[closest]);
            data[closest] = Math.round(data[closest]);
            if (nonIntegers === 1) break;
            err /= (nonIntegers - 1);
            for (var t = 0; t < data.length; ++t) {
                if (data[t] !== Math.round(data[t])) data[t] += err;
            }
        }
    }

    // Mirrors GlyphLevelsAndWeights.vue `adjustSlider` (lines 184-220) but
    // simplified for the iOS Stepper UI: each call is a discrete +/-1 rather
    // than a continuous drag, so we reduce from current values directly
    // (no `savedWeights` snapshot needed). Invariant after this call:
    // ep + repl + dt + eternities <= 100 (and === 100 if the clamp fired).
    globalThis._nativeSetEffarigWeight = function (key, value) {
        try {
            if (!player.celestials.effarig.glyphWeights) return;
            if (key !== "ep" && key !== "repl" && key !== "dt" && key !== "eternities") return;
            var w = player.celestials.effarig.glyphWeights;
            var v = Math.max(0, Math.min(100, value | 0));
            var fields = ["ep", "repl", "dt", "eternities"];
            var otherSum = 0;
            for (var i = 0; i < fields.length; ++i) {
                if (fields[i] !== key) otherSum += w[fields[i]];
            }
            if (otherSum + v > 100) {
                // Scale the other three down so the total lands on 100.
                var headroom = 100 - v;
                var newOthers;
                if (otherSum > 0) {
                    var ratio = headroom / otherSum;
                    newOthers = [];
                    for (var j = 0; j < fields.length; ++j) {
                        if (fields[j] !== key) newOthers.push(w[fields[j]] * ratio);
                    }
                } else {
                    // otherSum == 0 and v would push total over 100 — only
                    // possible when v > 100, which the clamp above prevents.
                    // Guard anyway: split headroom evenly.
                    var even = headroom / 3;
                    newOthers = [even, even, even];
                }
                _effarigRoundPreservingSum(newOthers);
                var idx2 = 0;
                for (var k = 0; k < fields.length; ++k) {
                    if (fields[k] !== key) {
                        w[fields[k]] = Math.max(0, Math.round(newOthers[idx2++]));
                    }
                }
            }
            w[key] = v;
        } catch (e) { effarigLog(e); }
    };

    // Matches GlyphLevelsAndWeights.vue `resetWeights` (line 180): restore
    // the default 25/25/25/25 split summing to 100.
    globalThis._nativeResetEffarigWeights = function () {
        try {
            if (!player.celestials.effarig.glyphWeights) return;
            player.celestials.effarig.glyphWeights.ep = 25;
            player.celestials.effarig.glyphWeights.repl = 25;
            player.celestials.effarig.glyphWeights.dt = 25;
            player.celestials.effarig.glyphWeights.eternities = 25;
        } catch (e) { effarigLog(e); }
    };

    globalThis._nativeToggleEffarigAutoWeights = function () {
        try {
            var unlocked = (typeof Achievement === "function" && Achievement(165) && Achievement(165).isUnlocked);
            if (!unlocked) {
                // Defensive: clear any stale flag from a pre-fix save where the
                // toggle was reachable before Achievement 165 was earned.
                player.celestials.effarig.autoAdjustGlyphWeights = false;
                return;
            }
            player.celestials.effarig.autoAdjustGlyphWeights = !player.celestials.effarig.autoAdjustGlyphWeights;
        } catch (e) { effarigLog(e); }
    };

    // ---- Effarig: Glyph Filter -----------------------------------------

    globalThis._nativeGlyphFilter = function () {
        try {
            var f = player.reality.glyphs.filter;
            if (!f) return JSON.stringify({ selectMode: 0, trashMode: 0, simpleThreshold: 0, alchemyUnlocked: false, types: [] });
            var alchemyUnlocked = false;
            try {
                alchemyUnlocked = !!(typeof Ra !== "undefined" && Ra.unlocks && Ra.unlocks.unlockGlyphAlchemy && Ra.unlocks.unlockGlyphAlchemy.canBeApplied);
            } catch (e) {}
            var lockedTypes = [];
            try {
                if (typeof GlyphTypes !== "undefined" && GlyphTypes.locked) {
                    lockedTypes = GlyphTypes.locked.map(function (t) { return t.id; });
                }
            } catch (e) {}
            var types = [];
            // Iterate in the web-canonical order (GlyphTypes.list excluding locked).
            var orderedIds = [];
            try {
                if (typeof GlyphTypes !== "undefined" && GlyphTypes.list) {
                    for (var oi = 0; oi < GlyphTypes.list.length; oi++) {
                        var gt = GlyphTypes.list[oi];
                        if (!gt || !gt.id) continue;
                        if (lockedTypes.indexOf(gt.id) !== -1) continue;
                        if (!Object.prototype.hasOwnProperty.call(f.types, gt.id)) continue;
                        orderedIds.push(gt.id);
                    }
                }
            } catch (e) {}
            // Fallback: object iteration order if GlyphTypes wasn't available.
            if (!orderedIds.length) {
                for (var tk in f.types) {
                    if (Object.prototype.hasOwnProperty.call(f.types, tk)) orderedIds.push(tk);
                }
            }

            for (var ii = 0; ii < orderedIds.length; ii++) {
                var typeId = orderedIds[ii];
                var cfg = f.types[typeId];
                if (!cfg) continue;
                var effectIds = [];
                var effectNames = [];
                var effectBitmaskIndices = [];
                var typeColor = "";
                var typeSymbol = "?";
                try {
                    var glyphType = GlyphTypes[typeId];
                    if (glyphType) {
                        if (glyphType.color) typeColor = glyphType.color;
                        try {
                            typeSymbol = CosmeticGlyphTypes[typeId].currentSymbol.symbol;
                        } catch (e) {}
                        if (glyphType.effects) {
                            for (var i = 0; i < glyphType.effects.length; i++) {
                                var eff = glyphType.effects[i];
                                effectIds.push(eff.id || "");
                                // Absolute bitmask index (NOT per-type contiguous). The
                                // SPECIFIED_EFFECT filter mode toggles `specifiedMask`
                                // via `1 << bitmaskIndex` and the score is computed as
                                // `specifiedMask & glyph.effects`, where `glyph.effects`
                                // uses these absolute bits. iOS must use the same bit per
                                // checkbox or every checked effect counts as "missing"
                                // (−200 each) for any type whose offset != 0.
                                effectBitmaskIndices.push(eff.bitmaskIndex | 0);
                                // Prefer `genericDesc` (value-free label used by web filter UI).
                                // Fall back to shortDesc/{value}-stripped when absent.
                                var label = eff.genericDesc;
                                if (typeof label === "function") label = label();
                                if (!label) {
                                    label = String(eff.shortDesc || eff.id || "").replace(/\{value2?\}/g, "…").trim();
                                }
                                effectNames.push(String(label || "").trim());
                            }
                        }
                    }
                } catch (e) {}
                types.push({
                    type: typeId,
                    typeDisplayName: typeId.charAt(0).toUpperCase() + typeId.slice(1),
                    typeSymbol: typeSymbol,
                    typeColor: typeColor,
                    rarity: cfg.rarity | 0,
                    score: cfg.score | 0,
                    effectCount: cfg.effectCount | 0,
                    specifiedMask: cfg.specifiedMask | 0,
                    effectScores: (cfg.effectScores || []).map(function (n) { return n | 0; }),
                    effectIds: effectIds,
                    effectNames: effectNames,
                    effectBitmaskIndices: effectBitmaskIndices
                });
            }
            var autoRealityForFilter = false;
            try { autoRealityForFilter = !!(player.options && player.options.autoRealityForFilter); } catch (e) {}
            return JSON.stringify({
                selectMode: f.select | 0,
                trashMode: f.trash | 0,
                simpleThreshold: f.simple | 0,
                alchemyUnlocked: alchemyUnlocked,
                autoRealityForFilter: autoRealityForFilter,
                types: types
            });
        } catch (e) { effarigLog(e); return JSON.stringify({ selectMode: 0, trashMode: 0, simpleThreshold: 0, alchemyUnlocked: false, autoRealityForFilter: false, types: [] }); }
    };

    // Mirrors web's GlyphFilterPanel.toggleAutoReality (toggleAutoReality on
    // GlyphFilterPanel.vue:175-179): flips the player option AND clears
    // `hasCheckedFilter` so RealityAutobuyer.tick() re-evaluates on the next
    // tick. Without the reset the toggle wouldn't take effect mid-Reality.
    globalThis._nativeToggleGlyphFilterAutoReality = function () {
        try {
            if (!player.options) return;
            player.options.autoRealityForFilter = !player.options.autoRealityForFilter;
            if (player.reality) player.reality.hasCheckedFilter = false;
        } catch (e) { effarigLog(e); }
    };

    globalThis._nativeSetGlyphFilterMode = function (which, value) {
        try {
            var f = player.reality.glyphs.filter;
            if (!f) return;
            var v = value | 0;
            if (which === "select") f.select = v;
            else if (which === "trash") f.trash = v;
            else if (which === "simple") f.simple = v;
        } catch (e) { effarigLog(e); }
    };

    globalThis._nativeSetGlyphFilterType = function (type, field, value) {
        try {
            var f = player.reality.glyphs.filter;
            if (!f || !f.types[type]) return;
            if (field === "rarity" || field === "score" || field === "effectCount" || field === "specifiedMask") {
                f.types[type][field] = value | 0;
            }
        } catch (e) { effarigLog(e); }
    };

    // Port of GlyphFilterPanel.vue `exportFilterSettings()` — serializes the
    // full filter state into a short pipe-joined string, wraps it with
    // GameSaveSerializer's "glyph filter" header, and returns it. Swift copies
    // the result to UIPasteboard. Returns "" on failure.
    globalThis._nativeExportGlyphFilter = function () {
        try {
            var f = player.reality.glyphs.filter;
            if (!f) return "";
            var types = (typeof ALCHEMY_BASIC_GLYPH_TYPES !== "undefined") ? ALCHEMY_BASIC_GLYPH_TYPES : Object.keys(f.types);
            var serializeType = function (s) {
                return [s.rarity, s.score, s.effectCount, s.specifiedMask, (s.effectScores || []).join("/")].join(",");
            };
            var simpleData = [f.select, f.simple, f.trash].join("|");
            var typeData = types.map(function (t) { return serializeType(f.types[t]); }).join("|");
            return GameSaveSerializer.encodeText(simpleData + "|" + typeData, "glyph filter");
        } catch (e) { effarigLog(e); return ""; }
    };

    // Validate + preview an import string without applying it. Returns JSON
    // matching the parsed web structure (plus a `valid` boolean) so the Swift
    // sheet can show a diff before commit.
    globalThis._nativeParseGlyphFilterImport = function (raw) {
        try {
            var decoded;
            try { decoded = GameSaveSerializer.decodeText(String(raw || ""), "glyph filter"); }
            catch (e) { return JSON.stringify({ valid: false }); }
            if (!decoded || decoded.length === 0 || !/^[0-9,.|/-]*$/.test(decoded)) {
                return JSON.stringify({ valid: false });
            }
            var parts = decoded.split("|");
            if (parts.length < 4) return JSON.stringify({ valid: false });
            var types = (typeof ALCHEMY_BASIC_GLYPH_TYPES !== "undefined") ? ALCHEMY_BASIC_GLYPH_TYPES : [];
            var typeInfo = {};
            var idx = 3;
            for (var i = 0; i < types.length; i++) {
                var t = types[i];
                if (!t) continue;
                if (idx >= parts.length) return JSON.stringify({ valid: false });
                var sub = parts[idx].split(",");
                if (sub.length < 5) return JSON.stringify({ valid: false });
                typeInfo[t] = {
                    rarity: Number(sub[0]) | 0,
                    score: Number(sub[1]) | 0,
                    effectCount: Number(sub[2]) | 0,
                    specifiedMask: Number(sub[3]) | 0,
                    effectScores: sub[4].split("/").map(function (s) { return Number(s) | 0; })
                };
                idx++;
            }
            var current = player.reality.glyphs.filter || {};
            var modeName = function (m) {
                try { return AutoGlyphProcessor.filterModeName(m); } catch (e) { return String(m); }
            };
            var trashName = function (m) {
                try { return AutoGlyphProcessor.trashModeDesc(m); } catch (e) { return String(m); }
            };
            return JSON.stringify({
                valid: true,
                select: Number(parts[0]) | 0,
                simple: Number(parts[1]) | 0,
                trash: Number(parts[2]) | 0,
                currentSelect: current.select | 0,
                currentSimple: current.simple | 0,
                currentTrash: current.trash | 0,
                selectName: modeName(Number(parts[0]) | 0),
                currentSelectName: modeName(current.select | 0),
                trashLabel: trashName(Number(parts[2]) | 0),
                currentTrashLabel: trashName(current.trash | 0),
                types: typeInfo
            });
        } catch (e) { effarigLog(e); return JSON.stringify({ valid: false }); }
    };

    // Commit a validated import string. Returns "ok" / "invalid" / "error".
    globalThis._nativeImportGlyphFilter = function (raw) {
        try {
            var decoded;
            try { decoded = GameSaveSerializer.decodeText(String(raw || ""), "glyph filter"); }
            catch (e) { return "invalid"; }
            if (!decoded || !/^[0-9,.|/-]*$/.test(decoded)) return "invalid";
            var parts = decoded.split("|");
            if (parts.length < 4) return "invalid";
            var types = (typeof ALCHEMY_BASIC_GLYPH_TYPES !== "undefined") ? ALCHEMY_BASIC_GLYPH_TYPES : [];
            var typeInfo = {};
            var idx = 3;
            for (var i = 0; i < types.length; i++) {
                var t = types[i];
                if (!t) continue;
                if (idx >= parts.length) return "invalid";
                var sub = parts[idx].split(",");
                if (sub.length < 5) return "invalid";
                typeInfo[t] = {
                    rarity: Number(sub[0]) | 0,
                    score: Number(sub[1]) | 0,
                    effectCount: Number(sub[2]) | 0,
                    specifiedMask: Number(sub[3]) | 0,
                    effectScores: sub[4].split("/").map(function (s) { return Number(s) | 0; })
                };
                idx++;
            }
            player.reality.glyphs.filter = {
                select: Number(parts[0]) | 0,
                simple: Number(parts[1]) | 0,
                trash: Number(parts[2]) | 0,
                types: typeInfo
            };
            if (typeof player.reality.hasCheckedFilter !== "undefined") {
                player.reality.hasCheckedFilter = false;
            }
            return "ok";
        } catch (e) { effarigLog(e); return "error"; }
    };

    globalThis._nativeSetGlyphFilterEffectScore = function (type, idx, value) {
        try {
            var f = player.reality.glyphs.filter;
            if (!f || !f.types[type]) return;
            var arr = f.types[type].effectScores;
            if (!arr || idx < 0 || idx >= arr.length) return;
            arr[idx] = value | 0;
        } catch (e) { effarigLog(e); }
    };

    // ---- Effarig: Glyph Presets ----------------------------------------

    globalThis._nativeGlyphPresets = function () {
        try {
            var sets = player.reality.glyphs.sets || [];
            var out = [];
            for (var i = 0; i < sets.length; i++) {
                var s = sets[i] || { name: "", glyphs: [] };
                var glyphs = s.glyphs || [];
                var serialized = [];
                for (var j = 0; j < glyphs.length; j++) {
                    var rec = serializeGlyphRecord(glyphs[j], j);
                    if (rec) serialized.push(rec);
                }
                out.push({
                    id: i,
                    name: s.name || "",
                    glyphs: serialized,
                    isEmpty: glyphs.length === 0
                });
            }
            return JSON.stringify({
                slots: out,
                hasEquipped: (typeof Glyphs !== "undefined" && Glyphs.activeList.length > 0),
                ignoreEffects: !!player.options.ignoreGlyphEffects,
                ignoreRarity: !!player.options.ignoreGlyphRarity,
                ignoreLevel: !!player.options.ignoreGlyphLevel
            });
        } catch (e) { effarigLog(e); return JSON.stringify({ slots: [], hasEquipped: false, ignoreEffects: true, ignoreRarity: true, ignoreLevel: true }); }
    };

    globalThis._nativeSaveGlyphPreset = function (slot) {
        try {
            var sets = player.reality.glyphs.sets;
            if (!sets || !sets[slot]) return "bad-slot";
            if (sets[slot].glyphs && sets[slot].glyphs.length) return "slot-occupied";
            var active = Glyphs.active.compact();
            if (!active.length) return "empty-active";
            sets[slot].glyphs = active;
            try { EventHub.dispatch(GAME_EVENT.GLYPH_SET_SAVE_CHANGE); } catch (e) {}
            return "ok";
        } catch (e) { effarigLog(e); return "error"; }
    };

    globalThis._nativeDeleteGlyphPreset = function (slot) {
        try {
            var sets = player.reality.glyphs.sets;
            if (!sets || !sets[slot]) return "bad-slot";
            sets[slot].glyphs = [];
            try { EventHub.dispatch(GAME_EVENT.GLYPH_SET_SAVE_CHANGE); } catch (e) {}
            return "ok";
        } catch (e) { effarigLog(e); return "error"; }
    };

    globalThis._nativeRenameGlyphPreset = function (slot, name) {
        try {
            var sets = player.reality.glyphs.sets;
            if (!sets || !sets[slot]) return "bad-slot";
            var clean = String(name || "").replace(/[\r\n]/g, "").slice(0, 20);
            sets[slot].name = clean;
            try { EventHub.dispatch(GAME_EVENT.GLYPH_SET_SAVE_CHANGE); } catch (e) {}
            return "ok";
        } catch (e) { effarigLog(e); return "error"; }
    };

    globalThis._nativeSetGlyphPresetIgnore = function (field, value) {
        try {
            var v = !!value;
            if (field === "effects") player.options.ignoreGlyphEffects = v;
            else if (field === "rarity") player.options.ignoreGlyphRarity = v;
            else if (field === "level") player.options.ignoreGlyphLevel = v;
        } catch (e) { effarigLog(e); }
    };

    // Inlined port of GlyphSetSavePanel.loadGlyphSet — the ~80-line greedy
    // matcher that applies `ignoreGlyphEffects/Rarity/Level` slack when the
    // preset doesn't perfectly match the current inventory.
    function _effarigLoadGlyphSet(set, slotId) {
        if (!set || !set.length || set.length > Glyphs.activeSlotCount) return "invalid-set";
        var slack = {
            effects: !!player.options.ignoreGlyphEffects,
            rarity: !!player.options.ignoreGlyphRarity,
            level: !!player.options.ignoreGlyphLevel
        };
        var glyphsToLoad = set.slice().sort(function (a, b) { return (-a.level * a.strength) + (b.level * b.strength); });
        var activeGlyphs = Glyphs.active.filter(function (g) { return g; });

        function findOptions(g, pool, sign) {
            return Glyphs.findByValues(g, pool, {
                level: slack.level ? sign : 0,
                strength: slack.rarity ? sign : 0,
                effects: slack.effects ? sign : 0
            });
        }

        var activeOptions = [];
        for (var a = 0; a < activeGlyphs.length; a++) {
            activeOptions.push({ glyph: activeGlyphs[a], options: findOptions(activeGlyphs[a], glyphsToLoad, -1) });
        }

        function findSelected(optionList, maxGlyphs) {
            var compFn = function (o) { return 1000 * (10 * o.glyph.type.length + o.glyph.type.codePointAt(0)) + o.options.length; };
            optionList.sort(function (x, y) { return compFn(x) - compFn(y); });
            var toLoad = [];
            var slotsLeft = maxGlyphs;
            for (var k = 0; k < optionList.length; k++) {
                if (slotsLeft === 0) break;
                var entry = optionList[k];
                var filtered = entry.options.filter(function (g) { return toLoad.indexOf(g) === -1; });
                if (!filtered.length) continue;
                toLoad.push(filtered[filtered.length - 1]);
                slotsLeft--;
            }
            return toLoad;
        }

        var selectedFromActive = findSelected(activeOptions, 5);
        for (var m = 0; m < selectedFromActive.length; m++) {
            var sg = selectedFromActive[m];
            glyphsToLoad = glyphsToLoad.filter(function (g) { return g !== sg; });
        }

        var remainingOptions = [];
        for (var p = 0; p < glyphsToLoad.length; p++) {
            remainingOptions[p] = { glyph: glyphsToLoad[p], options: findOptions(glyphsToLoad[p], Glyphs.sortedInventoryList, 1) };
        }
        var selectedFromInv = findSelected(remainingOptions, Glyphs.active.countWhere(function (g) { return g === null; }));
        for (var q = 0; q < selectedFromInv.length; q++) {
            var ig = selectedFromInv[q];
            glyphsToLoad = glyphsToLoad.filter(function (g) { return g !== ig; });
        }

        var missing = glyphsToLoad.length;
        for (var r = 0; r < selectedFromInv.length; r++) {
            var idx = Glyphs.active.indexOf(null);
            if (idx !== -1) {
                Glyphs.equip(selectedFromInv[r], idx);
                missing--;
            }
        }
        if (missing > 0) {
            GameUI.notify.error("Could not find or equip " + missing + " glyph" + (missing === 1 ? "" : "s") + " from preset #" + (slotId + 1) + ".");
        } else {
            GameUI.notify.success("Successfully loaded preset #" + (slotId + 1) + ".");
        }
        return "ok";
    }

    globalThis._nativeLoadGlyphPreset = function (slot) {
        try {
            var sets = player.reality.glyphs.sets;
            if (!sets || !sets[slot]) return "bad-slot";
            var set = sets[slot].glyphs;
            if (!set || !set.length) return "no-set";
            return _effarigLoadGlyphSet(set, slot);
        } catch (e) { effarigLog(e); return "error"; }
    };

    // ---- Enslaved (The Nameless Ones) -----------------------------------

    function enslavedLog(e) {
        if (typeof _nativeLog !== "undefined") {
            _nativeLog("[enslaved] " + (e && e.message ? e.message : String(e)));
        }
    }

    globalThis._nativeEnslavedState = function () {
        try {
            if (typeof Enslaved === "undefined") {
                return JSON.stringify({ ready: false });
            }

            var storedBH = player.celestials.enslaved.stored || 0;
            var storedReal = player.celestials.enslaved.storedReal || 0;
            var isRunning = !!Enslaved.isRunning;
            var isDoomed = (typeof Pelle !== "undefined") && !!Pelle.isDoomed;

            // Unlocks shop
            var unlocks = [];
            try {
                var entries = Object.values(ENSLAVED_UNLOCKS);
                var rateForEstimate = Enslaved.currentBlackHoleStoreAmountPerMs || 0;
                var isChargingForEstimate = !!Enslaved.isStoringGameTime;
                for (var i = 0; i < entries.length; i++) {
                    var info = entries[i];
                    var descRaw = typeof info.description === "function" ? info.description() : info.description;
                    var bought = Enslaved.has(info);
                    // Mirrors EnslavedTab.vue `timeUntilBuy(price)`:
                    //   Math.max((price - storedBH) / currentSpeedUp, 0)
                    var timeToObtainText = "";
                    if (!bought && isChargingForEstimate && rateForEstimate > 0) {
                        var msNeeded = (info.price - storedBH) / rateForEstimate;
                        if (msNeeded > 0) timeToObtainText = timeDisplayShort(msNeeded);
                    }
                    unlocks.push({
                        id: info.id,
                        description: String(descRaw || "").replace(/\s+/g, " ").trim(),
                        priceYears: timeDisplayShort(info.price),
                        hasBought: bought,
                        canBuy: Enslaved.canBuy(info),
                        timeToObtainText: timeToObtainText
                    });
                }
            } catch (e) { enslavedLog(e); }

            // Run description lines from GameDatabase.celestials.descriptions[2].effects()
            var runDescription = [];
            try {
                var descs = GameDatabase && GameDatabase.celestials && GameDatabase.celestials.descriptions;
                if (descs && descs[2] && typeof descs[2].effects === "function") {
                    runDescription = descs[2].effects().split("\n").map(function (s) { return s.trim(); }).filter(function (s) { return s.length > 0; });
                }
            } catch (e) {}

            // Nerfed in-reality discharge text — only meaningful while inside the reality.
            var nerfedText = "";
            try {
                if (isRunning) nerfedText = timeDisplayShort(Enslaved.storedTimeInsideEnslaved(storedBH));
            } catch (e) {}

            // Black Hole inversion state (only visible post-V-flipped & BHs permanent)
            var isNegativeBHUnlocked = false;
            var isBHInverted = false;
            var negativeSlider = 0;
            var negativeBHDivisor = "1.00";
            var sliderDisabled = false;
            var sliderLockText = "";
            try {
                if (typeof V !== "undefined" && typeof BlackHoles !== "undefined") {
                    isNegativeBHUnlocked = !!V.isFlipped && !!BlackHoles.arePermanent;
                    isBHInverted = !!BlackHoles.areNegative;
                    var bhNeg = player.blackHoleNegative || 1;
                    negativeSlider = -Math.log10(bhNeg);
                    negativeBHDivisor = format(Math.pow(10, negativeSlider), 2, 2);
                    var maxInversion = (player.requirementChecks && player.requirementChecks.reality
                        && player.requirementChecks.reality.slowestBH <= 1e-300);
                    if (typeof ImaginaryUpgrade !== "undefined"
                        && typeof Ra !== "undefined"
                        && ImaginaryUpgrade(24).isLockingMechanics && Ra.isRunning && maxInversion) {
                        sliderDisabled = true;
                        sliderLockText = 'Inversion strength cannot be modified due to Lock for "' + ImaginaryUpgrade(24).name + '"';
                    }
                }
            } catch (e) {}

            return JSON.stringify({
                ready: true,
                isUnlocked: !!Enslaved.isUnlocked,
                isRunning: isRunning,
                isCompleted: !!Enslaved.isCompleted,
                isDoomed: isDoomed,

                // Speedrun flags — also mirrored per-tick on `engine` via the
                // celestial-reality JS eval so cross-tab UI (Time Studies
                // secret study, Break Infinity "FEEL ETERNITY" swap) can
                // read them without waiting for a Celestials poll.
                hasSecretStudy: !!player.celestials.enslaved.hasSecretStudy,
                feltEternity: !!player.celestials.enslaved.feltEternity,

                isStoringBlackHole: !!Enslaved.isStoringGameTime,
                canModifyGameTimeStorage: !!Enslaved.canModifyGameTimeStorage,
                canDischarge: !!Enslaved.canRelease(false),
                hasNoCharge: storedBH === 0,
                storedBlackHoleText: timeDisplayShort(storedBH),
                storedBlackHoleMs: storedBH,
                currentBHStoreAmountPerMs: Enslaved.currentBlackHoleStoreAmountPerMs || 0,
                nerfedInRealityText: nerfedText,

                isStoringReal: !!Enslaved.isStoringRealTime,
                autoStoreReal: !!player.celestials.enslaved.autoStoreReal,
                offlineProgressEnabled: !!player.options.offlineProgress,
                canChangeStoreRealTime: !!Enslaved.canModifyRealTimeStorage,
                hasReachedCurrentCap: storedReal >= Enslaved.storedRealTimeCap,
                storedRealText: timeDisplayShort(storedReal),
                storedRealEfficiencyPct: formatPercents(Enslaved.storedRealTimeEfficiency),
                storedRealCapText: timeDisplayShort(Enslaved.storedRealTimeCap),

                isNegativeBHUnlocked: isNegativeBHUnlocked,
                isBHInverted: isBHInverted,
                negativeSlider: negativeSlider,
                negativeBHDivisor: negativeBHDivisor,
                sliderDisabled: sliderDisabled,
                sliderLockText: sliderLockText,

                hasRunUnlock: Enslaved.has(ENSLAVED_UNLOCKS.RUN),
                runDescription: runDescription,
                unlocks: unlocks,

                // Pulse Black Hole (Ra.unlocks.autoPulseTime, Enslaved pet lv 10).
                // Mirrors `EnslavedTab.vue` autoRelease toggle.
                hasAutoPulse: !!(typeof Ra !== "undefined" && Ra.unlocks
                    && Ra.unlocks.autoPulseTime && Ra.unlocks.autoPulseTime.canBeApplied),
                canAutoPulse: !!Enslaved.canRelease(true),
                isAutoPulsing: !!(Enslaved.isAutoReleasing),
                autoPulseSpeedText: Enslaved.isAutoReleasing
                    ? formatX(Enslaved.autoReleaseSpeed || 0, 2, 2) : ""
            });
        } catch (e) {
            enslavedLog(e);
            return JSON.stringify({ ready: false });
        }
    };

    globalThis._nativeStartEnslavedRun = function () {
        try {
            if (typeof Enslaved === "undefined") return;
            if (!Enslaved.has(ENSLAVED_UNLOCKS.RUN)) return;
            // Same pipeline Effarig uses: beginProcessReality → initializeRun.
            beginProcessReality(getRealityProps(true));
            Enslaved.initializeRun();
        } catch (e) { enslavedLog(e); }
    };

    globalThis._nativeBuyEnslavedUnlock = function (id) {
        try {
            if (typeof ENSLAVED_UNLOCKS === "undefined" || typeof Enslaved === "undefined") return;
            var entries = Object.values(ENSLAVED_UNLOCKS);
            for (var i = 0; i < entries.length; i++) {
                if (entries[i].id === id) {
                    Enslaved.buyUnlock(entries[i]);
                    return;
                }
            }
        } catch (e) { enslavedLog(e); }
    };

    globalThis._nativeToggleEnslavedStoreBH = function () {
        try { if (typeof Enslaved !== "undefined") Enslaved.toggleStoreBlackHole(); }
        catch (e) { enslavedLog(e); }
    };

    globalThis._nativeToggleEnslavedStoreReal = function () {
        try { if (typeof Enslaved !== "undefined") Enslaved.toggleStoreReal(); }
        catch (e) { enslavedLog(e); }
    };

    globalThis._nativeToggleEnslavedAutoStoreReal = function () {
        try { if (typeof Enslaved !== "undefined") Enslaved.toggleAutoStoreReal(); }
        catch (e) { enslavedLog(e); }
    };

    globalThis._nativeEnslavedUseStored = function () {
        try { if (typeof Enslaved !== "undefined") Enslaved.useStoredTime(false); }
        catch (e) { enslavedLog(e); }
    };

    // Reality Amplify — `Enslaved.boostReality` toggle. When on, the next
    // Reality you complete is amplified — its rewards are multiplied by
    // `Enslaved.realityBoostRatio`, in exchange for spending stored real time.
    // Mirrors `RealityAmplifyButton.vue`.
    globalThis._nativeEnslavedAmplifyState = function () {
        try {
            if (typeof Enslaved === "undefined") return JSON.stringify({ ready: false });
            var inCelestialReality = (typeof isInCelestialReality === "function") && !!isInCelestialReality();
            return JSON.stringify({
                ready: true,
                isUnlocked: !!Enslaved.isUnlocked,
                canAmplify: !!Enslaved.canAmplify,
                isActive: !!Enslaved.boostReality,
                ratio: Enslaved.realityBoostRatio || 0,
                isInCelestialReality: inCelestialReality
            });
        } catch (e) {
            enslavedLog(e);
            return JSON.stringify({ ready: false });
        }
    };

    globalThis._nativeToggleEnslavedAmplify = function () {
        try {
            if (typeof Enslaved === "undefined") return;
            // Web's RealityAmplifyButton click handler short-circuits when
            // amplify is already on (always lets you toggle off) but gates
            // turning it on behind canAmplify.
            if (!Enslaved.boostReality && !Enslaved.canAmplify) return;
            Enslaved.boostReality = !Enslaved.boostReality;
        } catch (e) { enslavedLog(e); }
    };

    globalThis._nativeSetEnslavedNegativeSlider = function (value) {
        try {
            var v = Math.max(0, Math.min(300, Number(value) || 0));
            player.blackHoleNegative = Math.pow(10, -v);
            if (player.requirementChecks && player.requirementChecks.reality) {
                player.requirementChecks.reality.slowestBH = Math.max(
                    player.requirementChecks.reality.slowestBH,
                    player.blackHoleNegative
                );
            }
        } catch (e) { enslavedLog(e); }
    };

    // Debug cheats (always defined; Swift gates the calls behind #if DEBUG).
    globalThis._nativeDevAddEnslavedYears = function (years) {
        try {
            var ms = TimeSpan.fromYears(Number(years) || 0).totalMilliseconds;
            if (!player.celestials.enslaved) return;
            player.celestials.enslaved.stored = (player.celestials.enslaved.stored || 0) + ms;
        } catch (e) { enslavedLog(e); }
    };

    globalThis._nativeDevResetEnslavedTime = function () {
        try { if (player.celestials.enslaved) player.celestials.enslaved.stored = 0; }
        catch (e) { enslavedLog(e); }
    };

    // ---- Enslaved: speedrun-path actions ---------------------------------

    // Award 100 TT + mark the secret study claimed. Mirrors
    // EnslavedTimeStudy.vue:39-44 exactly. Early-returns when not inside
    // the run or already claimed — prevents double-dipping through a
    // delayed tap or race with an ongoing reality reset.
    globalThis._nativeClaimEnslavedSecretStudy = function () {
        try {
            if (typeof Enslaved === "undefined") return;
            if (!Enslaved.isRunning) return;
            if (player.celestials.enslaved.hasSecretStudy) return;
            player.celestials.enslaved.hasSecretStudy = true;
            if (typeof EnslavedProgress !== "undefined"
                && EnslavedProgress.secretStudy
                && typeof EnslavedProgress.secretStudy.giveProgress === "function") {
                EnslavedProgress.secretStudy.giveProgress();
            }
            Currency.timeTheorems.add(100);
        } catch (e) { enslavedLog(e); }
    };

    // Feel Eternity — delegates straight to the game-core method, which
    // handles both the first-time unlock (EnslavedProgress.feelEternity)
    // and the repeat-message branches via Modal.message.show(). Our
    // _nativeMessage bridge surfaces that as a SwiftUI alert automatically.
    globalThis._nativeEnslavedFeelEternity = function () {
        try { if (typeof Enslaved !== "undefined") Enslaved.feelEternity(); }
        catch (e) { enslavedLog(e); }
    };

    // ---- Enslaved hints modal --------------------------------------------

    // Lambert-W based estimate of time-to-afford the next hint at the
    // current charging rate. Mirrors EnslavedHintsModal.vue:35-56.
    function _enslavedHintTimeEstimate(currentStored, nextHintCost, hintCostIncreases) {
        if (currentStored >= nextHintCost) return "";
        var storeRate;
        try {
            storeRate = 1000 * (Enslaved.isStoringGameTime
                ? Enslaved.currentBlackHoleStoreAmountPerMs
                : getGameSpeedupFactor());
        } catch (e) { storeRate = 0; }
        if (!isFinite(storeRate) || storeRate <= 0) return "";
        var alreadyWaited = currentStored / storeRate;
        var decaylessTime = nextHintCost / storeRate;
        // Fast path — if decay won't matter, just return the naive linear estimate.
        var minCostEstimate = (TimeSpan.fromYears(1e40).totalMilliseconds - currentStored) / storeRate;
        if (TimeSpan.fromSeconds(minCostEstimate).totalDays > hintCostIncreases) {
            return TimeSpan.fromSeconds(minCostEstimate).toStringShort(true);
        }
        // Full Lambert-W calculation with 3x-per-day decay baked in.
        try {
            var K = Math.pow(3, 1 / 86400);
            var x = decaylessTime * Math.log(K) * Math.pow(K, alreadyWaited);
            var timeToGoal = productLog(x) / Math.log(K) - alreadyWaited;
            return TimeSpan.fromSeconds(timeToGoal).toStringShort(true);
        } catch (e) { return ""; }
    }

    globalThis._nativeEnslavedHintsState = function () {
        try {
            if (typeof Enslaved === "undefined" || typeof EnslavedProgress === "undefined") {
                return JSON.stringify({ ready: false });
            }

            var hasRun = Enslaved.has(ENSLAVED_UNLOCKS.RUN);
            var hintsUnlockedProgress = !!EnslavedProgress.hintsUnlocked.hasProgress;
            var canShow = hasRun && !Enslaved.isCompleted && hintsUnlockedProgress;

            var realityEntries = [];
            var unlockedCount = 0;
            var all = EnslavedProgress.all;
            for (var i = 0; i < all.length; i++) {
                var p = all[i];
                var hasHint = !!p.hasHint;
                if (hasHint) unlockedCount++;
                // Serialise hint + condition strings (some are functions).
                var hint = "", cond = "";
                try {
                    hint = typeof p.hintInfo === "function" ? p.hintInfo() : (p.hintInfo || "");
                } catch (e) {}
                try {
                    cond = typeof p.completedInfo === "function" ? p.completedInfo() : (p.completedInfo || "");
                } catch (e) {}
                realityEntries.push({
                    id: p.id,
                    hint: String(hint).replace(/\s+/g, " ").trim(),
                    condition: String(cond).replace(/\s+/g, " ").trim(),
                    hasHint: hasHint,
                    hasProgress: !!p.hasProgress
                });
            }

            var glyphHintsCfg = GameDatabase.celestials.enslaved.glyphHints || [];
            var glyphHintsGiven = Math.max(0, Math.min(glyphHintsCfg.length,
                (player.celestials.enslaved.glyphHintsGiven | 0)));
            var glyphHints = [];
            for (var gi = 0; gi < glyphHintsGiven; gi++) {
                glyphHints.push(String(glyphHintsCfg[gi] || "").replace(/\s+/g, " ").trim());
            }

            var stored = player.celestials.enslaved.stored || 0;
            var nextCost = Enslaved.nextHintCost;
            var costIncreases = Enslaved.hintCostIncreases | 0;

            return JSON.stringify({
                ready: true,
                canShowHintsButton: canShow,
                realityHintsUnlocked: unlockedCount,
                realityHintsTotal: all.length,
                glyphHintsGiven: glyphHintsGiven,
                glyphHintsTotal: glyphHintsCfg.length,
                realityEntries: realityEntries,
                glyphHints: glyphHints,
                allRealityHintsShown: unlockedCount >= all.length,
                allGlyphHintsShown: glyphHintsGiven >= glyphHintsCfg.length,
                nextHintCostText: timeDisplayShort(nextCost),
                canAffordHint: stored >= nextCost,
                timeToNextHintText: _enslavedHintTimeEstimate(stored, nextCost, costIncreases),
                hintCostIncreases: costIncreases
            });
        } catch (e) {
            enslavedLog(e);
            return JSON.stringify({ ready: false });
        }
    };

    globalThis._nativeSpendTimeForRealityHint = function () {
        try {
            if (typeof Enslaved === "undefined") return;
            if (!Enslaved.spendTimeForHint()) return;
            // Pick a random unshown entry and unlock() its hint — same as web.
            var locked = EnslavedProgress.all.filter(function (p) { return !p.hasHint; });
            if (locked.length && typeof locked[0].unlock === "function") {
                var pick = locked[Math.floor(Math.random() * locked.length)];
                pick.unlock();
            }
        } catch (e) { enslavedLog(e); }
    };

    globalThis._nativeSpendTimeForGlyphHint = function () {
        try {
            if (typeof Enslaved === "undefined") return;
            if (!Enslaved.spendTimeForHint()) return;
            var max = (GameDatabase.celestials.enslaved.glyphHints || []).length;
            var cur = player.celestials.enslaved.glyphHintsGiven | 0;
            if (cur < max) player.celestials.enslaved.glyphHintsGiven = cur + 1;
        } catch (e) { enslavedLog(e); }
    };

    // ---- Tesseracts --------------------------------------------------------

    globalThis._nativeTesseractState = function () {
        try {
            if (!has(Tesseracts) || !has(Enslaved) || !Enslaved.isCompleted) return "null";
            return JSON.stringify({
                bought: Tesseracts.bought,
                extra: Tesseracts.extra,
                nextCost: format(Tesseracts.nextCost, 2, 2),
                canBuy: Tesseracts.canBuyTesseract,
                nextCapIncrease: format(Tesseracts.nextTesseractIncrease, 2, 2),
                totalCap: format(Tesseracts.capIncrease(), 2, 2)
            });
        } catch (e) { return "null"; }
    };

    globalThis._nativeBuyTesseract = function () {
        try { if (has(Tesseracts)) Tesseracts.buyTesseract(); } catch (e) {}
    };

    // ---- V — The Celestial of Achievements ---------------------------------

    function vLog(e) {
        if (typeof _nativeLog === "function") _nativeLog("[V] " + e);
    }

    globalThis._nativeVState = function () {
        try {
            if (!has(V) || !has(VUnlocks) || !has(VRunUnlocks)) return "null";

            // Unlock requirements (pre-unlock)
            // mainUnlock is an object keyed by name, not an array.
            // Each entry: { name, resource() → current value, requirement → goal number,
            //               format(x), progress() → 0..1 fraction }
            var reqs = [];
            var db = GameDatabase.celestials.v.mainUnlock;
            var keys = Object.keys(db);
            for (var i = 0; i < keys.length; i++) {
                var r = db[keys[i]];
                var currentVal = r.resource();  // function call → Decimal or number
                var goalVal = r.requirement;    // plain number (e.g. 10000, 1e70)
                var prog = r.progress();        // 0..1 fraction (already emphasizeEnd'd)
                // Format current + goal using the entry's own format() if available
                var currentStr = r.format ? r.format(currentVal) : format(currentVal, 2);
                var goalStr = r.format ? r.format(goalVal) : format(goalVal, 2);
                // isMet: compare Decimal or number
                var met = false;
                if (currentVal && typeof currentVal.gte === "function") {
                    met = currentVal.gte(goalVal);
                } else {
                    met = Number(currentVal) >= Number(goalVal);
                }
                reqs.push({
                    id: i,
                    name: r.name,
                    current: currentStr,
                    goal: goalStr,
                    progress: Math.min(1, Math.max(0, isFinite(prog) ? prog : 0)),
                    isMet: met
                });
            }

            // Achievements (9 total: 0-5 normal, 6-8 hard)
            var achs = [];
            var allUnlocks = VRunUnlocks.all;
            for (var j = 0; j < allUnlocks.length; j++) {
                var h = allUnlocks[j];
                if (!h || !h.config) continue;
                var cfg = h.config;
                var isHard = cfg.isHard || false;
                var comp = h.completions;
                var maxComp = cfg.values.length;
                var atMax = comp >= maxComp;
                var goalVal = atMax ? cfg.values[maxComp - 1] : cfg.values[comp];
                // Description with current goal value. Several V configs
                // (e.g. "Post-destination" at v.js:163) span a multi-line
                // JS template literal — the embedded `\n` + source indentation
                // bakes a hard line break + whitespace run into iOS's Text
                // and burns a lineLimit row for nothing. Normalize via
                // normText so the description natural-wraps to the hex width.
                var desc = "";
                try { desc = normText(cfg.description(goalVal)); } catch (e2) { desc = cfg.name; }
                // Record
                var rec = "";
                try {
                    var rawRec = player.celestials.v.runRecords[h.id];
                    if (rawRec !== undefined && (rawRec > 0 || (h.id === 0 && rawRec > -10) || (h.id === 6 && rawRec > -10))) {
                        rec = cfg.formatRecord(rawRec);
                    }
                } catch (e3) {}
                // Reduction info
                var canReduce = VUnlocks.shardReduction.isUnlocked && !atMax;
                var redCost = "";
                var redMode = "";
                var redValue = "";
                var isReduced = false;
                try {
                    var steps = (player.celestials.v.goalReductionSteps || [])[h.id] || 0;
                    isReduced = steps > 0;
                } catch (eRed) {}
                try {
                    if (canReduce) {
                        redCost = format(h.reductionCost, 2, 0);
                        redMode = (cfg.mode === 0) ? "reduced" : "divided";
                        redValue = (cfg.mode === 0)
                            ? formatInt(h.reduction)
                            : format(Decimal.pow10(h.reduction));
                    } else if (isReduced) {
                        // Display still needs mode/value when reduction is no
                        // longer purchasable (e.g. fully completed) so the
                        // "Goal has been ... by ..." line keeps rendering.
                        redMode = (cfg.mode === 0) ? "reduced" : "divided";
                        redValue = (cfg.mode === 0)
                            ? formatInt(h.reduction)
                            : format(Decimal.pow10(h.reduction));
                    }
                } catch (e4) {}
                // Hex color (white → golden gradient based on completions)
                var hexColor;
                if (atMax) {
                    hexColor = "#ead584";
                } else {
                    hexColor = "rgb(" + (255 - 5 * comp) + "," + (255 - 10 * comp) + "," + (255 - 20 * comp) + ")";
                }

                // Per-achievement Glyph Set (web VTab.vue:253 — the
                // `<GlyphSetPreview :glyphs="runGlyphs[hex.id]" />`).
                // Surfaced for iOS long-press → glyph set sheet.
                var glyphSet = [];
                try {
                    var rg = (player.celestials.v.runGlyphs || [])[h.id];
                    if (rg && rg.length) {
                        for (var gi = 0; gi < rg.length; gi++) {
                            var rec2 = serializeGlyphRecord(rg[gi], gi);
                            if (rec2) glyphSet.push(rec2);
                        }
                    }
                } catch (eGs) {}

                achs.push({
                    id: j,
                    name: cfg.name,
                    description: desc,
                    completions: comp,
                    maxCompletions: maxComp,
                    isHard: isHard,
                    rewardPerCompletion: isHard ? 2 : 1,
                    record: rec,
                    canReduce: canReduce,
                    reductionCost: redCost,
                    reductionMode: redMode,
                    reductionValue: redValue,
                    isReduced: isReduced,
                    isFullyCompleted: atMax,
                    hexColor: hexColor,
                    glyphSet: glyphSet
                });
            }

            // Milestones (6 V-Unlocks)
            var miles = [];
            var unlockKeys = ["shardReduction", "adPow", "fastAutoEC", "autoAutoClean", "achievementBH", "raUnlock"];
            for (var k = 0; k < unlockKeys.length; k++) {
                var u = VUnlocks[unlockKeys[k]];
                if (!u) continue;
                // formattedEffect: "Currently: X" line (e.g. shardReduction
                // shows the active discount). Mirrors web `milestone.formattedEffect`.
                var fmtEff = "";
                try {
                    if (typeof u.formattedEffect === "string") {
                        fmtEff = u.formattedEffect;
                    } else if (typeof u.formattedEffect === "function") {
                        fmtEff = u.formattedEffect();
                    } else if (u.config && typeof u.config.formatEffect === "function" && typeof u.config.effect === "function") {
                        fmtEff = u.config.formatEffect(u.config.effect());
                    }
                } catch (eFmt) { fmtEff = ""; }

                miles.push({
                    id: k,
                    description: normText(u.description || (u.config && u.config.description)),
                    reward: normText(u.rewardText || u.reward || (u.config && u.config.reward)),
                    formattedEffect: normText(fmtEff || ""),
                    stRequired: u.requirement,
                    isReached: u.isUnlocked
                });
            }

            // Pre-unlock V button copy (Vue VTab.vue:179-180 reads
            // `vUnlock.description` + `vUnlock.rewardText` directly from
            // the VUnlocks.vAchievementUnlock config).
            var vBtnDesc = "";
            var vBtnReward = "";
            try {
                var vUn = VUnlocks.vAchievementUnlock;
                if (vUn) {
                    vBtnDesc = normText(vUn.description || (vUn.config && vUn.config.description) || "");
                    vBtnReward = normText(vUn.rewardText || vUn.reward || (vUn.config && (vUn.config.rewardText || vUn.config.reward)) || "");
                }
            } catch (eBtn) {}

            // Run description
            var runDesc = "";
            try {
                runDesc = normText(GameDatabase.celestials.descriptions[3].effects);
                runDesc = runDesc.replace(/^\w/u, function (c) { return c.toUpperCase(); });
            } catch (e5) {}

            return JSON.stringify({
                isUnlocked: VUnlocks.vAchievementUnlock.isUnlocked,
                isRunning: V.isRunning,
                canUnlockCelestial: V.canUnlockCelestial,
                requirements: reqs,
                spaceTheorems: V.spaceTheorems,
                ppAvailable: format(Currency.perkPoints.value, 2, 0),
                showReduction: VUnlocks.shardReduction.isUnlocked,
                achievements: achs,
                milestones: miles,
                isFlipped: V.isFlipped,
                wantsFlipped: player.celestials.v.wantsFlipped,
                runDescription: runDesc,
                hasAlchemy: has(Ra) && Ra.unlocks.unlockGlyphAlchemy.canBeApplied,
                unlockButtonDescription: vBtnDesc,
                unlockButtonReward: vBtnReward
            });
        } catch (e) {
            vLog(e);
            return "null";
        }
    };

    globalThis._nativeUnlockV = function () {
        try { if (has(V) && V.canUnlockCelestial) V.unlockCelestial(); } catch (e) { vLog(e); }
    };

    globalThis._nativeStartVRun = function () {
        try {
            if (has(V)) {
                beginProcessReality(getRealityProps(true));
                V.initializeRun();
            }
        } catch (e) { vLog(e); }
    };

    globalThis._nativeReduceVGoal = function (achId) {
        try {
            var hex = VRunUnlocks.all[achId];
            if (!hex) return;
            if (!Currency.perkPoints.purchase(hex.reductionCost)) return;
            var steps = hex.config.reductionStepSize ? hex.config.reductionStepSize : 1;
            player.celestials.v.goalReductionSteps[hex.id] += steps;
            for (var u of VRunUnlocks.all) u.tryComplete();
            V.checkForUnlocks();
        } catch (e) { vLog(e); }
    };

    globalThis._nativeToggleVFlipped = function () {
        try { player.celestials.v.wantsFlipped = !player.celestials.v.wantsFlipped; } catch (e) { vLog(e); }
    };

    // ---- V Debug Cheats (called from Swift #if DEBUG) ----------------------

    // Complete one tier of a specific V-Achievement
    globalThis._nativeDevCompleteVAchievement = function (achId) {
        try {
            var hex = VRunUnlocks.all[achId];
            if (!hex) return "invalid";
            if (hex.completions >= hex.config.values.length) return "maxed";
            player.celestials.v.runRecords[achId] = hex.conditionValue;
            player.celestials.v.runGlyphs[achId] = Glyphs.copyForRecords(
                Glyphs.active.filter(function (g) { return g !== null; })
            );
            hex.tryComplete();
            V.updateTotalRunUnlocks();
            V.checkForUnlocks();
            return "ok:" + hex.completions;
        } catch (e) { vLog(e); return "error"; }
    };

    // Max all tiers of a specific V-Achievement
    globalThis._nativeDevMaxVAchievement = function (achId) {
        try {
            var hex = VRunUnlocks.all[achId];
            if (!hex) return "invalid";
            var max = hex.config.values.length;
            while (hex.completions < max) {
                player.celestials.v.runRecords[achId] = hex.conditionValue;
                player.celestials.v.runGlyphs[achId] = Glyphs.copyForRecords(
                    Glyphs.active.filter(function (g) { return g !== null; })
                );
                hex.tryComplete();
            }
            V.updateTotalRunUnlocks();
            V.checkForUnlocks();
            return "ok:" + hex.completions;
        } catch (e) { vLog(e); return "error"; }
    };

    // Max all 6 normal V-Achievements (IDs 0-5) → 36 ST
    globalThis._nativeDevCompleteAllNormalVAchievements = function () {
        try {
            for (var i = 0; i < 6; i++) _nativeDevMaxVAchievement(i);
            return "ok:" + V.spaceTheorems + " ST";
        } catch (e) { vLog(e); return "error"; }
    };

    // Max all 9 V-Achievements including hard (IDs 0-8) → 66 ST
    globalThis._nativeDevCompleteAllVAchievements = function () {
        try {
            for (var i = 0; i < 9; i++) _nativeDevMaxVAchievement(i);
            return "ok:" + V.spaceTheorems + " ST";
        } catch (e) { vLog(e); return "error"; }
    };

    // Force all 6 V unlock requirements to be met
    globalThis._nativeDevForceVRequirements = function () {
        try {
            Currency.realities.bumpTo(10000);
            Currency.eternities.bumpTo(new Decimal("1e70"));
            Currency.infinities.bumpTo(new Decimal("1e160"));
            Currency.dilatedTime.bumpTo(new Decimal("1e320"));
            Currency.replicanti.bumpTo(new Decimal("1e320000"));
            Currency.realityMachines.bumpTo(new Decimal("1e60"));
            return "ok";
        } catch (e) { vLog(e); return "error"; }
    };

    // ======================================================================
    // Ra / Laitela / V — navigation sub-trees + Ra state bridge
    // Ported from src/core/secret-formula/celestials/navigation.js lines 695–1805.
    // Each push matches the web node's `visible` / `complete` / `legend` logic.
    // ======================================================================

    function vis_vAchievementUnlocked() {
        return has(VUnlocks) && VUnlocks.vAchievementUnlock && VUnlocks.vAchievementUnlock.isUnlocked;
    }
    function vis_achievement151OrVUnlocked() {
        try {
            if (vis_vAchievementUnlocked()) return true;
            return has(Achievement) && Achievement(151).isUnlocked;
        } catch (e) { return false; }
    }
    function vis_laitelaUnlocked() {
        return has(Laitela) && Laitela.isUnlocked;
    }
    function vis_laitelaDMD2Unlocked() {
        try { return has(DarkMatterDimension) && DarkMatterDimension(2).isUnlocked && Currency.singularities.gte(1); }
        catch (e) { return false; }
    }
    function vis_laitelaDMD3Unlocked() {
        try { return has(DarkMatterDimension) && DarkMatterDimension(3).isUnlocked; }
        catch (e) { return false; }
    }
    function vis_laitelaDMD4Unlocked() {
        try { return has(DarkMatterDimension) && DarkMatterDimension(4).isUnlocked; }
        catch (e) { return false; }
    }
    function vis_laitelaAnnihilationBought() {
        try { return has(DarkMatterDimension) && DarkMatterDimension(4).isUnlocked && has(ImaginaryUpgrade) && ImaginaryUpgrade(19).isBought; }
        catch (e) { return false; }
    }
    function vis_raEffarigUnlocked() { return has(Ra) && Ra.unlocks && Ra.unlocks.effarigUnlock && Ra.unlocks.effarigUnlock.isUnlocked; }
    function vis_raEnslavedUnlocked() { return has(Ra) && Ra.unlocks && Ra.unlocks.enslavedUnlock && Ra.unlocks.enslavedUnlock.isUnlocked; }
    function vis_raVPetUnlocked() { return has(Ra) && Ra.unlocks && Ra.unlocks.vUnlock && Ra.unlocks.vUnlock.isUnlocked; }

    function safeComplete(fn) {
        try { var v = fn(); if (!isFinite(v)) return 0; return Math.min(1, Math.max(0, v)); }
        catch (e) { return 0; }
    }

    // ---- V sub-tree ----------------------------------------------------

    // Spokes inherit the parent v-unlock-achievement gate (vis_effarigRealityCompleted)
    // in addition to their own progress condition. Achievement(151) can fire long before
    // V is reachable, so the spokes would otherwise render orphaned without their parent
    // node — see the comment on the v-unlock-achievement entry above.
    function vis_vUnlockSpokes() {
        return vis_effarigRealityCompleted() && vis_achievement151OrVUnlocked();
    }

    for (var vi = 1; vi <= 6; vi++) {
        (function (index) {
            navNodes.push({
                id: "v-unlock-" + index,
                visible: vis_vUnlockSpokes,
                complete: function () {
                    try {
                        if (vis_vAchievementUnlocked()) return 1;
                        return safeComplete(function () { return vUnlockProgress(index); });
                    } catch (e) { return 0; }
                },
                legend: function (c) {
                    try { return vUnlockLegendLabel(c, index) || ""; }
                    catch (e) { return ""; }
                }
            });
        })(vi);
    }

    var vAchievementNames = ["Double Galaxy", "No DB", "No Glyphs", "Eternity Count",
                             "Dilation", "Replicanti Galaxy", "Hard-0", "Hard-1", "Hard-2"];
    for (var vai = 0; vai < 9; vai++) {
        (function (index) {
            navNodes.push({
                id: "v-achievement-" + index,
                visible: function () { return vis_vAchievementUnlocked(); },
                complete: function () {
                    try {
                        var a = VRunUnlocks.all[index];
                        if (!a) return 0;
                        return Math.min(1, (a.completions || 0) / 6);
                    } catch (e) { return 0; }
                },
                legend: function (c) {
                    try {
                        var a = VRunUnlocks.all[index];
                        if (!a) return "V-Achievement";
                        var name = (a.config && a.config.name) || vAchievementNames[index] || "V-Achievement";
                        if (c >= 1) return "V-Achievement \"" + name + "\"";
                        var comp = a.completions || 0;
                        return "Reach " + formatInt(comp) + " / " + formatInt(6) + " in " + name;
                    } catch (e) { return "V-Achievement"; }
                }
            });
        })(vai);
    }

    // ---- Ra sub-tree (4 pets + 5 rings) --------------------------------

    var RA_PETS = [
        { key: "teresa",   name: "Teresa",         prevKey: null,        unlockFn: vis_raUnlocked },
        { key: "effarig",  name: "Effarig",        prevKey: "teresa",    unlockFn: vis_raEffarigUnlocked },
        { key: "enslaved", name: "Nameless",       prevKey: "effarig",   unlockFn: vis_raEnslavedUnlocked },
        { key: "v",        name: "V",              prevKey: "enslaved",  unlockFn: vis_raVPetUnlocked }
    ];

    for (var rpi = 0; rpi < RA_PETS.length; rpi++) {
        (function (pet) {
            navNodes.push({
                id: "ra-pet-" + pet.key,
                // First pet (Teresa) visible on Ra unlock; others gated by the previous pet's unlock.
                visible: pet.prevKey === null ? vis_raUnlocked : function () { return pet.unlockFn(); },
                complete: function () {
                    try {
                        if (!has(Ra)) return 0;
                        if (pet.prevKey === null) return pet.unlockFn() ? 1 : 0;
                        // Progress is the PREVIOUS pet's level / 8 until our own unlock fires.
                        if (!pet.unlockFn()) {
                            var prev = Ra.pets[pet.prevKey];
                            return prev ? Math.min(1, prev.level / 8) : 0;
                        }
                        return 1;
                    } catch (e) { return 0; }
                },
                legend: function (c) {
                    try {
                        if (!has(Ra)) return "Ra's " + pet.name;
                        var myPet = Ra.pets[pet.key];
                        if (!myPet) return "Ra's " + pet.name;
                        if (c < 1) {
                            var prev = pet.prevKey ? Ra.pets[pet.prevKey] : null;
                            if (prev) return "Ra's " + (pet.prevKey === "enslaved" ? "Nameless" :
                                prev.name || pet.prevKey) + " Memory level " + formatInt(prev.level) + " / " + formatInt(8);
                        }
                        if (myPet.level === 25) return "Ra's " + pet.name + " Memories have all been returned";
                        return "Ra's " + pet.name + " Memory level " + formatInt(myPet.level) + " / " + formatInt(25);
                    } catch (e) { return "Ra's " + pet.name; }
                }
            });
        })(RA_PETS[rpi]);
    }

    for (var rri = 1; rri <= 5; rri++) {
        navNodes.push({
            id: "ra-ring-" + rri,
            visible: vis_raUnlocked,
            complete: function () { return vis_raUnlocked() ? 1 : 0; },
            legend: function () { return ""; }
        });
    }

    // ---- Laitela sub-tree (6 dimensional nodes) ------------------------

    navNodes.push({
        id: "laitela-2nd-dim",
        visible: vis_laitelaUnlocked,
        complete: function () {
            try {
                var up = DarkMatterDimension(2).unlockUpgrade;
                if (up.canBeBought || up.isBought) return 1;
                if (up.isAvailableForPurchase) return Math.min(1, up.currency.value / up.cost);
                return Laitela.difficultyTier < 1 ? 0 :
                    Math.min(1, 30 / (player.celestials.laitela.fastestCompletion || 1e9));
            } catch (e) { return 0; }
        },
        legend: function (c) {
            try {
                var dim = DarkMatterDimension(2);
                if (dim.isUnlocked) return "2nd Dark Matter Dimension";
                if (c >= 1) return "2nd DMD — ready to unlock";
                return "Unlock the 2nd Dark Matter Dimension";
            } catch (e) { return "2nd Dark Matter Dimension"; }
        }
    });
    navNodes.push({
        id: "laitela-singularity",
        visible: vis_laitelaUnlocked,
        complete: function () {
            try {
                if (Currency.singularities.gte(1)) return 1;
                return Math.min(0.999, Currency.darkEnergy.value / Singularity.cap);
            } catch (e) { return 0; }
        },
        legend: function (c) {
            try {
                if (c >= 1) return "Obtain a Singularity";
                return "Condense Dark Energy — " + format(Currency.darkEnergy.value, 2) + " / " + format(Singularity.cap, 2);
            } catch (e) { return "Singularity"; }
        }
    });
    navNodes.push({
        id: "laitela-3rd-dim",
        visible: vis_laitelaDMD2Unlocked,
        complete: function () {
            try {
                var up = DarkMatterDimension(3).unlockUpgrade;
                if (up.canBeBought || up.isBought) return 1;
                if (up.isAvailableForPurchase) return Math.min(1, up.currency.value / up.cost);
                if (!player.auto.singularity.isActive) return 0.5;
                return Math.min(0.999, Singularity.singularitiesGained / 20);
            } catch (e) { return 0; }
        },
        legend: function (c) {
            try {
                if (DarkMatterDimension(3).isUnlocked) return "3rd Dark Matter Dimension";
                if (c >= 1) return "3rd DMD — ready to unlock";
                return "Unlock the 3rd Dark Matter Dimension";
            } catch (e) { return "3rd Dark Matter Dimension"; }
        }
    });
    navNodes.push({
        id: "laitela-4th-dim",
        visible: vis_laitelaDMD3Unlocked,
        complete: function () {
            try {
                var up = DarkMatterDimension(4).unlockUpgrade;
                if (up.canBeBought || up.isBought) return 1;
                if (up.isAvailableForPurchase) return Math.min(1, up.currency.value / up.cost);
                var all = (Replicanti.galaxies.total || 0) + (player.galaxies || 0) + (player.dilation.totalTachyonGalaxies || 0);
                return Math.min(1, all / 80000);
            } catch (e) { return 0; }
        },
        legend: function (c) {
            try {
                if (DarkMatterDimension(4).isUnlocked) return "4th Dark Matter Dimension";
                if (c >= 1) return "4th DMD — ready to unlock";
                return "Have " + format(80000) + " total Galaxies";
            } catch (e) { return "4th Dark Matter Dimension"; }
        }
    });
    navNodes.push({
        id: "laitela-annihilation",
        visible: vis_laitelaDMD4Unlocked,
        complete: function () {
            try {
                var up = ImaginaryUpgrade(19);
                if (up.canBeBought || up.isBought) return 1;
                if (up.isAvailableForPurchase) return Math.min(1, Currency.imaginaryMachines.value / up.cost);
                return up.isPossible ? Math.min(1, Tickspeed.continuumValue / 3850000) : 0;
            } catch (e) { return 0; }
        },
        legend: function () { return "Annihilate your Dark Matter Dimensions"; }
    });
    navNodes.push({
        id: "laitela-destabilization",
        visible: vis_laitelaAnnihilationBought,
        complete: function () {
            try { return Math.min(1, (Laitela.difficultyTier || 0) / 8); }
            catch (e) { return 0; }
        },
        legend: function (c) {
            try {
                if (c >= 1) return "Lai'tela's Reality completely destabilized";
                return "Destabilize Lai'tela's Reality — " + format(Laitela.difficultyTier) + " / " + format(8) + " Dimensions disabled";
            } catch (e) { return "Destabilize Lai'tela's Reality"; }
        }
    });

    // ---- Ra state bridge ----------------------------------------------

    // Map each unlock's Font Awesome / Unicode displayIcon to a renderable token.
    // "sf:<name>" → Swift renders SF Symbol. "unicode:<char>" → Swift renders Text(char).
    var RA_ICON_MAP = {
        // Teresa line
        "atom": "sf:atom",
        "infinity": "sf:infinity",
        "bolt": "sf:bolt.fill",
        "project-diagram": "sf:chart.bar.doc.horizontal",
        "dot-circle": "sf:smallcircle.filled.circle",
        // Effarig line
        "grip-horizontal": "sf:ellipsis",
        "vial": "sf:testtube.2",
        "clone": "sf:square.on.square",
        "braille": "sf:circle.grid.3x3.fill",
        "fire": "sf:flame.fill",
        "ankh": "sf:cross",
        // Enslaved line
        "circle": "sf:circle.fill",
        "history": "sf:clock.arrow.circlepath",
        "stopwatch": "sf:stopwatch.fill",
        "expand-arrows-alt": "sf:arrow.up.left.and.arrow.down.right",
        "tachometer-alt": "sf:gauge.with.dots.needle.67percent",
        "clock": "sf:clock.fill",
        // V line
        "sync-alt": "sf:arrow.triangle.2.circlepath",
        "fast-forward": "sf:forward.fill",
        "book": "sf:book.fill",
        "trophy": "sf:trophy.fill",
        "university": "sf:building.columns.fill",
        "graduation-cap": "sf:graduationcap.fill",
        "buffer": "sf:square.stack.3d.up.fill",
        // Shared
        "crown": "sf:crown.fill",
        "star": "sf:star.fill",
        "sun": "sf:sun.max.fill",
        // Fallback when web uses a Unicode-literal glyph
        "Ϟ": "unicode:Ϟ",
        "Ϙ": "unicode:Ϙ",
        "⌬": "unicode:⌬"
    };

    function raIconToken(config) {
        var di = config.displayIcon || "";
        // Unicode literal → pass through.
        if (di && di.length <= 4 && /[^\s<]/.test(di) && di.indexOf("<") === -1) {
            return "unicode:" + di;
        }
        // Font Awesome <span class="fas fa-XXX"> or <i class="fa-YYY">
        var m = /fa-([a-z0-9-]+)/i.exec(di);
        if (m) {
            var key = m[1];
            return RA_ICON_MAP[key] || "sf:questionmark.circle";
        }
        // Special chain glyph for effarig unlock (\uf0c1).
        if (di.indexOf("link") !== -1 || di.indexOf("\\uf0c1") !== -1 || di.indexOf("\uf0c1") !== -1) {
            return "sf:link";
        }
        return "sf:star.circle";
    }

    function raBuildUnlockList(petKey) {
        try {
            if (!has(Ra) || !Ra.unlocks || !Ra.unlocks.all) return [];
            var out = [];
            for (var i = 0; i < Ra.unlocks.all.length; i++) {
                var u = Ra.unlocks.all[i];
                if (!u || !u.pet || u.pet.config.id !== petKey) continue;
                out.push({
                    id: u.config.id,
                    pet: petKey,
                    level: u.config.level,
                    reward: normText(u.config.reward),
                    iconToken: raIconToken(u.config),
                    isUnlocked: !!u.isUnlocked,
                    disabledByPelle: !!u.disabledByPelle
                });
            }
            out.sort(function (a, b) { return a.level - b.level; });
            return out;
        } catch (e) { return []; }
    }

    function raNextUnlockText(petKey, level) {
        try {
            if (!has(Ra) || !Ra.unlocks || !Ra.unlocks.all) return "";
            var best = null;
            for (var i = 0; i < Ra.unlocks.all.length; i++) {
                var u = Ra.unlocks.all[i];
                if (!u || !u.pet || u.pet.config.id !== petKey) continue;
                if (u.config.level <= level) continue;
                if (!best || u.config.level < best.config.level) best = u;
            }
            if (!best) return "";
            return "At level " + formatInt(best.config.level) + ": " + normText(best.config.reward);
        } catch (e) { return ""; }
    }

    function raTimeToAffordUpgrade(pet, cost) {
        try {
            var mps = pet.memoryChunks * Ra.productionPerMemoryChunk * pet.memoryUpgradeCurrentMult;
            if (!isFinite(mps) || mps <= 0) return "";
            if (pet.memories >= cost) return "";
            var remain = cost - pet.memories;
            var secs = remain / mps;
            if (!isFinite(secs) || secs <= 0) return "";
            return "in " + TimeSpan.fromSeconds(secs).toStringShort();
        } catch (e) { return ""; }
    }

    function raBuildPet(petKey, displayName, chunkGain, memoryGain, prevKey) {
        try {
            if (!has(Ra) || !Ra.pets || !Ra.pets[petKey]) return null;
            var p = Ra.pets[petKey];
            var unlocked = !!p.isUnlocked;
            var reqText = "";
            if (!unlocked && prevKey) {
                var prev = Ra.pets[prevKey];
                if (prev) reqText = "Get " + prev.name + " to level " + formatInt(8);
            } else if (!unlocked) {
                reqText = "Unlock Ra";
            }

            var level = p.level || 0;
            var required = p.requiredMemories || 0;
            var progress = required > 0 ? Math.min(1, (p.memories || 0) / required) : 0;

            var memUp = {
                cost: format(p.memoryUpgradeCost, 2),
                costRaw: p.memoryUpgradeCost,
                canAfford: !!p.canBuyMemoryUpgrade,
                isCapped: !!p.memoryUpgradeCapped,
                currentMult: format(p.memoryUpgradeCurrentMult, 2) + "x",
                nextMult: format(p.memoryUpgradeCurrentMult * 1.3, 2) + "x",
                effectDescription: "+30% Memories gained per Memory Chunk",
                timeToAfford: raTimeToAffordUpgrade(p, p.memoryUpgradeCost)
            };
            var chunkUp = {
                cost: format(p.chunkUpgradeCost, 2),
                costRaw: p.chunkUpgradeCost,
                canAfford: !!p.canBuyChunkUpgrade,
                isCapped: !!p.chunkUpgradeCapped,
                currentMult: format(p.chunkUpgradeCurrentMult, 2) + "x",
                nextMult: format(p.chunkUpgradeCurrentMult * 1.5, 2) + "x",
                effectDescription: "+50% Memory Chunks per second",
                timeToAfford: raTimeToAffordUpgrade(p, p.chunkUpgradeCost)
            };

            // Chunks/s × memoryUpgradeCurrentMult × productionPerMemoryChunk × chunks in reservoir
            // is too expensive to replicate exactly; web shows `memoryChunksPerSecond` and
            // `memoryProductionMultiplier * memoryChunks` separately. We surface both.
            var cps = p.memoryChunksPerSecond || 0;
            var mps = (p.memoryChunks || 0) * (Ra.productionPerMemoryChunk || 1) *
                (p.memoryUpgradeCurrentMult || 1);

            // "Time to next level" via Ra.timeToGoalString (returns "in 1m 30s" or "")
            var timeToLevel = "";
            if (!p.isCapped && required > 0) {
                var expToGain = required - (p.memories || 0);
                if (expToGain > 0) {
                    try { timeToLevel = Ra.timeToGoalString(p, expToGain) || ""; } catch (e) {}
                }
            }

            // Web RaPet.vue:265-270 — "Multiplying all Memory production by X"
            // shown when memoryMultiplier > 1 and Ra is not totally capped.
            var memMult = p.memoryProductionMultiplier || 1;
            var memMultText = "";
            if (memMult > 1) memMultText = format(memMult, 2, 3);

            return {
                key: petKey,
                displayName: displayName,
                colorHex: p.color || "#9063de",
                chunkGainResource: chunkGain,
                memoryGainResource: memoryGain,
                isUnlocked: unlocked,
                unlockRequirementText: reqText,
                level: level,
                isCapped: !!p.isCapped,
                memories: format(p.memories || 0, 2),
                memoriesRaw: p.memories || 0,
                memoryChunks: format(p.memoryChunks || 0, 2),
                chunksPerSecond: format(cps, 2) + "/s",
                memoriesPerSecond: format(mps, 2) + "/s",
                requiredMemories: format(required, 2),
                requiredMemoriesRaw: required,
                progressToNextLevel: progress,
                timeToNextLevel: timeToLevel,
                hasRemembrance: !!p.hasRemembrance,
                memoryUpgrade: memUp,
                chunkUpgrade: chunkUp,
                canLevelUp: (p.memories || 0) >= required && !p.isCapped,
                scalingUpgradeText: "",  // filled per-pet below
                nextUnlockText: raNextUnlockText(petKey, level),
                unlocks: raBuildUnlockList(petKey),
                memoryMultiplier: memMult,
                memoryMultiplierText: memMultText
            };
        } catch (e) { return null; }
    }

    globalThis._nativeRaState = function () {
        try {
            if (!has(Ra) || !Ra.pets) return JSON.stringify({ ready: false });
            var isUnlocked = vis_raUnlocked();
            if (!isUnlocked) return JSON.stringify({ ready: true, isUnlocked: false });

            var pets = [];
            var p;
            p = raBuildPet("teresa",   "Teresa",          "Eternity Points",     "current RM",           null);       if (p) pets.push(p);
            p = raBuildPet("effarig",  "Effarig",         "Relic Shards gained", "best Glyph level",     "teresa");   if (p) pets.push(p);
            p = raBuildPet("enslaved", "The Nameless Ones","Time Shards",        "total time played",    "effarig");  if (p) pets.push(p);
            p = raBuildPet("v",        "V",               "Infinity Power",      "total Memory levels",  "enslaved"); if (p) pets.push(p);

            // Pet-specific scaling upgrade copy surfaced under the pet's
            // header (matches web RaTab.vue `scalingUpgradeText`). Each line
            // is only rendered when its `scalingUpgradeVisible` gate is true.
            try {
                for (var si = 0; si < pets.length; si++) {
                    var sp = pets[si];
                    if (sp.key === "teresa") {
                        if (Ra.unlocks.chargedInfinityUpgrades && Ra.unlocks.chargedInfinityUpgrades.isUnlocked) {
                            var charges = Ra.totalCharges || 0;
                            sp.scalingUpgradeText = "You can Charge " + formatInt(charges) +
                                " Infinity Upgrade" + (charges === 1 ? "" : "s") + ".";
                        }
                    } else if (sp.key === "effarig") {
                        try {
                            var unlockedAlch = AlchemyResources.all.filter(function (r) { return r.isUnlocked; }).length;
                            if (unlockedAlch > 0) {
                                sp.scalingUpgradeText = "You have unlocked " + formatInt(unlockedAlch) +
                                    " Alchemy Resource" + (unlockedAlch === 1 ? "" : "s") + ".";
                            }
                        } catch (_) {}
                    } else if (sp.key === "enslaved") {
                        try {
                            if (Ra.unlocks.improvedStoredTime && Ra.unlocks.improvedStoredTime.isUnlocked) {
                                var amp = Ra.unlocks.improvedStoredTime.effects.gameTimeAmplification.effectOrDefault(1);
                                var realCap = Ra.unlocks.improvedStoredTime.effects.realTimeCap.effectOrDefault(0) / 3600000;
                                sp.scalingUpgradeText = "Stored game time " + formatX(amp, 2, 2) +
                                    " and +" + formatInt(realCap) + "h real time cap.";
                            }
                        } catch (_) {}
                    } else if (sp.key === "v") {
                        try {
                            if (Ra.unlocks.unlockHardV && Ra.unlocks.unlockHardV.isUnlocked) {
                                var triads = Ra.unlocks.unlockHardV.effectOrDefault(0);
                                sp.scalingUpgradeText = "You have unlocked " + formatInt(triads) +
                                    " Triad Stud" + (triads === 1 ? "y" : "ies") + ".";
                            }
                        } catch (_) {}
                    }
                }
            } catch (e) {}

            var pwr = Ra.petWithRemembrance || "";
            var totalLevel = Ra.totalPetLevel || 0;
            var maxTotal = Ra.maxTotalPetLevel || 100;
            var remUnlocked = has(Ra.remembrance) ? !!Ra.remembrance.isUnlocked : false;
            // Web gate: `Ra.unlocks.effarigUnlock.canBeApplied` (RaTab.vue line 90).
            var showRem = false;
            try { showRem = !!(Ra.unlocks.effarigUnlock && Ra.unlocks.effarigUnlock.canBeApplied); }
            catch (e) { showRem = false; }

            // Safe rebuild of the boost list — Ra.memoryBoostResources has a
            // "…, and undefined" bug on empty arrays and also on 2+ elements
            // when the last iteration yields undefined. Only emit when the
            // final memory multiplier is > 1 (matches the web template gate).
            var boostRes = "";
            try {
                var ppmc = Ra.productionPerMemoryChunk || 1;
                if (ppmc > 1) {
                    var boostList = [];
                    for (var bi = 0; bi < Ra.pets.all.length; bi++) {
                        var bp = Ra.pets.all[bi];
                        if (bp && bp.isUnlocked && bp.memoryProductionMultiplier !== 1 && bp.memoryGain) {
                            boostList.push(bp.memoryGain);
                        }
                    }
                    try { if (Achievement(168).isUnlocked) boostList.push("Achievement 168"); } catch (_) {}
                    try { if (Ra.unlocks.continuousTTBoost && Ra.unlocks.continuousTTBoost.canBeApplied) boostList.push("current TT"); } catch (_) {}
                    if (boostList.length === 1) boostRes = boostList[0];
                    else if (boostList.length === 2) boostRes = boostList[0] + " and " + boostList[1];
                    else if (boostList.length > 2) boostRes = boostList.slice(0, -1).join(", ") + ", and " + boostList[boostList.length - 1];
                }
            } catch (e) { boostRes = ""; }

            return JSON.stringify({
                ready: true,
                isUnlocked: true,
                isRunning: !!Ra.isRunning,
                petWithRemembrance: pwr,
                remembranceUnlocked: remUnlocked,
                showRemembrance: showRem,
                remembranceMult: Ra.remembrance ? Ra.remembrance.multiplier : 5,
                remembranceNerf: Ra.remembrance ? Ra.remembrance.nerf : 0.5,
                remembranceRequiredLevel: Ra.remembrance ? Ra.remembrance.requiredLevels : 20,
                totalPetLevel: totalLevel,
                maxTotalPetLevel: maxTotal,
                levelCap: Ra.levelCap || 25,
                memoriesPerChunk: format(Ra.productionPerMemoryChunk || 0, 3),
                memoryBoostResources: boostRes,
                canStartRun: !!Ra.isUnlocked,
                // Web RaTab.vue:77 — descriptions[4].effects() with first
                // letter uppercased; we keep the canonical source instead of
                // hardcoding English.
                runDescription: (function () {
                    try {
                        var raw = GameDatabase.celestials.descriptions[4].effects();
                        if (!raw) return "";
                        return String(raw).replace(/^\w/u, function (c) { return c.toUpperCase(); });
                    } catch (eRd) {
                        return "All Glyph effects are disabled. Only Antimatter, Infinity, and Time Dimensions produce. Gain Memory Chunks for pets based on what happens inside the Reality.";
                    }
                })(),
                exitAvailable: !!Ra.isRunning,
                pets: pets
            });
        } catch (e) {
            try { debugLog && debugLog("Ra state error: " + (e && e.message ? e.message : e)); } catch (_) {}
            return JSON.stringify({ ready: false });
        }
    };

    // ---- Ra actions ---------------------------------------------------

    globalThis._nativeStartRaRun = function () {
        try {
            if (!has(Ra)) return "missing";
            if (typeof startRaReality === "function") { startRaReality(); return "ok"; }
            if (Ra.initializeRun) {
                // Mirror the web's BigCrunchButton.vue / RaRunButton flow:
                // process a manual Reality with no glyph selection, then flip
                // player.celestials.ra.run.
                if (typeof processManualReality === "function") {
                    processManualReality(true, undefined);
                }
                Ra.initializeRun();
                return "ok";
            }
            return "nofn";
        } catch (e) { try { _nativeLog && _nativeLog("[ra] startRun error " + e); } catch (_) {} return "error"; }
    };

    globalThis._nativeRaLevelUp = function (petKey) {
        try { Ra.pets[petKey].levelUp(); return "ok"; } catch (e) { return "error"; }
    };
    globalThis._nativeRaBuyMemoryUpgrade = function (petKey) {
        try { Ra.pets[petKey].purchaseMemoryUpgrade(); return "ok"; } catch (e) { return "error"; }
    };
    globalThis._nativeRaBuyChunkUpgrade = function (petKey) {
        try { Ra.pets[petKey].purchaseChunkUpgrade(); return "ok"; } catch (e) { return "error"; }
    };
    globalThis._nativeRaSelectRemembrance = function (petKey) {
        try {
            // Pet name is the display name in player.celestials.ra.petWithRemembrance.
            var name = Ra.pets[petKey] ? Ra.pets[petKey].name : "";
            if (!name) return "missing";
            // Toggle: clicking the same pet clears selection.
            Ra.petWithRemembrance = (Ra.petWithRemembrance === name) ? "" : name;
            return "ok";
        } catch (e) { return "error"; }
    };

    // DEBUG: bump a single pet to max level (25) for testing milestone unlocks.
    globalThis._nativeDevMaxRaPet = function (petKey) {
        try {
            var p = Ra.pets[petKey];
            if (!p) return "missing";
            // Grant enough memories for the jump + call levelUp repeatedly so
            // Ra.checkForUnlocks() fires per level.
            while (p.level < Ra.levelCap) {
                p.memories = Ra.requiredMemoriesForLevel(p.level) + 1;
                p.levelUp();
            }
            return "ok";
        } catch (e) { return "error"; }
    };

    // ---- Glyph Alchemy ------------------------------------------------

    // Precomputed node coordinates matching web `alchemy-circle-layout.js`.
    // Layout is deterministic (depends only on static tier/uiOrder), so the
    // first call memoizes and Swift pulls the same positions every poll.
    var _alchemyLayoutCache = null;
    function _computeAlchemyLayout() {
        if (_alchemyLayoutCache) return _alchemyLayoutCache;
        if (typeof AlchemyResources === "undefined") return null;
        var orbits = [
            { tier: 1, radius: 4, offset: -Math.PI / 3 },
            { tier: 2, radius: 3, offset: 0 },
            { tier: 3, radius: 2, offset: Math.PI / 3 },
            { tier: 4, radius: 1, offset: -Math.PI / 6 },
            { tier: 5, radius: 0, offset: 0 }
        ];
        var nodes = [];
        for (var i = 0; i < orbits.length; i++) {
            var o = orbits[i];
            var inTier = AlchemyResources.all
                .filter(function (r) { return r.config.tier === o.tier; })
                .sort(function (a, b) { return a.config.uiOrder - b.config.uiOrder; });
            var step = 2 * Math.PI / inTier.length;
            var angle = o.offset;
            for (var j = 0; j < inTier.length; j++) {
                var res = inTier[j];
                nodes.push({
                    id: res.id,
                    x: o.radius * Math.sin(angle),
                    y: o.radius * Math.cos(angle)
                });
                angle += step;
            }
        }
        var maxAbs = 0;
        for (var k = 0; k < nodes.length; k++) {
            if (Math.abs(nodes[k].x) > maxAbs) maxAbs = Math.abs(nodes[k].x);
            if (Math.abs(nodes[k].y) > maxAbs) maxAbs = Math.abs(nodes[k].y);
        }
        var size = maxAbs * 2;
        for (var n = 0; n < nodes.length; n++) {
            nodes[n].x = (nodes[n].x / size + 0.5) * 100;
            nodes[n].y = (nodes[n].y / size + 0.5) * 100;
        }
        _alchemyLayoutCache = nodes;
        return nodes;
    }

    globalThis._nativeAlchemyState = function () {
        try {
            if (typeof AlchemyResources === "undefined" || !Ra
                || !Ra.unlocks || !Ra.unlocks.unlockGlyphAlchemy
                || !Ra.unlocks.unlockGlyphAlchemy.canBeApplied) {
                return JSON.stringify({ unlocked: false });
            }
            var layout = _computeAlchemyLayout();
            var posById = {};
            if (layout) {
                for (var i = 0; i < layout.length; i++) {
                    posById[layout[i].id] = layout[i];
                }
            }
            var capFactor = 1 / GlyphSacrificeHandler.glyphRefinementEfficiency;
            var isDoomed = !!(Pelle && Pelle.isDoomed);
            var realityCreationVisible = Ra.pets && Ra.pets.effarig && Ra.pets.effarig.level === 25;

            var resources = AlchemyResources.all.map(function (r) {
                var cfg = r.config || {};
                var pos = posById[r.id] || { x: 50, y: 50 };
                var effectText = "";
                try {
                    if (cfg.formatEffect) effectText = normText(cfg.formatEffect(r.effectValue));
                } catch (e) {}
                var lockText = "";
                try { lockText = normText(r.lockText || ""); } catch (e) {}
                var reactionActive = false;
                var reactionText = "";
                var reactionProduction = 0;
                if (!r.isBaseResource && r.reaction) {
                    reactionActive = !isDoomed && !!r.reaction.isActive;
                    reactionProduction = r.reaction.reactionProduction || 0;
                    if (r === AlchemyResource.reality) {
                        reactionText = r.reaction.reagents.map(function (rg) { return rg.resource.symbol; }).join(" + ")
                            + " ➜ " + r.symbol;
                    } else {
                        reactionText = r.reaction.reagents
                            .map(function (rg) { return format(rg.cost) + rg.resource.symbol; })
                            .join(" + ")
                            + " ➜ " + format(reactionProduction, 2, 2) + r.symbol;
                    }
                }
                var flow = r.flow || 0;
                var flowText;
                if (Math.abs(flow) < 0.01) flowText = "None";
                else flowText = (flow >= 0 ? "+" : "-") + format(Math.abs(flow), 2, 2) + "/sec";
                return {
                    id: r.id,
                    name: cfg.name || "",
                    symbol: cfg.symbol || "",
                    tier: cfg.tier || 1,
                    uiOrder: cfg.uiOrder || 0,
                    x: pos.x,
                    y: pos.y,
                    amount: formatFloat(r.amount, 1),
                    cap: formatFloat(r.cap, 1),
                    amountNum: r.amount,
                    capNum: r.cap,
                    capped: !!r.capped,
                    flow: flow,
                    flowText: flowText,
                    isUnlocked: !!r.isUnlocked,
                    isBaseResource: !!r.isBaseResource,
                    lockText: lockText,
                    reactionActive: reactionActive,
                    reactionText: reactionText,
                    reactionProduction: reactionProduction,
                    effectText: effectText,
                    description: normText(cfg.description || "")
                };
            });

            // Build reaction arrows
            var arrows = [];
            var reactions = (typeof AlchemyReactions !== "undefined" && AlchemyReactions.all)
                ? AlchemyReactions.all : [];
            for (var j = 0; j < reactions.length; j++) {
                var rx = reactions[j];
                if (!rx) continue;
                var prod = rx.product;
                var prodPos = posById[prod.id];
                if (!prodPos) continue;
                for (var k = 0; k < rx.reagents.length; k++) {
                    var reag = rx.reagents[k];
                    var reagPos = posById[reag.resource.id];
                    if (!reagPos) continue;
                    var outAmt = prod.amount;
                    var inAmt = reag.resource.amount;
                    var capped = (outAmt > 0 && outAmt >= inAmt) || outAmt >= prod.cap;
                    var lessThan = prod.amount > 0 && reag.cost < reag.resource.cap;
                    arrows.push({
                        reagentId: reag.resource.id,
                        productId: prod.id,
                        rx: reagPos.x, ry: reagPos.y,
                        px: prodPos.x, py: prodPos.y,
                        unlocked: !!(prod.isUnlocked && reag.resource.isUnlocked),
                        capped: !!capped,
                        active: !!(rx.isActive && !isDoomed),
                        lessThan: !!lessThan
                    });
                }
            }

            var activeReactions = 0, totalReactions = 0;
            for (var m = 0; m < reactions.length; m++) {
                var r2 = reactions[m];
                if (!r2 || !r2.product.isUnlocked) continue;
                totalReactions++;
                if (r2.isActive) activeReactions++;
            }

            return JSON.stringify({
                unlocked: true,
                isDoomed: isDoomed,
                realityCreationVisible: !!realityCreationVisible,
                createdRealityGlyph: !!(player && player.reality && player.reality.glyphs && player.reality.glyphs.createdRealityGlyph),
                allReactionsDisabled: activeReactions === 0 && totalReactions > 0,
                alchemyCap: Ra.alchemyResourceCap,
                capFactor: capFactor,
                resources: resources,
                arrows: arrows
            });
        } catch (e) {
            try { _nativeLog && _nativeLog("[alchemy] state error " + e); } catch (_) {}
            return JSON.stringify({ unlocked: false, __err: String(e && e.message || e) });
        }
    };

    globalThis._nativeAlchemyToggleReaction = function (resourceId) {
        try {
            var r = AlchemyResources.all.filter(function (x) { return x.id === resourceId; })[0];
            if (!r || r.isBaseResource || !r.reaction) return "missing";
            r.reaction.isActive = !r.reaction.isActive;
            return "ok";
        } catch (e) { return "error"; }
    };

    globalThis._nativeAlchemyToggleAllReactions = function () {
        try {
            var reactions = AlchemyReactions.all.filter(function (r) { return r && r.product.isUnlocked; });
            var allOff = reactions.every(function (r) { return !r.isActive; });
            for (var i = 0; i < reactions.length; i++) reactions[i].isActive = allOff;
            return "ok";
        } catch (e) { return "error"; }
    };

    // DEBUG: max all alchemy resources in one shot. Swift gates call sites
    // behind #if DEBUG; the JS helper is always loaded for simplicity.
    globalThis._nativeDevMaxAllAlchemy = function () {
        try {
            if (typeof AlchemyResources === "undefined") return "missing";
            AlchemyResources.all.forEach(function (r) {
                try { r.amount = r.cap; } catch (e) {}
            });
            return "ok";
        } catch (e) { return "error"; }
    };

    // ---- Lai'tela ------------------------------------------------------
    // Layout references:
    //   LaitelaTab.vue
    //   DarkMatterDimensionRow.vue / DarkMatterDimensionGroup.vue
    //   SingularityPane.vue / SingularityMilestonePane.vue / SingularityMilestoneComponent.vue
    //   LaitelaRunButton.vue / LaitelaAutobuyerPane.vue / AnnihilationButton.vue

    function _laitelaSerializeMilestone(m, key) {
        if (!m || !m.config) return null;
        var cfg = m.config;
        var mode = "singularities";
        // Heuristic matching SingularityMilestoneComponent.vue:
        //   autoCondense, darkAutobuyerSpeed → condenseCount mode
        var condenseModeKeys = { autoCondense: 1, darkAutobuyerSpeed: 1 };
        if (condenseModeKeys[key]) mode = "condenseCount";

        // `isUnique` on the instance is the canonical check; `isRepeatable`
        // isn't always a direct getter. Fall back to config.repeat sentinels.
        var isUnique = !!m.isUnique || (typeof m.isRepeatable !== "undefined" ? !m.isRepeatable : false);
        if (typeof m.isUnique === "undefined" && typeof m.isRepeatable === "undefined") {
            isUnique = !cfg.repeat || cfg.repeat === 1;
        }
        var limit = isUnique ? 1 : (cfg.limit || Infinity);
        var maxed = !!m.isMaxed;
        var completions = (typeof m.completions === "number") ? m.completions : 0;
        if (maxed) mode = "maxed";

        // Current effect display. Prefer the instance's own preformatted
        // getters (`effectDisplay` / `nextEffectDisplay`) — those match web
        // `SingularityMilestoneComponent.vue` exactly, including milestone
        // effects where `effect(completions)` ≠ effect(completions + 1)
        // formatted identically at 2dp (e.g. continuumMult uses
        // Math.pow(1.03, c), so 1.03 → 1.06 needs 2dp display).
        var effectText = "";
        try {
            if (typeof m.effectDisplay === "string") {
                effectText = normText(m.effectDisplay);
            } else if (typeof cfg.effectFormat === "function") {
                effectText = normText(cfg.effectFormat(m.effectValue));
            } else if (m.effectValue !== undefined) {
                effectText = format(m.effectValue, 2, 2);
            }
        } catch (e) {}
        var nextEffectText = "";
        if (!isUnique && !maxed) {
            try {
                if (typeof m.nextEffectDisplay === "string") {
                    nextEffectText = normText(m.nextEffectDisplay);
                } else if (typeof cfg.effect === "function") {
                    var nextVal = cfg.effect(completions + 1);
                    nextEffectText = (typeof cfg.effectFormat === "function")
                        ? normText(cfg.effectFormat(nextVal))
                        : format(nextVal, 2, 2);
                }
            } catch (e) {}
        }
        // Final sanity: if current === next formatted string, we're probably
        // hitting a format-precision collision. Drop the arrow so the card
        // doesn't read "X → X".
        if (nextEffectText && nextEffectText === effectText) {
            nextEffectText = "";
        }

        // Progress + remaining singularities. Read the instance's own
        // `nextGoal` / `previousGoal` / `remainingSingularities` getters —
        // those match web's SingularityMilestone class exactly (incl. the
        // `unnerfCompletions` softcap math, which the prior manual fallback
        // ignored — producing "In 0 Singularities" + a full bar on every
        // infinite-limit milestone once its `increaseThreshold` was passed).
        // NOTE: there is no `nextGoalAt` getter on this class, and
        // `progressToNext` returns a formatted percent STRING, not a number —
        // both prior branches were dead, so everything fell through to the
        // broken manual path. Web's bar width = `progressToNext` =
        // (sing - previousGoal) / nextGoal clampMax 1, and the remaining text =
        // quantify("Singularity", remainingSingularities, 2) = format(_, 2).
        var progress = 0;
        var remainingText = "0";
        var sing = Currency.singularities.value;
        try {
            if (maxed) {
                progress = 1;
            } else {
                var next = (typeof m.nextGoal === "number") ? m.nextGoal : NaN;
                var prev = (typeof m.previousGoal === "number") ? m.previousGoal : NaN;
                var remaining = (typeof m.remainingSingularities === "number")
                              ? m.remainingSingularities
                              : (next - sing);
                remainingText = format(Math.max(0, remaining), 2);
                if (!isNaN(next) && next > 0 && !isNaN(prev)) {
                    progress = Math.min(1, Math.max(0, (sing - prev) / next));
                }
            }
        } catch (e) {}

        return {
            id: key,
            name: normText(cfg.description || ""),
            description: normText(cfg.description || ""),
            effectText: effectText,
            nextEffectText: nextEffectText,
            isUnique: isUnique,
            isMaxed: maxed,
            isUnlocked: !!m.isUnlocked,
            completions: completions,
            limit: (limit === Infinity) ? 999 : limit,
            remainingSingularities: remainingText,
            progressPct: progress,
            mode: mode
        };
    }

    function _laitelaGlyphRecord(g) {
        if (!g) return null;
        var typeColor = "";
        try { typeColor = GlyphAppearanceHandler.getBorderColor(g.type); } catch (e) {}
        var rarityColor = "";
        var rarityPct = "";
        var rarityPctNum = 0;
        var rarityName = "";
        try {
            var rarity = strengthToRarity(g.strength);
            rarityPctNum = +rarity || 0;
            rarityPct = formatRarity(rarity);
            var rarityObj = getRarity(g.strength);
            if (rarityObj) {
                rarityColor = rarityObj.darkColor || rarityObj.color || "";
                rarityName = rarityObj.name || "";
            }
        } catch (e) {}
        var bits = g.effects || 0;
        var effectCount = 0;
        var tmp = bits;
        while (tmp) { effectCount += tmp & 1; tmp >>>= 1; }
        return {
            type: g.type || "",
            symbol: g.symbol || (CosmeticGlyphTypes[g.type] ? CosmeticGlyphTypes[g.type].currentSymbol.symbol : "?"),
            level: g.level || 0,
            effectCount: effectCount,
            typeColor: typeColor,
            rarityColor: rarityColor,
            rarityPercent: rarityPct,
            rarityPercentNum: rarityPctNum,
            rarityName: rarityName,
            effects: []
        };
    }

    globalThis._nativeLaitelaState = function () {
        try {
            if (typeof Laitela === "undefined") {
                return JSON.stringify({ ready: false });
            }

            // Self-heal on every Lai'tela poll: if the user lands on this tab
            // with broken state (DMD1.amount = 0 / DM = 0 from a cheat path
            // that bypassed ImaginaryUpgrade(15).onPurchased, or a save
            // imported from a build before the heal existed), fix it before
            // returning state. Cheap and idempotent — no-op once amounts > 0.
            try {
                if (typeof globalThis._nativeHealDMDs === "function") {
                    globalThis._nativeHealDMDs();
                }
                // Also clear stuck celestial-run flags if the user is doomed
                // — covers saves where doomCurrentReality() didn't exit Ra/V/etc.
                if (typeof globalThis._nativeHealDoomedCelestialRuns === "function") {
                    globalThis._nativeHealDoomedCelestialRuns();
                }
            } catch (e) {}

            var isDoomed = !!(typeof Pelle !== "undefined" && Pelle.isDoomed);
            var darkMatter = Currency.darkMatter.value;
            var darkMatterCap = (typeof Currency.darkMatter.max !== "undefined")
                ? Currency.darkMatter.max : darkMatter;
            var darkEnergy = Currency.darkEnergy.value;

            // --- Singularity block ----------------------------------------
            var tpcSec = Singularity.timePerCondense || 0;
            var gainedPerCondense = Math.max(1, Math.floor(Singularity.singularitiesGained || 1));
            var gainPerHour = (tpcSec > 0) ? (gainedPerCondense / tpcSec * 3600) : 0;
            // Auto-condense waits for `autoCondense.effectValue × cap` worth of
            // DE before firing, so the effective period is longer by
            //   extraSec = tpcSec × (autoFactor − 1).
            var autoFactor = SingularityMilestone.autoCondense.effectValue || 0;
            var autoApplicable = !!SingularityMilestone.autoCondense.canBeApplied;
            var extraSec = (autoApplicable && autoFactor > 1) ? tpcSec * (autoFactor - 1) : 0;
            var autoTpcSec = tpcSec + extraSec;
            var autoGainPerHour = (autoTpcSec > 0) ? (gainedPerCondense / autoTpcSec * 3600) : 0;
            // Per-step Dark Energy multiplier (×10 baseline) and per-step
            // gained-Singularity multiplier (base 11, modified by
            // improvedSingularityCap milestone).
            var gainPerCapStep = 11;
            try {
                if (Singularity.gainPerCapIncrease !== undefined) gainPerCapStep = Singularity.gainPerCapIncrease;
                else if (SingularityMilestone.improvedSingularityCap
                         && typeof SingularityMilestone.improvedSingularityCap.effectOrDefault === "function") {
                    gainPerCapStep = SingularityMilestone.improvedSingularityCap.effectOrDefault(11);
                }
            } catch (e) {}
            // Vue SingularityPane.vue:
            //   `singularityFormText` — "Condense all Dark Energy into a
            //   Singularity" / "into N Singularities" when can perform; pre-cap
            //   reads "Reach X Dark Energy to condense ...".
            //   `singularityWaitText` — status line below the condense button:
            //   "(Auto-condensing in X)" / "(Will immediately auto-condense)"
            //   / "(Enough Dark Energy in X)" depending on cap + auto state.
            var canPerform = !!Singularity.capIsReached && !isDoomed;
            var formNoun = (gainedPerCondense === 1)
                ? "all Dark Energy into a Singularity"
                : "all Dark Energy into " + format(gainedPerCondense, 2) + " Singularities";
            var singularityFormText = canPerform
                ? ("Condense " + formNoun)
                : ("Reach " + format(Singularity.cap) + " Dark Energy to condense " + formNoun);

            var singularityWaitText = "";
            try {
                var curTime = Singularity.timeUntilCap || 0;
                if (canPerform) {
                    if (autoApplicable) {
                        var totalAuto = curTime + extraSec;
                        singularityWaitText = totalAuto > 0
                            ? "(Auto-condensing in " + TimeSpan.fromSeconds(totalAuto).toStringShort() + ")"
                            : "(Will immediately auto-condense)";
                    }
                } else {
                    singularityWaitText = "(Enough Dark Energy in " + TimeSpan.fromSeconds(curTime).toStringShort() + ")";
                }
            } catch (e) { singularityWaitText = ""; }

            var sing = {
                singularities: format(Currency.singularities.value, 2, 0),
                singularitiesRaw: Currency.singularities.value,
                darkEnergy: format(darkEnergy, 2, 4),
                darkEnergyPerSec: format(Currency.darkEnergy.productionPerSecond || 0, 2, 4),
                cap: format(Singularity.cap, 2, 0),
                capRaw: Singularity.cap,
                capIncreases: player.celestials.laitela.singularityCapIncreases,
                maxCapIncreases: 50,
                canPerform: canPerform,
                singularitiesGainedPerCondense: gainedPerCondense,
                formText: singularityFormText,
                waitText: singularityWaitText,
                timePerCondenseText: TimeSpan.fromSeconds(tpcSec).toStringShort(),
                timePerCondenseSec: tpcSec,
                timeUntilCapText: TimeSpan.fromSeconds(Singularity.timeUntilCap || 0).toStringShort(),
                gainPerHourText: format(gainPerHour, 2, 3),
                extraTimeAfterSingularityText: extraSec > 0
                    ? TimeSpan.fromSeconds(extraSec).toStringShort() : "",
                autoGainPerHourText: format(autoGainPerHour, 2, 3),
                gainPerCapStep: gainPerCapStep,
                darkEnergyPerCapStep: 10,
                hasBulkUnlocked: Currency.singularities.value >= 10,
                hasAutoCondense: !!SingularityMilestone.autoCondense.isUnlocked,
                autoCondenseActive: autoApplicable,
                autoCondenseFactor: autoFactor,
                autoCondenseFactorText: autoFactor ? formatX(autoFactor, 2, 2) : "",
                nextLowerStep: Math.max(0, (player.celestials.laitela.singularityCapIncreases || 0) - 1),
                willCondenseOnDecrease: false
            };

            // --- DMD rows (tiers 1..4) ------------------------------------
            var dims = [];
            for (var t = 1; t <= 4; t++) {
                var d = DarkMatterDimension(t);
                var intervalMs = d.interval || 1000;
                var timerPct = 0;
                try {
                    var last = (player.celestials.laitela.dimensions[t - 1] || {}).timeSinceLastUpdate || 0;
                    timerPct = Math.max(0, Math.min(1, last / intervalMs));
                } catch (e) {}
                dims.push({
                    tier: t,
                    isUnlocked: !!d.isUnlocked,
                    amount: format(d.amount, 2, 2),
                    interval: TimeSpan.fromMilliseconds(intervalMs).toStringShort(),
                    intervalMs: intervalMs,
                    timerPct: timerPct,
                    isIntervalCapped: intervalMs <= 10,
                    powerDM: formatX(d.powerDM, 2, 2),
                    powerDE: "+" + format(d.powerDE, 2, 4),
                    dePerSec: format(d.productionPerSecond || 0, 2, 4),
                    dePerSecPct: "0%",
                    productionText: "",
                    intervalCost: format(d.intervalCost, 2, 0),
                    powerDMCost: format(d.powerDMCost, 2, 0),
                    powerDECost: format(d.powerDECost, 2, 0),
                    canBuyInterval: !!d.canBuyInterval,
                    canBuyPowerDM: !!d.canBuyPowerDM,
                    canBuyPowerDE: !!d.canBuyPowerDE,
                    ascensionCount: d.ascensions || 0,
                    hasAscended: (d.ascensions || 0) > 0,
                    nextAscensionIntervalText: "",
                    intervalPurchaseCap: d.intervalPurchaseCap || 10,
                    adjustedPurchaseCap: d.adjustedPurchaseCap || d.intervalPurchaseCap || 10,
                    continuumValue: d.continuumValue || 0
                });
            }

            // --- Annihilation ---------------------------------------------
            var annUnlocked = !!Laitela.annihilationUnlocked;
            var annAutoUnlocked = !!(typeof Autobuyer !== "undefined" && Autobuyer.annihilation && Autobuyer.annihilation.isUnlocked);
            var annihilation = {
                unlocked: annUnlocked,
                isVisible: annUnlocked || annAutoUnlocked,
                canAnnihilate: !!Laitela.canAnnihilate,
                darkMatter: format(darkMatter, 2, 2),
                darkMatterMult: formatX(Laitela.darkMatterMult || 1, 2, 2),
                darkMatterMultGain: "+" + format(Laitela.darkMatterMultGain || 0, 2, 2),
                darkMatterMultRatio: formatX(Laitela.darkMatterMultRatio || 1, 2, 2),
                autoUnlocked: annAutoUnlocked,
                autoMultiplier: (player.auto && player.auto.annihilation) ? (player.auto.annihilation.multiplier || 0) : 0,
                requirementText: "Reach " + format(1e60, 2, 0) + " Dark Matter"
            };

            // --- Autobuyer pane -------------------------------------------
            var autobuyers = {
                isVisible: !!(SingularityMilestone.darkDimensionAutobuyers.isUnlocked
                           || SingularityMilestone.ascensionAutobuyers.isUnlocked
                           || SingularityMilestone.autoCondense.isUnlocked
                           || annAutoUnlocked),
                dimension: {
                    isUnlocked: !!SingularityMilestone.darkDimensionAutobuyers.isUnlocked,
                    isActive: !!(player.auto.darkMatterDims && player.auto.darkMatterDims.isActive),
                    label: "Auto-buy Dark Matter Dimensions",
                    description: "Auto-buys up to tier "
                        + formatInt(SingularityMilestone.darkDimensionAutobuyers.effectValue || 0)
                },
                ascension: {
                    isUnlocked: !!SingularityMilestone.ascensionAutobuyers.isUnlocked,
                    isActive: !!(player.auto.ascension && player.auto.ascension.isActive),
                    label: "Auto-Ascend Dark Matter Dimensions",
                    description: "Auto-ascends up to tier "
                        + formatInt(SingularityMilestone.ascensionAutobuyers.effectValue || 0)
                },
                singularity: {
                    isUnlocked: !!SingularityMilestone.autoCondense.isUnlocked,
                    isActive: !!(player.auto.singularity && player.auto.singularity.isActive),
                    label: "Auto-Condense Singularities",
                    description: SingularityMilestone.autoCondense.effectValue
                        ? ("Auto-condenses at Cap " + formatX(SingularityMilestone.autoCondense.effectValue, 2, 2))
                        : "Auto-condenses at the Singularity cap"
                },
                annihilation: {
                    isUnlocked: annAutoUnlocked,
                    isActive: !!(player.auto.annihilation && player.auto.annihilation.isActive),
                    label: "Auto-Annihilate",
                    description: "Auto-triggers when Dark Matter multiplier gain exceeds threshold"
                }
            };

            // --- Run info -------------------------------------------------
            var fastestSec = player.celestials.laitela.fastestCompletion || 3600;
            var bestSet = [];
            try {
                var arr = player.celestials.laitela.glyphs || [];
                for (var gi = 0; gi < arr.length; gi++) {
                    var gg = _laitelaGlyphRecord(arr[gi]);
                    if (gg) bestSet.push(gg);
                }
            } catch (e) {}

            var runDescription = "";
            try {
                var descs = GameDatabase && GameDatabase.celestials && GameDatabase.celestials.descriptions;
                if (descs && descs[5] && typeof descs[5].effects === "function") {
                    runDescription = normText(descs[5].effects());
                }
            } catch (e) {}

            // Vue LaitelaRunButton.vue:
            //   `runEffects` — descriptions[5].effects() split on "\n".
            //   `runDescription` — descriptions[5].description().
            //   multiplier line — "All Dark Matter multipliers are ×N higher."
            //     shown when realityReward > 1.
            var runEffectsLines = [];
            try {
                var raw5 = (descs && descs[5] && typeof descs[5].effects === "function")
                    ? descs[5].effects() : "";
                if (raw5) {
                    runEffectsLines = String(raw5).split("\n")
                        .map(function (s) { return s.replace(/\s+/g, " ").trim(); })
                        .filter(function (s) { return s.length > 0; });
                }
            } catch (e) {}
            var runDescriptionPara = "";
            try {
                if (descs && descs[5] && typeof descs[5].description === "function") {
                    runDescriptionPara = normText(descs[5].description());
                }
            } catch (e) {}
            var rr = Laitela.realityReward || 1;
            var multiplierLine = (rr > 1)
                ? "All Dark Matter multipliers are " + formatX(rr, 2, 2) + " higher."
                : "";

            var run = {
                isRunning: !!Laitela.isRunning,
                difficultyTier: Laitela.difficultyTier || 0,
                maxAllowedDimension: Laitela.maxAllowedDimension || 8,
                fastestCompletionSeconds: fastestSec,
                fastestCompletionText: TimeSpan.fromSeconds(fastestSec).toStringShort(),
                realityReward: formatX(rr, 2, 2),
                bestSet: bestSet,
                isFullyDestabilized: !!Laitela.isFullyDestabilized,
                tierNotCompleted: (Laitela.difficultyTier || 0) < 1,
                runDescription: runDescription,
                runEffectsLines: runEffectsLines,
                description: runDescriptionPara,
                multiplierLine: multiplierLine
            };

            // --- Milestones ------------------------------------------------
            var allKeys = [];
            var msDb = (GameDatabase && GameDatabase.celestials && GameDatabase.celestials.singularityMilestones)
                ? GameDatabase.celestials.singularityMilestones : null;
            if (msDb) {
                for (var k in msDb) { if (msDb.hasOwnProperty(k)) allKeys.push(k); }
            }
            var allMs = [];
            for (var i2 = 0; i2 < allKeys.length; i2++) {
                var key = allKeys[i2];
                var m = SingularityMilestone[key];
                var entry = _laitelaSerializeMilestone(m, key);
                if (entry) allMs.push(entry);
            }
            // Next-N carousel: prefer web's own `nextMilestoneGroup` which
            // filters to the next uncompleted tier of each milestone — exactly
            // what `SingularityMilestonePane.vue` renders. Fall back to a
            // local "unmaxed + closest-remaining" filter if the web helper
            // isn't exposed on this save.
            var next = [];
            try {
                if (typeof SingularityMilestones !== "undefined" && SingularityMilestones.nextMilestoneGroup) {
                    var group = SingularityMilestones.nextMilestoneGroup;
                    if (group && group.length) {
                        // Find the matching serialized entry in allMs by id.
                        // `nextMilestoneGroup` may return wrapped instances, not
                        // config objects — search by config reference first.
                        for (var gi = 0; gi < group.length; gi++) {
                            var inst = group[gi];
                            var matchedKey = null;
                            for (var k2 in msDb) {
                                if (msDb.hasOwnProperty(k2) && (inst === SingularityMilestone[k2] || inst.config === msDb[k2])) {
                                    matchedKey = k2; break;
                                }
                            }
                            if (matchedKey) {
                                for (var ai = 0; ai < allMs.length; ai++) {
                                    if (allMs[ai].id === matchedKey) { next.push(allMs[ai]); break; }
                                }
                            }
                        }
                    }
                }
            } catch (e) {}
            if (!next.length) {
                var parseRem = function (s) {
                    var n = parseFloat((s || "0").replace(/,/g, ""));
                    return isFinite(n) ? n : Number.MAX_VALUE;
                };
                next = allMs.filter(function (m) { return !m.isMaxed && parseRem(m.remainingSingularities) > 0; })
                    .sort(function (a, b) {
                        return parseRem(a.remainingSingularities) - parseRem(b.remainingSingularities);
                    })
                    .slice(0, 6);
            }

            // Continuum bonus — matterExtraPurchaseFactor returns a multiplier
            // (1.0 = no bonus, 1.05 = +5% extra purchases). Surface as "X%".
            var extraFactor = 1;
            try { extraFactor = Laitela.matterExtraPurchaseFactor || 1; } catch (e) {}
            var continuumBonusPct = format((extraFactor - 1) * 100, 2, 2) + "%";

            // Vue LaitelaTab.vue:67 computes the per-second DMD1 gain rate
            // as `d1.amount × d1.powerDM / d1.interval × 1000`. We mirror that
            // (treating Decimals or plain numbers) and format with TimeSpan
            // for the singularity unlock countdown.
            var darkMatterGain = 0;
            try {
                var d1 = DarkMatterDimension(1);
                if (d1) {
                    var amt = (d1.amount && typeof d1.amount.toNumber === "function")
                        ? d1.amount.toNumber() : Number(d1.amount || 0);
                    var pdm = (d1.powerDM && typeof d1.powerDM.toNumber === "function")
                        ? d1.powerDM.toNumber() : Number(d1.powerDM || 0);
                    var ivl = d1.interval || 1;
                    darkMatterGain = (ivl > 0) ? (amt * pdm / ivl * 1000) : 0;
                }
            } catch (e) { darkMatterGain = 0; }

            // "Unlock Singularities in X" (Vue LaitelaTab.vue:115) — only
            // useful pre-first-Singularity. Falls back to "" when DE/sec is 0.
            var singUnlockTimeText = "";
            try {
                var dePerSec = Currency.darkEnergy.productionPerSecond || 0;
                if (dePerSec > 0) {
                    var remDE = Math.max(0, Singularity.cap - darkEnergy);
                    if (remDE > 0) {
                        singUnlockTimeText = TimeSpan.fromSeconds(remDE / dePerSec).toStringShort();
                    } else {
                        singUnlockTimeText = "now";
                    }
                }
            } catch (e) { singUnlockTimeText = ""; }

            return JSON.stringify({
                ready: true,
                isUnlocked: !!Laitela.isUnlocked,
                isDoomed: isDoomed,
                darkMatter: format(darkMatter, 2, 2),
                darkMatterCap: format(darkMatterCap, 2, 2),
                darkMatterPerSecText: format(darkMatterGain, 2, 2),
                singularityUnlockTime: singUnlockTimeText,
                maxDarkMatterEver: format(player.celestials.laitela.maxDarkMatter || darkMatter, 2, 2),
                darkMatterCapped: !!(darkMatter && darkMatterCap && darkMatter.gte && darkMatter.gte(darkMatterCap)),
                continuumUnlocked: !!Laitela.continuumUnlocked,
                continuumActive: !!Laitela.continuumActive,
                continuumDisabled: !!player.auto.disableContinuum,
                continuumBonusPct: continuumBonusPct,
                singularity: sing,
                dimensions: dims,
                annihilation: annihilation,
                autobuyers: autobuyers,
                run: run,
                nextMilestones: next,
                allMilestones: allMs
            });
        } catch (e) {
            try { _nativeLog && _nativeLog("[laitela] state error " + e); } catch (_) {}
            return JSON.stringify({ ready: false, __err: String(e && e.message || e) });
        }
    };

    // ---- Lai'tela actions ---------------------------------------------

    globalThis._nativeStartLaitelaRun = function () {
        try {
            if (typeof Laitela === "undefined" || !Laitela.isUnlocked) return "locked";
            if (typeof processManualReality === "function") {
                processManualReality(true, undefined);
            }
            Laitela.initializeRun();
            return "ok";
        } catch (e) { return "error"; }
    };

    globalThis._nativeLaitelaBuyInterval = function (tier) {
        try { DarkMatterDimension(tier).buyInterval(); return "ok"; } catch (e) { return "error"; }
    };
    globalThis._nativeLaitelaBuyPowerDM = function (tier) {
        try { DarkMatterDimension(tier).buyPowerDM(); return "ok"; } catch (e) { return "error"; }
    };
    globalThis._nativeLaitelaBuyPowerDE = function (tier) {
        try { DarkMatterDimension(tier).buyPowerDE(); return "ok"; } catch (e) { return "error"; }
    };
    globalThis._nativeLaitelaAscend = function (tier) {
        try { DarkMatterDimension(tier).ascend(); return "ok"; } catch (e) { return "error"; }
    };
    globalThis._nativeLaitelaMaxAllDMD = function () {
        try {
            if (typeof Laitela.maxAllDMDimensions === "function") {
                Laitela.maxAllDMDimensions(4);
                return "ok";
            }
            return "nofn";
        } catch (e) { return "error"; }
    };

    globalThis._nativeSingularityPerform = function () {
        try { Singularity.perform(); return "ok"; } catch (e) { return "error"; }
    };
    globalThis._nativeSingularityIncreaseCap = function () {
        try { Singularity.increaseCap(); return "ok"; } catch (e) { return "error"; }
    };
    globalThis._nativeSingularityDecreaseCap = function () {
        try { Singularity.decreaseCap(); return "ok"; } catch (e) { return "error"; }
    };

    globalThis._nativeLaitelaAnnihilate = function () {
        try { Laitela.annihilate(false); return "ok"; } catch (e) { return "error"; }
    };
    globalThis._nativeLaitelaSetAnnihilationMultiplier = function (v) {
        try {
            if (!player.auto.annihilation) return "missing";
            player.auto.annihilation.multiplier = Math.max(0, Number(v) || 0);
            return "ok";
        } catch (e) { return "error"; }
    };

    globalThis._nativeLaitelaSetContinuum = function (enabled) {
        try {
            if (typeof Laitela.setContinuum === "function") {
                Laitela.setContinuum(!!enabled);
            } else {
                player.auto.disableContinuum = !enabled;
            }
            return "ok";
        } catch (e) { return "error"; }
    };

    globalThis._nativeLaitelaToggleAutobuyer = function (name, active) {
        try {
            var target = null;
            if (name === "dimension") target = player.auto.darkMatterDims;
            else if (name === "ascension") target = player.auto.ascension;
            else if (name === "singularity") target = player.auto.singularity;
            else if (name === "annihilation") target = player.auto.annihilation;
            if (!target) return "missing";
            target.isActive = !!active;
            return "ok";
        } catch (e) { return "error"; }
    };

    // ---- Lai'tela DEBUG cheats ----------------------------------------

    globalThis._nativeDevGrantSingularities = function (n) {
        try {
            var amt = Number(n) || 0;
            if (amt > 0) Currency.singularities.add(amt);
            return "ok";
        } catch (e) { return "error"; }
    };

    // Bump difficulty tier by one. Sets a reasonable fastestCompletion so
    // the reward stays sane, and exits any active run.
    globalThis._nativeDevCompleteLaitelaTier = function () {
        try {
            var cur = player.celestials.laitela.difficultyTier || 0;
            if (cur >= 8) return "maxed";
            player.celestials.laitela.difficultyTier = cur + 1;
            if (!player.celestials.laitela.fastestCompletion || player.celestials.laitela.fastestCompletion > 360) {
                player.celestials.laitela.fastestCompletion = 360;
            }
            if (player.celestials.laitela.run) player.celestials.laitela.run = false;
            return "ok";
        } catch (e) { return "error"; }
    };

    // Set difficulty tier directly (clamped 0..8). Used by the LaitelaTab DEBUG
    // stepper to jump to any tier without grinding individual completions —
    // primarily to reach Pelle's unlock gate (tier 8 + ImaginaryUpgrade(25)).
    globalThis._nativeDevSetLaitelaDifficultyTier = function (n) {
        try {
            var t = Math.max(0, Math.min(8, Math.floor(Number(n) || 0)));
            player.celestials.laitela.difficultyTier = t;
            if (t > 0 && (!player.celestials.laitela.fastestCompletion || player.celestials.laitela.fastestCompletion > 360)) {
                player.celestials.laitela.fastestCompletion = 360;
            }
            if (player.celestials.laitela.run) player.celestials.laitela.run = false;
            return "ok";
        } catch (e) { return "error"; }
    };

    globalThis._nativeDevSetDarkMatter = function (n) {
        try {
            var dm = new Decimal(Number(n) || 0);
            Currency.darkMatter.value = dm;
            // Bump `max` too so progression flags keyed off
            // Currency.darkMatter.max (annihilation requirement, milestones)
            // see the new value rather than the prior peak.
            if (Currency.darkMatter.max && Currency.darkMatter.max.lt(dm)) {
                Currency.darkMatter.max = dm;
            }
            return "ok";
        } catch (e) { return "error"; }
    };

    // Seed DMD `amount` fields back to 1 for any DMD that's currently 0.
    // Web normally does this exactly once via ImaginaryUpgrade(15..18)'s
    // onPurchased hook (imaginary-upgrades.js:93). After Laitela.reset() / a
    // bad save migration, those amounts can fall to 0, at which point DMD
    // production is stuck at zero (production = amount × ticks × powerDM)
    // and DM never grows again. Calling this re-bootstraps the chain
    // without forcing a full Laitela.reset.
    globalThis._nativeDevSeedDMDs = function () {
        try {
            if (typeof globalThis._nativeHealDMDs !== "function") return "no-heal";
            globalThis._nativeHealDMDs();
            return "ok";
        } catch (e) { return "error"; }
    };
    globalThis._nativeDevSetDarkEnergy = function (n) {
        try { Currency.darkEnergy.value = Number(n) || 0; return "ok"; } catch (e) { return "error"; }
    };
    globalThis._nativeDevSetSingularities = function (n) {
        try { Currency.singularities.value = Number(n) || 0; return "ok"; } catch (e) { return "error"; }
    };
    globalThis._nativeDevSetImaginaryMachines = function (n) {
        try { Currency.imaginaryMachines.value = Number(n) || 0; return "ok"; } catch (e) { return "error"; }
    };

    // ====================================================================
    //  Pelle — final celestial.
    //  Phase 1 scaffolding: returns the minimal state set the iOS PelleTab
    //  needs to render the pre-doom requirements gate, the "Doom Your
    //  Reality" entry button, the post-doom currency header, and Armageddon
    //  affordances. Phase 3-6 fill in strikes/rifts/upgrades/galaxy data.
    //
    //  Web references:
    //    src/core/celestials/pelle/pelle.js
    //    src/components/tabs/celestial-pelle/PelleTab.vue
    //    src/core/secret-formula/celestials/pelle-rebuyables.js
    // ====================================================================

    // Canonical disabled-item registries. Static post-init — call once at
    // startup, cache Swift-side, never re-poll. Mirrors `pelle.js:184-204`
    // getters which all return literal arrays (no game-state inputs).
    //
    // Returns JSON: { disabledAchievements: [Int], uselessTimeStudies: [Int],
    // uselessPerks: [Int], disabledRUPGs: [Int], uselessInfinityUpgrades: [String] }
    //
    // The Swift port previously hardcoded these sets in their respective tab
    // files (pelleUselessPerks in PerksTab.swift, etc.) — replaced by reads
    // from this bridge so the lists never drift from upstream JS.
    globalThis._nativePelleDisabledLists = function () {
        try {
            if (typeof Pelle === "undefined" || !Pelle) {
                return JSON.stringify({
                    disabledAchievements: [], uselessTimeStudies: [],
                    uselessPerks: [], disabledRUPGs: [],
                    uselessInfinityUpgrades: []
                });
            }
            return JSON.stringify({
                disabledAchievements: Pelle.disabledAchievements || [],
                uselessTimeStudies: Pelle.uselessTimeStudies || [],
                uselessPerks: Pelle.uselessPerks || [],
                disabledRUPGs: Pelle.disabledRUPGs || [],
                uselessInfinityUpgrades: Pelle.uselessInfinityUpgrades || []
            });
        } catch (e) {
            return JSON.stringify({
                disabledAchievements: [], uselessTimeStudies: [],
                uselessPerks: [], disabledRUPGs: [],
                uselessInfinityUpgrades: []
            });
        }
    };

    globalThis._nativePelleState = function () {
        var out = {
            ready: false,
            isUnlocked: false,
            canDoom: false,
            isDoomed: false,
            preDoomRequirements: [],
            remnantsText: "0",
            realityShardsText: "0",
            realityShardsPerSecText: "0/s",
            // `Pelle.riftDrainPercent` is the static 3% drain rate
            // (`pelle.js:313-315`). Pulled here so iOS can render the
            // "When active, Rifts consume X% per second." flavor text
            // without hardcoding the value Swift-side.
            riftDrainPercentText: "0%",
            armageddon: { canArmageddon: false, remnantsGainText: "0", realityShardsRateText: "0/s", realityShardsRateAfterText: "0/s", resetSummaryText: "" },
            rebuyableUpgrades: [],
            oneTimeUpgrades: [],
            strikes: [],
            rifts: [],
            galaxyGenerator: { panelVisible: false, isUnlocked: false, spentGalaxies: 0, generatedGalaxies: 0, phase: 0,
                               sacrificeActive: false, sacrificeProgressText: "",
                               galaxiesText: "0", capText: "0", gainPerSecText: "0/s", isCapped: false,
                               capRiftCycledName: "", phaseCompletionText: "", timeToCapText: "",
                               generatedGalaxiesText: "0", barFraction: 0,
                               upgrades: [] },
            disabledMechanics: [],
            collapsed: { upgrades: false, galaxies: false, rifts: false },
            showBought: true,
            specialGlyphEffectText: "",
            specialGlyphEffectUnlocked: false,
            glyphMaxLevel: 0,
            glyphRarityText: "0%",
            remnantGainBreakdown: []
        };
        try {
            if (typeof Pelle === "undefined" || !Pelle) return JSON.stringify(out);
            out.ready = true;
            out.isUnlocked = !!Pelle.isUnlocked;
            out.isDoomed = !!Pelle.isDoomed;
            // `Pelle.riftDrainPercent` is currently a literal 0.03; route
            // through formatPercents so any future upstream change carries
            // through automatically.
            try {
                var rdp = (typeof Pelle.riftDrainPercent === "number") ? Pelle.riftDrainPercent : 0.03;
                out.riftDrainPercentText = (typeof formatPercents === "function") ? formatPercents(rdp) : (Math.round(rdp * 100) + "%");
            } catch (e) { out.riftDrainPercentText = "3%"; }

            // Pre-doom requirements: achievement rows + alchemy resource caps.
            // Mirrors PelleTab.vue computed (completedRows / cappedResources).
            // Populated whenever the player is not doomed — regardless of
            // `Pelle.isUnlocked` — so the pre-Lai'tela view also shows the
            // progress numbers (matches Vue, which renders the requirements
            // line without an "is Pelle unlocked yet" gate). iOS still
            // surfaces these as 0/total for fresh saves.
            if (!out.isDoomed) {
                try {
                    var totalRows = (typeof Achievements !== "undefined" && Achievements.prePelleRows)
                        ? Achievements.prePelleRows.length : 0;
                    var completedRows = (totalRows > 0)
                        ? Achievements.prePelleRows.countWhere(function (r) { return r.every(function (a) { return a.isUnlocked; }); })
                        : 0;
                    out.preDoomRequirements.push({
                        id: "achievements",
                        label: "Achievement rows complete",
                        progressText: completedRows + "/" + totalRows,
                        isMet: completedRows === totalRows && totalRows > 0,
                        total: totalRows,
                        completed: completedRows
                    });
                    var totalAlc = (typeof AlchemyResources !== "undefined" && AlchemyResources.all)
                        ? AlchemyResources.all.length : 0;
                    var cappedAlc = (totalAlc > 0)
                        ? AlchemyResources.all.countWhere(function (r) { return r.capped; })
                        : 0;
                    out.preDoomRequirements.push({
                        id: "alchemy",
                        label: "Alchemy resources capped",
                        progressText: cappedAlc + "/" + totalAlc,
                        isMet: cappedAlc === totalAlc && totalAlc > 0,
                        total: totalAlc,
                        completed: cappedAlc
                    });
                    out.canDoom = (completedRows === totalRows && totalRows > 0)
                                  && (cappedAlc === totalAlc && totalAlc > 0);
                } catch (e) { /* leave canDoom = false */ }
            }

            // Currency display — Remnants + Reality Shards. Both are
            // Decimals (NOT plain JS numbers / ints) — Pelle.cel.remnants
            // is `new Decimal(0)` from pelle.js. Format with `(2, 2)` to
            // always preserve 2 decimal places: a value of 0.42 must NOT
            // round to "0", and the user explicitly asked for double-style
            // display, not int-style.
            try {
                if (Pelle.cel) {
                    var rem = Pelle.cel.remnants;
                    out.remnantsText = (typeof format === "function") ? format(rem || 0, 2, 2) : String(rem || 0);
                    var rs = Pelle.cel.realityShards;
                    out.realityShardsText = (typeof format === "function") ? format(rs || 0, 2, 2) : String(rs || 0);
                    // `realityShardGainPerSecond` and `nextRealityShardGain`
                    // are GETTERS (defined as `get realityShardGainPerSecond()`
                    // in pelle.js) — calling them with `()` throws and the
                    // old `typeof === "function"` guard always failed,
                    // leaving the rate stuck at the initial "0/s".
                    var rate = Pelle.realityShardGainPerSecond;
                    if (rate !== undefined && rate !== null) {
                        out.realityShardsPerSecText = ((typeof format === "function") ? format(rate, 2, 2) : String(rate)) + "/s";
                    }
                    // Web `PelleUpgradePanel.vue:15` defaults `showBought: false`
                    // (bought hidden). Use truthy coercion so undefined →
                    // false, matching the web data() default.
                    out.showBought = !!Pelle.cel.showBought;
                    if (Pelle.cel.collapsed) {
                        out.collapsed.upgrades = !!Pelle.cel.collapsed.upgrades;
                        out.collapsed.galaxies = !!Pelle.cel.collapsed.galaxies;
                        out.collapsed.rifts = !!Pelle.cel.collapsed.rifts;
                    }
                }
            } catch (e) {}

            // Armageddon affordance — also surfaces the post-Armageddon
            // rate (`nextRealityShardGain`) so the in-tab Armageddon
            // button matches the header banner's "X/s ➔ Y/s" readout.
            try {
                if (out.isDoomed) {
                    var canArm = !!Pelle.canArmageddon;
                    out.armageddon.canArmageddon = canArm;
                    var remGain = Pelle.remnantsGain;
                    out.armageddon.remnantsGainText = (typeof format === "function") ? format(remGain || 0, 2, 2) : String(remGain || 0);
                    var rateNow = Pelle.realityShardGainPerSecond;
                    if (rateNow !== undefined && rateNow !== null) {
                        out.armageddon.realityShardsRateText = ((typeof format === "function") ? format(rateNow, 2, 2) : String(rateNow)) + "/s";
                    }
                    var rateNext = Pelle.nextRealityShardGain;
                    if (rateNext !== undefined && rateNext !== null) {
                        out.armageddon.realityShardsRateAfterText = ((typeof format === "function") ? format(rateNext, 2, 2) : String(rateNext)) + "/s";
                    }
                }
            } catch (e) {}

            // Remnant Gain Factors — mirrors RemnantGainFactor.vue. Skipped
            // pre-doom because the records don't exist yet.
            try {
                if (out.isDoomed && Pelle.cel && Pelle.cel.records) {
                    var bestAM = Pelle.cel.records.totalAntimatter;
                    var bestIP = Pelle.cel.records.totalInfinityPoints;
                    var bestEP = Pelle.cel.records.totalEternityPoints;
                    var dMult = (PelleStrikes.dilation && PelleStrikes.dilation.hasStrike) ? [500, 10, 5] : [1, 1, 1];
                    var amTerm = Math.log10(bestAM.add(1).log10() * dMult[0] + 2);
                    var ipTerm = Math.log10(bestIP.add(1).log10() * dMult[1] + 2);
                    var epTerm = Math.log10(bestEP.add(1).log10() * dMult[2] + 2);
                    var remnants = Pelle.cel.remnants;
                    var remGainFinal = Pelle.remnantsGain;
                    var fmt = function (n, lo, hi) {
                        return (typeof format === "function") ? format(n, lo, hi) : String(n);
                    };
                    var amDilSuffix = dMult[0] > 1 ? "*" + dMult[0] : "";
                    var ipDilSuffix = dMult[1] > 1 ? "*" + dMult[1] : "";
                    var epDilSuffix = dMult[2] > 1 ? "*" + dMult[2] : "";
                    out.remnantGainBreakdown = [
                        { id: "best-am",  label: "Best AM",                                              value: fmt(bestAM, 2, 2),  isTotal: false },
                        { id: "best-ip",  label: "Best IP",                                              value: fmt(bestIP, 2, 2),  isTotal: false },
                        { id: "best-ep",  label: "Best EP",                                              value: fmt(bestEP, 2, 2),  isTotal: false },
                        { id: "amTerm",   label: "log10(log10(am)" + amDilSuffix + " + 2)",              value: fmt(amTerm, 2, 2),  isTotal: false },
                        { id: "ipTerm",   label: "+ log10(log10(ip)" + ipDilSuffix + " + 2)",            value: fmt(ipTerm, 2, 2),  isTotal: false },
                        { id: "epTerm",   label: "+ log10(log10(ep)" + epDilSuffix + " + 2)",            value: fmt(epTerm, 2, 2),  isTotal: false },
                        { id: "divisor",  label: "/ Static divisor",                                     value: fmt(1.64, 2, 2),    isTotal: false },
                        { id: "power",    label: "^ Static power",                                       value: fmt(7.5, 2, 2),     isTotal: false },
                        { id: "existing", label: "− Existing Remnants",                                  value: fmt(remnants, 2, 2),isTotal: false },
                        { id: "total",    label: "Final amount",                                         value: fmt(remGainFinal, 2, 2), isTotal: true }
                    ];
                }
            } catch (e) {}

            // Strikes — only render once doomed (web's PelleBarPanel has the
            // same gate). Mirrors `PelleStrikes.all` in
            // src/core/celestials/pelle/strikes.js + secret-formula
            // strikes.js. `name` is a short display label derived from the
            // config key; full descriptive text lives in requirement/penalty/
            // reward fields.
            if (out.isDoomed && typeof PelleStrikes !== "undefined" && PelleStrikes && PelleStrikes.all) {
                var strikeNames = {
                    1: "Infinity", 2: "Power Galaxies", 3: "Eternity",
                    4: "115 Time Theorems", 5: "Dilation"
                };
                for (var si = 0; si < PelleStrikes.all.length; si++) {
                    var s = PelleStrikes.all[si];
                    if (!s) continue;
                    var riftKey = "";
                    try { riftKey = (s.rift && s.rift.config && s.rift.config.key) || ""; } catch (e) {}
                    var rewardText = "";
                    try { rewardText = normPelleText(s.reward()); } catch (e) {}
                    out.strikes.push({
                        id: s.id,
                        name: strikeNames[s.id] || ("Strike " + s.id),
                        hasStrike: !!s.hasStrike,
                        // wordCycle padding preserved — see `normPelleText`.
                        requirementText: normPelleText(s.requirement),
                        penaltyText: normPelleText(s.penalty),
                        rewardText: rewardText,
                        riftId: riftKey
                    });
                }
            }

            // Rifts — also gated on doomed, but we always include the array
            // shape so Swift can render the panel scaffolding before any
            // strike triggers. Each rift's full milestone roster comes along
            // for the detail sheet; the milestones array is small (≤4 per
            // rift) so the per-tick cost is negligible.
            if (out.isDoomed && typeof PelleRifts !== "undefined" && PelleRifts && PelleRifts.all) {
                // Stable-color palette per rift key. Web uses CSS variables
                // for these — we hard-code matching values so iOS doesn't
                // need to re-extract them every tick.
                var riftColors = {
                    vacuum:    "#ff7300",  // orange
                    decay:     "#b07cd6",  // purple
                    chaos:     "#ff5959",  // red
                    recursion: "#67d6ff",  // cyan
                    paradox:   "#fff04f"   // yellow
                };
                for (var ri = 0; ri < PelleRifts.all.length; ri++) {
                    var rift = PelleRifts.all[ri];
                    if (!rift) continue;
                    var key = (rift.config && rift.config.key) || "";
                    var displayName = "";
                    var nameList = null;
                    try {
                        var nameField = rift.name;
                        if (Array.isArray(nameField)) {
                            nameList = nameField;
                            displayName = nameField[0] || "";
                        } else {
                            displayName = nameField || "";
                        }
                    } catch (e) {}
                    // wordCycle the rift title (web: PelleRift.vue line 66 —
                    // wordShift.wordCycle(rift.name, true)). noBuffer = true
                    // since the title has its own line.
                    var cycledName = nameList ? pelleWordCycle(nameList, true) : displayName;
                    var fillCurrencyName = "";
                    try { fillCurrencyName = rift.config.drainResource || ""; } catch (e) {}
                    // Chaos drain resource cycles the Decay rift names
                    // (web: PelleRiftBar.vue line 59).
                    var cycledFillCurrencyName = fillCurrencyName;
                    try {
                        if (rift.id === 3 && PelleRifts.decay && Array.isArray(PelleRifts.decay.name)) {
                            cycledFillCurrencyName = pelleWordCycle(PelleRifts.decay.name, false);
                        }
                    } catch (e) {}
                    var rReducedTo = rift.reducedTo || 0;
                    var milestonesOut = [];
                    try {
                        for (var mi = 0; mi < rift.milestones.length; mi++) {
                            var m = rift.milestones[mi];
                            var req = m.config.requirement || 0;
                            milestonesOut.push({
                                id: key + "-" + (mi + 1),
                                thresholdPct: req * 100,
                                requirementText: formatPercents(req, 0),
                                // Some rift milestones use wordCycle in their
                                // description — preserve padding to keep the
                                // milestone sheet from twitching every poll.
                                effectText: normPelleText(m.description),
                                isUnlocked: !!m.isUnlocked,
                                // Web: PelleRiftBar.vue dims milestones whose
                                // requirement is above the rift's reducedTo
                                // (cap from sacrifice). Disabled marks no
                                // pulse + brightness 0.25.
                                isDisabled: req > rReducedTo
                            });
                        }
                    } catch (e) {}
                    // "Drains X to fill" / "Current Amount" / "Total Filled"
                    // flavor text mirrors web `PelleRift.vue:107-119`. Web's
                    // `formatRift(value)` (line 62) treats numbers as percentages
                    // (decay rift) and Decimals normally — replicated here.
                    var formatRiftValue = function (v) {
                        if (typeof v === "number") {
                            return (typeof formatInt === "function") ? (formatInt(100 * v) + "%") : (Math.round(100 * v) + "%");
                        }
                        return (typeof format === "function") ? format(v, 2) : String(v);
                    };
                    var currentFillText = "";
                    var totalFillText = "";
                    try {
                        if (rift.fillCurrency && typeof rift.fillCurrency.value !== "undefined") {
                            currentFillText = formatRiftValue(rift.fillCurrency.value);
                        }
                    } catch (e) {}
                    try {
                        totalFillText = formatRiftValue(rift.totalFill);
                    } catch (e) {}
                    // Rift reward effects (web: PelleRift.vue:88-95 renders
                    // `rift.effects`). The `effects` getter returns
                    // `[baseEffect(effectValue), ...additionalEffects.formattedEffect]`
                    // — already-formatted strings describing the reward you get
                    // from draining this rift (e.g. Vacuum/"Void" → "IP gain ×X",
                    // its EP-gain milestone effect, etc.). Without this the iOS
                    // rift card never showed the drain reward at all.
                    var riftEffects = [];
                    try {
                        var effArr = rift.effects;
                        if (Array.isArray(effArr)) {
                            for (var efi = 0; efi < effArr.length; efi++) {
                                var effStr = effArr[efi];
                                if (effStr !== null && typeof effStr !== "undefined" && effStr !== "") {
                                    riftEffects.push(normText(effStr));
                                }
                            }
                        }
                    } catch (e) {}
                    out.rifts.push({
                        id: key,
                        name: displayName,
                        cycledName: cycledName,
                        fillCurrencyName: fillCurrencyName,
                        cycledFillCurrencyName: cycledFillCurrencyName,
                        percentage: rift.percentage || 0,
                        realPercentage: rift.realPercentage || 0,
                        reducedTo: rReducedTo,
                        isActive: !!rift.isActive,
                        isMaxed: !!rift.isMaxed,
                        isSpendable: !!(rift.config && rift.config.spendable),
                        hexColor: riftColors[key] || "#ffffff",
                        milestones: milestonesOut,
                        currentFillText: currentFillText,
                        totalFillText: totalFillText,
                        effects: riftEffects
                    });
                }
            }

            // Upgrades shop (Phase 4) — gated on doomed because purchases
            // require Pelle.isDoomed (PelleUpgradeState.isAvailableForPurchase
            // line 432). The 5 rebuyables (PelleUpgrade.rebuyables) come first,
            // then the ~23 one-times (PelleUpgrade.singles), already sorted
            // by ascending cost on the JS side.
            if (out.isDoomed && typeof PelleUpgrade !== "undefined" && PelleUpgrade) {
                // Friendly display titles for the 5 rebuyables (web shows the
                // description as both heading and body; we split for readability).
                var rebuyableTitles = {
                    antimatterDimensionMult: "Antimatter Dim Mult",
                    timeSpeedMult: "Time Speed",
                    glyphLevels: "Glyph Levels",
                    infConversion: "Infinity Conversion",
                    galaxyPower: "Galaxy Power"
                };
                // Reality Shards / sec — used for time-to-afford on every
                // Pelle upgrade card. Pull once for the whole loop so we
                // don't re-evaluate the getter per upgrade.
                var rsCurrent = (Pelle.cel && Pelle.cel.realityShards) || new Decimal(0);
                var rsRatePerSec = Pelle.realityShardGainPerSecond;
                // Format a Decimal-seconds value in the user-requested
                // bucket scheme: seconds → HH:MM:SS → days → years. Avoids
                // the Decimal-to-Number coercion bug that broke the
                // earlier TimeSpan.fromMilliseconds path (TimeSpan's
                // constructor uses Guard.isNumber, throws on a Decimal).
                function fmtPelleETA(secondsDec) {
                    try {
                        if (!secondsDec) return "";
                        var pad = function (n) { var s = String(Math.floor(n)); return s.length < 2 ? "0" + s : s; };
                        // Bail out before NaN-converting the Decimal —
                        // anything > ~1e15 years isn't useful.
                        if (typeof secondsDec.gt === "function" && secondsDec.gt(new Decimal("1e30"))) {
                            return "> " + ((typeof format === "function")
                                ? format(secondsDec.div(31557600), 2, 0)
                                : "1e30") + " years";
                        }
                        var n = (typeof secondsDec.toNumber === "function") ? secondsDec.toNumber() : Number(secondsDec);
                        if (!isFinite(n) || isNaN(n)) return "";
                        if (n < 1) return "< 1 second";
                        if (n < 60) return Math.floor(n) + (Math.floor(n) === 1 ? " second" : " seconds");
                        if (n < 86400) {
                            var hh = Math.floor(n / 3600);
                            var mm = Math.floor((n % 3600) / 60);
                            var ss = Math.floor(n % 60);
                            return pad(hh) + ":" + pad(mm) + ":" + pad(ss);
                        }
                        var days = n / 86400;
                        if (days < 365.25) return ((typeof format === "function") ? format(days, 2, 1) : days.toFixed(1)) + " days";
                        var years = days / 365.25;
                        return ((typeof format === "function") ? format(years, 2, 2) : years.toFixed(2)) + " years";
                    } catch (e) { return ""; }
                }
                function pelleTimeToAfford(cost) {
                    try {
                        if (!cost) return "";
                        var diff = (typeof cost.minus === "function")
                            ? cost.minus(rsCurrent)
                            : new Decimal(cost).minus(rsCurrent);
                        if (typeof diff.lte === "function" && diff.lte(0)) return "Now";
                        if (!rsRatePerSec) return "—";
                        var rate = rsRatePerSec;
                        var rateIsZero = typeof rate.lte === "function" ? rate.lte(0) : !(rate > 0);
                        if (rateIsZero) return "Never (no Remnants)";
                        var seconds = (typeof diff.div === "function") ? diff.div(rate) : diff / rate;
                        return fmtPelleETA(seconds);
                    } catch (e) { return ""; }
                }
                try {
                    var rebuy = PelleUpgrade.rebuyables || [];
                    for (var ri2 = 0; ri2 < rebuy.length; ri2++) {
                        var u = rebuy[ri2];
                        if (!u) continue;
                        var key = String(u.id);
                        var bought = u.boughtAmount || 0;
                        var cap = (u.config && u.config.cap) || 0;
                        var capped = !!u.isCapped;
                        var costVal = u.cost;
                        var effectVal = u.effectValue;
                        var nextEffectVal;
                        try { nextEffectVal = u.config.effect(bought + 1); } catch (e) { nextEffectVal = null; }
                        var fmt = (u.config && u.config.formatEffect) ? u.config.formatEffect : function (x) { return String(x); };
                        out.rebuyableUpgrades.push({
                            id: key,
                            name: rebuyableTitles[key] || key,
                            // RebuyablePelleUpgradeState extends
                            // RebuyableMechanicState which has no
                            // `description` getter — `u.description` is
                            // therefore undefined. Pull from `u.config.description`
                            // (the destructured-into-factory string).
                            description: normText((u.config && u.config.description) || u.description || ""),
                            effectText: (function () { try { return fmt(effectVal); } catch (e) { return ""; } })(),
                            nextEffectText: (capped || nextEffectVal == null)
                                ? ""
                                : (function () { try { return fmt(nextEffectVal); } catch (e) { return ""; } })(),
                            costText: capped ? "Capped" : ((typeof format === "function") ? format(costVal, 2) : String(costVal)),
                            costCurrencyName: "Reality Shards",
                            rebuyable: true,
                            boughtAmount: bought,
                            maxAmount: cap,
                            isBought: capped,           // visual reuse: capped ≈ bought
                            isAffordable: !capped && !!u.canBeBought,
                            isAvailable: true,
                            requirementText: "",
                            timeToAffordText: capped ? "" : pelleTimeToAfford(costVal)
                        });
                    }
                } catch (e) {}

                // One-time upgrades (PelleUpgrade.singles, already sorted by cost).
                // Hide bought entries when player.celestials.pelle.showBought
                // is false — web `PelleUpgradePanel.vue` does the same toggle.
                try {
                    var singles = PelleUpgrade.singles || [];
                    // Web defaults `showBought: false` (bought hidden) — see
                    // PelleUpgradePanel.vue:15. Truthy coercion matches that
                    // default; the prior `!== false` form treated undefined
                    // as TRUE, which made fresh saves render bought + unbought
                    // by default contrary to web.
                    var showBought = !!(Pelle.cel && Pelle.cel.showBought);
                    for (var si2 = 0; si2 < singles.length; si2++) {
                        var s2 = singles[si2];
                        if (!s2) continue;
                        var bought2 = !!s2.isBought;
                        if (bought2 && !showBought) continue;
                        out.oneTimeUpgrades.push({
                            id: String(s2.id),
                            name: "",
                            description: normText(s2.description || ""),
                            effectText: "",
                            nextEffectText: "",
                            costText: bought2 ? "Bought" : ((typeof format === "function") ? format(s2.cost, 2) : String(s2.cost)),
                            costCurrencyName: "Reality Shards",
                            rebuyable: false,
                            boughtAmount: 0,
                            maxAmount: 0,
                            isBought: bought2,
                            isAffordable: !bought2 && !!s2.canBeBought,
                            isAvailable: !!s2.isAvailableForPurchase,
                            requirementText: "",
                            timeToAffordText: bought2 ? "" : pelleTimeToAfford(s2.cost)
                        });
                    }
                } catch (e) {}
            }

            // Galaxy Generator (Phase 5). Hidden until recursion's 3rd
            // milestone is reached OR you've already spent galaxies.
            // Mirrors PelleTab.vue `hasGalaxyGenerator` gate.
            if (out.isDoomed && typeof GalaxyGenerator !== "undefined" && GalaxyGenerator) {
                try {
                    // Panel visibility — web PelleTab.vue `hasGalaxyGenerator`
                    // (recursion milestone 3 reached, OR galaxies already spent).
                    var ggPanelVisible = false;
                    try {
                        ggPanelVisible = !!(PelleRifts.recursion.milestones[2].canBeApplied
                                            || GalaxyGenerator.spentGalaxies > 0);
                    } catch (e) { ggPanelVisible = (GalaxyGenerator.spentGalaxies || 0) > 0; }
                    out.galaxyGenerator.panelVisible = ggPanelVisible;
                    // Actual unlock flag — web `Pelle.hasGalaxyGenerator` getter,
                    // i.e. whether the in-panel "Unlock the Galaxy Generator"
                    // button has been clicked. Distinct from panel visibility.
                    out.galaxyGenerator.isUnlocked = !!((player.celestials.pelle.galaxyGenerator || {}).unlocked);
                    out.galaxyGenerator.spentGalaxies = GalaxyGenerator.spentGalaxies || 0;
                    out.galaxyGenerator.generatedGalaxies = GalaxyGenerator.generatedGalaxies || 0;
                    out.galaxyGenerator.phase = (player.celestials.pelle.galaxyGenerator || {}).phase || 0;
                    out.galaxyGenerator.sacrificeActive = !!GalaxyGenerator.sacrificeActive;
                    // Web `PelleGalaxyGeneratorPanel.vue:53` displays
                    //     player.galaxies + GalaxyGenerator.galaxies
                    // (i.e. regular antimatter-tier Galaxies plus generated
                    // minus spent). Using GG.galaxies alone goes negative
                    // immediately after a buy because spent exceeds the
                    // newly-generated count until the loop catches up.
                    try {
                        var galN = (player.galaxies || 0) + (GalaxyGenerator.galaxies || 0);
                        if (galN == null || isNaN(galN)) galN = 0;
                        out.galaxyGenerator.galaxiesText = (typeof format === "function")
                            ? format(galN, 2, 2)
                            : String(galN);
                    } catch (eGal) {
                        out.galaxyGenerator.galaxiesText = "0";
                    }
                    var cap = GalaxyGenerator.generationCap;
                    try {
                        out.galaxyGenerator.capText = (cap === Infinity)
                            ? "∞"
                            : ((typeof format === "function") ? format(cap, 2, 0) : String(cap));
                    } catch (eCap) { out.galaxyGenerator.capText = "?"; }
                    out.galaxyGenerator.isCapped = !!GalaxyGenerator.isCapped;
                    var gps = 0;
                    try { gps = GalaxyGenerator.gainPerSecond || 0; } catch (eGps) { gps = 0; }
                    try {
                        out.galaxyGenerator.gainPerSecText =
                            ((typeof format === "function") ? format(gps, 2, 2) : String(gps)) + "/s";
                    } catch (eGpsT) { out.galaxyGenerator.gainPerSecText = String(gps) + "/s"; }
                    try {
                        out.galaxyGenerator.generatedGalaxiesText = (typeof format === "function")
                            ? format(GalaxyGenerator.generatedGalaxies || 0, 2, 2)
                            : String(GalaxyGenerator.generatedGalaxies || 0);
                    } catch (eGen) {
                        out.galaxyGenerator.generatedGalaxiesText = String(GalaxyGenerator.generatedGalaxies || 0);
                    }
                    // Bar fill fraction. Web `PelleGalaxyGeneratorPanel.vue`:
                    //   barWidth = isCapped ? capRift.reducedTo : (generated/cap)^0.45
                    // Clamp 0..1 for safety. Used by the iOS panel to render
                    // the big fill bar across the panel.
                    var barFrac = 0;
                    try {
                        var capRiftLocal = GalaxyGenerator.capRift;
                        if (GalaxyGenerator.isCapped && capRiftLocal) {
                            barFrac = capRiftLocal.reducedTo || 0;
                        } else if (cap > 0 && cap !== Infinity) {
                            var ratio = (GalaxyGenerator.generatedGalaxies || 0) / cap;
                            if (ratio > 0) barFrac = Math.pow(ratio, 0.45);
                        }
                    } catch (e) {}
                    if (!isFinite(barFrac)) barFrac = 0;
                    out.galaxyGenerator.barFraction = Math.max(0, Math.min(1, barFrac));
                    // Cap-rift cycled name (web: PelleGalaxyGeneratorPanel.vue
                    // line 60 — wordShift.wordCycle(capRift.name)). Available
                    // whenever there's a cap rift, regardless of sacrifice
                    // state, so the sacrifice card can render the cycled
                    // "Sacrifice your Decay/Collapse/Disarray" copy.
                    var capRift = GalaxyGenerator.capRift;
                    if (capRift) {
                        try {
                            var capList = capRift.name;
                            out.galaxyGenerator.capRiftCycledName = Array.isArray(capList)
                                ? pelleWordCycle(capList, false)
                                : (capList || "");
                        } catch (e) { out.galaxyGenerator.capRiftCycledName = ""; }
                    }
                    if (out.galaxyGenerator.sacrificeActive) {
                        // Sacrifice drains capRift.reducedTo from 1 → 0 at 3%/s.
                        // Show a 0..100% progress that fills as reducedTo falls.
                        try {
                            if (capRift) {
                                var pct = Math.max(0, Math.min(1, 1 - capRift.reducedTo)) * 100;
                                out.galaxyGenerator.sacrificeProgressText = pct.toFixed(1) + "%";
                                // Phase ETA — drain rate is 3%/s (galaxy-generator.js:74),
                                // so seconds remaining = reducedTo / 0.03.
                                var phaseSecs = (capRift.reducedTo || 0) / 0.03;
                                if (phaseSecs > 0) {
                                    out.galaxyGenerator.phaseCompletionText = fmtPelleETA(new Decimal(phaseSecs));
                                }
                            }
                        } catch (eSac) {}
                    }
                    // Time-to-cap (next-galaxy ETA). Wrapped so a Decimal /
                    // fmtPelleETA hiccup can't bubble out of the GG block.
                    try {
                        if (!out.galaxyGenerator.isCapped && cap !== Infinity && gps > 0) {
                            var remaining = cap - (GalaxyGenerator.generatedGalaxies || 0);
                            if (remaining > 0 && isFinite(remaining)) {
                                out.galaxyGenerator.timeToCapText = fmtPelleETA(new Decimal(remaining / gps));
                            }
                        }
                    } catch (eTtc) {}
                    // Upgrades — 5 of them, each on a different currency.
                    // Pull `name` from `ug.config.description` so the card
                    // matches web copy verbatim ("Increase base Galaxy
                    // generation by 2", "Multiply Galaxy generation"). Hard-
                    // coded fallbacks only if a config lookup fails.
                    var ggKeys = ["additive", "multiplicative", "antimatterMult", "IPMult", "EPMult"];
                    var ggDisplayKeys = ["additive", "multiplicative", "antimatterMult", "ipMult", "epMult"];
                    var ggFallbackDescriptions = {
                        additive: "Increase base Galaxy generation",
                        multiplicative: "Multiply Galaxy generation",
                        antimatterMult: "Multiply Galaxy generation",
                        ipMult: "Multiply Galaxy generation",
                        epMult: "Multiply Galaxy generation"
                    };
                    for (var gi = 0; gi < ggKeys.length; gi++) {
                        // Wrap every iteration so a single upgrade's cost /
                        // effect / canBeBought getter throwing can't wipe the
                        // entire upgrades list. (We previously saw all 5
                        // cards disappear after buying additive — a downstream
                        // throw bubbled to the outer GG try/catch and reset
                        // `upgrades` to `[]`.)
                        try {
                            var jsKey = ggKeys[gi];
                            var dispKey = ggDisplayKeys[gi];
                            var ug = GalaxyGeneratorUpgrades[jsKey];
                            if (!ug) continue;
                            var ugDesc = "";
                            try {
                                ugDesc = (ug.config && ug.config.description) ? String(ug.config.description) : "";
                            } catch (eDesc) { ugDesc = ""; }
                            if (!ugDesc) ugDesc = ggFallbackDescriptions[dispKey] || jsKey;
                            ugDesc = normText(ugDesc);
                            var ueffect; try { ueffect = ug.effectValue; } catch (eEff) { ueffect = null; }
                            var unext;
                            try { unext = ug.config.effect((ug.boughtAmount || 0) + 1); } catch (eNext) { unext = null; }
                            var uFmt = (ug.config && ug.config.formatEffect) ? ug.config.formatEffect : function (x) { return String(x); };
                            var uCurrency = (ug.config && ug.config.currencyLabel) || "";
                            var uBought = 0;
                            try { uBought = ug.boughtAmount || 0; } catch (eBought) { uBought = 0; }
                            var uAffordable = false;
                            try { uAffordable = !!ug.canBeBought; } catch (eAfford) { uAffordable = false; }
                            var uCostText = "";
                            try {
                                var rawCost = ug.cost;
                                uCostText = (typeof format === "function") ? format(rawCost, 2) : String(rawCost);
                            } catch (eCost) { uCostText = "?"; }
                            // Per-upgrade ETA — only galaxy-cost upgrades get
                            // a useful "(cost - have) / rate" estimate; AM/IP/EP
                            // costs have no single per-tick rate available here.
                            var ttaText = "";
                            try {
                                if ((dispKey === "additive" || dispKey === "multiplicative")
                                    && !uAffordable && gps > 0) {
                                    var costNum = (typeof ug.cost === "number") ? ug.cost
                                        : (ug.cost && typeof ug.cost.toNumber === "function" ? ug.cost.toNumber() : Number(ug.cost));
                                    var haveNum = GalaxyGenerator.galaxies || 0;
                                    if (isFinite(costNum) && costNum > haveNum) {
                                        ttaText = fmtPelleETA(new Decimal((costNum - haveNum) / gps));
                                    }
                                }
                            } catch (eEta) {}
                            out.galaxyGenerator.upgrades.push({
                                id: dispKey,
                                name: ugDesc,
                                bought: uBought,
                                costText: uCostText,
                                costCurrencyName: uCurrency,
                                effectText: (function () { try { return ueffect == null ? "" : uFmt(ueffect); } catch (e) { return ""; } })(),
                                nextEffectText: unext == null ? "" : (function () { try { return uFmt(unext); } catch (e) { return ""; } })(),
                                isAffordable: uAffordable,
                                timeToAffordText: ttaText
                            });
                        } catch (eUpg) { /* skip this upgrade — preserve the others */ }
                    }
                } catch (e) { /* GG block failed; leave defaults */ }
            }

            // Disabled-mechanics list (Phase 8) — direct port of the strings
            // in PelleEffectsModal.vue. We keep the JS-side build so live
            // `format()` calls honor the player's selected notation.
            if (out.isDoomed) {
                try {
                    var fmt = (typeof format === "function") ? format : function (x) { return String(x); };
                    var fmtP = (typeof formatPercents === "function") ? formatPercents : function (x) { return (x * 100).toFixed(0) + "%"; };
                    var fmtI = (typeof formatInt === "function") ? formatInt : function (x) { return String(x); };
                    var fmtX = (typeof formatX === "function") ? formatX : function (x) { return "x" + String(x); };
                    var nerfs = [
                        // Numerical nerfs / disabled boosts
                        "Anything unlocked through a Pelle upgrade cannot be unlocked normally",
                        "All pre-Doomed IP and EP multipliers are disabled",
                        "IP generation based on fastest infinity speed is disabled",
                        "All pre-Doomed Replicanti speed multipliers are disabled",
                        "Replicanti slows down more drastically above " + fmt(Number.MAX_VALUE, 2),
                        "Most Eternity Challenges are harder",
                        "All Galaxies are only " + fmtP(0.5) + " as effective",
                        "Antimatter Dimension multiplier is divided by " + fmtI(10),
                        "Achievement multiplier and many achievement rewards are disabled",
                        "All Infinity and Eternity multipliers and generation are disabled",
                        "Black Holes are disabled",
                        "Reality Upgrade \"Temporal Transcendence\" is disabled",
                        // Initial QoL and automation
                        "All rewards which increase your starting resources except Achievement 21 are disabled",
                        "All rewards which prevent resources from being reset are disabled",
                        "Perk rewards which reduce unlock costs have been disabled, excluding the ECR group",
                        "Automatic Infinity and Eternity Challenges are disabled",
                        "All Dimension and pre-Infinity Autobuyers are disabled until reacquired through Pelle",
                        "The Time Theorem Autobuyer is disabled",
                        "All Automation related to Time Dilation or later is disabled",
                        // Time studies + Dilation
                        "Eternity Upgrade to Time Dimensions based on days played is based on this Armageddon time",
                        "All pre-Doomed Dilated Time multipliers are disabled except the " + fmtX(2) + " buyable",
                        "All Tachyon Particle multipliers are disabled",
                        "All pre-Doomed Time Theorem generation effects are disabled except the Dilation upgrade",
                        // Glyphs
                        "Glyph equipping is disabled until reacquired",
                        "Glyph levels are lowered and rarity is set to " + fmtP(0),
                        "Effects from Glyph Sacrifice, Alteration, and Alchemy are all disabled",
                        // Celestial features
                        "You cannot enter any other Celestial Realities",
                        "Music Glyphs cannot be bought",
                        "All rewards from Effarig are disabled",
                        "All features related to storing time are disabled",
                        "All rewards from V are disabled",
                        "The Teresa Level " + fmtI(1) + " effect from Ra is disabled",
                        "Infinity Upgrades cannot be charged",
                        "Triad Studies and Space Theorems are disabled",
                        "Imaginary Upgrades are disabled excluding those relating to DMD's and Celestial unlocks",
                        "Continuum and Singularity rewards are disabled"
                    ];
                    for (var ni = 0; ni < nerfs.length; ni++) {
                        out.disabledMechanics.push({
                            id: "nerf-" + ni,
                            label: nerfs[ni],
                            statusText: "",
                            unlockedByText: ""
                        });
                    }
                } catch (e) {}
            }

            // Glyph max level + special glyph effect description + rarity readout.
            // Mirrors `CurrentGlyphEffects.vue` `pelleGlyphText` + `chaosEffect`.
            try {
                if (typeof Pelle.glyphMaxLevel === "number") out.glyphMaxLevel = Math.floor(Pelle.glyphMaxLevel);
                if (Pelle.specialGlyphEffect) {
                    if (typeof Pelle.specialGlyphEffect.description === "string") {
                        out.specialGlyphEffectText = normText(Pelle.specialGlyphEffect.description);
                    }
                    out.specialGlyphEffectUnlocked = !!Pelle.specialGlyphEffect.isUnlocked;
                }
                // `Pelle.glyphStrength` → strengthToRarity(...) → formatPercents(...)
                // = the "Glyph Rarity is set to X%" readout. Pelle force-fixes
                // glyph strength to 1 (= 0% rarity) but we read it dynamically
                // anyway in case the value diverges in a future patch.
                if (typeof Pelle.glyphStrength === "number"
                    && typeof strengthToRarity === "function"
                    && typeof formatPercents === "function") {
                    out.glyphRarityText = formatPercents(strengthToRarity(Pelle.glyphStrength));
                }
            } catch (e) {}
        } catch (e) {
            out.__err = "pelleState: " + (e && e.message ? e.message : String(e));
        }
        return JSON.stringify(out);
    };

    // -- Pelle actions --
    // Doom the current Reality. Web flow: PelleTab.vue Doom button →
    // Modal.armageddon.show() → on confirm calls Pelle.initializeRun(). The
    // iOS layer already shows its own confirmation sheet (PrestigeModal.pelleDoom),
    // so this skips the web modal and calls initializeRun directly. The JS
    // method also fires the `initial` quote.
    globalThis._nativeDoomReality = function () {
        try {
            if (typeof Pelle === "undefined" || !Pelle) return "no-pelle";
            if (Pelle.isDoomed) return "already-doomed";
            Pelle.initializeRun();
            return "ok";
        } catch (e) { return "error"; }
    };

    // Trigger Armageddon while doomed. `gainStuff` defaults to true (gain
    // remnants); pass false to skip the reward (used by the JS-side
    // initializeRun path).
    globalThis._nativePelleArmageddon = function (gainStuff) {
        try {
            if (typeof Pelle === "undefined" || !Pelle || !Pelle.isDoomed) return "not-doomed";
            Pelle.armageddon(gainStuff !== false);
            return "ok";
        } catch (e) { return "error"; }
    };

    // Toggle a Pelle rift's active flag. Web's RiftState.toggle() caps active
    // rifts at 2 and surfaces a GameUI.notify.error if exceeded — which
    // routes through `_nativeNotify` to the iOS toast queue.
    globalThis._nativeTogglePelleRift = function (key) {
        try {
            if (typeof PelleRifts === "undefined" || !PelleRifts) return "no-rifts";
            var rift = PelleRifts[String(key)];
            if (!rift || typeof rift.toggle !== "function") return "no-rift";
            rift.toggle();
            return "ok";
        } catch (e) { return "error"; }
    };

    // -- Pelle upgrade actions (Phase 4) --
    //
    // Rebuyables and one-time upgrades both live on the same `PelleUpgrade`
    // namespace — keys-by-id (string for rebuyables, numeric for one-times).
    // We accept the id as a string in all cases and look up the upgrade by
    // matching `String(u.id) === id`, which works for both shapes.

    function _findPelleUpgrade(id) {
        if (typeof PelleUpgrade === "undefined" || !PelleUpgrade || !PelleUpgrade.all) return null;
        var key = String(id);
        for (var i = 0; i < PelleUpgrade.all.length; i++) {
            var u = PelleUpgrade.all[i];
            if (u && String(u.id) === key) return u;
        }
        return null;
    }

    // Single-purchase a rebuyable. Web RebuyableMechanicState.purchase()
    // handles affordability + cap + currency drain.
    globalThis._nativeBuyPelleUpgrade = function (id) {
        try {
            var u = _findPelleUpgrade(id);
            if (!u || typeof u.purchase !== "function") return "no-upgrade";
            return u.purchase() ? "ok" : "noop";
        } catch (e) { return "error"; }
    };

    // Buy as many of a rebuyable as currently affordable, in a tight loop —
    // the JS class doesn't expose a single buy-max method.
    globalThis._nativeBuyPelleRebuyableMax = function (id) {
        try {
            var u = _findPelleUpgrade(id);
            if (!u || typeof u.purchase !== "function") return "no-upgrade";
            // Cap at 1000 iterations to defend against runaway loops on
            // unexpected state — real caps are 9..44.
            for (var n = 0; n < 1000; n++) {
                if (u.isCapped || !u.canBeBought) break;
                if (!u.purchase()) break;
            }
            return "ok";
        } catch (e) { return "error"; }
    };

    // Toggle the "show bought" flag in the upgrades panel.
    globalThis._nativeTogglePelleShowBought = function () {
        try {
            if (typeof Pelle === "undefined" || !Pelle || !Pelle.cel) return "no-pelle";
            Pelle.cel.showBought = !Pelle.cel.showBought;
            return "ok";
        } catch (e) { return "error"; }
    };

    // -- Galaxy Generator actions (Phase 5) --
    //
    // Display ids ("additive", "multiplicative", "antimatterMult", "ipMult",
    // "epMult") map to the JS-side keys in GalaxyGeneratorUpgrades. The
    // capitalisation differs (IPMult/EPMult), so we map back here rather
    // than forcing the iOS layer to know about both.
    var _ggKeyMap = {
        additive: "additive",
        multiplicative: "multiplicative",
        antimatterMult: "antimatterMult",
        ipMult: "IPMult",
        epMult: "EPMult"
    };

    globalThis._nativeBuyGalaxyGenUpgrade = function (id) {
        try {
            if (typeof GalaxyGeneratorUpgrades === "undefined") return "no-gg";
            var jsKey = _ggKeyMap[String(id)] || String(id);
            var ug = GalaxyGeneratorUpgrades[jsKey];
            if (!ug || typeof ug.purchase !== "function") return "no-upgrade";
            return ug.purchase() ? "ok" : "noop";
        } catch (e) { return "error"; }
    };

    // Flip the Galaxy Generator from "panel visible" to "unlocked" — mirrors
    // web `PelleGalaxyGeneratorPanel.vue` `unlock()` (lines 68-71). Sets
    // `player.celestials.pelle.galaxyGenerator.unlocked = true` so
    // `Pelle.hasGalaxyGenerator` flips, and surfaces the unlock quote.
    globalThis._nativeUnlockGalaxyGenerator = function () {
        try {
            if (!player || !player.celestials || !player.celestials.pelle
                || !player.celestials.pelle.galaxyGenerator) return "no-state";
            if (player.celestials.pelle.galaxyGenerator.unlocked) return "already-unlocked";
            player.celestials.pelle.galaxyGenerator.unlocked = true;
            try {
                if (typeof Pelle !== "undefined" && Pelle.quotes
                    && Pelle.quotes.galaxyGeneratorUnlock
                    && typeof Pelle.quotes.galaxyGeneratorUnlock.show === "function") {
                    Pelle.quotes.galaxyGeneratorUnlock.show();
                }
            } catch (e) {}
            return "ok";
        } catch (e) { return "error"; }
    };

    // Begin draining the cap rift to advance to the next phase. Web exposes
    // `startSacrifice()` directly — the loop in galaxy-generator.js handles
    // the rest each tick.
    globalThis._nativeStartGalaxyGenSacrifice = function () {
        try {
            if (typeof GalaxyGenerator === "undefined") return "no-gg";
            if (GalaxyGenerator.sacrificeActive) return "already-active";
            GalaxyGenerator.startSacrifice();
            return "ok";
        } catch (e) { return "error"; }
    };

    // ====================================================================
    //  DMD amount self-heal.
    //
    //  Web normally seeds `DarkMatterDimension(N).amount = 1` exactly once,
    //  inside ImaginaryUpgrade(15..18).onPurchased. If a save reaches
    //  Laitela.isUnlocked via any other path — debug cheats that flip
    //  upgrade bits, save-state imports from older builds, the recover-
    //  from-corrupted-save flow — that hook is bypassed and DMD amounts
    //  stay at 0. Since DMD production is `amount × ticks × powerDM`,
    //  a 0 amount means DM never grows and the player is stuck.
    //
    //  The heal:
    //    - Runs once at helper-injection time (boot / importSave / hardReset).
    //    - Re-runs after every REALITY_UPGRADE_BOUGHT event (catches in-
    //      session imaginary-upgrade purchases via any path, since IU
    //      onPurchased dispatches REALITY_UPGRADE_BOUGHT).
    //    - Idempotent: only writes amounts that are currently `lte(0)`,
    //      so it never clobbers legitimate progress.
    // ====================================================================
    function _healDMDAmounts() {
        try {
            if (typeof Laitela === "undefined" || !Laitela || !Laitela.isUnlocked) return;
            if (typeof DarkMatterDimension === "undefined") return;
            // DMD1 is the entry point: if Laitela is unlocked it MUST have
            // amount >= 1 or production is stuck at zero. Don't gate on
            // `dim.isUnlocked` for tier 1 — some broken save states report
            // it false even though Laitela is unlocked.
            for (var t = 1; t <= 4; t++) {
                var dim = DarkMatterDimension(t);
                if (!dim) continue;
                if (t > 1 && !dim.isUnlocked) continue;
                var amt = dim.amount || (dim.data ? dim.data.amount : null);
                if (!amt || (typeof amt.lte === "function" && amt.lte(0))) {
                    if (dim.data) dim.data.amount = new Decimal(1);
                }
            }
            // Also bump base DM to at least 1 so the first upgrade purchase
            // succeeds before any production lands. Cheap idempotent check.
            if (typeof Currency !== "undefined" && Currency.darkMatter
                && Currency.darkMatter.value
                && typeof Currency.darkMatter.value.lt === "function"
                && Currency.darkMatter.value.lt(1)) {
                Currency.darkMatter.value = new Decimal(1);
            }
        } catch (e) { /* never crash startup over a heal */ }
    }
    // Expose the heal as the canonical entry point so the dev "Seed DMDs"
    // button and any future call sites all share one definition.
    globalThis._nativeHealDMDs = _healDMDAmounts;

    // ====================================================================
    //  Heal: clear celestial run flags when Pelle.isDoomed is true.
    //  Background: Pelle.doomCurrentReality is supposed to exit any active
    //  celestial reality as part of the doom transition. Saves that were
    //  doomed via cheats / older builds can land in a state where Ra /
    //  Teresa / Effarig / Enslaved / V / Lai'tela still report
    //  `isRunning === true` while Pelle.isDoomed is also true. The header
    //  banner then says "You are in Ra's Reality" which is incorrect — the
    //  user is in Pelle's Reality. Heal by clearing every celestial.run
    //  flag when doomed. Idempotent: only writes flags that are currently
    //  true.
    // ====================================================================
    function _healDoomedCelestialRuns() {
        try {
            if (typeof Pelle === "undefined" || !Pelle || !Pelle.isDoomed) return;
            if (typeof player === "undefined" || !player || !player.celestials) return;
            var c = player.celestials;
            if (c.teresa  && c.teresa.run)  c.teresa.run  = false;
            if (c.effarig && c.effarig.run) c.effarig.run = false;
            if (c.enslaved && c.enslaved.run) c.enslaved.run = false;
            if (c.v       && c.v.run)       c.v.run       = false;
            if (c.ra      && c.ra.run)      c.ra.run      = false;
            if (c.laitela && c.laitela.run) c.laitela.run = false;
        } catch (e) { /* never crash over a heal */ }
    }
    globalThis._nativeHealDoomedCelestialRuns = _healDoomedCelestialRuns;
    // Setup-time heal — covers boot of an existing save where the upgrade
    // was bought on an old build / via cheat that bypassed onPurchased.
    _healDMDAmounts();
    _healDoomedCelestialRuns();
    // Bind the in-session listeners exactly once across reinjects (boot +
    // import re-inject the helpers; we don't want N stacked listeners).
    if (typeof EventHub !== "undefined" && EventHub && EventHub.logic
        && typeof GAME_EVENT !== "undefined"
        && !globalThis._nativeDMDHealHooked) {
        try {
            if (GAME_EVENT.REALITY_UPGRADE_BOUGHT !== undefined) {
                EventHub.logic.on(GAME_EVENT.REALITY_UPGRADE_BOUGHT, _healDMDAmounts);
            }
            // Save imports / slot switches go through GAME_LOAD — covers the
            // case where the broken save lands fresh and never bought a
            // reality upgrade in this session.
            if (GAME_EVENT.GAME_LOAD !== undefined) {
                EventHub.logic.on(GAME_EVENT.GAME_LOAD, function () {
                    _healDMDAmounts();
                    _healDoomedCelestialRuns();
                });
            }
            // Post-Reality state can wipe DMD amounts to 0 before the
            // upgrade-bought event fires; covers that window.
            if (GAME_EVENT.REALITY_RESET_AFTER !== undefined) {
                EventHub.logic.on(GAME_EVENT.REALITY_RESET_AFTER, function () {
                    _healDMDAmounts();
                    _healDoomedCelestialRuns();
                });
            }
            globalThis._nativeDMDHealHooked = true;
        } catch (e) {}
    }
})();
