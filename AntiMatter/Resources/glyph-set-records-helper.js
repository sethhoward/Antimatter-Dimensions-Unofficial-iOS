// glyph-set-records-helper.js — JS bridge for Statistics > Glyph Set Records
// subtab. Mirrors `GlyphSetRecordsTab.vue`.
//
// Returns 8 record rows (some gated on celestial unlocks), each carrying:
//   label  — "Best Reality Machines gained" / …
//   value  — pre-formatted value string ("12.34 RM" / "Level 100" / …)
//   glyphs — array of GlyphPresetGlyph-shape mini snapshots (id, type,
//            symbol, level, strength, effects bitmask + count, typeColor,
//            rarityColor). Renderer reuses `MiniPresetGlyph` from the
//            Glyph Presets sheet.
//
// On-demand only — NOT per-tick polled. Refreshed when the subtab opens or
// after Reality / celestial events that change records.

(function () {
    "use strict";

    // Same mini-preview builder used by glyph-loadout-helpers — duplicated
    // here so the two helpers stay self-contained. Defensive against missing
    // GLYPH_SYMBOLS / GameDatabase fields.
    function makePresetPreview(g) {
        if (!g) return null;
        var tp = g.type || "power";
        var sym = (typeof GLYPH_SYMBOLS !== "undefined" && GLYPH_SYMBOLS[tp]) || "?";
        var typeCol = "#888";
        try {
            var def = (GameDatabase.reality.glyphTypes[tp] || GameDatabase.reality.cosmeticGlyphs[tp]);
            if (def && def.color) typeCol = def.color;
        } catch (e) {}
        if (g.cosmetic) {
            try {
                var cos = GameDatabase.reality.cosmeticGlyphs[g.cosmetic];
                if (cos) {
                    if (cos.symbol) sym = cos.symbol;
                    if (cos.color) typeCol = cos.color;
                }
            } catch (e) {}
        }
        var rarityCol = "#888";
        try {
            var rar = getRarity(g.strength || 1);
            rarityCol = rar.darkColor || rar.color || "#888";
        } catch (e) {}
        var effCount = 0;
        try {
            if (typeof countValuesFromBitmask === "function") {
                effCount = countValuesFromBitmask(g.effects || 0);
            }
        } catch (e) {}
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

    function copySet(arr) {
        try {
            if (typeof Glyphs !== "undefined" && Glyphs.copyForRecords && arr) {
                return Glyphs.copyForRecords(arr) || [];
            }
        } catch (e) {}
        return (arr || []).filter(function (g) { return !!g; });
    }

    // Glyphs.copyForRecords strips the `id` field (returns only {type, level,
    // strength, effects, color, symbol}). Without an id, every snapshot has
    // id=0, SwiftUI's `ForEach(Identifiable)` collapses them to a single row,
    // and the Glyph Set Records subtab visually repeats the first glyph for
    // all positions. Inject a synthetic monotonically-increasing id per call
    // so each preview row is identity-stable across the set.
    var _previewIdCounter = 1;
    function previewSet(arr) {
        return copySet(arr).map(function (g) {
            var preview = makePresetPreview(g);
            if (preview) {
                preview.id = _previewIdCounter++;
            }
            return preview;
        }).filter(function (p) { return !!p; });
    }

    globalThis._nativeGlyphSetRecords = function () {
        try {
            var best = (player && player.records && player.records.bestReality) || {};
            var teresaBest = (player && player.celestials && player.celestials.teresa) || {};
            var laitelaState = (player && player.celestials && player.celestials.laitela) || {};
            var laitelaDim = 0;
            try { laitelaDim = 8 - Laitela.difficultyTier; } catch (e) {}

            var rows = [];

            // Always visible
            rows.push({
                visible: true,
                label: "Best Reality Machines gained",
                value: (function () {
                    try { return format(best.RM, 2, 2) + " RM"; } catch (e) { return "0 RM"; }
                })(),
                glyphs: previewSet(best.RMSet)
            });
            rows.push({
                visible: true,
                label: "Best Reality Machines per minute",
                value: (function () {
                    try { return format(best.RMmin, 2, 2) + " RM/min"; } catch (e) { return "0 RM/min"; }
                })(),
                glyphs: previewSet(best.RMminSet)
            });
            rows.push({
                visible: true,
                label: "Best Glyph Level",
                value: (function () {
                    try { return "Level " + formatInt(best.glyphLevel || 0); } catch (e) { return "Level 0"; }
                })(),
                glyphs: previewSet(best.glyphLevelSet)
            });
            rows.push({
                visible: true,
                label: "Highest Eternity Points",
                value: (function () {
                    try { return format(best.bestEP, 2, 2) + " EP"; } catch (e) { return "0 EP"; }
                })(),
                glyphs: previewSet(best.bestEPSet)
            });
            rows.push({
                visible: true,
                label: "Fastest Reality (real time)",
                value: (function () {
                    try { return TimeSpan.fromMilliseconds(best.realTime || 0).toStringShort(); }
                    catch (e) { return "—"; }
                })(),
                glyphs: previewSet(best.speedSet)
            });

            // Teresa-gated row
            var teresaVisible = false;
            try { teresaVisible = teresaBest.bestRunAM && teresaBest.bestRunAM.gt && teresaBest.bestRunAM.gt(1); }
            catch (e) {}
            if (teresaVisible) {
                var teresaName = "Teresa's";
                try { teresaName = Teresa.possessiveName; } catch (e) {}
                rows.push({
                    visible: true,
                    label: "Highest Antimatter in " + teresaName + " Reality",
                    value: (function () {
                        try { return format(teresaBest.bestRunAM, 2, 2) + " Antimatter"; }
                        catch (e) { return "0 Antimatter"; }
                    })(),
                    glyphs: previewSet(teresaBest.bestAMSet)
                });
            }

            // iM cap row — gated on Currency.imaginaryMachines > 0
            var imVisible = false;
            try { imVisible = Currency.imaginaryMachines.gt(0); } catch (e) {}
            if (imVisible) {
                rows.push({
                    visible: true,
                    label: "Highest Imaginary Machine cap",
                    value: (function () {
                        try { return format(MachineHandler.currentIMCap, 2, 2) + " iM"; }
                        catch (e) { return "0 iM"; }
                    })(),
                    glyphs: previewSet(best.iMCapSet)
                });
            }

            // Lai'tela row — gated on Laitela.isUnlocked
            var laitelaVisible = false;
            try { laitelaVisible = !!Laitela.isUnlocked; } catch (e) {}
            if (laitelaVisible) {
                var laitelaName = "Lai'tela's";
                try { laitelaName = Laitela.displayName; } catch (e) {}
                var fastest = laitelaState.fastestCompletion || 0;
                rows.push({
                    visible: true,
                    label: "Best " + laitelaName + " Destabilization",
                    value: (function () {
                        try {
                            var t = TimeSpan.fromSeconds(fastest).toStringShort();
                            var dimCount = laitelaDim < 0 ? 0 : laitelaDim;
                            var pl = (typeof pluralize === "function")
                                ? pluralize("Dimension", dimCount) : "Dimensions";
                            return t + ", " + dimCount + " " + pl
                                + " (" + formatX(Laitela.realityReward, 2, 2) + " DM)";
                        } catch (e) { return "—"; }
                    })(),
                    glyphs: previewSet(best.laitelaSet)
                });
            }

            return JSON.stringify({ records: rows });
        } catch (e) {
            try { _nativeLog && _nativeLog("[glyph-records] failed: " + e); } catch (_e) {}
            return JSON.stringify({ records: [] });
        }
    };
})();
