// multiplier-breakdown-helper.js — JS bridge for the Multiplier Breakdown
// subtab. Mirrors `MultiplierBreakdownTab.vue` and recursively walks
// `multiplierTabTree` + `multiplierTabValues` to produce a static snapshot
// that Swift can render without re-implementing any of the calculation.
//
// Exports:
//   _nativeMultiplierBreakdownResource(key, opts)
//       Returns one resource node (the top-level pick or a child via tap-to-
//       drill). `opts.depth` controls how many levels of children to inline
//       (default 0 = flat list of immediate entries, hasChildren flagged).
//   _nativeMultiplierBreakdownTopOptions()
//       Returns the 12-entry resource picker list with .isActive gating
//       (matches MULT_TAB_OPTIONS in the Vue source).
//   _nativeMultiplierBreakdownSet(field, value)
//       Persists `player.options.multiplierTab[field]` for currTab / showAltGroup
//       / replacePowers.
//
// Injected from `GameEngine.setupMultiplierBreakdownHelpers()`. Same
// lifecycle as the other helper scripts.
//
// CSS-var resolution: web uses `var(--color-X)` in icons; we resolve those
// JS-side via `CSS_COLORS` hardcoded against the Modern UI palette so iOS
// gets concrete `#rrggbb` strings.
//
// Font-Awesome to SF-Symbol mapping: every `<i class="fas fa-…">` glyph used
// in icons.js maps to an SF Symbol name via `FA_TO_SF`. Unknown classes fall
// through to empty string so the renderer omits the icon.

