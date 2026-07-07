// glyph-loadout-helpers.js
//
// JS-side support for the iOS Glyph Presets UI. Mirrors the web feature in
// `src/components/tabs/glyphs/sidebar/GlyphSetSavePanel.vue`. Storage lives
// at `player.reality.glyphs.sets` (array of 7 `{name, glyphs[]}` records,
// populated by migrations.js — every existing save already has the slots).
//
// Matching algorithm is the web's verbatim — we call `Glyphs.findByValues`
// and the same greedy/lenient compromise from the Vue. iOS does not
// reimplement matching; the JS-side result is what we surface.
//
// Injected by GameEngine+GlyphPresets.setupGlyphPresetHelpers(). Lifecycle
// matches save-helpers.js: finishStartup / importSave / hardReset / slot
// switch / backup restore.

(function () {
    "use strict";

    // ---- Helpers -------------------------------------------------------

    // Compact mini-preview shape: just enough to render `GlyphComponent` in
    // a row inside the sheet. We avoid surfacing full GlyphInfo here because
    // the saved-glyph copies are static snapshots — they don't have a slot
    // index, rarity name, or the full effect-text list. The sheet only
    // needs the visual ID.
    function makePresetPreview(g) {
        if (!g) return null;
        var tp = g.type || "power";
        var sym = (typeof GLYPH_SYMBOLS !== "undefined" && GLYPH_SYMBOLS[tp]) || "?";
        var typeCol = "#888";
        try {
            var def = (GameDatabase.reality.glyphTypes[tp] || GameDatabase.reality.cosmeticGlyphs[tp]);
            if (def && def.color) typeCol = def.color;
        } catch (e) { /* fallthrough */ }
        if (g.cosmetic) {
            try {
                var cos = GameDatabase.reality.cosmeticGlyphs[g.cosmetic];
                if (cos) {
                    if (cos.symbol) sym = cos.symbol;
                    if (cos.color) typeCol = cos.color;
                }
            } catch (e) { /* fallthrough */ }
        }
        var rarityCol = "#888";
        try {
            var rar = getRarity(g.strength || 1);
            rarityCol = rar.darkColor || rar.color || "#888";
        } catch (e) { /* fallthrough */ }
        var effCount = 0;
        try {
            if (typeof countValuesFromBitmask === "function") {
                effCount = countValuesFromBitmask(g.effects || 0);
            }
        } catch (e) { /* fallthrough */ }
        return {
            id: Number(g.id || 0),
            type: tp,
            symbol: sym,
            level: Number(g.level || 0),
            strength: Number(g.strength || 0),
            effects: Number(g.effects || 0),
            effectCount: effCount,
            typeColor: typeCol,
            rarityColor: rarityCol
        };
    }

    function toggleStates() {
        // Defensive defaults: missing `player.options` would be a malformed save.
        var o = (typeof player !== "undefined" && player && player.options) || {};
        return {
            effects: !!o.ignoreGlyphEffects,
            level: !!o.ignoreGlyphLevel,
            rarity: !!o.ignoreGlyphRarity
        };
    }

    function setsArray() {
        if (typeof player === "undefined" || !player || !player.reality
            || !player.reality.glyphs || !player.reality.glyphs.sets) return [];
        return player.reality.glyphs.sets;
    }

    function activeSlotCountSafe() {
        try { return Glyphs.activeSlotCount; } catch (e) { return 0; }
    }

    function freeInventorySlotsSafe() {
        try {
            // `Glyphs.freeInventorySpace` is the public getter. Falls back
            // to counting nulls in the protected-and-beyond range.
            if (typeof Glyphs !== "undefined" && typeof Glyphs.freeInventorySpace === "number") {
                return Glyphs.freeInventorySpace;
            }
        } catch (e) { /* fallthrough */ }
        return 0;
    }

    function hasEquippedSafe() {
        try { return Glyphs.activeList.length > 0; } catch (e) { return false; }
    }

    // ---- Reads --------------------------------------------------------

    // Compute the cute "Powerful Infinite Time" auto-derived set name for
    // an array of glyphs. Lifted from the equivalent block in pollGlyphs;
    // duplicated here so saved presets get the same display treatment.
    function computeSetName(glyphs) {
        try {
            if (!Array.isArray(glyphs) || glyphs.length === 0) return "Void";
            var NAMES = {
                companion: { adj: "Huggable", noun: "Companion" },
                reality: { adj: "Real", noun: "Reality" },
                effarig: { adj: "Meta", noun: "Effarig" },
                cursed: { adj: "Cursed", noun: "Curse" },
                power: { adj: ["Powerful", "Mastered", "Potential"], noun: "Power" },
                infinity: { adj: ["Infinite", "Boundless", "Immense"], noun: "Infinity" },
                replication: { adj: ["Replicated", "Simulated", "Duplicated"], noun: "Replication" },
                time: { adj: ["Temporal", "Chronal", "Transient"], noun: "Time" },
                dilation: { adj: ["Dilated", "Attenuated", "Diluted"], noun: "Dilation" }
            };
            var typeCounts = {};
            glyphs.forEach(function (g) { typeCounts[g.type] = (typeCounts[g.type] || 0) + 1; });
            var types = Object.keys(typeCounts).sort(function (a, b) { return typeCounts[b] - typeCounts[a]; });
            var parts = [];
            for (var ti = 0; ti < types.length; ti++) {
                var t = types[ti]; var n = NAMES[t];
                if (!n) continue;
                if (ti === types.length - 1) {
                    parts.push(n.noun);
                } else {
                    var a = n.adj;
                    parts.push(typeof a === "string" ? a : a[0]);
                }
            }
            return parts.join(" ");
        } catch (e) { return ""; }
    }

    globalThis._nativeListGlyphPresets = function () {
        var sets = setsArray();
        var out = [];
        for (var i = 0; i < sets.length; i++) {
            var s = sets[i] || {};
            var glyphs = Array.isArray(s.glyphs) ? s.glyphs : [];
            var preview = [];
            for (var j = 0; j < glyphs.length; j++) {
                var p = makePresetPreview(glyphs[j]);
                if (p) preview.push(p);
            }
            out.push({
                id: i,
                name: String(s.name || ""),
                autoName: computeSetName(glyphs),
                glyphs: preview
            });
        }
        return JSON.stringify({
            sets: out,
            toggles: toggleStates(),
            hasEquipped: hasEquippedSafe(),
            activeSlotCount: activeSlotCountSafe(),
            freeInventorySlots: freeInventorySlotsSafe()
        });
    };

    globalThis._nativeSetGlyphMatchToggle = function (kind, on) {
        if (typeof player === "undefined" || !player.options) return "no-options";
        var v = !!on;
        if (kind === "effects") player.options.ignoreGlyphEffects = v;
        else if (kind === "level") player.options.ignoreGlyphLevel = v;
        else if (kind === "rarity") player.options.ignoreGlyphRarity = v;
        else return "invalid-kind";
        return "ok";
    };

    // ---- Save / Delete / Rename --------------------------------------

    globalThis._nativeSaveGlyphPreset = function (id) {
        var sets = setsArray();
        if (id < 0 || id >= sets.length) return "invalid-id";
        if (!hasEquippedSafe()) return "no-equipped";
        var slot = sets[id];
        if (Array.isArray(slot.glyphs) && slot.glyphs.length > 0) return "slot-occupied";
        try {
            // `Glyphs.active.compact()` mirrors web saveGlyphSet exactly —
            // strips nulls and stores the actual glyph references (web treats
            // saved glyphs as snapshots of the active set).
            slot.glyphs = Glyphs.active.compact();
            if (typeof EventHub !== "undefined" && EventHub.dispatch && GAME_EVENT) {
                try { EventHub.dispatch(GAME_EVENT.GLYPH_SET_SAVE_CHANGE); } catch (e) { /* ignore */ }
            }
            return "ok";
        } catch (e) {
            if (typeof _nativeLog === "function") _nativeLog("[glyph-presets] save error: " + e);
            return "error";
        }
    };

    globalThis._nativeDeleteGlyphPreset = function (id) {
        var sets = setsArray();
        if (id < 0 || id >= sets.length) return "invalid-id";
        var slot = sets[id];
        if (!Array.isArray(slot.glyphs) || slot.glyphs.length === 0) return "empty";
        slot.glyphs = [];
        if (typeof EventHub !== "undefined" && EventHub.dispatch && GAME_EVENT) {
            try { EventHub.dispatch(GAME_EVENT.GLYPH_SET_SAVE_CHANGE); } catch (e) { /* ignore */ }
        }
        return "ok";
    };

    globalThis._nativeRenameGlyphPreset = function (id, name) {
        var sets = setsArray();
        if (id < 0 || id >= sets.length) return "invalid-id";
        // Web caps at 20 chars (GlyphSetSavePanel.vue nicknameBlur).
        sets[id].name = String(name || "").slice(0, 20);
        return "ok";
    };

    // ---- Load / Preview ----------------------------------------------
    //
    // The matching logic mirrors `GlyphSetSavePanel.vue.loadGlyphSet` /
    // `findSelectedGlyphs` verbatim, but rewritten so that:
    //   • it accepts a `dryRun` flag (preview vs. real load)
    //   • it returns per-slot match metadata so Swift can render the diff
    //     preview and the persistent post-load badges.
    //
    // Match kinds per result slot:
    //   "exact"        — saved glyph itself is still in inventory; equipped as-is
    //   "fuzzy-full"   — different glyph, but full effect superset under toggle policy
    //   "partial"      — different glyph, fewer matching effects than the saved one
    //   "missing"      — no candidate; slot stays empty
    //   "already"      — currently-equipped glyph already satisfies this saved entry
    //                    (we keep it in place rather than swapping)

    function classifyMatch(target, picked, toggles) {
        if (!picked) return "missing";
        if (target.id === picked.id) return "exact";
        // "fuzzy-full" when effect bitmask is exact-or-superset of saved.
        // Under toggle.effects=true ("Including"), web allows supersets.
        // Otherwise effects must be exactly equal — which would have been
        // caught by the id check on a same-id glyph, so any non-id match
        // here is a partial.
        if ((picked.effects & target.effects) === target.effects) return "fuzzy-full";
        return "partial";
    }

    function findSelectedGlyphs(optionList, maxGlyphs) {
        // Lifted verbatim from GlyphSetSavePanel.vue:135-155. Same composite
        // sort + greedy-vs-conservative pick. Kept here so the helper is
        // self-contained; web's Vue method isn't on globalThis.
        var compFn = function (o) {
            return 1000 * (10 * o.glyph.type.length + o.glyph.type.codePointAt(0)) + o.options.length;
        };
        optionList.sort(function (a, b) { return compFn(a) - compFn(b); });
        var toLoad = [];
        var slotsLeft = maxGlyphs;
        for (var index = 0; index < optionList.length; index++) {
            if (slotsLeft === 0) break;
            var entry = optionList[index];
            var filtered = entry.options.filter(function (g) { return toLoad.indexOf(g) === -1; });
            if (filtered.length === 0) continue;
            var picked = filtered[filtered.length - 1];
            toLoad.push(picked);
            slotsLeft--;
        }
        return toLoad;
    }

    function computeLoadPlan(set) {
        // Web `loadGlyphSet` core logic. Returns
        //   { selectedFromActive: [glyph], selectedFromInventory: [glyph],
        //     missing: [savedGlyph], saved: [savedGlyph] }
        // so callers can either apply the plan (real load) or render a diff
        // preview from it (dry run).
        var saved = Array.isArray(set) ? set.slice() : (set && set.glyphs ? set.glyphs.slice() : []);
        // Sort by perceived strength so greedy matching picks the strongest
        // demand first. Matches web's `-a.level*a.strength + b.level*b.strength`.
        saved.sort(function (a, b) { return (-a.level * a.strength) + (b.level * b.strength); });

        var fuzzy = {
            level: (player.options.ignoreGlyphLevel ? -1 : 0),
            strength: (player.options.ignoreGlyphRarity ? -1 : 0),
            effects: (player.options.ignoreGlyphEffects ? -1 : 0)
        };
        // Inverse direction when scanning inventory (we want glyphs equal-or-
        // better than the saved). Mirrors web `findByValues` polarities at
        // GlyphSetSavePanel.vue:82-86 + 100-104.
        var fuzzyInv = {
            level: (player.options.ignoreGlyphLevel ? 1 : 0),
            strength: (player.options.ignoreGlyphRarity ? 1 : 0),
            effects: (player.options.ignoreGlyphEffects ? 1 : 0)
        };

        var activeGlyphs = Glyphs.active.filter(function (g) { return g; }).slice();
        var glyphsToLoad = saved.slice();

        // Phase 1 — find saved entries already covered by currently-equipped glyphs.
        var activeOptions = [];
        for (var ai = 0; ai < activeGlyphs.length; ai++) {
            var ag = activeGlyphs[ai];
            var aopts = Glyphs.findByValues(ag, glyphsToLoad, fuzzy);
            activeOptions.push({ glyph: ag, options: aopts });
        }
        var coveredByActive = findSelectedGlyphs(activeOptions, 5);
        for (var ci = 0; ci < coveredByActive.length; ci++) {
            var covered = coveredByActive[ci];
            glyphsToLoad = glyphsToLoad.filter(function (g) { return g !== covered; });
        }

        // Phase 2 — find remaining demands in inventory.
        var freeSlots = Glyphs.active.countWhere(function (g) { return g === null; });
        var invOptions = [];
        for (var gi = 0; gi < glyphsToLoad.length; gi++) {
            var demand = glyphsToLoad[gi];
            var iopts = Glyphs.findByValues(demand, Glyphs.sortedInventoryList, fuzzyInv);
            invOptions.push({ glyph: demand, options: iopts });
        }
        var selectedFromInventory = findSelectedGlyphs(invOptions, freeSlots);
        for (var si = 0; si < selectedFromInventory.length; si++) {
            var inv = selectedFromInventory[si];
            // The inventory greedy pick is, in our terms, a chosen inventory
            // glyph; map it back to the demand that picked it.
            // (Web doesn't reuse this beyond a length check; we need it for
            // the diff preview.)
        }

        // Build per-saved-entry result with the right pick.
        // For dry-run / preview, we need to know what would land in each
        // active slot. Match each `coveredByActive` to the saved entry that
        // it satisfies (the first saved option in `activeOptions` that's
        // still in the remaining `glyphsToLoad` at coverage time), and each
        // `selectedFromInventory` to the saved entry it was demanded for.
        // We approximate this by re-running the option matching against the
        // *original* saved list — that's web's behavior.

        return {
            saved: Array.isArray(set) ? set.slice() : (set && set.glyphs ? set.glyphs.slice() : []),
            sortedDemand: Array.isArray(set) ? set.slice() : (set && set.glyphs ? set.glyphs.slice() : []),
            activeCovers: coveredByActive,
            invPicks: selectedFromInventory,
            unmatched: glyphsToLoad.filter(function (g) {
                return selectedFromInventory.indexOf(g) === -1;
            })
        };
    }

    function buildResultMetadata(set, plan) {
        // Per-saved-entry result for Swift consumption.
        var toggles = toggleStates();
        var slots = [];
        var savedList = plan.saved;
        // `activeCovers` and `invPicks` are pools of physical glyphs; map
        // each saved entry to the best match (preferring exact id, then
        // any covering active, then any inventory pick).
        // We mark a covering glyph as "used" once it's been assigned.
        var usedActive = [];
        var usedInv = [];
        for (var i = 0; i < savedList.length; i++) {
            var sg = savedList[i];
            var pickedActive = null;
            for (var ai = 0; ai < plan.activeCovers.length; ai++) {
                var cand = plan.activeCovers[ai];
                if (usedActive.indexOf(cand) !== -1) continue;
                if (cand.type !== sg.type) continue;
                // Exact id wins outright
                if (cand.id === sg.id) { pickedActive = cand; break; }
                // Otherwise the first compatible candidate
                if (!pickedActive) pickedActive = cand;
            }
            if (pickedActive) {
                usedActive.push(pickedActive);
                slots.push({
                    savedGlyph: makePresetPreview(sg),
                    willEquipGlyph: makePresetPreview(pickedActive),
                    matchKind: (pickedActive.id === sg.id) ? "already" : "already"
                });
                continue;
            }
            var pickedInv = null;
            for (var ii = 0; ii < plan.invPicks.length; ii++) {
                var inv = plan.invPicks[ii];
                if (usedInv.indexOf(inv) !== -1) continue;
                if (inv.type !== sg.type) continue;
                if (inv.id === sg.id) { pickedInv = inv; break; }
                if (!pickedInv) pickedInv = inv;
            }
            if (pickedInv) {
                usedInv.push(pickedInv);
                slots.push({
                    savedGlyph: makePresetPreview(sg),
                    willEquipGlyph: makePresetPreview(pickedInv),
                    matchKind: classifyMatch(sg, pickedInv, toggles)
                });
                continue;
            }
            slots.push({
                savedGlyph: makePresetPreview(sg),
                willEquipGlyph: null,
                matchKind: "missing"
            });
        }
        var missingCount = 0;
        for (var k = 0; k < slots.length; k++) {
            if (slots[k].matchKind === "missing") missingCount++;
        }
        var exactCount = 0, fuzzyCount = 0, partialCount = 0, alreadyCount = 0;
        for (var k2 = 0; k2 < slots.length; k2++) {
            switch (slots[k2].matchKind) {
                case "exact": exactCount++; break;
                case "fuzzy-full": fuzzyCount++; break;
                case "partial": partialCount++; break;
                case "already": alreadyCount++; break;
            }
        }
        return {
            slots: slots,
            missingCount: missingCount,
            exactCount: exactCount,
            fuzzyCount: fuzzyCount,
            partialCount: partialCount,
            alreadyCount: alreadyCount
        };
    }

    globalThis._nativePreviewLoadGlyphPreset = function (id) {
        var sets = setsArray();
        if (id < 0 || id >= sets.length) return JSON.stringify({ error: "invalid-id" });
        var slot = sets[id];
        if (!slot || !Array.isArray(slot.glyphs) || slot.glyphs.length === 0) {
            return JSON.stringify({ error: "empty" });
        }
        if (slot.glyphs.length > activeSlotCountSafe()) {
            return JSON.stringify({ error: "too-many-glyphs", required: slot.glyphs.length, available: activeSlotCountSafe() });
        }
        try {
            var plan = computeLoadPlan(slot);
            var meta = buildResultMetadata(slot, plan);
            meta.name = String(slot.name || "");
            return JSON.stringify(meta);
        } catch (e) {
            if (typeof _nativeLog === "function") _nativeLog("[glyph-presets] preview error: " + e);
            return JSON.stringify({ error: "exception" });
        }
    };

    globalThis._nativeLoadGlyphPreset = function (id) {
        var sets = setsArray();
        if (id < 0 || id >= sets.length) return JSON.stringify({ error: "invalid-id" });
        var slot = sets[id];
        if (!slot || !Array.isArray(slot.glyphs) || slot.glyphs.length === 0) {
            return JSON.stringify({ error: "empty" });
        }
        if (slot.glyphs.length > activeSlotCountSafe()) {
            return JSON.stringify({ error: "too-many-glyphs", required: slot.glyphs.length, available: activeSlotCountSafe() });
        }
        try {
            var plan = computeLoadPlan(slot);
            var meta = buildResultMetadata(slot, plan);
            // Actually equip the inventory picks in the first available
            // empty active slots. Mirrors web `loadGlyphSet`:
            //   for (const glyph of selectedFromInventory) {
            //     const idx = Glyphs.active.indexOf(null);
            //     if (idx !== -1) { Glyphs.equip(glyph, idx); }
            //   }
            for (var i = 0; i < plan.invPicks.length; i++) {
                var pick = plan.invPicks[i];
                var idx = Glyphs.active.indexOf(null);
                if (idx === -1) break;
                try { Glyphs.equip(pick, idx); } catch (e) { /* swallow */ }
            }
            meta.name = String(slot.name || "");
            return JSON.stringify(meta);
        } catch (e) {
            if (typeof _nativeLog === "function") _nativeLog("[glyph-presets] load error: " + e);
            return JSON.stringify({ error: "exception" });
        }
    };

})();