(function () {
    "use strict";

    // --- Resource picker table -------------------------------------------
    var MULT_TAB_OPTIONS = [
        { id: 0,  key: "AM",         label: "Antimatter Production" },
        { id: 1,  key: "tickspeed",  label: "Tickspeed" },
        { id: 2,  key: "AD",         label: "Antimatter Dimensions" },
        { id: 3,  key: "IP",         label: "Infinity Points" },
        { id: 4,  key: "ID",         label: "Infinity Dimensions" },
        { id: 5,  key: "infinities", label: "Infinities" },
        { id: 6,  key: "replicanti", label: "Replicanti Speed" },
        { id: 7,  key: "EP",         label: "Eternity Points" },
        { id: 8,  key: "TD",         label: "Time Dimensions" },
        { id: 9,  key: "eternities", label: "Eternities" },
        { id: 10, key: "DT",         label: "Dilated Time" },
        { id: 11, key: "gamespeed",  label: "Game Speed" }
    ];

    // --- CSS variable resolution ----------------------------------------
    // Modern UI (`new-ui-styles.css`) overrides several base colors. We use
    // the Modern values where they exist, falling back to the classic-UI
    // values otherwise. Pulled from public/stylesheets/*.css.
    var CSS_COLORS = {
        "color-antimatter":         "#df5050",
        "color-infinity":           "#b67f33",
        "color-eternity":           "#b341e0",
        "color-reality":            "#0ba00e",
        "color-dilation":           "#64dd17",
        "color-pelle--base":        "#9b0202",
        "color-bad":                "#b84b5f",
        "color-good":               "#1bbb36",
        "color-disabled":           "#a3a3a3",
        "color-text":               "#ffffff",
        "color-teresa--base":       "#62a7ff",
        "color-teresa--accent":     "#000000",
        "color-effarig--base":      "#ffa337",
        "color-enslaved--base":     "#cdb979",
        "color-v--base":            "#fdd835",
        "color-ra--base":           "#9575cd",
        "color-ra-pet--teresa":     "#5151ec",
        "color-ra-pet--effarig":    "#ce8462",
        "color-ra-pet--enslaved":   "#bba59b",
        "color-ra-pet--v":          "#ead584",
        "color-laitela--base":      "#000000",
        "color-laitela--accent":    "#ffffff",
        "color-accent":             "#e6e600"
    };
    function resolveCSSColor(input) {
        if (typeof input !== "string" || !input) return "#cccccc";
        var m = input.match(/var\(--([\w-]+)\)/);
        if (m) {
            var key = m[1];
            return CSS_COLORS[key] || "#cccccc";
        }
        // Glyph type colors from reality.glyphTypes[t].color are direct hex.
        if (input[0] === "#") return input;
        return "#cccccc";
    }

    // --- Font Awesome → SF Symbol mapping -------------------------------
    // Only includes classes actually used in icons.js. Unrecognized classes
    // return "" so iOS skips the SF Symbol render.
    var FA_TO_SF = {
        "fa-arrow-up-right-dots":            "chart.line.uptrend.xyaxis",
        "fa-arrows-up-to-line":              "arrow.up.to.line",
        "fa-up-right-and-down-left-from-center": "arrow.up.left.and.arrow.down.right",
        "fa-arrow-down-wide-short":          "arrow.down.right.square",
        "fa-turn-down":                      "arrow.turn.down.right",
        "fa-arrow-up":                       "arrow.up",
        "fa-arrow-down-up-across-line":      "arrow.up.arrow.down",
        "fa-arrow-right-arrow-left":         "arrow.left.arrow.right",
        "fa-atom":                           "atom",
        "fa-calculator":                     "function",
        "fa-angles-up":                      "chevron.up.2",
        "fa-clock":                          "clock",
        "fa-bahai":                          "sun.max",
        "fa-trophy":                         "trophy",
        "fa-book":                           "book",
        "fa-meteor":                         "sparkle",
        "fa-clone":                          "square.on.square",
        "fa-circle":                         "circle.fill",
        "fa-sun":                            "sun.max.fill",
        "fa-vial":                           "testtube.2",
        "fa-expand-arrows-alt":              "arrow.up.left.and.down.right.magnifyingglass",
        "fa-arrows-up-down-left-right":      "arrow.up.and.down.and.arrow.left.and.right",
        "fa-coins":                          "dollarsign.circle",
        "fa-arrows-turn-right":              "arrow.turn.up.right",
        "fa-lightbulb":                      "lightbulb"
    };

    // Strip an icon's HTML, extracting (a) any Unicode prefix wrapped in <b>
    // and (b) the first recognized FA class. Returns { iconText, iconSF }.
    function parseIconHTML(html) {
        if (typeof html !== "string" || !html) return { iconText: "", iconSF: "" };
        // Extract bold text first.
        var iconText = "";
        var boldMatch = html.match(/<b>([\s\S]*?)<\/b>/);
        if (boldMatch) {
            // Inner may itself be HTML — strip tags but keep Unicode glyphs.
            iconText = boldMatch[1].replace(/<[^>]*>/g, "").trim();
        }
        // Some icons use a raw <div>\uXXXX</div> instead of <b>…</b>.
        if (!iconText) {
            var divMatch = html.match(/<div[^>]*>([\s\S]*?)<\/div>/);
            if (divMatch) iconText = divMatch[1].replace(/<[^>]*>/g, "").trim();
        }
        var iconSF = "";
        var faMatch = html.match(/fa-[a-z0-9-]+/);
        if (faMatch) {
            // Skip the "fas"/"far"/"fab" prefix classes — they're not the icon itself.
            var cls = faMatch[0];
            if (cls !== "fa-solid" && cls !== "fa-regular" && FA_TO_SF[cls]) {
                iconSF = FA_TO_SF[cls];
            }
        }
        return { iconText: iconText, iconSF: iconSF };
    }

    // --- Entry helpers ---------------------------------------------------
    function createGetter(prop, args) {
        if (typeof prop === "function") return function () { return prop.apply(null, args); };
        return function () { return prop; };
    }

    // Inline replacement for BreakdownEntryInfo (we don't want to bring in
    // the Vue.observable runtime — pure data-only readers are enough).
    //
    // CRITICAL — mult/pow are gated on isActive. Web's BreakdownEntryInfo.update()
    // does `this.data.mult.fromDecimal(isVisible ? this.mult : DC.D1)` and
    // `this.data.pow = isVisible ? this.pow : 1`. Without that gate, entries
    // whose `isActive` is false (e.g. `nerfPelle` when not in Doomed Reality)
    // would still contribute their stale base mult/pow values (0.1 and 0.5
    // for nerfPelle), producing phantom bar segments and -50% rows.
    function entryInfoForKey(key) {
        var parts = key.split("_");
        var section = (typeof GameDatabase !== "undefined") ? GameDatabase.multiplierTabValues : null;
        if (!section || !section[parts[0]] || !section[parts[0]][parts[1]]) return null;
        var dbEntry = section[parts[0]][parts[1]];
        var rest = parts.length >= 3
            ? parts.slice(2).map(function (a) { return /^\d+$/.test(a) ? Number(a) : a; })
            : [];

        var isActiveBool = (function () {
            try { var v = createGetter(dbEntry.isActive, rest)(); return v == null ? false : !!v; }
            catch (e) { return false; }
        })();

        // Gate mult + pow on isActive (matches web's update() semantics).
        var mult, pow;
        if (isActiveBool) {
            mult = (function () {
                try { return new Decimal(createGetter(dbEntry.multValue, rest)() != null ? createGetter(dbEntry.multValue, rest)() : 1); }
                catch (e) { return new Decimal(1); }
            })();
            pow = (function () {
                try { var v = createGetter(dbEntry.powValue, rest)(); return v == null ? 1 : v; }
                catch (e) { return 1; }
            })();
        } else {
            mult = new Decimal(1);
            pow = 1;
        }

        return {
            key: key,
            name: createGetter(dbEntry.name, rest)(),
            mult: mult,
            pow: pow,
            isActive: isActiveBool,
            fakeValue: (function () {
                try { return createGetter(dbEntry.fakeValue, rest)(); }
                catch (e) { return undefined; }
            })(),
            icon: (function () {
                try { return createGetter(dbEntry.icon, rest)(); }
                catch (e) { return undefined; }
            })(),
            displayOverride: (function () {
                try { return createGetter(dbEntry.displayOverride, rest)(); }
                catch (e) { return undefined; }
            })(),
            isDilated: (function () {
                try { return !!createGetter(dbEntry.isDilated, rest)(); }
                catch (e) { return false; }
            })(),
            isBase: (function () {
                try { return !!createGetter(dbEntry.isBase, rest)(); }
                catch (e) { return false; }
            })(),
            ignoresNerfPowers: (function () {
                try { var v = createGetter(dbEntry.ignoresNerfPowers, rest)(); return v == null ? false : !!v; }
                catch (e) { return false; }
            })(),
            dilationEffect: (function () {
                try { var v = createGetter(dbEntry.dilationEffect, rest)(); return v == null ? 1 : v; }
                catch (e) { return 1; }
            })()
        };
    }

    function isVisible(entry) {
        if (!entry) return false;
        if (!entry.isActive) return false;
        if (entry.pow !== 1) return true;
        try { return entry.mult.neq(1); } catch (e) { return false; }
    }

    function getEntryGroups(key) {
        if (typeof GameDatabase === "undefined" || !GameDatabase.multiplierTabTree) return [];
        var treeGroups = GameDatabase.multiplierTabTree[key];
        if (!treeGroups) return [];
        return treeGroups.map(function (keys) {
            return keys.map(function (k) { return entryInfoForKey(k); }).filter(function (e) { return e; });
        });
    }

    function groupHasVisibleEntries(group) {
        var activeChildren = group.filter(isVisible);
        if (activeChildren.length > 1) return true;
        if (activeChildren.length === 1 && activeChildren[0].key.indexOf("general") === 0) return true;
        return false;
    }

    function selectedGroup(key, prefShowAlt) {
        var groups = getEntryGroups(key);
        if (groups.length === 0) return [];
        if (groups.length > 1 && prefShowAlt) return groups[1];
        return groups[0];
    }

    function hasAltGroup(key) {
        return getEntryGroups(key).length > 1;
    }

    // --- Percent math ----------------------------------------------------
    // Mirrors calculatePercents in MultiplierBreakdownEntry.vue.
    function calcPercents(entries, resource) {
        var powList = entries.map(function (e) { return e.pow; });
        var totalPosPow = powList.filter(function (p) { return p > 1; })
            .reduce(function (x, y) { return x * y; }, 1);
        var totalNegPow = powList.filter(function (p) { return p < 1; })
            .reduce(function (x, y) { return x * y; }, 1);
        var baseVal = (resource.fakeValue !== undefined && resource.fakeValue !== null)
            ? resource.fakeValue : resource.mult;
        var log10Mult = 0;
        try { log10Mult = baseVal.log10 ? baseVal.log10() / totalPosPow : Math.log10(Number(baseVal)) / totalPosPow; }
        catch (e) { log10Mult = 0; }

        var percentList = [];
        var nerfBlacklist = { "IP_base": true, "EP_base": true, "TP_base": true };
        for (var i = 0; i < entries.length; ++i) {
            var entry = entries[i];
            var multFrac = 0;
            if (log10Mult !== 0) {
                try { multFrac = (entry.mult.log10 ? entry.mult.log10() : Math.log10(Number(entry.mult))) / log10Mult; }
                catch (e) {}
            }
            var powFrac = totalPosPow === 1 ? 0 : Math.log(entry.pow) / Math.log(totalPosPow);
            var perc;
            if (entry.pow >= 1) {
                perc = multFrac / totalPosPow + powFrac * (1 - 1 / totalPosPow);
            } else {
                perc = Math.log(entry.pow) / Math.log(totalNegPow) * (totalNegPow - 1);
            }
            if (nerfBlacklist[entry.key]) perc = Math.max(perc, 0.0001);
            percentList.push([entry.ignoresNerfPowers, perc]);
        }

        var totalPerc = percentList.filter(function (p) { return p[1] > 0; })
            .map(function (p) { return p[1]; })
            .reduce(function (x, y) { return x + y; }, 0);
        var nerfedPerc = percentList.filter(function (p) { return p[1] > 0; })
            .reduce(function (x, y) { return x + (y[0] ? y[1] : y[1] * totalNegPow); }, 0);
        var final = percentList.map(function (p) {
            if (p[1] > 0) return (p[0] ? p[1] : p[1] * totalNegPow) / (nerfedPerc || 1);
            return Math.max(p[1] * (totalPerc - nerfedPerc) / (totalPerc || 1) / (totalNegPow || 1), -1);
        });
        return {
            percents: final,
            log10Mult: log10Mult,
            totalPositivePower: totalPosPow,
            totalMultiplier: (function () {
                try { return Decimal.pow10(log10Mult); } catch (e) { return new Decimal(1); }
            })(),
            isEmpty: log10Mult === 0
        };
    }

    // --- Display strings -------------------------------------------------
    function padPercents(s) {
        while (s.length < 7) s = " " + s;
        return s;
    }
    function formatPercString(perc) {
        try {
            if (perc === 0) return formatPercents(0);
            if (perc === 1) return formatPercents(1);
            if (perc < 0.001 && perc > 0) return "<" + formatPercents(0.001, 1);
            if (perc > 0.9995) return "~" + formatPercents(1);
            return formatPercents(perc, 1);
        } catch (e) { return "0%"; }
    }
    function formatFnFor(entry, dilationExponent, replacePowers, totalMultiplier, totalPositivePower) {
        return function (x) {
            try {
                if (entry.isDilated && dilationExponent !== 1) {
                    var undil = Decimal.pow10(Math.pow(x.log10(), 1 / dilationExponent));
                    return formatX(undil, 2, 2) + " ➜ " + formatX(x, 2, 2);
                }
                return entry.isBase ? format(x, 2, 2) : formatX(x, 2, 2);
            } catch (e) { return "0"; }
        };
    }

    function buildEntryDisplay(entry, perc, dilationExponent, replacePowers, totalMultiplier, totalPositivePower) {
        var percString = padPercents(formatPercString(perc));
        if (!isVisible(entry)) return percString + ": " + entry.name;

        var override = entry.displayOverride;
        if (override) return percString + ": " + entry.name + " (" + override + ")";

        var values = [];
        var fmtFn = formatFnFor(entry, dilationExponent, replacePowers, totalMultiplier, totalPositivePower);
        var nerfBlacklist = { "IP_base": true, "EP_base": true, "TP_base": true };
        var isNerfEntry = perc < 0 && !nerfBlacklist[entry.key];
        if (isNerfEntry) {
            // Nerf format from nerfString in Vue.
            var nerfFmt = entry.isBase ? function (x) { return format(x, 2, 2); }
                : function (x) {
                    try { return "/" + format(x.reciprocal(), 2, 2); }
                    catch (e) { return "/0"; }
                };
            try {
                if (replacePowers && entry.pow !== 1) {
                    // Simplified — base resource not passed in nerf path here.
                    values.push(nerfFmt(entry.mult));
                } else {
                    if (entry.mult.neq(1)) values.push(nerfFmt(entry.mult));
                    if (entry.pow !== 1) values.push(formatPow(entry.pow, 2, 3));
                }
            } catch (e) {}
            var nv = values.length === 0 ? "" : "(" + values.join(", ") + ")";
            return percString + ": " + entry.name + " " + nv;
        }

        try {
            if (replacePowers && entry.pow !== 1) {
                var powFrac = Math.log(entry.pow) / Math.log(totalPositivePower || 2);
                var equiv = totalMultiplier.pow((totalPositivePower - 1) * powFrac);
                values.push(fmtFn(entry.mult.times(equiv)));
            } else {
                if (entry.mult.neq(1)) values.push(fmtFn(entry.mult));
                if (entry.pow !== 1) values.push(formatPow(entry.pow, 2, 3));
            }
        } catch (e) {}
        var valueStr = values.length === 0 ? "" : "(" + values.join(", ") + ")";
        return percString + ": " + entry.name + " " + valueStr;
    }

    function buildTotalString(resource) {
        var override = resource.displayOverride;
        if (override) return resource.name + ": " + override;
        try {
            var v = resource.mult;
            return resource.isBase
                ? resource.name + ": " + format(v, 2, 2)
                : resource.name + ": " + formatX(v, 2, 2);
        } catch (e) { return resource.name + ": 0"; }
    }

    function buildDilationString(resource, dilationExponent, entries) {
        try {
            var baseMult = resource.mult;
            var beforeMult, afterMult;
            if (resource.isDilated) {
                var dilProd = entries
                    .filter(function (e) { return isVisible(e) && e.isDilated; })
                    .map(function (e) { return e.mult; })
                    .map(function (v) { return Decimal.pow10(Math.pow(v.log10(), 1 / dilationExponent)); })
                    .reduce(function (x, y) { return x.times(y); }, new Decimal(1));
                beforeMult = dilProd.neq(1)
                    ? dilProd
                    : Decimal.pow10(Math.pow(baseMult.log10(), 1 / dilationExponent));
                afterMult = baseMult;
            } else {
                beforeMult = baseMult;
                afterMult = Decimal.pow10(Math.pow(baseMult.log10(), dilationExponent));
            }
            var fmt = resource.isBase
                ? function (x) { return format(x, 2, 2); }
                : function (x) { return formatX(x, 2, 2); };
            return "Dilation Effect: Exponent" + formatPow(dilationExponent, 2, 3)
                + " (" + fmt(beforeMult) + " ➜ " + fmt(afterMult) + ")";
        } catch (e) { return null; }
    }

    function nodeForEntry(entry, perc, isNerf, dilationExponent, replacePowers, totalMultiplier, totalPositivePower) {
        var iconObj = entry.icon || {};
        var parsed = parseIconHTML(iconObj.symbol);
        return {
            key: entry.key,
            name: entry.name,
            displayString: buildEntryDisplay(entry, perc, dilationExponent, replacePowers, totalMultiplier, totalPositivePower),
            percent: perc,
            isNerf: isNerf,
            isVisible: isVisible(entry),
            hasChildren: (function () {
                var groups = getEntryGroups(entry.key);
                return groups.some(groupHasVisibleEntries);
            })(),
            iconText: parsed.iconText,
            iconSFSymbol: parsed.iconSF,
            iconColor: resolveCSSColor(iconObj.color),
            iconTextColor: (iconObj.textColor === "black" || iconObj.textColor === "var(--color-text-inverted)")
                ? "black"
                : (iconObj.textColor && iconObj.textColor[0] === "#" ? iconObj.textColor : "white")
        };
    }

    function resolveResource(key, prefShowAlt, prefReplacePowers) {
        var resource = entryInfoForKey(key);
        if (!resource) return null;
        var entries = selectedGroup(key, prefShowAlt);
        var percInfo = calcPercents(entries, resource);
        var nerfBlacklist = { "IP_base": true, "EP_base": true, "TP_base": true };

        var nodes = [];
        for (var i = 0; i < entries.length; ++i) {
            // Match web `v-if="shouldShowEntry"` — skip entries that aren't
            // currently active/visible. With the isActive gate on entryInfoForKey
            // above, inactive entries have mult=1 + pow=1 and would be filtered
            // here as "not visible". Without this skip, every JSON payload
            // includes every non-active entry as a 0% row.
            if (!isVisible(entries[i])) continue;
            var perc = percInfo.percents[i];
            var isNerf = perc < 0 && !nerfBlacklist[entries[i].key];
            nodes.push(nodeForEntry(entries[i], perc, isNerf,
                resource.dilationEffect, prefReplacePowers,
                percInfo.totalMultiplier, percInfo.totalPositivePower));
        }

        // Disabled-text mirrors the Vue computed property.
        var disabledText;
        if (!resource.isBase) {
            disabledText = "Total effect inactive, disabled, or reduced to " + (function () {
                try { return formatX(1); } catch (e) { return "×1"; }
            })();
        } else {
            try {
                if (Decimal.eq(resource.mult, 0)) disabledText = "You cannot gain this resource (prestige requirement not reached)";
                else disabledText = "You have no multipliers for this resource (will gain " + format(1) + " on prestige)";
            } catch (e) { disabledText = ""; }
        }

        var hasSeenPowers = false;
        try {
            hasSeenPowers = !!(InfinityChallenge(4).isCompleted || PlayerProgress.eternityUnlocked());
        } catch (e) {}
        var forbidden = ["AD_infinityPower", "galaxies", "tickspeed"];
        var allowPowerToggle = !forbidden.some(function (f) { return resource.key.indexOf(f) === 0; });

        var inNC12 = false;
        try { inNC12 = !!NormalChallenge(12).isRunning; } catch (e) {}

        return {
            key: resource.key,
            name: resource.name,
            totalString: buildTotalString(resource),
            isEmpty: percInfo.isEmpty,
            disabledText: disabledText,
            isDilated: resource.dilationEffect !== 1,
            dilationString: resource.dilationEffect !== 1
                ? buildDilationString(resource, resource.dilationEffect, entries) : null,
            inNC12Notice: inNC12 && resource.key === "AD_total",
            isADTotal: resource.key === "AD_total",
            hasAltGroup: hasAltGroup(resource.key),
            allowPowerToggle: allowPowerToggle,
            hasSeenPowers: hasSeenPowers,
            entries: nodes
        };
    }

    // --- Exported API ----------------------------------------------------
    globalThis._nativeMultiplierBreakdownTopOptions = function () {
        try {
            var out = MULT_TAB_OPTIONS.map(function (opt) {
                var isActive = false;
                try {
                    var db = GameDatabase.multiplierTabValues[opt.key];
                    if (db && db.total) {
                        isActive = (typeof db.total.isActive === "function")
                            ? !!db.total.isActive()
                            : !!db.total.isActive;
                    }
                } catch (e) {}
                return { id: opt.id, key: opt.key, label: opt.label, isActive: isActive };
            });
            // Current id from options
            var currTab = 0;
            try { currTab = player.options.multiplierTab.currTab; }
            catch (e) {}
            var showAlt = false, replacePow = false;
            try { showAlt = !!player.options.multiplierTab.showAltGroup; } catch (e) {}
            try { replacePow = !!player.options.multiplierTab.replacePowers; } catch (e) {}
            return JSON.stringify({
                resources: out,
                currentResourceId: currTab,
                showAltGroup: showAlt,
                replacePowers: replacePow
            });
        } catch (e) {
            return JSON.stringify({ resources: [], currentResourceId: 0, showAltGroup: false, replacePowers: false });
        }
    };

    globalThis._nativeMultiplierBreakdownResource = function (key) {
        try {
            var showAlt = false, replacePow = false;
            try { showAlt = !!player.options.multiplierTab.showAltGroup; } catch (e) {}
            try { replacePow = !!player.options.multiplierTab.replacePowers; } catch (e) {}
            var k = (typeof key === "string" && key) ? key : "AM_total";
            // Top-level pick uses `{key}_total`.
            if (k.indexOf("_") === -1) k = k + "_total";
            var res = resolveResource(k, showAlt, replacePow);
            return JSON.stringify(res || { entries: [], isEmpty: true });
        } catch (e) {
            try { _nativeLog && _nativeLog("[mult] resource failed: " + e); } catch (_e) {}
            return JSON.stringify({ entries: [], isEmpty: true });
        }
    };

    globalThis._nativeMultiplierBreakdownSet = function (field, value) {
        try {
            if (!player.options || !player.options.multiplierTab) return false;
            if (field === "currTab") player.options.multiplierTab.currTab = Number(value) || 0;
            else if (field === "showAltGroup") player.options.multiplierTab.showAltGroup = !!value;
            else if (field === "replacePowers") player.options.multiplierTab.replacePowers = !!value;
            else return false;
            return true;
        } catch (e) { return false; }
    };
})();
